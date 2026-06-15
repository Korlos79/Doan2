library verilog;
use verilog.vl_types.all;
entity Control_Unit is
    port(
        inst            : in     vl_logic_vector(31 downto 0);
        pc              : in     vl_logic_vector(31 downto 0);
        rd              : out    vl_logic_vector(4 downto 0);
        rs1             : out    vl_logic_vector(4 downto 0);
        rs2             : out    vl_logic_vector(4 downto 0);
        rs3             : out    vl_logic_vector(4 downto 0);
        imm             : out    vl_logic_vector(31 downto 0);
        use_rs1         : out    vl_logic;
        use_rs2         : out    vl_logic;
        use_rs3         : out    vl_logic;
        use_rd          : out    vl_logic;
        fp_rs1          : out    vl_logic;
        fp_rs2          : out    vl_logic;
        fp_rs3          : out    vl_logic;
        fp_rd           : out    vl_logic;
        to_alu          : out    vl_logic;
        to_fpu          : out    vl_logic;
        to_lsu          : out    vl_logic;
        alu_op          : out    vl_logic_vector(4 downto 0);
        fpu_op          : out    vl_logic_vector(4 downto 0);
        lsu_op          : out    vl_logic_vector(2 downto 0);
        is_branch       : out    vl_logic;
        is_jal          : out    vl_logic;
        is_jalr         : out    vl_logic;
        is_lui          : out    vl_logic;
        is_auipc        : out    vl_logic;
        is_load         : out    vl_logic;
        is_store        : out    vl_logic;
        is_fp_load      : out    vl_logic;
        is_fp_store     : out    vl_logic;
        branch_op       : out    vl_logic_vector(2 downto 0);
        valid           : out    vl_logic
    );
end Control_Unit;
