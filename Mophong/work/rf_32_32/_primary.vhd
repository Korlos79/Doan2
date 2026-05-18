library verilog;
use verilog.vl_types.all;
entity rf_32_32 is
    port(
        clk             : in     vl_logic;
        reg_write       : in     vl_logic;
        rst_n           : in     vl_logic;
        data_write      : in     vl_logic_vector(31 downto 0);
        wa              : in     vl_logic_vector(4 downto 0);
        ra1             : in     vl_logic_vector(4 downto 0);
        ra2             : in     vl_logic_vector(4 downto 0);
        rd1             : out    vl_logic_vector(31 downto 0);
        rd2             : out    vl_logic_vector(31 downto 0)
    );
end rf_32_32;
