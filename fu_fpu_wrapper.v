// =============================================================================
//  fu_fpu_wrapper.v
//
//  Wrapper kết nối FPU pipeline với Reservation Station và CDB Arbiter.
//
//  - FPU có tag_in/tag_out → wrapper không cần FIFO, không cần tự quản lý tag.
//  - Khi FPU done=1, tag_out chính xác → đẩy thẳng lên CDB.
//  - "Trạm dừng" (staging register) giữ kết quả chờ CDB ack.
// =============================================================================

module fu_fpu_wrapper #(
    parameter DATA_WIDTH = 32,
    parameter TAG_WIDTH  = 4
)(
    input  wire                  clk,
    input  wire                  rst_n,

    // --- Giao diện với Reservation Station ---
    input  wire                  start,
    input  wire [4:0]            opcode,
    input  wire [31:0]           op1, op2, op3,
    input  wire [TAG_WIDTH-1:0]  tag_in,

    // --- Giao diện với CDB Arbiter ---
    output reg                   cdb_valid,
    output reg  [DATA_WIDTH-1:0] cdb_result,
    output reg  [TAG_WIDTH-1:0]  cdb_tag,
    input  wire                  cdb_ack
);

    // =========================================================================
    //  KẾT NỐI VỚI FPU PIPELINE CORE
    // =========================================================================
    wire [DATA_WIDTH-1:0] fpu_result_w;
    wire [TAG_WIDTH-1:0]  fpu_tag_out_w;
    wire                  fpu_done_w;
    wire                  fpu_exc_w;

    FPU FPU_CORE (
        .clk        (clk),
        .rst_n      (rst_n),
        .start      (start),
        .tag_in     (tag_in),         // tag từ RS truyền thẳng vào FPU
        .FPUOpd     (opcode),
        .a_operand  (op1),
        .b_operand  (op2),
        .c_operand  (op3),
        .result     (fpu_result_w),
        .tag_out    (fpu_tag_out_w),  // tag ra cùng kết quả, không cần FIFO
        .done       (fpu_done_w),
        .Exception  (fpu_exc_w)
    );

    // =========================================================================
    //  STAGING REGISTER — "TRẠM DỪNG" CHỜ CDB
    //
    //  Khi fpu_done=1 và done+ack cùng lúc → kết quả mới ghi đè ngay,
    //  không mất chu kỳ (ưu tiên done hơn ack).
    // =========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cdb_valid  <= 1'b0;
            cdb_result <= {DATA_WIDTH{1'b0}};
            cdb_tag    <= {TAG_WIDTH{1'b0}};
        end else begin
            if (fpu_done_w) begin
                // FPU xong → chốt kết quả vào trạm dừng
                cdb_valid  <= 1'b1;
                cdb_result <= fpu_result_w;
                cdb_tag    <= fpu_tag_out_w;  // tag chính xác từ FPU
            end else if (cdb_valid && cdb_ack) begin
                // CDB đã nhận → xóa trạm dừng
                cdb_valid <= 1'b0;
            end
        end
    end

    // =========================================================================
    //  GHI CHÚ:
    //  - fpu_exc_w chưa dùng. Nếu cần, thêm output cdb_exception để ROB
    //    xử lý overflow / div-by-zero / sqrt âm.
    // =========================================================================

endmodule