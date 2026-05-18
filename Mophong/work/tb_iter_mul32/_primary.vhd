library verilog;
use verilog.vl_types.all;
entity tb_iter_mul32 is
    generic(
        TAG_WIDTH       : integer := 4
    );
    attribute mti_svvh_generic_type : integer;
    attribute mti_svvh_generic_type of TAG_WIDTH : constant is 1;
end tb_iter_mul32;
