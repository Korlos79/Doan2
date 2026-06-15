library verilog;
use verilog.vl_types.all;
entity mantissa_multiplier is
    port(
        clk             : in     vl_logic;
        A               : in     vl_logic_vector(23 downto 0);
        B               : in     vl_logic_vector(23 downto 0);
        Product         : out    vl_logic_vector(47 downto 0)
    );
end mantissa_multiplier;
