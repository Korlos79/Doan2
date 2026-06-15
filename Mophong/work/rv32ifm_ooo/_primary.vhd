library verilog;
use verilog.vl_types.all;
entity rv32ifm_ooo is
    generic(
        TAG_WIDTH       : integer := 7;
        ROB_IDX         : integer := 5;
        ROB_DEPTH       : integer := 32;
        NUM_PHYS        : integer := 64;
        NUM_ARCH        : integer := 32;
        FP_NUM_PHYS     : integer := 64;
        FP_NUM_ARCH     : integer := 32
    );
    port(
        clk             : in     vl_logic;
        rst_n           : in     vl_logic
    );
    attribute mti_svvh_generic_type : integer;
    attribute mti_svvh_generic_type of TAG_WIDTH : constant is 1;
    attribute mti_svvh_generic_type of ROB_IDX : constant is 1;
    attribute mti_svvh_generic_type of ROB_DEPTH : constant is 1;
    attribute mti_svvh_generic_type of NUM_PHYS : constant is 1;
    attribute mti_svvh_generic_type of NUM_ARCH : constant is 1;
    attribute mti_svvh_generic_type of FP_NUM_PHYS : constant is 1;
    attribute mti_svvh_generic_type of FP_NUM_ARCH : constant is 1;
end rv32ifm_ooo;
