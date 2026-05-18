`timescale 1ns / 1ps

module tb_iter_div32();

    // --- 0. Khai báo tham số và tín hiệu ---
    parameter TAG_WIDTH = 4;
    
    reg          clk;
    reg          rst_n;
    reg          start;
    reg  [4:0]   op_sel;
    reg  [TAG_WIDTH-1:0] tag_in;
    reg  [31:0]  rs1, rs2;

    wire         done;
    wire [TAG_WIDTH-1:0] tag_out;
    wire [31:0]  result;

    // FIFO để lưu thông tin mong đợi (Kết quả + TAG)
    reg [31:0]            expected_res_fifo [0:255];
    reg [TAG_WIDTH-1:0]   expected_tag_fifo [0:255];
    integer wr_ptr = 0; 
    integer rd_ptr = 0; 
    
    integer pass_count = 0;
    integer fail_count = 0;
    integer i;

    // --- 1. Khởi tạo Module (DUT) ---
    iter_div32 #(
        .TAG_WIDTH(TAG_WIDTH)
    ) uut (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .op_sel(op_sel),
        .tag_in(tag_in),
        .rs1(rs1),
        .rs2(rs2),
        .done(done),
        .tag_out(tag_out),
        .result(result)
    );

    // --- 2. Tạo xung Clock ---
    always #5 clk = ~clk;

    // --- 3. Khối điều khiển (Driver) ---
    initial begin
        clk = 0; rst_n = 0; start = 0;
        rs1 = 0; rs2 = 0; op_sel = 0; tag_in = 0;
        
        #20 rst_n = 1; 
        repeat(2) @(posedge clk);

        $display("--- BAT DAU KIEM TRA PIPELINE VOI TAG ---");

        // TEST CASE 1: Continuous Burst (Gửi liên tục lệnh với TAG tăng dần)
        for (i = 0; i < 40; i = i + 1) begin
            send_op(5'b10100, i * 15, 4, i[TAG_WIDTH-1:0]); 
        end

        // TEST CASE 2: RISC-V Edge Cases (Chia cho 0, Tràn số)
        send_op(5'b10100, 100, 0, 4'd10);          // DIV / 0
        send_op(5'b10110, 100, 0, 4'd11);          // REM / 0
        send_op(5'b10100, 32'h8000_0000, 32'hFFFF_FFFF, 4'd12); // Overflow

        // Đợi đến khi toàn bộ pipeline xả hết kết quả
        wait (rd_ptr == wr_ptr);
        repeat(5) @(posedge clk);

        $display("--------------------------------------------------");
        $display("TONG KET: PASS = %d | FAIL = %d", pass_count, fail_count);
        if (fail_count == 0) 
            $display(">>> KET QUA: [PASS] - TAG va Du lieu khop hoan hao!");
        else 
            $display(">>> KET QUA: [FAIL] - Co loi logic!");
        $display("--------------------------------------------------");
        $finish;
    end

    // --- 4. Task gửi lệnh (Cập nhật TAG) ---
    task send_op(
        input [4:0] sel, 
        input [31:0] a, 
        input [31:0] b, 
        input [TAG_WIDTH-1:0] t
    );
        reg [31:0] ref_res;
        begin
            @(posedge clk);
            start  = 1;
            op_sel = sel;
            rs1    = a;
            rs2    = b;
            tag_in = t;
            
            // Reference Model (Theo chuẩn RISC-V và xử lý Tag)
            case(sel)
                5'b10100: begin // DIV
                    if (b == 0) ref_res = 32'hFFFF_FFFF;
                    else if (a == 32'h8000_0000 && b == 32'hFFFF_FFFF) ref_res = 32'h8000_0000;
                    else ref_res = $signed(a) / $signed(b);
                end
                5'b10101: begin // DIVU
                    if (b == 0) ref_res = 32'hFFFF_FFFF;
                    else ref_res = a / b;
                end
                5'b10110: begin // REM
                    if (b == 0) ref_res = a;
                    else if (a == 32'h8000_0000 && b == 32'hFFFF_FFFF) ref_res = 0;
                    else ref_res = $signed(a) % $signed(b);
                end
                5'b10111: begin // REMU
                    if (b == 0) ref_res = a;
                    else ref_res = a % b;
                end
                default: ref_res = 0;
            endcase
            
            expected_res_fifo[wr_ptr] = ref_res;
            expected_tag_fifo[wr_ptr] = t;
            wr_ptr = wr_ptr + 1;
            
            @(posedge clk);
            start = 0; // Luôn hạ start sau 1 chu kỳ
        end
    endtask

    // --- 5. Khối Checker (Kiểm tra cả Result và TAG) ---
    always @(posedge clk) begin
        if (done) begin
            if (result === expected_res_fifo[rd_ptr] && tag_out === expected_tag_fifo[rd_ptr]) begin
                $display("[OK] Time:%0t | TAG:%d | Out:%h", $time, tag_out, result);
                pass_count = pass_count + 1;
            end else begin
                $display("[ERR] Time:%0t | TAG_Out:%d (Exp:%d) | Out:%h (Exp:%h)", 
                          $time, tag_out, expected_tag_fifo[rd_ptr], result, expected_res_fifo[rd_ptr]);
                fail_count = fail_count + 1;
            end
            rd_ptr = rd_ptr + 1;
        end
    end

endmodule