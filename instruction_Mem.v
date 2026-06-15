module instruction_Mem (
    input [31:0] addr,
	 output reg [31:0] inst
);
   reg [31:0] i_mem [63:0]; 
	
	initial begin
		$readmemh ("D:/RISCV_Pipelined_IFM_AXI4_OoO_v2/TestCase/FP.txt", i_mem);
   end
	 
	always @(*) begin
		inst = i_mem[addr[31:2]];
	end
	 
endmodule