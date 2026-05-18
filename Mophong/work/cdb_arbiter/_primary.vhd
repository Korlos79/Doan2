library verilog;
use verilog.vl_types.all;
entity cdb_arbiter is
    generic(
        DATA_WIDTH      : integer := 32;
        TAG_WIDTH       : integer := 4
    );
    port(
        alu_valid       : in     vl_logic;
        alu_result      : in     vl_logic_vector;
        alu_tag         : in     vl_logic_vector;
        alu_branch_taken: in     vl_logic;
        alu_branch_target: in     vl_logic_vector(31 downto 0);
        alu_ack         : out    vl_logic;
        fpu_valid       : in     vl_logic;
        fpu_result      : in     vl_logic_vector;
        fpu_tag         : in     vl_logic_vector;
        fpu_ack         : out    vl_logic;
        lsu_valid       : in     vl_logic;
        lsu_result      : in     vl_logic_vector;
        lsu_tag         : in     vl_logic_vector;
        lsu_ack         : out    vl_logic;
        cdb_valid_out   : out    vl_logic;
        cdb_result_out  : out    vl_logic_vector;
        cdb_tag_out     : out    vl_logic_vector;
        cdb_branch_taken_out: out    vl_logic;
        cdb_branch_target_out: out    vl_logic_vector(31 downto 0)
    );
    attribute mti_svvh_generic_type : integer;
    attribute mti_svvh_generic_type of DATA_WIDTH : constant is 1;
    attribute mti_svvh_generic_type of TAG_WIDTH : constant is 1;
end cdb_arbiter;
