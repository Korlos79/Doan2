module ROB #(
    parameter ROB_ENTRIES = 16,
    parameter TAG_WIDTH = 4   // log2(16) = 4 bit
)(
    input wire clk,
    input wire rst_n,

    // 1. CỔNG ISSUE
    input  wire                 issue_valid,     
    input  wire [4:0]           issue_rd,        
    input  wire                 issue_reg_write, 
    input  wire                 issue_is_fp,     
    input  wire                 issue_is_branch, 
    output wire                 rob_full,        
    output wire [TAG_WIDTH-1:0] allocate_tag,    

    // 2. CỔNG CDB SNOOP
    input  wire                 cdb_valid,       
    input  wire [TAG_WIDTH-1:0] cdb_tag,         
    input  wire [31:0]          cdb_result,      
    input  wire                 cdb_branch_taken,
    input  wire [31:0]          cdb_branch_target,

    // 3. CỔNG COMMIT
    output reg                  commit_valid,    
    output reg  [4:0]           commit_rd,       
    output reg  [31:0]          commit_result,   
    output reg  [TAG_WIDTH-1:0] commit_tag,      
    output reg                  commit_int_we,   
    output reg                  commit_float_we, 

    // 4. CỔNG FLUSH
    output reg                  rob_flush,       
    output reg  [31:0]          rob_flush_pc     
);

    // --- CẤU TRÚC BỘ NHỚ ROB ---
    reg [4:0]  rob_dest          [ROB_ENTRIES-1:0]; 
    reg [31:0] rob_value         [ROB_ENTRIES-1:0]; 
    reg        rob_ready         [ROB_ENTRIES-1:0]; 
    reg        rob_reg_write     [ROB_ENTRIES-1:0]; 
    reg        rob_is_fp         [ROB_ENTRIES-1:0]; 
    reg        rob_is_branch     [ROB_ENTRIES-1:0]; 
    reg        rob_branch_taken  [ROB_ENTRIES-1:0]; 
    reg [31:0] rob_branch_target [ROB_ENTRIES-1:0]; 

    // --- CON TRỎ FIFO ---
    reg [TAG_WIDTH-1:0] head;  
    reg [TAG_WIDTH-1:0] tail;  
    reg [TAG_WIDTH:0]   count; 

    assign rob_full = (count == ROB_ENTRIES);
    assign allocate_tag = tail; 

    wire do_issue  = issue_valid && !rob_full;
    wire do_commit = (count > 0) && rob_ready[head];
    
    // Tạm thời giữ logic: Nếu là Branch và nó NHẢY thì Flush
    wire is_flush  = do_commit && rob_is_branch[head] && rob_branch_taken[head];

    integer i;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            head  <= 0;
            tail  <= 0;
            count <= 0;
            
            commit_valid    <= 0;
            commit_int_we   <= 0;
            commit_float_we <= 0;
            
            rob_flush       <= 0;
            rob_flush_pc    <= 0;
            
            for (i=0; i<ROB_ENTRIES; i=i+1) begin
                rob_ready[i] <= 0;
            end
        end else begin
            
            // Mặc định hạ cờ commit và flush (chỉ kích hoạt pulse 1 chu kỳ)
            commit_valid <= 1'b0;
            rob_flush    <= 1'b0;

            if (is_flush) begin
                // A. XẢ PIPELINE (FLUSH)
                commit_valid    <= 1'b1;
                commit_rd       <= rob_dest[head];
                commit_result   <= rob_value[head];
                commit_tag      <= head;
                commit_int_we   <= rob_reg_write[head] && !rob_is_fp[head];
                commit_float_we <= rob_reg_write[head] && rob_is_fp[head];

                rob_flush       <= 1'b1;
                rob_flush_pc    <= rob_branch_target[head];

                head  <= 0;
                tail  <= 0;
                count <= 0;
                for (i=0; i<ROB_ENTRIES; i=i+1) begin
                    rob_ready[i] <= 1'b0;
                end
            end 
            else begin
                // B. COMMIT BÌNH THƯỜNG
                if (do_commit) begin
                    commit_valid    <= 1'b1;
                    commit_rd       <= rob_dest[head];
                    commit_result   <= rob_value[head];
                    commit_tag      <= head;
                    
                    commit_int_we   <= rob_reg_write[head] && !rob_is_fp[head];
                    commit_float_we <= rob_reg_write[head] && rob_is_fp[head];
                    
                    rob_ready[head] <= 1'b0; 
                    head            <= head + 1;
                end

                // C. CDB SNOOP (Lắng nghe Bus)
                if (cdb_valid) begin
                    rob_ready[cdb_tag]         <= 1'b1;        
                    rob_value[cdb_tag]         <= cdb_result;
                    rob_branch_taken[cdb_tag]  <= cdb_branch_taken;
                    rob_branch_target[cdb_tag] <= cdb_branch_target;
                end

                // D. ISSUE (Nạp lệnh mới)
                // Lưu ý: Khối Issue được đặt DƯỚI khối CDB. 
                // Nếu hiếm hoi cdb_tag trùng với tail, lệnh gán rob_ready[tail] <= 0 
                // sẽ đè lên cdb_valid, đảm bảo Slot mới cất lệnh luôn ở trạng thái NOT READY.
                if (do_issue) begin
                    rob_dest[tail]         <= issue_rd;
                    rob_reg_write[tail]    <= issue_reg_write; 
                    rob_is_fp[tail]        <= issue_is_fp;     
                    
                    rob_is_branch[tail]    <= issue_is_branch; 
                    rob_branch_taken[tail] <= 1'b0;
                    
                    rob_ready[tail]        <= 1'b0;              
                    tail                   <= tail + 1;
                end

                // E. QUẢN LÝ BIẾN ĐẾM COUNT
                if (do_issue && !do_commit)
                    count <= count + 1;
                else if (!do_issue && do_commit)
                    count <= count - 1;
            end
        end
    end
endmodule