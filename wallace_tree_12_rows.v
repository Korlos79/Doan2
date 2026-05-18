// wallace_tree_13_rows.v
// Wallace Tree nén 13 partial products (12 Booth + 1 correction) xuống còn 2 (sum + carry)
// Dùng compressor 3:2 (full adder) 72-bit

module wallace_tree_12_rows (
    input [71:0] pp0,  pp1,  pp2,  pp3,
    input [71:0] pp4,  pp5,  pp6,  pp7,
    input [71:0] pp8,  pp9,  pp10, pp11,
    input [71:0] pp12,
    output [71:0] sum,
    output [71:0] carry
);
    // Tầng 1: nén 13 → 9 (4 compressor × 3 = 12, còn 1 pass-through)
    wire [71:0] s1_0, c1_0, s1_1, c1_1, s1_2, c1_2, s1_3, c1_3;

    compressor_3_2_72bit st1_0 (pp0,  pp1,  pp2,  s1_0, c1_0);
    compressor_3_2_72bit st1_1 (pp3,  pp4,  pp5,  s1_1, c1_1);
    compressor_3_2_72bit st1_2 (pp6,  pp7,  pp8,  s1_2, c1_2);
    compressor_3_2_72bit st1_3 (pp9,  pp10, pp11, s1_3, c1_3);
    // pp12 pass-through → 9 signals: s1_0,c1_0, s1_1,c1_1, s1_2,c1_2, s1_3,c1_3, pp12

    // Tầng 2: nén 9 → 6
    wire [71:0] s2_0, c2_0, s2_1, c2_1, s2_2, c2_2;

    compressor_3_2_72bit st2_0 (s1_0, c1_0, s1_1, s2_0, c2_0);
    compressor_3_2_72bit st2_1 (c1_1, s1_2, c1_2, s2_1, c2_1);
    compressor_3_2_72bit st2_2 (s1_3, c1_3, pp12, s2_2, c2_2);
    // 6 signals: s2_0,c2_0, s2_1,c2_1, s2_2,c2_2

    // Tầng 3: nén 6 → 4
    wire [71:0] s3_0, c3_0, s3_1, c3_1;

    compressor_3_2_72bit st3_0 (s2_0, c2_0, s2_1, s3_0, c3_0);
    compressor_3_2_72bit st3_1 (c2_1, s2_2, c2_2, s3_1, c3_1);

    // Tầng 4: nén 4 → 3
    wire [71:0] s4, c4;
    compressor_3_2_72bit st4_0 (s3_0, c3_0, s3_1, s4, c4);

    // Tầng 5: nén 3 → 2
    compressor_3_2_72bit st5_0 (s4, c4, c3_1, sum, carry);

endmodule