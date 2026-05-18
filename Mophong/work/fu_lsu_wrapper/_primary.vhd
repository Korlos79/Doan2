library verilog;
use verilog.vl_types.all;
entity fu_lsu_wrapper is
    generic(
        DATA_WIDTH      : integer := 32;
        TAG_WIDTH       : integer := 4
    );
    port(
        clk             : in     vl_logic;
        rst_n           : in     vl_logic;
        start           : in     vl_logic;
        opcode          : in     vl_logic_vector(4 downto 0);
        op1             : in     vl_logic_vector(31 downto 0);
        op2             : in     vl_logic_vector(31 downto 0);
        imm             : in     vl_logic_vector(31 downto 0);
        tag_in          : in     vl_logic_vector;
        fu_ready        : out    vl_logic;
        cdb_valid       : out    vl_logic;
        cdb_result      : out    vl_logic_vector;
        cdb_tag         : out    vl_logic_vector;
        cdb_ack         : in     vl_logic;
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
    attribute mti_svvh_generic_type : integer;
    attribute mti_svvh_generic_type of DATA_WIDTH : constant is 1;
    attribute mti_svvh_generic_type of TAG_WIDTH : constant is 1;
end fu_lsu_wrapper;
