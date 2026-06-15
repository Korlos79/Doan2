// =============================================================================
// prf.v  —  Physical Register File  (Flat-bus, Verilog-2001 compatible)
//
// FIX: đổi unpacked array port [0:NUM_RD-1] sang flat vector
//      để tương thích Verilog-2001 và ModelSim/Quartus
//
// rd_tag  : {tagN-1, ..., tag1, tag0}  — tag0 ở bit thấp nhất
// rd_data : {dataN-1,..., data1, data0}
// rd_ready: {rdyN-1,..., rdy1, rdy0}
// =============================================================================
module prf #(
    parameter NUM_PHYS  = 64,
    parameter NUM_ARCH  = 32,
    parameter TAG_WIDTH = 7,  // [FIX-FP-TAG],
    parameter NUM_RD    = 4
)(
    input  wire        clk,
    input  wire        rst_n,

    // READ ports — flat vector
    input  wire [(NUM_RD*TAG_WIDTH)-1:0] rd_tag,
    output wire [(NUM_RD*32)-1:0]        rd_data,
    output wire [NUM_RD-1:0]             rd_ready,

    // WRITE ports
    input  wire                  wb0_en,
    input  wire [TAG_WIDTH-1:0]  wb0_tag,
    input  wire [31:0]           wb0_data,

    input  wire                  wb1_en,
    input  wire [TAG_WIDTH-1:0]  wb1_tag,
    input  wire [31:0]           wb1_data,

    input  wire                  wb2_en,
    input  wire [TAG_WIDTH-1:0]  wb2_tag,
    input  wire [31:0]           wb2_data,

    input  wire                  wb3_en,
    input  wire [TAG_WIDTH-1:0]  wb3_tag,
    input  wire [31:0]           wb3_data,

    // CLEAR ready khi Rename
    input  wire                  clear_en,
    input  wire [TAG_WIDTH-1:0]  clear_tag
);

    reg [31:0] mem  [0:NUM_PHYS-1];
    reg        rdy  [0:NUM_PHYS-1];

    // Tách từng read port từ flat vector
    genvar g;
    generate
        for (g = 0; g < NUM_RD; g = g + 1) begin : RD_PORT
            wire [TAG_WIDTH-1:0] tag_g  = rd_tag [g*TAG_WIDTH +: TAG_WIDTH];
            wire                 hit0   = wb0_en && (wb0_tag == tag_g);
            wire                 hit1   = wb1_en && (wb1_tag == tag_g);
            wire                 hit2   = wb2_en && (wb2_tag == tag_g);
            wire                 hit3   = wb3_en && (wb3_tag == tag_g);
            wire                 any_hit= hit0 | hit1 | hit2 | hit3;

            // WB bypass: wb3 > wb2 > wb1 > wb0
            assign rd_data [g*32 +: 32] = hit3 ? wb3_data :
                                           hit2 ? wb2_data :
                                           hit1 ? wb1_data :
                                           hit0 ? wb0_data :
                                                  mem[tag_g];
            assign rd_ready[g]          = any_hit | rdy[tag_g];
        end
    endgenerate

    integer i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < NUM_PHYS; i = i + 1) begin
                mem[i] <= 32'd0;
                // tag 0..(NUM_ARCH-1) map tới architectural regs → ready=1
                rdy[i] <= (i < NUM_ARCH) ? 1'b1 : 1'b0;
            end
        end else begin
            if (wb0_en) begin mem[wb0_tag] <= wb0_data; rdy[wb0_tag] <= 1'b1; end
            if (wb1_en) begin mem[wb1_tag] <= wb1_data; rdy[wb1_tag] <= 1'b1; end
            if (wb2_en) begin mem[wb2_tag] <= wb2_data; rdy[wb2_tag] <= 1'b1; end
            if (wb3_en) begin mem[wb3_tag] <= wb3_data; rdy[wb3_tag] <= 1'b1; end

            // Clear ready khi rename cấp tag mới (ưu tiên WB nếu cùng cycle)
            if (clear_en) begin
                if (!( (wb0_en && wb0_tag==clear_tag) ||
                       (wb1_en && wb1_tag==clear_tag) ||
                       (wb2_en && wb2_tag==clear_tag) ||
                       (wb3_en && wb3_tag==clear_tag) ))
                    rdy[clear_tag] <= 1'b0;
            end
        end
    end

endmodule