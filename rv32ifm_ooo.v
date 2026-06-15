// =============================================================================
// rv32ifm_ooo.v  —  RV32IFM Out-of-Order Processor  (Top-Level)
// Verilog-2001 compatible
//
// [FIX-DMEM-DOUBLE] lsu_eu không còn nhận dmem_we/waddr/wdata trực tiếp.
//   Store commit chỉ đi qua fu_lsu_wrapper. lsu_eu chỉ drive dmem_re/addr/mode.
//
// [FIX-JALR] Đã sửa trong fu_alu_wrapper.v.
//
// [FIX-ROB-COMMIT_PC] commit_pc_w expose ra ngoài để testbench dùng.
// =============================================================================

module rv32ifm_ooo #(
    parameter TAG_WIDTH = 7,   // [FIX-FP-TAG] tăng lên 7-bit để đủ 128 tags
    parameter ROB_IDX   = 5,
    parameter ROB_DEPTH = 32,
    parameter NUM_PHYS  = 64,  // INT: p0..p63  (p32..p63 free)
    parameter NUM_ARCH  = 32,
    // [FIX-FP-TAG] FP dùng tag riêng p64..p127, tránh collision với INT
    parameter FP_NUM_PHYS = 64, // FP physical regs: p64..p127
    parameter FP_NUM_ARCH = 32  // FP arch regs f0..f31 → initial tag p64..p95
)(
    input  wire clk,
    input  wire rst_n
);

    // =========================================================================
    // §1  FETCH
    // =========================================================================
    wire [31:0] pc_out, pc_next, flush_pc_target, inst_raw;
    wire        pc_en, flush_pipeline, stall;

    // [FIX-FLUSH-PC] pc_en=1 khi flush (để PC nhảy đến target) hoặc không stall
    // pc_next được assign bởi BP block phía dưới (sau khi tất cả signals sẵn sàng)
    assign pc_en = flush_pipeline || !stall;

    wire [31:0] disp_int_rs1_data;
    wire [31:0] disp_int_rs2_data;
    wire [31:0] disp_fp_rs1_data;
    wire [31:0] disp_fp_rs2_data;

    PC u_pc (
        .clk     (clk),
        .en      (pc_en),
        .rst     (rst_n),
        .addr_in (pc_next),
        .addr_out(pc_out)
    );

    instruction_Mem u_imem (
        .addr(pc_out),
        .inst(inst_raw)
    );

    reg [31:0] if_id_pc, if_id_inst;
    reg        if_id_valid;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            if_id_pc    <= 32'd0;
            if_id_inst  <= 32'd0;
            if_id_valid <= 1'b0;
        end else if (flush_pipeline) begin
            if_id_pc    <= 32'd0;
            if_id_inst  <= 32'd0;
            if_id_valid <= 1'b0;
        end else if (!stall) begin
            if_id_pc    <= pc_out;
            if_id_inst  <= inst_raw;
            if_id_valid <= 1'b1;
        end
    end

    // =========================================================================
    // §2  DECODE / RENAME
    // =========================================================================
    wire [4:0]  dec_rd, dec_rs1, dec_rs2, dec_rs3;
    wire [31:0] dec_imm;
    wire        dec_use_rs1, dec_use_rs2, dec_use_rs3, dec_use_rd;
    wire        dec_fp_rs1,  dec_fp_rs2,  dec_fp_rs3,  dec_fp_rd;
    wire        dec_to_alu_raw, dec_to_fpu_raw, dec_to_lsu;
    wire [4:0]  dec_alu_op, dec_fpu_op;
    wire [2:0]  dec_lsu_op;
    wire        dec_is_branch, dec_is_jal, dec_is_jalr;
    wire        dec_is_lui,    dec_is_auipc;
    wire        dec_is_load,   dec_is_store;
    wire        dec_is_fp_load, dec_is_fp_store;
    wire [2:0]  dec_branch_op;
    wire        dec_valid;

    Control_Unit u_ctrl (
        .inst        (if_id_inst),
        .pc          (if_id_pc),
        .rd          (dec_rd),
        .rs1         (dec_rs1),
        .rs2         (dec_rs2),
        .rs3         (dec_rs3),
        .imm         (dec_imm),
        .use_rs1     (dec_use_rs1),
        .use_rs2     (dec_use_rs2),
        .use_rs3     (dec_use_rs3),
        .use_rd      (dec_use_rd),
        .fp_rs1      (dec_fp_rs1),
        .fp_rs2      (dec_fp_rs2),
        .fp_rs3      (dec_fp_rs3),
        .fp_rd       (dec_fp_rd),
        .to_alu      (dec_to_alu_raw),
        .to_fpu      (dec_to_fpu_raw),
        .to_lsu      (dec_to_lsu),
        .alu_op      (dec_alu_op),
        .fpu_op      (dec_fpu_op),
        .lsu_op      (dec_lsu_op),
        .is_branch   (dec_is_branch),
        .is_jal      (dec_is_jal),
        .is_jalr     (dec_is_jalr),
        .is_lui      (dec_is_lui),
        .is_auipc    (dec_is_auipc),
        .is_load     (dec_is_load),
        .is_store    (dec_is_store),
        .is_fp_load  (dec_is_fp_load),
        .is_fp_store (dec_is_fp_store),
        .branch_op   (dec_branch_op),
        .valid       (dec_valid)
    );

    wire dec_to_fpu = dec_to_fpu_raw && !dec_is_fp_load && !dec_is_fp_store;
    wire dec_to_alu = dec_to_alu_raw;

    // --- Free List Int ---
    wire        fl_int_alloc_ok;
    wire [TAG_WIDTH-1:0] fl_int_alloc_tag;
    wire        fl_int_free_valid;
    wire [TAG_WIDTH-1:0] fl_int_free_tag;
    // [FIX-JAL/JALR] JAL/JALR cũng cần snapshot để free_list restore đúng khi flush
    wire fl_int_snapshot_en = if_id_valid && dec_valid
                              && (dec_is_branch || dec_is_jal || dec_is_jalr) && !stall;

    free_list #(.NUM_PHYS(NUM_PHYS),.NUM_ARCH(NUM_ARCH),.TAG_WIDTH(TAG_WIDTH)) u_fl_int (
        .clk        (clk),
        .rst_n      (rst_n),
        .flush      (flush_pipeline),
        .snapshot_en(fl_int_snapshot_en),
        .alloc_valid(if_id_valid && dec_valid && dec_use_rd && !dec_fp_rd && !stall),
        .alloc_tag  (fl_int_alloc_tag),
        .alloc_ok   (fl_int_alloc_ok),
        .free_valid (fl_int_free_valid),
        .free_tag   (fl_int_free_tag)
    );

    // --- Free List Float ---
    // [FIX-FP-TAG] BASE_TAG=64: FP tags = p96..p127, tách khỏi INT p32..p63
    wire        fl_fp_alloc_ok;
    wire [TAG_WIDTH-1:0] fl_fp_alloc_tag;
    wire        fl_fp_free_valid;
    wire [TAG_WIDTH-1:0] fl_fp_free_tag;

    free_list #(
        .NUM_PHYS (FP_NUM_PHYS),
        .NUM_ARCH (FP_NUM_ARCH),
        .TAG_WIDTH(TAG_WIDTH),
        .BASE_TAG (NUM_PHYS)     // FP free range bắt đầu từ tag 64
    ) u_fl_fp (
        .clk        (clk),
        .rst_n      (rst_n),
        .flush      (flush_pipeline),
        .snapshot_en(fl_int_snapshot_en),
        .alloc_valid(if_id_valid && dec_valid && dec_use_rd && dec_fp_rd && !stall),
        .alloc_tag  (fl_fp_alloc_tag),
        .alloc_ok   (fl_fp_alloc_ok),
        .free_valid (fl_fp_free_valid),
        .free_tag   (fl_fp_free_tag)
    );

    wire [TAG_WIDTH-1:0] new_prd    = dec_fp_rd ? fl_fp_alloc_tag : fl_int_alloc_tag;
    wire                 new_prd_ok = dec_fp_rd ? fl_fp_alloc_ok  : fl_int_alloc_ok;

    // Forward declarations
    wire        commit_valid_w;
    wire [4:0]  commit_rd_arch_w;
    wire [TAG_WIDTH-1:0] commit_prd_w;
    wire        commit_fp_rd_w;
    wire [31:0] commit_result_w;
    wire        commit_use_rd_w;
    wire        do_dispatch;

    // --- RAT Int ---
    wire [TAG_WIDTH-1:0] rat_int_prs1_tag, rat_int_prs2_tag;
    wire [TAG_WIDTH-1:0] rat_int_old_prd;
    wire                 rat_int_free_valid;
    wire [TAG_WIDTH-1:0] rat_int_old_prd_dispatch;

    RAT_Int #(.TAG_WIDTH(TAG_WIDTH)) u_rat_int (
        .clk               (clk),
        .rst_n             (rst_n),
        .flush             (flush_pipeline),
        .rs1_addr          (dec_rs1),
        .rs1_tag           (rat_int_prs1_tag),
        .rs2_addr          (dec_rs2),
        .rs2_tag           (rat_int_prs2_tag),
        .rd_addr           (dec_rd),
        .rd_current_tag    (rat_int_old_prd_dispatch),
        .issue_valid       (do_dispatch && dec_use_rd && !dec_fp_rd),
        .issue_rd          (dec_rd),
        .issue_new_pr_tag  (new_prd),
        .commit_valid      (commit_valid_w && !commit_fp_rd_w),
        .commit_rd         (commit_rd_arch_w),
        .commit_pr_tag     (commit_prd_w),
        .old_pr_tag_to_free(rat_int_old_prd),
        .free_tag_valid    (rat_int_free_valid)
    );

    // --- RAT Float ---
    wire [TAG_WIDTH-1:0] rat_fp_prs1_tag, rat_fp_prs2_tag, rat_fp_prs3_tag;
    wire [TAG_WIDTH-1:0] rat_fp_old_prd;
    wire                 rat_fp_free_valid;
    wire [TAG_WIDTH-1:0] rat_fp_old_prd_dispatch;

    // [FIX-FP-TAG] RAT_Float dùng BASE_TAG=64: f0→p64, f1→p65, ...
    RAT_Float #(.TAG_WIDTH(TAG_WIDTH), .BASE_TAG(NUM_PHYS)) u_rat_fp (
        .clk               (clk),
        .rst_n             (rst_n),
        .flush             (flush_pipeline),
        .rs1_addr          (dec_rs1),
        .rs1_tag           (rat_fp_prs1_tag),
        .rs2_addr          (dec_rs2),
        .rs2_tag           (rat_fp_prs2_tag),
        .rs3_addr          (dec_rs3),
        .rs3_tag           (rat_fp_prs3_tag),
        .rd_addr           (dec_rd),
        .rd_current_tag    (rat_fp_old_prd_dispatch),
        .issue_valid       (do_dispatch && dec_use_rd && dec_fp_rd),
        .issue_rd          (dec_rd),
        .issue_new_pr_tag  (new_prd),
        .commit_valid      (commit_valid_w && commit_fp_rd_w),
        .commit_rd         (commit_rd_arch_w),
        .commit_pr_tag     (commit_prd_w),
        .old_pr_tag_to_free(rat_fp_old_prd),
        .free_tag_valid    (rat_fp_free_valid)
    );

    assign fl_int_free_valid = rat_int_free_valid;
    assign fl_int_free_tag   = rat_int_old_prd;
    assign fl_fp_free_valid  = rat_fp_free_valid;
    assign fl_fp_free_tag    = rat_fp_old_prd;

    wire [TAG_WIDTH-1:0] ren_prs1 = dec_fp_rs1 ? rat_fp_prs1_tag : rat_int_prs1_tag;
    wire [TAG_WIDTH-1:0] ren_prs2 = dec_fp_rs2 ? rat_fp_prs2_tag : rat_int_prs2_tag;
    wire [TAG_WIDTH-1:0] ren_prs3 = dec_fp_rs3 ? rat_fp_prs3_tag : {TAG_WIDTH{1'b0}};
    wire [TAG_WIDTH-1:0] ren_prd  = new_prd;
    wire [TAG_WIDTH-1:0] ren_old_prd = dec_fp_rd ? rat_fp_old_prd_dispatch
                                                  : rat_int_old_prd_dispatch;

    // =========================================================================
    // [FIX-DISP-DATA] Registered dispatch tags — latch ren_prs1/2 tại đúng cycle
    //
    // Vấn đề gốc:
    //   Cycle N   : do_dispatch=1, ren_prs1=pTag_A
    //   Cycle N+1 : dispatch_unit latch IQ entry, prf_int_rd_tag[port4/5] dùng
    //               ren_prs1/2 combinational → lúc này là tag của lệnh MỚI (B)!
    //               → IQ nhận data/ready của tag B thay vì tag A
    //
    // Giải pháp: latch ren_prs1/2 tại posedge cycle N (khi do_dispatch)
    //   → PRF port 6/7 đọc đúng tag A ở cycle N+1
    // =========================================================================
    reg [TAG_WIDTH-1:0] disp_prs1_tag_r, disp_prs2_tag_r;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            disp_prs1_tag_r <= {TAG_WIDTH{1'b0}};
            disp_prs2_tag_r <= {TAG_WIDTH{1'b0}};
        end else if (do_dispatch) begin
            disp_prs1_tag_r <= ren_prs1;
            disp_prs2_tag_r <= ren_prs2;
        end
    end

    // =========================================================================
    // §3  ROB
    // =========================================================================
    wire [ROB_IDX-1:0] rob_idx_alloc;
    wire               rob_full;

    wire        wb0_valid_w; wire [ROB_IDX-1:0] wb0_rob_idx_w; wire [31:0] wb0_result_w; wire wb0_exc_w;
    wire        wb1_valid_w; wire [ROB_IDX-1:0] wb1_rob_idx_w; wire [31:0] wb1_result_w; wire wb1_exc_w;
    wire        wb2_valid_w; wire [ROB_IDX-1:0] wb2_rob_idx_w; wire [31:0] wb2_result_w; wire wb2_exc_w;
    wire        wb3_valid_w; wire [ROB_IDX-1:0] wb3_rob_idx_w; wire [31:0] wb3_result_w; wire wb3_exc_w;
    wire        wbs_valid_w; wire [ROB_IDX-1:0] wbs_rob_idx_w;
    wire [31:0] wbs_store_addr_w, wbs_store_data_w; wire [2:0] wbs_store_mode_w;

    wire [TAG_WIDTH-1:0] cdb0_tag_w, cdb1_tag_w, cdb2_tag_w, cdb3_tag_w;
    wire                 cdb0_valid_w, cdb1_valid_w, cdb2_valid_w, cdb3_valid_w;
    wire [31:0]          cdb0_data_w, cdb1_data_w, cdb2_data_w, cdb3_data_w;

    wire        commit_store_w;
    wire [31:0] commit_store_addr_w, commit_store_data_w;
    wire [2:0]  commit_store_mode_w;
    wire [TAG_WIDTH-1:0] commit_old_prd_w;
    wire        rob_empty_w;
    wire        store_pending_w;   // [FIX-STORE-LOAD-ORDER] ROB → IQ_MEM
    wire [31:0] commit_pc_w;

    wire        rob_alloc_valid_w;
    wire [31:0] rob_alloc_pc_w;
    wire [4:0]  rob_alloc_rd_arch_w;
    wire [TAG_WIDTH-1:0] rob_alloc_prd_w, rob_alloc_old_prd_w;
    wire        rob_alloc_fp_rd_w, rob_alloc_is_branch_w;
    wire        rob_alloc_is_jump_w;      // [FIX-JAL/JALR]
    wire [31:0] rob_alloc_jump_rd_val_w;  // [FIX-JAL/JALR]
    wire        rob_alloc_is_store_w, rob_alloc_use_rd_w;

    ROB #(.ROB_DEPTH(ROB_DEPTH),.TAG_WIDTH(TAG_WIDTH),.ROB_IDX(ROB_IDX)) u_rob (
        .clk              (clk),
        .rst_n            (rst_n),
        .alloc_valid      (rob_alloc_valid_w),
        .alloc_pc         (rob_alloc_pc_w),
        .alloc_rd_arch    (rob_alloc_rd_arch_w),
        .alloc_prd        (rob_alloc_prd_w),
        .alloc_old_prd    (rob_alloc_old_prd_w),
        .alloc_fp_rd      (rob_alloc_fp_rd_w),
        .alloc_is_branch  (rob_alloc_is_branch_w),
        .alloc_is_jump    (rob_alloc_is_jump_w),
        .alloc_jump_rd_val(rob_alloc_jump_rd_val_w),
        .alloc_is_store   (rob_alloc_is_store_w),
        .alloc_use_rd     (rob_alloc_use_rd_w),
        .rob_idx          (rob_idx_alloc),
        .rob_full         (rob_full),
        .wb0_valid(wb0_valid_w), .wb0_rob_idx(wb0_rob_idx_w), .wb0_result(wb0_result_w), .wb0_exc(wb0_exc_w),
        .wb1_valid(wb1_valid_w), .wb1_rob_idx(wb1_rob_idx_w), .wb1_result(wb1_result_w), .wb1_exc(wb1_exc_w),
        .wb2_valid(wb2_valid_w), .wb2_rob_idx(wb2_rob_idx_w), .wb2_result(wb2_result_w), .wb2_exc(wb2_exc_w),
        .wb3_valid(wb3_valid_w), .wb3_rob_idx(wb3_rob_idx_w), .wb3_result(wb3_result_w), .wb3_exc(wb3_exc_w),
        .wbs_valid(wbs_valid_w), .wbs_rob_idx(wbs_rob_idx_w),
        .wbs_store_addr(wbs_store_addr_w), .wbs_store_data(wbs_store_data_w), .wbs_store_mode(wbs_store_mode_w),
        .commit_valid     (commit_valid_w),
        .commit_rd_arch   (commit_rd_arch_w),
        .commit_prd       (commit_prd_w),
        .commit_old_prd   (commit_old_prd_w),
        .commit_fp_rd     (commit_fp_rd_w),
        .commit_result    (commit_result_w),
        .commit_pc        (commit_pc_w),
        .commit_use_rd    (commit_use_rd_w),
        .commit_store     (commit_store_w),
        .commit_store_addr(commit_store_addr_w),
        .commit_store_data(commit_store_data_w),
        .commit_store_mode(commit_store_mode_w),
        .flush            (flush_pipeline),
        .flush_pc         (flush_pc_target),
        .cdb0_tag(cdb0_tag_w), .cdb0_valid(cdb0_valid_w), .cdb0_data(cdb0_data_w),
        .cdb1_tag(cdb1_tag_w), .cdb1_valid(cdb1_valid_w), .cdb1_data(cdb1_data_w),
        .cdb2_tag(cdb2_tag_w), .cdb2_valid(cdb2_valid_w), .cdb2_data(cdb2_data_w),
        .cdb3_tag(cdb3_tag_w), .cdb3_valid(cdb3_valid_w), .cdb3_data(cdb3_data_w),
        .rob_empty        (rob_empty_w),
        .store_pending    (store_pending_w)
    );

    // =========================================================================
    // §4  DISPATCH UNIT
    // =========================================================================
    wire iq_alu_full_w, iq_fpu_full_w, iq_lsu_full_w;
    wire dispatch_ready_w;
    wire prs1_int_ready_w, prs1_fp_ready_w;
    wire prs2_int_ready_w, prs2_fp_ready_w;
    wire prs3_fp_ready_w;

    wire        iq_alu_wr_en_w, iq_fpu_wr_en_w, iq_lsu_wr_en_w;
    wire [TAG_WIDTH-1:0] iq_prd_w, iq_prs1_w, iq_prs2_w, iq_prs3_w;
    wire        iq_prs1_ready_w, iq_prs2_ready_w, iq_prs3_ready_w;
    wire [31:0] iq_imm_w, iq_pc_w;
    wire [4:0]  iq_alu_op_w, iq_fpu_op_w;
    wire [2:0]  iq_lsu_op_w;
    wire [ROB_IDX-1:0] iq_rob_idx_w;
    wire        iq_use_imm_w;
    wire        iq_is_branch_w, iq_is_jal_w, iq_is_jalr_w, iq_is_lui_w, iq_is_auipc_w;
    wire        iq_is_load_w, iq_is_store_w, iq_is_fp_load_w, iq_is_fp_store_w;
    wire [2:0]  iq_branch_op_w;
    wire        iq_fp_rd_w, iq_fp_rs1_w, iq_fp_rs2_w;

    dispatch_unit #(.TAG_WIDTH(TAG_WIDTH),.ROB_IDX(ROB_IDX)) u_dispatch (
        .clk               (clk),
        .rst_n             (rst_n),
        .flush             (flush_pipeline),
        .ren_valid         (if_id_valid && dec_valid),
        .dispatch_ready    (dispatch_ready_w),
        .ren_rd            (dec_rd),
        .ren_rs1           (dec_rs1),
        .ren_rs2           (dec_rs2),
        .ren_rs3           (dec_rs3),
        .ren_prd           (ren_prd),
        .ren_prs1          (ren_prs1),
        .ren_prs2          (ren_prs2),
        .ren_prs3          (ren_prs3),
        .ren_old_prd       (ren_old_prd),
        .ren_imm           (dec_imm),
        .ren_pc            (if_id_pc),
        .ren_use_rs1       (dec_use_rs1),
        .ren_use_rs2       (dec_use_rs2),
        .ren_use_rs3       (dec_use_rs3),
        .ren_use_rd        (dec_use_rd),
        .ren_fp_rs1        (dec_fp_rs1),
        .ren_fp_rs2        (dec_fp_rs2),
        .ren_fp_rs3        (dec_fp_rs3),
        .ren_fp_rd         (dec_fp_rd),
        .ren_to_alu        (dec_to_alu),
        .ren_to_fpu        (dec_to_fpu),
        .ren_to_lsu        (dec_to_lsu),
        .ren_alu_op        (dec_alu_op),
        .ren_fpu_op        (dec_fpu_op),
        .ren_lsu_op        (dec_lsu_op),
        .ren_is_branch     (dec_is_branch),
        .ren_is_jal        (dec_is_jal),
        .ren_is_jalr       (dec_is_jalr),
        .ren_is_lui        (dec_is_lui),
        .ren_is_auipc      (dec_is_auipc),
        .ren_is_load       (dec_is_load),
        .ren_is_store      (dec_is_store),
        .ren_is_fp_load    (dec_is_fp_load),
        .ren_is_fp_store   (dec_is_fp_store),
        .ren_branch_op     (dec_branch_op),
        .rob_alloc_valid   (rob_alloc_valid_w),
        .rob_alloc_pc      (rob_alloc_pc_w),
        .rob_alloc_rd_arch (rob_alloc_rd_arch_w),
        .rob_alloc_prd     (rob_alloc_prd_w),
        .rob_alloc_old_prd (rob_alloc_old_prd_w),
        .rob_alloc_fp_rd   (rob_alloc_fp_rd_w),
        .rob_alloc_is_branch(rob_alloc_is_branch_w),
        .rob_alloc_is_jump      (rob_alloc_is_jump_w),
        .rob_alloc_jump_rd_val  (rob_alloc_jump_rd_val_w),
        .rob_alloc_is_store (rob_alloc_is_store_w),
        .rob_alloc_use_rd   (rob_alloc_use_rd_w),
        .rob_idx           (rob_idx_alloc),
        .rob_full          (rob_full),
        .iq_alu_wr_en      (iq_alu_wr_en_w),
        .iq_fpu_wr_en      (iq_fpu_wr_en_w),
        .iq_lsu_wr_en      (iq_lsu_wr_en_w),
        .iq_prd            (iq_prd_w),
        .iq_prs1           (iq_prs1_w),
        .iq_prs2           (iq_prs2_w),
        .iq_prs3           (iq_prs3_w),
        .iq_prs1_ready     (iq_prs1_ready_w),
        .iq_prs2_ready     (iq_prs2_ready_w),
        .iq_prs3_ready     (iq_prs3_ready_w),
        .iq_imm            (iq_imm_w),
        .iq_pc             (iq_pc_w),
        .iq_alu_op         (iq_alu_op_w),
        .iq_fpu_op         (iq_fpu_op_w),
        .iq_lsu_op         (iq_lsu_op_w),
        .iq_rob_idx        (iq_rob_idx_w),
        .iq_use_imm        (iq_use_imm_w),
        .iq_is_branch      (iq_is_branch_w),
        .iq_is_jal         (iq_is_jal_w),
        .iq_is_jalr        (iq_is_jalr_w),
        .iq_is_lui         (iq_is_lui_w),
        .iq_is_auipc       (iq_is_auipc_w),
        .iq_is_load        (iq_is_load_w),
        .iq_is_store       (iq_is_store_w),
        .iq_is_fp_load     (iq_is_fp_load_w),
        .iq_is_fp_store    (iq_is_fp_store_w),
        .iq_branch_op      (iq_branch_op_w),
        .iq_fp_rd          (iq_fp_rd_w),
        .iq_fp_rs1         (iq_fp_rs1_w),
        .iq_fp_rs2         (iq_fp_rs2_w),
        .iq_alu_full       (iq_alu_full_w),
        .iq_fpu_full       (iq_fpu_full_w),
        .iq_lsu_full       (iq_lsu_full_w),
        .prf_int_ready     ({TAG_WIDTH{1'b0}}),
        .prs1_int_ready_in (prs1_int_ready_w),
        .prs1_fp_ready_in  (prs1_fp_ready_w),
        .prs2_int_ready_in (prs2_int_ready_w),
        .prs2_fp_ready_in  (prs2_fp_ready_w),
        .prs3_fp_ready_in  (prs3_fp_ready_w)
    );

    assign do_dispatch = (if_id_valid && dec_valid && dispatch_ready_w);
    assign stall       = (if_id_valid && dec_valid && !dispatch_ready_w);

    // =========================================================================
    // §5  ISSUE QUEUES
    // =========================================================================
    wire [TAG_WIDTH-1:0] iq_alu_prf_rs1_tag, iq_alu_prf_rs2_tag;
    wire [TAG_WIDTH-1:0] iq_fpu_prf_rs1_tag, iq_fpu_prf_rs2_tag, iq_fpu_prf_rs3_tag;
    wire [TAG_WIDTH-1:0] iq_lsu_prf_rs1_tag, iq_lsu_prf_rs2_tag;

    wire [31:0] prf_int_rs1_for_alu, prf_int_rs2_for_alu;
    wire [31:0] prf_fp_rs1_for_fpu,  prf_fp_rs2_for_fpu, prf_fp_rs3_for_fpu;
    wire [31:0] prf_int_rs1_for_lsu;
    wire [31:0] prf_rs2_for_lsu;

    wire        iq_alu_issue_valid;
    wire [TAG_WIDTH-1:0] iq_alu_issue_prd;
    wire [ROB_IDX-1:0]   iq_alu_issue_rob_idx;
    wire [31:0] iq_alu_issue_rs1_val, iq_alu_issue_rs2_val;
    wire [31:0] iq_alu_issue_imm, iq_alu_issue_pc;
    wire [4:0]  iq_alu_issue_alu_op;
    wire        iq_alu_issue_use_imm;
    wire        iq_alu_issue_is_branch, iq_alu_issue_is_jal, iq_alu_issue_is_jalr;
    wire        iq_alu_issue_is_lui,    iq_alu_issue_is_auipc;
    wire [2:0]  iq_alu_issue_branch_op;

    iq_alu #(.NUM_RS(8),.TAG_WIDTH(TAG_WIDTH),.ROB_IDX(ROB_IDX)) u_iq_alu (
        .clk            (clk),
        .rst_n          (rst_n),
        .flush          (flush_pipeline),
        .wr_en          (iq_alu_wr_en_w),
        .wr_prd         (iq_prd_w),
        .wr_prs1        (iq_prs1_w),
        .wr_prs1_ready  (iq_prs1_ready_w),
        .wr_prs2        (iq_prs2_w),
        .wr_prs2_ready  (iq_prs2_ready_w),
        .wr_imm         (iq_imm_w),
        .wr_pc          (iq_pc_w),
        .wr_alu_op      (iq_alu_op_w),
        .wr_rob_idx     (iq_rob_idx_w),
        .wr_use_imm     (iq_use_imm_w),
        .wr_is_branch   (iq_is_branch_w),
        .wr_is_jal      (iq_is_jal_w),
        .wr_is_jalr     (iq_is_jalr_w),
        .wr_is_lui      (iq_is_lui_w),
        .wr_is_auipc    (iq_is_auipc_w),
        .wr_branch_op   (iq_branch_op_w),
        .full           (iq_alu_full_w),
        .cdb0_tag(cdb0_tag_w),.cdb0_valid(cdb0_valid_w),.cdb0_data(cdb0_data_w),
        .cdb1_tag(cdb1_tag_w),.cdb1_valid(cdb1_valid_w),.cdb1_data(cdb1_data_w),
        .cdb2_tag(cdb2_tag_w),.cdb2_valid(cdb2_valid_w),.cdb2_data(cdb2_data_w),
        .cdb3_tag(cdb3_tag_w),.cdb3_valid(cdb3_valid_w),.cdb3_data(cdb3_data_w),
        .prf_rs1_tag    (iq_alu_prf_rs1_tag),
        .prf_rs2_tag    (iq_alu_prf_rs2_tag),
        .wr_prs1_data   (disp_int_rs1_data),
        .wr_prs2_data   (disp_int_rs2_data),
        .prf_rs1_data   (prf_int_rs1_for_alu),
        .prf_rs2_data   (prf_int_rs2_for_alu),
        .issue_valid    (iq_alu_issue_valid),
        .issue_prd      (iq_alu_issue_prd),
        .issue_rob_idx  (iq_alu_issue_rob_idx),
        .issue_rs1_val  (iq_alu_issue_rs1_val),
        .issue_rs2_val  (iq_alu_issue_rs2_val),
        .issue_imm      (iq_alu_issue_imm),
        .issue_pc       (iq_alu_issue_pc),
        .issue_alu_op   (iq_alu_issue_alu_op),
        .issue_use_imm  (iq_alu_issue_use_imm),
        .issue_is_branch(iq_alu_issue_is_branch),
        .issue_is_jal   (iq_alu_issue_is_jal),
        .issue_is_jalr  (iq_alu_issue_is_jalr),
        .issue_is_lui   (iq_alu_issue_is_lui),
        .issue_is_auipc (iq_alu_issue_is_auipc),
        .issue_branch_op(iq_alu_issue_branch_op)
    );

    wire        iq_fpu_issue_valid;
    wire [TAG_WIDTH-1:0] iq_fpu_issue_prd;
    wire [ROB_IDX-1:0]   iq_fpu_issue_rob_idx;
    wire [31:0] iq_fpu_issue_rs1_val, iq_fpu_issue_rs2_val, iq_fpu_issue_rs3_val;
    wire [4:0]  iq_fpu_issue_fpu_op;
    wire        iq_fpu_issue_fp_rd, iq_fpu_issue_fp_rs1, iq_fpu_issue_fp_rs2;

    iq_fpu #(.NUM_RS(8),.TAG_WIDTH(TAG_WIDTH),.ROB_IDX(ROB_IDX)) u_iq_fpu (
        .clk            (clk),
        .rst_n          (rst_n),
        .flush          (flush_pipeline),
        .wr_en          (iq_fpu_wr_en_w),
        .wr_prd         (iq_prd_w),
        .wr_prs1        (iq_prs1_w),
        .wr_prs1_ready  (iq_prs1_ready_w),
        .wr_prs2        (iq_prs2_w),
        .wr_prs2_ready  (iq_prs2_ready_w),
        .wr_prs3        (iq_prs3_w),
        .wr_prs3_ready  (iq_prs3_ready_w),
        .wr_fpu_op      (iq_fpu_op_w),
        .wr_rob_idx     (iq_rob_idx_w),
        .wr_fp_rd       (iq_fp_rd_w),
        .wr_fp_rs1      (iq_fp_rs1_w),
        .wr_fp_rs2      (iq_fp_rs2_w),
        .full           (iq_fpu_full_w),
        .cdb0_tag(cdb0_tag_w),.cdb0_valid(cdb0_valid_w),.cdb0_data(cdb0_data_w),
        .cdb1_tag(cdb1_tag_w),.cdb1_valid(cdb1_valid_w),.cdb1_data(cdb1_data_w),
        .cdb2_tag(cdb2_tag_w),.cdb2_valid(cdb2_valid_w),.cdb2_data(cdb2_data_w),
        .cdb3_tag(cdb3_tag_w),.cdb3_valid(cdb3_valid_w),.cdb3_data(cdb3_data_w),
        .prf_rs1_tag    (iq_fpu_prf_rs1_tag),
        .prf_rs2_tag    (iq_fpu_prf_rs2_tag),
        .prf_rs3_tag    (iq_fpu_prf_rs3_tag),
        .wr_prs1_data   (disp_fp_rs1_data),
        .wr_prs2_data   (disp_fp_rs2_data),
        .wr_prs3_data   (32'd0),
        .prf_rs1_data   (prf_fp_rs1_for_fpu),
        .prf_rs2_data   (prf_fp_rs2_for_fpu),
        .prf_rs3_data   (prf_fp_rs3_for_fpu),
        .issue_valid    (iq_fpu_issue_valid),
        .issue_prd      (iq_fpu_issue_prd),
        .issue_rob_idx  (iq_fpu_issue_rob_idx),
        .issue_rs1_val  (iq_fpu_issue_rs1_val),
        .issue_rs2_val  (iq_fpu_issue_rs2_val),
        .issue_rs3_val  (iq_fpu_issue_rs3_val),
        .issue_fpu_op   (iq_fpu_issue_fpu_op),
        .issue_fp_rd    (iq_fpu_issue_fp_rd),
        .issue_fp_rs1   (iq_fpu_issue_fp_rs1),
        .issue_fp_rs2   (iq_fpu_issue_fp_rs2)
    );

    wire        iq_lsu_issue_valid;
    wire [TAG_WIDTH-1:0] iq_lsu_issue_prd;
    wire [ROB_IDX-1:0]   iq_lsu_issue_rob_idx;
    wire [31:0] iq_lsu_issue_rs1_val, iq_lsu_issue_rs2_val, iq_lsu_issue_imm;
    wire [2:0]  iq_lsu_issue_lsu_op;
    wire        iq_lsu_issue_is_load,    iq_lsu_issue_is_store;
    wire        iq_lsu_issue_is_fp_load, iq_lsu_issue_is_fp_store;
    wire        iq_lsu_issue_fp_rd,      iq_lsu_issue_fp_rs2;

    iq_mem #(.NUM_RS(8),.TAG_WIDTH(TAG_WIDTH),.ROB_IDX(ROB_IDX)) u_iq_lsu (
        .clk            (clk),
        .rst_n          (rst_n),
        .flush          (flush_pipeline),
        .wr_en          (iq_lsu_wr_en_w),
        .wr_prd         (iq_prd_w),
        .wr_prs1        (iq_prs1_w),
        .wr_prs1_ready  (iq_prs1_ready_w),
        .wr_prs2        (iq_prs2_w),
        .wr_prs2_ready  (iq_prs2_ready_w),
        .wr_imm         (iq_imm_w),
        .wr_lsu_op      (iq_lsu_op_w),
        .wr_rob_idx     (iq_rob_idx_w),
        .wr_is_load     (iq_is_load_w),
        .wr_is_store    (iq_is_store_w),
        .wr_is_fp_load  (iq_is_fp_load_w),
        .wr_is_fp_store (iq_is_fp_store_w),
        .wr_fp_rd       (iq_fp_rd_w),
        .wr_fp_rs2      (iq_fp_rs2_w),
        .full           (iq_lsu_full_w),
        .store_pending  (store_pending_w),   // [FIX-STORE-LOAD-ORDER]
        .cdb0_tag(cdb0_tag_w),.cdb0_valid(cdb0_valid_w),.cdb0_data(cdb0_data_w),
        .cdb1_tag(cdb1_tag_w),.cdb1_valid(cdb1_valid_w),.cdb1_data(cdb1_data_w),
        .cdb2_tag(cdb2_tag_w),.cdb2_valid(cdb2_valid_w),.cdb2_data(cdb2_data_w),
        .cdb3_tag(cdb3_tag_w),.cdb3_valid(cdb3_valid_w),.cdb3_data(cdb3_data_w),
        .prf_rs1_tag    (iq_lsu_prf_rs1_tag),
        .prf_rs2_tag    (iq_lsu_prf_rs2_tag),
        .wr_prs1_data   (disp_int_rs1_data),
        .wr_prs2_data   (disp_int_rs2_data),
        .prf_rs1_data   (prf_int_rs1_for_lsu),
        .prf_rs2_data   (prf_rs2_for_lsu),
        .issue_valid    (iq_lsu_issue_valid),
        .issue_prd      (iq_lsu_issue_prd),
        .issue_rob_idx  (iq_lsu_issue_rob_idx),
        .issue_rs1_val  (iq_lsu_issue_rs1_val),
        .issue_rs2_val  (iq_lsu_issue_rs2_val),
        .issue_imm      (iq_lsu_issue_imm),
        .issue_lsu_op   (iq_lsu_issue_lsu_op),
        .issue_is_load  (iq_lsu_issue_is_load),
        .issue_is_store (iq_lsu_issue_is_store),
        .issue_is_fp_load (iq_lsu_issue_is_fp_load),
        .issue_is_fp_store(iq_lsu_issue_is_fp_store),
        .issue_fp_rd    (iq_lsu_issue_fp_rd),
        .issue_fp_rs2   (iq_lsu_issue_fp_rs2)
    );

    // =========================================================================
    // §6  PHYSICAL REGISTER FILES
    // =========================================================================
    wire [(8*TAG_WIDTH)-1:0] prf_int_rd_tag;
    wire [(8*32)-1:0]        prf_int_rd_data;
    wire [7:0]               prf_int_rd_ready;

    // port 0: iq_alu_rs1  port 1: iq_alu_rs2
    // port 2: iq_lsu_rs1  port 3: iq_lsu_rs2
    // port 4: ren_prs1 (combinational — chỉ dùng cho ready check tại rename)
    // port 5: ren_prs2 (combinational — chỉ dùng cho ready check tại rename)
    // port 6: disp_prs1_tag_r (registered tag — data đúng cho IQ write)
    // port 7: disp_prs2_tag_r (registered tag — data đúng cho IQ write)
    assign prf_int_rd_tag = {
        disp_prs2_tag_r,    // port 7
        disp_prs1_tag_r,    // port 6
        ren_prs2,           // port 5
        ren_prs1,           // port 4
        iq_lsu_prf_rs2_tag, // port 3
        iq_lsu_prf_rs1_tag, // port 2
        iq_alu_prf_rs2_tag, // port 1
        iq_alu_prf_rs1_tag  // port 0
    };

    reg fpu_rob_fp_rd [0:(1<<ROB_IDX)-1];
    reg lsu_rob_fp_rd [0:(1<<ROB_IDX)-1];
    integer k;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (k = 0; k < (1<<ROB_IDX); k = k+1) begin
                fpu_rob_fp_rd[k] <= 1'b0;
                lsu_rob_fp_rd[k] <= 1'b0;
            end
        end else begin
            if (iq_fpu_issue_valid)
                fpu_rob_fp_rd[iq_fpu_issue_rob_idx] <= iq_fpu_issue_fp_rd;
            if (iq_lsu_issue_valid)
                lsu_rob_fp_rd[iq_lsu_issue_rob_idx] <= iq_lsu_issue_fp_rd;
        end
    end

    wire        alu_wb0_valid;  wire [ROB_IDX-1:0]   alu_wb0_rob_idx;
    wire [31:0] alu_wb0_result; wire                 alu_wb0_exc;
    wire [TAG_WIDTH-1:0] alu_wb0_prd;
    // [BP-UPDATE] branch predictor update từ ALU WB0
    wire [31:0] alu_wb0_pc;
    wire        alu_wb0_is_branch;

    // =========================================================================
    // §1b  BRANCH PREDICTOR — đặt tại đây vì cần alu_wb0_*, do_dispatch,
    //      dec_is_branch/jal/jalr, flush_pipeline đều đã được khai báo
    // =========================================================================
    // BP update wires (driven by alu_wb0 signals above)
    wire        bp_update_en        = alu_wb0_valid && (alu_wb0_is_branch || alu_wb0_exc);
    wire [31:0] bp_update_pc        = alu_wb0_pc;
    wire        bp_update_taken     = alu_wb0_exc;
    wire [31:0] bp_update_target    = alu_wb0_result;
    wire        bp_update_is_branch = alu_wb0_is_branch;
    // =========================================================================
    wire        bp_predict_taken;
    wire [31:0] bp_predict_target;

    // fetch_is_branch: decode từ inst_raw (combinational, opcode 1100011=BRANCH)
    wire fetch_is_branch_comb = (inst_raw[6:0] == 7'b1100011);

    branch_predictor #(
        .BTB_ENTRIES(64),
        .BHT_ENTRIES(256),
        .GHR_WIDTH  (8)
    ) u_bp (
        .clk                   (clk),
        .rst_n                 (rst_n),
        // FETCH query
        .fetch_pc              (pc_out),
        .fetch_is_branch       (fetch_is_branch_comb),
        .predict_taken         (bp_predict_taken),
        .predict_target        (bp_predict_target),
        // DISPATCH checkpoint (GHR snapshot)
        .dispatch_en           (do_dispatch && (dec_is_branch || dec_is_jal || dec_is_jalr)),
        .dispatch_predict_taken(bp_predict_taken),
        // UPDATE từ ALU WB0 (kết quả thực)
        .update_en             (bp_update_en),
        .update_pc             (bp_update_pc),
        .update_taken          (bp_update_taken),
        .update_target         (bp_update_target),
        .update_is_branch      (bp_update_is_branch),
        // FLUSH — restore GHR
        .flush_en              (flush_pipeline),
        .flush_mispred         (flush_pipeline)
    );

    // pc_next: ưu tiên flush > BP taken > PC+4
    assign pc_next = flush_pipeline    ? flush_pc_target  :
                     bp_predict_taken  ? bp_predict_target :
                                         (pc_out + 32'd4);

    wire        alu_wb1_valid;  wire [ROB_IDX-1:0]   alu_wb1_rob_idx;
    wire [31:0] alu_wb1_result; wire                 alu_wb1_exc;
    wire [TAG_WIDTH-1:0] alu_wb1_prd;

    wire        fpu_wb2_valid;  wire [ROB_IDX-1:0]   fpu_wb2_rob_idx;
    wire [31:0] fpu_wb2_result; wire                 fpu_wb2_exc;
    wire [TAG_WIDTH-1:0] fpu_wb2_prd;

    wire        lsu_wb3_valid;  wire [ROB_IDX-1:0]   lsu_wb3_rob_idx;
    wire [31:0] lsu_wb3_result; wire                 lsu_wb3_exc;
    wire [TAG_WIDTH-1:0] lsu_wb3_prd;

    wire        lsu_wbs_valid;  wire [ROB_IDX-1:0]   lsu_wbs_rob_idx;
    wire [31:0] lsu_wbs_store_addr, lsu_wbs_store_data;
    wire [2:0]  lsu_wbs_store_mode;

    wire wb2_is_fp_rd = fpu_rob_fp_rd[fpu_wb2_rob_idx];
    wire wb3_is_fp_rd = lsu_rob_fp_rd[lsu_wb3_rob_idx];

    prf #(.NUM_PHYS(NUM_PHYS),.NUM_ARCH(NUM_ARCH),.TAG_WIDTH(TAG_WIDTH),.NUM_RD(8))
    u_prf_int (
        .clk      (clk),
        .rst_n    (rst_n),
        .rd_tag   (prf_int_rd_tag),
        .rd_data  (prf_int_rd_data),
        .rd_ready (prf_int_rd_ready),
        .wb0_en   (alu_wb0_valid),
        .wb0_tag  (alu_wb0_prd),
        .wb0_data (alu_wb0_result),
        .wb1_en   (alu_wb1_valid),
        .wb1_tag  (alu_wb1_prd),
        .wb1_data (alu_wb1_result),
        .wb2_en   (fpu_wb2_valid && !wb2_is_fp_rd),
        .wb2_tag  (fpu_wb2_prd),
        .wb2_data (fpu_wb2_result),
        .wb3_en   (lsu_wb3_valid && !wb3_is_fp_rd),
        .wb3_tag  (lsu_wb3_prd),
        .wb3_data (lsu_wb3_result),
        .clear_en  (do_dispatch && dec_use_rd && !dec_fp_rd),
        .clear_tag (new_prd)
    );

    assign prf_int_rs1_for_alu = prf_int_rd_data[0*32 +: 32];
    assign prf_int_rs2_for_alu = prf_int_rd_data[1*32 +: 32];
    assign prf_int_rs1_for_lsu = prf_int_rd_data[2*32 +: 32];
    wire [31:0] prf_int_rs2_for_lsu = prf_int_rd_data[3*32 +: 32];

    assign prs1_int_ready_w = prf_int_rd_ready[4]; // port 4: ren_prs1 comb
    assign prs2_int_ready_w = prf_int_rd_ready[5]; // port 5: ren_prs2 comb
    // [FIX] port 6/7 dùng registered tag → data đúng lệnh đang dispatch
    assign disp_int_rs1_data = prf_int_rd_data[6*32 +: 32];
    assign disp_int_rs2_data = prf_int_rd_data[7*32 +: 32];

    wire [(8*TAG_WIDTH)-1:0] prf_fp_rd_tag;
    wire [(8*32)-1:0]        prf_fp_rd_data;
    wire [7:0]               prf_fp_rd_ready;

    assign prf_fp_rd_tag = {
        disp_prs2_tag_r,    // port 7: registered dispatch rs2
        disp_prs1_tag_r,    // port 6: registered dispatch rs1
        ren_prs2,           // port 5: rename ready check
        ren_prs1,           // port 4: rename ready check
        iq_lsu_prf_rs2_tag, // port 3
        iq_fpu_prf_rs3_tag, // port 2
        iq_fpu_prf_rs2_tag, // port 1
        iq_fpu_prf_rs1_tag  // port 0
    };

    // [FIX-FP-TAG] prf_fp cần NUM_PHYS=128 để mem[64..127] hợp lệ
    prf #(.NUM_PHYS(NUM_PHYS+FP_NUM_PHYS),.NUM_ARCH(NUM_ARCH),.TAG_WIDTH(TAG_WIDTH),.NUM_RD(8))
    u_prf_fp (
        .clk      (clk),
        .rst_n    (rst_n),
        .rd_tag   (prf_fp_rd_tag),
        .rd_data  (prf_fp_rd_data),
        .rd_ready (prf_fp_rd_ready),
        .wb0_en   (1'b0), .wb0_tag({TAG_WIDTH{1'b0}}), .wb0_data(32'b0),
        .wb1_en   (1'b0), .wb1_tag({TAG_WIDTH{1'b0}}), .wb1_data(32'b0),
        .wb2_en   (fpu_wb2_valid && wb2_is_fp_rd),
        .wb2_tag  (fpu_wb2_prd),
        .wb2_data (fpu_wb2_result),
        .wb3_en   (lsu_wb3_valid && wb3_is_fp_rd),
        .wb3_tag  (lsu_wb3_prd),
        .wb3_data (lsu_wb3_result),
        .clear_en  (do_dispatch && dec_use_rd && dec_fp_rd),
        .clear_tag (new_prd)
    );

    assign prf_fp_rs1_for_fpu = prf_fp_rd_data[0*32 +: 32];
    assign prf_fp_rs2_for_fpu = prf_fp_rd_data[1*32 +: 32];
    assign prf_fp_rs3_for_fpu = prf_fp_rd_data[2*32 +: 32];

    assign prs1_fp_ready_w = prf_fp_rd_ready[4];
    assign prs2_fp_ready_w = prf_fp_rd_ready[5];
    assign prs3_fp_ready_w = 1'b0;
    // [FIX] port 6/7 dùng registered tag
    assign disp_fp_rs1_data = prf_fp_rd_data[6*32 +: 32];
    assign disp_fp_rs2_data = prf_fp_rd_data[7*32 +: 32];

    assign prf_rs2_for_lsu = iq_lsu_issue_fp_rs2
                             ? prf_fp_rd_data[3*32 +: 32]
                             : prf_int_rs2_for_lsu;

    // =========================================================================
    // §7  EXECUTE STAGE
    // =========================================================================
    wire        dmem_re_w;
    wire [2:0]  dmem_load_mode_w;
    wire [9:0]  dmem_addr_w;
    wire [31:0] dmem_rdata_w;

    fu_alu_wrapper #(.TAG_WIDTH(TAG_WIDTH),.ROB_IDX(ROB_IDX)) u_alu_eu (
        .clk             (clk),
        .rst_n           (rst_n),
        .flush           (flush_pipeline),
        .issue_valid     (iq_alu_issue_valid),
        .issue_prd       (iq_alu_issue_prd),
        .issue_rs1_val   (iq_alu_issue_rs1_val),
        .issue_rs2_val   (iq_alu_issue_rs2_val),
        .issue_imm       (iq_alu_issue_imm),
        .issue_pc        (iq_alu_issue_pc),
        .issue_alu_op    (iq_alu_issue_alu_op),
        .issue_rob_idx   (iq_alu_issue_rob_idx),
        .issue_use_imm   (iq_alu_issue_use_imm),
        .issue_is_branch (iq_alu_issue_is_branch),
        .issue_is_jal    (iq_alu_issue_is_jal),
        .issue_is_jalr   (iq_alu_issue_is_jalr),
        .issue_is_lui    (iq_alu_issue_is_lui),
        .issue_is_auipc  (iq_alu_issue_is_auipc),
        .issue_branch_op (iq_alu_issue_branch_op),
        .wb0_valid       (alu_wb0_valid),
        .wb0_rob_idx     (alu_wb0_rob_idx),
        .wb0_result      (alu_wb0_result),
        .wb0_exc         (alu_wb0_exc),
        .wb0_prd         (alu_wb0_prd),
        .wb0_pc          (alu_wb0_pc),
        .wb0_is_branch   (alu_wb0_is_branch),
        .wb1_valid       (alu_wb1_valid),
        .wb1_rob_idx     (alu_wb1_rob_idx),
        .wb1_result      (alu_wb1_result),
        .wb1_exc         (alu_wb1_exc),
        .wb1_prd         (alu_wb1_prd)
    );

    fu_fpu_wrapper #(.TAG_WIDTH(TAG_WIDTH),.ROB_IDX(ROB_IDX)) u_fpu_eu (
        .clk           (clk),
        .rst_n         (rst_n),
        .flush         (flush_pipeline),
        .issue_valid   (iq_fpu_issue_valid),
        .issue_prd     (iq_fpu_issue_prd),
        .issue_rs1_val (iq_fpu_issue_rs1_val),
        .issue_rs2_val (iq_fpu_issue_rs2_val),
        .issue_rs3_val (iq_fpu_issue_rs3_val),
        .issue_fpu_op  (iq_fpu_issue_fpu_op),
        .issue_rob_idx (iq_fpu_issue_rob_idx),
        .wb2_valid     (fpu_wb2_valid),
        .wb2_rob_idx   (fpu_wb2_rob_idx),
        .wb2_result    (fpu_wb2_result),
        .wb2_exc       (fpu_wb2_exc),
        .wb2_prd       (fpu_wb2_prd)
    );

    // [FIX-DMEM-DOUBLE] lsu_eu không nhận store commit trực tiếp nữa
    lsu_eu #(.TAG_WIDTH(TAG_WIDTH),.ROB_IDX(ROB_IDX)) u_lsu_eu (
        .clk               (clk),
        .rst_n             (rst_n),
        .flush             (flush_pipeline),
        .issue_valid       (iq_lsu_issue_valid),
        .issue_prd         (iq_lsu_issue_prd),
        .issue_rs1_val     (iq_lsu_issue_rs1_val),
        .issue_rs2_val     (iq_lsu_issue_rs2_val),
        .issue_imm         (iq_lsu_issue_imm),
        .issue_lsu_op      (iq_lsu_issue_lsu_op),
        .issue_rob_idx     (iq_lsu_issue_rob_idx),
        .issue_is_load     (iq_lsu_issue_is_load),
        .issue_is_store    (iq_lsu_issue_is_store),
        .issue_is_fp_load  (iq_lsu_issue_is_fp_load),
        .issue_is_fp_store (iq_lsu_issue_is_fp_store),
        .wb3_valid         (lsu_wb3_valid),
        .wb3_rob_idx       (lsu_wb3_rob_idx),
        .wb3_result        (lsu_wb3_result),
        .wb3_exc           (lsu_wb3_exc),
        .wb3_prd           (lsu_wb3_prd),
        .wbs_valid         (lsu_wbs_valid),
        .wbs_rob_idx       (lsu_wbs_rob_idx),
        .wbs_store_addr    (lsu_wbs_store_addr),
        .wbs_store_data    (lsu_wbs_store_data),
        .wbs_store_mode    (lsu_wbs_store_mode),
        .dmem_re           (dmem_re_w),
        .dmem_load_mode    (dmem_load_mode_w),
        .dmem_addr         (dmem_addr_w),
        .dmem_rdata        (dmem_rdata_w)
        // [FIX] Đã xóa dmem_we/waddr/wdata — store commit chỉ đi qua fu_lsu_wrapper
    );

    fu_lsu_wrapper u_dmem_wrap (
        .clk        (clk),
        .re         (dmem_re_w),
        .load_mode  (dmem_load_mode_w),
        .load_addr  (dmem_addr_w),
        .load_data  (dmem_rdata_w),
        .we         (commit_store_w),
        .store_mode (commit_store_mode_w),
        .store_addr (commit_store_addr_w[9:0]),
        .store_data (commit_store_data_w)
    );

    // =========================================================================
    // §8  WRITEBACK BUS AGGREGATION
    // =========================================================================
    assign wb0_valid_w      = alu_wb0_valid;
    assign wb0_rob_idx_w    = alu_wb0_rob_idx;
    assign wb0_result_w     = alu_wb0_result;
    assign wb0_exc_w        = alu_wb0_exc;

    assign wb1_valid_w      = alu_wb1_valid;
    assign wb1_rob_idx_w    = alu_wb1_rob_idx;
    assign wb1_result_w     = alu_wb1_result;
    assign wb1_exc_w        = alu_wb1_exc;

    assign wb2_valid_w      = fpu_wb2_valid;
    assign wb2_rob_idx_w    = fpu_wb2_rob_idx;
    assign wb2_result_w     = fpu_wb2_result;
    assign wb2_exc_w        = fpu_wb2_exc;

    assign wb3_valid_w      = lsu_wb3_valid;
    assign wb3_rob_idx_w    = lsu_wb3_rob_idx;
    assign wb3_result_w     = lsu_wb3_result;
    assign wb3_exc_w        = lsu_wb3_exc;

    assign wbs_valid_w      = lsu_wbs_valid;
    assign wbs_rob_idx_w    = lsu_wbs_rob_idx;
    assign wbs_store_addr_w = lsu_wbs_store_addr;
    assign wbs_store_data_w = lsu_wbs_store_data;
    assign wbs_store_mode_w = lsu_wbs_store_mode;

endmodule