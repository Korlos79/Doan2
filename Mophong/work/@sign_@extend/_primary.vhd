library verilog;
use verilog.vl_types.all;
entity Sign_Extend is
    port(
        inst            : in     vl_logic_vector(24 downto 0);
        control         : in     vl_logic_vector(2 downto 0);
        imm             : out    vl_logic_vector(31 downto 0)
    );
end Sign_Extend;
