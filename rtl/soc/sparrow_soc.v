`include "D:\PDS\test\Sparrow_RISC-V\rtl\defines.v"

module sparrow_soc ( 
    // 公共接口
    input  wire clk,         // 时钟输入 ( SoC主时钟 )
    input  wire hard_rst_n,  // 来自外部的复位信号，低电平有效
    output wire core_active, // 处理器活动指示，以肉眼可见速度翻转

    // JTAG 接口
    input  wire JTAG_TMS,
    input  wire JTAG_TDI, 
    output wire JTAG_TDO,
    input  wire JTAG_TCK,    // 即使没有JTAG，也保留这个接口，使得约束可以通用

    // SD、TF卡接口 
    output wire       sd_clk,   
    inout  wire       sd_cmd,
    input  wire [3:0] sd_dat, // 需要上拉

    // FPIOA
    inout  wire [`FPIOA_PORT_NUM-1:0] fpioa, // 处理器IO接口

    // LED 调试接口
    output wire         led4, // 写入成功指示
    output wire         led5, // 读取成功指示

    // =========================================================================
    // 新增：对接 DDR IP 的跨时钟域信号与 AXI Master 接口 (256-bit)
    // =========================================================================
    input  wire          ddr_clk,       // DDR 侧工作时钟 (通常为高频时钟如 125MHz)
    input  wire          ddr_init_done, // DDR 初始化完成标志，用作复位信号


    // AXI 读地址通道 (AR)
    output wire [31:0]   axi_araddr,
    output wire [3:0]    axi_arlen,     // 对应例程中的 axi_arlen
    output wire [3:0]    axi_aruser_id, // 新增：读 ID
    output wire          axi_aruser_ap, // 新增：读自动预充电
    output wire          axi_arvalid,
    input  wire          axi_arready,


    // AXI 读数据通道 (R)
    input  wire [255:0]  axi_rdata,
    input  wire [3:0]    axi_rid,       // 新增：读返回 ID
    input  wire          axi_rlast,     // 新增：读返回 Last
    input  wire          axi_rvalid,
    output wire          axi_rready,

    // AXI 写地址通道 (AW)
    output wire [31:0]   axi_awaddr,
    output wire [3:0]    axi_awlen,     // 新增：写长度
    output wire [3:0]    axi_awuser_id, // 新增：写 ID
    output wire          axi_awuser_ap, // 新增：写自动预充电
    output wire          axi_awvalid,
    input  wire          axi_awready,

    // AXI 写数据通道 (W)
    output wire [255:0]  axi_wdata,
    output wire [31:0]   axi_wstrb,
    output wire [3:0]    axi_wusero_id, // 新增：写数据 ID
    output wire          axi_wusero_last,// 新增：写数据 Last 标志
    output wire          axi_wvalid,
    input  wire          axi_wready,

    // AXI 写响应通道 (B)
    input  wire          axi_bvalid,
    output wire          axi_bready ,

    // 新增：帧冻结控制
    output wire frame_freeze    // 帧冻结控制信号
);



//*********************************
//           定义总线线网
//
//m0
wire                 jtag_icb_cmd_valid;
wire                 jtag_icb_cmd_ready;
wire [`MemAddrBus]   jtag_icb_icb_cmd_addr ;
wire                 jtag_icb_cmd_read ;
wire [`MemBus]       jtag_icb_cmd_wdata;
wire [3:0]           jtag_icb_cmd_wmask;
wire                 jtag_icb_rsp_valid;
wire                 jtag_icb_rsp_ready;
wire                 jtag_icb_rsp_err  ;
wire [`MemBus]       jtag_icb_rsp_rdata;
//m1
wire                 core_icb_cmd_valid;
wire                 core_icb_cmd_ready;
wire [`MemAddrBus]   core_icb_cmd_addr ;
wire                 core_icb_cmd_read ;
wire [`MemBus]       core_icb_cmd_wdata;
wire [3:0]           core_icb_cmd_wmask;
wire                 core_icb_rsp_valid;
wire                 core_icb_rsp_ready;
wire                 core_icb_rsp_err  ;
wire [`MemBus]       core_icb_rsp_rdata;
//s0
wire                 iram_icb_cmd_valid;
wire                 iram_icb_cmd_ready;
wire [`MemAddrBus]   iram_icb_cmd_addr ;
wire                 iram_icb_cmd_read ;
wire [`MemBus]       iram_icb_cmd_wdata;
wire [3:0]           iram_icb_cmd_wmask;
wire                 iram_icb_rsp_valid;
wire                 iram_icb_rsp_ready;
wire                 iram_icb_rsp_err  ;
wire [`MemBus]       iram_icb_rsp_rdata;
//s1
wire                 sram_icb_cmd_valid;
wire                 sram_icb_cmd_ready;
wire [`MemAddrBus]   sram_icb_cmd_addr ;
wire                 sram_icb_cmd_read ;
wire [`MemBus]       sram_icb_cmd_wdata;
wire [3:0]           sram_icb_cmd_wmask;
wire                 sram_icb_rsp_valid;
wire                 sram_icb_rsp_ready;
wire                 sram_icb_rsp_err  ;
wire [`MemBus]       sram_icb_rsp_rdata;
//s2
wire                 sysp_icb_cmd_valid;
wire                 sysp_icb_cmd_ready;
wire [`MemAddrBus]   sysp_icb_cmd_addr ;
wire                 sysp_icb_cmd_read ;
wire [`MemBus]       sysp_icb_cmd_wdata;
wire [3:0]           sysp_icb_cmd_wmask;
wire                 sysp_icb_rsp_valid;
wire                 sysp_icb_rsp_ready;
wire                 sysp_icb_rsp_err  ;
wire [`MemBus]       sysp_icb_rsp_rdata;
//s3
wire                 plic_icb_cmd_valid;
wire                 plic_icb_cmd_ready;
wire [`MemAddrBus]   plic_icb_cmd_addr ;
wire                 plic_icb_cmd_read ;
wire [`MemBus]       plic_icb_cmd_wdata;
wire [3:0]           plic_icb_cmd_wmask;
wire                 plic_icb_rsp_valid;
wire                 plic_icb_rsp_ready;
wire                 plic_icb_rsp_err  ;
wire [`MemBus]       plic_icb_rsp_rdata;
//s4
wire                 sdrd_icb_cmd_valid;
wire                 sdrd_icb_cmd_ready;
wire [`MemAddrBus]   sdrd_icb_cmd_addr ;
wire                 sdrd_icb_cmd_read ;
wire [`MemBus]       sdrd_icb_cmd_wdata;
wire [3:0]           sdrd_icb_cmd_wmask;
wire                 sdrd_icb_rsp_valid;
wire                 sdrd_icb_rsp_ready;
wire                 sdrd_icb_rsp_err  ;
wire [`MemBus]       sdrd_icb_rsp_rdata;



//其他信号
wire halt_req;
wire jtag_rst_en;
wire [4:0]core_ex_trap_id;//中断源ID
wire [3:0]irq_fpioa_eli;
wire [15:0]plic_irq_port;
wire inst_req;//取指请求
wire [`InstAddrBus] inst_addr;//取指地址
wire inst_ack;//取指响应
wire [`InstBus] inst_data;//取指数据

//
//           定义线网
//*********************************

//小麻雀内核
core inst_core
(
    .clk              (clk),
    .rst_n            (rst_n),
    .halt_req_i       (halt_req),
    .hx_valid         (hx_valid),
    .soft_rst         (soft_rst_en),

//外部中断
    .core_ex_trap_valid_i   (core_ex_trap_valid),
    .core_ex_trap_id_i      (core_ex_trap_id),
    .core_ex_trap_ready_o   (core_ex_trap_ready),
    .core_ex_trap_cplet_o   (),
    .core_ex_trap_cplet_id_o(),

//m1 内核
    .core_icb_cmd_valid (core_icb_cmd_valid),
    .core_icb_cmd_ready (core_icb_cmd_ready),
    .core_icb_cmd_addr  (core_icb_cmd_addr ),
    .core_icb_cmd_read  (core_icb_cmd_read ),
    .core_icb_cmd_wdata (core_icb_cmd_wdata),
    .core_icb_cmd_wmask (core_icb_cmd_wmask),
    .core_icb_rsp_valid (core_icb_rsp_valid),
    .core_icb_rsp_ready (core_icb_rsp_ready),
    .core_icb_rsp_err   (core_icb_rsp_err  ),
    .core_icb_rsp_rdata (core_icb_rsp_rdata),
    .if_req_o           (inst_req),
    .if_addr_o          (inst_addr), 
    .if_ack_i           (inst_ack),
    .if_data_i          (inst_data)
    /*
//s0 iram指令存储器
    .iram_icb_cmd_valid (iram_icb_cmd_valid),
    .iram_icb_cmd_ready (iram_icb_cmd_ready),
    .iram_icb_cmd_addr  (iram_icb_cmd_addr ),
    .iram_icb_cmd_read  (iram_icb_cmd_read ),
    .iram_icb_cmd_wdata (iram_icb_cmd_wdata),
    .iram_icb_cmd_wmask (iram_icb_cmd_wmask),
    .iram_icb_rsp_valid (iram_icb_rsp_valid),
    .iram_icb_rsp_ready (iram_icb_rsp_ready),
    .iram_icb_rsp_err   (iram_icb_rsp_err  ),
    .iram_icb_rsp_rdata (iram_icb_rsp_rdata)
    */
);

wire JTAG_TCK_in;
// 调用紫光原语，对普通的 JTAG_TCK 输入引脚进行缓冲
GTP_INBUF #(
    .IOSTANDARD("DEFAULT"),
    .TERM_DDR("ON") 
) GTP_INBUF_inst (
    .O(JTAG_TCK_in), // 输出：接入全局时钟网络的优质时钟信号
    .I(JTAG_TCK)     // 输入：来自普通物理 IO 的原始时钟
);
// 同时在约束文件中，需要放宽对该普通管脚上专用时钟路由的限制
//define_attribute {n:JTAG_TCK_in} {PAP_CLOCK_DEDICATED_ROUTE} {false}

`ifdef JTAG_DBG_MODULE
//JTAG模块
jtag_top inst_jtag_top
(
    .clk              (clk),
    .jtag_rst_n       (rst_n),
    .jtag_pin_TCK     (JTAG_TCK),
    .jtag_pin_TMS     (JTAG_TMS),
    .jtag_pin_TDI     (JTAG_TDI),
    .jtag_pin_TDO     (JTAG_TDO),
    .reg_we_o         (),
    .reg_addr_o       (),
    .reg_wdata_o      (),
    .reg_rdata_i      (32'b0),
    //m0 jtag
    .jtag_icb_cmd_valid (jtag_icb_cmd_valid),
    .jtag_icb_cmd_ready (jtag_icb_cmd_ready),
    .jtag_icb_cmd_addr  (jtag_icb_cmd_addr ),
    .jtag_icb_cmd_read  (jtag_icb_cmd_read ),
    .jtag_icb_cmd_wdata (jtag_icb_cmd_wdata),
    .jtag_icb_cmd_wmask (jtag_icb_cmd_wmask),
    .jtag_icb_rsp_valid (jtag_icb_rsp_valid),
    .jtag_icb_rsp_ready (jtag_icb_rsp_ready),
    .jtag_icb_rsp_err   (jtag_icb_rsp_err  ),
    .jtag_icb_rsp_rdata (jtag_icb_rsp_rdata),
    .halt_req_o       (halt_req),
    .reset_req_o      (jtag_rst_en)
);
`else //禁用jtag
    assign halt_req = 1'b0;
    assign jtag_rst_en = 1'b0;
    assign jtag_icb_cmd_valid = 1'b0;
    assign jtag_icb_cmd_addr  = 32'b0;
    assign jtag_icb_cmd_read  = 1'b0;
    assign jtag_icb_cmd_wdata = 32'b0;
    assign jtag_icb_cmd_wmask = 4'b0;
    assign jtag_icb_rsp_ready = 1'b1;
	assign JTAG_TDO = 1'b0;
`endif

//s0 iram外设，指令存储器
iram inst_iram
(
    .clk                (clk),
    .rst_n              (rst_n),
    .inst_addr_i        (inst_addr),//指令地址
    .inst_req_i         (inst_req),//取指请求
    .inst_data_o        (inst_data),//指令
    .inst_ack_o         (inst_ack),//取指响应
    .iram_icb_cmd_valid (iram_icb_cmd_valid),
    .iram_icb_cmd_ready (iram_icb_cmd_ready),
    .iram_icb_cmd_addr  (iram_icb_cmd_addr ),
    .iram_icb_cmd_read  (iram_icb_cmd_read ),
    .iram_icb_cmd_wdata (iram_icb_cmd_wdata),
    .iram_icb_cmd_wmask (iram_icb_cmd_wmask),
    .iram_icb_rsp_valid (iram_icb_rsp_valid),
    .iram_icb_rsp_ready (iram_icb_rsp_ready),
    .iram_icb_rsp_err   (iram_icb_rsp_err  ),
    .iram_icb_rsp_rdata (iram_icb_rsp_rdata)
);

//s1 sram外设
sram inst_sram
(
    .clk              (clk),
    .rst_n            (rst_n),

    .sram_icb_cmd_valid (sram_icb_cmd_valid),
    .sram_icb_cmd_ready (sram_icb_cmd_ready),
    .sram_icb_cmd_addr  (sram_icb_cmd_addr ),
    .sram_icb_cmd_read  (sram_icb_cmd_read ),
    .sram_icb_cmd_wdata (sram_icb_cmd_wdata),
    .sram_icb_cmd_wmask (sram_icb_cmd_wmask),
    .sram_icb_rsp_valid (sram_icb_rsp_valid),
    .sram_icb_rsp_ready (sram_icb_rsp_ready),
    .sram_icb_rsp_err   (sram_icb_rsp_err  ),
    .sram_icb_rsp_rdata (sram_icb_rsp_rdata)
);

//s2 sys_perip系统外设
sys_perip inst_sys_perip
(
    .clk               (clk),
    .rst_n             (rst_n),
    .fpioa             (fpioa),
    .frame_freeze       (frame_freeze),  // 新增连接,帧冻结控制信号
    .irq_fpioa_eli  (irq_fpioa_eli),    //FPIOA端口外部连线中断
    .irq_spi0_end   (irq_spi0_end),           //SPI收发结束中断
    .irq_timer0_of  (irq_timer0_of),      //定时器溢出中断
    .irq_uart0_tx   (irq_uart0_tx),  //uart tx发送完成中断
    .irq_uart0_rx   (irq_uart0_rx),   //uart rx接收数据中断
    .irq_uart1_tx   (irq_uart1_tx),  //uart tx发送完成中断
    .irq_uart1_rx   (irq_uart1_rx),   //uart rx接收数据中断

    .sysp_icb_cmd_valid (sysp_icb_cmd_valid),
    .sysp_icb_cmd_ready (sysp_icb_cmd_ready),
    .sysp_icb_cmd_addr  (sysp_icb_cmd_addr ),
    .sysp_icb_cmd_read  (sysp_icb_cmd_read ),
    .sysp_icb_cmd_wdata (sysp_icb_cmd_wdata),
    .sysp_icb_cmd_wmask (sysp_icb_cmd_wmask),
    .sysp_icb_rsp_valid (sysp_icb_rsp_valid),
    .sysp_icb_rsp_ready (sysp_icb_rsp_ready),
    .sysp_icb_rsp_err   (sysp_icb_rsp_err  ),
    .sysp_icb_rsp_rdata (sysp_icb_rsp_rdata)
);

//s3 PLIC
assign plic_irq_port[0] = 1'b0;//中断源ID0 保留，不可以使用
assign plic_irq_port[1] = irq_fpioa_eli[0];
assign plic_irq_port[2] = irq_fpioa_eli[1];
assign plic_irq_port[3] = irq_fpioa_eli[2];
assign plic_irq_port[4] = irq_fpioa_eli[3];
assign plic_irq_port[5] = irq_uart0_tx;
assign plic_irq_port[6] = irq_uart0_rx;
assign plic_irq_port[7] = irq_uart1_tx;
assign plic_irq_port[8] = irq_uart1_rx;
assign plic_irq_port[9] = irq_timer0_of;
assign plic_irq_port[10] = irq_spi0_end;
assign plic_irq_port[11] = 1'b0;
assign plic_irq_port[12] = 1'b0;
assign plic_irq_port[13] = 1'b0;
assign plic_irq_port[14] = 1'b0;
assign plic_irq_port[15] = 1'b0;
plic inst_plic
(
    .clk                  (clk),
    .rst_n                (rst_n),

    .plic_icb_cmd_valid   (plic_icb_cmd_valid),
    .plic_icb_cmd_ready   (plic_icb_cmd_ready),
    .plic_icb_cmd_addr    (plic_icb_cmd_addr ),
    .plic_icb_cmd_read    (plic_icb_cmd_read ),
    .plic_icb_cmd_wdata   (plic_icb_cmd_wdata),
    .plic_icb_cmd_wmask   (plic_icb_cmd_wmask),
    .plic_icb_rsp_valid   (plic_icb_rsp_valid),
    .plic_icb_rsp_ready   (plic_icb_rsp_ready),
    .plic_icb_rsp_err     (plic_icb_rsp_err  ),
    .plic_icb_rsp_rdata   (plic_icb_rsp_rdata),

    .plic_irq_port        (plic_irq_port),

    .core_ex_trap_valid_o (core_ex_trap_valid),
    .core_ex_trap_id_o    (core_ex_trap_id),
    .core_ex_trap_ready_i (core_ex_trap_ready)
);

//s4
sdrd inst_sdrd
(
    .clk                (clk),
    .rst_n              (rst_n),

    .sdrd_icb_cmd_valid (sdrd_icb_cmd_valid),
    .sdrd_icb_cmd_ready (sdrd_icb_cmd_ready),
    .sdrd_icb_cmd_addr  (sdrd_icb_cmd_addr),
    .sdrd_icb_cmd_read  (sdrd_icb_cmd_read),
    .sdrd_icb_cmd_wdata (sdrd_icb_cmd_wdata),
    .sdrd_icb_cmd_wmask (sdrd_icb_cmd_wmask),
    .sdrd_icb_rsp_valid (sdrd_icb_rsp_valid),
    .sdrd_icb_rsp_ready (sdrd_icb_rsp_ready),
    .sdrd_icb_rsp_err   (sdrd_icb_rsp_err),
    .sdrd_icb_rsp_rdata (sdrd_icb_rsp_rdata),

    .sd_clk             (sd_clk),
    .sd_cmd             (sd_cmd),
    .sd_dat             (sd_dat)
);



// =====================================================
// 1. 定义 s5 ICB 线网与 AXI 线网
// =====================================================
wire                 s5_icb_cmd_valid, s5_icb_cmd_ready, s5_icb_cmd_read;
wire [`MemAddrBus]   s5_icb_cmd_addr;
wire [`MemBus]       s5_icb_cmd_wdata;
wire [3:0]           s5_icb_cmd_wmask;
wire                 s5_icb_rsp_valid, s5_icb_rsp_ready, s5_icb_rsp_err;
wire [`MemBus]       s5_icb_rsp_rdata;




//2主8从ICB总线桥
icb_2m8s inst_icb_2m8s
(
    .clk              (clk),
    
    .m0_icb_cmd_valid (jtag_icb_cmd_valid),
    .m0_icb_cmd_ready (jtag_icb_cmd_ready),
    .m0_icb_cmd_addr  (jtag_icb_cmd_addr ),
    .m0_icb_cmd_read  (jtag_icb_cmd_read ),
    .m0_icb_cmd_wdata (jtag_icb_cmd_wdata),
    .m0_icb_cmd_wmask (jtag_icb_cmd_wmask),
    .m0_icb_rsp_valid (jtag_icb_rsp_valid),
    .m0_icb_rsp_ready (jtag_icb_rsp_ready),
    .m0_icb_rsp_err   (jtag_icb_rsp_err  ),
    .m0_icb_rsp_rdata (jtag_icb_rsp_rdata),

    .m1_icb_cmd_valid (core_icb_cmd_valid),
    .m1_icb_cmd_ready (core_icb_cmd_ready),
    .m1_icb_cmd_addr  (core_icb_cmd_addr ),
    .m1_icb_cmd_read  (core_icb_cmd_read ),
    .m1_icb_cmd_wdata (core_icb_cmd_wdata),
    .m1_icb_cmd_wmask (core_icb_cmd_wmask),
    .m1_icb_rsp_valid (core_icb_rsp_valid),
    .m1_icb_rsp_ready (core_icb_rsp_ready),
    .m1_icb_rsp_err   (core_icb_rsp_err  ),
    .m1_icb_rsp_rdata (core_icb_rsp_rdata),

    .s0_icb_cmd_valid (iram_icb_cmd_valid),
    .s0_icb_cmd_ready (iram_icb_cmd_ready),
    .s0_icb_cmd_addr  (iram_icb_cmd_addr ),
    .s0_icb_cmd_read  (iram_icb_cmd_read ),
    .s0_icb_cmd_wdata (iram_icb_cmd_wdata),
    .s0_icb_cmd_wmask (iram_icb_cmd_wmask),
    .s0_icb_rsp_valid (iram_icb_rsp_valid),
    .s0_icb_rsp_ready (iram_icb_rsp_ready),
    .s0_icb_rsp_err   (iram_icb_rsp_err  ),
    .s0_icb_rsp_rdata (iram_icb_rsp_rdata),

    .s1_icb_cmd_valid (sram_icb_cmd_valid),
    .s1_icb_cmd_ready (sram_icb_cmd_ready),
    .s1_icb_cmd_addr  (sram_icb_cmd_addr ),
    .s1_icb_cmd_read  (sram_icb_cmd_read ),
    .s1_icb_cmd_wdata (sram_icb_cmd_wdata),
    .s1_icb_cmd_wmask (sram_icb_cmd_wmask),
    .s1_icb_rsp_valid (sram_icb_rsp_valid),
    .s1_icb_rsp_ready (sram_icb_rsp_ready),
    .s1_icb_rsp_err   (sram_icb_rsp_err  ),
    .s1_icb_rsp_rdata (sram_icb_rsp_rdata),

    .s2_icb_cmd_valid (sysp_icb_cmd_valid),
    .s2_icb_cmd_ready (sysp_icb_cmd_ready),
    .s2_icb_cmd_addr  (sysp_icb_cmd_addr ),
    .s2_icb_cmd_read  (sysp_icb_cmd_read ),
    .s2_icb_cmd_wdata (sysp_icb_cmd_wdata),
    .s2_icb_cmd_wmask (sysp_icb_cmd_wmask),
    .s2_icb_rsp_valid (sysp_icb_rsp_valid),
    .s2_icb_rsp_ready (sysp_icb_rsp_ready),
    .s2_icb_rsp_err   (sysp_icb_rsp_err  ),
    .s2_icb_rsp_rdata (sysp_icb_rsp_rdata),

    .s3_icb_cmd_valid (plic_icb_cmd_valid),
    .s3_icb_cmd_ready (plic_icb_cmd_ready),
    .s3_icb_cmd_addr  (plic_icb_cmd_addr ),
    .s3_icb_cmd_read  (plic_icb_cmd_read ),
    .s3_icb_cmd_wdata (plic_icb_cmd_wdata),
    .s3_icb_cmd_wmask (plic_icb_cmd_wmask),
    .s3_icb_rsp_valid (plic_icb_rsp_valid),
    .s3_icb_rsp_ready (plic_icb_rsp_ready),
    .s3_icb_rsp_err   (plic_icb_rsp_err  ),
    .s3_icb_rsp_rdata (plic_icb_rsp_rdata),

    .s4_icb_cmd_valid (sdrd_icb_cmd_valid),
    .s4_icb_cmd_ready (sdrd_icb_cmd_ready),
    .s4_icb_cmd_addr  (sdrd_icb_cmd_addr ),
    .s4_icb_cmd_read  (sdrd_icb_cmd_read ),
    .s4_icb_cmd_wdata (sdrd_icb_cmd_wdata),
    .s4_icb_cmd_wmask (sdrd_icb_cmd_wmask),
    .s4_icb_rsp_valid (sdrd_icb_rsp_valid),
    .s4_icb_rsp_ready (sdrd_icb_rsp_ready),
    .s4_icb_rsp_err   (sdrd_icb_rsp_err  ),
    .s4_icb_rsp_rdata (sdrd_icb_rsp_rdata),

    // ==========================================
    // 修改：将 s5 连接到 ICB 线网
    // ==========================================
    .s5_icb_cmd_valid (s5_icb_cmd_valid),
    .s5_icb_cmd_ready (s5_icb_cmd_ready),
    .s5_icb_cmd_addr  (s5_icb_cmd_addr ),
    .s5_icb_cmd_read  (s5_icb_cmd_read ),
    .s5_icb_cmd_wdata (s5_icb_cmd_wdata),
    .s5_icb_cmd_wmask (s5_icb_cmd_wmask),
    .s5_icb_rsp_valid (s5_icb_rsp_valid),
    .s5_icb_rsp_ready (s5_icb_rsp_ready),
    .s5_icb_rsp_err   (s5_icb_rsp_err  ),
    .s5_icb_rsp_rdata (s5_icb_rsp_rdata),

    .s6_icb_cmd_valid (                ),
    .s6_icb_cmd_ready (1'b0            ),
    .s6_icb_cmd_addr  (                ),
    .s6_icb_cmd_read  (                ),
    .s6_icb_cmd_wdata (                ),
    .s6_icb_cmd_wmask (                ),
    .s6_icb_rsp_valid (1'b0            ),
    .s6_icb_rsp_ready (                ),
    .s6_icb_rsp_err   (1'b0            ),
    .s6_icb_rsp_rdata (32'h0           ),

    .s7_icb_cmd_valid (                ),
    .s7_icb_cmd_ready (1'b0            ),
    .s7_icb_cmd_addr  (                ),
    .s7_icb_cmd_read  (                ),
    .s7_icb_cmd_wdata (                ),
    .s7_icb_cmd_wmask (                ),
    .s7_icb_rsp_valid (1'b0            ),
    .s7_icb_rsp_ready (                ),
    .s7_icb_rsp_err   (1'b0            ),
    .s7_icb_rsp_rdata (32'h0           )
);




// =============================================================================
// 2. 实例化 ICB 转 AXI 桥 (32位 ICB -> 64位 AXI，属于 25MHz SoC时钟域)
// =============================================================================
wire         br_arvalid, br_arready, br_rvalid, br_rready, br_rlast;
wire [31:0]  br_araddr;
wire [7:0]   br_arlen;
wire [2:0]   br_arsize;
wire [1:0]   br_arburst, br_rresp;
wire [63:0]  br_rdata;

wire         br_awvalid, br_awready, br_wvalid, br_wready, br_bvalid, br_bready;
wire [31:0]  br_awaddr;
wire [63:0]  br_wdata;
wire [7:0]   br_wstrb;

sirv_gnrl_icb32_to_axi64 inst_icb32_to_axi64 (
    .clk              (clk),            
    .rst_n            (rst_n),
    .i_icb_cmd_valid  (s5_icb_cmd_valid), 
    .i_icb_cmd_ready  (s5_icb_cmd_ready), 
    .i_icb_cmd_read   (s5_icb_cmd_read), 
    .i_icb_cmd_addr   (s5_icb_cmd_addr), 
    .i_icb_cmd_wdata  (s5_icb_cmd_wdata), 
    .i_icb_cmd_wmask  (s5_icb_cmd_wmask),
    .i_icb_cmd_size   (2'b10),          
    .i_icb_rsp_valid  (s5_icb_rsp_valid), 
    .i_icb_rsp_ready  (s5_icb_rsp_ready), 
    .i_icb_rsp_err    (s5_icb_rsp_err),
    .i_icb_rsp_rdata  (s5_icb_rsp_rdata), 

    // AXI 输出到内部线网
    .o_axi_arvalid    (br_arvalid), .o_axi_arready    (br_arready), .o_axi_araddr     (br_araddr),
    .o_axi_arlen      (br_arlen),   .o_axi_arsize     (br_arsize),  .o_axi_arburst    (br_arburst),
    .o_axi_rvalid     (br_rvalid),  .o_axi_rready     (br_rready),  .o_axi_rdata      (br_rdata),
    .o_axi_rresp      (br_rresp),   .o_axi_rlast      (br_rlast),
    
    .o_axi_awvalid    (br_awvalid), .o_axi_awready    (br_awready), .o_axi_awaddr     (br_awaddr),
    .o_axi_wvalid     (br_wvalid),  .o_axi_wready     (br_wready),  .o_axi_wdata      (br_wdata), 
    .o_axi_wstrb      (br_wstrb),
    .o_axi_bvalid     (br_bvalid),  .o_axi_bready     (br_bready)
);

// =============================================================================
// =============================================================================
    // 3. 读请求通道逻辑 (CMD) 替换为自建 FIFO
    // =============================================================================
    wire [68:0] cmd_fifo_din = { 10'b0, 1'b1, 4'b0, br_araddr, br_arlen, br_arsize, br_arburst, 9'b0 };
    wire [68:0] cmd_fifo_dout_raw;
    wire        cmd_fifo_full, cmd_fifo_empty_raw;
    wire        cmd_fifo_rd_en_raw;

    sparrow_async_fifo #( .DWIDTH(69), .AWIDTH(4) ) u_fifo_cmd (
      .wr_clk(clk),     .wr_rst_n(rst_n),         .wr_en(br_arvalid && !cmd_fifo_full), .wr_data(cmd_fifo_din),      .full(cmd_fifo_full),
      .rd_clk(ddr_clk), .rd_rst_n(ddr_init_done), .rd_en(cmd_fifo_rd_en_raw),           .rd_data(cmd_fifo_dout_raw), .empty(cmd_fifo_empty_raw)
    );

   // ==========================================================
    // FWFT 极简逻辑 (增加 AXI 读写强保序互锁 - RAW Hazard Fix 终极版)
    // 引入 BVALID 跟踪器：绝对确保物理内存写入完成后，再允许读取！
    // ==========================================================
    // 【修改】：将 wire 声明提取到 always 块的外部（模块层级）
    wire aw_fire = axi_awvalid && axi_awready;
    wire b_fire  = axi_bvalid && axi_bready;

    reg [7:0] ddr_outstanding_w;
    always @(posedge ddr_clk or negedge ddr_init_done) begin
        if (!ddr_init_done) 
            ddr_outstanding_w <= 8'd0;
        else begin
            if (aw_fire && !b_fire) 
                ddr_outstanding_w <= ddr_outstanding_w + 1'b1;
            else if (!aw_fire && b_fire) 
                ddr_outstanding_w <= ddr_outstanding_w - 1'b1;
        end
    end
    
    // 互锁条件：FIFO非空 OR 还有未收到 BVALID 的写请求 OR 正在握手
    wire write_is_active = (!wr_fifo_empty_raw) || (ddr_outstanding_w > 0) || aw_done || w_done;
    
    assign axi_arvalid = (!cmd_fifo_empty_raw) && (!write_is_active);
    assign cmd_fifo_rd_en_raw = axi_arvalid && axi_arready;

    wire [31:0] unaligned_araddr = cmd_fifo_dout_raw[53:22];
    wire [31:0] physical_byte_araddr = unaligned_araddr & 32'h0FFF_FFFF;
    
    // 【终极修复】：DDR IP 接收的是 32位字地址！
    // 1. & 32'hFFFF_FFE0: 强制向下对齐到 32字节边界 (对应 256bit 突发读取)
    // 2. >> 2: 将字节地址转换为 DDR IP 所需的 32位字地址
    assign axi_araddr = (physical_byte_araddr & 32'hFFFF_FFE0) >> 2;
    assign axi_arlen   = cmd_fifo_dout_raw[17:14];
    assign axi_arsize  = 3'b101;  // 强制32字节
    assign axi_arburst = cmd_fifo_dout_raw[10:9];
    assign axi_aruser_id = 4'b0000;
    assign axi_aruser_ap = 1'b0;

    // --- 外部 DDR 侧裁切逻辑 (256位 -> 64位) 保持不变 ---
    // 【修复】：扩大 AXI 读取偏移追踪 FIFO 深度，防止高压读取时被覆盖
    reg [1:0] ddr_rd_offset_q [0:31];
    reg [4:0] ddr_rd_wr_ptr, ddr_rd_rd_ptr;
    always @(posedge ddr_clk or negedge ddr_init_done) begin
        if (!ddr_init_done) begin
            ddr_rd_wr_ptr <= 0; ddr_rd_rd_ptr <= 0;
        end else begin
            if (axi_arvalid && axi_arready) begin
                ddr_rd_offset_q[ddr_rd_wr_ptr] <= unaligned_araddr[4:3];
                ddr_rd_wr_ptr <= ddr_rd_wr_ptr + 1;
            end
            if (axi_rvalid && axi_rready) ddr_rd_rd_ptr <= ddr_rd_rd_ptr + 1;
        end
    end
    wire [1:0] cur_rd_offset = ddr_rd_offset_q[ddr_rd_rd_ptr];
    wire [63:0] selected_64b_rdata = 
        (cur_rd_offset == 2'b11) ? axi_rdata[255:192] :
        (cur_rd_offset == 2'b10) ? axi_rdata[191:128] :
        (cur_rd_offset == 2'b01) ? axi_rdata[127:64]  : axi_rdata[63:0];

    // =============================================================================
    // 读返回通道 (RSP) 替换为自建 FIFO
    // =============================================================================
    wire [63:0] rsp_fifo_dout_raw;
    wire        rsp_fifo_full, rsp_fifo_empty_raw;
    wire        rsp_fifo_rd_en_raw;

    sparrow_async_fifo #( .DWIDTH(64), .AWIDTH(4) ) u_fifo_rsp (
      .wr_clk(ddr_clk), .wr_rst_n(ddr_init_done), .wr_en(axi_rvalid && !rsp_fifo_full), .wr_data(selected_64b_rdata), .full(rsp_fifo_full),
      .rd_clk(clk),     .rd_rst_n(rst_n),         .rd_en(rsp_fifo_rd_en_raw),           .rd_data(rsp_fifo_dout_raw),  .empty(rsp_fifo_empty_raw)
    );

    // FWFT 极简逻辑
    assign br_rvalid = !rsp_fifo_empty_raw;
    assign rsp_fifo_rd_en_raw = br_rvalid && br_rready;
    assign br_rdata   = rsp_fifo_dout_raw;
    
    assign axi_rready = !rsp_fifo_full;
    assign br_rlast   = 1'b1;
    assign br_rresp   = 2'b00;

    // =============================================================================
    // 4. 写通道逻辑 (WR) 替换为自建 FIFO
    // =============================================================================
    wire [103:0] wr_fifo_din = {br_awaddr, br_wdata, br_wstrb};
    wire [103:0] wr_fifo_dout_raw;
    wire         wr_fifo_full, wr_fifo_empty_raw;
    wire         wr_fifo_rd_en_raw;

    sparrow_async_fifo #( .DWIDTH(104), .AWIDTH(4) ) u_fifo_wr (
      .wr_clk(clk),     .wr_rst_n(rst_n),         .wr_en(br_awvalid && br_wvalid && !wr_fifo_full), .wr_data(wr_fifo_din),      .full(wr_fifo_full),
      .rd_clk(ddr_clk), .rd_rst_n(ddr_init_done), .rd_en(wr_fifo_rd_en_raw),                        .rd_data(wr_fifo_dout_raw), .empty(wr_fifo_empty_raw)
    );

    assign br_awready = !wr_fifo_full;
    assign br_wready  = !wr_fifo_full;
    assign br_arready = !cmd_fifo_full;

    // 写出握手逻辑
    reg aw_done, w_done;
    wire fifo_wr_pop = (axi_awvalid && axi_awready || aw_done) && 
                       (axi_wvalid && axi_wready || w_done) && !wr_fifo_empty_raw;

    assign wr_fifo_rd_en_raw = fifo_wr_pop;

    always @(posedge ddr_clk or negedge ddr_init_done) begin
        if (!ddr_init_done) begin aw_done <= 0; w_done <= 0; end
        else if (fifo_wr_pop) begin aw_done <= 0; w_done <= 0; end
        else begin
            if (axi_awvalid && axi_awready) aw_done <= 1;
            if (axi_wvalid && axi_wready)   w_done <= 1;
        end
    end

    // 写响应流水线计数
    reg [3:0] b_cnt;
    wire wr_accepted = br_awvalid && br_wvalid && !wr_fifo_full;
    wire b_returned  = br_bvalid && br_bready;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) b_cnt <= 4'd0;
        else b_cnt <= b_cnt + wr_accepted - b_returned;
    end
    assign br_bvalid = (b_cnt > 0);

    // FWFT 极简控制逻辑
    assign axi_awvalid = !wr_fifo_empty_raw && !aw_done;
    assign axi_wvalid  = !wr_fifo_empty_raw && !w_done;

    wire [31:0] ddr_wr_addr = wr_fifo_dout_raw[103:72];
    wire [63:0] ddr_wr_data = wr_fifo_dout_raw[71:8];
    wire [7:0]  ddr_wr_strb = wr_fifo_dout_raw[7:0];   

    // ================== 修改 2：写通道 (AW) ==================
    wire [31:0] physical_byte_awaddr = ddr_wr_addr & 32'h0FFF_FFFF;
    
    // 【终极修复】：写通道同样需转换为 32位字地址
    assign axi_awaddr = (physical_byte_awaddr & 32'hFFFF_FFE0) >> 2;
    assign axi_wdata = (ddr_wr_addr[4:3] == 2'b11) ? {ddr_wr_data, 192'b0} :
                       (ddr_wr_addr[4:3] == 2'b10) ? {64'b0, ddr_wr_data, 128'b0} :
                       (ddr_wr_addr[4:3] == 2'b01) ? {128'b0, ddr_wr_data, 64'b0} : {192'b0, ddr_wr_data};

    assign axi_wstrb = (ddr_wr_addr[4:3] == 2'b11) ? {ddr_wr_strb, 24'b0} :
                       (ddr_wr_addr[4:3] == 2'b10) ? {8'b0, ddr_wr_strb, 16'b0} :
                       (ddr_wr_addr[4:3] == 2'b01) ? {16'b0, ddr_wr_strb, 8'b0} : {24'b0, ddr_wr_strb};

    assign axi_awlen     = 4'b0000;
    assign axi_awuser_id = 4'b0000;
    assign axi_awuser_ap = 1'b0;
    assign axi_wusero_id   = 4'b0000;
    assign axi_wusero_last = 1'b1; 
    assign axi_bready = 1'b1;


// =============================================================================
// 5. LED 状态锁定逻辑 (25MHz SoC 侧)
// =============================================================================
reg led4_reg, led5_reg;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin led4_reg <= 0; led5_reg <= 0; end
    else begin
        if (br_awvalid && br_awready) led4_reg <= 1; // 写入请求成功触发 LED4
        if (br_rvalid && br_rready)   led5_reg <= 1; // 读数据返回成功触发 LED5
    end
end
assign led4 = led4_reg;
assign led5 = led5_reg;




//复位控制器
rstc inst_rstc
(
    .clk         (clk),
    .hard_rst_n  (hard_rst_n),
    .soft_rst_en (soft_rst_en),
    .jtag_rst_en (jtag_rst_en),
    .rst_n       (rst_n)
);


//处理器活动指示，只要指令流不停，灯就在闪
reg [clogb2(`CPU_CLOCK_HZ/4)-1:0]hx_cnt;//计数器
reg active_reg;//状态翻转
always @(posedge clk or negedge rst_n) begin
    if(~rst_n) begin
        hx_cnt <= 0;
        active_reg <= 1'b1;
    end 
    else begin
        if (hx_valid == 1'b1) begin
            if(hx_cnt < `CPU_CLOCK_HZ/4) begin
                hx_cnt <= hx_cnt + 1'b1;
            end
            else begin
                hx_cnt <= 0;
                active_reg <= ~active_reg;
            end
        end
    end
end
assign core_active = active_reg;//硬连线

//计算log2，得到地址位宽，如clogb2(RAM_DEPTH-1)
function integer clogb2;
    input integer depth;
        for (clogb2=0; depth>0; clogb2=clogb2+1)
            depth = depth >> 1;
endfunction




endmodule

// =========================================================================
// 自定义的极简安全异步 FIFO (天生 FWFT，零延迟，免疫黑盒 IP Bug)
// =========================================================================
module sparrow_async_fifo #(
    parameter DWIDTH = 64,
    parameter AWIDTH = 4
)(
    input  wire              wr_clk,
    input  wire              wr_rst_n,
    input  wire              wr_en,
    input  wire [DWIDTH-1:0] wr_data,
    output wire              full,

    input  wire              rd_clk,
    input  wire              rd_rst_n,
    input  wire              rd_en,
    output wire [DWIDTH-1:0] rd_data,
    output wire              empty
);
    reg [DWIDTH-1:0] mem [0:(1<<AWIDTH)-1];
    reg [AWIDTH:0] wptr, rptr, wq1_rptr, wq2_rptr, rq1_wptr, rq2_wptr;

    wire [AWIDTH:0] wptr_gray = wptr ^ (wptr >> 1);
    wire [AWIDTH:0] rptr_gray = rptr ^ (rptr >> 1);

    always @(posedge wr_clk or negedge wr_rst_n) begin
        if (!wr_rst_n) {wq2_rptr, wq1_rptr} <= 0;
        else {wq2_rptr, wq1_rptr} <= {wq1_rptr, rptr_gray};
    end
    always @(posedge rd_clk or negedge rd_rst_n) begin
        if (!rd_rst_n) {rq2_wptr, rq1_wptr} <= 0;
        else {rq2_wptr, rq1_wptr} <= {rq1_wptr, wptr_gray};
    end
    always @(posedge wr_clk or negedge wr_rst_n) begin
        if (!wr_rst_n) wptr <= 0;
        else if (wr_en && !full) begin
            mem[wptr[AWIDTH-1:0]] <= wr_data;
            wptr <= wptr + 1;
        end
    end
    always @(posedge rd_clk or negedge rd_rst_n) begin
        if (!rd_rst_n) rptr <= 0;
        else if (rd_en && !empty) rptr <= rptr + 1;
    end

    assign full = (wptr_gray == {~wq2_rptr[AWIDTH:AWIDTH-1], wq2_rptr[AWIDTH-2:0]});
    assign empty = (rptr_gray == rq2_wptr);
    // 异步读取，天生 FWFT，只要 empty 是 0，数据立刻有效！
    assign rd_data = mem[rptr[AWIDTH-1:0]];


endmodule
