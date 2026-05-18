module fp_mul (
    input clk,
    input rst_n,          // Thêm rst để reset thanh ghi valid
    input start,        // Tín hiệu kích hoạt lệnh
    input [3:0] tag_in, // Thêm ngõ vào tag_in
    input [31:0] floatA,
    input [31:0] floatB,
    output reg [31:0] result,
    output reg valid_out, // High khi result hợp lệ
    output reg [3:0] tag_out // Thêm ngõ ra tag_out
);

// --- QUẢN LÝ VALID & TAG (3-cycle delay) ---
    reg [1:0] v_pipe;          // Giảm từ 3 xuống 2 bit
    reg [3:0] tag_pipe [0:1];  // Giảm từ 3 xuống 2 tầng

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            v_pipe <= 2'b0;
            tag_pipe[0] <= 4'b0;
            tag_pipe[1] <= 4'b0;
        end else begin 
            v_pipe <= {v_pipe[0], start};
            tag_pipe[0] <= tag_in;
            tag_pipe[1] <= tag_pipe[0];
        end
    end
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_out <= 1'b0;
            tag_out   <= 4'b0;
        end else begin     
            valid_out <= v_pipe[1];
            tag_out   <= tag_pipe[1];
        end
    end

    // --- TẦNG 1: UNPACK (Combinational) ---
    wire s_node;
    wire [7:0]  eA, eB;
    wire [23:0] mA, mB;

    assign s_node = floatA[31] ^ floatB[31];
    assign eA     = floatA[30:23];
    assign eB     = floatB[30:23];
    
    assign mA = (eA == 8'b0) ? {1'b0, floatA[22:0]} : {1'b1, floatA[22:0]};
    assign mB = (eB == 8'b0) ? {1'b0, floatB[22:0]} : {1'b1, floatB[22:0]};

    // --- TẦNG 2: EXPO & SIGN REG (1st Clock) ---
    reg [8:0] exp_sum; 
    reg s_d1;
    reg is_zero_d1;

    always @(posedge clk) begin
        exp_sum    <= eA + eB - 9'd127; 
        s_d1       <= s_node; 
        is_zero_d1 <= (eA == 8'b0 || eB == 8'b0);
    end

    // --- TẦNG 3: MANTISSA MULTIPLY (2nd Clock) ---
    // Giả định mantissa_multiplier có thanh ghi ngõ ra bên trong
    wire [47:0] m_prod;
    mantissa_multiplier mul_inst (
        .clk(clk), 
        .A(mA), 
        .B(mB), 
        .Product(m_prod)
    ); 

    // Các tín hiệu ở Tầng 2 cần được delay thêm 1 nhịp để khớp với m_prod từ multiplier
    reg [8:0] exp_sum_d2;
    reg s_d2;
    reg is_zero_d2;
    
    always @(posedge clk) begin
        exp_sum_d2 <= exp_sum;
        s_d2       <= s_d1;
        is_zero_d2 <= is_zero_d1;
    end

    // --- TẦNG 4: NORMALIZATION & OUTPUT (3rd Clock) ---
    wire norm;
    wire [8:0]  f_exp_full;
    wire [22:0] f_mant;

    assign norm       = m_prod[47]; 
    assign f_exp_full = exp_sum_d2 + {8'b0, norm}; 
    assign f_mant     = norm ? m_prod[46:24] : m_prod[45:23]; 

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            result <= 32'b0;
        end else begin
            if (is_zero_d2) 
                result <= {s_d2, 8'b0, 23'b0};
            else 
                result <= {s_d2, f_exp_full[7:0], f_mant}; 
        end
    end
endmodule