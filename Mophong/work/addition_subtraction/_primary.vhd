library verilog;
use verilog.vl_types.all;
entity addition_subtraction is
    port(
        clk             : in     vl_logic;
        rst_n           : in     vl_logic;
        start           : in     vl_logic;
        tag_in          : in     vl_logic_vector(3 downto 0);
        op_sub          : in     vl_logic;
        a               : in     vl_logic_vector(31 downto 0);
        b               : in     vl_logic_vector(31 downto 0);
        \out\           : out    vl_logic_vector(31 downto 0);
        valid_out       : out    vl_logic;
        tag_out         : out    vl_logic_vector(3 downto 0)
    );
end addition_subtraction;
