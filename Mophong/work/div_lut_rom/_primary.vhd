library verilog;
use verilog.vl_types.all;
entity div_lut_rom is
    port(
        clk             : in     vl_logic;
        lut_idx         : in     vl_logic_vector(7 downto 0);
        lut_f0          : out    vl_logic_vector(31 downto 0)
    );
end div_lut_rom;
