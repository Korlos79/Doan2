module ConvfromSignInt(
    input  [31:0] int_in,
    output reg [31:0] float_out
);
    reg sign;
    reg [31:0] abs_val;
    reg [7:0] exponent;
    reg [22:0] mantissa;
    integer i;
    reg [31:0] shifted; // Sửa độ rộng cho khớp logic

    always @(*) begin
        if (int_in == 32'd0) begin
            float_out = 32'd0;
        end else begin
            // 1. Lấy dấu và trị tuyệt đối
            sign = int_in[31];
            // Lưu ý: Nếu int_in là -2147483648 (0x80000000), abs_val vẫn là 0x80000000
            // Logic dưới vẫn xử lý đúng trường hợp này.
            abs_val = sign ? (-int_in) : int_in;

            // 2. Tìm vị trí bit '1' cao nhất (Priority Encoder)
            i = 31;
            while (i > 0 && abs_val[i] == 1'b0) begin
                i = i - 1;
            end

            // 3. Tính exponent (bias = 127)
            exponent = 8'd127 + i[7:0];

            // 4. Dịch bit để tạo mantissa
            // i là vị trí bit 1 cao nhất (Hidden bit), mantissa lấy 23 bit sau nó
            if (i > 23)
                shifted = abs_val >> (i - 23);
            else
                shifted = abs_val << (23 - i);

            mantissa = shifted[22:0];

            // 5. Tổ hợp IEEE-754
            float_out = {sign, exponent, mantissa};
        end
    end
endmodule