module mantissa_multiplier (
    input  clk,
    input  [23:0] A, B,
    output reg [47:0] Product
);
    wire [24:0] B25;
    assign B25 = {1'b0, B};

    wire [47:0] p0, p1, p2, p3, p4, p5, p6, p7, p8, p9, p10, p11, p12;
    wire [71:0] pp0, pp1, pp2, pp3, pp4, pp5, pp6, pp7, pp8, pp9, pp10, pp11, pp12;

    // Booth Encoders 
    booth_encoder_radix4 be0  (A, {B25[1], B25[0], 1'b0}, p0);
    booth_encoder_radix4 be1  (A, {B25[3], B25[2], B25[1]}, p1);
    booth_encoder_radix4 be2  (A, {B25[5], B25[4], B25[3]}, p2);
    booth_encoder_radix4 be3  (A, {B25[7], B25[6], B25[5]}, p3);
    booth_encoder_radix4 be4  (A, {B25[9], B25[8], B25[7]}, p4);
    booth_encoder_radix4 be5  (A, {B25[11], B25[10], B25[9]}, p5);
    booth_encoder_radix4 be6  (A, {B25[13], B25[12], B25[11]}, p6);
    booth_encoder_radix4 be7  (A, {B25[15], B25[14], B25[13]}, p7);
    booth_encoder_radix4 be8  (A, {B25[17], B25[16], B25[15]}, p8);
    booth_encoder_radix4 be9  (A, {B25[19], B25[18], B25[17]}, p9);
    booth_encoder_radix4 be10 (A, {B25[21], B25[20], B25[19]}, p10);
    booth_encoder_radix4 be11 (A, {B25[23], B25[22], B25[21]}, p11);
    booth_encoder_radix4 be12 (A, {1'b0, B25[24], B25[23]}, p12);

    // Sign-extend & Shift 
    assign pp0  = {{24{p0[47]}}, p0};
    assign pp1  = {{24{p1[47]}}, p1} << 2;
    assign pp2  = {{24{p2[47]}}, p2} << 4;
    assign pp3  = {{24{p3[47]}}, p3} << 6;
    assign pp4  = {{24{p4[47]}}, p4} << 8;
    assign pp5  = {{24{p5[47]}}, p5} << 10;
    assign pp6  = {{24{p6[47]}}, p6} << 12;
    assign pp7  = {{24{p7[47]}}, p7} << 14;
    assign pp8  = {{24{p8[47]}}, p8} << 16;
    assign pp9  = {{24{p9[47]}}, p9} << 18;
    assign pp10 = {{24{p10[47]}}, p10} << 20;
    assign pp11 = {{24{p11[47]}}, p11} << 22;
    assign pp12 = {{24{p12[47]}}, p12} << 24;

    wire [71:0] s_f, c_f;
    wallace_tree_12_rows wt (
        pp0, pp1, pp2, pp3, pp4, pp5, pp6, pp7, pp8, pp9, pp10, pp11, pp12, 
        s_f, c_f
    );

    // FINAL SUM: Cộng s_f và c_f
    wire [71:0] full_res;
    assign full_res = s_f + c_f; 

    always @(posedge clk) begin
        // Quan trọng: lấy 48-bit thấp của tổng hoàn chỉnh [cite: 46]
        Product <= full_res[47:0]; 
    end
endmodule