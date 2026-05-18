module lzc_24 (
    input  [23:0] in,
    output reg [4:0] out
);
    // Chia thành 4 nhóm 6-bit, kiểm tra song song
    wire has_23_18 = |in[23:18];
    wire has_17_12 = |in[17:12];
    wire has_11_6  = |in[11:6];

    wire [5:0] sel6 = has_23_18 ? in[23:18] :
                      has_17_12 ? in[17:12] :
                      has_11_6  ? in[11:6]  : in[5:0];

    wire [1:0] grp  = has_23_18 ? 2'd0 :
                      has_17_12 ? 2'd1 :
                      has_11_6  ? 2'd2 : 2'd3;

    reg [2:0] fine;
    always @(*) begin
        casex (sel6)
            6'b1xxxxx: fine = 3'd0;
            6'b01xxxx: fine = 3'd1;
            6'b001xxx: fine = 3'd2;
            6'b0001xx: fine = 3'd3;
            6'b00001x: fine = 3'd4;
            default:   fine = 3'd5;
        endcase
    end

    always @(*)
		out = {1'b0, grp, 2'b00} + {2'b0, grp, 1'b0} + {2'b0, fine};
endmodule
