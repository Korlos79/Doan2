`timescale 1ns / 1ps

module FPU_tb;

    // =========================================================================
    //  TÍN HIỆU KẾT NỐI VỚI DUT
    // =========================================================================
    reg         clk;
    reg         rst_n;
    reg         start;
    reg  [3:0]  tag_in;
    reg  [31:0] a_operand;
    reg  [31:0] b_operand;
    reg  [31:0] c_operand;
    reg  [4:0]  FPUOpd;
    
    wire [31:0] result;
    wire [3:0]  tag_out;
    wire        done;
    wire        Exception;

    // Opcode
    localparam FADD     = 5'd0;
    localparam FSUB     = 5'd1;
    localparam FSGNJ    = 5'd9;

    // Bộ nhớ lưu kết quả mong đợi
    reg [31:0] expected_result [0:15];
    integer pass_count;
    integer fail_count;

    // =========================================================================
    //  KẾT NỐI KHỐI FPU (DUT)
    // =========================================================================
    FPU uut (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .tag_in(tag_in),
        .a_operand(a_operand),
        .b_operand(b_operand),
        .c_operand(c_operand),
        .FPUOpd(FPUOpd),
        .result(result),
        .tag_out(tag_out),
        .done(done),
        .Exception(Exception)
    );

    // =========================================================================
    //  GIẢ LẬP ĐỘ TRỄ KHỐI ADDER (4 CYCLES) BẰNG SHIFT REGISTER (CHUẨN VERILOG)
    // =========================================================================
    reg [3:0]  pipe_valid;
    reg [3:0]  pipe_tag [0:3];
    reg [31:0] pipe_res [0:3];
    
    wire [31:0] calc_res = uut.add_a_r + (uut.add_op_sub_r ? (~uut.add_b_r + 1'b1) : uut.add_b_r);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pipe_valid <= 4'b0;
        end else begin
            // Dịch pipeline
            pipe_valid <= {pipe_valid[2:0], uut.add_start_r};
            
            pipe_tag[0] <= uut.add_tag_r;
            pipe_tag[1] <= pipe_tag[0];
            pipe_tag[2] <= pipe_tag[1];
            pipe_tag[3] <= pipe_tag[2];

            pipe_res[0] <= calc_res;
            pipe_res[1] <= pipe_res[0];
            pipe_res[2] <= pipe_res[1];
            pipe_res[3] <= pipe_res[2];
        end
    end
    
    // Gán force kết quả từ tầng cuối của pipeline giả lập (tầng thứ 4)
    initial begin
        force uut.add_valid   = pipe_valid[3];
        force uut.add_tag_out = pipe_tag[3];
        force uut.add_result  = pipe_res[3];
    end

    // Tạo xung Clock
    always #5 clk = ~clk;

    // =========================================================================
    //  TỰ ĐỘNG CHECK KẾT QUẢ
    // =========================================================================
    always @(posedge clk) begin
        if (done) begin
            $display("\n[TIME: %0t ns] >> Nhận DONE từ TAG: %0d", $time, tag_out);
            $display("    -> Thực tế thu được = 32'h%h", result);
            $display("    -> Mong đợi (Expect) = 32'h%h", expected_result[tag_out]);
            
            if (result === expected_result[tag_out]) begin
                $display("    => [RESULT]: PASSED");
                pass_count = pass_count + 1;
            end else begin
                $display("    => [RESULT]: FAILED !!!");
                fail_count = fail_count + 1;
            end
        end
    end

    // =========================================================================
    //  KỊCH BẢN KIỂM THỬ (STIMULUS)
    // =========================================================================
    initial begin
        // Khởi tạo
        clk = 0; rst_n = 0; start = 0; tag_in = 0;
        a_operand = 0; b_operand = 0; c_operand = 0; FPUOpd = 0;
        pass_count = 0; fail_count = 0;
        
        #15; rst_n = 1;
        @(posedge clk);
        $display("=================================================");
        $display("--- BẮT ĐẦU CHẠY KIỂM THỬ TỰ ĐỘNG (VERILOG) ---");
        $display("=================================================");

        // LỆNH 1: FADD (5.5 + 2.25 = 7.75 -> 32'h40f80000)
        start     = 1'b1;
        FPUOpd    = FADD;
        tag_in    = 4'd4; 
        a_operand = 32'h40B00000; // 5.5
        b_operand = 32'h40100000; // 2.25
        expected_result[4] = 32'h40f80000; 
        $display("[INPUT] Đẩy lệnh 1: FADD, gán TAG: %0d", tag_in);
        @(posedge clk);
        
        // LỆNH 2: FSUB gối đầu ngay sau đó (12.0 - 4.5 = 7.5 -> 32'h40f00000)
        start     = 1'b1;
        FPUOpd    = FSUB;
        tag_in    = 4'd7; 
        a_operand = 32'h41400000; // 12.0
        b_operand = 32'h40900000; // 4.5
        expected_result[7] = 32'h40f00000;
        $display("[INPUT] Đẩy lệnh 2: FSUB, gán TAG: %0d", tag_in);
        @(posedge clk);
        start     = 1'b0; 

        // LỆNH TỨC THÌ: FSGNJ (Xen ngang giữa chừng)
        #10;
        @(posedge clk);
        start     = 1'b1;
        FPUOpd    = FSGNJ;
        tag_in    = 4'd2;
        a_operand = 32'h80000000; 
        b_operand = 32'h00000000; 
        expected_result[2] = 32'h00000000; 
        $display("[INPUT] Đẩy lệnh tức thì: FSGNJ, gán TAG: %0d", tag_in);
        @(posedge clk);
        start     = 1'b0;

        // Chờ hoàn thành
        #100;
        
        $display("\n=================================================");
        $display("Tổng số lệnh test thành công (PASS): %0d", pass_count);
        $display("Tổng số lệnh test thất bại   (FAIL): %0d", fail_count);
        $display("=================================================");
        $finish;
    end

endmodule