library verilog;
use verilog.vl_types.all;
entity RAT_Int is
    generic(
        TAG_WIDTH       : integer := 7
    );
    port(
        clk             : in     vl_logic;
        rst_n           : in     vl_logic;
        flush           : in     vl_logic;
        rs1_addr        : in     vl_logic_vector(4 downto 0);
        rs1_tag         : out    vl_logic_vector;
        rs2_addr        : in     vl_logic_vector(4 downto 0);
        rs2_tag         : out    vl_logic_vector;
        rd_addr         : in     vl_logic_vector(4 downto 0);
        rd_current_tag  : out    vl_logic_vector;
        issue_valid     : in     vl_logic;
        issue_rd        : in     vl_logic_vector(4 downto 0);
        issue_new_pr_tag: in     vl_logic_vector;
        commit_valid    : in     vl_logic;
        commit_rd       : in     vl_logic_vector(4 downto 0);
        commit_pr_tag   : in     vl_logic_vector;
        old_pr_tag_to_free: out    vl_logic_vector;
        free_tag_valid  : out    vl_logic
    );
    attribute mti_svvh_generic_type : integer;
    attribute mti_svvh_generic_type of TAG_WIDTH : constant is 1;
end RAT_Int;
