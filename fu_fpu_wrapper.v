// =============================================================================
// fpu_eu.v  —  FPU Execute Unit  (Execute Stage wrapper)
//
// Bọc ngoài FPU.v (đã có sẵn).
//
// Xử lý tất cả F-extension:
//   FADD, FSUB, FMUL, FDIV, FSQRT, FMADD, FMSUB, FNMADD, FNMSUB
//   FSGNJ, FSGNJN, FSGNJX, FEQ, FLT, FLE
//   FCVT, FMV, FMIN, FMAX
//
// Tag strategy:
//   FPU.v dùng tag_in (4-bit) để track lệnh qua pipeline.
//   Ở đây dùng rob_idx[3:0] làm tag_in.
//   Khi done=1, tag_out khớp với rob_idx → dùng rob_to_prd table để lấy prd.
// =============================================================================

module fu_fpu_wrapper #(
    parameter TAG_WIDTH = 6,
    parameter ROB_IDX   = 5
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        flush,

    // -------------------------------------------------------------------------
    // Từ IQ_FPU (Issue)
    // -------------------------------------------------------------------------
    input  wire                  issue_valid,
    input  wire [TAG_WIDTH-1:0]  issue_prd,
    input  wire [31:0]           issue_rs1_val,
    input  wire [31:0]           issue_rs2_val,
    input  wire [31:0]           issue_rs3_val,
    input  wire [4:0]            issue_fpu_op,
    input  wire [ROB_IDX-1:0]   issue_rob_idx,

    // -------------------------------------------------------------------------
    // Writeback Port 2: FPU (variable-latency, tag-based)
    // -------------------------------------------------------------------------
    output wire                  wb2_valid,
    output wire [ROB_IDX-1:0]   wb2_rob_idx,
    output wire [31:0]           wb2_result,
    output wire                  wb2_exc,
    output wire [TAG_WIDTH-1:0]  wb2_prd
);

    // =========================================================================
    // ROB idx → PRD mapping
    // =========================================================================
    reg [TAG_WIDTH-1:0] rob_to_prd [0:(1<<ROB_IDX)-1];
    reg [ROB_IDX-1:0]   rob_idx_tbl [0:15];  // tag_in (4-bit) → rob_idx

    always @(posedge clk) begin
        if (issue_valid) begin
            rob_to_prd[issue_rob_idx]         <= issue_prd;
            rob_idx_tbl[issue_rob_idx[3:0]]   <= issue_rob_idx;
        end
    end

    // =========================================================================
    // FPU.v instance
    // =========================================================================
    wire [31:0] fpu_result;
    wire [3:0]  fpu_tag_out;
    wire        fpu_done;
    wire        fpu_exc;

    // [FIX-7] Gate fpu_done với flush: nếu flush đang active thì bỏ qua kết quả
    // vì ROB entries tương ứng đã bị invalidate.
    reg flush_r;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) flush_r <= 1'b0;
        else        flush_r <= flush;
    end

    FPU u_fpu (
        .clk        (clk),
        .rst_n      (rst_n),
        .start      (issue_valid),
        .tag_in     (issue_rob_idx[3:0]),   // 4-bit tag = rob_idx[3:0]
        .a_operand  (issue_rs1_val),
        .b_operand  (issue_rs2_val),
        .c_operand  (issue_rs3_val),
        .FPUOpd     (issue_fpu_op),
        .result     (fpu_result),
        .tag_out    (fpu_tag_out),
        .done       (fpu_done),
        .Exception  (fpu_exc)
    );

    // =========================================================================
    // WB2 output
    // =========================================================================
    wire [ROB_IDX-1:0] resolved_rob_idx = rob_idx_tbl[fpu_tag_out];

    assign wb2_valid   = fpu_done && !flush_r;  // [FIX-7] bỏ qua kết quả sau flush
    assign wb2_result  = fpu_result;
    assign wb2_rob_idx = resolved_rob_idx;
    assign wb2_exc     = fpu_exc;
    assign wb2_prd     = rob_to_prd[resolved_rob_idx];

endmodule