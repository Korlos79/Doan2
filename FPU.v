// =============================================================================
//  FPU.v  –  Floating-Point Unit  (Pipeline Architecture)
//
//  Tương thích với các submodule pipeline:
//    • addition_subtraction  (4-cycle latency, valid_out, tag_in/tag_out)
//    • fp_mul                (3-cycle latency, valid_out, tag_in/tag_out)
//    • fp_div_goldschmidt    (13-cycle latency, valid_out, tag_in/tag_out)
//    • fp_sqrt_goldschmidt   (21-cycle latency, valid_out, tag_in/tag_out)
//
//  Chiến lược TAG:
//    tag_in đến từ bên ngoài (wrapper/RS), được truyền thẳng vào subunit.
//    Khi done=1, tag_out trả lại đúng tag của lệnh vừa hoàn thành.
//    FPU không tự tạo tag nữa — hoàn toàn trong suốt với hệ thống bên ngoài.
//
//  Lệnh FMADD/FMSUB/FNMADD/FNMSUB:
//    Bước 1 → fp_mul  (tag_in lưu trong fma_table)
//    Bước 2 → khi mul_valid, đẩy kết quả vào addition_subtraction
//             (tag giữ nguyên xuyên suốt cả 2 bước)
//
// =============================================================================

module FPU (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,
    input  wire [3:0]  tag_in,       // Tag từ RS/wrapper, truyền xuyên pipeline
    input  wire [31:0] a_operand,
    input  wire [31:0] b_operand,
    input  wire [31:0] c_operand,
    input  wire [4:0]  FPUOpd,
    output reg  [31:0] result,
    output reg  [3:0]  tag_out,      // Tag tương ứng với result khi done=1
    output reg         done,
    output reg         Exception
);

    // =========================================================================
    //  BẢNG OPCODE
    // =========================================================================
    localparam FADD     = 5'd0;
    localparam FSUB     = 5'd1;
    localparam FMUL     = 5'd2;
    localparam FDIV     = 5'd3;
    localparam FSQRT    = 5'd4;
    localparam FMADD    = 5'd5;
    localparam FMSUB    = 5'd6;
    localparam FNMADD   = 5'd7;
    localparam FNMSUB   = 5'd8;
    localparam FSGNJ    = 5'd9;
    localparam FSGNJN   = 5'd10;
    localparam FSGNJX   = 5'd11;
    localparam FEQ      = 5'd12;
    localparam FLT      = 5'd13;
    localparam FLE      = 5'd14;
    localparam FCVT_WS  = 5'd15;
    localparam FCVT_WSU = 5'd16;
    localparam FCVT_SW  = 5'd17;
    localparam FCVT_SWU = 5'd18;
    localparam FMV_XW   = 5'd19;
    localparam FMIN     = 5'd20;
    localparam FMAX     = 5'd21;
    localparam FMV_WX   = 5'd22;   // [FIX] FMV.W.X (Int→FP bit-cast) tách riêng khỏi FCVT_SW

    // =========================================================================
    //  COMPARE (dùng cho FEQ/FLT/FLE/FMIN/FMAX)
    // =========================================================================
    wire        a_sign = a_operand[31];
    wire        b_sign = b_operand[31];
    wire [30:0] a_abs  = a_operand[30:0];
    wire [30:0] b_abs  = b_operand[30:0];

    wire both_neg  = a_sign & b_sign;
    wire both_pos  = ~a_sign & ~b_sign;
    wire a_is_zero = (a_abs == 31'd0);
    wire b_is_zero = (b_abs == 31'd0);

    wire cmp_eq = (a_operand == b_operand) | (a_is_zero & b_is_zero);
    wire cmp_lt = (!cmp_eq) & (
                     (a_sign & !b_sign)           |
                     (both_pos & (a_abs < b_abs)) |
                     (both_neg & (a_abs > b_abs))
                  );
    wire cmp_le = cmp_lt | cmp_eq;

    // =========================================================================
    //  CONVERT HELPERS (combinational)
    // =========================================================================
    wire [31:0] cvt_sw_res, cvt_swu_res, cvt_ws_res, cvt_wsu_res;

    ConvfromSignInt CVT1 (a_operand, cvt_sw_res);
    ConvfromUnsInt  CVT2 (a_operand, cvt_swu_res);
    ConverttoInt    CVT3 (a_operand, cvt_ws_res);
    ConvertUnstoInt CVT4 (a_operand, cvt_wsu_res);

    // =========================================================================
    //  1. ADDITION / SUBTRACTION UNIT (4 chu kì)
    // =========================================================================
    reg  [31:0] add_a_r, add_b_r;
    reg         add_op_sub_r;
    reg         add_start_r;
    reg  [3:0]  add_tag_r;

    wire [31:0] add_result;
    wire        add_valid;
    wire [3:0]  add_tag_out;

    addition_subtraction ADD_UNIT (
        .clk      (clk),
        .rst_n    (rst_n),
        .start    (add_start_r),
        .tag_in   (add_tag_r),
        .op_sub   (add_op_sub_r),
        .a        (add_a_r),
        .b        (add_b_r),
        .out      (add_result),
        .valid_out(add_valid),
        .tag_out  (add_tag_out)
    );

    // =========================================================================
    //  2. MULTIPLY UNIT (3 chu kì)
    // =========================================================================
    reg  [31:0] mul_a_r, mul_b_r;
    reg         mul_start_r;
    reg  [3:0]  mul_tag_r;

    wire [31:0] mul_result;
    wire        mul_valid;
    wire [3:0]  mul_tag_out;

    fp_mul MUL_UNIT (
        .clk      (clk),
        .rst_n    (rst_n),
        .start    (mul_start_r),
        .tag_in   (mul_tag_r),
        .floatA   (mul_a_r),
        .floatB   (mul_b_r),
        .result   (mul_result),
        .valid_out(mul_valid),
        .tag_out  (mul_tag_out)
    );

    // =========================================================================
    //  3. DIVISION UNIT () (13 chu kì)
    // =========================================================================
    reg  [31:0] div_a_r, div_b_r;
    reg         div_start_r;
    reg  [3:0]  div_tag_r;

    wire [31:0] div_result;
    wire        div_valid;
    wire [3:0]  div_tag_out;

    fp_div_goldschmidt DIV_UNIT (
        .clk      (clk),
        .rst_n    (rst_n),
        .start    (div_start_r),
        .tag_in   (div_tag_r),
        .floatA   (div_a_r),
        .floatB   (div_b_r),
        .result   (div_result),
        .valid_out(div_valid),
        .tag_out  (div_tag_out)
    );

    // =========================================================================
    //  4. SQUARE ROOT UNIT (21 chu kì)
    // =========================================================================
    reg  [31:0] sqrt_a_r;
    reg         sqrt_start_r;
    reg  [3:0]  sqrt_tag_r;

    wire [31:0] sqrt_result;
    wire        sqrt_valid;
    wire [3:0]  sqrt_tag_out;

    fp_sqrt_goldschmidt SQRT_UNIT (
        .clk      (clk),
        .rst_n    (rst_n),
        .start    (sqrt_start_r),
        .tag_in   (sqrt_tag_r),
        .floatA   (sqrt_a_r),
        .result   (sqrt_result),
        .valid_out(sqrt_valid),
        .tag_out  (sqrt_tag_out)
    );

    // =========================================================================
    //  FMA TABLE
    //  Lưu thông tin lệnh FMA để sau khi mul xong thì đẩy sang adder.
    //  Index bằng tag_in (4-bit, 16 entry, tag=0 không dùng).
    // =========================================================================
    reg [4:0]  fma_op_tbl   [0:15];
    reg [31:0] fma_c_tbl    [0:15];
    reg        fma_valid_tbl[0:15];

    integer idx;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (idx = 0; idx <= 15; idx = idx + 1) begin
                fma_op_tbl[idx]    <= 5'd0;
                fma_c_tbl[idx]     <= 32'd0;
                fma_valid_tbl[idx] <= 1'b0;
            end
        end else begin
            // Ghi entry khi bắt đầu lệnh FMA — index bằng tag_in từ bên ngoài
            if (start && (FPUOpd == FMADD || FPUOpd == FMSUB ||
                          FPUOpd == FNMADD || FPUOpd == FNMSUB)) begin
                fma_op_tbl[tag_in]    <= FPUOpd;
                fma_c_tbl[tag_in]     <= c_operand;
                fma_valid_tbl[tag_in] <= 1'b1;
            end
            // Xóa entry khi mul xong và đã đẩy sang adder
            if (mul_valid && fma_valid_tbl[mul_tag_out]) begin
                fma_valid_tbl[mul_tag_out] <= 1'b0;
            end
        end
    end

    // =========================================================================
    //  DISPATCH LOGIC
    // =========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            add_start_r  <= 0; add_a_r <= 0; add_b_r <= 0;
            add_op_sub_r <= 0; add_tag_r <= 0;
            mul_start_r  <= 0; mul_a_r <= 0; mul_b_r <= 0; mul_tag_r <= 0;
            div_start_r  <= 0; div_a_r <= 0; div_b_r <= 0; div_tag_r <= 0;
            sqrt_start_r <= 0; sqrt_a_r <= 0; sqrt_tag_r <= 0;
            done      <= 0;
            tag_out   <= 0;
            result    <= 0;
            Exception <= 0;
        end else begin
            // Mặc định: xung 1 chu kỳ
            add_start_r  <= 0;
            mul_start_r  <= 0;
            div_start_r  <= 0;
            sqrt_start_r <= 0;
            done         <= 0;
            tag_out      <= 0;
            Exception    <= 0;

            // ------------------------------------------------------------------
            //  A. Kết quả từ các pipeline unit → ghi result + tag_out + done
            // ------------------------------------------------------------------

            if (add_valid) begin
                result    <= add_result;
                tag_out   <= add_tag_out;
                Exception <= 1'b0;
                done      <= 1'b1;
            end

            if (mul_valid) begin
                if (fma_valid_tbl[mul_tag_out]) begin
                    // FMA bước 2: chuyển sang adder, giữ nguyên tag
                    add_start_r  <= 1'b1;
                    add_tag_r    <= mul_tag_out;
                    add_a_r      <= (fma_op_tbl[mul_tag_out] == FNMADD ||
                                     fma_op_tbl[mul_tag_out] == FNMSUB)
                                    ? {~mul_result[31], mul_result[30:0]}
                                    : mul_result;
                    add_b_r      <= fma_c_tbl[mul_tag_out];
                    add_op_sub_r <= (fma_op_tbl[mul_tag_out] == FMSUB ||
                                     fma_op_tbl[mul_tag_out] == FNMADD);
                end else begin
                    // FMUL thuần
                    result    <= mul_result;
                    tag_out   <= mul_tag_out;
                    Exception <= 1'b0;
                    done      <= 1'b1;
                end
            end

            if (div_valid) begin
                result    <= div_result;
                tag_out   <= div_tag_out;
                Exception <= 1'b0;
                done      <= 1'b1;
            end

            if (sqrt_valid) begin
                result    <= sqrt_result;
                tag_out   <= sqrt_tag_out;
                Exception <= (sqrt_result[30:23] == 8'hFF); // NaN khi input âm
                done      <= 1'b1;
            end

            // ------------------------------------------------------------------
            //  B. Dispatch lệnh mới — dùng tag_in trực tiếp
            // ------------------------------------------------------------------
            if (start) begin
                case (FPUOpd)

                    FADD: begin
                        add_start_r  <= 1'b1;
                        add_tag_r    <= tag_in;
                        add_a_r      <= a_operand;
                        add_b_r      <= b_operand;
                        add_op_sub_r <= 1'b0;
                    end

                    FSUB: begin
                        add_start_r  <= 1'b1;
                        add_tag_r    <= tag_in;
                        add_a_r      <= a_operand;
                        add_b_r      <= b_operand;
                        add_op_sub_r <= 1'b1;
                    end

                    FMUL: begin
                        mul_start_r <= 1'b1;
                        mul_tag_r   <= tag_in;
                        mul_a_r     <= a_operand;
                        mul_b_r     <= b_operand;
                    end

                    FDIV: begin
                        div_start_r <= 1'b1;
                        div_tag_r   <= tag_in;
                        div_a_r     <= a_operand;
                        div_b_r     <= b_operand;
                    end

                    FSQRT: begin
                        sqrt_start_r <= 1'b1;
                        sqrt_tag_r   <= tag_in;
                        sqrt_a_r     <= a_operand;
                    end

                    FMADD, FMSUB, FNMADD, FNMSUB: begin
                        // Bước 1: nhân a × b, mang tag_in theo
                        mul_start_r <= 1'b1;
                        mul_tag_r   <= tag_in;
                        mul_a_r     <= a_operand;
                        mul_b_r     <= b_operand;
                        // Bước 2 tự động kích hoạt khi mul_valid (xem phần A)
                    end

                    // ----------------------------------------------------------
                    //  Lệnh tức thì: done ngay chu kỳ hiện tại, tag_out = tag_in
                    // ----------------------------------------------------------
                    FSGNJ: begin
                        result  <= {b_operand[31], a_operand[30:0]};
                        tag_out <= tag_in; done <= 1'b1;
                    end
                    FSGNJN: begin
                        result  <= {~b_operand[31], a_operand[30:0]};
                        tag_out <= tag_in; done <= 1'b1;
                    end
                    FSGNJX: begin
                        result  <= {a_operand[31] ^ b_operand[31], a_operand[30:0]};
                        tag_out <= tag_in; done <= 1'b1;
                    end
                    FEQ: begin
                        result  <= {31'd0, cmp_eq};
                        tag_out <= tag_in; done <= 1'b1;
                    end
                    FLT: begin
                        result  <= {31'd0, cmp_lt};
                        tag_out <= tag_in; done <= 1'b1;
                    end
                    FLE: begin
                        result  <= {31'd0, cmp_le};
                        tag_out <= tag_in; done <= 1'b1;
                    end
                    FCVT_SW: begin
                        result  <= cvt_sw_res;
                        tag_out <= tag_in; done <= 1'b1;
                    end
                    FCVT_SWU: begin
                        result  <= cvt_swu_res;
                        tag_out <= tag_in; done <= 1'b1;
                    end
                    FCVT_WS: begin
                        result  <= cvt_ws_res;
                        tag_out <= tag_in; done <= 1'b1;
                    end
                    FCVT_WSU: begin
                        result  <= cvt_wsu_res;
                        tag_out <= tag_in; done <= 1'b1;
                    end
                    FMV_XW: begin
                        result  <= a_operand;   // bit-cast FP→Int
                        tag_out <= tag_in; done <= 1'b1;
                    end
                    FMV_WX: begin
                        result  <= a_operand;   // bit-cast Int→FP (giá trị bits không đổi)
                        tag_out <= tag_in; done <= 1'b1;
                    end
                    FMIN: begin
                        result  <= cmp_lt ? a_operand : b_operand;
                        tag_out <= tag_in; done <= 1'b1;
                    end
                    FMAX: begin
                        result  <= cmp_lt ? b_operand : a_operand;
                        tag_out <= tag_in; done <= 1'b1;
                    end
                    default: begin
                        result  <= 32'd0;
                        tag_out <= tag_in; done <= 1'b1;
                    end
                endcase
            end
        end
    end

endmodule