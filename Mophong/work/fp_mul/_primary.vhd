library verilog;
use verilog.vl_types.all;
entity fp_mul is
    port(
        clk             : in     vl_logic;
        rst_n           : in     vl_logic;
        start           : in     vl_logic;
        tag_in          : in     vl_logic_vector(3 downto 0);
        floatA          : in     vl_logic_vector(31 downto 0);
        floatB          : in     vl_logic_vector(31 downto 0);
        result          : out    vl_logic_vector(31 downto 0);
        valid_out       : out    vl_logic;
        tag_out         : out    vl_logic_vector(3 downto 0)
    );
end fp_mul;
