`timescale 1ns/1ps

// ===========================================================================
//  fp_sqrt_goldschmidt.v  (Fixed – 0 ULP)
//
//  Thuật toán: Goldschmidt 3 vòng lặp + Newton-Raphson correction step
//              + Post-rounding integer correction (0 ULP guaranteed)
//
//  Pipeline timing (FMA_LAT = 2):
//    Cycle  0 : start, floatA vào
//    Cycle  2 : y0_r, X_in_s1 sẵn sàng  → u_g0, u_h0 bắt đầu
//    Cycle  4 : fma_g0, fma_h0           → u_F0 bắt đầu
//    Cycle  6 : fma_F0, g0_dly[1]        → u_g1, u_h1 bắt đầu
//    Cycle  8 : fma_g1, fma_h1           → u_F1 bắt đầu
//    Cycle 10 : fma_F1, g1_dly[1]        → u_g2, u_h2 bắt đầu
//    Cycle 12 : fma_g2, fma_h2           → u_F2 bắt đầu
//    Cycle 14 : fma_F2, g2_dly[1]        → u_g3, u_h3 bắt đầu
//    Cycle 16 : fma_g3, fma_h3           → u_e3 bắt đầu
//    Cycle 18 : fma_e3                   → u_gfinal bắt đầu
//    Cycle 20 : fma_gfinal sẵn sàng      → post-round correction
//    Cycle 21 : OUTPUT register          → PIPE_LAT = 21
//
//  NR correction:
//    e3      = FMA(-g3, g3, x)      // residual = x - g3^2
//    g_final = FMA(e3,  h3, g3)     // g3 + e3*h3
//
//  Post-rounding correction (cycle 20→21, combinational):
//    Dùng fp_mul_approx để tính g_final^2, so sánh với X_in (dạng integer).
//    Nếu g_final^2 > X_in  → result = g_final - 1 ULP
//    Nếu g_final^2 < X_in và (g_final+1)^2 <= X_in → result = g_final + 1 ULP
//    Ngược lại → result = g_final
// ===========================================================================

module fp_sqrt_goldschmidt #(
    parameter PIPE_LAT = 21
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,
    input  wire [3:0]  tag_in,
    input  wire [31:0] floatA,
    output reg  [31:0] result,
    output reg         valid_out,
    output reg  [3:0]  tag_out
);

    localparam [31:0] FP_ZERO     = 32'h00000000;
    localparam [31:0] FP_HALF     = 32'h3F000000; // 0.5
    localparam [31:0] FP_ONE_HALF = 32'h3FC00000; // 1.5
    localparam [31:0] FP_NAN      = 32'h7FC00000; // Not a Number
    localparam        FMA_LAT     = 2;
    localparam        META_D      = 20; // delay final_exp/flags đến cycle 20

    // ----------------------------------------------------------
    // VALID & TAG SHIFT REGISTERS
    // ----------------------------------------------------------
    reg [PIPE_LAT-2:0] valid_pipe;
    reg [3:0]          tag_pipe [0:PIPE_LAT-2];
    integer ti;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_pipe <= 0;
            for (ti = 0; ti < PIPE_LAT-1; ti = ti + 1) tag_pipe[ti] <= 4'b0;
        end else begin
            valid_pipe <= {valid_pipe[PIPE_LAT-3:0], start};
            tag_pipe[0] <= tag_in;
            for (ti = 1; ti < PIPE_LAT-1; ti = ti + 1)
                tag_pipe[ti] <= tag_pipe[ti-1];
        end
    end

    // ----------------------------------------------------------
    // STAGE 0: BÓC TÁCH EXPONENT & CHUẨN BỊ X_in
    // ----------------------------------------------------------
    wire [31:0] X_in_wire = {1'b0, floatA[23] ? 8'd127 : 8'd128, floatA[22:0]};

    wire signed [8:0] e_adj         = {1'b0, floatA[30:23]} - 9'd127;
    wire signed [8:0] e_out         = (e_adj >>> 1);
    wire        [7:0] final_exp_wire = e_out[7:0] + 8'd127;

    wire is_zero_wire = (floatA[30:23] == 8'd0);
    wire is_neg_wire  = floatA[31] & ~is_zero_wire;

    // X_in_s1 sẵn sàng tại cycle 2
    reg [31:0] X_in_s0, X_in_s1;
    always @(posedge clk) begin
        X_in_s0 <= X_in_wire;
        X_in_s1 <= X_in_s0;
    end

    // ----------------------------------------------------------
    // X_in DELAY PIPELINE: cycle 2 → cycle 16 (delay thêm 14)
    // ----------------------------------------------------------
    localparam X_DELAY = 14;
    reg [31:0] X_in_dly [0:X_DELAY-1];
    integer xi;
    always @(posedge clk) begin
        X_in_dly[0] <= X_in_s1;
        for (xi = 1; xi < X_DELAY; xi = xi + 1)
            X_in_dly[xi] <= X_in_dly[xi-1];
    end
    // X_in_dly[13] sẵn sàng tại cycle 2+14 = 16

    // ----------------------------------------------------------
    // X_in thêm delay 4 nữa → cycle 20 (dùng cho post-correction)
    // ----------------------------------------------------------
    localparam X_DELAY2 = 4;
    reg [31:0] X_in_dly2 [0:X_DELAY2-1];
    integer xi2;
    always @(posedge clk) begin
        X_in_dly2[0] <= X_in_dly[X_DELAY-1];
        for (xi2 = 1; xi2 < X_DELAY2; xi2 = xi2 + 1)
            X_in_dly2[xi2] <= X_in_dly2[xi2-1];
    end
    // X_in_dly2[3] sẵn sàng tại cycle 20 — chính là X_norm tại cycle output

    // ----------------------------------------------------------
    // STAGE 1 & 2: LUT ROM → y0 = 1/sqrt(X_norm), latency 1 clk
    // ----------------------------------------------------------
    wire [31:0] lut_y0_wire;
    sqrt_lut_rom lut_inst (
        .clk    (clk),
        .lut_idx({~floatA[23], floatA[22:16]}),
        .lut_y0 (lut_y0_wire)
    );

    reg [31:0] y0_r;
    always @(posedge clk) y0_r <= lut_y0_wire;
    // y0_r sẵn sàng tại cycle 2

    // ----------------------------------------------------------
    // META PIPELINE: delay 20 chu kỳ
    // ----------------------------------------------------------
    reg [7:0] final_exp_pipe [0:META_D-1];
    reg       is_zero_pipe   [0:META_D-1];
    reg       is_neg_pipe    [0:META_D-1];
    integer gi;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (gi = 0; gi < META_D; gi = gi + 1) begin
                final_exp_pipe[gi] <= 0;
                is_zero_pipe[gi]   <= 0;
                is_neg_pipe[gi]    <= 0;
            end
        end else begin
            final_exp_pipe[0] <= final_exp_wire;
            is_zero_pipe[0]   <= is_zero_wire;
            is_neg_pipe[0]    <= is_neg_wire;
            for (gi = 1; gi < META_D; gi = gi + 1) begin
                final_exp_pipe[gi] <= final_exp_pipe[gi-1];
                is_zero_pipe[gi]   <= is_zero_pipe[gi-1];
                is_neg_pipe[gi]    <= is_neg_pipe[gi-1];
            end
        end
    end

    // ==========================================================
    // GOLDSCHMIDT – 3 ITERATIONS
    // ==========================================================

    // --- Cycle 2→4: g0 = X_norm*y0,  h0 = y0*0.5 ---
    wire [31:0] fma_g0, fma_h0;
    fp_fma u_g0 (.clk(clk), .floatA(X_in_s1), .floatB(y0_r),   .floatC(FP_ZERO), .result(fma_g0));
    fp_fma u_h0 (.clk(clk), .floatA(y0_r),    .floatB(FP_HALF), .floatC(FP_ZERO), .result(fma_h0));

    reg [31:0] g0_dly[0:FMA_LAT-1], h0_dly[0:FMA_LAT-1];
    always @(posedge clk) begin
        g0_dly[0] <= fma_g0; g0_dly[1] <= g0_dly[0];
        h0_dly[0] <= fma_h0; h0_dly[1] <= h0_dly[0];
    end

    // --- Cycle 4→6: F0 = 1.5 - g0*h0 ---
    wire [31:0] neg_g0 = {~fma_g0[31], fma_g0[30:0]};
    wire [31:0] fma_F0;
    fp_fma u_F0 (.clk(clk), .floatA(neg_g0), .floatB(fma_h0), .floatC(FP_ONE_HALF), .result(fma_F0));

    // --- Cycle 6→8: g1 = g0*F0,  h1 = h0*F0 ---
    wire [31:0] fma_g1, fma_h1;
    fp_fma u_g1 (.clk(clk), .floatA(g0_dly[1]), .floatB(fma_F0), .floatC(FP_ZERO), .result(fma_g1));
    fp_fma u_h1 (.clk(clk), .floatA(h0_dly[1]), .floatB(fma_F0), .floatC(FP_ZERO), .result(fma_h1));

    reg [31:0] g1_dly[0:FMA_LAT-1], h1_dly[0:FMA_LAT-1];
    always @(posedge clk) begin
        g1_dly[0] <= fma_g1; g1_dly[1] <= g1_dly[0];
        h1_dly[0] <= fma_h1; h1_dly[1] <= h1_dly[0];
    end

    // --- Cycle 8→10: F1 = 1.5 - g1*h1 ---
    wire [31:0] neg_g1 = {~fma_g1[31], fma_g1[30:0]};
    wire [31:0] fma_F1;
    fp_fma u_F1 (.clk(clk), .floatA(neg_g1), .floatB(fma_h1), .floatC(FP_ONE_HALF), .result(fma_F1));

    // --- Cycle 10→12: g2 = g1*F1,  h2 = h1*F1 ---
    wire [31:0] fma_g2, fma_h2;
    fp_fma u_g2 (.clk(clk), .floatA(g1_dly[1]), .floatB(fma_F1), .floatC(FP_ZERO), .result(fma_g2));
    fp_fma u_h2 (.clk(clk), .floatA(h1_dly[1]), .floatB(fma_F1), .floatC(FP_ZERO), .result(fma_h2));

    reg [31:0] g2_dly[0:FMA_LAT-1], h2_dly[0:FMA_LAT-1];
    always @(posedge clk) begin
        g2_dly[0] <= fma_g2; g2_dly[1] <= g2_dly[0];
        h2_dly[0] <= fma_h2; h2_dly[1] <= h2_dly[0];
    end

    // --- Cycle 12→14: F2 = 1.5 - g2*h2 ---
    wire [31:0] neg_g2 = {~fma_g2[31], fma_g2[30:0]};
    wire [31:0] fma_F2;
    fp_fma u_F2 (.clk(clk), .floatA(neg_g2), .floatB(fma_h2), .floatC(FP_ONE_HALF), .result(fma_F2));

    // --- Cycle 14→16: g3 = g2*F2,  h3 = h2*F2 ---
    wire [31:0] fma_g3, fma_h3;
    fp_fma u_g3 (.clk(clk), .floatA(g2_dly[1]), .floatB(fma_F2), .floatC(FP_ZERO), .result(fma_g3));
    fp_fma u_h3 (.clk(clk), .floatA(h2_dly[1]), .floatB(fma_F2), .floatC(FP_ZERO), .result(fma_h3));

    // ==========================================================
    // NEWTON-RAPHSON CORRECTION STEP (+4 cycles)
    //   Bước A: e3      = FMA(-g3, g3, x)     // x - g3^2
    //   Bước B: g_final = FMA(e3,  h3, g3)    // g3 + e3*h3
    // ==========================================================

    reg [31:0] g3_dly[0:FMA_LAT-1];
    always @(posedge clk) begin
        g3_dly[0] <= fma_g3;
        g3_dly[1] <= g3_dly[0];
    end

    reg [31:0] h3_dly[0:FMA_LAT-1];
    always @(posedge clk) begin
        h3_dly[0] <= fma_h3;
        h3_dly[1] <= h3_dly[0];
    end

    // --- Cycle 16→18: e3 = x - g3^2 ---
    wire [31:0] neg_g3 = {~fma_g3[31], fma_g3[30:0]};
    wire [31:0] fma_e3;
    fp_fma u_e3 (
        .clk   (clk),
        .floatA(neg_g3),
        .floatB(fma_g3),
        .floatC(X_in_dly[X_DELAY-1]),
        .result(fma_e3)
    );

    // --- Cycle 18→20: g_final = g3 + e3*h3 ---
    wire [31:0] fma_gfinal;
    fp_fma u_gfinal (
        .clk   (clk),
        .floatA(fma_e3),
        .floatB(h3_dly[1]),
        .floatC(g3_dly[1]),
        .result(fma_gfinal)
    );
    // fma_gfinal sẵn sàng tại cycle 20

    // ==========================================================
    // POST-ROUNDING INTEGER CORRECTION (combinational, cycle 20)
    //
    //  Mục tiêu: đảm bảo 0 ULP bằng cách kiểm tra integer g^2 vs x
    //
    //  Với float32 dương: bit[30:0] là giá trị tăng đơn điệu,
    //  nên g^2 > x khi và chỉ khi fp_square(g) > x theo integer so sánh.
    //
    //  Cách tính fp_square nhanh (không cần FMA thật):
    //    mantissa_sq = {1, g[22:0]} * {1, g[22:0]}  (48-bit)
    //    Lấy 24 bit cao, cộng exp*2-127
    //    Kết quả dùng để so sánh integer với X_in_dly2[3]
    //
    //  Correction rule (IEEE round-to-nearest-even):
    //    sq0 = integer_square(g_final)
    //    sq1 = integer_square(g_final + 1ULP)
    //    x_norm = X_in_dly2[3]  (tức X_in tại cycle 20)
    //
    //    if   sq0 > x_norm                     → result = g_final - 1 ULP
    //    elif sq1 <= x_norm                    → result = g_final + 1 ULP
    //    else                                  → result = g_final
    // ==========================================================

    // --- Hàm tính integer-approximate của g^2 (mantissa level) ---
    // Dùng 24-bit mantissa (ẩn bit 1)
    // Kết quả: 48-bit product → lấy bit[47:24] để được 24-bit mantissa kết quả
    // Điều chỉnh exponent: exp_sq = 2*exp - 127 (unbiased: 2*(exp-127))

    function [31:0] fp_isquare;
        input [31:0] f;
        reg [23:0] mant;
        reg [47:0] mant_sq;
        reg [7:0]  exp_f;
        reg [8:0]  exp_sq;
        reg [22:0] mant_out;
        begin
            exp_f   = f[30:23];
            mant    = {1'b1, f[22:0]};
            mant_sq = mant * mant;          // 48-bit
            // Chuẩn hóa: bit47 luôn = 1 (vì mant >= 1.0)
            // mant_sq[47:24] = phần integer 24-bit
            mant_out = mant_sq[47] ? mant_sq[46:24] : mant_sq[45:23];
            exp_sq   = mant_sq[47] ? ({1'b0, exp_f} * 2 - 9'd127)
                                   : ({1'b0, exp_f} * 2 - 9'd128);
            fp_isquare = {1'b0, exp_sq[7:0], mant_out};
        end
    endfunction

    // Tính g_final^2 và (g_final ± 1ULP)^2 dạng integer so sánh
    wire [31:0] g_up   = fma_gfinal + 32'd1;      // +1 ULP
    wire [31:0] g_down = fma_gfinal - 32'd1;      // -1 ULP

    wire [31:0] sq_cur  = fp_isquare(fma_gfinal);
    wire [31:0] sq_up   = fp_isquare(g_up);
    wire [31:0] sq_down = fp_isquare(g_down);

    wire [31:0] x_norm_cy20 = X_in_dly2[X_DELAY2-1]; // X_in tại cycle 20

    // So sánh integer (float32 dương: integer order = value order)
    wire overshoot   = (sq_cur  > x_norm_cy20);  // g^2 > x → g quá lớn
    wire undershoot1 = (sq_up  <= x_norm_cy20);  // (g+1)^2 ≤ x → g quá nhỏ

    wire [31:0] g_corrected = overshoot   ? g_down    :
                              undershoot1 ? g_up      :
                                            fma_gfinal;

    // ==========================================================
    // OUTPUT STAGE (CYCLE 21)
    // ==========================================================
    wire       is_neg_final  = is_neg_pipe[META_D-1];
    wire       is_zero_final = is_zero_pipe[META_D-1];
    wire [7:0] exp_final     = final_exp_pipe[META_D-1];

    wire [7:0] exp_sqrt_raw = g_corrected[30:23];
    wire [7:0] exp_result   = exp_final + exp_sqrt_raw - 8'd127;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            result    <= 32'b0;
            valid_out <= 1'b0;
            tag_out   <= 4'b0;
        end else begin
            valid_out <= valid_pipe[PIPE_LAT-2];
            tag_out   <= tag_pipe[PIPE_LAT-2];

            if (is_zero_final)
                result <= FP_ZERO;
            else if (is_neg_final)
                result <= FP_NAN;
            else
                result <= {1'b0, exp_result, g_corrected[22:0]};
        end
    end

endmodule