library verilog;
use verilog.vl_types.all;
entity fpu_top is
    port(
        clk             : in     vl_logic;
        rst_n           : in     vl_logic;
        valid_in        : in     vl_logic;
        opcode          : in     vl_logic_vector(2 downto 0);
        a               : in     vl_logic_vector(31 downto 0);
        b               : in     vl_logic_vector(31 downto 0);
        result_out      : out    vl_logic_vector(31 downto 0);
        valid_out       : out    vl_logic;
        rob_full        : out    vl_logic
    );
end fpu_top;
