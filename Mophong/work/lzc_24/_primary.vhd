library verilog;
use verilog.vl_types.all;
entity lzc_24 is
    port(
        \in\            : in     vl_logic_vector(23 downto 0);
        \out\           : out    vl_logic_vector(4 downto 0)
    );
end lzc_24;
