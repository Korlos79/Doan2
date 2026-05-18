module free_list #(
    parameter PR_NUM    = 64, // Tổng số Physical Registers
    parameter TAG_WIDTH = 6   // log2(64)
)(
    input  wire                 clk,
    input  wire                 rst_n,
    input  wire                 flush, // Khi đoán sai nhánh, cần phục hồi (Rollback)

    // Cổng Pop (Lấy Tag mới lúc Dispatch/Issue)
    input  wire                 pop_req,
    output wire [TAG_WIDTH-1:0] pop_tag,
    output wire                 empty,

    // Cổng Push (Trả Tag cũ lúc Commit)
    input  wire                 push_req,
    input  wire [TAG_WIDTH-1:0] push_tag,
    output wire                 full
);
    // Hàng đợi FIFO vòng (Circular Queue)
    reg [TAG_WIDTH-1:0] fifo [0:PR_NUM-1];
    reg [TAG_WIDTH-1:0] head; // Con trỏ Pop
    reg [TAG_WIDTH-1:0] tail; // Con trỏ Push
    reg [6:0]           count; // Số lượng Tag đang rảnh

    assign empty   = (count == 0);
    assign full    = (count == PR_NUM);
    assign pop_tag = fifo[head];

    integer i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Mặc định ban đầu:
            // x0-x31 (hoặc f0-f31) được map cứng với PR 0-31
            // Do đó, các PR rảnh rỗi nằm trong Free List sẽ bắt đầu từ 32 đến 63
            head  <= 0;
            tail  <= PR_NUM - 32;
            count <= PR_NUM - 32;
            for (i = 0; i < PR_NUM - 32; i = i + 1) begin
                fifo[i] <= i + 32; // Nạp các Tag từ 32 đến 63 vào Free List
            end
        end 
        else if (flush) begin
            // XỬ LÝ FLUSH (Rất phức tạp trong thực tế, đây là bản đơn giản hóa)
            // Trong đồ án, để an toàn khi flush, bạn có thể ép Free List quét lại aRAT 
            // hoặc đơn giản là dùng cơ chế Checkpoint (lưu lại Head/Tail mỗi khi branch).
            // (Đoạn này phụ thuộc vào cách bạn thiết kế Checkpoint ROB, tạm để trống hoặc 
            // thiết kế mảng Bitmap thay vì FIFO nếu bạn gặp lỗi Rollback).
        end
        else begin
            case ({push_req, pop_req})
                2'b01: begin // Chỉ Pop
                    if (!empty) begin
                        head  <= (head + 1) % PR_NUM;
                        count <= count - 1;
                    end
                end
                2'b10: begin // Chỉ Push
                    if (!full) begin
                        fifo[tail] <= push_tag;
                        tail       <= (tail + 1) % PR_NUM;
                        count      <= count + 1;
                    end
                end
                2'b11: begin // Vừa Push vừa Pop
                    if (!empty && !full) begin
                        fifo[tail] <= push_tag;
                        head       <= (head + 1) % PR_NUM;
                        tail       <= (tail + 1) % PR_NUM;
                        // Count không đổi
                    end
                end
            endcase
        end
    end
endmodule