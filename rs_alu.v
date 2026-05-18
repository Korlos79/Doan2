module rs_alu #(
    parameter DATA_WIDTH  = 32,
    parameter TAG_WIDTH   = 4,   
    parameter NUM_ENTRIES = 4   
)(
    input wire clk,
    input wire rst_n,
    input wire flush,

    // --- 1. GIAO DIỆN VỚI DISPATCHER ---
    input  wire                   dispatch_enable,
    input  wire [4:0]             opcode,
    input  wire [TAG_WIDTH-1:0]   my_rob_tag,
    input  wire [DATA_WIDTH-1:0]  src1_val, src2_val, src3_val,
    input  wire [TAG_WIDTH-1:0]   src1_tag, src2_tag, src3_tag,
    input  wire                   src1_ready, src2_ready, src3_ready,
    input  wire [31:0]            disp_pc,
    input  wire [31:0]            disp_imm,      
    input  wire                   disp_muxjalr,
    input  wire                   disp_jump,
    input  wire                   disp_branch,
    output wire                   rs_full,

    // --- 2. GIAO DIỆN VỚI CDB (Snooping) ---
    input  wire                   cdb_valid,
    input  wire [TAG_WIDTH-1:0]   cdb_tag,
    input  wire [DATA_WIDTH-1:0]  cdb_value,

    // --- 3. GIAO DIỆN VỚI FU ALU ---
    input  wire                   fu_busy_basic, 
    input  wire                   fu_busy_md,    
    output reg                    fu_start,
    output reg  [DATA_WIDTH-1:0]  fu_op1, fu_op2, fu_op3,
    output reg  [4:0]             fu_opcode,
    output reg [TAG_WIDTH-1:0]    fu_dest_tag,
    output reg  [31:0]            fu_pc,
    output reg  [31:0]            fu_imm,         
    output reg                    fu_muxjalr,
    output reg                    fu_jump,
    output reg                    fu_branch
);

    // ==========================================
    // THANH GHI ĐỆM GIỮ GIÁ TRỊ CDB (NEW)
    // ==========================================
    reg                   reg_cdb_valid;
    reg [TAG_WIDTH-1:0]   reg_cdb_tag;
    reg [DATA_WIDTH-1:0]  reg_cdb_value;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            reg_cdb_valid <= 0;
            reg_cdb_tag   <= 0;
            reg_cdb_value <= 0;
        end else if (cdb_valid) begin
            // Cập nhật khi có giá trị mới, nếu không có thì giữ nguyên giá trị cũ
            reg_cdb_valid <= 1'b1;
            reg_cdb_tag   <= cdb_tag;
            reg_cdb_value <= cdb_value;
        end
    end

    // Dùng dây nội bộ để chọn giữa giá trị đang bay trên Bus (Wire) 
    // hoặc giá trị đã chốt trong thanh ghi (Reg)
    wire current_cdb_valid = cdb_valid || reg_cdb_valid;
    wire [TAG_WIDTH-1:0]  current_cdb_tag   = cdb_valid ? cdb_tag   : reg_cdb_tag;
    wire [DATA_WIDTH-1:0] current_cdb_value = cdb_valid ? cdb_value : reg_cdb_value;


    // ==========================================
    // CẤU TRÚC LƯU TRỮ (RESERVATION STATION)
    // ==========================================
    reg [NUM_ENTRIES-1:0] busy;
    reg [4:0]             op [NUM_ENTRIES-1:0];
    reg [DATA_WIDTH-1:0]  v1 [NUM_ENTRIES-1:0]; reg [TAG_WIDTH-1:0] q1 [NUM_ENTRIES-1:0]; reg r1 [NUM_ENTRIES-1:0];
    reg [DATA_WIDTH-1:0]  v2 [NUM_ENTRIES-1:0]; reg [TAG_WIDTH-1:0] q2 [NUM_ENTRIES-1:0]; reg r2 [NUM_ENTRIES-1:0];
    reg [DATA_WIDTH-1:0]  v3 [NUM_ENTRIES-1:0]; reg [TAG_WIDTH-1:0] q3 [NUM_ENTRIES-1:0]; reg r3 [NUM_ENTRIES-1:0];
    reg [TAG_WIDTH-1:0]   rob_tag    [NUM_ENTRIES-1:0];
    reg [31:0]            rs_pc      [NUM_ENTRIES-1:0];
    reg [31:0]            rs_imm     [NUM_ENTRIES-1:0]; 
    reg                   rs_muxjalr [NUM_ENTRIES-1:0];
    reg                   rs_jump    [NUM_ENTRIES-1:0];
    reg                   rs_branch  [NUM_ENTRIES-1:0];

    integer i;

    // --- Logic Allocation & Issue giữ nguyên ---
    reg [31:0] alloc_idx;
    reg        found_slot;
    always @(*) begin
        found_slot = 0; alloc_idx  = 0;
        for (i = 0; i < NUM_ENTRIES; i = i + 1) begin
            if (!busy[i] && !found_slot) begin alloc_idx = i; found_slot = 1; end
        end
    end
    assign rs_full = !found_slot;

    reg [31:0] issue_idx;
    reg        can_fire;
    wire [NUM_ENTRIES-1:0] is_md_entry;
    generate
        genvar g;
        for (g = 0; g < NUM_ENTRIES; g = g + 1) begin: check_type
            assign is_md_entry[g] = (op[g] >= 5'd9 && op[g] <= 5'd16);
        end
    endgenerate

    always @(*) begin
        can_fire  = 0; issue_idx = 0;
        for (i = 0; i < NUM_ENTRIES; i = i + 1) begin
            if (busy[i] && r1[i] && r2[i] && r3[i] && !can_fire) begin
                if (is_md_entry[i]) begin
                    if (!fu_busy_md) begin issue_idx = i; can_fire = 1; end
                end else begin
                    if (!fu_busy_basic) begin issue_idx = i; can_fire = 1; end
                end
            end
        end
    end

    // ==========================================
    // SEQUENTIAL LOGIC - CẬP NHẬT TRẠNG THÁI
    // ==========================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            busy <= 0;
            fu_start <= 0;
            for (i = 0; i < NUM_ENTRIES; i = i + 1) begin
                r1[i] <= 0; r2[i] <= 0; r3[i] <= 0;
            end
        end else if (flush) begin
            busy <= 0;
            fu_start <= 0;
            for (i = 0; i < NUM_ENTRIES; i = i + 1) begin
                r1[i] <= 0; r2[i] <= 0; r3[i] <= 0;
            end
        end else begin
            fu_start <= 0;

            if (can_fire) begin
                fu_start    <= 1;
                fu_op1      <= v1[issue_idx];
                fu_op2      <= v2[issue_idx];
                fu_op3      <= v3[issue_idx];
                fu_opcode   <= op[issue_idx];
                fu_dest_tag <= rob_tag[issue_idx];
                fu_pc       <= rs_pc[issue_idx];
                fu_imm      <= rs_imm[issue_idx]; 
                fu_muxjalr  <= rs_muxjalr[issue_idx];
                fu_jump     <= rs_jump[issue_idx];
                fu_branch   <= rs_branch[issue_idx];
                busy[issue_idx] <= 1'b0; 
            end

            for (i = 0; i < NUM_ENTRIES; i = i + 1) begin
                // SỬ DỤNG current_cdb_* ĐỂ SNOOP (ĐÃ ĐƯỢC CHỐT)
                if (dispatch_enable && found_slot && (i == alloc_idx)) begin
                    busy[i] <= 1;
                    op[i] <= opcode;
                    rob_tag[i] <= my_rob_tag;
                    rs_pc[i] <= disp_pc;
                    rs_imm[i] <= disp_imm;
                    rs_muxjalr[i] <= disp_muxjalr;
                    rs_jump[i] <= disp_jump;
                    rs_branch[i] <= disp_branch;

                    // Snooping khi Dispatch
                    if (src1_ready) begin
                        v1[i] <= src1_val; r1[i] <= 1; q1[i] <= 0;
                    end else if (current_cdb_valid && (src1_tag == current_cdb_tag) && (current_cdb_tag != 0)) begin
                        v1[i] <= current_cdb_value; r1[i] <= 1; q1[i] <= 0;
                    end else begin
                        v1[i] <= 0; r1[i] <= 0; q1[i] <= src1_tag;
                    end

                    if (src2_ready) begin
                        v2[i] <= src2_val; r2[i] <= 1; q2[i] <= 0;
                    end else if (current_cdb_valid && (src2_tag == current_cdb_tag) && (current_cdb_tag != 0)) begin
                        v2[i] <= current_cdb_value; r2[i] <= 1; q2[i] <= 0;
                    end else begin
                        v2[i] <= 0; r2[i] <= 0; q2[i] <= src2_tag;
                    end

                    if (src3_ready) begin
                        v3[i] <= src3_val; r3[i] <= 1; q3[i] <= 0;
                    end else if (current_cdb_valid && (src3_tag == current_cdb_tag) && (current_cdb_tag != 0)) begin
                        v3[i] <= current_cdb_value; r3[i] <= 1; q3[i] <= 0;
                    end else begin
                        v3[i] <= 0; r3[i] <= 0; q3[i] <= src3_tag;
                    end
                end 
                else if (busy[i]) begin
                    if (!(can_fire && (i == issue_idx))) begin
                        if (current_cdb_valid && (current_cdb_tag != 0)) begin
                            if (!r1[i] && (q1[i] == current_cdb_tag)) begin 
                                v1[i] <= current_cdb_value; r1[i] <= 1'b1; q1[i] <= 0; 
                            end
                            if (!r2[i] && (q2[i] == current_cdb_tag)) begin 
                                v2[i] <= current_cdb_value; r2[i] <= 1'b1; q2[i] <= 0; 
                            end
                            if (!r3[i] && (q3[i] == current_cdb_tag)) begin 
                                v3[i] <= current_cdb_value; r3[i] <= 1'b1; q3[i] <= 0; 
                            end
                        end
                    end
                end
            end 
        end
    end

endmodule