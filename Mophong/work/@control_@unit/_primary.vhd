library verilog;
use verilog.vl_types.all;
entity Control_Unit is
    port(
        funct7          : in     vl_logic_vector(6 downto 0);
        opcode          : in     vl_logic_vector(6 downto 0);
        funct3          : in     vl_logic_vector(2 downto 0);
        rs2             : in     vl_logic_vector(4 downto 0);
        IsALU           : out    vl_logic;
        IsFPU           : out    vl_logic;
        IsLSU           : out    vl_logic;
        JumpD           : out    vl_logic;
        BranchD         : out    vl_logic;
        MuxjalrD        : out    vl_logic;
        ALUSrcA_D       : out    vl_logic_vector(1 downto 0);
        ALUSrcB_D       : out    vl_logic_vector(1 downto 0);
        RegWriteEn      : out    vl_logic;
        IsFloatDest     : out    vl_logic;
        OpD             : out    vl_logic_vector(4 downto 0);
        ImmControlD     : out    vl_logic_vector(2 downto 0);
        src1_is_float   : out    vl_logic;
        src2_is_float   : out    vl_logic;
        src3_is_float   : out    vl_logic;
        instruction_is_legal: out    vl_logic
    );
end Control_Unit;
