library verilog;
use verilog.vl_types.all;
entity fu_fpu_wrapper is
    generic(
        TAG_WIDTH       : integer := 6;
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
        issue_rs3_val   : in     vl_logic_vector(31 downto 0);
        issue_fpu_op    : in     vl_logic_vector(4 downto 0);
        issue_rob_idx   : in     vl_logic_vector;
        wb2_valid       : out    vl_logic;
        wb2_rob_idx     : out    vl_logic_vector;
        wb2_result      : out    vl_logic_vector(31 downto 0);
        wb2_exc         : out    vl_logic;
        wb2_prd         : out    vl_logic_vector
    );
    attribute mti_svvh_generic_type : integer;
    attribute mti_svvh_generic_type of TAG_WIDTH : constant is 1;
    attribute mti_svvh_generic_type of ROB_IDX : constant is 1;
end fu_fpu_wrapper;
