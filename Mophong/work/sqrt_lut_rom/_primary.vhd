library verilog;
use verilog.vl_types.all;
entity sqrt_lut_rom is
    port(
        clk             : in     vl_logic;
        lut_idx         : in     vl_logic_vector(7 downto 0);
        lut_y0          : out    vl_logic_vector(31 downto 0)
    );
end sqrt_lut_rom;
