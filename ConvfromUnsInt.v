module ConvfromUnsInt(
    input  [31:0] int_in,
    output reg [31:0] float_out
);
    reg [31:0] abs_val;
    reg [31:0] shifted;
    reg [7:0] exponent;
    reg [22:0] mantissa;
    integer i;

    always @(*) begin
        if (int_in == 32'd0) begin
            float_out = 32'd0;
        end else begin
            abs_val = int_in;

            // Tìm vị trí bit '1' cao nhất
            i = 31;
            while (i > 0 && abs_val[i] == 1'b0) begin
                i = i - 1;
            end

            exponent = 8'd127 + i[7:0];

            // Dịch bit lấy Mantissa
            if (i > 23)
                shifted = abs_val >> (i - 23);
            else
                shifted = abs_val << (23 - i);

            mantissa = shifted[22:0];

            // Unsigned luôn dương
            float_out = {1'b0, exponent, mantissa};
        end
    end
endmodule