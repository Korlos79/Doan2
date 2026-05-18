library verilog;
use verilog.vl_types.all;
entity ConvfromUnsInt is
    port(
        int_in          : in     vl_logic_vector(31 downto 0);
        float_out       : out    vl_logic_vector(31 downto 0)
    );
end ConvfromUnsInt;
