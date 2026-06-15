// =============================================================================
// dispatch.v  —  Dispatch Stage
//
// Nhận lệnh đã Rename và phân phối vào:
//   • ROB (alloc entry)
//   • Issue Queue phù hợp: IQ_ALU, IQ_FPU, IQ_LSU
//
// Backpressure: stall nếu IQ đích đầy hoặc ROB đầy
// =============================================================================

module dispatch_unit #(
    parameter TAG_WIDTH = 6,
    parameter ROB_IDX   = 5
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        flush,

    // -------------------------------------------------------------------------
    // Từ Rename
    // -------------------------------------------------------------------------
    input  wire                  ren_valid,
    output wire                  dispatch_ready,     // Backpressure → Rename

    input  wire [4:0]            ren_rd,
    input  wire [4:0]            ren_rs1,
    input  wire [4:0]            ren_rs2,
    input  wire [4:0]            ren_rs3,
    input  wire [TAG_WIDTH-1:0]  ren_prd,
    input  wire [TAG_WIDTH-1:0]  ren_prs1,
    input  wire [TAG_WIDTH-1:0]  ren_prs2,
    input  wire [TAG_WIDTH-1:0]  ren_prs3,
    input  wire [TAG_WIDTH-1:0]  ren_old_prd,
    input  wire [31:0]           ren_imm,
    input  wire [31:0]           ren_pc,
    input  wire                  ren_use_rs1,
    input  wire                  ren_use_rs2,
    input  wire                  ren_use_rs3,
    input  wire                  ren_use_rd,
    input  wire                  ren_fp_rs1,
    input  wire                  ren_fp_rs2,
    input  wire                  ren_fp_rs3,
    input  wire                  ren_fp_rd,
    input  wire                  ren_to_alu,
    input  wire                  ren_to_fpu,
    input  wire                  ren_to_lsu,
    input  wire [4:0]            ren_alu_op,
    input  wire [4:0]            ren_fpu_op,
    input  wire [2:0]            ren_lsu_op,
    input  wire                  ren_is_branch,
    input  wire                  ren_is_jal,
    input  wire                  ren_is_jalr,
    input  wire                  ren_is_lui,
    input  wire                  ren_is_auipc,
    input  wire                  ren_is_load,
    input  wire                  ren_is_store,
    input  wire                  ren_is_fp_load,
    input  wire                  ren_is_fp_store,
    input  wire [2:0]            ren_branch_op,

    // -------------------------------------------------------------------------
    // ROB interface
    // -------------------------------------------------------------------------
    output wire                  rob_alloc_valid,
    output wire [31:0]           rob_alloc_pc,
    output wire [4:0]            rob_alloc_rd_arch,
    output wire [TAG_WIDTH-1:0]  rob_alloc_prd,
    output wire [TAG_WIDTH-1:0]  rob_alloc_old_prd,
    output wire                  rob_alloc_fp_rd,
    output wire                  rob_alloc_is_branch,
    // [FIX-JAL/JALR]
    output wire                  rob_alloc_is_jump,
    output wire [31:0]           rob_alloc_jump_rd_val,
    output wire                  rob_alloc_is_store,
    output wire                  rob_alloc_use_rd,
    input  wire [ROB_IDX-1:0]   rob_idx,
    input  wire                  rob_full,

    // -------------------------------------------------------------------------
    // Issue Queue interfaces (to IQ_ALU / IQ_FPU / IQ_LSU)
    // Mỗi IQ có 1 cổng write
    // -------------------------------------------------------------------------
    // Common IQ entry fields:
    output reg                   iq_alu_wr_en,
    output reg                   iq_fpu_wr_en,
    output reg                   iq_lsu_wr_en,

    // IQ entry payload (dùng chung signal, mỗi IQ chỉ nhận khi wr_en của nó)
    output reg  [TAG_WIDTH-1:0]  iq_prd,
    output reg  [TAG_WIDTH-1:0]  iq_prs1,
    output reg  [TAG_WIDTH-1:0]  iq_prs2,
    output reg  [TAG_WIDTH-1:0]  iq_prs3,
    output reg                   iq_prs1_ready,
    output reg                   iq_prs2_ready,
    output reg                   iq_prs3_ready,
    output reg  [31:0]           iq_imm,
    output reg  [31:0]           iq_pc,
    output reg  [4:0]            iq_alu_op,
    output reg  [4:0]            iq_fpu_op,
    output reg  [2:0]            iq_lsu_op,
    output reg  [ROB_IDX-1:0]   iq_rob_idx,
    output reg                   iq_use_imm,    // Lệnh dùng imm thay rs2
    output reg                   iq_is_branch,
    output reg                   iq_is_jal,
    output reg                   iq_is_jalr,
    output reg                   iq_is_lui,
    output reg                   iq_is_auipc,
    output reg                   iq_is_load,
    output reg                   iq_is_store,
    output reg                   iq_is_fp_load,
    output reg                   iq_is_fp_store,
    output reg  [2:0]            iq_branch_op,
    output reg                   iq_fp_rd,
    output reg                   iq_fp_rs1,
    output reg                   iq_fp_rs2,

    // Backpressure từ IQ
    input  wire                  iq_alu_full,
    input  wire                  iq_fpu_full,
    input  wire                  iq_lsu_full,

    // PRF ready bits (để kiểm tra readiness tại dispatch)
    // PRF_Int và PRF_Float đều expose ready[]
    input  wire [TAG_WIDTH-1:0]  prf_int_ready,  // ready bit của PRF Int (dạng index)
    // Đơn giản hóa: dùng 1D wire indexed
    // Thực tế nên là input wire [NUM_PHYS-1:0] prf_int_ready_vec
    // Ở đây truyền 2 flag ready từ PRF
    input  wire                  prs1_int_ready_in,
    input  wire                  prs1_fp_ready_in,
    input  wire                  prs2_int_ready_in,
    input  wire                  prs2_fp_ready_in,
    input  wire                  prs3_fp_ready_in
);

    // =========================================================================
    // Backpressure
    // =========================================================================
    wire target_iq_full = (ren_to_alu && iq_alu_full) ||
                          (ren_to_fpu && iq_fpu_full) ||
                          (ren_to_lsu && iq_lsu_full);

    assign dispatch_ready = !target_iq_full && !rob_full;

    wire do_dispatch = ren_valid && dispatch_ready;

    // =========================================================================
    // ROB alloc
    // =========================================================================
    // [FIX-9] rob_alloc_* outputs được drive từ dispatch_unit.
    // Top-level rv32ifm_ooo phải nối rob_alloc_valid → ROB.alloc_valid,
    // KHÔNG dùng riêng do_dispatch để nối thẳng vào ROB, tránh double-drive.
    assign rob_alloc_valid     = do_dispatch;
    assign rob_alloc_pc        = ren_pc;
    assign rob_alloc_rd_arch   = ren_rd;
    assign rob_alloc_prd       = ren_prd;
    assign rob_alloc_old_prd   = ren_old_prd;
    assign rob_alloc_fp_rd     = ren_fp_rd;
    assign rob_alloc_is_branch   = ren_is_branch;
    assign rob_alloc_is_store    = ren_is_store | ren_is_fp_store;
    assign rob_alloc_use_rd      = ren_use_rd;
    // [FIX-JAL/JALR]
    assign rob_alloc_is_jump     = ren_is_jal | ren_is_jalr;
    assign rob_alloc_jump_rd_val = ren_pc + 32'd4;

    // =========================================================================
    // Readiness check
    // rs1/rs2/rs3 ready nếu:
    //   (a) không dùng nguồn này, hoặc
    //   (b) PRF đã có giá trị (ready bit = 1)
    // =========================================================================
    wire prs1_ready = !ren_use_rs1 ||
                      (ren_fp_rs1 ? prs1_fp_ready_in : prs1_int_ready_in);
    wire prs2_ready = !ren_use_rs2 ||
                      (ren_fp_rs2 ? prs2_fp_ready_in : prs2_int_ready_in);
    wire prs3_ready = !ren_use_rs3 || prs3_fp_ready_in;

    // Lệnh dùng immediate thay rs2?
    wire use_imm = ren_is_lui | ren_is_auipc | ren_is_jal | ren_is_jalr |
                   ren_is_load | ren_is_fp_load |
                   (ren_to_alu && !ren_is_branch && ren_use_rs1 && !ren_use_rs2);

    // =========================================================================
    // IQ write
    // =========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            iq_alu_wr_en <= 1'b0;
            iq_fpu_wr_en <= 1'b0;
            iq_lsu_wr_en <= 1'b0;
        end else if (flush) begin
            iq_alu_wr_en <= 1'b0;
            iq_fpu_wr_en <= 1'b0;
            iq_lsu_wr_en <= 1'b0;
        end else begin
            iq_alu_wr_en <= do_dispatch && ren_to_alu;
            iq_fpu_wr_en <= do_dispatch && ren_to_fpu && !ren_is_fp_load && !ren_is_fp_store;
            iq_lsu_wr_en <= do_dispatch && ren_to_lsu;

            if (do_dispatch) begin
                iq_prd        <= ren_prd;
                iq_prs1       <= ren_prs1;
                iq_prs2       <= ren_prs2;
                iq_prs3       <= ren_prs3;
                iq_prs1_ready <= prs1_ready;
                iq_prs2_ready <= prs2_ready;
                iq_prs3_ready <= prs3_ready;
                iq_imm        <= ren_imm;
                iq_pc         <= ren_pc;
                iq_alu_op     <= ren_alu_op;
                iq_fpu_op     <= ren_fpu_op;
                iq_lsu_op     <= ren_lsu_op;
                iq_rob_idx    <= rob_idx;
                iq_use_imm    <= use_imm;
                iq_is_branch  <= ren_is_branch;
                iq_is_jal     <= ren_is_jal;
                iq_is_jalr    <= ren_is_jalr;
                iq_is_lui     <= ren_is_lui;
                iq_is_auipc   <= ren_is_auipc;
                iq_is_load    <= ren_is_load;
                iq_is_store   <= ren_is_store;
                iq_is_fp_load <= ren_is_fp_load;
                iq_is_fp_store<= ren_is_fp_store;
                iq_branch_op  <= ren_branch_op;
                iq_fp_rd      <= ren_fp_rd;
                iq_fp_rs1     <= ren_fp_rs1;
                iq_fp_rs2     <= ren_fp_rs2;
            end
        end
    end

endmodule