library verilog;
use verilog.vl_types.all;
entity dmem is
    port(
        clk             : in     vl_logic;
        rst_n           : in     vl_logic;
        we              : in     vl_logic;
        re              : in     vl_logic;
        mode            : in     vl_logic_vector(2 downto 0);
        addr            : in     vl_logic_vector(31 downto 0);
        write_data      : in     vl_logic_vector(31 downto 0);
        mem_out         : out    vl_logic_vector(31 downto 0);
        stall_out       : out    vl_logic;
        m_axi_awaddr    : out    vl_logic_vector(31 downto 0);
        m_axi_awvalid   : out    vl_logic_vector(31 downto 0);
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
end dmem;
