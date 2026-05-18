`timescale 1ns / 1ps

module fpu_top_tb;

    // =========================================================
    // Tín hiệu giao tiếp DUT
    // =========================================================
    reg         clk;
    reg         rst_n;
    reg         valid_in;
    // Opcode 3-bit: 000 (Add), 001 (Sub), 010 (Mul), 011 (Div), 100 (Sqrt)
    reg  [2:0]  opcode; 
    reg  [31:0] a;
    reg  [31:0] b;
    wire rob_full;
    wire [31:0] result_out;
    wire        valid_out;
	 
    localparam CLK_PERIOD = 10;

    // =========================================================
    // Khởi tạo DUT (Top-Level FPU)
    // SỬA LỖI Ở ĐÂY: Đổi từ fpu_ooo_rob thành fpu_top
    // =========================================================
    fpu_top dut (
        .clk(clk),
        .rst_n(rst_n),
        .valid_in(valid_in),
        .opcode(opcode),
        .a(a),
        .b(b),
        .result_out(result_out),
        .valid_out(valid_out),
		  .rob_full(rob_full)
    );

    // =========================================================
    // Tạo Clock
    // =========================================================
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // =========================================================
    // Cơ sở hạ tầng Kiểm tra (Checker Infrastructure)
    // =========================================================
    // Hàng đợi lưu kết quả kỳ vọng (Kích thước 64 để chống tràn)
    reg [31:0] expected_queue [0:63];
    reg [2:0]  opcode_queue   [0:63];
    integer    q_tail = 0; // Con trỏ nạp kết quả kỳ vọng
    integer    q_head = 0; // Con trỏ kiểm tra kết quả thực tế
    
    integer    pass_cnt = 0;
    integer    fail_cnt = 0;
    integer    total_inst = 0; // Tự động đếm số lệnh

    // Task phát lệnh (Issue Instruction)
    task issue_inst(
        input [2:0]  op_in, // Opcode 3-bit
        input [31:0] a_in,
        input [31:0] b_in,
        input [31:0] exp_res
    );
        begin
            @(negedge clk); // Đưa tín hiệu vào ở cạnh xuống
            valid_in = 1'b1;
            opcode   = op_in;
            a        = a_in;
            b        = b_in;
            
            // Lưu lại kết quả kỳ vọng vào FIFO để check sau
            expected_queue[q_tail] = exp_res;
            opcode_queue[q_tail]   = op_in;
            
            // Quay vòng con trỏ an toàn và tự tăng số lệnh
            q_tail = (q_tail + 1) % 64;
            total_inst = total_inst + 1; 
        end
    endtask

    // Task ngừng phát lệnh
    task stall_issue();
        begin
            @(negedge clk);
            valid_in = 1'b0;
        end
    endtask

    // =========================================================
    // Tiến trình Màn hình theo dõi Output (Commit Monitor)
    // =========================================================
    always @(posedge clk) begin
        if (valid_out) begin
            if (result_out === expected_queue[q_head]) begin
                $display("[%4t ns] COMMIT [%0d] PASS | OP: %b | Result: %h", 
                         $time, q_head, opcode_queue[q_head], result_out);
                pass_cnt = pass_cnt + 1;
            end else begin
                $display("[%4t ns] COMMIT [%0d] FAIL | OP: %b | Got: %h | Expected: %h <--- ERROR!", 
                         $time, q_head, opcode_queue[q_head], result_out, expected_queue[q_head]);
                fail_cnt = fail_cnt + 1;
            end
            
            q_head = (q_head + 1) % 64; // Quay vòng an toàn
        end
    end

    // =========================================================
    // Main Test Sequence
    // =========================================================
    initial begin
        $display("==================================================");
        $display("   STARTING FPU OUT-OF-ORDER (ROB) TESTBENCH      ");
        $display("==================================================");

        // Khởi tạo
        rst_n = 0;
        valid_in = 0;
        opcode = 0;
        a = 0; b = 0;
        
        #(CLK_PERIOD * 3);
        rst_n = 1;
        repeat(2) @(posedge clk);

        $display("\n--- [ISSUE PHASE] Pumping back-to-back instructions ---");
        
        // Lệnh 0: CĂN BẬC HAI (SQRT) - Mất 21 chu kỳ
        // sqrt(4.0) = 2.0
        issue_inst(3'b100, 32'h40800000, 32'h00000000, 32'h40000000); 

        // Lệnh 1: CHIA (DIV) - Mất 13 chu kỳ
        // 10.0 / 2.0 = 5.0
        issue_inst(3'b011, 32'h41200000, 32'h40000000, 32'h40A00000); 

        // Lệnh 2: NHÂN (MUL) - Mất 3 chu kỳ
        // 2.5 * 4.0 = 10.0
        issue_inst(3'b010, 32'h40200000, 32'h40800000, 32'h41200000); 

        // Lệnh 3: CỘNG (ADD) - Mất 4 chu kỳ
        // 2.5 + 1.0 = 3.5
        issue_inst(3'b000, 32'h40200000, 32'h3F800000, 32'h40600000); 

        // Lệnh 4: TRỪ (SUB) - Mất 4 chu kỳ
        // 2.5 - 1.0 = 1.5
        issue_inst(3'b001, 32'h40200000, 32'h3F800000, 32'h3FC00000); 

        // Lệnh 5: CHIA (DIV) - Mất 13 chu kỳ
        // 3.5 / 0.5 = 7.0
        issue_inst(3'b011, 32'h40600000, 32'h3F000000, 32'h40E00000); 

        // Lệnh 6: NHÂN (MUL) - Mất 3 chu kỳ
        // 1.0 * 1.0 = 1.0
        issue_inst(3'b010, 32'h3F800000, 32'h3F800000, 32'h3F800000); 

        // Lệnh 7: CĂN BẬC HAI (SQRT) - Thêm 1 trường hợp nữa
        // sqrt(16.0) = 4.0
        issue_inst(3'b100, 32'h41800000, 32'h00000000, 32'h40800000); 

        // Ngừng phát lệnh
        stall_issue();
        $display("--- [ISSUE PHASE] Completed. Waiting for Commits... ---\n");

        // Chờ đến khi tất cả các lệnh đã được Commit ra ngoài
        wait (pass_cnt + fail_cnt == total_inst);
        
        // Chờ thêm một chút cho waveform ghi nhận đầy đủ
        #(CLK_PERIOD * 5);

        // Tổng kết
        $display("==================================================");
        $display("  TOTAL INST: %0d | PASS: %0d | FAIL: %0d", total_inst, pass_cnt, fail_cnt);
        if (fail_cnt == 0)
            $display("  >>> SUCCESS: OoO Execution & In-Order Commit OK <<<");
        else
            $display("  >>> FAILED <<<");
        $display("==================================================");

        $finish;
    end

    // Waveform dump
    initial begin
        $dumpfile("fpu_top_tb.vcd");
        $dumpvars(0, fpu_top_tb);
    end

endmodule