library verilog;
use verilog.vl_types.all;
entity Sqrt is
    generic(
        XLEN            : integer := 32
    );
    port(
        clk             : in     vl_logic;
        rst_n           : in     vl_logic;
        start           : in     vl_logic;
        A               : in     vl_logic_vector;
        busy            : out    vl_logic;
        done            : out    vl_logic;
        result          : out    vl_logic_vector;
        exception       : out    vl_logic;
        zero_sqrt       : out    vl_logic
    );
    attribute mti_svvh_generic_type : integer;
    attribute mti_svvh_generic_type of XLEN : constant is 1;
end Sqrt;
