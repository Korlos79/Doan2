module RAT_Float #(
    parameter TAG_WIDTH = 6
)(
    input wire clk,
    input wire rst_n,
    input wire flush,

    // Cổng đọc
    input  wire [4:0]           rs1_addr,
    output wire [TAG_WIDTH-1:0] rs1_tag,

    input  wire [4:0]           rs2_addr,
    output wire [TAG_WIDTH-1:0] rs2_tag,

    input  wire [4:0]           rs3_addr,
    output wire [TAG_WIDTH-1:0] rs3_tag,

    // Cổng Issue
    input  wire                 issue_valid,
    input  wire [4:0]           issue_rd,
    input  wire [TAG_WIDTH-1:0] issue_new_pr_tag, // Tag lấy từ Free List Float

    // Cổng Commit
    input  wire                 commit_valid,
    input  wire [4:0]           commit_rd,
    input  wire [TAG_WIDTH-1:0] commit_pr_tag,
    
    // Gửi Tag cũ trả về Free List Float
    output wire [TAG_WIDTH-1:0] old_pr_tag_to_free,
    output wire                 free_tag_valid
);
    reg [TAG_WIDTH-1:0] fRAT [0:31];
    reg [TAG_WIDTH-1:0] aRAT [0:31];

    assign rs1_tag = fRAT[rs1_addr];
    assign rs2_tag = fRAT[rs2_addr];
    assign rs3_tag = fRAT[rs3_addr];

    assign old_pr_tag_to_free = aRAT[commit_rd];
    assign free_tag_valid     = commit_valid; // f0 vẫn được free bình thường

    integer i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i=0; i<32; i=i+1) begin
                fRAT[i] <= i;
                aRAT[i] <= i;
            end
        end 
        else if (flush) begin
            for (i=0; i<32; i=i+1) begin
                fRAT[i] <= aRAT[i];
            end
        end 
        else begin
            if (commit_valid) begin
                aRAT[commit_rd] <= commit_pr_tag;
            end

            if (issue_valid) begin
                fRAT[issue_rd] <= issue_new_pr_tag;
            end
        end
    end
endmodule