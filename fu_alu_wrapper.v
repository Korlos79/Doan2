// =============================================================================
// fu_alu_wrapper.v  —  ALU Execute Unit (Execute Stage wrapper)
//
// Chu kỳ:
//   • Lệnh cơ bản (ADD/SUB/...): 1 chu kỳ (wb0_valid cycle sau issue)
//   • MUL: 4 chu kỳ (iter_mul32), DIV: 34 chu kỳ (iter_div32)
//   • Branch/JAL/JALR/LUI/AUIPC: 1 chu kỳ (wb0_valid)
//
// [FIX-JALR] jalr_target = (rs1_val + imm) & ~32'h1
//   Trước đây dùng bit-split sai: {rs1[31:1]+imm[31:1], 1'b0}
//   Đúng chuẩn RISC-V: cộng 32-bit đầy đủ rồi clear bit 0.
// =============================================================================

module fu_alu_wrapper #(
    parameter TAG_WIDTH = 7,   // [FIX-FP-TAG] 7-bit,
    parameter ROB_IDX   = 5
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        flush,

    // -------------------------------------------------------------------------
    // Từ IQ_ALU (Issue)
    // -------------------------------------------------------------------------
    input  wire                  issue_valid,
    input  wire [TAG_WIDTH-1:0]  issue_prd,
    input  wire [31:0]           issue_rs1_val,
    input  wire [31:0]           issue_rs2_val,
    input  wire [31:0]           issue_imm,
    input  wire [31:0]           issue_pc,
    input  wire [4:0]            issue_alu_op,
    input  wire [ROB_IDX-1:0]   issue_rob_idx,
    input  wire                  issue_use_imm,
    input  wire                  issue_is_branch,
    input  wire                  issue_is_jal,
    input  wire                  issue_is_jalr,
    input  wire                  issue_is_lui,
    input  wire                  issue_is_auipc,
    input  wire [2:0]            issue_branch_op,

    // -------------------------------------------------------------------------
    // Writeback Port 0: basic (1-cycle)
    // -------------------------------------------------------------------------
    output reg                   wb0_valid,
    output reg  [ROB_IDX-1:0]   wb0_rob_idx,
    output reg  [31:0]           wb0_result,
    output reg                   wb0_exc,
    output reg  [TAG_WIDTH-1:0]  wb0_prd,
    // [BP-UPDATE] Branch predictor update signals
    output reg  [31:0]           wb0_pc,          // PC of branch/jump
    output reg                   wb0_is_branch,   // was conditional branch

    // -------------------------------------------------------------------------
    // Writeback Port 1: mul/div (multi-cycle, tag-based)
    // -------------------------------------------------------------------------
    output wire                  wb1_valid,
    output wire [ROB_IDX-1:0]   wb1_rob_idx,
    output wire [31:0]           wb1_result,
    output wire                  wb1_exc,
    output wire [TAG_WIDTH-1:0]  wb1_prd
);

    // =========================================================================
    // Operand select
    // [FIX-MULDIV-RETRIGGER] Gate với issue_valid:
    // issue_alu_op là registered reg trong iq_alu — giữ giá trị cũ khi
    // issue_valid=0. Nếu không gate, is_mul/is_div trong alu.v sẽ assert liên
    // tục → iter_mul32/iter_div32 re-start mỗi cycle → kết quả sai.
    // Tương tự op_a/op_b: gate để FU nhận 0 thay vì stale data.
    // =========================================================================
    wire [31:0] op_a = !issue_valid         ? 32'd0       :
                       issue_is_auipc       ? issue_pc    :
                       issue_is_lui         ? 32'd0       :
                                              issue_rs1_val;
    wire [31:0] op_b = !issue_valid         ? 32'd0       :
                       issue_use_imm        ? issue_imm   :
                                              issue_rs2_val;
    wire [4:0]  gated_op = issue_valid ? issue_alu_op : 5'd0;

    // =========================================================================
    // ALU core (alu.v)
    // =========================================================================
    wire [31:0] basic_result;
    wire        branch_z;
    wire [31:0] mul_result;
    wire        mul_done;
    wire [TAG_WIDTH-1:0] mul_tag_out;
    wire [31:0] div_result;
    wire        div_done;
    wire [TAG_WIDTH-1:0] div_tag_out;

    alu #(.TAG_WIDTH(ROB_IDX)) u_alu (
        .clk        (clk),
        .rst_n      (rst_n),
        .A          (op_a),
        .B          (op_b),
        .opcode     (gated_op),
        .branch     (issue_branch_op),
        .tag_in     (issue_rob_idx),
        .basic_result(basic_result),
        .Z          (branch_z),
        .mul_result (mul_result),
        .mul_done   (mul_done),
        .mul_tag_out(mul_tag_out),
        .div_result (div_result),
        .div_done   (div_done),
        .div_tag_out(div_tag_out)
    );

    // =========================================================================
    // ROB index → PRD mapping table (cho MUL/DIV)
    // =========================================================================
    reg [TAG_WIDTH-1:0] rob_to_prd [0:(1<<ROB_IDX)-1];

    always @(posedge clk) begin
        if (issue_valid)
            rob_to_prd[issue_rob_idx] <= issue_prd;
    end

    // =========================================================================
    // Branch logic
    // =========================================================================
    wire branch_taken = issue_is_branch && branch_z;

    wire [31:0] branch_target = issue_pc + issue_imm;
    wire [31:0] jal_target    = issue_pc + issue_imm;
    // [FIX-JALR] Chuẩn RISC-V: target = (rs1 + imm) & ~1
    wire [31:0] jalr_target   = (issue_rs1_val + issue_imm) & 32'hFFFF_FFFE;
    wire [31:0] pc_plus4      = issue_pc + 32'd4;

    // =========================================================================
    // WB0: basic result (1-cycle delay)
    // =========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wb0_valid <= 1'b0;
            wb0_exc   <= 1'b0;
        end else if (flush) begin
            wb0_valid <= 1'b0;
            wb0_exc   <= 1'b0;
        end else begin
            // Exclude MUL/DIV (opcode[4:3] == 2'b10)
            wb0_valid      <= issue_valid && !(issue_alu_op[4:3] == 2'b10);
            wb0_rob_idx    <= issue_rob_idx;
            wb0_prd        <= issue_prd;
            wb0_exc        <= 1'b0;
            // [BP-UPDATE] latch PC và is_branch để cập nhật predictor
            wb0_pc         <= issue_pc;
            wb0_is_branch  <= issue_is_branch;

            if (issue_valid) begin
                if (issue_is_branch) begin
                    wb0_exc    <= branch_taken;
                    wb0_result <= branch_taken ? branch_target : pc_plus4;
                end else if (issue_is_jal) begin
                    // JAL: rd=PC+4, nhảy vô điều kiện → exc=1 (always flush)
                    // wb0_result = flush_pc target (ROB dùng để set flush_pc)
                    // rd value (PC+4) được ghi qua ROB commit path bình thường
                    // Trick: dùng wb1 path cho rd, wb0 cho flush signal
                    // Nhưng ROB chỉ có 1 result field → encode: 
                    // [FIX-JAL] ROB result = jal_target (flush target)
                    // rd value (pc_plus4) lưu riêng qua jal_rd_result register
                    wb0_exc    <= 1'b1;           // luôn flush (unconditional)
                    wb0_result <= jal_target;     // ROB.flush_pc = PC+imm
                end else if (issue_is_jalr) begin
                    // JALR: rd=PC+4, nhảy đến (rs1+imm)&~1 → exc=1
                    wb0_exc    <= 1'b1;
                    wb0_result <= jalr_target;    // ROB.flush_pc = (rs1+imm)&~1
                end else begin
                    wb0_result <= basic_result;
                    wb0_exc    <= 1'b0;
                end
            end
        end
    end

    // =========================================================================
    // WB1: MUL / DIV result (multi-cycle)
    // =========================================================================
    assign wb1_valid   = mul_done | div_done;
    assign wb1_result  = mul_done ? mul_result : div_result;
    assign wb1_rob_idx = mul_done ? mul_tag_out : div_tag_out;
    assign wb1_exc     = 1'b0;
    assign wb1_prd     = rob_to_prd[wb1_rob_idx];

endmodule