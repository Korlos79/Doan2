library verilog;
use verilog.vl_types.all;
entity alu is
    port(
        clk             : in     vl_logic;
        rst_n           : in     vl_logic;
        A               : in     vl_logic_vector(31 downto 0);
        B               : in     vl_logic_vector(31 downto 0);
        opcode          : in     vl_logic_vector(4 downto 0);
        branch          : in     vl_logic_vector(2 downto 0);
        alu_result      : out    vl_logic_vector(31 downto 0);
        md_result       : out    vl_logic_vector(31 downto 0);
        md_busy         : out    vl_logic;
        md_done         : out    vl_logic;
        Z               : out    vl_logic
    );
end alu;
