library verilog;
use verilog.vl_types.all;
entity ROB is
    generic(
        ROB_ENTRIES     : integer := 16;
        TAG_WIDTH       : integer := 4
    );
    port(
        clk             : in     vl_logic;
        rst_n           : in     vl_logic;
        issue_valid     : in     vl_logic;
        issue_rd        : in     vl_logic_vector(4 downto 0);
        issue_reg_write : in     vl_logic;
        issue_is_fp     : in     vl_logic;
        issue_is_branch : in     vl_logic;
        rob_full        : out    vl_logic;
        allocate_tag    : out    vl_logic_vector;
        cdb_valid       : in     vl_logic;
        cdb_tag         : in     vl_logic_vector;
        cdb_result      : in     vl_logic_vector(31 downto 0);
        cdb_branch_taken: in     vl_logic;
        cdb_branch_target: in     vl_logic_vector(31 downto 0);
        commit_valid    : out    vl_logic;
        commit_rd       : out    vl_logic_vector(4 downto 0);
        commit_result   : out    vl_logic_vector(31 downto 0);
        commit_tag      : out    vl_logic_vector;
        commit_int_we   : out    vl_logic;
        commit_float_we : out    vl_logic;
        rob_flush       : out    vl_logic;
        rob_flush_pc    : out    vl_logic_vector(31 downto 0)
    );
    attribute mti_svvh_generic_type : integer;
    attribute mti_svvh_generic_type of ROB_ENTRIES : constant is 1;
    attribute mti_svvh_generic_type of TAG_WIDTH : constant is 1;
end ROB;
