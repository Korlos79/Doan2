library verilog;
use verilog.vl_types.all;
entity addition_subtraction is
    port(
        clk             : in     vl_logic;
        rst_n           : in     vl_logic;
        start           : in     vl_logic;
        a_operand       : in     vl_logic_vector(31 downto 0);
        b_operand       : in     vl_logic_vector(31 downto 0);
        AddBar_Sub      : in     vl_logic;
        Exception       : out    vl_logic;
        result          : out    vl_logic_vector(31 downto 0);
        busy            : out    vl_logic;
        done            : out    vl_logic
    );
end addition_subtraction;
