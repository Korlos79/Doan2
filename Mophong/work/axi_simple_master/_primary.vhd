library verilog;
use verilog.vl_types.all;
entity axi_simple_master is
    port(
        clk             : in     vl_logic;
        rst_n           : in     vl_logic;
        start           : in     vl_logic;
        rw              : in     vl_logic;
        addr            : in     vl_logic_vector(31 downto 0);
        wdata           : in     vl_logic_vector(31 downto 0);
        wstrb           : in     vl_logic_vector(3 downto 0);
        done            : out    vl_logic;
        rdata           : out    vl_logic_vector(31 downto 0);
        busy            : out    vl_logic;
        m_axi_awaddr    : out    vl_logic_vector(31 downto 0);
        m_axi_awvalid   : out    vl_logic;
        m_axi_awready   : in     vl_logic;
        m_axi_wdata     : out    vl_logic_vector(31 downto 0);
        m_axi_wstrb     : out    vl_logic_vector(3 downto 0);
        m_axi_wvalid    : out    vl_logic;
        m_axi_wready    : in     vl_logic;
        m_axi_bvalid    : in     vl_logic;
        m_axi_bready    : out    vl_logic;
        m_axi_araddr    : out    vl_logic_vector(31 downto 0);
        m_axi_arvalid   : out    vl_logic;
        m_axi_arready   : in     vl_logic;
        m_axi_rdata     : in     vl_logic_vector(31 downto 0);
        m_axi_rvalid    : in     vl_logic;
        m_axi_rready    : out    vl_logic
    );
end axi_simple_master;
