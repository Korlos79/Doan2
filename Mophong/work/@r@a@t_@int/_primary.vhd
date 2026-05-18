library verilog;
use verilog.vl_types.all;
entity RAT_Int is
    generic(
        TAG_WIDTH       : integer := 4
    );
    port(
        clk             : in     vl_logic;
        rst_n           : in     vl_logic;
        flush           : in     vl_logic;
        rs1_addr        : in     vl_logic_vector(4 downto 0);
        rs1_ready       : out    vl_logic;
        rs1_tag         : out    vl_logic_vector;
        rs2_addr        : in     vl_logic_vector(4 downto 0);
        rs2_ready       : out    vl_logic;
        rs2_tag         : out    vl_logic_vector;
        issue_valid     : in     vl_logic;
        issue_rd        : in     vl_logic_vector(4 downto 0);
        issue_rob_tag   : in     vl_logic_vector;
        commit_valid    : in     vl_logic;
        commit_rd       : in     vl_logic_vector(4 downto 0);
        commit_tag      : in     vl_logic_vector
    );
    attribute mti_svvh_generic_type : integer;
    attribute mti_svvh_generic_type of TAG_WIDTH : constant is 1;
end RAT_Int;
