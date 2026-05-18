library verilog;
use verilog.vl_types.all;
entity iter_mul32 is
    generic(
        TAG_WIDTH       : integer := 4
    );
    port(
        clk             : in     vl_logic;
        rst_n           : in     vl_logic;
        start           : in     vl_logic;
        op_sel          : in     vl_logic_vector(4 downto 0);
        tag_in          : in     vl_logic_vector;
        rs1             : in     vl_logic_vector(31 downto 0);
        rs2             : in     vl_logic_vector(31 downto 0);
        done            : out    vl_logic;
        tag_out         : out    vl_logic_vector;
        result          : out    vl_logic_vector(31 downto 0)
    );
    attribute mti_svvh_generic_type : integer;
    attribute mti_svvh_generic_type of TAG_WIDTH : constant is 1;
end iter_mul32;
