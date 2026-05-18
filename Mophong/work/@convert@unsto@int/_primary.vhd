library verilog;
use verilog.vl_types.all;
entity ConvertUnstoInt is
    port(
        float_in        : in     vl_logic_vector(31 downto 0);
        int_out         : out    vl_logic_vector(31 downto 0)
    );
end ConvertUnstoInt;
