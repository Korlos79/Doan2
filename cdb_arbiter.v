module cdb_arbiter #(
    parameter DATA_WIDTH = 32,
    parameter TAG_WIDTH  = 4  // Đồng bộ với ROB và RAT (log2(16) = 4)
)(
    // ==========================================
    // 1. KẾT NỐI VỚI ALU WRAPPER
    // ==========================================
    input  wire                  alu_valid,
    input  wire [DATA_WIDTH-1:0] alu_result,
    input  wire [TAG_WIDTH-1:0]  alu_tag,
    
    // MỚI: Tín hiệu Branch/Jump từ ALU
    input  wire                  alu_branch_taken,
    input  wire [31:0]           alu_branch_target,
    
    output reg                   alu_ack,

    // ==========================================
    // 2. KẾT NỐI VỚI FPU WRAPPER
    // ==========================================
    input  wire                  fpu_valid,
    input  wire [DATA_WIDTH-1:0] fpu_result,
    input  wire [TAG_WIDTH-1:0]  fpu_tag,
    output reg                   fpu_ack,

    // ==========================================
    // 3. KẾT NỐI VỚI LSU WRAPPER
    // ==========================================
    input  wire                  lsu_valid,
    input  wire [DATA_WIDTH-1:0] lsu_result,
    input  wire [TAG_WIDTH-1:0]  lsu_tag,
    output reg                   lsu_ack,

    // ==========================================
    // 4. ĐẦU RA CHÍNH (COMMON DATA BUS OUT)
    // Broadcast tới ROB, RS
    // ==========================================
    output reg                   cdb_valid_out,
    output reg  [DATA_WIDTH-1:0] cdb_result_out,
    output reg  [TAG_WIDTH-1:0]  cdb_tag_out,
    
    // MỚI: Broadcast tín hiệu Branch/Jump cho ROB
    output reg                   cdb_branch_taken_out,
    output reg  [31:0]           cdb_branch_target_out
);

    // Mạch tổ hợp (Combinational Logic) - Phản hồi ngay lập tức trong 1 chu kỳ
    always @(*) begin
        // 0. Mặc định: Không ai được cấp quyền, Bus rỗng
        alu_ack = 1'b0;
        fpu_ack = 1'b0;
        lsu_ack = 1'b0;
        
        cdb_valid_out         = 1'b0;
        cdb_result_out        = {DATA_WIDTH{1'b0}};
        cdb_tag_out           = {TAG_WIDTH{1'b0}};
        cdb_branch_taken_out  = 1'b0;
        cdb_branch_target_out = 32'd0;

        // 1. Phân xử theo thứ tự ưu tiên: LSU -> ALU -> FPU
        if (lsu_valid) begin
            // LSU thắng
            lsu_ack               = 1'b1;
            cdb_valid_out         = 1'b1;
            cdb_result_out        = lsu_result;
            cdb_tag_out           = lsu_tag;
            // LSU không có branch, giữ nguyên 0

        end else if (alu_valid) begin
            // ALU thắng
            alu_ack               = 1'b1;
            cdb_valid_out         = 1'b1;
            cdb_result_out        = alu_result;
            cdb_tag_out           = alu_tag;
            
            // MỚI: Truyền cờ Branch/Jump từ ALU lên Bus
            cdb_branch_taken_out  = alu_branch_taken;
            cdb_branch_target_out = alu_branch_target;

        end else if (fpu_valid) begin
            // FPU thắng
            fpu_ack               = 1'b1;
            cdb_valid_out         = 1'b1;
            cdb_result_out        = fpu_result;
            cdb_tag_out           = fpu_tag;
            // FPU không có branch, giữ nguyên 0
        end
    end

endmodule