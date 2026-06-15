library verilog;
use verilog.vl_types.all;
entity compressor_3_2_72bit is
    port(
        in0             : in     vl_logic_vector(71 downto 0);
        in1             : in     vl_logic_vector(71 downto 0);
        in2             : in     vl_logic_vector(71 downto 0);
        sum             : out    vl_logic_vector(71 downto 0);
        carry           : out    vl_logic_vector(71 downto 0)
    );
end compressor_3_2_72bit;
