library verilog;
use verilog.vl_types.all;
entity tb_ooo_proof is
    generic(
        TAG_WIDTH       : integer := 7;
        ROB_IDX         : integer := 5;
        ROB_DEPTH       : integer := 32;
        NUM_PHYS        : integer := 64;
        NUM_ARCH        : integer := 32;
        INST_COUNT      : integer := 8;
        CLK_HALF        : integer := 5;
        MAX_CYCLES      : integer := 120
    );
    attribute mti_svvh_generic_type : integer;
    attribute mti_svvh_generic_type of TAG_WIDTH : constant is 1;
    attribute mti_svvh_generic_type of ROB_IDX : constant is 1;
    attribute mti_svvh_generic_type of ROB_DEPTH : constant is 1;
    attribute mti_svvh_generic_type of NUM_PHYS : constant is 1;
    attribute mti_svvh_generic_type of NUM_ARCH : constant is 1;
    attribute mti_svvh_generic_type of INST_COUNT : constant is 1;
    attribute mti_svvh_generic_type of CLK_HALF : constant is 1;
    attribute mti_svvh_generic_type of MAX_CYCLES : constant is 1;
end tb_ooo_proof;
