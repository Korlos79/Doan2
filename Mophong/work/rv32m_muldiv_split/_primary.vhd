library verilog;
use verilog.vl_types.all;
entity rv32m_muldiv_split is
    port(
        clk             : in     vl_logic;
        rst_n           : in     vl_logic;
        op_valid        : in     vl_logic;
        op_sel          : in     vl_logic_vector(4 downto 0);
        rs1             : in     vl_logic_vector(31 downto 0);
        rs2             : in     vl_logic_vector(31 downto 0);
        busy            : out    vl_logic;
        done            : out    vl_logic;
        result          : out    vl_logic_vector(31 downto 0)
    );
end rv32m_muldiv_split;
