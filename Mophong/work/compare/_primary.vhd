library verilog;
use verilog.vl_types.all;
entity compare is
    port(
        a_operand       : in     vl_logic_vector(31 downto 0);
        b_operand       : in     vl_logic_vector(31 downto 0);
        mode            : in     vl_logic_vector(1 downto 0);
        result          : out    vl_logic
    );
end compare;
