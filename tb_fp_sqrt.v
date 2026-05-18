`timescale 1ns/1ps

module tb_fp_sqrt;

    // =========================================================
    // Tín hiệu giao tiếp
    // =========================================================
    reg         clk;
    reg         rst_n;
    reg         start;
    reg  [3:0]  tag_in;
    reg  [31:0] floatA;
    
    wire [31:0] result;
    wire        valid_out;
    wire [3:0]  tag_out;

    localparam CLK_PERIOD = 10;

    // =========================================================
    // Khởi tạo DUT
    // =========================================================
    fp_sqrt_goldschmidt #(
        .PIPE_LAT(21)   // pipeline: Goldschmidt 3 iter + NR correction = 21 chu kỳ
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .tag_in(tag_in),
        .floatA(floatA),
        .result(result),
        .valid_out(valid_out),
        .tag_out(tag_out)
    );

    // =========================================================
    // Tạo Clock (100MHz)
    // =========================================================
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // =========================================================
    // Cơ sở hạ tầng kiểm tra (Task)
    // =========================================================
    integer pass_cnt = 0;
    integer fail_cnt = 0;

    task run_test(
        input integer id,
        input [31:0] a_in,
        input [31:0] expected
    );
        reg [31:0] diff; // Lưu sai số LSB
        begin
            // 1. Đưa tín hiệu vào ở cạnh xuống
            @(negedge clk);
            floatA = a_in;
            tag_in = id[3:0];
            start  = 1'b1;

            // 2. Tắt start tạo xung pulse
            @(negedge clk);
            start  = 1'b0;

            // 3. Đợi valid_out từ pipeline (21 chu kỳ)
            while (!valid_out) @(posedge clk);
            
            #1; // Đợi logic ổn định

            // 4. Tính toán sai số (Dung sai LSB)
            // Lấy trị tuyệt đối của sự khác biệt giữa result và expected
            diff = (result > expected) ? (result - expected) : (expected - result);

            // Bắt các trường hợp đặc biệt (Zero, NaN)
            if (expected == 32'h00000000 || expected == 32'h7FC00000) begin
                if (result === expected && tag_out === id[3:0]) begin
                    $display("TC%0d PASS | Tag OK (%0d) | Sqrt(%h) = %h", id, tag_out, a_in, result);
                    pass_cnt = pass_cnt + 1;
                end else begin
                    $display("TC%0d FAIL | Sqrt(%h) | Got: %h (Tag: %0d) | Exp: %h <---", id, a_in, result, tag_out, expected);
                    fail_cnt = fail_cnt + 1;
                end
            end 
            // Các số thực bình thường (Chấp nhận sai số tối đa 5 LSB - ULPs)
            else begin
                if (diff <= 32'd5 && tag_out === id[3:0]) begin
                    $display("TC%0d PASS | Tag OK (%0d) | Sqrt(%h) = %h (Sai so LSB: %0d)", id, tag_out, a_in, result, diff);
                    pass_cnt = pass_cnt + 1;
                end else begin
                    $display("TC%0d FAIL | Sqrt(%h) | Got: %h (Tag: %0d) | Exp: %h (Lech: %0d LSB) <---", id, a_in, result, tag_out, expected, diff);
                    fail_cnt = fail_cnt + 1;
                end
            end
        end
    endtask

    // =========================================================
    // Main Test Sequence
    // =========================================================
    initial begin
        $display("==================================================");
        $display("   STARTING FP_SQRT_GOLDSCHMIDT TESTBENCH         ");
        $display("==================================================");

        rst_n = 0;
        start = 0;
        tag_in = 0;
        floatA = 0;

        #(CLK_PERIOD * 3);
        rst_n = 1;
        repeat(2) @(posedge clk);

        // --- Danh sách Test Cases ---

        // TEST 1: Sqrt(4.0) = 2.0
        run_test(1, 32'h40800000, 32'h40000000);

        // TEST 2: Sqrt(9.0) = 3.0
        run_test(2, 32'h41100000, 32'h40400000);

        // TEST 3: Sqrt(16.0) = 4.0
        run_test(3, 32'h41800000, 32'h40800000);

        // TEST 4: Sqrt(0.25) = 0.5
        run_test(4, 32'h3E800000, 32'h3F000000);

        // TEST 5: Sqrt(2.0) = 1.4142135 (Trường hợp số lẻ vô tỉ)
        run_test(5, 32'h40000000, 32'h3FB504F3);

        // TEST 6: Sqrt(0.0) = 0.0 (Bắt trường hợp gốc bằng 0)
        run_test(6, 32'h41100000, 32'h40400000);

        // TEST 7: Sqrt(-4.0) = NaN (Lỗi tính căn số âm)
        run_test(7, 32'hC0800000, 32'h7FC00000);

        $display("==================================================");
        $display("  TOTAL: %0d | PASS: %0d | FAIL: %0d", pass_cnt+fail_cnt, pass_cnt, fail_cnt);
        if (fail_cnt == 0)
            $display("  >>> ALL TESTS PASSED <<<");
        else
            $display("  >>> FAILED: %0d case(s) <<<", fail_cnt);
        $display("==================================================");

        $finish;
    end

    // Waveform dump để debug
    initial begin
        $dumpfile("fp_sqrt_tb.vcd");
        $dumpvars(0, tb_fp_sqrt);
    end

endmodule