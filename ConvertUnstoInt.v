module ConvertUnstoInt(
    input  [31:0] float_in,
    output reg [31:0] int_out
);
    wire sign = float_in[31];
    wire [7:0] exponent = float_in[30:23];
    wire [22:0] fraction = float_in[22:0];
    
    reg [31:0] value;
    integer E;

    always @(*) begin
        E = exponent - 127;

        if (sign) begin
            // Số âm -> 0 (theo chuẩn ép kiểu C/C++)
            int_out = 32'd0;
        end
        else if (exponent < 127) begin
            // < 1.0 -> 0
            int_out = 32'd0;
        end
        // Sửa ngưỡng tràn: Unsigned max là 2^32-1 (Exponent ~ 158 là 2^31, vẫn OK)
        // 2^32 tương ứng exponent = 127 + 32 = 159
        else if (exponent >= 159) begin 
            int_out = 32'hFFFFFFFF; // Max Unsigned
        end
        else begin
            if (E > 23)
                value = {1'b1, fraction} << (E - 23);
            else
                value = {1'b1, fraction} >> (23 - E);

            int_out = value;
        end
    end
endmodule