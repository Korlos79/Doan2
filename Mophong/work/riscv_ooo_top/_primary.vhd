library verilog;
use verilog.vl_types.all;
entity riscv_ooo_top is
    port(
        clk             : in     vl_logic;
        rst_n           : in     vl_logic;
        alu_op1_check   : out    vl_logic_vector(31 downto 0);
        alu_op2_check   : out    vl_logic_vector(31 downto 0);
        commit_result_check: out    vl_logic_vector(31 downto 0);
        cdb_result_out_check: out    vl_logic_vector(31 downto 0);
        alu_res_check   : out    vl_logic_vector(31 downto 0);
        opcode_check    : out    vl_logic_vector(4 downto 0);
        alu_busy_md_check: out    vl_logic;
        alu_busy_basic_check: out    vl_logic;
        tag             : out    vl_logic_vector(4 downto 0)
    );
end riscv_ooo_top;
