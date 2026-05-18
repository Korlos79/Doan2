module RAT_Int #(
    parameter TAG_WIDTH = 6 // Chú ý: Đổi thành 6 bit cho 64 thanh ghi
)(
    input wire clk,
    input wire rst_n,
    input wire flush, 

    // =========================================
    // 1. CỔNG ĐỌC TẠI DISPATCH
    // =========================================
    input  wire [4:0]           rs1_addr,
    output wire [TAG_WIDTH-1:0] rs1_tag, // Không còn rs_ready ở đây nữa!

    input  wire [4:0]           rs2_addr,
    output wire [TAG_WIDTH-1:0] rs2_tag,

    // =========================================
    // 2. CỔNG ISSUE (Đổi tên thanh ghi đích)
    // =========================================
    input  wire                 issue_valid,
    input  wire [4:0]           issue_rd,
    input  wire [TAG_WIDTH-1:0] issue_new_pr_tag, // Tag mới lấy từ Free List

    // =========================================
    // 3. CỔNG COMMIT (Cập nhật aRAT & thu hồi Tag)
    // =========================================
    input  wire                 commit_valid,
    input  wire [4:0]           commit_rd,
    input  wire [TAG_WIDTH-1:0] commit_pr_tag,
    
    // OUTPUT RẤT QUAN TRỌNG: Gửi Tag cũ trả về Free List
    output wire [TAG_WIDTH-1:0] old_pr_tag_to_free,
    output wire                 free_tag_valid 
);
    // Khai báo 2 bảng RAT
    reg [TAG_WIDTH-1:0] fRAT [0:31]; // Front-end RAT (Sổ nháp)
    reg [TAG_WIDTH-1:0] aRAT [0:31]; // Architectural RAT (Sổ chính thức)

    // Lõi logic đọc (Luôn lấy từ fRAT)
    assign rs1_tag = (rs1_addr == 0) ? {TAG_WIDTH{1'b0}} : fRAT[rs1_addr];
    assign rs2_tag = (rs2_addr == 0) ? {TAG_WIDTH{1'b0}} : fRAT[rs2_addr];

    // Truy xuất Tag cũ từ aRAT để vứt vào Free List khi Commit thành công
    assign old_pr_tag_to_free = aRAT[commit_rd];
    assign free_tag_valid     = commit_valid && (commit_rd != 0); // Không bao giờ free PR 0 của x0

    integer i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Reset: Map 1-1 (x0->P0, x1->P1,..., x31->P31)
            for (i=0; i<32; i=i+1) begin
                fRAT[i] <= i;
                aRAT[i] <= i;
            end
        end 
        else if (flush) begin
            // KHI ĐOÁN SAI NHÁNH: Phục hồi Sổ nháp bằng Sổ chính thức
            for (i=0; i<32; i=i+1) begin
                fRAT[i] <= aRAT[i];
            end
        end 
        else begin
            // --- XỬ LÝ COMMIT (Cập nhật Sổ chính thức) ---
            if (commit_valid && commit_rd != 0) begin
                aRAT[commit_rd] <= commit_pr_tag;
            end

            // --- XỬ LÝ ISSUE (Cập nhật Sổ nháp) ---
            if (issue_valid && issue_rd != 0) begin
                fRAT[issue_rd] <= issue_new_pr_tag;
            end
        end
    end
endmodule