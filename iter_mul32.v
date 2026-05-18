module iter_mul32 #(
    parameter TAG_WIDTH = 4 // Bạn có thể điều chỉnh độ rộng tag ở đây
)(
    input  wire                   clk,
    input  wire                   rst_n,

    input  wire                   start,   
    input  wire [4:0]             op_sel,
    input  wire [TAG_WIDTH-1:0]   tag_in,   // Tag đầu vào (ví dụ: ID của lệnh)
    input  wire [31:0]            rs1,
    input  wire [31:0]            rs2,

    output reg                    done,
    output reg  [TAG_WIDTH-1:0]   tag_out,  // Tag đầu ra (khớp với kết quả)
    output reg  [31:0]            result
);

    localparam OP_MUL    = 5'b10000;
    localparam OP_MULH   = 5'b10001;
    localparam OP_MULHSU = 5'b10010;
    localparam OP_MULHU  = 5'b10011;

    // --- STAGE 1 ---
    reg                   s1_valid;
    reg [TAG_WIDTH-1:0]   s1_tag;
    reg                   s1_want_high, s1_neg_res;
    reg [31:0]            s1_abs_a, s1_abs_b;
    
    wire is_a_signed = (op_sel == OP_MULH) | (op_sel == OP_MULHSU);
    wire is_b_signed = (op_sel == OP_MULH);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s1_valid <= 1'b0;
            s1_tag   <= {TAG_WIDTH{1'b0}};
        end else begin
            s1_valid <= start;
            s1_tag   <= tag_in; // Nạp tag vào tầng 1
        end
    end

    always @(posedge clk) begin
        s1_want_high <= (op_sel != OP_MUL);
        s1_abs_a     <= (is_a_signed && rs1[31]) ? (~rs1 + 1'b1) : rs1;
        s1_abs_b     <= (is_b_signed && rs2[31]) ? (~rs2 + 1'b1) : rs2;
        s1_neg_res   <= (is_a_signed & rs1[31]) ^ (is_b_signed & rs2[31]);
    end

    // --- STAGE 2 ---
    reg                   s2_valid;
    reg [TAG_WIDTH-1:0]   s2_tag;
    reg                   s2_want_high, s2_neg_res;
    reg [63:0]            s2_product_raw;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s2_valid <= 1'b0;
            s2_tag   <= {TAG_WIDTH{1'b0}};
        end else begin
            s2_valid <= s1_valid;
            s2_tag   <= s1_tag; // Truyền tag sang tầng 2
        end
    end

    always @(posedge clk) begin
        s2_want_high   <= s1_want_high;
        s2_neg_res     <= s1_neg_res;
        s2_product_raw <= {32'b0, s1_abs_a} * {32'b0, s1_abs_b};
    end

    // --- STAGE 3 ---
    reg                   s3_valid;
    reg [TAG_WIDTH-1:0]   s3_tag;
    reg                   s3_want_high, s3_neg_res;
    reg [63:0]            s3_product;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s3_valid <= 1'b0;
            s3_tag   <= {TAG_WIDTH{1'b0}};
        end else begin
            s3_valid <= s2_valid;
            s3_tag   <= s2_tag; // Truyền tag sang tầng 3
        end
    end

    always @(posedge clk) begin
        s3_want_high <= s2_want_high;
        s3_neg_res   <= s2_neg_res;
        s3_product   <= s2_product_raw;
    end

    // --- STAGE 4 (FINALIZE) ---
    wire [63:0] final_product_w = s3_neg_res ? (~s3_product + 64'd1) : s3_product;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            done    <= 1'b0;
            tag_out <= {TAG_WIDTH{1'b0}};
            result  <= 32'd0;
        end else begin
            done    <= s3_valid;
            tag_out <= s3_tag; // Xuất tag cùng với kết quả
            result  <= s3_want_high ? final_product_w[63:32] : final_product_w[31:0];
        end
    end

endmodule