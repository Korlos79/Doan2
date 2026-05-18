library verilog;
use verilog.vl_types.all;
entity fu_fpu_wrapper is
    generic(
        DATA_WIDTH      : integer := 32;
        TAG_WIDTH       : integer := 4
    );
    port(
        clk             : in     vl_logic;
        rst_n           : in     vl_logic;
        start           : in     vl_logic;
        opcode          : in     vl_logic_vector(4 downto 0);
        op1             : in     vl_logic_vector(31 downto 0);
        op2             : in     vl_logic_vector(31 downto 0);
        op3             : in     vl_logic_vector(31 downto 0);
        tag_in          : in     vl_logic_vector;
        busy            : out    vl_logic;
        cdb_valid       : out    vl_logic;
        cdb_result      : out    vl_logic_vector;
        cdb_tag         : out    vl_logic_vector;
        cdb_ack         : in     vl_logic
    );
    attribute mti_svvh_generic_type : integer;
    attribute mti_svvh_generic_type of DATA_WIDTH : constant is 1;
    attribute mti_svvh_generic_type of TAG_WIDTH : constant is 1;
end fu_fpu_wrapper;
