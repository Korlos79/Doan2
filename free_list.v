// =============================================================================
// free_list.v  —  Physical Register Free List  (parameterized)
//
// Dùng chung cho cả Int và Float physical register file.
//
// Kiến trúc:
//   • Circular FIFO, head = dequeue (cấp tag mới), tail = enqueue (trả tag cũ)
//   • Reset: nạp tag từ NUM_ARCH..NUM_PHYS-1 vào FIFO
//     (tag 0..NUM_ARCH-1 đã được RAT dùng ban đầu, không nằm trong Free List)
//   • alloc_valid   : yêu cầu cấp 1 tag → alloc_tag là tag cấp
//   • free_valid    : trả 1 tag cũ về sau commit
//   • full / empty  : trạng thái
// =============================================================================

module free_list #(
    parameter NUM_PHYS  = 64,
    parameter NUM_ARCH  = 32,
    parameter TAG_WIDTH = 6,
    // [FIX-FP-TAG] BASE_TAG: offset cho tag range được alloc
    // INT free_list: BASE_TAG=0  → tags = BASE_TAG+NUM_ARCH .. BASE_TAG+NUM_PHYS-1
    //                             = 0+32 .. 0+63   = p32..p63
    // FP  free_list: BASE_TAG=64 → tags = 64+32   .. 64+63   = p96..p127
    // Đảm bảo INT và FP dùng tag range không overlap nhau.
    parameter BASE_TAG  = 0
)(
    input  wire                 clk,
    input  wire                 rst_n,
    input  wire                 flush,          // Branch misprediction flush

    // Snapshot cho flush recovery
    input  wire                 snapshot_en,    // Chụp snapshot khi dispatch branch
    // (đơn giản: sau flush sẽ restore head về snapshot_head)
    
    // Cấp tag (Dispatch)
    input  wire                 alloc_valid,    // Yêu cầu lấy 1 tag
    output wire [TAG_WIDTH-1:0] alloc_tag,      // Tag được cấp
    output wire                 alloc_ok,       // Có sẵn tag không

    // Trả tag (Commit)
    input  wire                 free_valid,
    input  wire [TAG_WIDTH-1:0] free_tag,

    output wire                 full,
    output wire                 empty
);

    localparam DEPTH = NUM_PHYS - NUM_ARCH;  // Số slot FIFO
    localparam PTR   = $clog2(DEPTH) + 1;   // +1 bit để phân biệt full/empty

    reg [TAG_WIDTH-1:0] fifo [0:DEPTH-1];
    reg [PTR-1:0]       head, tail;          // head=đọc, tail=ghi
    reg [PTR-1:0]       snap_head;           // Snapshot cho branch recovery

    wire [PTR-2:0] head_idx = head[PTR-2:0];
    wire [PTR-2:0] tail_idx = tail[PTR-2:0];

    assign empty = (head == tail);
    assign full  = (head[PTR-2:0] == tail[PTR-2:0]) && (head[PTR-1] != tail[PTR-1]);

    assign alloc_ok  = !empty && alloc_valid;
    assign alloc_tag = fifo[head_idx];

    integer i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            head      <= 0;
            tail      <= 0;
            snap_head <= 0;
            // [FIX-FP-TAG] Nạp tag (BASE_TAG+NUM_ARCH) .. (BASE_TAG+NUM_PHYS-1)
            for (i = 0; i < DEPTH; i = i + 1)
                fifo[i] <= BASE_TAG + NUM_ARCH + i;
            tail <= DEPTH[PTR-1:0];  // tail bắt đầu ở cuối vì đã pre-fill
        end else if (flush) begin
            // Khôi phục head về snapshot
            head <= snap_head;
        end else begin
            // Snapshot khi dispatch branch
            if (snapshot_en)
                snap_head <= head;

            // Cấp tag: tăng head
            if (alloc_valid && !empty)
                head <= head + 1'b1;

            // Trả tag: ghi vào tail, tăng tail
            if (free_valid && !full) begin
                fifo[tail_idx] <= free_tag;
                tail <= tail + 1'b1;
            end
        end
    end

endmodule