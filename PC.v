module PC (
    input  wire        clk, 
    input  wire        rst_n, // Active low reset
    input  wire        en,  // Tín hiệu cho phép cập nhật (en = 0 tương đương với Stall)

    // --- 1. TÍN HIỆU DỰ ĐOÁN NHÁNH (Từ Branch Predictor / BTB) ---
    // Dùng để nạp địa chỉ nhảy trước khi biết kết quả thật
    input  wire        predict_taken,     // 1 = Đoán là sẽ nhảy, 0 = Không nhảy
    input  wire [31:0] predict_target_pc, // Địa chỉ nhảy tới nếu đoán là nhảy

    // --- 2. TÍN HIỆU SỬA SAI TỪ ROB (Độ ưu tiên cao nhất) ---
    input  wire        rob_flush,         // 1 = Chết dở, đoán sai rồi, quay xe!
    input  wire [31:0] rob_flush_pc,      // Địa chỉ đúng do ROB gửi về

    // --- 3. ĐẦU RA ---
    output reg  [31:0] addr_out
);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Khởi tạo PC tại địa chỉ bắt đầu của Instruction Memory (ví dụ 0x0000_0000)
            addr_out <= 32'h0000_0000; 
        end 
        else if (rob_flush) begin
            // ƯU TIÊN SỐ 1: ROB bảo quay xe là bỏ hết, ép PC về địa chỉ đúng
            addr_out <= rob_flush_pc;
        end 
        else if (en) begin
            // ƯU TIÊN SỐ 2: Pipeline đang chạy bình thường (Không bị Stall)
            if (predict_taken) begin
                // Nếu bộ dự đoán bảo nhảy -> Lấy địa chỉ nhảy
                addr_out <= predict_target_pc;
            end else begin
                // MẶC ĐỊNH: Chạy tuần tự (Gộp PC + 4 trực tiếp vào đây)
                addr_out <= addr_out + 32'd4;
            end
        end
        // Nếu en == 0 (bị Stall) và không có Flush: PC giữ nguyên giá trị, chờ giải quyết tắc nghẽn
    end

endmodule