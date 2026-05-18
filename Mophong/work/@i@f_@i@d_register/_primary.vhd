library verilog;
use verilog.vl_types.all;
entity IF_ID_register is
    port(
        clk             : in     vl_logic;
        rst_n           : in     vl_logic;
        stall           : in     vl_logic;
        flush           : in     vl_logic;
        issue_fire      : in     vl_logic;
        instF           : in     vl_logic_vector(31 downto 0);
        PCF             : in     vl_logic_vector(31 downto 0);
        validF          : in     vl_logic;
        instD           : out    vl_logic_vector(31 downto 0);
        PCD             : out    vl_logic_vector(31 downto 0);
        validD          : out    vl_logic
    );
end IF_ID_register;
