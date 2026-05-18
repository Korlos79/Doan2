library verilog;
use verilog.vl_types.all;
entity rs_alu is
    generic(
        DATA_WIDTH      : integer := 32;
        TAG_WIDTH       : integer := 4;
        NUM_ENTRIES     : integer := 4
    );
    port(
        clk             : in     vl_logic;
        rst_n           : in     vl_logic;
        flush           : in     vl_logic;
        dispatch_enable : in     vl_logic;
        opcode          : in     vl_logic_vector(4 downto 0);
        my_rob_tag      : in     vl_logic_vector;
        src1_val        : in     vl_logic_vector;
        src2_val        : in     vl_logic_vector;
        src3_val        : in     vl_logic_vector;
        src1_tag        : in     vl_logic_vector;
        src2_tag        : in     vl_logic_vector;
        src3_tag        : in     vl_logic_vector;
        src1_ready      : in     vl_logic;
        src2_ready      : in     vl_logic;
        src3_ready      : in     vl_logic;
        disp_pc         : in     vl_logic_vector(31 downto 0);
        disp_imm        : in     vl_logic_vector(31 downto 0);
        disp_muxjalr    : in     vl_logic;
        disp_jump       : in     vl_logic;
        disp_branch     : in     vl_logic;
        rs_full         : out    vl_logic;
        cdb_valid       : in     vl_logic;
        cdb_tag         : in     vl_logic_vector;
        cdb_value       : in     vl_logic_vector;
        fu_busy_basic   : in     vl_logic;
        fu_busy_md      : in     vl_logic;
        fu_start        : out    vl_logic;
        fu_op1          : out    vl_logic_vector;
        fu_op2          : out    vl_logic_vector;
        fu_op3          : out    vl_logic_vector;
        fu_opcode       : out    vl_logic_vector(4 downto 0);
        fu_dest_tag     : out    vl_logic_vector;
        fu_pc           : out    vl_logic_vector(31 downto 0);
        fu_imm          : out    vl_logic_vector(31 downto 0);
        fu_muxjalr      : out    vl_logic;
        fu_jump         : out    vl_logic;
        fu_branch       : out    vl_logic
    );
    attribute mti_svvh_generic_type : integer;
    attribute mti_svvh_generic_type of DATA_WIDTH : constant is 1;
    attribute mti_svvh_generic_type of TAG_WIDTH : constant is 1;
    attribute mti_svvh_generic_type of NUM_ENTRIES : constant is 1;
end rs_alu;
