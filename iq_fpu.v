// =============================================================================
// iq_fpu.v  —  Issue Queue cho FPU
//
// Payload riêng của FPU:
//   • rs1_val, rs2_val, rs3_val  (FP operands — rs3 cho FMADD/FMSUB/FNMADD/FNMSUB)
//   • fpu_op [4:0]
//   • prd (FP physical dest), rob_idx
//   • fp_rd, fp_rs1, fp_rs2  (loại register file — hỗ trợ FCVT cross Int/FP)
//
// KHÔNG có: alu_op, lsu_op, imm, pc, branch, jal, lui, load, store
//
// CDB snoop: 4 port — snoop cả rs1/rs2/rs3 vì FPU có R4-type
// =============================================================================

module iq_fpu #(
    parameter NUM_RS    = 8,
    parameter TAG_WIDTH = 7,   // [FIX-FP-TAG] 7-bit cho tag 0..127
    parameter ROB_IDX   = 5
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        flush,

    // -------------------------------------------------------------------------
    // Write port (từ Dispatch)
    // -------------------------------------------------------------------------
    input  wire                  wr_en,
    input  wire [TAG_WIDTH-1:0]  wr_prd,
    input  wire [TAG_WIDTH-1:0]  wr_prs1,
    input  wire                  wr_prs1_ready,
    input  wire [TAG_WIDTH-1:0]  wr_prs2,
    input  wire                  wr_prs2_ready,
    input  wire [31:0]           wr_prs1_data,
    input  wire [31:0]           wr_prs2_data,
    input  wire [31:0]           wr_prs3_data,
    input  wire [TAG_WIDTH-1:0]  wr_prs3,
    input  wire                  wr_prs3_ready,
    input  wire [4:0]            wr_fpu_op,
    input  wire [ROB_IDX-1:0]   wr_rob_idx,
    input  wire                  wr_fp_rd,
    input  wire                  wr_fp_rs1,
    input  wire                  wr_fp_rs2,

    output wire                  full,

    // -------------------------------------------------------------------------
    // CDB (4 port)
    // -------------------------------------------------------------------------
    input  wire [TAG_WIDTH-1:0]  cdb0_tag,
    input  wire                  cdb0_valid,
    input  wire [31:0]           cdb0_data,

    input  wire [TAG_WIDTH-1:0]  cdb1_tag,
    input  wire                  cdb1_valid,
    input  wire [31:0]           cdb1_data,

    input  wire [TAG_WIDTH-1:0]  cdb2_tag,
    input  wire                  cdb2_valid,
    input  wire [31:0]           cdb2_data,

    input  wire [TAG_WIDTH-1:0]  cdb3_tag,
    input  wire                  cdb3_valid,
    input  wire [31:0]           cdb3_data,

    // -------------------------------------------------------------------------
    // PRF read request
    // -------------------------------------------------------------------------
    output wire [TAG_WIDTH-1:0]  prf_rs1_tag,
    output wire [TAG_WIDTH-1:0]  prf_rs2_tag,
    output wire [TAG_WIDTH-1:0]  prf_rs3_tag,
    input  wire [31:0]           prf_rs1_data,
    input  wire [31:0]           prf_rs2_data,
    input  wire [31:0]           prf_rs3_data,

    // -------------------------------------------------------------------------
    // Issue output → FPU EU
    // -------------------------------------------------------------------------
    output reg                   issue_valid,
    output reg  [TAG_WIDTH-1:0]  issue_prd,
    output reg  [ROB_IDX-1:0]   issue_rob_idx,
    output reg  [31:0]           issue_rs1_val,
    output reg  [31:0]           issue_rs2_val,
    output reg  [31:0]           issue_rs3_val,
    output reg  [4:0]            issue_fpu_op,
    output reg                   issue_fp_rd,
    output reg                   issue_fp_rs1,
    output reg                   issue_fp_rs2
);

    // =========================================================================
    // Storage
    // =========================================================================
    reg                  rs_valid    [0:NUM_RS-1];
    reg [TAG_WIDTH-1:0]  rs_prd      [0:NUM_RS-1];
    reg [TAG_WIDTH-1:0]  rs_prs1     [0:NUM_RS-1];
    reg [TAG_WIDTH-1:0]  rs_prs2     [0:NUM_RS-1];
    reg [TAG_WIDTH-1:0]  rs_prs3     [0:NUM_RS-1];
    reg                  rs_prs1_rdy [0:NUM_RS-1];
    reg                  rs_prs2_rdy [0:NUM_RS-1];
    reg                  rs_prs3_rdy [0:NUM_RS-1];
    reg [31:0]           rs_rs1_val  [0:NUM_RS-1];
    reg [31:0]           rs_rs2_val  [0:NUM_RS-1];
    reg [31:0]           rs_rs3_val  [0:NUM_RS-1];
    reg [4:0]            rs_fpu_op   [0:NUM_RS-1];
    reg [ROB_IDX-1:0]   rs_rob_idx  [0:NUM_RS-1];
    reg                  rs_fp_rd    [0:NUM_RS-1];
    reg                  rs_fp_rs1   [0:NUM_RS-1];
    reg                  rs_fp_rs2   [0:NUM_RS-1];
    reg                  rs_age      [0:NUM_RS-1];

    // =========================================================================
    // Issue selection (oldest-first, rs1+rs2+rs3 tất cả ready)  ← TRƯỚC free_slot
    // [FIX-AGE-TIE] Khi age bit bằng nhau (do bị overwrite bởi lần write sau),
    // dùng rob_idx nhỏ hơn làm tiebreaker (older ROB entry = smaller idx).
    // =========================================================================
    integer si;
    reg [$clog2(NUM_RS)-1:0] issue_slot;
    reg found_issue;
    always @(*) begin
        issue_slot  = 0;
        found_issue = 1'b0;
        for (si = 0; si < NUM_RS; si = si + 1) begin
            if (rs_valid[si] && rs_prs1_rdy[si] && rs_prs2_rdy[si] && rs_prs3_rdy[si]) begin
                if (!found_issue) begin
                    issue_slot  = si[$clog2(NUM_RS)-1:0];
                    found_issue = 1'b1;
                end else begin
                    // age=1 beats age=0 (older wins)
                    // tiebreak: smaller rob_idx = older = wins
                    if (rs_age[si] > rs_age[issue_slot] ||
                        (rs_age[si] == rs_age[issue_slot] &&
                         rs_rob_idx[si] < rs_rob_idx[issue_slot]))
                    begin
                        issue_slot = si[$clog2(NUM_RS)-1:0];
                    end
                end
            end
        end
    end

    // =========================================================================
    // Free slot
    // [FIX-IQ-CONFLICT] skip issue_slot khi found_issue=1
    // =========================================================================
    integer fi;
    reg [$clog2(NUM_RS)-1:0] free_slot;
    reg found_free;
    always @(*) begin
        free_slot  = 0;
        found_free = 1'b0;
        for (fi = NUM_RS-1; fi >= 0; fi = fi - 1)
            if (!rs_valid[fi] && !(found_issue && fi[$clog2(NUM_RS)-1:0] == issue_slot)) begin
                free_slot = fi[$clog2(NUM_RS)-1:0];
                found_free = 1'b1;
            end
    end
    assign full = !found_free;

    assign prf_rs1_tag = rs_prs1[issue_slot];
    assign prf_rs2_tag = rs_prs2[issue_slot];
    assign prf_rs3_tag = rs_prs3[issue_slot];

    // =========================================================================
    // Main
    // =========================================================================
    integer i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            issue_valid <= 1'b0;
            for (i = 0; i < NUM_RS; i = i + 1) begin
                rs_valid[i] <= 1'b0;
                rs_age[i]   <= 1'b0;
            end
        end else if (flush) begin
            issue_valid <= 1'b0;
            for (i = 0; i < NUM_RS; i = i + 1) begin
                rs_valid[i] <= 1'b0;
                rs_age[i]   <= 1'b0;
            end
        end else begin
            issue_valid <= 1'b0;

            // ------------------------------------------------------------------
            // 1. CDB Snoop (rs1 + rs2 + rs3)
            // ------------------------------------------------------------------
            for (i = 0; i < NUM_RS; i = i + 1) begin
                if (rs_valid[i]) begin
                    if (cdb0_valid) begin
                        if (!rs_prs1_rdy[i] && rs_prs1[i] == cdb0_tag) begin rs_prs1_rdy[i] <= 1'b1; rs_rs1_val[i] <= cdb0_data; end
                        if (!rs_prs2_rdy[i] && rs_prs2[i] == cdb0_tag) begin rs_prs2_rdy[i] <= 1'b1; rs_rs2_val[i] <= cdb0_data; end
                        if (!rs_prs3_rdy[i] && rs_prs3[i] == cdb0_tag) begin rs_prs3_rdy[i] <= 1'b1; rs_rs3_val[i] <= cdb0_data; end
                    end
                    if (cdb1_valid) begin
                        if (!rs_prs1_rdy[i] && rs_prs1[i] == cdb1_tag) begin rs_prs1_rdy[i] <= 1'b1; rs_rs1_val[i] <= cdb1_data; end
                        if (!rs_prs2_rdy[i] && rs_prs2[i] == cdb1_tag) begin rs_prs2_rdy[i] <= 1'b1; rs_rs2_val[i] <= cdb1_data; end
                        if (!rs_prs3_rdy[i] && rs_prs3[i] == cdb1_tag) begin rs_prs3_rdy[i] <= 1'b1; rs_rs3_val[i] <= cdb1_data; end
                    end
                    if (cdb2_valid) begin
                        if (!rs_prs1_rdy[i] && rs_prs1[i] == cdb2_tag) begin rs_prs1_rdy[i] <= 1'b1; rs_rs1_val[i] <= cdb2_data; end
                        if (!rs_prs2_rdy[i] && rs_prs2[i] == cdb2_tag) begin rs_prs2_rdy[i] <= 1'b1; rs_rs2_val[i] <= cdb2_data; end
                        if (!rs_prs3_rdy[i] && rs_prs3[i] == cdb2_tag) begin rs_prs3_rdy[i] <= 1'b1; rs_rs3_val[i] <= cdb2_data; end
                    end
                    if (cdb3_valid) begin
                        if (!rs_prs1_rdy[i] && rs_prs1[i] == cdb3_tag) begin rs_prs1_rdy[i] <= 1'b1; rs_rs1_val[i] <= cdb3_data; end
                        if (!rs_prs2_rdy[i] && rs_prs2[i] == cdb3_tag) begin rs_prs2_rdy[i] <= 1'b1; rs_rs2_val[i] <= cdb3_data; end
                        if (!rs_prs3_rdy[i] && rs_prs3[i] == cdb3_tag) begin rs_prs3_rdy[i] <= 1'b1; rs_rs3_val[i] <= cdb3_data; end
                    end
                end
            end

            // ------------------------------------------------------------------
            // 2. Write
            // ------------------------------------------------------------------
            if (wr_en && !full) begin
                rs_valid[free_slot]     <= 1'b1;
                rs_prd[free_slot]       <= wr_prd;
                rs_prs1[free_slot]      <= wr_prs1;
                rs_prs2[free_slot]      <= wr_prs2;
                rs_prs3[free_slot]      <= wr_prs3;
                // [FIX-CDB-WRITE-BYPASS] Check CDB cùng cycle khi ghi entry mới
                rs_prs1_rdy[free_slot]  <= wr_prs1_ready
                    || (cdb0_valid && cdb0_tag==wr_prs1)
                    || (cdb1_valid && cdb1_tag==wr_prs1)
                    || (cdb2_valid && cdb2_tag==wr_prs1)
                    || (cdb3_valid && cdb3_tag==wr_prs1);
                rs_prs2_rdy[free_slot]  <= wr_prs2_ready
                    || (cdb0_valid && cdb0_tag==wr_prs2)
                    || (cdb1_valid && cdb1_tag==wr_prs2)
                    || (cdb2_valid && cdb2_tag==wr_prs2)
                    || (cdb3_valid && cdb3_tag==wr_prs2);
                rs_prs3_rdy[free_slot]  <= wr_prs3_ready
                    || (cdb0_valid && cdb0_tag==wr_prs3)
                    || (cdb1_valid && cdb1_tag==wr_prs3)
                    || (cdb2_valid && cdb2_tag==wr_prs3)
                    || (cdb3_valid && cdb3_tag==wr_prs3);
                rs_rs1_val[free_slot]   <= (cdb3_valid && cdb3_tag==wr_prs1) ? cdb3_data :
                                           (cdb2_valid && cdb2_tag==wr_prs1) ? cdb2_data :
                                           (cdb1_valid && cdb1_tag==wr_prs1) ? cdb1_data :
                                           (cdb0_valid && cdb0_tag==wr_prs1) ? cdb0_data :
                                           wr_prs1_ready ? wr_prs1_data : 32'd0;
                rs_rs2_val[free_slot]   <= (cdb3_valid && cdb3_tag==wr_prs2) ? cdb3_data :
                                           (cdb2_valid && cdb2_tag==wr_prs2) ? cdb2_data :
                                           (cdb1_valid && cdb1_tag==wr_prs2) ? cdb1_data :
                                           (cdb0_valid && cdb0_tag==wr_prs2) ? cdb0_data :
                                           wr_prs2_ready ? wr_prs2_data : 32'd0;
                rs_rs3_val[free_slot]   <= (cdb3_valid && cdb3_tag==wr_prs3) ? cdb3_data :
                                           (cdb2_valid && cdb2_tag==wr_prs3) ? cdb2_data :
                                           (cdb1_valid && cdb1_tag==wr_prs3) ? cdb1_data :
                                           (cdb0_valid && cdb0_tag==wr_prs3) ? cdb0_data :
                                           wr_prs3_ready ? wr_prs3_data : 32'd0;
                rs_fpu_op[free_slot]    <= wr_fpu_op;
                rs_rob_idx[free_slot]   <= wr_rob_idx;
                rs_fp_rd[free_slot]     <= wr_fp_rd;
                rs_fp_rs1[free_slot]    <= wr_fp_rs1;
                rs_fp_rs2[free_slot]    <= wr_fp_rs2;
                rs_age[free_slot]       <= 1'b0;
                for (i = 0; i < NUM_RS; i = i + 1)
                    if (rs_valid[i] && i != free_slot) rs_age[i] <= 1'b1;
            end

            // ------------------------------------------------------------------
            // 3. Issue
            // ------------------------------------------------------------------
            if (found_issue) begin
                issue_valid   <= 1'b1;
                issue_prd     <= rs_prd[issue_slot];
                issue_rob_idx <= rs_rob_idx[issue_slot];
                issue_rs1_val <= rs_prs1_rdy[issue_slot] ? rs_rs1_val[issue_slot] : prf_rs1_data;
                issue_rs2_val <= rs_prs2_rdy[issue_slot] ? rs_rs2_val[issue_slot] : prf_rs2_data;
                issue_rs3_val <= rs_prs3_rdy[issue_slot] ? rs_rs3_val[issue_slot] : prf_rs3_data;
                issue_fpu_op  <= rs_fpu_op[issue_slot];
                issue_fp_rd   <= rs_fp_rd[issue_slot];
                issue_fp_rs1  <= rs_fp_rs1[issue_slot];
                issue_fp_rs2  <= rs_fp_rs2[issue_slot];
                rs_valid[issue_slot] <= 1'b0;
            end
        end
    end

endmodule