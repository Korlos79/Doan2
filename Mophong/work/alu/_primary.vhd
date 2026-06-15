library verilog;
use verilog.vl_types.all;
entity alu is
    generic(
        TAG_WIDTH       : integer := 4
    );
    port(
        clk             : in     vl_logic;
        rst_n           : in     vl_logic;
        A               : in     vl_logic_vector(31 downto 0);
        B               : in     vl_logic_vector(31 downto 0);
        opcode          : in     vl_logic_vector(4 downto 0);
        branch          : in     vl_logic_vector(2 downto 0);
        tag_in          : in     vl_logic_vector;
        basic_result    : out    vl_logic_vector(31 downto 0);
        Z               : out    vl_logic;
        mul_result      : out    vl_logic_vector(31 downto 0);
        mul_done        : out    vl_logic;
        mul_tag_out     : out    vl_logic_vector;
        div_result      : out    vl_logic_vector(31 downto 0);
        div_done        : out    vl_logic;
        div_tag_out     : out    vl_logic_vector
    );
    attribute mti_svvh_generic_type : integer;
    attribute mti_svvh_generic_type of TAG_WIDTH : constant is 1;
end alu;
