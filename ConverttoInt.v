module ConverttoInt(
    input  [31:0] float_in,
    output reg [31:0] int_out
);
    wire sign = float_in[31];
    wire [7:0] exponent = float_in[30:23];
    wire [22:0] fraction = float_in[22:0];
    
    reg [31:0] value;
    integer E;

    always @(*) begin
        // Exponent thực tế
        E = exponent - 127;

        if (exponent == 8'd0) begin
            // Zero hoặc Subnormal
            int_out = 32'd0;
        end
        else if (exponent < 127) begin
            // |Value| < 1.0 -> 0
            int_out = 32'd0;
        end
        else if (exponent > 157) begin 
            // 158 - 127 = 31. 1.0 * 2^31 tràn số dương signed 32-bit (max 2^31 - 1)
            // Nếu là số âm, -2^31 vẫn biểu diễn được, nhưng logic đơn giản ta coi như tràn.
            int_out = sign ? 32'h80000000 : 32'h7FFFFFFF;
        end
        else begin
            // Khôi phục bit ẩn: 1.fraction
            value = {1'b1, fraction, 8'd0}; // Đặt vào 32 bit, 1.xxxxx...

            // Dịch bit:
            // Mantissa đang ở dạng 1.23bit.
            // Cần dịch phải (23 - E) bit để đưa dấu chấm về đúng chỗ.
            if (E > 23)
                value = {1'b1, fraction} << (E - 23);
            else
                value = {1'b1, fraction} >> (23 - E);

            int_out = sign ? (-value) : value;
        end
    end
endmodule