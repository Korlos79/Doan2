// =============================================================================
// branch_predictor.v — Tournament Branch Predictor
//
// Kiến trúc:
//   BTB  (64-entry direct-mapped): lưu branch target
//   BHT  (256-entry, 2-bit saturating): lưu taken/not-taken history
//   GHR  (8-bit global history register): XOR với PC để index BHT
//
// Pipeline integration:
//   FETCH  : predict_taken, predict_target → điều khiển pc_next
//   WB0    : update BTB/BHT sau khi biết kết quả thực
//   FLUSH  : restore GHR về checkpoint
//   DISPATCH: checkpoint GHR cho flush recovery
//
// Accuracy (lý thuyết):
//   Simple loop: ~90%+
//   Mixed:       ~80-85%
//   So sánh với always-not-taken: ~50-60%
//
// Parameters:
//   BTB_ENTRIES : số entry BTB (mũ của 2)
//   BHT_ENTRIES : số entry BHT (mũ của 2)
//   GHR_WIDTH   : độ rộng GHR
// =============================================================================
`timescale 1ns/1ps

module branch_predictor #(
    parameter BTB_ENTRIES = 64,     // direct-mapped BTB
    parameter BHT_ENTRIES = 256,    // 2-bit saturating counter table
    parameter GHR_WIDTH   = 8       // global history register width
)(
    input  wire        clk,
    input  wire        rst_n,

    // =========================================================================
    // FETCH interface — query predictor
    // =========================================================================
    input  wire [31:0] fetch_pc,         // PC đang fetch
    input  wire        fetch_is_branch,  // decode sớm: có phải branch không
                                         // (dùng cho conditional branch)
    output wire        predict_taken,    // dự đoán: taken?
    output wire [31:0] predict_target,   // dự đoán: target PC (nếu taken)

    // =========================================================================
    // DISPATCH interface — checkpoint GHR khi dispatch branch/jump
    // =========================================================================
    input  wire        dispatch_en,      // do_dispatch && (is_branch|is_jal|is_jalr)
    input  wire        dispatch_predict_taken, // prediction tại FETCH của lệnh này

    // =========================================================================
    // UPDATE interface — cập nhật sau khi biết kết quả thực (WB0)
    // =========================================================================
    input  wire        update_en,        // 1 khi ALU wb0 có branch/jump result
    input  wire [31:0] update_pc,        // PC của branch
    input  wire        update_taken,     // kết quả thực: taken?
    input  wire [31:0] update_target,    // target thực (khi taken)
    input  wire        update_is_branch, // là conditional branch (cần update BHT)

    // =========================================================================
    // FLUSH interface — restore GHR khi misprediction
    // =========================================================================
    input  wire        flush_en,         // flush_pipeline
    input  wire        flush_mispred     // 1 nếu là misprediction (cần restore GHR)
);

    // =========================================================================
    // 1. GHR — Global History Register
    //    Lưu lịch sử N branch gần nhất (1=taken, 0=not-taken)
    //    GHR[0] = branch cũ nhất, GHR[GHR_WIDTH-1] = branch mới nhất
    // =========================================================================
    reg [GHR_WIDTH-1:0] ghr;          // GHR hiện tại (speculative)
    reg [GHR_WIDTH-1:0] ghr_ckpt;     // Checkpoint tại DISPATCH

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ghr       <= {GHR_WIDTH{1'b0}};
            ghr_ckpt  <= {GHR_WIDTH{1'b0}};
        end else begin
            // Ưu tiên: flush restore > dispatch checkpoint > update
            if (flush_en && flush_mispred) begin
                // Restore GHR về checkpoint trước lệnh bị flush
                ghr <= ghr_ckpt;
            end else if (update_en && update_is_branch) begin
                // Cập nhật GHR sau khi biết kết quả thực
                // Shift left, thêm outcome vào MSB
                ghr <= {ghr[GHR_WIDTH-2:0], update_taken};
            end

            // Checkpoint GHR tại DISPATCH (trước khi speculative update)
            if (dispatch_en) begin
                ghr_ckpt <= ghr;
            end
        end
    end

    // =========================================================================
    // 2. BHT — Branch History Table (2-bit saturating counters)
    //    Index = PC[BHT_IDX+1:2] XOR GHR[BHT_IDX-1:0]
    //    00=StronglyNotTaken, 01=WeaklyNotTaken
    //    10=WeaklyTaken,      11=StronglyTaken
    // =========================================================================
    localparam BHT_IDX = $clog2(BHT_ENTRIES);  // 8 bits for 256 entries

    reg [1:0] bht [0:BHT_ENTRIES-1];

    // Index cho FETCH query
    wire [BHT_IDX-1:0] bht_fetch_idx =
        fetch_pc[BHT_IDX+1:2] ^ ghr[BHT_IDX-1:0];

    // Index cho UPDATE
    wire [BHT_IDX-1:0] bht_update_idx =
        update_pc[BHT_IDX+1:2] ^ ghr[BHT_IDX-1:0];

    // Prediction từ BHT: taken nếu MSB = 1
    wire bht_predict = bht[bht_fetch_idx][1];

    integer bi;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (bi = 0; bi < BHT_ENTRIES; bi = bi + 1)
                bht[bi] <= 2'b01; // WeaklyNotTaken (hơi thiên về not-taken)
        end else if (update_en && update_is_branch) begin
            // 2-bit saturating counter update
            if (update_taken) begin
                // Taken: increment (max 11)
                if (bht[bht_update_idx] != 2'b11)
                    bht[bht_update_idx] <= bht[bht_update_idx] + 1'b1;
            end else begin
                // Not-taken: decrement (min 00)
                if (bht[bht_update_idx] != 2'b00)
                    bht[bht_update_idx] <= bht[bht_update_idx] - 1'b1;
            end
        end
    end

    // =========================================================================
    // 3. BTB — Branch Target Buffer (direct-mapped)
    //    Index = PC[BTB_IDX+1:2]
    //    Lưu: valid, tag (PC[31:BTB_IDX+2]), target
    //    Chỉ có valid BTB hit mới cho phép predict taken
    // =========================================================================
    localparam BTB_IDX = $clog2(BTB_ENTRIES);  // 6 bits for 64 entries
    localparam BTB_TAG_WIDTH = 32 - BTB_IDX - 2; // remaining PC bits

    reg                       btb_valid  [0:BTB_ENTRIES-1];
    reg [BTB_TAG_WIDTH-1:0]   btb_tag    [0:BTB_ENTRIES-1];
    reg [31:0]                btb_target [0:BTB_ENTRIES-1];

    // BTB lookup tại FETCH
    wire [BTB_IDX-1:0]       btb_fetch_idx = fetch_pc[BTB_IDX+1:2];
    wire [BTB_TAG_WIDTH-1:0] btb_fetch_tag = fetch_pc[31:BTB_IDX+2];
    wire btb_hit = btb_valid[btb_fetch_idx] &&
                   (btb_tag[btb_fetch_idx] == btb_fetch_tag);

    // BTB update
    wire [BTB_IDX-1:0]       btb_update_idx = update_pc[BTB_IDX+1:2];
    wire [BTB_TAG_WIDTH-1:0] btb_update_tag = update_pc[31:BTB_IDX+2];

    integer vi;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (vi = 0; vi < BTB_ENTRIES; vi = vi + 1) begin
                btb_valid[vi]  <= 1'b0;
                btb_tag[vi]    <= {BTB_TAG_WIDTH{1'b0}};
                btb_target[vi] <= 32'd0;
            end
        end else if (update_en && update_taken) begin
            // Chỉ ghi BTB khi branch taken (target mới biết chắc)
            btb_valid[btb_update_idx]  <= 1'b1;
            btb_tag[btb_update_idx]    <= btb_update_tag;
            btb_target[btb_update_idx] <= update_target;
        end
    end

    // =========================================================================
    // 4. Prediction output
    //    predict_taken = BHT predict taken AND BTB hit (có target)
    //    Nếu BTB miss: không thể predict taken (không biết target)
    //    JAL/JALR: luôn taken → BTB hit là điều kiện đủ
    // =========================================================================
    assign predict_taken  = bht_predict && btb_hit && fetch_is_branch;
    assign predict_target = btb_hit ? btb_target[btb_fetch_idx] : 32'd0;

endmodule