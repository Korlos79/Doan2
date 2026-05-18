library verilog;
use verilog.vl_types.all;
entity multiplication is
    port(
        clk             : in     vl_logic;
        rst_n           : in     vl_logic;
        start           : in     vl_logic;
        a_in            : in     vl_logic_vector(31 downto 0);
        b_in            : in     vl_logic_vector(31 downto 0);
        result          : out    vl_logic_vector(31 downto 0);
        busy            : out    vl_logic;
        done            : out    vl_logic;
        Exception       : out    vl_logic
    );
end multiplication;
