module fu_alu_wrapper #(
    parameter DATA_WIDTH = 32,
    parameter TAG_WIDTH  = 4
)(
    input wire clk,
    input wire rst_n,

    // --- GIAO DIỆN VỚI RESERVATION STATION ---
    input  wire                  start,
    input  wire [4:0]            opcode,
    input  wire [31:0]           op1, op2,
    input  wire [TAG_WIDTH-1:0]  tag_in,

    input  wire [31:0]           pc, imm,
    input  wire                  MuxjalrD,
    input  wire                  JumpD,
    input  wire                  BranchD,

    // --- GIAO DIỆN VỚI CDB ---
    output reg                   cdb_valid,
    output reg  [DATA_WIDTH-1:0] cdb_result,
    output reg  [TAG_WIDTH-1:0]  cdb_tag,
    output reg                   cdb_branch_taken,
    output reg  [31:0]           cdb_branch_target
);

    // =========================================================================
    // 1. PHÂN LOẠI OPCODE
    // =========================================================================
    wire is_mul  = (opcode[4:2] == 3'b100) && !opcode[3];  // 5'b10000–5'b10011
    wire is_div  = (opcode[4:3] == 2'b10)  &&  opcode[2];  // 5'b10100–5'b10111
    wire is_md   = is_mul | is_div;
    wire is_base = !is_md;

    // =========================================================================
    // 2. BRANCH DECODE
    // =========================================================================
    wire [2:0] branch_sel = BranchD ? opcode[2:0] : 3'b000;

    // =========================================================================
    // 3. ALU CORE
    // =========================================================================
    wire [31:0]          alu_basic_res;
    wire                 alu_z_w;
    wire [31:0]          mul_result_w;
    wire                 mul_done_w;
    wire [TAG_WIDTH-1:0] mul_tag_out_w;
    wire [31:0]          div_result_w;
    wire                 div_done_w;
    wire [TAG_WIDTH-1:0] div_tag_out_w;

    alu #(.TAG_WIDTH(TAG_WIDTH)) ALU_CORE (
        .clk        (clk),
        .rst_n      (rst_n),
        .A          (op1),
        .B          (op2),
        .opcode     (opcode),
        .branch     (branch_sel),
        .start      (start),
        .tag_in     (tag_in),
        .alu_result (alu_basic_res),
        .Z          (alu_z_w),
        .mul_result (mul_result_w),
        .mul_done   (mul_done_w),
        .mul_tag_out(mul_tag_out_w),
        .div_result (div_result_w),
        .div_done   (div_done_w),
        .div_tag_out(div_tag_out_w)
    );

    // =========================================================================
    // 4. LUỒNG CƠ BẢN — chốt kết quả 1 chu kỳ rồi lên CDB ngay
    // =========================================================================
    wire [31:0] next_pc      = MuxjalrD ? ((op1 + imm) & 32'hFFFF_FFFE) : (pc + imm);
    wire        actual_taken = JumpD | (BranchD & alu_z_w);

    reg                  base_valid;
    reg [TAG_WIDTH-1:0]  base_tag;
    reg [31:0]           base_res;
    reg                  base_taken;
    reg [31:0]           base_target;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            base_valid <= 0;
        end else begin
            base_valid  <= start & is_base;
            base_tag    <= tag_in;
            base_res    <= alu_basic_res;
            base_taken  <= actual_taken;
            base_target <= next_pc;
        end
    end

    // =========================================================================
    // 5. CDB MUX — Ưu tiên MUL/DIV done > base
    // =========================================================================
    wire        md_done_any = mul_done_w | div_done_w;
    wire [31:0] md_res_any  = mul_done_w ? mul_result_w : div_result_w;
    wire [TAG_WIDTH-1:0] md_tag_any = mul_done_w ? mul_tag_out_w : div_tag_out_w;

    always @(*) begin
        cdb_valid         = 0;
        cdb_result        = 0;
        cdb_tag           = 0;
        cdb_branch_taken  = 0;
        cdb_branch_target = 0;

        if (md_done_any) begin
            cdb_valid  = 1;
            cdb_result = md_res_any;
            cdb_tag    = md_tag_any;
        end else if (base_valid) begin
            cdb_valid         = 1;
            cdb_result        = base_res;
            cdb_tag           = base_tag;
            cdb_branch_taken  = base_taken;
            cdb_branch_target = base_target;
        end
    end

endmodule