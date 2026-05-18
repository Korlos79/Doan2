library verilog;
use verilog.vl_types.all;
entity PC is
    port(
        clk             : in     vl_logic;
        rst_n           : in     vl_logic;
        en              : in     vl_logic;
        predict_taken   : in     vl_logic;
        predict_target_pc: in     vl_logic_vector(31 downto 0);
        rob_flush       : in     vl_logic;
        rob_flush_pc    : in     vl_logic_vector(31 downto 0);
        addr_out        : out    vl_logic_vector(31 downto 0)
    );
end PC;
