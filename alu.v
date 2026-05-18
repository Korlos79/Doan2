// =============================================================================
// Module : alu (Upgraded with Iterative MUL/DIV)
// Desc   : Tích hợp iter_mul32 và iter_div32 vào ALU gốc.
//          - Các phép toán cơ bản (ADD, SUB, SLL, ...) vẫn là combinational.
//          - Các phép MUL/DIV/REM là sequential, dùng tín hiệu start/done/tag.
// =============================================================================

module alu #(
    parameter TAG_WIDTH = 4
)(
    input  wire        clk,
    input  wire        rst_n,

    // --- Operands & Control ---
    input  wire [31:0] A,
    input  wire [31:0] B,
    input  wire [4:0]  opcode,
    input  wire [2:0]  branch,

    // --- Handshake cho MUL/DIV (sequential) ---
    input  wire [TAG_WIDTH-1:0]  tag_in,      // Tag định danh lệnh đầu vào

    // --- OUTPUTS ---
    // Kết quả combinational (ADD, SUB, logic...)
    output reg  [31:0] basic_result,
    // Cờ nhánh
    output reg         Z,

    // Kết quả sequential (MUL/DIV/REM) -- valid khi done = 1
    output wire [31:0]            mul_result,
    output wire                   mul_done,
    output wire [TAG_WIDTH-1:0]   mul_tag_out,

    output wire [31:0]            div_result,
    output wire                   div_done,
    output wire [TAG_WIDTH-1:0]   div_tag_out
);

    // =========================================================================
    // 1. OPCODE DEFINITIONS
    // =========================================================================
    // --- Combinational ALU ---
    localparam OP_ADD   = 5'd0;
    localparam OP_SLL   = 5'd1;
    localparam OP_SLT   = 5'd2;
    localparam OP_SLTU  = 5'd3;
    localparam OP_XOR   = 5'd4;
    localparam OP_SRL   = 5'd5;
    localparam OP_OR    = 5'd6;
    localparam OP_AND   = 5'd7;
    localparam OP_SUB   = 5'd8;
    localparam OP_SRA   = 5'd17;

    // --- MUL (iter_mul32) ---
    localparam OP_MUL    = 5'b10000;
    localparam OP_MULH   = 5'b10001;
    localparam OP_MULHSU = 5'b10010;
    localparam OP_MULHU  = 5'b10011;

    // --- DIV (iter_div32) ---
    localparam OP_DIV    = 5'b10100;
    localparam OP_DIVU   = 5'b10101;
    localparam OP_REM    = 5'b10110;
    localparam OP_REMU   = 5'b10111;

    // --- Branch ---
    localparam beq  = 3'b000;
    localparam bne  = 3'b001;
    localparam blt  = 3'b100;
    localparam bge  = 3'b101;
    localparam bltu = 3'b110;
    localparam bgeu = 3'b111;

    // =========================================================================
    // 2. IS_MUL / IS_DIV DECODE
    // =========================================================================
    wire is_mul = (opcode == OP_MUL)  | (opcode == OP_MULH) |
                  (opcode == OP_MULHSU)| (opcode == OP_MULHU);

    wire is_div = (opcode == OP_DIV)  | (opcode == OP_DIVU) |
                  (opcode == OP_REM)  | (opcode == OP_REMU);

    // =========================================================================
    // 3. INSTANTIATE iter_mul32
    // =========================================================================
    iter_mul32 #(
        .TAG_WIDTH(TAG_WIDTH)
    ) u_mul (
        .clk    (clk),
        .rst_n  (rst_n),
        .start  (is_mul),
        .op_sel (opcode),
        .tag_in (tag_in),
        .rs1    (A),
        .rs2    (B),
        .done   (mul_done),
        .tag_out(mul_tag_out),
        .result (mul_result)
    );

    // =========================================================================
    // 4. INSTANTIATE iter_div32
    // =========================================================================
    iter_div32 #(
        .TAG_WIDTH(TAG_WIDTH)
    ) u_div (
        .clk    (clk),
        .rst_n  (rst_n),
        .start  (is_div),
        .op_sel (opcode),
        .tag_in (tag_in),
        .rs1    (A),
        .rs2    (B),
        .done   (div_done),
        .tag_out(div_tag_out),
        .result (div_result)
    );

    // =========================================================================
    // 5. COMBINATIONAL ALU (phép toán ngay lập tức)
    // =========================================================================
    always @(*) begin
        case (opcode)
            OP_ADD:  basic_result = A + B;
            OP_SLL:  basic_result = A << B[4:0];
            OP_SLT:  basic_result = ($signed(A) < $signed(B)) ? 32'd1 : 32'd0;
            OP_SLTU: basic_result = (A < B)                   ? 32'd1 : 32'd0;
            OP_XOR:  basic_result = A ^ B;
            OP_SRL:  basic_result = A >> B[4:0];
            OP_OR:   basic_result = A | B;
            OP_AND:  basic_result = A & B;
            OP_SUB:  basic_result = A - B;
            OP_SRA:  basic_result = $signed(A) >>> B[4:0];
            // MUL/DIV không trả kết quả qua cổng này
            default: basic_result = 32'd0;
        endcase
    end

    // =========================================================================
    // 6. BRANCH COMPARATOR
    // =========================================================================
    always @(*) begin
        case (branch)
            beq:     Z = (A == B);
            bne:     Z = (A != B);
            blt:     Z = ($signed(A) < $signed(B));
            bge:     Z = ($signed(A) >= $signed(B));
            bltu:    Z = (A < B);
            bgeu:    Z = (A >= B);
            default: Z = 1'b0;
        endcase
    end

endmodule