module booth_encoder_radix4 (
    input [23:0] multiplier_bit, 
    input [2:0]  code_bits,      
    output reg [47:0] p_out      
);
    wire [47:0] A_ext;
    wire [47:0] A_ext_x2;

    assign A_ext    = {24'b0, multiplier_bit}; // Zero-extend cho mantissa không dấu 
    assign A_ext_x2 = {23'b0, multiplier_bit, 1'b0}; // Tương đương A * 2 -> dịch trái 1 bit  

    always @(*) begin
        case (code_bits)
            3'b000, 3'b111: p_out = 48'b0;
            3'b001, 3'b010: p_out = A_ext; // +1A -> Giữ nguyên A (A_ext)
            3'b011:         p_out = A_ext_x2; // +2A -> Dịch trái A 1 bit (A_ext_x2)
            3'b100:         p_out = (~A_ext_x2) + 48'b1; // -2A -> Đảo bit A_ext_x2 rồi cộng 1 (Bù 2)
            3'b101, 3'b110: p_out = (~A_ext) + 48'b1; // -1A -> Đảo bit A_ext rồi cộng 1 (Bù 2)
            default:        p_out = 48'b0;
        endcase
    end
endmodule