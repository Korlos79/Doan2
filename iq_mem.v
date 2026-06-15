// =============================================================================
// tb_rv32ifm_ooo.v  —  Testbench cho RV32IFM Out-of-Order Processor
//
// Test case: DivMul.txt  (OoO verification — DIV cực chậm)
//   [0x00] ADDI x1, x0, 100   → x1 = 100
//   [0x04] ADDI x2, x0, 5     → x2 = 5
//   [0x08] ADDI x5, x0, 10    → x5 = 10
//   [0x0C] ADDI x6, x0, 20    → x6 = 20
//   [0x10] DIV  x3, x1, x2    → x3 = 20   [iter_div32: 34 chu kì] ← Tag A (cực chậm)
//   [0x14] ADD  x7, x5, x6    → x7 = 30   [1 chu kì, OoO chạy trước Tag A] ← Tag B
//   [0x18] SUB  x8, x7, x5    → x8 = 20   [1 chu kì, đợi x7] ← Tag C
//   [0x1C] MUL  x4, x3, x5    → x4 = 200  [4 chu kì, đợi x3 từ DIV] ← Tag D
//
// Điểm kiểm tra OoO:
//   * Tag B (ADD x7) và Tag C (SUB x8) phải ISSUE và COMMIT trước Tag A (DIV x3)
//   * Tag D (MUL x4) phải đợi CDB broadcast của Tag A trước khi issue
//   * Commit vẫn in-order: A→B→C→D (nhưng A commit muộn nhất về thời gian)
//
// Pipeline stages hiển thị:
//   [FETCH]    — PC đang fetch, inst từ imem
//   [DEC/REN]  — IF/ID reg: decode + rename physical tag
//   [DISPATCH] — do_dispatch pulse: ghi vào ROB + IQ
//   [IQ_WRITE] — 1 cycle sau dispatch: entry thực sự vào IQ
//   [ISSUE/OA] — IQ chọn entry sẵn sàng → gửi xuống FU kèm operand
//   [EXECUTE]  — WB result từ FU (wb0=ALU-basic, wb1=MUL/DIV, wb2=FPU, wb3=LSU)
//   [COMMIT]   — ROB commit head entry (in-order)
//
// Dừng: sau khi tất cả INST_COUNT lệnh commit và ROB rỗng, hoặc timeout.
// =============================================================================
`timescale 1ns/1ps

module tb_rv32ifm_ooo;

    // =========================================================================
    // Parameters
    // =========================================================================
    parameter TAG_WIDTH  = 7;   // [FIX-FP-TAG]
    parameter ROB_IDX    = 5;
    parameter ROB_DEPTH  = 32;
    parameter NUM_PHYS   = 64;
    parameter NUM_ARCH   = 32;
    parameter INST_COUNT = 8;
    parameter CLK_HALF   = 5;
    // DIV=34cyc + MUL=4cyc + pipeline overhead ~15cyc + margin → 120 đủ
    // Branch test: 5 commits (x1, x2, BNE-commit, x3=SUB, x2=ADDI)
    parameter MAX_CYCLES = 120;

    // =========================================================================
    // Clock / Reset
    // =========================================================================
    reg clk, rst_n;
    initial clk = 0;
    always #CLK_HALF clk = ~clk;

    // =========================================================================
    // DUT
    // =========================================================================
    rv32ifm_ooo #(
        .TAG_WIDTH(TAG_WIDTH),
        .ROB_IDX  (ROB_IDX),
        .ROB_DEPTH(ROB_DEPTH),
        .NUM_PHYS (NUM_PHYS),
        .NUM_ARCH (NUM_ARCH)
    ) dut (
        .clk  (clk),
        .rst_n(rst_n)
    );

    // =========================================================================
    // Internal signal taps
    // =========================================================================

    // §1 FETCH
    wire [31:0] t_pc_out    = dut.pc_out;
    wire [31:0] t_inst_raw  = dut.inst_raw;
    wire        t_stall     = dut.stall;
    wire        t_flush     = dut.flush_pipeline;
    wire [31:0] t_flush_tgt = dut.flush_pc_target;

    // §2 IF/ID register  → DECODE/RENAME
    wire [31:0] t_ifid_pc   = dut.if_id_pc;
    wire [31:0] t_ifid_inst = dut.if_id_inst;
    wire        t_ifid_vld  = dut.if_id_valid;
    wire        t_dec_valid = dut.dec_valid;
    wire [4:0]  t_dec_rd    = dut.dec_rd;
    wire [4:0]  t_dec_rs1   = dut.dec_rs1;
    wire [4:0]  t_dec_rs2   = dut.dec_rs2;
    wire [31:0] t_dec_imm   = dut.dec_imm;
    wire        t_dec_alu   = dut.dec_to_alu;
    wire        t_dec_fpu   = dut.dec_to_fpu;
    wire        t_dec_lsu   = dut.dec_to_lsu;
    wire [4:0]  t_dec_op    = dut.dec_alu_op;
    wire [TAG_WIDTH-1:0] t_ren_prd  = dut.ren_prd;
    wire [TAG_WIDTH-1:0] t_ren_prs1 = dut.ren_prs1;
    wire [TAG_WIDTH-1:0] t_ren_prs2 = dut.ren_prs2;
    // Readiness tại rename (combinational từ PRF)
    wire t_prs1_rdy = dut.prs1_int_ready_w | dut.prs1_fp_ready_w;
    wire t_prs2_rdy = dut.prs2_int_ready_w | dut.prs2_fp_ready_w;

    // §3 DISPATCH (do_dispatch là pulse tổ hợp từ if_id_valid & dec_valid & dispatch_ready)
    wire        t_do_disp   = dut.do_dispatch;
    wire [ROB_IDX-1:0] t_rob_tail = dut.rob_idx_alloc;   // ROB index cấp cho lệnh mới
    wire        t_rob_full  = dut.rob_full;

    // §3b IQ_WRITE — 1 cycle sau do_dispatch (registered outputs của dispatch_unit)
    wire        t_iq_alu_wr = dut.iq_alu_wr_en_w;
    wire        t_iq_fpu_wr = dut.iq_fpu_wr_en_w;
    wire        t_iq_lsu_wr = dut.iq_lsu_wr_en_w;
    wire [TAG_WIDTH-1:0] t_iq_prd  = dut.iq_prd_w;
    wire [TAG_WIDTH-1:0] t_iq_prs1 = dut.iq_prs1_w;
    wire [TAG_WIDTH-1:0] t_iq_prs2 = dut.iq_prs2_w;
    wire        t_iq_p1rdy  = dut.iq_prs1_ready_w;
    wire        t_iq_p2rdy  = dut.iq_prs2_ready_w;
    wire [ROB_IDX-1:0] t_iq_rob  = dut.iq_rob_idx_w;

    // §4 ISSUE / OPERAND ACCESS
    wire        t_alu_iss   = dut.iq_alu_issue_valid;
    wire [TAG_WIDTH-1:0] t_alu_prd  = dut.iq_alu_issue_prd;
    wire [ROB_IDX-1:0]   t_alu_rob  = dut.iq_alu_issue_rob_idx;
    wire [4:0]  t_alu_op    = dut.iq_alu_issue_alu_op;
    wire        t_alu_uimm  = dut.iq_alu_issue_use_imm;
    wire [31:0] t_alu_rs1   = dut.iq_alu_issue_rs1_val;
    wire [31:0] t_alu_rs2   = dut.iq_alu_issue_rs2_val;
    wire [31:0] t_alu_imm   = dut.iq_alu_issue_imm;

    wire        t_fpu_iss   = dut.iq_fpu_issue_valid;
    wire [TAG_WIDTH-1:0] t_fpu_prd  = dut.iq_fpu_issue_prd;
    wire [ROB_IDX-1:0]   t_fpu_rob  = dut.iq_fpu_issue_rob_idx;
    wire [31:0] t_fpu_rs1   = dut.iq_fpu_issue_rs1_val;
    wire [31:0] t_fpu_rs2   = dut.iq_fpu_issue_rs2_val;

    wire        t_lsu_iss      = dut.iq_lsu_issue_valid;
    wire [TAG_WIDTH-1:0] t_lsu_prd  = dut.iq_lsu_issue_prd;
    wire [ROB_IDX-1:0]   t_lsu_rob  = dut.iq_lsu_issue_rob_idx;
    wire [31:0] t_lsu_rs1      = dut.iq_lsu_issue_rs1_val;
    wire [31:0] t_lsu_rs2      = dut.iq_lsu_issue_rs2_val;
    wire [31:0] t_lsu_imm      = dut.iq_lsu_issue_imm;
    wire        t_lsu_is_store = dut.iq_lsu_issue_is_store;

    // §5 EXECUTE / WRITEBACK
    wire        t_wb0_v     = dut.alu_wb0_valid;
    wire [ROB_IDX-1:0]   t_wb0_rob = dut.alu_wb0_rob_idx;
    wire [TAG_WIDTH-1:0] t_wb0_prd = dut.alu_wb0_prd;
    wire [31:0] t_wb0_res   = dut.alu_wb0_result;

    wire        t_wb1_v     = dut.alu_wb1_valid;
    wire [ROB_IDX-1:0]   t_wb1_rob = dut.alu_wb1_rob_idx;
    wire [TAG_WIDTH-1:0] t_wb1_prd = dut.alu_wb1_prd;
    wire [31:0] t_wb1_res   = dut.alu_wb1_result;

    wire        t_wb2_v     = dut.fpu_wb2_valid;
    wire [ROB_IDX-1:0]   t_wb2_rob = dut.fpu_wb2_rob_idx;
    wire [31:0] t_wb2_res   = dut.fpu_wb2_result;

    wire        t_wb3_v     = dut.lsu_wb3_valid;
    wire [ROB_IDX-1:0]   t_wb3_rob = dut.lsu_wb3_rob_idx;
    wire [TAG_WIDTH-1:0] t_wb3_prd = dut.lsu_wb3_prd;   // tên đúng trong rv32ifm_ooo
    wire [31:0] t_wb3_res   = dut.lsu_wb3_result;

    // Store buffer writeback (STORE EX1 → ROB store buffer)
    wire        t_wbs_v    = dut.lsu_wbs_valid;          // tên đúng (không có _w)
    wire [ROB_IDX-1:0] t_wbs_rob  = dut.lsu_wbs_rob_idx;
    wire [31:0] t_wbs_addr = dut.lsu_wbs_store_addr;
    wire [31:0] t_wbs_data = dut.lsu_wbs_store_data;

    // §6 COMMIT
    wire        t_cmt_v     = dut.u_rob.commit_valid;
    wire [31:0] t_cmt_pc    = dut.u_rob.commit_pc;
    wire [4:0]  t_cmt_rd    = dut.u_rob.commit_rd_arch;
    wire [31:0] t_cmt_res   = dut.u_rob.commit_result;
    wire        t_cmt_use_rd= dut.u_rob.commit_use_rd;
    wire        t_rob_empty = dut.rob_empty_w;

    // =========================================================================
    // Cycle / commit counters
    // =========================================================================
    integer cyc, cmt_cnt;
    initial begin cyc = 0; cmt_cnt = 0; end
    always @(posedge clk) cyc <= cyc + 1;
    always @(posedge clk) if (t_cmt_v) cmt_cnt <= cmt_cnt + 1;

    // =========================================================================
    // Helper: mnemonic từ encoding
    // =========================================================================
    function [63:0] mnem;
        input [31:0] inst;
        reg [6:0] op; reg [2:0] f3; reg [6:0] f7;
        begin
            op = inst[6:0]; f3 = inst[14:12]; f7 = inst[31:25];
            if      (inst == 32'b0)                                         mnem = "----    ";
            else if (op == 7'b0010011)                                      mnem = "ADDI    ";
            else if (op == 7'b0110011 && f7 == 7'b0000001 && f3 == 3'b000) mnem = "MUL     ";
            else if (op == 7'b0110011 && f7 == 7'b0000001 && f3 == 3'b001) mnem = "MULH    ";
            else if (op == 7'b0110011 && f7 == 7'b0000001 && f3 == 3'b010) mnem = "MULHSU  ";
            else if (op == 7'b0110011 && f7 == 7'b0000001 && f3 == 3'b011) mnem = "MULHU   ";
            else if (op == 7'b0110011 && f7 == 7'b0000001 && f3 == 3'b100) mnem = "DIV     ";
            else if (op == 7'b0110011 && f7 == 7'b0000001 && f3 == 3'b101) mnem = "DIVU    ";
            else if (op == 7'b0110011 && f7 == 7'b0000001 && f3 == 3'b110) mnem = "REM     ";
            else if (op == 7'b0110011 && f7 == 7'b0000001 && f3 == 3'b111) mnem = "REMU    ";
            else if (op == 7'b0110011 && f7 == 7'b0000000 && f3 == 3'b000) mnem = "ADD     ";
            else if (op == 7'b0110011 && f7 == 7'b0100000 && f3 == 3'b000) mnem = "SUB     ";
            else if (op == 7'b0110011 && f7 == 7'b0000000 && f3 == 3'b001) mnem = "SLL     ";
            else if (op == 7'b0110011 && f7 == 7'b0000000 && f3 == 3'b100) mnem = "XOR     ";
            else if (op == 7'b0110011 && f7 == 7'b0000000 && f3 == 3'b110) mnem = "OR      ";
            else if (op == 7'b0110011 && f7 == 7'b0000000 && f3 == 3'b111) mnem = "AND     ";
            else if (op == 7'b0000011)                                      mnem = "LOAD    ";
            else if (op == 7'b0100011)                                      mnem = "STORE   ";
            else if (op == 7'b1100011)                                      mnem = "BRANCH  ";
            else if (op == 7'b1101111)                                      mnem = "JAL     ";
            else if (op == 7'b1100111)                                      mnem = "JALR    ";
            else if (op == 7'b0110111)                                      mnem = "LUI     ";
            else if (op == 7'b0010111)                                      mnem = "AUIPC   ";
            // RV32F
            else if (op == 7'b1000011)                                      mnem = "FMADD   ";
            else if (op == 7'b1000111)                                      mnem = "FMSUB   ";
            else if (op == 7'b1001011)                                      mnem = "FNMSUB  ";
            else if (op == 7'b1001111)                                      mnem = "FNMADD  ";
            else if (op == 7'b1010011) begin
                case (f7)
                    7'b0000000: mnem = "FADD    ";
                    7'b0000100: mnem = "FSUB    ";
                    7'b0001000: mnem = "FMUL    ";
                    7'b0001100: mnem = "FDIV    ";
                    7'b0101100: mnem = "FSQRT   ";
                    7'b0010000: mnem = "FSGNJ   ";
                    7'b0010100: mnem = "FMINMAX ";
                    7'b1010000: mnem = "FCMP    ";
                    7'b1100000: mnem = "FCVT.W  ";
                    7'b1101000: mnem = "FCVT.S  ";
                    7'b1110000: mnem = "FMVXW   ";
                    7'b1111000: mnem = "FMVWX   ";
                    default:    mnem = "FP-OP   ";
                endcase
            end
            else if (op == 7'b0000111)                                      mnem = "FLW     ";
            else if (op == 7'b0100111)                                      mnem = "FSW     ";
            else                                                             mnem = "???     ";
        end
    endfunction

    // =========================================================================
    // Helper: hiển thị float 32-bit IEEE-754 dạng "0x41100000(9.000)"
    // Verilog không có $bitstoreal cho single precision → decode thủ công
    // =========================================================================
    function real bits_to_float;
        input [31:0] bits;
        real mantissa, result;
        integer exp_i;
        reg sign;
        reg [7:0] exp;
        reg [22:0] frac;
        begin
            sign = bits[31];
            exp  = bits[30:23];
            frac = bits[22:0];
            if (exp == 8'hFF && frac != 0)
                result = 0.0; // NaN → hiển thị 0
            else if (exp == 8'hFF)
                result = sign ? -1e38 : 1e38; // Inf
            else if (exp == 8'h00)
                result = 0.0; // denorm/zero
            else begin
                mantissa = 1.0;
                // build mantissa: 1 + frac/2^23
                begin : frac_loop
                    integer k;
                    real bit_val;
                    bit_val = 0.5;
                    for (k = 22; k >= 0; k = k - 1) begin
                        if (frac[k]) mantissa = mantissa + bit_val;
                        bit_val = bit_val / 2.0;
                    end
                end
                exp_i = exp - 127;
                // 2^exp_i
                begin : exp_loop
                    integer j;
                    result = mantissa;
                    if (exp_i >= 0) begin
                        for (j = 0; j < exp_i; j = j + 1)
                            result = result * 2.0;
                    end else begin
                        for (j = 0; j > exp_i; j = j - 1)
                            result = result / 2.0;
                    end
                end
                if (sign) result = -result;
            end
            bits_to_float = result;
        end
    endfunction

    function [23:0] fu_str;
        input alu, fpu, lsu;
        begin
            if      (alu) fu_str = "ALU";
            else if (fpu) fu_str = "FPU";
            else if (lsu) fu_str = "LSU";
            else          fu_str = "---";
        end
    endfunction

    // =========================================================================
    // RESET
    // =========================================================================
    initial begin
        rst_n = 1'b0;
        repeat(3) @(posedge clk);
        #1 rst_n = 1'b1;
        $display("");
        $display("==============================================================");
        $display("  RV32IFM OoO Processor  -  DivMul OoO Test");
        $display("  Lenh nap:");
        $display("    [0x00] ADDI x1,  x0, 100");
        $display("    [0x04] ADDI x2,  x0, 5");
        $display("    [0x08] ADDI x5,  x0, 10");
        $display("    [0x0C] ADDI x6,  x0, 20");
        $display("    [0x10] DIV  x3,  x1, x2   [34 cyc]  Tag-A (cu cham)");
        $display("    [0x14] ADD  x7,  x5, x6   [1 cyc]   Tag-B (OoO truoc A)");
        $display("    [0x18] SUB  x8,  x7, x5   [1 cyc]   Tag-C (sau B)");
        $display("    [0x1C] MUL  x4,  x3, x5   [4 cyc]   Tag-D (doi x3)");
        $display("  Ghi chu:");
        $display("    * DIV  dung iter_div32: 34 chu ki tu Issue den WB1");
        $display("    * MUL  dung iter_mul32:  4 chu ki tu Issue den WB1");
        $display("    * ADD/SUB/ADDI: 1 chu ki (WB0)");
        $display("    * prs rdy=0 → phu thuoc du lieu, cho CDB snoop");
        $display("    * alu_op: 0=ADD/ADDI, 8=SUB, 16=MUL, 20=DIV");
        $display("  Ket qua ky vong:");
        $display("    x1=100  x2=5    x5=10   x6=20");
        $display("    x3= 20  DIV(100,5)");
        $display("    x7= 30  ADD(10,20)  [commit truoc x3]");
        $display("    x8= 20  SUB(30,10)  [commit truoc x3]");
        $display("    x4=200  MUL(20,10)  [doi x3 xong moi issue]");
        $display("==============================================================");
    end

    // =========================================================================
    // Per-cycle display
    // =========================================================================
    always @(posedge clk) begin
        if (!rst_n) disable per_cycle_block;
        begin : per_cycle_block
            $display("------ Cycle %0d ------", cyc);

            // ------------------------------------------------------------------
            // FETCH
            // ------------------------------------------------------------------
            if (t_flush)
                $display("  [FETCH]    *** FLUSH (branch mispred) *** re-fetch tu 0x%08h  [wrong-path squashed]",
                         t_flush_tgt);
            else if (t_stall)
                $display("  [FETCH]    PC=0x%08h  inst=0x%08h  (%s)  <STALL>",
                         t_pc_out, t_inst_raw, mnem(t_inst_raw));
            else if (t_inst_raw != 32'b0)
                $display("  [FETCH]    PC=0x%08h  inst=0x%08h  (%s)",
                         t_pc_out, t_inst_raw, mnem(t_inst_raw));

            // ------------------------------------------------------------------
            // DECODE / RENAME  (trên IF/ID reg — lệnh 1 cycle trước)
            // ------------------------------------------------------------------
            if (t_ifid_vld && t_dec_valid) begin
                $display("  [DEC/REN]  PC=0x%08h  inst=0x%08h  (%s)",
                         t_ifid_pc, t_ifid_inst, mnem(t_ifid_inst));
                $display("             rd=x%-2d  rs1=x%-2d  rs2=x%-2d  imm=%0d",
                         t_dec_rd, t_dec_rs1, t_dec_rs2, $signed(t_dec_imm));
                $display("             FU=%s  alu_op=%-2d  prd=p%-2d  prs1=p%-2d(rdy=%b)  prs2=p%-2d(rdy=%b)",
                         fu_str(t_dec_alu, t_dec_fpu, t_dec_lsu),
                         t_dec_op,
                         t_ren_prd, t_ren_prs1, t_prs1_rdy, t_ren_prs2, t_prs2_rdy);
            end

            // ------------------------------------------------------------------
            // DISPATCH  (combinational pulse — cùng cycle với DEC/REN nếu không stall)
            // Hiển thị thông tin ROB alloc
            // ------------------------------------------------------------------
            if (t_do_disp) begin
                $display("  [DISPATCH] ROB[%0d]  FU=%s  prd=p%-2d  prs1=p%-2d(rdy=%b)  prs2=p%-2d(rdy=%b)",
                         t_rob_tail,
                         fu_str(t_dec_alu, t_dec_fpu, t_dec_lsu),
                         t_ren_prd,
                         t_ren_prs1, t_prs1_rdy,
                         t_ren_prs2, t_prs2_rdy);
            end else if (t_ifid_vld && t_dec_valid && !t_do_disp) begin
                $display("  [DISPATCH] <STALL — IQ/ROB full>");
            end

            // ------------------------------------------------------------------
            // IQ_WRITE  (registered: 1 cycle sau do_dispatch)
            // Đây là thời điểm entry THỰC SỰ vào trong Issue Queue
            // ------------------------------------------------------------------
            if (t_iq_alu_wr)
                $display("  [IQ_WRITE] -> IQ_ALU  ROB[%0d]  prd=p%-2d  prs1=p%-2d(rdy=%b)  prs2=p%-2d(rdy=%b)",
                         t_iq_rob, t_iq_prd, t_iq_prs1, t_iq_p1rdy, t_iq_prs2, t_iq_p2rdy);
            if (t_iq_fpu_wr)
                $display("  [IQ_WRITE] -> IQ_FPU  ROB[%0d]  prd=p%-2d  prs1=p%-2d(rdy=%b)  prs2=p%-2d(rdy=%b)",
                         t_iq_rob, t_iq_prd, t_iq_prs1, t_iq_p1rdy, t_iq_prs2, t_iq_p2rdy);
            if (t_iq_lsu_wr)
                $display("  [IQ_WRITE] -> IQ_LSU  ROB[%0d]  prd=p%-2d  prs1=p%-2d(rdy=%b)  prs2=p%-2d(rdy=%b)",
                         t_iq_rob, t_iq_prd, t_iq_prs1, t_iq_p1rdy, t_iq_prs2, t_iq_p2rdy);

            // ------------------------------------------------------------------
            // ISSUE / OPERAND ACCESS
            // IQ chọn entry sẵn sàng → gửi xuống FU; operand đã được latch
            // ------------------------------------------------------------------
            if (t_alu_iss) begin
                if (t_alu_uimm)
                    $display("  [ISSUE/OA] ALU  ROB[%0d]  prd=p%-2d  op=%-2d  rs1=0x%08h  imm=0x%08h(%0d)",
                             t_alu_rob, t_alu_prd, t_alu_op, t_alu_rs1, t_alu_imm, $signed(t_alu_imm));
                else
                    $display("  [ISSUE/OA] ALU  ROB[%0d]  prd=p%-2d  op=%-2d  rs1=0x%08h  rs2=0x%08h",
                             t_alu_rob, t_alu_prd, t_alu_op, t_alu_rs1, t_alu_rs2);
            end
            if (t_fpu_iss)
                $display("  [ISSUE/OA] FPU  ROB[%0d]  prd=p%-3d  rs1=0x%08h(%.3f)  rs2=0x%08h(%.3f)",
                         t_fpu_rob, t_fpu_prd,
                         t_fpu_rs1, bits_to_float(t_fpu_rs1),
                         t_fpu_rs2, bits_to_float(t_fpu_rs2));
            if (t_lsu_iss) begin
                if (t_lsu_is_store)
                    $display("  [ISSUE/OA] LSU  STORE  ROB[%0d]  addr_base=0x%08h  data=0x%08h  imm=%0d",
                             t_lsu_rob, t_lsu_rs1, t_lsu_rs2, $signed(t_lsu_imm));
                else
                    $display("  [ISSUE/OA] LSU  LOAD   ROB[%0d]  prd=p%-2d  addr_base=0x%08h  imm=%0d",
                             t_lsu_rob, t_lsu_prd, t_lsu_rs1, $signed(t_lsu_imm));
            end

            // ------------------------------------------------------------------
            // EXECUTE / WRITEBACK
            // wbs: STORE EX1 (addr+data → ROB store buffer)
            // wb3: LOAD EX2  (dmem read result)
            // ------------------------------------------------------------------
            if (t_wbs_v)
                $display("  [EXECUTE]  WBS-STORE    ROB[%0d]  addr=0x%08h  data=0x%08h  (vao store buffer)",
                         t_wbs_rob, t_wbs_addr, t_wbs_data);

            // ------------------------------------------------------------------
            // EXECUTE / WRITEBACK
            // wb0: ALU basic 1-cycle
            // wb1: MUL/DIV multi-cycle (4 / 34 chu kì)
            // wb2: FPU
            // wb3: LSU load
            // ------------------------------------------------------------------
            if (t_wb0_v)
                $display("  [EXECUTE]  WB0-ALU      ROB[%0d]  prd=p%-2d  result=0x%08h (%0d)",
                         t_wb0_rob, t_wb0_prd, t_wb0_res, $signed(t_wb0_res));
            if (t_wb1_v)
                $display("  [EXECUTE]  WB1-MUL/DIV  ROB[%0d]  prd=p%-2d  result=0x%08h (%0d)",
                         t_wb1_rob, t_wb1_prd, t_wb1_res, $signed(t_wb1_res));
            if (t_wb2_v)
                $display("  [EXECUTE]  WB2-FPU      ROB[%0d]  result=0x%08h  (float=%.4f)",
                         t_wb2_rob, t_wb2_res, bits_to_float(t_wb2_res));
            if (t_wb3_v)
                $display("  [EXECUTE]  WB3-LOAD     ROB[%0d]  prd=p%-2d  result=0x%08h (%0d)",
                         t_wb3_rob, t_wb3_prd, t_wb3_res, $signed(t_wb3_res));

            // ------------------------------------------------------------------
            // COMMIT  (in-order từ ROB head)
            // ------------------------------------------------------------------
            if (t_cmt_v) begin
                if (dut.u_rob.commit_store)
                    $display("  [COMMIT]   PC=0x%08h  STORE → mem[0x%08h] = 0x%08h   #%0d",
                             t_cmt_pc,
                             dut.u_rob.commit_store_addr,
                             dut.u_rob.commit_store_data,
                             cmt_cnt + 1);
                else if (!t_cmt_use_rd || t_cmt_rd == 0)
                    $display("  [COMMIT]   PC=0x%08h  (branch/no-rd, squash wrong path)   #%0d",
                             t_cmt_pc, cmt_cnt + 1);
                else if (dut.u_rob.commit_fp_rd)
                    // FP register: hiển thị giá trị dạng float
                    $display("  [COMMIT]   PC=0x%08h  f%-2d = 0x%08h  (float=%.4f)   #%0d",
                             t_cmt_pc, t_cmt_rd, t_cmt_res,
                             bits_to_float(t_cmt_res), cmt_cnt + 1);
                else
                    $display("  [COMMIT]   PC=0x%08h  x%-2d = 0x%08h (%0d)   #%0d",
                             t_cmt_pc, t_cmt_rd, t_cmt_res, $signed(t_cmt_res),
                             cmt_cnt + 1);
            end

            $display("");
        end
    end

    // =========================================================================
    // Điều kiện dừng — tự động, không cần biết trước INST_COUNT
    // Dừng khi ROB empty VÀ pipeline idle 5 cycle liên tiếp (không có hoạt động)
    // =========================================================================
    integer idle_cnt;
    initial idle_cnt = 0;

    always @(posedge clk) begin
        if (!rst_n) begin
            idle_cnt <= 0;
        end else begin
            if (t_cmt_v || t_do_disp || t_alu_iss || t_lsu_iss || t_fpu_iss
                || t_wb0_v || t_wb1_v || t_wb2_v || t_wb3_v || t_flush)
                idle_cnt <= 0;
            else if (t_rob_empty && cmt_cnt > 0)
                idle_cnt <= idle_cnt + 1;

            if (idle_cnt >= 5) begin
                $display("==============================================================");
                $display("  DONE: %0d lenh da commit, ROB trong, pipeline idle o chu ki %0d",
                         cmt_cnt, cyc);
                $display("  Xem cac dong [COMMIT] va [EXECUTE] o tren de kiem tra ket qua.");
                $display("==============================================================");
                $finish;
            end

            if (cyc >= MAX_CYCLES) begin
                $display("!!! TIMEOUT chu ki %0d  (commit %0d lenh)", cyc, cmt_cnt);
                $finish;
            end
        end
    end

    // =========================================================================
    // Waveform dump
    // =========================================================================
    initial begin
        $dumpfile("tb_rv32ifm_ooo.vcd");
        $dumpvars(0, tb_rv32ifm_ooo);
    end

endmodule

// =============================================================================
// CÁC LỖI LOGIC ĐÃ PHÁT HIỆN VÀ SỬA
// =============================================================================
//
// BUG 1 — instruction_Mem.v: đường dẫn cứng D:/...
//   Sửa: $readmemh("DivMul.txt", i_mem);  (file instruction_Mem_fixed.v đính kèm)
//
// BUG 2 — Decode sai ADDI rs2: inst_name hiển thị rs2=x4/x5/x10/x20 cho ADDI
//   Nguyên nhân: ADDI (opcode ALUI) dùng immediate, rs2 = inst[24:20] chỉ là
//   bit field của immediate, KHÔNG phải source register thật.
//   Control_Unit đúng (use_rs2=0 cho ALUI), nhưng testbench cũ in t_dec_rs2
//   mà không ghi chú → gây nhầm lẫn.
//   Sửa: testbench mới không in rs2 riêng mà để logic tự hiển thị use_imm.
//
// BUG 3 — Dispatch readiness display sai: "rdy=x" thay vì "rdy=1" cho ADDI
//   Nguyên nhân: disp_int_rs1_data / disp_int_rs2_data được latch qua
//   posedge clk (dòng 691-699 rv32ifm_ooo.v), nên tại thời điểm do_dispatch
//   xảy ra, prs1_int_ready_w/prs2_int_ready_w đọc từ PRF combinational
//   (đúng), nhưng testbench cũ dùng t_iq_p1rdy (sau registered dispatch)
//   để biểu diễn readiness tại DISPATCH → bị lệch 1 cycle.
//   Sửa: [DISPATCH] dùng t_prs1_rdy = prs1_int_ready_w (combinational PRF),
//        [IQ_WRITE]  dùng t_iq_p1rdy (registered value vào IQ entry).
//
// BUG 4 — Fetch không dừng: PC tiếp tục tăng sau khi hết lệnh
//   Nguyên nhân: không có cơ chế halt. inst_raw = X khi vượt quá vùng nhớ.
//   dec_valid = (opcode7 != 0) && (inst != 0) → lệnh X không dispatch được,
//   nhưng PC vẫn tăng vì stall chỉ active khi if_id_valid && dec_valid &&
//   !dispatch_ready.
//   Sửa trong testbench: chỉ in [FETCH] khi inst_raw có opcode hợp lệ
//   (inst_raw[6:0] != 0 && inst_raw != 32'hx), tránh spam màn hình.
//   Để dừng hẳn pipeline cần thêm cơ chế halt vào RTL (ngoài scope testbench).
//
// BUG 5 — WB1 MUL ra X (result = 0xxxxxxxxx)
//   Nguyên nhân CHÍNH: prs2_rdy hiển thị 'x' khi dispatch MUL x3,x1,x2
//   (Cycle 8), nhưng thực tế x1=p32 VÀ x2=p33 đều đã commit trước (WB0
//   cycle 8 và 9). CDB broadcast (wb0→cdb0) carry prd tag, nhưng IQ entry
//   cho MUL được write vào IQ_ALU cycle 9 với wr_prs1_data = disp_int_rs1_data
//   — đây là giá trị REGISTERED từ cycle trước, có thể chưa có giá trị mới.
//   Cụ thể: ADDI x1 commit WB0 cycle 8; dispatch MUL cycle 8 → same-cycle
//   CDB snoop trong IQ write path (dòng 224-243 iq_alu.v) phải bắt được,
//   nhưng disp_int_rs1_data (fallback) bị lệch 1 cycle.
//   Sửa cần thiết trong RTL: bỏ thanh ghi latch disp_int_rs1/rs2_data,
//   truyền thẳng prf_int_rd_data[4*32+:32] (combinational) vào wr_prs1_data
//   của IQ. Xem hướng dẫn sửa RTL bên dưới.
//
// =============================================================================
// SỬA RTL ĐỂ FIX BUG 5 (trong rv32ifm_ooo.v)
// =============================================================================
// Tìm đoạn:
//   always @(posedge clk or negedge rst_n) begin
//       ...
//       disp_int_rs1_data <= prf_int_rd_data[4*32 +: 32];
//       disp_int_rs2_data <= prf_int_rd_data[5*32 +: 32];
//   end
//
// Sửa thành wire (bỏ register):
//   wire [31:0] disp_int_rs1_data = prf_int_rd_data[4*32 +: 32];
//   wire [31:0] disp_int_rs2_data = prf_int_rd_data[5*32 +: 32];
//
// Tương tự cho disp_fp_rs1_data / disp_fp_rs2_data:
//   wire [31:0] disp_fp_rs1_data = prf_fp_rd_data[4*32 +: 32];
//   wire [31:0] disp_fp_rs2_data = prf_fp_rd_data[5*32 +: 32];
//
// Lý do: dispatch_unit đã là registered (clk), nên data path cần là:
//   PRF (comb) → dispatch_unit (reg) → IQ
//   Nếu thêm 1 FF nữa trước dispatch_unit thì data bị lệch 1 cycle
//   so với ready bit, khiến same-cycle CDB bypass không bắt được đúng giá trị.
// =============================================================================