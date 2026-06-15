library verilog;
use verilog.vl_types.all;
entity prf is
    generic(
        NUM_PHYS        : integer := 64;
        NUM_ARCH        : integer := 32;
        TAG_WIDTH       : integer := 7;
        NUM_RD          : integer := 4
    );
    port(
        clk             : in     vl_logic;
        rst_n           : in     vl_logic;
        rd_tag          : in     vl_logic_vector;
        rd_data         : out    vl_logic_vector;
        rd_ready        : out    vl_logic_vector;
        wb0_en          : in     vl_logic;
        wb0_tag         : in     vl_logic_vector;
        wb0_data        : in     vl_logic_vector(31 downto 0);
        wb1_en          : in     vl_logic;
        wb1_tag         : in     vl_logic_vector;
        wb1_data        : in     vl_logic_vector(31 downto 0);
        wb2_en          : in     vl_logic;
        wb2_tag         : in     vl_logic_vector;
        wb2_data        : in     vl_logic_vector(31 downto 0);
        wb3_en          : in     vl_logic;
        wb3_tag         : in     vl_logic_vector;
        wb3_data        : in     vl_logic_vector(31 downto 0);
        clear_en        : in     vl_logic;
        clear_tag       : in     vl_logic_vector
    );
    attribute mti_svvh_generic_type : integer;
    attribute mti_svvh_generic_type of NUM_PHYS : constant is 1;
    attribute mti_svvh_generic_type of NUM_ARCH : constant is 1;
    attribute mti_svvh_generic_type of TAG_WIDTH : constant is 1;
    attribute mti_svvh_generic_type of NUM_RD : constant is 1;
end prf;
