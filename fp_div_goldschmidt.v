`timescale 1ns/1ps

module fp_div_goldschmidt #(
    parameter PIPE_LAT = 13
)(
    input         clk,
    input         rst_n,
    input         start,
    input  [3:0]  tag_in,      
    input  [31:0] floatA,
    input  [31:0] floatB,
    output reg [31:0] result,
    output reg        valid_out,
    output reg [3:0]  tag_out      
);

    localparam [31:0] FP_TWO  = 32'h40000000; //2 
    localparam [31:0] FP_ZERO = 32'h00000000; //0 
    localparam [31:0] FP_NEG1 = 32'hBF800000; //-1 
    localparam        FMA_LAT = 2;             // TRUE latency of fp_fma
    localparam        META_D  = 5 * FMA_LAT; // = 10

    // ----------------------------------------------------------
    // valid & tag shift register: PIPE_LAT-1 = 12 stages
    // ----------------------------------------------------------
    reg [PIPE_LAT-2:0] valid_pipe;
    reg [3:0]          tag_pipe [0:PIPE_LAT-2]; // Mảng 2D cho Tag delay line
    integer ti;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_pipe <= 0;
            for (ti = 0; ti < PIPE_LAT-1; ti = ti + 1) begin
                tag_pipe[ti] <= 4'b0;
            end
        end else begin
            valid_pipe <= {valid_pipe[PIPE_LAT-3:0], start};
            tag_pipe[0] <= tag_in;
            for (ti = 1; ti < PIPE_LAT-1; ti = ti + 1) begin
                tag_pipe[ti] <= tag_pipe[ti-1];
            end
        end
    end

    // ----------------------------------------------------------
    // Stage 0: capture inputs, compute exp correction & sign
    // ----------------------------------------------------------
    reg [31:0]       N_s0, D_s0;
    reg              sign_s0;
    reg signed [8:0] exp_corr_s0;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sign_s0 <= 0; exp_corr_s0 <= 0;
            N_s0 <= 0; D_s0 <= 0;
        end else begin
            sign_s0     <= floatA[31] ^ floatB[31];
            exp_corr_s0 <= $signed({1'b0, floatA[30:23]})
                         - $signed({1'b0, floatB[30:23]});
            // Normalize cả hai về [1,2) bằng cách force exp = 127
            N_s0 <= {1'b0, 8'd127, floatA[22:0]};
            D_s0 <= {1'b0, 8'd127, floatB[22:0]};
        end
    end

    // ----------------------------------------------------------
    // LUT ROM: f0 ≈ 1/B_norm (registered output, 1-cycle latency)
    // lut_idx dùng floatB[22:15] TRỰC TIẾP (input port, not from S0)
    // Điều này đúng vì S0 và LUT đều latch cùng 1 posedge từ input
    // ----------------------------------------------------------
    wire [31:0] lut_f0_wire;
    div_lut_rom lut_inst (
        .clk    (clk),
        .lut_idx(floatB[22:15]),
        .lut_f0 (lut_f0_wire)
    );

    // Thêm 1 register để đồng bộ với N_s1/D_s1 (cả hai delay 2 cycles từ input)
    reg [31:0] lut_f0_r;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) lut_f0_r <= 0;
        else     lut_f0_r <= lut_f0_wire;
    end

    // ----------------------------------------------------------
    // Stage 1: pipeline registers
    // ----------------------------------------------------------
    reg [31:0]       N_s1, D_s1;
    reg              sign_s1;
    reg signed [8:0] exp_corr_s1;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            N_s1 <= 0; D_s1 <= 0;
            sign_s1 <= 0; exp_corr_s1 <= 0;
        end else begin
            N_s1 <= N_s0; D_s1 <= D_s0;
            sign_s1 <= sign_s0; exp_corr_s1 <= exp_corr_s0;
        end
    end

    // ----------------------------------------------------------
    // Meta pipeline: truyền sign và exp_corr qua META_D=10 stages
    // sign_pipe[0] ← sign_s1 tại posedge cycle i+2 (sign_s1 valid từ cycle i+2)
    // sign_pipe[9] valid tại cycle i+12 → dùng trong output stage tại posedge i+13 ✓
    // ----------------------------------------------------------
    reg              sign_pipe [0:META_D-1];
    reg signed [8:0] exp_pipe  [0:META_D-1];

    integer gi;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (gi = 0; gi < META_D; gi = gi + 1) begin
                sign_pipe[gi] <= 0; exp_pipe[gi] <= 0;
            end
        end else begin
            sign_pipe[0] <= sign_s1; exp_pipe[0] <= exp_corr_s1;
            for (gi = 1; gi < META_D; gi = gi + 1) begin
                sign_pipe[gi] <= sign_pipe[gi-1];
                exp_pipe[gi]  <= exp_pipe[gi-1];
            end
        end
    end

    // ----------------------------------------------------------
    // Iteration 0-A: N1 = N_norm * f0,  D1 = D_norm * f0
    // inputs valid từ cycle i+2 → outputs (fma_N1, fma_D1) valid từ cycle i+4
    // ----------------------------------------------------------
    wire [31:0] fma_N1, fma_D1;
    fp_fma fma_N0_inst (.clk(clk), .floatA(N_s1),    .floatB(lut_f0_r), .floatC(FP_ZERO), .result(fma_N1));
    fp_fma fma_D0_inst (.clk(clk), .floatA(D_s1),    .floatB(lut_f0_r), .floatC(FP_ZERO), .result(fma_D1));

    // ----------------------------------------------------------
    // Iteration 0-B: F1 = 2 - D1
    // input fma_D1 valid từ cycle i+4 → fma_F1 valid từ cycle i+6
    // ----------------------------------------------------------
    wire [31:0] fma_F1;
    fp_fma fma_F0_inst (.clk(clk), .floatA(FP_NEG1), .floatB(fma_D1),   .floatC(FP_TWO),  .result(fma_F1));

    // Delay chain N1, D1: FMA_LAT=2 phần tử
    // N1_dly[0] valid tại cycle i+5, N1_dly[1] valid tại cycle i+6
    // fma_F1 cũng valid tại cycle i+6 → ALIGNED ✓
    reg [31:0] N1_dly [0:FMA_LAT-1];
    reg [31:0] D1_dly [0:FMA_LAT-1];
    always @(posedge clk) begin
        N1_dly[0] <= fma_N1;
        D1_dly[0] <= fma_D1;
    end
    genvar di;
    generate
        for (di = 1; di < FMA_LAT; di = di + 1) begin : nd1_dly
            always @(posedge clk) begin
                N1_dly[di] <= N1_dly[di-1];
                D1_dly[di] <= D1_dly[di-1];
            end
        end
    endgenerate

    // ----------------------------------------------------------
    // Iteration 1-A: N2 = N1 * F1,  D2 = D1 * F1
    // inputs valid từ cycle i+6 → outputs valid từ cycle i+8
    // ----------------------------------------------------------
    wire [31:0] fma_N2, fma_D2;
    fp_fma fma_N1_inst (.clk(clk), .floatA(N1_dly[FMA_LAT-1]), .floatB(fma_F1), .floatC(FP_ZERO), .result(fma_N2));
    fp_fma fma_D1_inst (.clk(clk), .floatA(D1_dly[FMA_LAT-1]), .floatB(fma_F1), .floatC(FP_ZERO), .result(fma_D2));

    // ----------------------------------------------------------
    // Iteration 1-B: F2 = 2 - D2
    // input fma_D2 valid từ cycle i+8 → fma_F2 valid từ cycle i+10
    // ----------------------------------------------------------
    wire [31:0] fma_F2;
    fp_fma fma_F1_inst (.clk(clk), .floatA(FP_NEG1), .floatB(fma_D2),   .floatC(FP_TWO),  .result(fma_F2));

    // Delay chain N2: FMA_LAT=2 phần tử
    // N2_dly[1] valid tại cycle i+10 → fma_F2 cũng valid tại cycle i+10 → ALIGNED ✓
    reg [31:0] N2_dly [0:FMA_LAT-1];
    always @(posedge clk) N2_dly[0] <= fma_N2;
    genvar di2;
    generate
        for (di2 = 1; di2 < FMA_LAT; di2 = di2 + 1) begin : n2_dly
            always @(posedge clk) N2_dly[di2] <= N2_dly[di2-1];
        end
    endgenerate

    // ----------------------------------------------------------
    // Iteration 2-A: N3 = N2 * F2  (kết quả cuối)
    // inputs valid từ cycle i+10 → fma_N3 valid từ cycle i+12
    // ----------------------------------------------------------
    wire [31:0] fma_N3;
    fp_fma fma_N2_inst (.clk(clk), .floatA(N2_dly[FMA_LAT-1]), .floatB(fma_F2), .floatC(FP_ZERO), .result(fma_N3));

    // ----------------------------------------------------------
    // Output stage: pack IEEE 754
    // fma_N3 valid từ cycle i+12
    // sign_pipe[9] valid từ cycle i+12 (META_D-1 = 9)
    // result registered tại posedge i+13 (PIPE_LAT = 13) ✓
    // ----------------------------------------------------------
    wire              sign_final     = sign_pipe[META_D-1];
    wire signed [8:0] exp_corr_final = exp_pipe [META_D-1];

    wire signed [9:0] exp_n3_10    = {2'b00, fma_N3[30:23]};
    wire signed [9:0] exp_corr_10  = {{1{exp_corr_final[8]}}, exp_corr_final};
    wire signed [9:0] exp_result_s = exp_n3_10 + exp_corr_10;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            result    <= 32'b0; 
            valid_out <= 1'b0;
            tag_out   <= 4'b0; // <--- Đảm bảo reset tag_out
        end else begin
            valid_out <= valid_pipe[PIPE_LAT-2];
            tag_out   <= tag_pipe[PIPE_LAT-2]; // <--- Xuất tag_out ra ngoài tại stage cuối

            if (fma_N3 == FP_ZERO)
                result <= {sign_final, 31'b0};
            else if (exp_result_s >= 10'sd255)
                result <= {sign_final, 8'hFF, 23'b0};   // overflow → Inf
            else if (exp_result_s <= 10'sd0)
                result <= {sign_final, 31'b0};           // underflow → 0
            else
                result <= {sign_final, exp_result_s[7:0], fma_N3[22:0]};
        end
    end

endmodule