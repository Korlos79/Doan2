library verilog;
use verilog.vl_types.all;
entity branch_predictor is
    generic(
        BTB_ENTRIES     : integer := 64;
        BHT_ENTRIES     : integer := 256;
        GHR_WIDTH       : integer := 8
    );
    port(
        clk             : in     vl_logic;
        rst_n           : in     vl_logic;
        fetch_pc        : in     vl_logic_vector(31 downto 0);
        fetch_is_branch : in     vl_logic;
        predict_taken   : out    vl_logic;
        predict_target  : out    vl_logic_vector(31 downto 0);
        dispatch_en     : in     vl_logic;
        dispatch_predict_taken: in     vl_logic;
        update_en       : in     vl_logic;
        update_pc       : in     vl_logic_vector(31 downto 0);
        update_taken    : in     vl_logic;
        update_target   : in     vl_logic_vector(31 downto 0);
        update_is_branch: in     vl_logic;
        flush_en        : in     vl_logic;
        flush_mispred   : in     vl_logic
    );
    attribute mti_svvh_generic_type : integer;
    attribute mti_svvh_generic_type of BTB_ENTRIES : constant is 1;
    attribute mti_svvh_generic_type of BHT_ENTRIES : constant is 1;
    attribute mti_svvh_generic_type of GHR_WIDTH : constant is 1;
end branch_predictor;
