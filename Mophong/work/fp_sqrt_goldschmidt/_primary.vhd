library verilog;
use verilog.vl_types.all;
entity fp_sqrt_goldschmidt is
    generic(
        PIPE_LAT        : integer := 21
    );
    port(
        clk             : in     vl_logic;
        rst_n           : in     vl_logic;
        start           : in     vl_logic;
        tag_in          : in     vl_logic_vector(3 downto 0);
        floatA          : in     vl_logic_vector(31 downto 0);
        result          : out    vl_logic_vector(31 downto 0);
        valid_out       : out    vl_logic;
        tag_out         : out    vl_logic_vector(3 downto 0)
    );
    attribute mti_svvh_generic_type : integer;
    attribute mti_svvh_generic_type of PIPE_LAT : constant is 1;
end fp_sqrt_goldschmidt;
