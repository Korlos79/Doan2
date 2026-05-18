// =============================================================================
// pipe_div32.v — Pipelined 32-stage Integer Divider (RISC-V RV32M)
// Với tính năng truyền TAG qua Pipeline
// =============================================================================

module iter_div32 #(
    parameter TAG_WIDTH = 4
)(
    input  wire                   clk,
    input  wire                   rst_n,

    input  wire                   start,   
    input  wire [4:0]             op_sel,
    input  wire [TAG_WIDTH-1:0]   tag_in,   // Tag đầu vào
    input  wire [31:0]            rs1,     
    input  wire [31:0]            rs2,     

    output reg                    done,    
    output reg  [TAG_WIDTH-1:0]   tag_out,  // Tag đầu ra khớp với kết quả
    output reg  [31:0]            result   
);

    // --- 0. HẰNG SỐ ---
    localparam OP_DIV  = 5'b10100;
    localparam OP_DIVU = 5'b10101;
    localparam OP_REM  = 5'b10110;
    localparam OP_REMU = 5'b10111;
    localparam STAGES  = 32;

    // --- 1. CẤU TRÚC PIPELINE (MỞ RỘNG ĐỘ RỘNG) ---
    // Cấu trúc cũ: [101]valid, [100:69]R, [68:37]Q, [36:5]B, [4:0]flags (102 bits)
    // Cấu trúc mới: Thêm TAG_WIDTH vào bit cao nhất.
    localparam BASE_W = 102;
    localparam W      = BASE_W + TAG_WIDTH; 

    reg [W-1:0] pipe [0:STAGES]; 

    // Giải mã tín hiệu từ tầng cuối cùng (Stage 32)
    wire                   p_valid    = pipe[STAGES][101];
    wire [TAG_WIDTH-1:0]   p_tag      = pipe[STAGES][W-1:BASE_W]; // Lấy tag từ bit cao
    wire [31:0]            p_R        = pipe[STAGES][100:69];
    wire [31:0]            p_Q        = pipe[STAGES][68:37];
    wire                   p_rs1_sign = pipe[STAGES][4];
    wire                   p_rs2_sign = pipe[STAGES][3];
    wire                   p_is_rem   = pipe[STAGES][2];
    wire                   p_div_zero = pipe[STAGES][1];
    wire                   p_overflow = pipe[STAGES][0];

    // --- 2. PRE-ENCODE ---
    wire is_signed = (op_sel == OP_DIV) || (op_sel == OP_REM);
    wire is_rem    = (op_sel == OP_REM) || (op_sel == OP_REMU);
    wire rs1_sign  = is_signed & rs1[31];
    wire rs2_sign  = is_signed & rs2[31];
    wire [31:0] abs_rs1 = rs1_sign ? (~rs1 + 1'b1) : rs1;
    wire [31:0] abs_rs2 = rs2_sign ? (~rs2 + 1'b1) : rs2;
    wire div_zero  = (rs2 == 32'd0);
    wire overflow  = is_signed & (rs1 == 32'h80000000) & (rs2 == 32'hFFFFFFFF);

    // --- 3. STAGE 0: Nạp TAG và Dữ liệu ---
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            pipe[0] <= {W{1'b0}};
        else begin
            pipe[0][W-1:BASE_W] <= tag_in;      // Nạp Tag vào pipeline
            pipe[0][101]        <= start;
            pipe[0][100:69]     <= 32'd0;    
            pipe[0][68:37]      <= abs_rs1;  
            pipe[0][36:5]       <= abs_rs2;  
            pipe[0][4]          <= rs1_sign;
            pipe[0][3]          <= rs2_sign;
            pipe[0][2]          <= is_rem;
            pipe[0][1]          <= div_zero;
            pipe[0][0]          <= overflow;
        end
    end

    // --- 4. TẦNG CALC 1..32 (Truyền TAG qua các tầng) ---
    genvar i;
    generate
        for (i = 1; i <= STAGES; i = i + 1) begin : calc_stage
            wire [31:0] in_R = pipe[i-1][100:69];
            wire [31:0] in_Q = pipe[i-1][68:37];
            wire [31:0] in_B = pipe[i-1][36:5];

            wire [31:0] r_shift = {in_R[30:0], in_Q[31]};
            wire [31:0] q_shift = {in_Q[30:0], 1'b0};
            wire        do_sub  = (r_shift >= in_B);
            wire [31:0] next_R  = do_sub ? (r_shift - in_B) : r_shift;
            wire [31:0] next_Q  = do_sub ? {q_shift[31:1], 1'b1} : {q_shift[31:1], 1'b0};

            always @(posedge clk or negedge rst_n) begin
                if (!rst_n)
                    pipe[i] <= {W{1'b0}};
                else begin
                    pipe[i][W-1:BASE_W] <= pipe[i-1][W-1:BASE_W]; // Truyền Tag
                    pipe[i][101]        <= pipe[i-1][101];        // valid
                    pipe[i][100:69]     <= next_R;
                    pipe[i][68:37]      <= next_Q;
                    pipe[i][36:5]       <= in_B;
                    pipe[i][4:0]        <= pipe[i-1][4:0];
                end
            end
        end
    endgenerate

    // --- 5. RS1 DELAY LINE (Cho ngoại lệ REM x/0) ---
    reg [31:0] rs1_pipe [0:STAGES]; 
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) rs1_pipe[0] <= 32'd0;
        else        rs1_pipe[0] <= rs1;
    end

    genvar j;
    generate
        for (j = 1; j <= STAGES; j = j + 1) begin : rs1_delay
            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) rs1_pipe[j] <= 32'd0;
                else        rs1_pipe[j] <= rs1_pipe[j-1];
            end
        end
    endgenerate

    // --- 6. FIX STAGE (Xử lý dấu và xuất kết quả + TAG) ---
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            done    <= 1'b0;
            tag_out <= {TAG_WIDTH{1'b0}};
            result  <= 32'd0;
        end else begin
            done    <= p_valid;
            tag_out <= p_tag; // Xuất Tag cùng lúc với done

            if (p_valid) begin
                if (p_div_zero)
                    result <= p_is_rem ? rs1_pipe[STAGES] : 32'hFFFFFFFF;
                else if (p_overflow)
                    result <= p_is_rem ? 32'd0 : 32'h80000000;
                else begin
                    if (p_is_rem)
                        result <= p_rs1_sign ? (~p_R + 1'b1) : p_R;
                    else
                        result <= (p_rs1_sign ^ p_rs2_sign) ? (~p_Q + 1'b1) : p_Q;
                end
            end
        end
    end

endmodule