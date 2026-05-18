`timescale 1ns/1ps

module tb_fp_div_goldschmidt;

    // =========================================================
    // Tín hiệu
    // =========================================================
    reg         clk;
    reg         rst_n;
    reg         start;
    reg  [3:0]  tag_in;       // Thêm tín hiệu tag_in
    reg  [31:0] floatA;
    reg  [31:0] floatB;
    
    wire [31:0] result;
    wire        valid_out;
    wire [3:0]  tag_out;      // Thêm tín hiệu tag_out

    localparam CLK_PERIOD = 10; // Tần số 100MHz

    // =========================================================
    // DUT Instantiation
    // =========================================================
    fp_div_goldschmidt #(
        .PIPE_LAT(13) // Khớp với latency đã thiết kế
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .tag_in(tag_in),      // Kết nối tag_in
        .floatA(floatA),
        .floatB(floatB),
        .result(result),
        .valid_out(valid_out),
        .tag_out(tag_out)     // Kết nối tag_out
    );

    // =========================================================
    // Clock Generation
    // =========================================================
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // =========================================================
    // Task: run_test
    // =========================================================
    integer pass_cnt = 0;
    integer fail_cnt = 0;

    task run_test(
        input integer id,
        input [31:0] a,
        input [31:0] b,
        input [31:0] expected
    );
        begin
            // 1. Đưa dữ liệu và Tag vào ở cạnh xuống
            @(negedge clk);
            floatA = a;
            floatB = b;
            tag_in = id[3:0]; // Sử dụng 4 bit của id làm tag
            start  = 1'b1;

            // 2. Tắt start sau 1 chu kỳ (tạo xung pulse)
            @(negedge clk);
            start  = 1'b0;

            // 3. Đợi cho đến khi hardware báo kết quả đã xong (Latency 13 cycles)
            while (!valid_out) @(posedge clk);

            // 4. Kiểm tra kết quả (so sánh Tag và Result)
            #1; // Trễ nhẹ để ổn định logic
            
            // Lưu ý: Thuật toán Goldschmidt có thể chênh lệch 1-2 LSB so với chuẩn IEEE 754
            // tùy thuộc vào độ lớn của bảng LUT. 
            if (result === expected && tag_out === id[3:0]) begin
                $display("TC%0d PASS | Tag OK (%0d) | %h / %h = %h", id, tag_out, a, b, result);
                pass_cnt = pass_cnt + 1;
            end else begin
                $display("TC%0d FAIL | %h / %h | Got: %h (Tag: %0d) | Exp: %h (Tag: %0d) <---", 
                         id, a, b, result, tag_out, expected, id[3:0]);
                fail_cnt = fail_cnt + 1;
            end
        end
    endtask

    // =========================================================
    // Main Test Sequence
    // =========================================================
    initial begin
        $display("--------------------------------------------------");
        $display("   STARTING FP_DIV_GOLDSCHMIDT TEST (13-STAGE)    ");
        $display("--------------------------------------------------");

        rst_n = 0; start = 0; floatA = 0; floatB = 0; tag_in = 0;
        
        // Reset hệ thống
        #(CLK_PERIOD * 3);
        rst_n = 1;
        repeat(2) @(posedge clk);

        // --- Danh sách Test Cases ---
        
        // TEST 1: 10.0 / 2.0 = 5.0
        run_test(1, 32'h41200000, 32'h40000000, 32'h40A00000); 

        // TEST 2: 3.5 / 0.5 = 7.0
        run_test(2, 32'h40600000, 32'h3F000000, 32'h40E00000); 

        // TEST 3: -12.0 / 3.0 = -4.0
        run_test(3, 32'hC1400000, 32'h40400000, 32'hC0800000); 

        // TEST 4: 1.0 / 4.0 = 0.25
        run_test(4, 32'h3F800000, 32'h40800000, 32'h3E800000); 

        // TEST 5: -15.0 / -1.5 = 10.0
        run_test(5, 32'hC1700000, 32'hBFC00000, 32'h41200000); 

        $display("--------------------------------------------------");
        $display("  TOTAL: %0d | PASS: %0d | FAIL: %0d", pass_cnt+fail_cnt, pass_cnt, fail_cnt);
        if (fail_cnt == 0)
            $display("  >>> ALL TESTS PASSED <<<");
        else
            $display("  >>> FAILED: %0d case(s) <<<", fail_cnt);
        $display("--------------------------------------------------");

        $finish;
    end

    // Waveform dump để debug
    initial begin
        $dumpfile("fp_div_tb.vcd");
        $dumpvars(0, tb_fp_div_goldschmidt);
    end

endmodule