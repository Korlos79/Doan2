library verilog;
use verilog.vl_types.all;
entity axi4_ram_model is
    generic(
        LATENCY         : integer := 20;
        INIT_FILE       : string  := ""
    );
    port(
        clk             : in     vl_logic;
        rst_n           : in     vl_logic;
        s_axi_araddr    : in     vl_logic_vector(31 downto 0);
        s_axi_arvalid   : in     vl_logic;
        s_axi_arready   : out    vl_logic;
        s_axi_rdata     : out    vl_logic_vector(31 downto 0);
        s_axi_rvalid    : out    vl_logic;
        s_axi_rready    : in     vl_logic;
        s_axi_awaddr    : in     vl_logic_vector(31 downto 0);
        s_axi_awvalid   : in     vl_logic;
        s_axi_awready   : out    vl_logic;
        s_axi_wdata     : in     vl_logic_vector(31 downto 0);
        s_axi_wstrb     : in     vl_logic_vector(3 downto 0);
        s_axi_wvalid    : in     vl_logic;
        s_axi_wready    : out    vl_logic;
        s_axi_bvalid    : out    vl_logic;
        s_axi_bready    : in     vl_logic
    );
    attribute mti_svvh_generic_type : integer;
    attribute mti_svvh_generic_type of LATENCY : constant is 1;
    attribute mti_svvh_generic_type of INIT_FILE : constant is 1;
end axi4_ram_model;
