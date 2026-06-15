library verilog;
use verilog.vl_types.all;
entity fu_alu_wrapper is
    generic(
        TAG_WIDTH       : integer := 7;
        ROB_IDX         : integer := 5
    );
    port(
        clk             : in     vl_logic;
        rst_n           : in     vl_logic;
        flush           : in     vl_logic;
        issue_valid     : in     vl_logic;
        issue_prd       : in     vl_logic_vector;
        issue_rs1_val   : in     vl_logic_vector(31 downto 0);
        issue_rs2_val   : in     vl_logic_vector(31 downto 0);
        issue_imm       : in     vl_logic_vector(31 downto 0);
        issue_pc        : in     vl_logic_vector(31 downto 0);
        issue_alu_op    : in     vl_logic_vector(4 downto 0);
        issue_rob_idx   : in     vl_logic_vector;
        issue_use_imm   : in     vl_logic;
        issue_is_branch : in     vl_logic;
        issue_is_jal    : in     vl_logic;
        issue_is_jalr   : in     vl_logic;
        issue_is_lui    : in     vl_logic;
        issue_is_auipc  : in     vl_logic;
        issue_branch_op : in     vl_logic_vector(2 downto 0);
        wb0_valid       : out    vl_logic;
        wb0_rob_idx     : out    vl_logic_vector;
        wb0_result      : out    vl_logic_vector(31 downto 0);
        wb0_exc         : out    vl_logic;
        wb0_prd         : out    vl_logic_vector;
        wb0_pc          : out    vl_logic_vector(31 downto 0);
        wb0_is_branch   : out    vl_logic;
        wb1_valid       : out    vl_logic;
        wb1_rob_idx     : out    vl_logic_vector;
        wb1_result      : out    vl_logic_vector(31 downto 0);
        wb1_exc         : out    vl_logic;
        wb1_prd         : out    vl_logic_vector
    );
    attribute mti_svvh_generic_type : integer;
    attribute mti_svvh_generic_type of TAG_WIDTH : constant is 1;
    attribute mti_svvh_generic_type of ROB_IDX : constant is 1;
end fu_alu_wrapper;
