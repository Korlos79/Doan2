library verilog;
use verilog.vl_types.all;
entity free_list is
    generic(
        NUM_PHYS        : integer := 64;
        NUM_ARCH        : integer := 32;
        TAG_WIDTH       : integer := 6;
        BASE_TAG        : integer := 0
    );
    port(
        clk             : in     vl_logic;
        rst_n           : in     vl_logic;
        flush           : in     vl_logic;
        snapshot_en     : in     vl_logic;
        alloc_valid     : in     vl_logic;
        alloc_tag       : out    vl_logic_vector;
        alloc_ok        : out    vl_logic;
        free_valid      : in     vl_logic;
        free_tag        : in     vl_logic_vector;
        full            : out    vl_logic;
        empty           : out    vl_logic
    );
    attribute mti_svvh_generic_type : integer;
    attribute mti_svvh_generic_type of NUM_PHYS : constant is 1;
    attribute mti_svvh_generic_type of NUM_ARCH : constant is 1;
    attribute mti_svvh_generic_type of TAG_WIDTH : constant is 1;
    attribute mti_svvh_generic_type of BASE_TAG : constant is 1;
end free_list;
