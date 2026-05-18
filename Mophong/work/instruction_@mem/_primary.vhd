library verilog;
use verilog.vl_types.all;
entity instruction_Mem is
    port(
        clk             : in     vl_logic;
        rst_n           : in     vl_logic;
        addr            : in     vl_logic_vector(31 downto 0);
        inst            : out    vl_logic_vector(31 downto 0);
        stall_out       : out    vl_logic;
        validF          : out    vl_logic;
        m_axi_araddr    : out    vl_logic_vector(31 downto 0);
        m_axi_arvalid   : out    vl_logic;
        m_axi_arready   : in     vl_logic;
        m_axi_rdata     : in     vl_logic_vector(31 downto 0);
        m_axi_rvalid    : in     vl_logic;
        m_axi_rready    : out    vl_logic
    );
end instruction_Mem;
