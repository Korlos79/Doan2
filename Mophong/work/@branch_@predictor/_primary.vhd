library verilog;
use verilog.vl_types.all;
entity Branch_Predictor is
    generic(
        INDEX_BITS      : integer := 5;
        TAG_BITS        : integer := 10
    );
    port(
        clk             : in     vl_logic;
        rst_n           : in     vl_logic;
        pc_in           : in     vl_logic_vector(31 downto 0);
        predict_taken   : out    vl_logic;
        predict_target  : out    vl_logic_vector(31 downto 0);
        update_valid    : in     vl_logic;
        update_pc       : in     vl_logic_vector(31 downto 0);
        update_taken    : in     vl_logic;
        update_target   : in     vl_logic_vector(31 downto 0)
    );
    attribute mti_svvh_generic_type : integer;
    attribute mti_svvh_generic_type of INDEX_BITS : constant is 1;
    attribute mti_svvh_generic_type of TAG_BITS : constant is 1;
end Branch_Predictor;
