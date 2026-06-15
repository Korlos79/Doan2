module addition_subtraction(
    input        clk,
    input        rst_n,          
    input        start,        
    input  [3:0] tag_in,       
    input        op_sub,
    input  [31:0] a, b,
    output reg [31:0] out,
    output reg valid_out,      
    output reg [3:0] tag_out   
);

    reg [2:0] v_pipe;          
    reg [3:0] tag_pipe [0:2];  

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            v_pipe <= 3'b0;
            tag_pipe[0] <= 4'b0;
            tag_pipe[1] <= 4'b0;
            tag_pipe[2] <= 4'b0;
        end else begin 
            v_pipe <= {v_pipe[1:0], start};
            tag_pipe[0] <= tag_in;
            tag_pipe[1] <= tag_pipe[0];
            tag_pipe[2] <= tag_pipe[1];
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_out <= 1'b0;
            tag_out   <= 4'b0;
        end else begin     
            valid_out <= v_pipe[2];
            tag_out   <= tag_pipe[2];
        end
    end

    // ---- STAGE 1: Unpack & Align (1st Register) ----
    // [FIX-ADD-PIPELINE] Gated với start: chỉ latch khi start=1
    // Nếu không gate, khi start=0 Stage1 vẫn latch a,b,op_sub stale/rác
    // → Stage2 nhận data sai ở cycle giữa 2 lệnh liên tiếp
    reg [23:0] m_large_s2, m_small_align_s2;
    reg [7:0]  e_large_s2;
    reg        sign_s2, is_sub_s2, close_path_s2;
    reg        valid_s2;  // valid gate cho stage2

    wire s1      = a[31];
    wire s2_sig  = b[31] ^ op_sub;
    wire [7:0] e1 = a[30:23], e2 = b[30:23];
    wire [23:0] m1 = (e1 == 8'd0) ? 24'd0 : {1'b1, a[22:0]};
    wire [23:0] m2 = (e2 == 8'd0) ? 24'd0 : {1'b1, b[22:0]};

    wire a_gt  = (e1 > e2) | (e1 == e2 & m1 >= m2);
    wire [7:0] d_exp = a_gt ? (e1 - e2) : (e2 - e1);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            m_large_s2 <= 0; e_large_s2 <= 0; sign_s2 <= 0;
            is_sub_s2 <= 0; close_path_s2 <= 0; m_small_align_s2 <= 0;
            valid_s2 <= 0;
        end else if (start) begin   // [FIX] chỉ latch khi start=1
            m_large_s2       <= a_gt ? m1 : m2;
            e_large_s2       <= a_gt ? e1 : e2;
            sign_s2          <= a_gt ? s1 : s2_sig;
            is_sub_s2        <= s1 ^ s2_sig;
            close_path_s2    <= (s1 ^ s2_sig) & (d_exp <= 8'd1);
            m_small_align_s2 <= (a_gt ? m2 : m1) >> d_exp;
            valid_s2 <= 1'b1;
        end else begin
            valid_s2 <= 1'b0;  // không có lệnh mới → invalid
        end
    end

    // ---- STAGE 2: Add / Sub (2nd Register) ----
    // [FIX-ADD-PIPELINE] Gate với valid_s2
    reg [24:0] res_m_s3;
    reg [7:0]  e_large_s3;
    reg        sign_s3, close_path_s3;
    reg        valid_s3;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            res_m_s3 <= 0; e_large_s3 <= 0; sign_s3 <= 0;
            close_path_s3 <= 0; valid_s3 <= 0;
        end else if (valid_s2) begin  // [FIX] chỉ latch khi data valid
            res_m_s3 <= is_sub_s2
                ? ({1'b0, m_large_s2} - {1'b0, m_small_align_s2})
                : ({1'b0, m_large_s2} + {1'b0, m_small_align_s2});
            e_large_s3    <= e_large_s2;
            sign_s3       <= sign_s2;
            close_path_s3 <= close_path_s2;
            valid_s3      <= 1'b1;
        end else begin
            valid_s3 <= 1'b0;
        end
    end

    // ---- STAGE 3a: LZC (3rd Register) ----
    // [FIX-ADD-PIPELINE] Gate với valid_s3
    reg [4:0]  sh_amt_s4;
    reg [24:0] res_m_s4;
    reg [7:0]  e_large_s4;
    reg        sign_s4, close_path_s4;
    reg        valid_s4;

    wire [4:0] sh_amt_comb;
    lzc_24 u_lzc (.in(res_m_s3[23:0]), .out(sh_amt_comb));

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sh_amt_s4 <= 0; res_m_s4 <= 0; e_large_s4 <= 0;
            sign_s4 <= 0; close_path_s4 <= 0; valid_s4 <= 0;
        end else if (valid_s3) begin  // [FIX]
            sh_amt_s4     <= sh_amt_comb;
            res_m_s4      <= res_m_s3;
            e_large_s4    <= e_large_s3;
            sign_s4       <= sign_s3;
            close_path_s4 <= close_path_s3;
            valid_s4      <= 1'b1;
        end else begin
            valid_s4 <= 1'b0;
        end
    end

    // ---- STAGE 3b: Normalize & Pack (4th Register - Output) ----
    // [FIX-ADD-PIPELINE] Gate với valid_s4
    wire [23:0] m_norm_close = res_m_s4[23:0] << sh_amt_s4;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out <= 32'd0;
        end else if (valid_s4) begin  // [FIX] chỉ ghi output khi valid
            if (close_path_s4) begin
                out <= (res_m_s4[23:0] == 24'd0)
                    ? 32'd0
                    : {sign_s4, (e_large_s4 - {3'd0, sh_amt_s4}), m_norm_close[22:0]};
            end else begin
                out <= res_m_s4[24]
                    ? {sign_s4, e_large_s4 + 8'd1, res_m_s4[23:1]}
                    : {sign_s4, e_large_s4,         res_m_s4[22:0]};
            end
        end
        // valid_s4=0 → giữ nguyên out (không overwrite kết quả hợp lệ trước)
    end

endmodule