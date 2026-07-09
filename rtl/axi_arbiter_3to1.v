`timescale 1ns / 1ps

module axi_arbiter_3to1 #(
    parameter DATA_WIDTH = 256,
    parameter ADDR_WIDTH = 28,
    parameter ID_WIDTH   = 4
)(  
    input wire clk,
    input wire rst_n,

    // Master 0 (M0): RISC-V 软核 (低优先级)
    input  wire [ADDR_WIDTH-1:0] m0_awaddr, input wire [3:0] m0_awlen, input wire [ID_WIDTH-1:0] m0_awid, input wire m0_awvalid, output wire m0_awready,
    input  wire [DATA_WIDTH-1:0] m0_wdata, input wire [DATA_WIDTH/8-1:0] m0_wstrb, input wire m0_wlast, input wire m0_wvalid, output wire m0_wready,
    output wire [1:0] m0_bresp, output wire [ID_WIDTH-1:0] m0_bid, output wire m0_bvalid, input wire m0_bready,
    input  wire [ADDR_WIDTH-1:0] m0_araddr, input wire [3:0] m0_arlen, input wire [ID_WIDTH-1:0] m0_arid, input wire m0_arvalid, output wire m0_arready,
    output wire [DATA_WIDTH-1:0] m0_rdata, output wire m0_rlast, output wire [ID_WIDTH-1:0] m0_rid, output wire m0_rvalid, input wire m0_rready,

    // Master 1 (M1): 原图读写 (fram_buf) (最高优先级)
    input  wire [ADDR_WIDTH-1:0] m1_awaddr, input wire [3:0] m1_awlen, input wire [ID_WIDTH-1:0] m1_awid, input wire m1_awvalid, output wire m1_awready,
    input  wire [DATA_WIDTH-1:0] m1_wdata, input wire [DATA_WIDTH/8-1:0] m1_wstrb, input wire m1_wlast, input wire m1_wvalid, output wire m1_wready,
    output wire [1:0] m1_bresp, output wire [ID_WIDTH-1:0] m1_bid, output wire m1_bvalid, input wire m1_bready,
    input  wire [ADDR_WIDTH-1:0] m1_araddr, input wire [3:0] m1_arlen, input wire [ID_WIDTH-1:0] m1_arid, input wire m1_arvalid, output wire m1_arready,
    output wire [DATA_WIDTH-1:0] m1_rdata, output wire m1_rlast, output wire [ID_WIDTH-1:0] m1_rid, output wire m1_rvalid, input wire m1_rready,
 
    // Master 2 (M2): 二值化写回 (中优先级)
    input  wire [ADDR_WIDTH-1:0] m2_awaddr, input wire [3:0] m2_awlen, input wire [ID_WIDTH-1:0] m2_awid, input wire m2_awvalid, output wire m2_awready,
    input  wire [DATA_WIDTH-1:0] m2_wdata, input wire [DATA_WIDTH/8-1:0] m2_wstrb, input wire m2_wlast, input wire m2_wvalid, output wire m2_wready,
    output wire [1:0] m2_bresp, output wire [ID_WIDTH-1:0] m2_bid, output wire m2_bvalid, input wire m2_bready,
    input  wire [ADDR_WIDTH-1:0] m2_araddr, input wire [3:0] m2_arlen, input wire [ID_WIDTH-1:0] m2_arid, input wire m2_arvalid, output wire m2_arready,
    output wire [DATA_WIDTH-1:0] m2_rdata, output wire m2_rlast, output wire [ID_WIDTH-1:0] m2_rid, output wire m2_rvalid, input wire m2_rready,

    // Slave 0 (S0): DDR IP
    // s_wlast 是 output
    output wire [ADDR_WIDTH-1:0] s_awaddr, output wire [3:0] s_awlen, output wire [ID_WIDTH-1:0] s_awid, output wire s_awvalid, input wire s_awready,
    output wire [DATA_WIDTH-1:0] s_wdata, output wire [DATA_WIDTH/8-1:0] s_wstrb, output wire s_wlast, output wire s_wvalid, input wire s_wready,
    input  wire [1:0] s_bresp, input wire [ID_WIDTH-1:0] s_bid, input wire s_bvalid, output wire s_bready,
    output wire [ADDR_WIDTH-1:0] s_araddr, output wire [3:0] s_arlen, output wire [ID_WIDTH-1:0] s_arid, output wire s_arvalid, input wire s_arready,
    input  wire [DATA_WIDTH-1:0] s_rdata, input wire s_rlast, input wire [ID_WIDTH-1:0] s_rid, input wire s_rvalid, output wire s_rready
);

    // ==========================================================
    // 1. 读通道严格仲裁 (AR 和 R)
    // ==========================================================
    reg r_active;
    reg [1:0] r_grant;
    reg ar_done;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r_active <= 1'b0;
            r_grant  <= 2'd0;
            ar_done  <= 1'b0;
        end else begin
            if (!r_active) begin
                if (m1_arvalid)      begin r_grant <= 2'd1; r_active <= 1'b1; ar_done <= 1'b0; end
                else if (m0_arvalid) begin r_grant <= 2'd0; r_active <= 1'b1; ar_done <= 1'b0; end
                else if (m2_arvalid) begin r_grant <= 2'd2; r_active <= 1'b1; ar_done <= 1'b0; end
            end else begin
                if (s_arvalid && s_arready) ar_done <= 1'b1; 
                if (s_rvalid && s_rready && s_rlast) r_active <= 1'b0; 
            end
        end
    end

    assign s_arvalid  = (r_active && !ar_done) ? ((r_grant == 2'd1) ? m1_arvalid : (r_grant == 2'd0) ? m0_arvalid : m2_arvalid) : 1'b0;
    assign s_araddr   = (r_grant == 2'd1) ? m1_araddr  : (r_grant == 2'd0) ? m0_araddr  : m2_araddr;
    assign s_arlen    = (r_grant == 2'd1) ? m1_arlen   : (r_grant == 2'd0) ? m0_arlen   : m2_arlen;
    assign s_arid     = (r_grant == 2'd1) ? m1_arid    : (r_grant == 2'd0) ? m0_arid    : m2_arid;

    assign m0_arready = (r_active && !ar_done && r_grant == 2'd0) ? s_arready : 1'b0;
    assign m1_arready = (r_active && !ar_done && r_grant == 2'd1) ? s_arready : 1'b0;
    assign m2_arready = (r_active && !ar_done && r_grant == 2'd2) ? s_arready : 1'b0;

    assign s_rready   = r_active ? ((r_grant == 2'd1) ? m1_rready : (r_grant == 2'd0) ? m0_rready : m2_rready) : 1'b1;
    assign m0_rvalid  = (r_active && r_grant == 2'd0) ? s_rvalid : 1'b0;
    assign m1_rvalid  = (r_active && r_grant == 2'd1) ? s_rvalid : 1'b0;
    assign m2_rvalid  = (r_active && r_grant == 2'd2) ? s_rvalid : 1'b0;

    assign m0_rdata = s_rdata; assign m0_rlast = s_rlast; assign m0_rid = s_rid;
    assign m1_rdata = s_rdata; assign m1_rlast = s_rlast; assign m1_rid = s_rid;
    assign m2_rdata = s_rdata; assign m2_rlast = s_rlast; assign m2_rid = s_rid;

    // ==========================================================
// 2. 写通道严格仲裁 (AW, W, B)
// ==========================================================
    reg w_active;
    reg [1:0] w_grant;
    reg aw_done;
    reg w_done;

    // B通道响应追踪队列，深度为8的环形队列，支持总线不间断交替写入
    reg [1:0] b_grant_queue [0:7];
    reg [2:0] b_push_ptr;
    reg [2:0] b_pop_ptr;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            w_active   <= 1'b0;
            w_grant    <= 2'd0;
            aw_done    <= 1'b0;
            w_done     <= 1'b0;
            b_push_ptr <= 3'd0;
            b_pop_ptr  <= 3'd0;
        end else begin
            // 追踪每次 AW 握手，把发起者的 ID 推入队列
            if (s_awvalid && s_awready) begin
                b_grant_queue[b_push_ptr] <= w_grant;
                b_push_ptr <= b_push_ptr + 1'b1;
            end
            
            // 追踪每次 B 握手，从队列弹出，结束一次追踪
            if (s_bvalid && s_bready) begin
                b_pop_ptr <= b_pop_ptr + 1'b1;
            end

            if (!w_active) begin
                if (m1_awvalid)      begin w_grant <= 2'd1; w_active <= 1'b1; aw_done <= 1'b0; w_done <= 1'b0; end
                else if (m2_awvalid) begin w_grant <= 2'd2; w_active <= 1'b1; aw_done <= 1'b0; w_done <= 1'b0; end
                else if (m0_awvalid) begin w_grant <= 2'd0; w_active <= 1'b1; aw_done <= 1'b0; w_done <= 1'b0; end
            end else begin
                if (s_awvalid && s_awready) aw_done <= 1'b1;
                
                // 写完最后一个数据立刻释放总线，不等 BVALID！
                if (s_wvalid && s_wready && s_wlast) begin
                    w_done   <= 1'b1;
                    w_active <= 1'b0; 
                end
            end
        end
    end

    // 当前应该把 DDR 的 B 响应发给谁？看队列头部
    wire [1:0] current_b_grant = b_grant_queue[b_pop_ptr];
    wire has_pending_b = (b_push_ptr != b_pop_ptr); // 队列里是否有未处理的响应

    assign s_awvalid  = (w_active && !aw_done) ? ((w_grant == 2'd1) ? m1_awvalid : (w_grant == 2'd0) ? m0_awvalid : m2_awvalid) : 1'b0;
    assign s_awaddr   = (w_grant == 2'd1) ? m1_awaddr  : (w_grant == 2'd0) ? m0_awaddr  : m2_awaddr;
    assign s_awlen    = (w_grant == 2'd1) ? m1_awlen   : (w_grant == 2'd0) ? m0_awlen   : m2_awlen;
    assign s_awid     = (w_grant == 2'd1) ? m1_awid    : (w_grant == 2'd0) ? m0_awid    : m2_awid;
    
    assign m0_awready = (w_active && !aw_done && w_grant == 2'd0) ? s_awready : 1'b0;
    assign m1_awready = (w_active && !aw_done && w_grant == 2'd1) ? s_awready : 1'b0;
    assign m2_awready = (w_active && !aw_done && w_grant == 2'd2) ? s_awready : 1'b0;
    
    assign s_wvalid   = (w_active && !w_done) ? ((w_grant == 2'd1) ? m1_wvalid : (w_grant == 2'd0) ? m0_wvalid : m2_wvalid) : 1'b0;
    assign s_wdata    = (w_grant == 2'd1) ? m1_wdata   : (w_grant == 2'd0) ? m0_wdata   : m2_wdata;
    assign s_wstrb    = (w_grant == 2'd1) ? m1_wstrb   : (w_grant == 2'd0) ? m0_wstrb   : m2_wstrb;
    
    // wlast同样由当前授权的 Master 驱动
    assign s_wlast    = (w_grant == 2'd1) ? m1_wlast   : (w_grant == 2'd0) ? m0_wlast   : m2_wlast;
    
    assign m0_wready  = (w_active && !w_done && w_grant == 2'd0) ? s_wready : 1'b0;
    assign m1_wready  = (w_active && !w_done && w_grant == 2'd1) ? s_wready : 1'b0;
    assign m2_wready  = (w_active && !w_done && w_grant == 2'd2) ? s_wready : 1'b0;
    
    //  响应通道按队列精确分发
    assign s_bready   = 1'b1; // 仲裁器永远准备好接收响应
    
    assign m0_bvalid  = (s_bvalid && has_pending_b && current_b_grant == 2'd0) ? 1'b1 : 1'b0;
    assign m1_bvalid  = (s_bvalid && has_pending_b && current_b_grant == 2'd1) ? 1'b1 : 1'b0;
    assign m2_bvalid  = (s_bvalid && has_pending_b && current_b_grant == 2'd2) ? 1'b1 : 1'b0;

    assign m0_bresp = s_bresp; assign m0_bid = s_bid;
    assign m1_bresp = s_bresp; assign m1_bid = s_bid;
    assign m2_bresp = s_bresp; assign m2_bid = s_bid;

endmodule