library verilog;
use verilog.vl_types.all;
entity fu_lsu_wrapper is
    port(
        clk             : in     vl_logic;
        re              : in     vl_logic;
        load_mode       : in     vl_logic_vector(2 downto 0);
        load_addr       : in     vl_logic_vector(9 downto 0);
        load_data       : out    vl_logic_vector(31 downto 0);
        we              : in     vl_logic;
        store_mode      : in     vl_logic_vector(2 downto 0);
        store_addr      : in     vl_logic_vector(9 downto 0);
        store_data      : in     vl_logic_vector(31 downto 0)
    );
end fu_lsu_wrapper;
