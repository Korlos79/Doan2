library verilog;
use verilog.vl_types.all;
entity dmem is
    port(
        clk             : in     vl_logic;
        we              : in     vl_logic;
        re              : in     vl_logic;
        mode            : in     vl_logic_vector(2 downto 0);
        addr            : in     vl_logic_vector(9 downto 0);
        write_data      : in     vl_logic_vector(31 downto 0);
        mem_out         : out    vl_logic_vector(31 downto 0)
    );
end dmem;
