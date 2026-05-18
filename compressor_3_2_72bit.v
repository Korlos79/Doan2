module compressor_3_2_72bit (
    input  [71:0] in0, in1, in2,   // FIX: 72-bit (không phải 48-bit)
    output [71:0] sum,
    output [71:0] carry
);
    assign sum   = in0 ^ in1 ^ in2;
    assign carry = ((in0 & in1) | (in1 & in2) | (in0 & in2)) << 1;
endmodule