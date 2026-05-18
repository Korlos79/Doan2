`timescale 1ns / 1ps

module fp_mul_tb;

    // =========================================================
    // Tín hiệu
    // =========================================================
    reg         clk;
    reg         rst_n;
    reg         start;
    reg  [3:0]  tag_in;       // Thêm tín hiệu tag_in
    reg  [31:0] floatA, floatB;
    
    wire [31:0] result;
    wire        valid_out;
    wire [3:0]  tag_out;      // Thêm tín hiệu tag_out

    localparam CLK_PERIOD = 10;

    // =========================================================
    // DUT (Cập nhật cổng mới)
    // =========================================================
    fp_mul dut (
        .clk       (clk),
        .rst_n       (rst_n),
        .start     (start),
        .tag_in    (tag_in),  // Kết nối tag_in
        .floatA    (floatA),
        .floatB    (floatB),
        .result    (result),
        .valid_out (valid_out),
        .tag_out   (tag_out)  // Kết nối tag_out
    );

    // =========================================================
    // Clock 100MHz
    // =========================================================
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // =========================================================
    // Task: apply_and_check
    // =========================================================
    integer pass_cnt, fail_cnt;

    task apply_and_check;
        input [31:0] a, b, expected;
        input [63:0] tc_num;
        begin
            // 1. Đưa input, tag và bật start ở cạnh xuống
            @(negedge clk);
            floatA = a;
            floatB = b;
            tag_in = tc_num[3:0]; // Lấy 4 bit cuối của tc_num làm tag
            start  = 1'b1;

            // 2. Sau 1 chu kỳ thì tắt start (tạo xung pulse)
            @(negedge clk);
            start  = 1'b0;

            // 3. Đợi valid_out lên 1 (không quan tâm PIPELINE là bao nhiêu)
            while (!valid_out) @(posedge clk);
            
            // Chờ một chút để kết quả logic ổn định sau cạnh lên
            #1; 

            // 4. Kiểm tra kết quả và đối chiếu Tag
            if (result === expected && tag_out === tc_num[3:0]) begin
                $display("TC%0d PASS | Tag OK (%0d) | %h * %h = %h", tc_num, tag_out, a, b, result);
                pass_cnt = pass_cnt + 1;
            end else begin
                $display("TC%0d FAIL | %h * %h | Got: %h (Tag: %0d) | Exp: %h (Tag: %0d)  <---",
                          tc_num, a, b, result, tag_out, expected, tc_num[3:0]);
                fail_cnt = fail_cnt + 1;
            end
        end
    endtask

    // =========================================================
    // Test cases
    // =========================================================
    initial begin
        // Khởi tạo giá trị
        pass_cnt = 0;
        fail_cnt = 0;
        floatA   = 0;
        floatB   = 0;
        start    = 0;
        tag_in   = 0; // Khởi tạo tag_in
        rst_n      = 0;

        // Reset hệ thống
        #(CLK_PERIOD * 3);
        rst_n = 1;
        repeat(2) @(posedge clk);

        $display("--------------------------------------------------");
        $display("    STARTING FLOATING POINT MULTIPLIER TEST      ");
        $display("--------------------------------------------------");

        //                A           B           Expected    TC#
        apply_and_check(32'h40200000, 32'h40800000, 32'h41200000, 1); //  2.5 * 4.0 = 10.0
        apply_and_check(32'hC0A00000, 32'h40000000, 32'hC1200000, 2); // -5.0 * 2.0 = -10.0
        apply_and_check(32'hBFA00000, 32'hC0000000, 32'h40200000, 3); // -1.25 * -2.0 = 2.5
        apply_and_check(32'h3FD00000, 32'h3FD00000, 32'h40290000, 4); //  1.625 * 1.625 = 2.640625
        apply_and_check(32'h3E200000, 32'h41800000, 32'h40200000, 5); //  0.15625 * 16.0 = 2.5
        apply_and_check(32'h3F800000, 32'h3F800000, 32'h3F800000, 6); //  1.0 * 1.0 = 1.0
        apply_and_check(32'h40000000, 32'h40400000, 32'h40C00000, 7); //  2.0 * 3.0 = 6.0
        apply_and_check(32'hC0000000, 32'h40800000, 32'hC1000000, 8); // -2.0 * 4.0 = -8.0
        apply_and_check(32'h3FC00000, 32'h3FC00000, 32'h40100000, 9); //  1.5 * 1.5 = 2.25
        apply_and_check(32'h40C00000, 32'h40E00000, 32'h42280000, 10);//  6.0 * 7.0 = 42.0

        $display("--------------------------------------------------");
        $display("  TOTAL: %0d | PASS: %0d | FAIL: %0d",
                  pass_cnt+fail_cnt, pass_cnt, fail_cnt);
        if (fail_cnt == 0)
            $display("  >>> ALL TESTS PASSED <<<");
        else
            $display("  >>> FAILED: %0d case(s) <<<", fail_cnt);
        $display("--------------------------------------------------");

        $finish;
    end

    // Waveform dump
    initial begin
        $dumpfile("fp_mul_tb.vcd");
        $dumpvars(0, fp_mul_tb);
    end

endmodule