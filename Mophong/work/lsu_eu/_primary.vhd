library verilog;
use verilog.vl_types.all;
entity lsu_eu is
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
        issue_imm       : in     vl_logic_vector(31 downto 0);
        issue_lsu_op    : in     vl_logic_vector(2 downto 0);
        issue_rob_idx   : in     vl_logic_vector;
        issue_is_load   : in     vl_logic;
        issue_is_store  : in     vl_logic;
        issue_is_fp_load: in     vl_logic;
        issue_is_fp_store: in     vl_logic;
        wb3_valid       : out    vl_logic;
        wb3_rob_idx     : out    vl_logic_vector;
        wb3_result      : out    vl_logic_vector(31 downto 0);
        wb3_exc         : out    vl_logic;
        wb3_prd         : out    vl_logic_vector;
        wbs_valid       : out    vl_logic;
        wbs_rob_idx     : out    vl_logic_vector;
        wbs_store_addr  : out    vl_logic_vector(31 downto 0);
        wbs_store_data  : out    vl_logic_vector(31 downto 0);
        wbs_store_mode  : out    vl_logic_vector(2 downto 0);
        dmem_re         : out    vl_logic;
        dmem_load_mode  : out    vl_logic_vector(2 downto 0);
        dmem_addr       : out    vl_logic_vector(9 downto 0);
        dmem_rdata      : in     vl_logic_vector(31 downto 0)
    );
    attribute mti_svvh_generic_type : integer;
    attribute mti_svvh_generic_type of TAG_WIDTH : constant is 1;
    attribute mti_svvh_generic_type of ROB_IDX : constant is 1;
end lsu_eu;
