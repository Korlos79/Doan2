library verilog;
use verilog.vl_types.all;
entity instruction_Mem is
    port(
        addr            : in     vl_logic_vector(31 downto 0);
        inst            : out    vl_logic_vector(31 downto 0)
    );
end instruction_Mem;
