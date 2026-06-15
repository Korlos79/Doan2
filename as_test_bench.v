`timescale 1ns/1ps

module as_test_bench;
    reg clk;
    reg rst_n;
    reg start;
    reg [3:0] tag_in; // Thêm tín hiệu tag_in
    reg op_sub;
    reg [31:0] a, b;
    
    wire [31:0] out;
    wire valid_out;
    wire [3:0] tag_out; // Thêm tín hiệu tag_out

    // =========================================================
    // DUT Connection
    // =========================================================
    addition_subtraction dut (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .tag_in(tag_in),   // Kết nối tag_in
        .op_sub(op_sub),
        .a(a),
        .b(b),
        .out(out),
        .valid_out(valid_out),
        .tag_out(tag_out)  // Kết nối tag_out
    );

    // =========================================================
    // Clock Generation (181MHz)
    // =========================================================
    initial begin
        clk = 0;
        forever #2.75 clk = ~clk; 
    end

    // =========================================================
    // Task: run_test
    // =========================================================
    task run_test(
        input integer id, 
        input [31:0] in_a, 
        input [31:0] in_b, 
        input sub, 
        input [31:0] expected
    );
        begin
            // 1. Đưa dữ liệu và Tag vào ở cạnh xuống (negedge)
            @(negedge clk);
            a = in_a;
            b = in_b;
            tag_in = id[3:0]; // Sử dụng 4 bit của id làm tag
            op_sub = sub;
            start = 1'b1;

            // 2. Tắt start sau 1 chu kỳ (tạo xung pulse)
            @(negedge clk);
            start = 1'b0;
            
            // 3. Đợi cho đến khi hardware báo kết quả đã xong
            while (!valid_out) @(posedge clk);
            
            // 4. Kiểm tra kết quả
            #1; // Trễ cực nhỏ để logic ổn định
            if (out === expected && tag_out === id[3:0])
                $display("TEST %0d PASS | Tag OK (%0d) | Result: %h", id, tag_out, out);
            else
                $display("TEST %0d FAIL | Result: %h (Exp: %h) | Tag_out: %0d (Exp: %0d) <---", 
                         id, out, expected, tag_out, id[3:0]);
        end
    endtask

    // =========================================================
    // Main Test Sequence
    // =========================================================
    initial begin
        $display("--- Bat dau kiem tra FPU Add/Sub 4-Stage (Start/Valid Protocol with Tags) ---");
        
        // Khởi tạo các tín hiệu
        a = 0; b = 0; op_sub = 0; start = 0; tag_in = 0;
        rst_n = 0;
        
        // Reset hệ thống 3 chu kỳ
        #15;
        rst_n = 1;
        repeat(2) @(posedge clk);

        // --- Danh sách Test Cases ---

        // TEST 2: 2.5 + 1.0 = 3.5
        run_test(2, 32'h40200000, 32'h3f800000, 0, 32'h40600000);

        // TEST 3: 2.5 - 1.0 = 1.5 (3fc00000)
        run_test(5, 32'h40200000, 32'h3f800000, 1, 32'h3fc00000);

        // TEST 4: Pi + 10^-8 (FAR path)
        run_test(4, 32'h40490fdb, 32'h332b1662, 0, 32'h40490fdb);

        // TEST 5: -1235.1 + 1.1 = -1234.0
        run_test(3, 32'hc49a6333, 32'h3f8ccccd, 0, 32'hc49a4000);

        // TEST 6: -1235.1 - (-1.1) = -1234.0
        run_test(6, 32'hc49a6333, 32'hbf8ccccd, 1, 32'hc49a4000);

        // TEST 7: Pi - 10^-8
        run_test(7, 32'h40490fdb, 32'h332b1662, 1, 32'h40490fdb);

        $display("--- Hoan thanh tat ca cac test case ---");
        $finish;
    end

    // Waveform dump để debug
    initial begin
        $dumpfile("as_test.vcd");
        $dumpvars(0, as_test_bench);
    end

endmodule