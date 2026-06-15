// =============================================================================
// rob.v  —  Reorder Buffer  (ROB)
//
// Kích thước: ROB_DEPTH entry, mỗi entry chứa:
//   • pc, rd_arch, prd (physical dest tag), old_prd (tag cũ để free)
//   • fp_rd   : đích là FP reg không?
//   • done    : lệnh đã thực thi xong (written-back)
//   • result  : giá trị kết quả (để forward hoặc commit vào ARF)
//   • exc     : có exception không
//   • is_branch, is_store : cần xử lý đặc biệt khi commit
//   • store_addr, store_data : dùng khi commit store vào dmem
//
// Giao thức:
//   • alloc_valid: Dispatch yêu cầu cấp 1 ROB entry → rob_idx là index cấp ra
//   • wb_valid:    Writeback từ Execute Unit → đánh dấu entry done, ghi result
//   • commit_valid: ROB tự commit head entry khi done=1, flush nếu branch miss
//   • full / empty: trạng thái
// =============================================================================

module ROB #(
    parameter ROB_DEPTH  = 32,
    parameter TAG_WIDTH  = 6,
    parameter ROB_IDX    = 5        // ceil(log2(ROB_DEPTH))
)(
    input  wire        clk,
    input  wire        rst_n,

    // -------------------------------------------------------------------------
    // Dispatch → Alloc
    // -------------------------------------------------------------------------
    input  wire                  alloc_valid,
    input  wire [31:0]           alloc_pc,
    input  wire [4:0]            alloc_rd_arch,
    input  wire [TAG_WIDTH-1:0]  alloc_prd,
    input  wire [TAG_WIDTH-1:0]  alloc_old_prd,
    input  wire                  alloc_fp_rd,
    input  wire                  alloc_is_branch,
    // [FIX-JAL/JALR] JAL/JALR là unconditional jump — cũng cần flush như branch
    // alloc_is_jump=1 khi là JAL hoặc JALR
    // alloc_jump_rd_val = PC+4 (giá trị ghi vào rd, tách khỏi flush_pc)
    input  wire                  alloc_is_jump,
    input  wire [31:0]           alloc_jump_rd_val,
    input  wire                  alloc_is_store,
    input  wire                  alloc_use_rd,

    output wire [ROB_IDX-1:0]    rob_idx,       // ROB index cấp cho lệnh mới
    output wire                  rob_full,

    // -------------------------------------------------------------------------
    // Writeback (nhiều port)
    // Port 0: ALU basic (1 cycle)
    // Port 1: ALU mul/div (multi-cycle)
    // Port 2: FPU
    // Port 3: LSU load
    // -------------------------------------------------------------------------
    input  wire                  wb0_valid,
    input  wire [ROB_IDX-1:0]   wb0_rob_idx,
    input  wire [31:0]           wb0_result,
    input  wire                  wb0_exc,

    input  wire                  wb1_valid,
    input  wire [ROB_IDX-1:0]   wb1_rob_idx,
    input  wire [31:0]           wb1_result,
    input  wire                  wb1_exc,

    input  wire                  wb2_valid,
    input  wire [ROB_IDX-1:0]   wb2_rob_idx,
    input  wire [31:0]           wb2_result,
    input  wire                  wb2_exc,

    input  wire                  wb3_valid,
    input  wire [ROB_IDX-1:0]   wb3_rob_idx,
    input  wire [31:0]           wb3_result,
    input  wire                  wb3_exc,

    // Store writeback (địa chỉ + dữ liệu)
    input  wire                  wbs_valid,
    input  wire [ROB_IDX-1:0]   wbs_rob_idx,
    input  wire [31:0]           wbs_store_addr,
    input  wire [31:0]           wbs_store_data,
    input  wire [2:0]            wbs_store_mode,

    // -------------------------------------------------------------------------
    // Commit output (đến RAT, Free List, dmem, ARF)
    // -------------------------------------------------------------------------
    output reg                   commit_valid,
    output reg  [4:0]            commit_rd_arch,
    output reg  [TAG_WIDTH-1:0]  commit_prd,
    output reg  [TAG_WIDTH-1:0]  commit_old_prd,
    output reg                   commit_fp_rd,
    output reg  [31:0]           commit_result,
    output reg  [31:0]           commit_pc,
    output reg                   commit_use_rd,

    // Store commit
    output reg                   commit_store,
    output reg  [31:0]           commit_store_addr,
    output reg  [31:0]           commit_store_data,
    output reg  [2:0]            commit_store_mode,

    // Branch misprediction → flush
    output reg                   flush,
    output reg  [31:0]           flush_pc,      // PC đúng để fetch lại

    // -------------------------------------------------------------------------
    // CDB Broadcast (Common Data Bus) để Issue Queue biết tag nào đã sẵn
    // -------------------------------------------------------------------------
    output wire [TAG_WIDTH-1:0]  cdb0_tag,
    output wire                  cdb0_valid,
    output wire [31:0]           cdb0_data,

    output wire [TAG_WIDTH-1:0]  cdb1_tag,
    output wire                  cdb1_valid,
    output wire [31:0]           cdb1_data,

    output wire [TAG_WIDTH-1:0]  cdb2_tag,
    output wire                  cdb2_valid,
    output wire [31:0]           cdb2_data,

    output wire [TAG_WIDTH-1:0]  cdb3_tag,
    output wire                  cdb3_valid,
    output wire [31:0]           cdb3_data,

    output wire                  rob_empty,

    // -------------------------------------------------------------------------
    // store_pending: còn ít nhất 1 STORE entry trong ROB chưa commit
    // Dùng bởi IQ_MEM để block LOAD issue cho đến khi tất cả STORE trước đó
    // đã commit (memory ordering: store-before-load on same address)
    // -------------------------------------------------------------------------
    output wire                  store_pending
);

    // =========================================================================
    // ROB Entry
    // =========================================================================
    reg [31:0]           rob_pc        [0:ROB_DEPTH-1];
    reg [4:0]            rob_rd_arch   [0:ROB_DEPTH-1];
    reg [TAG_WIDTH-1:0]  rob_prd       [0:ROB_DEPTH-1];
    reg [TAG_WIDTH-1:0]  rob_old_prd   [0:ROB_DEPTH-1];
    reg                  rob_fp_rd     [0:ROB_DEPTH-1];
    reg                  rob_use_rd    [0:ROB_DEPTH-1];
    reg                  rob_done      [0:ROB_DEPTH-1];
    reg [31:0]           rob_result    [0:ROB_DEPTH-1];
    reg                  rob_exc       [0:ROB_DEPTH-1];
    reg                  rob_is_branch [0:ROB_DEPTH-1];
    reg                  rob_is_store  [0:ROB_DEPTH-1];
    reg                  rob_is_jump   [0:ROB_DEPTH-1]; // [FIX-JAL/JALR]
    reg [31:0]           rob_jump_rd   [0:ROB_DEPTH-1]; // PC+4 saved for JAL/JALR rd
    reg [31:0]           rob_store_addr[0:ROB_DEPTH-1];
    reg [31:0]           rob_store_data[0:ROB_DEPTH-1];
    reg [2:0]            rob_store_mode[0:ROB_DEPTH-1];
    reg                  rob_valid_entry[0:ROB_DEPTH-1];

    // Head (commit) và Tail (alloc)
    reg [ROB_IDX:0] head, tail;
    wire [ROB_IDX-1:0] head_idx = head[ROB_IDX-1:0];
    wire [ROB_IDX-1:0] tail_idx = tail[ROB_IDX-1:0];

    assign rob_full  = (head[ROB_IDX-1:0] == tail[ROB_IDX-1:0]) &&
                       (head[ROB_IDX]     != tail[ROB_IDX]);
    assign rob_empty = (head == tail);
    assign rob_idx   = tail_idx;

    // store_pending: còn STORE entry trong ROB chưa tính địa chỉ (chưa WBS).
    // Sau khi STORE done=1 (WBS xong, addr/data đã vào ROB store buffer),
    // LOAD có thể issue an toàn vì fu_lsu_wrapper forward store_data khi
    // cùng địa chỉ (store-to-load forwarding).
    // Chỉ block khi STORE chưa done (chưa biết địa chỉ/data thực sự).
    reg sp;
    integer spi;
    always @(*) begin
        sp = 1'b0;
        for (spi = 0; spi < ROB_DEPTH; spi = spi + 1)
            if (rob_valid_entry[spi] && rob_is_store[spi] && !rob_done[spi])
                sp = 1'b1;
    end
    assign store_pending = sp;

    // =========================================================================
    // CDB Broadcast (1 cycle sau writeback — dùng trực tiếp wb signals)
    // =========================================================================
    assign cdb0_valid = wb0_valid;
    assign cdb0_tag   = rob_prd[wb0_rob_idx];
    assign cdb0_data  = wb0_result;

    assign cdb1_valid = wb1_valid;
    assign cdb1_tag   = rob_prd[wb1_rob_idx];
    assign cdb1_data  = wb1_result;

    assign cdb2_valid = wb2_valid;
    assign cdb2_tag   = rob_prd[wb2_rob_idx];
    assign cdb2_data  = wb2_result;

    assign cdb3_valid = wb3_valid;
    assign cdb3_tag   = rob_prd[wb3_rob_idx];
    assign cdb3_data  = wb3_result;

    // =========================================================================
    // Main logic
    // =========================================================================
    integer i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            head       <= 0;
            tail       <= 0;
            flush      <= 1'b0;
            flush_pc   <= 32'd0;
            commit_valid <= 1'b0;
            for (i = 0; i < ROB_DEPTH; i = i + 1) begin
                rob_done[i]       <= 1'b0;
                rob_valid_entry[i]<= 1'b0;
                rob_exc[i]        <= 1'b0;
            end
        end else begin
            flush        <= 1'b0;
            commit_valid <= 1'b0;
            commit_store <= 1'b0;

            if (flush) begin
                for (i = 0; i < ROB_DEPTH; i = i + 1)
                    rob_valid_entry[i] <= 1'b0;
                head <= 0;
                tail <= 0;
            end else begin

            // ------------------------------------------------------------------
            // 1. ALLOC
            // ------------------------------------------------------------------
            if (alloc_valid && !rob_full) begin
                rob_pc[tail_idx]         <= alloc_pc;
                rob_rd_arch[tail_idx]    <= alloc_rd_arch;
                rob_prd[tail_idx]        <= alloc_prd;
                rob_old_prd[tail_idx]    <= alloc_old_prd;
                rob_fp_rd[tail_idx]      <= alloc_fp_rd;
                rob_use_rd[tail_idx]     <= alloc_use_rd;
                rob_done[tail_idx]       <= 1'b0;
                rob_exc[tail_idx]        <= 1'b0;
                rob_is_branch[tail_idx]  <= alloc_is_branch;
                rob_is_store[tail_idx]   <= alloc_is_store;
                // [FIX-JAL/JALR] lưu jump info tại alloc
                rob_is_jump[tail_idx]    <= alloc_is_jump;
                rob_jump_rd[tail_idx]    <= alloc_jump_rd_val;
                rob_valid_entry[tail_idx]<= 1'b1;
                tail <= tail + 1'b1;
            end

            // ------------------------------------------------------------------
            // 2. WRITEBACK
            // ------------------------------------------------------------------
            if (wb0_valid) begin
                rob_done[wb0_rob_idx]   <= 1'b1;
                rob_result[wb0_rob_idx] <= wb0_result;
                rob_exc[wb0_rob_idx]    <= wb0_exc;
            end
            if (wb1_valid) begin
                rob_done[wb1_rob_idx]   <= 1'b1;
                rob_result[wb1_rob_idx] <= wb1_result;
                rob_exc[wb1_rob_idx]    <= wb1_exc;
            end
            if (wb2_valid) begin
                rob_done[wb2_rob_idx]   <= 1'b1;
                rob_result[wb2_rob_idx] <= wb2_result;
                rob_exc[wb2_rob_idx]    <= wb2_exc;
            end
            if (wb3_valid) begin
                rob_done[wb3_rob_idx]   <= 1'b1;
                rob_result[wb3_rob_idx] <= wb3_result;
                rob_exc[wb3_rob_idx]    <= wb3_exc;
            end
            if (wbs_valid) begin
                rob_done[wbs_rob_idx]       <= 1'b1;
                rob_store_addr[wbs_rob_idx] <= wbs_store_addr;
                rob_store_data[wbs_rob_idx] <= wbs_store_data;
                rob_store_mode[wbs_rob_idx] <= wbs_store_mode;
            end

            // ------------------------------------------------------------------
            // 3. COMMIT + FLUSH
            //
            // [FIX-FAST-FLUSH] Flush nhanh hơn: khi WB0 trả kết quả branch
            // misprediction VÀ branch entry là HEAD (tất cả lệnh trước đã commit),
            // flush ngay trong cùng cycle thay vì phải chờ rob_done được latch
            // sang cycle tiếp theo.
            //
            // Điều kiện fast-flush:
            //   wb0_valid=1 AND is_branch[wb0_idx]=1 AND wb0_exc=1
            //   AND head_idx == wb0_rob_idx  (branch đang ở HEAD)
            //   AND rob_valid_entry[wb0_rob_idx]=1
            //
            // Điều kiện này đảm bảo tất cả lệnh trước branch đã commit
            // (vì head đã tiến đến branch), nên aRAT chính xác.
            // ------------------------------------------------------------------

            // Fast-flush: branch/JAL/JALR WB cùng cycle nó là HEAD
            if (wb0_valid && (rob_is_branch[wb0_rob_idx] || rob_is_jump[wb0_rob_idx])
                && wb0_exc
                && rob_valid_entry[wb0_rob_idx]
                && (wb0_rob_idx == head_idx)) begin

                commit_valid      <= 1'b1;
                commit_pc         <= rob_pc[wb0_rob_idx];
                commit_rd_arch    <= rob_rd_arch[wb0_rob_idx];
                // JAL/JALR: commit_use_rd=1, rd = PC+4 (rob_jump_rd)
                // branch:   commit_use_rd=0
                commit_use_rd     <= rob_is_jump[wb0_rob_idx];
                commit_prd        <= rob_prd[wb0_rob_idx];
                commit_old_prd    <= rob_old_prd[wb0_rob_idx];
                commit_fp_rd      <= rob_fp_rd[wb0_rob_idx];
                // JAL/JALR rd = PC+4; branch result = flush_pc (not committed to rd)
                commit_result     <= rob_is_jump[wb0_rob_idx]
                                     ? rob_jump_rd[wb0_rob_idx]
                                     : wb0_result;
                commit_store      <= 1'b0;

                rob_valid_entry[wb0_rob_idx] <= 1'b0;
                head <= head + 1'b1;

                flush    <= 1'b1;
                flush_pc <= wb0_result;  // flush_pc = jump/branch target

            end else begin
            // Normal commit path
            if (!rob_empty && rob_done[head_idx] && rob_valid_entry[head_idx]) begin
                commit_valid      <= 1'b1;
                commit_rd_arch    <= rob_rd_arch[head_idx];
                commit_prd        <= rob_prd[head_idx];
                commit_old_prd    <= rob_old_prd[head_idx];
                commit_fp_rd      <= rob_fp_rd[head_idx];
                commit_result     <= rob_is_jump[head_idx]
                                     ? rob_jump_rd[head_idx]   // JAL/JALR: rd=PC+4
                                     : rob_result[head_idx];   // normal: ALU result
                commit_pc         <= rob_pc[head_idx];
                commit_use_rd     <= rob_use_rd[head_idx];
                commit_store      <= rob_is_store[head_idx];
                commit_store_addr <= rob_store_addr[head_idx];
                commit_store_data <= rob_store_data[head_idx];
                commit_store_mode <= rob_store_mode[head_idx];

                rob_valid_entry[head_idx] <= 1'b0;
                head <= head + 1'b1;

                // Late flush fallback cho branch/JAL/JALR
                if ((rob_is_branch[head_idx] || rob_is_jump[head_idx]) && rob_exc[head_idx]) begin
                    flush    <= 1'b1;
                    flush_pc <= rob_result[head_idx];
                    tail <= head + {{ROB_IDX{1'b0}}, 1'b1};
                end
            end
            end  // end normal commit
            end  // end else (not flush)
        end
    end

endmodule