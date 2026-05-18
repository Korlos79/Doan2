module IF_ID_register (
    input  wire        clk, 
    input  wire        rst_n,   // Đổi thành rst_n cho đồng bộ
    input  wire        stall, 
    input  wire        flush, 
    input  wire        issue_fire,
	 
    // --- TÍN HIỆU TỪ TẦNG FETCH (IF) ---
    input  wire [31:0] instF, 
    input  wire [31:0] PCF,
    input  wire        validF,  // <-- NEW: Lệnh lấy từ I-Cache/Memory có hợp lệ không?
    
    // --- TÍN HIỆU XUẤT RA TẦNG DECODE (ID) ---
    output reg  [31:0] instD, 
    output reg  [31:0] PCD,
    output reg         validD   // <-- NEW: Sẽ trở thành `decode_valid` cho khối Dispatch
);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            instD  <= 32'b0;
            PCD    <= 32'b0;
            validD <= 1'b0;     // Reset thì không có lệnh hợp lệ
        end
        else if (flush) begin
            // Có thể gán instD = 32'h00000013 (Lệnh NOP: addi x0, x0, 0 của RISC-V) cho an toàn
            instD  <= 32'h00000013; 
            PCD    <= 32'b0;
            validD <= 1'b0;     // <-- QUAN TRỌNG: Báo hiệu đây chỉ là Bubble, cấm Dispatch!
        end
        else if (stall) begin 
            // Đóng băng toàn bộ thanh ghi
            instD  <= instD;
            PCD    <= PCD;
            if (issue_fire) 
                validD <= 1'b0; 
            else 
                validD <= validD;
        end
        else begin
            // Chạy bình thường
            instD  <= instF;
            PCD    <= PCF;
            validD <= validF;   // Truyền cờ valid đi tiếp
        end
    end
endmodule