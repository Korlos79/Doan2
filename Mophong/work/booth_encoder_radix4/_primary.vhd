library verilog;
use verilog.vl_types.all;
entity booth_encoder_radix4 is
    port(
        multiplier_bit  : in     vl_logic_vector(23 downto 0);
        code_bits       : in     vl_logic_vector(2 downto 0);
        p_out           : out    vl_logic_vector(47 downto 0)
    );
end booth_encoder_radix4;
