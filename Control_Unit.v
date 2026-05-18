// =============================================================================
// decoder.v  —  RV32IFM Instruction Decoder for Out-of-Order Pipeline
//
// Chức năng:
//   Giải mã lệnh RV32IFM thành các tín hiệu điều khiển:
//     • Loại lệnh (INT / FP / LOAD / STORE / BRANCH / JAL / JALR / LUI / AUIPC)
//     • Unit đích: ALU, FPU, LSU
//     • Opcode gửi vào từng unit
//     • Địa chỉ thanh ghi nguồn / đích (architectural)
//     • Immediate (đã sign-extend)
//     • Cờ sử dụng rs1, rs2, rs3, rd
//     • Cờ lệnh float (dùng FP register file)
// =============================================================================

module Control_Unit (
    input  wire [31:0] inst,
    input  wire [31:0] pc,          // PC của lệnh này (dùng cho AUIPC, JAL, JALR)

    // -------------------------------------------------------------------------
    // Destination / Source Registers (Architectural)
    // -------------------------------------------------------------------------
    output wire [4:0]  rd,
    output wire [4:0]  rs1,
    output wire [4:0]  rs2,
    output wire [4:0]  rs3,         // Chỉ dùng cho FMADD/FMSUB/FNMADD/FNMSUB

    // -------------------------------------------------------------------------
    // Immediate
    // -------------------------------------------------------------------------
    output wire [31:0] imm,

    // -------------------------------------------------------------------------
    // Source usage flags
    // -------------------------------------------------------------------------
    output wire        use_rs1,
    output wire        use_rs2,
    output wire        use_rs3,
    output wire        use_rd,

    // -------------------------------------------------------------------------
    // Float flags — dùng FP RAT & FP PRF thay vì Int
    // -------------------------------------------------------------------------
    output wire        fp_rs1,      // rs1 lấy từ FP PRF
    output wire        fp_rs2,      // rs2 lấy từ FP PRF
    output wire        fp_rs3,      // rs3 lấy từ FP PRF
    output wire        fp_rd,       // rd ghi vào FP PRF

    // -------------------------------------------------------------------------
    // Functional Unit chọn (one-hot)
    // -------------------------------------------------------------------------
    output wire        to_alu,
    output wire        to_fpu,
    output wire        to_lsu,

    // -------------------------------------------------------------------------
    // Opcode gửi vào từng unit
    // -------------------------------------------------------------------------
    output wire [4:0]  alu_op,      // Khớp với alu.v opcode
    output wire [4:0]  fpu_op,      // Khớp với FPU.v FPUOpd
    output wire [2:0]  lsu_op,      // {is_store, funct3[1:0]} hoặc mode

    // -------------------------------------------------------------------------
    // Loại lệnh đặc biệt
    // -------------------------------------------------------------------------
    output wire        is_branch,
    output wire        is_jal,
    output wire        is_jalr,
    output wire        is_lui,
    output wire        is_auipc,
    output wire        is_load,
    output wire        is_store,
    output wire        is_fp_load,  // FLW
    output wire        is_fp_store, // FSW

    // -------------------------------------------------------------------------
    // Branch function code (gửi sang ALU branch comparator)
    // -------------------------------------------------------------------------
    output wire [2:0]  branch_op,

    // -------------------------------------------------------------------------
    // Lệnh hợp lệ
    // -------------------------------------------------------------------------
    output wire        valid
);

    // =========================================================================
    // Trích trường
    // =========================================================================
    wire [6:0] opcode7  = inst[6:0];
    wire [2:0] funct3   = inst[14:12];
    wire [6:0] funct7   = inst[31:25];
    wire [4:0] funct5   = inst[31:27];   // Cho F-ext (rm field không dùng ở đây)

    assign rd   = inst[11:7];
    assign rs1  = inst[19:15];
    assign rs2  = inst[24:20];
    assign rs3  = inst[31:27];  // R4-type (FMADD...)

    // =========================================================================
    // Immediate decode (sign-extended 32-bit)
    // =========================================================================
    wire [31:0] imm_i = {{20{inst[31]}}, inst[31:20]};
    wire [31:0] imm_s = {{20{inst[31]}}, inst[31:25], inst[11:7]};
    wire [31:0] imm_b = {{19{inst[31]}}, inst[31], inst[7],
                          inst[30:25], inst[11:8], 1'b0};
    wire [31:0] imm_u = {inst[31:12], 12'b0};
    wire [31:0] imm_j = {{11{inst[31]}}, inst[31], inst[19:12],
                          inst[20], inst[30:21], 1'b0};

    // =========================================================================
    // Opcode constants
    // =========================================================================
    localparam OP_LUI    = 7'b0110111;
    localparam OP_AUIPC  = 7'b0010111;
    localparam OP_JAL    = 7'b1101111;
    localparam OP_JALR   = 7'b1100111;
    localparam OP_BRANCH = 7'b1100011;
    localparam OP_LOAD   = 7'b0000011;
    localparam OP_STORE  = 7'b0100011;
    localparam OP_ALUI   = 7'b0010011;  // ALU Immediate
    localparam OP_ALUR   = 7'b0110011;  // ALU Register / MUL / DIV
    localparam OP_FLW    = 7'b0000111;
    localparam OP_FSW    = 7'b0100111;
    localparam OP_FMADD  = 7'b1000011;
    localparam OP_FMSUB  = 7'b1000111;
    localparam OP_FNMSUB = 7'b1001011;
    localparam OP_FNMADD = 7'b1001111;
    localparam OP_FP     = 7'b1010011;  // Tất cả F-ext arithmetic

    // =========================================================================
    // Phân loại opcode7
    // =========================================================================
    assign is_lui    = (opcode7 == OP_LUI);
    assign is_auipc  = (opcode7 == OP_AUIPC);
    assign is_jal    = (opcode7 == OP_JAL);
    assign is_jalr   = (opcode7 == OP_JALR);
    assign is_branch = (opcode7 == OP_BRANCH);
    assign is_load   = (opcode7 == OP_LOAD);
    assign is_store  = (opcode7 == OP_STORE);
    assign is_fp_load  = (opcode7 == OP_FLW);
    assign is_fp_store = (opcode7 == OP_FSW);

    wire is_alui = (opcode7 == OP_ALUI);
    wire is_alur = (opcode7 == OP_ALUR);
    wire is_fmadd_t  = (opcode7 == OP_FMADD);
    wire is_fmsub_t  = (opcode7 == OP_FMSUB);
    wire is_fnmsub_t = (opcode7 == OP_FNMSUB);
    wire is_fnmadd_t = (opcode7 == OP_FNMADD);
    wire is_fp_r4    = is_fmadd_t | is_fmsub_t | is_fnmsub_t | is_fnmadd_t;
    wire is_fp_arith = (opcode7 == OP_FP);

    // MUL/DIV extension (funct7 = 0000001)
    wire is_muldiv = is_alur && (funct7 == 7'b0000001);

    // =========================================================================
    // Immediate select
    // =========================================================================
    assign imm = is_load || is_jalr || is_alui || is_fp_load ? imm_i :
                 is_store || is_fp_store                      ? imm_s :
                 is_branch                                    ? imm_b :
                 is_lui || is_auipc                           ? imm_u :
                 is_jal                                       ? imm_j :
                                                                32'd0;

    // =========================================================================
    // Functional Unit routing
    // =========================================================================
    assign to_fpu = is_fp_r4 | is_fp_arith | is_fp_load | is_fp_store;
    assign to_lsu = is_load | is_store | is_fp_load | is_fp_store;
    // Lưu ý: load/store dùng LSU nhưng FP load/store cũng cần FPU PRF
    assign to_alu = ~to_fpu & ~to_lsu;

    // =========================================================================
    // Float register file flags
    // =========================================================================
    // FP arithmetic: cả rs1, rs2 (rs3 nếu R4), rd đều là FP reg
    // FLW: rd là FP, rs1 là Int (base addr)
    // FSW: rs2 là FP (data), rs1 là Int
    // FCVT.W.S / FMV.X.W: rs1 là FP, rd là Int
    // FCVT.S.W / FMV.W.X: rs1 là Int, rd là FP

    // Phân loại FP opcode chi tiết
    wire fcvt_to_int = is_fp_arith && (funct5 == 5'b11000 || funct5 == 5'b11100);
                       // FCVT.W.S, FCVT.WU.S, FMV.X.W
    wire fcvt_to_fp  = is_fp_arith && (funct5 == 5'b11010 || funct5 == 5'b11110);
                       // FCVT.S.W, FCVT.S.WU, FMV.W.X
    wire fclass      = is_fp_arith && (funct5 == 5'b11100) && (funct3 == 3'b001);
    wire fcmp        = is_fp_arith && (funct5 == 5'b10100);

    assign fp_rs1 = (is_fp_arith && !fcvt_to_fp) | is_fp_r4 | is_fp_store;
    assign fp_rs2 = (is_fp_arith && !fcvt_to_int && !fcvt_to_fp && !fclass &&
                     funct5 != 5'b01011) | is_fp_r4;  // trừ FSQRT
    assign fp_rs3 = is_fp_r4;
    assign fp_rd  = (is_fp_arith && !fcvt_to_int) | is_fp_r4 | is_fp_load;

    // =========================================================================
    // Source / Destination usage
    // =========================================================================
    assign use_rd  = (rd != 5'd0) && !is_branch && !is_store && !is_fp_store;
    assign use_rs1 = !is_lui && !is_auipc && !is_jal;
    assign use_rs2 = is_alur | is_branch | is_store | is_fp_store |
                     is_fp_r4 | (is_fp_arith && !fcvt_to_int && !fcvt_to_fp && !fclass &&
                                  funct5 != 5'b01011);
    assign use_rs3 = is_fp_r4;

    // =========================================================================
    // Branch operation code (khớp với alu.v branch comparator)
    // =========================================================================
    assign branch_op = funct3;  // BEQ=000, BNE=001, BLT=100, BGE=101, BLTU=110, BGEU=111

    // =========================================================================
    // ALU opcode (khớp với alu.v localparam)
    // Ánh xạ:
    //   ADD=0, SLL=1, SLT=2, SLTU=3, XOR=4, SRL=5, OR=6, AND=7
    //   SUB=8, SRA=17
    //   MUL=16, MULH=17(conflict!→use funct3)
    // Dùng {funct7[5], funct3} làm key chính
    // =========================================================================
    reg [4:0] alu_op_r;
    always @(*) begin
        if (is_lui || is_auipc || is_jal || is_jalr) begin
            alu_op_r = 5'd0;    // ADD (kết quả từ adder, imm+pc hoặc imm+0)
        end else if (is_branch || is_load || is_store) begin
            alu_op_r = 5'd0;    // ADD (tính địa chỉ)
        end else if (is_alui) begin
            case (funct3)
                3'b000: alu_op_r = 5'd0;    // ADDI
                3'b001: alu_op_r = 5'd1;    // SLLI
                3'b010: alu_op_r = 5'd2;    // SLTI
                3'b011: alu_op_r = 5'd3;    // SLTIU
                3'b100: alu_op_r = 5'd4;    // XORI
                3'b101: alu_op_r = funct7[5] ? 5'd17 : 5'd5; // SRAI / SRLI
                3'b110: alu_op_r = 5'd6;    // ORI
                3'b111: alu_op_r = 5'd7;    // ANDI
                default: alu_op_r = 5'd0;
            endcase
        end else if (is_muldiv) begin
            // MUL=16..19, DIV=20..23
            alu_op_r = {2'b10, funct3};
        end else if (is_alur) begin
            case ({funct7[5], funct3})
                4'b0_000: alu_op_r = 5'd0;   // ADD
                4'b1_000: alu_op_r = 5'd8;   // SUB
                4'b0_001: alu_op_r = 5'd1;   // SLL
                4'b0_010: alu_op_r = 5'd2;   // SLT
                4'b0_011: alu_op_r = 5'd3;   // SLTU
                4'b0_100: alu_op_r = 5'd4;   // XOR
                4'b0_101: alu_op_r = 5'd5;   // SRL
                4'b1_101: alu_op_r = 5'd17;  // SRA
                4'b0_110: alu_op_r = 5'd6;   // OR
                4'b0_111: alu_op_r = 5'd7;   // AND
                default:  alu_op_r = 5'd0;
            endcase
        end else begin
            alu_op_r = 5'd0;
        end
    end
    assign alu_op = alu_op_r;

    // =========================================================================
    // FPU opcode (khớp với FPU.v localparam)
    //   FADD=0, FSUB=1, FMUL=2, FDIV=3, FSQRT=4
    //   FMADD=5, FMSUB=6, FNMADD=7, FNMSUB=8
    //   FSGNJ=9..11, FEQ=12, FLT=13, FLE=14
    //   FCVT_WS=15..18, FMV_XW=19, FMIN=20, FMAX=21
    // =========================================================================
    reg [4:0] fpu_op_r;
    always @(*) begin
        if (is_fmadd_t)       fpu_op_r = 5'd5;
        else if (is_fmsub_t)  fpu_op_r = 5'd6;
        else if (is_fnmadd_t) fpu_op_r = 5'd7;
        else if (is_fnmsub_t) fpu_op_r = 5'd8;
        else if (is_fp_arith) begin
            case (funct5)
                5'b00000: fpu_op_r = 5'd0;   // FADD
                5'b00001: fpu_op_r = 5'd1;   // FSUB
                5'b00010: fpu_op_r = 5'd2;   // FMUL
                5'b00011: fpu_op_r = 5'd3;   // FDIV
                5'b01011: fpu_op_r = 5'd4;   // FSQRT
                5'b00100: begin               // FSGNJ/FSGNJN/FSGNJX
                    case (funct3)
                        3'b000: fpu_op_r = 5'd9;
                        3'b001: fpu_op_r = 5'd10;
                        3'b010: fpu_op_r = 5'd11;
                        default: fpu_op_r = 5'd9;
                    endcase
                end
                5'b00101: fpu_op_r = (funct3==3'b000) ? 5'd20 : 5'd21; // FMIN/FMAX
                5'b10100: begin               // FEQ/FLT/FLE
                    case (funct3)
                        3'b010: fpu_op_r = 5'd12;
                        3'b001: fpu_op_r = 5'd13;
                        3'b000: fpu_op_r = 5'd14;
                        default: fpu_op_r = 5'd12;
                    endcase
                end
                5'b11000: fpu_op_r = (inst[20]) ? 5'd16 : 5'd15; // FCVT.W.S / FCVT.WU.S
                5'b11010: fpu_op_r = (inst[20]) ? 5'd18 : 5'd17; // FCVT.S.W / FCVT.S.WU
                5'b11100: fpu_op_r = 5'd19;   // FMV.X.W
                5'b11110: fpu_op_r = 5'd17;   // FMV.W.X → dùng FCVT_SW slot
                default:  fpu_op_r = 5'd0;
            endcase
        end else begin
            fpu_op_r = 5'd0;
        end
    end
    assign fpu_op = fpu_op_r;

    // =========================================================================
    // LSU opcode: {is_store, funct3}
    // funct3: LB=000, LH=001, LW=010, LBU=100, LHU=101
    //         SB=000, SH=001, SW=010
    // =========================================================================
    assign lsu_op = {(is_store | is_fp_store), funct3[1:0]};

    // =========================================================================
    // Valid
    // =========================================================================
    assign valid = (opcode7 != 7'b0000000) && (inst != 32'b0);

endmodule