module dispatch_unit #(
    parameter TAG_WIDTH = 4 // Đồng bộ với RAT và ROB
)(
    input wire [31:0] rdata1,       
    input wire [31:0] rdata2,
    input wire [31:0] frdata1,      
    input wire [31:0] frdata2,
    input wire [31:0] frdata3,
    
    input wire [31:0] pc,
    input wire [31:0] imm,

    // ---> BỔ SUNG: Nhận OpD từ Control Unit <---
    input wire [4:0]  op_d_in,      

    input wire [1:0]  alusrc_a,     
    input wire [1:0]  alusrc_b,     
    input wire        src1_is_float,
    input wire        src2_is_float,
    input wire        src3_is_float,
    
    input wire        muxjalr_in,
    input wire        jump_in,
    input wire        branch_in,

    input wire        decode_valid, 
    input wire        is_alu_inst,  
    input wire        is_fpu_inst,  
    input wire        is_lsu_inst,  

    input wire        rob_full,
    input wire        rs_alu_full,
    input wire        rs_fpu_full,
    input wire        rs_lsu_full,
    
    input wire        rob_flush,

    input wire                  int_rs1_ready, input wire [TAG_WIDTH-1:0] int_rs1_tag,
    input wire                  int_rs2_ready, input wire [TAG_WIDTH-1:0] int_rs2_tag,
    
    input wire                  float_rs1_ready, input wire [TAG_WIDTH-1:0] float_rs1_tag,
    input wire                  float_rs2_ready, input wire [TAG_WIDTH-1:0] float_rs2_tag,
    input wire                  float_rs3_ready, input wire [TAG_WIDTH-1:0] float_rs3_tag,

    output reg [31:0]           disp_op1_val, 
    output reg [TAG_WIDTH-1:0]  disp_op1_tag, 
    output reg                  disp_op1_ready,

    output reg [31:0]           disp_op2_val,
    output reg [TAG_WIDTH-1:0]  disp_op2_tag,
    output reg                  disp_op2_ready,
    
    output reg [31:0]           disp_op3_val,
    output reg [TAG_WIDTH-1:0]  disp_op3_tag,
    output reg                  disp_op3_ready,
    
    // ---> BỔ SUNG: Truyền OpD xuống các RS <---
    output wire [4:0]           disp_op_d,      
    
    output wire                 disp_muxjalr,
    output wire                 disp_jump,
    output wire                 disp_branch,
    output wire [31:0]          disp_pc,     
    output wire [31:0]          disp_imm,     

    output wire                 dispatch_en_alu,
    output wire                 dispatch_en_fpu,
    output wire                 dispatch_en_lsu,
    
    output wire                 dispatch_stall  
);

    // ==========================================
    // 0. PASS-THROUGH LOGIC CHO CONTROL SIGNALS
    // ==========================================
    assign disp_op_d    = op_d_in;    // Truyền Opcode 5-bit
    assign disp_muxjalr = muxjalr_in;
    assign disp_jump    = jump_in;
    assign disp_branch  = branch_in;
    assign disp_pc      = pc;
    assign disp_imm     = imm; 

    // ==========================================
    // 1. LOGIC TOÁN HẠNG 1
    // ==========================================
    always @(*) begin
        case (alusrc_a)
            2'b00: begin // Chọn Register
                disp_op1_val = src1_is_float ? frdata1 : rdata1;

                if (src1_is_float) begin
                    disp_op1_ready = float_rs1_ready;
                    disp_op1_tag   = float_rs1_tag;
                end else begin
                    disp_op1_ready = int_rs1_ready;
                    disp_op1_tag   = int_rs1_tag;
                end

                if (!disp_op1_ready) begin
                    disp_op1_val = 32'd0;
                end
            end
            
            2'b01: begin // Chọn PC
                disp_op1_val   = pc;
                disp_op1_ready = 1'b1;
                disp_op1_tag   = {TAG_WIDTH{1'b0}}; 
            end
            
            2'b10: begin // Chọn rs1 cho lệnh JALR/LUI
                disp_op1_val   = rdata1; 
                disp_op1_ready = int_rs1_ready;
                disp_op1_tag   = int_rs1_tag;
            end
            
            default: begin
                disp_op1_val   = 32'd0;
                disp_op1_ready = 1'b1;
                disp_op1_tag   = {TAG_WIDTH{1'b0}};
            end
        endcase
    end

    // ==========================================
    // 2. LOGIC TOÁN HẠNG 2
    // ==========================================
    always @(*) begin
        case (alusrc_b)
            2'b00: begin // Chọn Register
                disp_op2_val = src2_is_float ? frdata2 : rdata2;

                if (src2_is_float) begin
                    disp_op2_ready = float_rs2_ready;
                    disp_op2_tag   = float_rs2_tag;
                end else begin
                    disp_op2_ready = int_rs2_ready;
                    disp_op2_tag   = int_rs2_tag;
                end

                if (!disp_op2_ready) disp_op2_val = 32'd0;
            end
            
            2'b01: begin // Chọn Immediate
                disp_op2_val   = imm;
                disp_op2_ready = 1'b1;
                disp_op2_tag   = {TAG_WIDTH{1'b0}};
            end
            
            2'b10: begin // Chọn Constant 4 (Cho JAL/JALR để tính PC+4)
                disp_op2_val   = 32'd4;
                disp_op2_ready = 1'b1;
                disp_op2_tag   = {TAG_WIDTH{1'b0}};
            end

            default: begin
                disp_op2_val   = 32'd0;
                disp_op2_ready = 1'b1;
                disp_op2_tag   = {TAG_WIDTH{1'b0}};
            end
        endcase
    end

    // ==========================================
    // 3. LOGIC TOÁN HẠNG 3 (Chỉ dành cho Float FMA)
    // ==========================================
    always @(*) begin
        if (src3_is_float) begin
            disp_op3_val   = frdata3;
            disp_op3_ready = float_rs3_ready;
            disp_op3_tag   = float_rs3_tag;

            if (!disp_op3_ready) disp_op3_val = 32'd0;
        end else begin
            disp_op3_val   = 32'd0;
            disp_op3_ready = 1'b1;
            disp_op3_tag   = {TAG_WIDTH{1'b0}};
        end
    end

    // ==========================================
    // 4. STEERING LOGIC (Logic Điều phối)
    // ==========================================
    
    // Lệnh chỉ được phép đi tiếp nếu: Hợp lệ VÀ ROB chưa đầy VÀ Không bị xả (Flush)
    wire can_issue_base = decode_valid && !rob_full && !rob_flush;

    // Phân phát lệnh vào đúng trạm (RS) tương ứng.
    assign dispatch_en_alu = can_issue_base && is_alu_inst && !rs_alu_full;
    assign dispatch_en_fpu = can_issue_base && is_fpu_inst && !rs_fpu_full;
    assign dispatch_en_lsu = can_issue_base && is_lsu_inst && !rs_lsu_full;

    // Logic chặn (Stall) luồng lệnh ở Front-End.
    assign dispatch_stall = decode_valid && !rob_flush && (
        rob_full || 
        (is_alu_inst && rs_alu_full) ||
        (is_fpu_inst && rs_fpu_full) ||
        (is_lsu_inst && rs_lsu_full)
    );

endmodule