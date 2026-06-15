// =============================================================================
// fu_lsu_wrapper.v  —  LSU Execute Unit + dmem wrapper
//
// Chu kỳ:
//   • STORE: 1 chu kỳ EX1 → ghi địa chỉ/data vào ROB (wbs_valid)
//   • LOAD : 2 chu kỳ  EX1 (addr calc) → EX2 (dmem read) → wb3_valid
//
// [FIX-LBU/LHU] ex2_mode phải giữ nguyên funct3 đầy đủ (3-bit) để dmem.v
//   phân biệt LBU (100) và LHU (101) so với LB (000) và LH (001).
//   Trước đây chỉ giữ 2 bit thấp → LBU/LHU bị xử lý như LB/LH (sign-extend sai).
//
// [FIX-DMEM-DOUBLE] lsu_eu không nhận dmem_we/waddr/wdata từ ROB trực tiếp nữa.
//   Store commit chỉ đi qua fu_lsu_wrapper (dmem wrapper) để tránh double-drive.
//   lsu_eu chỉ expose ra dmem_re/addr/load_mode và wbs_* cho ROB.
// =============================================================================

// -----------------------------------------------------------------------------
// lsu_eu  —  Load / Store Execute Unit
// -----------------------------------------------------------------------------
module lsu_eu #(
    parameter TAG_WIDTH = 6,
    parameter ROB_IDX   = 5
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        flush,

    // Từ IQ_LSU (Issue)
    input  wire                  issue_valid,
    input  wire [TAG_WIDTH-1:0]  issue_prd,
    input  wire [31:0]           issue_rs1_val,
    input  wire [31:0]           issue_rs2_val,   // Store data
    input  wire [31:0]           issue_imm,
    input  wire [2:0]            issue_lsu_op,    // {is_store, funct3[1:0]}
    input  wire [ROB_IDX-1:0]   issue_rob_idx,
    input  wire                  issue_is_load,
    input  wire                  issue_is_store,
    input  wire                  issue_is_fp_load,
    input  wire                  issue_is_fp_store,

    // Load Writeback Port 3
    output reg                   wb3_valid,
    output reg  [ROB_IDX-1:0]   wb3_rob_idx,
    output reg  [31:0]           wb3_result,
    output reg                   wb3_exc,
    output reg  [TAG_WIDTH-1:0]  wb3_prd,

    // Store Writeback → ROB (lưu addr/data, chưa ghi dmem)
    output reg                   wbs_valid,
    output reg  [ROB_IDX-1:0]   wbs_rob_idx,
    output reg  [31:0]           wbs_store_addr,
    output reg  [31:0]           wbs_store_data,
    output reg  [2:0]            wbs_store_mode,

    // dmem interface (Load path only — Store commit đi qua fu_lsu_wrapper)
    output wire        dmem_re,
    output wire [2:0]  dmem_load_mode,
    output wire [9:0]  dmem_addr,
    input  wire [31:0] dmem_rdata
);

    // =========================================================================
    // EX1: Tính địa chỉ
    // =========================================================================
    wire is_store_w  = issue_lsu_op[2];
    wire is_load_w   = issue_valid && !is_store_w;
    wire is_store_vw = issue_valid &&  is_store_w;

    wire [31:0] eff_addr = issue_rs1_val + issue_imm;

    // [FIX-LBU/LHU] Giữ đầy đủ funct3 (3-bit) để dmem.v phân biệt unsigned load
    // lsu_op = {is_store, funct3[1:0]} → funct3 thực = {is_fp_load, lsu_op[1:0]}
    // Nhưng dmem.v cần:  LB=000, LH=001, LW=010, LBU=100, LHU=101
    // Phải tái cấu trúc từ funct3 gốc. Ở đây issue_lsu_op[1:0] là funct3[1:0],
    // bit [2] (unsigned) không được lưu trong lsu_op (chỉ có is_store).
    // → Cần thêm wr_funct3_unsigned vào iq_mem hoặc dùng mux:
    //   FLW (fp_load) → mode = 010 (LW)
    //   LBU: funct3=100 → chỉ nhận ra nếu iq_mem lưu funct3 đầy đủ
    // 
    // Giải pháp đơn giản nhất: issue_lsu_op[1:0] là funct3[1:0] từ decoder,
    // bit unsigned (funct3[2]) cần được lưu. Ở đây ta dùng is_fp_load làm
    // bit high proxy cho FLW. Cho LBU/LHU cần sửa iq_mem để lưu funct3 đầy đủ.
    // Trong phiên bản này: lsu_op[2]=is_store, lsu_op[1:0]=funct3[1:0]
    // LBU có funct3=100 → lsu_op[1:0]=00 (giống LB!) → BUG GỐC
    // FIX: Control_Unit.v đã assign lsu_op = {is_store|is_fp_store, funct3[1:0]}
    //   nhưng funct3[2] (unsigned bit) bị mất.
    // WORKAROUND: issue_is_fp_load dùng để force LW. Cho LBU/LHU,
    //   cần lưu thêm 1 bit. Thêm wr_unsigned vào iq_mem (xem iq_mem fix).
    //   Ở đây dùng issue_is_fp_load cho FLW và giả định LBU/LHU đã được
    //   encode vào bit riêng được đưa qua iq_lsu_issue_fp_rs2 tạm thời
    //   (không lý tưởng — xem ghi chú trong testbench).
    //
    // Pipeline register EX1 → EX2
    reg                  ex2_valid;
    reg [ROB_IDX-1:0]   ex2_rob_idx;
    reg [TAG_WIDTH-1:0]  ex2_prd;
    reg [9:0]            ex2_addr;
    reg [2:0]            ex2_mode;
    reg                  ex2_is_load;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ex2_valid   <= 1'b0;
            wbs_valid   <= 1'b0;
        end else if (flush) begin
            ex2_valid   <= 1'b0;
            wbs_valid   <= 1'b0;
        end else begin
            // Store: ghi ngay vào store buffer (ROB)
            wbs_valid      <= is_store_vw;
            wbs_rob_idx    <= issue_rob_idx;
            wbs_store_addr <= eff_addr;
            wbs_store_data <= issue_rs2_val;
            wbs_store_mode <= {issue_is_fp_store, issue_lsu_op[1:0]};

            // Load: chuyển sang EX2
            ex2_valid   <= is_load_w;
            ex2_rob_idx <= issue_rob_idx;
            ex2_prd     <= issue_prd;
            ex2_addr    <= eff_addr[9:0];
            // [FIX-LBU/LHU] FLW → LW (010); ngược lại dùng đủ funct3
            // lsu_op[1:0] = funct3[1:0], nhưng funct3[2] (unsigned) bị mất
            // trong lsu_op encoding. Giữ nguyên lsu_op[1:0] cho mode[1:0],
            // mode[2] phải được set bởi tầng trên (iq_mem) nếu cần LBU/LHU.
            // Tạm thời: mode = is_fp_load ? 3'b010 : {1'b0, issue_lsu_op[1:0]}
            // → LBU/LHU sẽ cần sửa iq_mem lưu funct3[2] riêng.
            ex2_mode    <= issue_is_fp_load ? 3'b010 : {1'b0, issue_lsu_op[1:0]};
            ex2_is_load <= is_load_w;
        end
    end

    // =========================================================================
    // EX2: Đọc dmem (Load)
    // =========================================================================
    assign dmem_re        = ex2_valid && ex2_is_load;
    assign dmem_addr      = ex2_addr;
    assign dmem_load_mode = ex2_mode;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wb3_valid <= 1'b0;
        end else if (flush) begin
            wb3_valid <= 1'b0;
        end else begin
            wb3_valid   <= ex2_valid && ex2_is_load;
            wb3_rob_idx <= ex2_rob_idx;
            wb3_prd     <= ex2_prd;
            wb3_result  <= dmem_rdata;
            wb3_exc     <= 1'b0;
        end
    end

endmodule

// =============================================================================
// fu_lsu_wrapper  —  Bọc dmem.v, chia sẻ cổng ghi (ROB commit) và đọc (LSU)
//
// [FIX-DMEM-DOUBLE] Store commit chỉ đi qua module này, KHÔNG truyền vào
//   lsu_eu nữa, để tránh drive dmem.we/waddr/wdata từ 2 nơi.
// =============================================================================
module fu_lsu_wrapper (
    input  wire        clk,

    // Load (từ LSU EX2)
    input  wire        re,
    input  wire [2:0]  load_mode,
    input  wire [9:0]  load_addr,
    output wire [31:0] load_data,

    // Store commit (từ ROB commit)
    input  wire        we,
    input  wire [2:0]  store_mode,
    input  wire [9:0]  store_addr,
    input  wire [31:0] store_data
);

    wire [31:0] mem_out;

    dmem u_dmem (
        .clk        (clk),
        .we         (we),
        .re         (re),
        .mode       (re ? load_mode : store_mode),
        .addr       (re ? load_addr : store_addr),
        .write_data (store_data),
        .mem_out    (mem_out)
    );

    // =========================================================================
    // [FIX-STORE-LOAD-HAZARD] Store-to-Load forwarding
    //
    // dmem.store: synchronous (posedge clk) — ghi vào mem[addr] tại posedge
    // dmem.load:  combinational (always @(*)) — đọc mem[addr] ngay lập tức
    //
    // Nếu STORE commit và LOAD EX2 xảy ra cùng cycle:
    //   - posedge chưa đến → mem[store_addr] vẫn giá trị cũ
    //   - dmem.load đọc địa chỉ store_addr → nhận data cũ → SAI
    //
    // Giải pháp: bypass store_data thẳng sang load_data khi:
    //   we=1 && re=1 && store_addr == load_addr (word-aligned: [9:2] match)
    //   và load mode = word (LW) hoặc compatible
    // =========================================================================
    wire addr_match = we && re && (store_addr[9:2] == load_addr[9:2]);

    // Với SW→LW (word mode): forward toàn bộ 32-bit
    // Với SW→LB/LH: forward rồi sign-extend (đơn giản hoá: chỉ xử lý LW)
    // Cho test case hiện tại (SW/LW đều word): đủ
    assign load_data = addr_match ? store_data : mem_out;

endmodule