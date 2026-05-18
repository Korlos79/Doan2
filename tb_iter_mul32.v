`timescale 1ns / 1ps

module tb_iter_mul32();

    // --- 1. Signal Declaration ---
    parameter TAG_WIDTH = 4;
    
    reg clk;
    reg rst_n;
    reg start;
    reg [4:0]  op_sel;
    reg [TAG_WIDTH-1:0] tag_in;
    reg [31:0] rs1;
    reg [31:0] rs2;

    wire        done;
    wire [TAG_WIDTH-1:0] tag_out;
    wire [31:0] result;

    // --- 2. Opcodes ---
    localparam OP_MUL    = 5'b10000;
    localparam OP_MULH   = 5'b10001; 
    localparam OP_MULHSU = 5'b10010; 
    localparam OP_MULHU  = 5'b10011; 

    // --- 3. Instantiate DUT ---
    iter_mul32 #(
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

    // --- 4. Clock Generation (100MHz) ---
    initial clk = 0;
    always #5 clk = ~clk;

    // --- 5. Monitor Output ---
    // Hiển thị kết quả dựa trên tín hiệu 'done' và khớp nối bằng 'tag_out'
    integer output_cnt = 0;
    always @(posedge clk) begin
        if (done) begin
            output_cnt = output_cnt + 1;
            $display("[OUTPUT %0d] Time: %t | Tag: %0d | Result: %h (%0d)", 
                     output_cnt, $time, tag_out, result, $signed(result));
        end
    end

    // --- 6. Task: Send Command ---
    reg [TAG_WIDTH-1:0] next_tag = 0;
    task send_cmd;
        input [4:0] opcode;
        input [31:0] in1;
        input [31:0] in2;
        input [127:0] comment; 
        begin
            @(posedge clk);
            start  <= 1;
            op_sel <= opcode;
            tag_in <= next_tag; // Gắn tag tự động tăng
            rs1    <= in1;
            rs2    <= in2;
            
            $display("[INPUT]  Time: %t | Tag: %0d | %0s | RS1=%h, RS2=%h", 
                     $time, next_tag, comment, in1, in2);
            
            next_tag = next_tag + 1;
            @(posedge clk);
            start  <= 0;
        end
    endtask

    // --- 7. Main Test Sequence ---
    initial begin
        // Init
        rst_n = 0; start = 0; op_sel = 0; rs1 = 0; rs2 = 0; tag_in = 0;

        // Reset
        $display("=== RESET SYSTEM ===");
        #25 rst_n = 1;
        #20;

        // --- TEST 1: Các lệnh đơn lẻ ---
        $display("\n=== TEST 1: Single Operations ===");
        send_cmd(OP_MUL, 32'd10, -32'd5, "10 * -5");
        #100; // Đợi trôi qua pipeline

        // --- TEST 2: Pipeline Stress (Đẩy liên tục mỗi chu kỳ) ---
        $display("\n=== TEST 2: Pipeline Throughput (Back-to-back) ===");
        
        // Gửi lệnh liên tục mà không có # delay ở giữa
        // Nhờ 'tag', chúng ta sẽ biết kết quả nào là của lệnh nào
        send_cmd(OP_MUL, 32'd2, 32'd3, "Burst A");
        send_cmd(OP_MUL, 32'd4, 32'd5, "Burst B");
        send_cmd(OP_MUL, 32'd6, 32'd7, "Burst C");
        send_cmd(OP_MUL, 32'd8, 32'd9, "Burst D");

        #150; // Đợi tất cả kết quả ra hết

        // --- TEST 3: MULH (High part) ---
        $display("\n=== TEST 3: MULH Test ===");
        send_cmd(OP_MULH, 32'h7FFFFFFF, 32'd2, "MaxPos * 2");
        
        #100;
        $display("\n=== END OF SIMULATION ===");
        $finish;
    end

endmodule