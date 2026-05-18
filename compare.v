module compare (
    input  [31:0] a_operand, 
    input  [31:0] b_operand,
    input  [1:0]  mode,   // 00: equal, 01: less-than, 10: less-or-equal
    output reg    result
);

    wire signA = a_operand[31];
    wire signB = b_operand[31];
    wire [7:0] expA = a_operand[30:23];
    wire [7:0] expB = b_operand[30:23];
    wire [22:0] fracA = a_operand[22:0];
    // SỬA LỖI QUAN TRỌNG TẠI ĐÂY:
    wire [22:0] fracB = b_operand[22:0]; // Cũ: a_operand -> Mới: b_operand

    // +0.0 == -0.0
    wire both_zero = (a_operand[30:0] == 31'd0) && (b_operand[30:0] == 31'd0);

    always @(*) begin
        result = 1'b0; 

        case(mode)
            // ========= FEQ =========
            2'b00: begin
                if (both_zero) result = 1'b1;
                else if (a_operand == b_operand) result = 1'b1;
                else result = 1'b0;
            end

            // ========= FLT (A < B) =========
            2'b01: begin
                if (both_zero) result = 1'b0;
                else if (signA != signB) begin
                    // Nếu dấu khác nhau: A < B nếu A âm (1) và B dương (0)
                    result = signA; 
                end else begin
                    // Cùng dấu
                    if (signA == 0) begin // Cùng dương
                        if (expA != expB) result = (expA < expB);
                        else result = (fracA < fracB);
                    end else begin // Cùng âm (số có độ lớn lớn hơn thì nhỏ hơn)
                        if (expA != expB) result = (expA > expB);
                        else result = (fracA > fracB);
                    end
                end
            end

            // ========= FLE (A <= B) =========
            2'b10: begin
                if (both_zero) result = 1'b1;
                else if (a_operand == b_operand) result = 1'b1;
                else begin
                    // Logic Less Than (copy từ trên)
                    if (signA != signB) result = signA;
                    else if (signA == 0) result = (a_operand[30:0] < b_operand[30:0]);
                    else result = (a_operand[30:0] > b_operand[30:0]);
                end
            end
            
            default: result = 0;
        endcase
    end
endmodule