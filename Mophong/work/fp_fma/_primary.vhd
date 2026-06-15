library verilog;
use verilog.vl_types.all;
entity fp_fma is
    port(
        clk             : in     vl_logic;
        floatA          : in     vl_logic_vector(31 downto 0);
        floatB          : in     vl_logic_vector(31 downto 0);
        floatC          : in     vl_logic_vector(31 downto 0);
        result          : out    vl_logic_vector(31 downto 0)
    );
end fp_fma;
