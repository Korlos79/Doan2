library verilog;
use verilog.vl_types.all;
entity wallace_tree_12_rows is
    port(
        pp0             : in     vl_logic_vector(71 downto 0);
        pp1             : in     vl_logic_vector(71 downto 0);
        pp2             : in     vl_logic_vector(71 downto 0);
        pp3             : in     vl_logic_vector(71 downto 0);
        pp4             : in     vl_logic_vector(71 downto 0);
        pp5             : in     vl_logic_vector(71 downto 0);
        pp6             : in     vl_logic_vector(71 downto 0);
        pp7             : in     vl_logic_vector(71 downto 0);
        pp8             : in     vl_logic_vector(71 downto 0);
        pp9             : in     vl_logic_vector(71 downto 0);
        pp10            : in     vl_logic_vector(71 downto 0);
        pp11            : in     vl_logic_vector(71 downto 0);
        pp12            : in     vl_logic_vector(71 downto 0);
        sum             : out    vl_logic_vector(71 downto 0);
        carry           : out    vl_logic_vector(71 downto 0)
    );
end wallace_tree_12_rows;
