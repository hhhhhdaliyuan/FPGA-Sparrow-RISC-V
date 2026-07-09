`include "D:\PDS\test\Sparrow_RISC-V\rtl\defines.v"

module system_top (
    input           sys_clk,
    input           key_sel,
    input           clk_p,
    input           clk_n,
    output          ddr_init_done,

     // 新增：帧冻结控制（从RISC-V SoC输出）
    output wire frame_freeze,    // 帧冻结控制信号 
    
    // RGMII (以太网) 
    input           rgmii_rxc,
    input           rgmii_rx_ctl,
    input   [3:0]   rgmii_rxd,
    output          rgmii_txc,
    output          rgmii_tx_ctl,
    output  [3:0]   rgmii_txd,
    output          phy_rstn,    // PHY 硬件复位引脚
    
    // HDMI IN
    input           pixclk_in,
    input           vs_in,
    input           hs_in,
    input           de_in, 
    input   [7:0]   r_in,
    input   [7:0]   g_in,
    input   [7:0]   b_in,
    
    // CMOS 摄像头（已废弃，引脚保留）
    
    // DDR3 ��������
    output          mem_rst_n, output mem_ck, output mem_ck_n, output mem_cke,
    output          mem_cs_n, output mem_ras_n, output mem_cas_n, output mem_we_n,
    output          mem_odt, output [14:0] mem_a, output [2:0] mem_ba,
    inout   [3:0]   mem_dqs, inout [3:0] mem_dqs_n, inout [31:0] mem_dq, output [3:0] mem_dm,
    output          heart_beat_led, output ddr_init_done_led,
    
    // MS72xx HDMI IIC 控制
    output          rstn_out,
    output          iic_tx_scl,
    inout           iic_tx_sda,
    output          hdmi_int_led,
    
    // HDMI OUT
    output          pix_clk,
    output          vs_out,
    output          hs_out,
    output          de_out,
    output  [7:0]   r_out,
    output  [7:0]   g_out,
    output  [7:0]   b_out,

   // =======================================================
    // С��ȸ SoC �ⲿ��������
    // =======================================================
    input           hard_rst_n,   // �ⲿӲ����λ (����Ч)
    output          core_active,  // �������ָʾ��
    output          led4,         // д DDR �ɹ�ָʾ��
    output          led5,         // �� DDR �ɹ�ָʾ��

    // JTAG �ӿ�
    input           JTAG_TMS,
    input           JTAG_TDI,
    output          JTAG_TDO,
    input           JTAG_TCK,
    
    // SD����TF���ӿ�
    output          sd_clk,
    inout           sd_cmd,
    input   [3:0]   sd_dat,
    
    // FPIOA (����IO���� UART��SPI ��)
    inout   [`FPIOA_PORT_NUM-1:0] fpioa
);

    wire clk_125Mhz;
    GTP_INBUFGDS #(
        .IOSTANDARD("DEFAULT"),
        .TERM_DIFF("ON")
    ) u_gtp (
        .O(clk_125Mhz), .I(clk_p), .IB(clk_n)
    );

    wire core_clk, pll_lock;
    wire GND = 1'b0; // ��ȫ�ӵ��ź�

   wire rgmii_clk, rgmii_clk_90p, rgmii_pll_lock;
    wire mac_tx_en, mac_rx_dv;
    wire [7:0] mac_tx_data, mac_rx_data;

  
    eth_rgmii_pll u_eth_rgmii_pll (
        .clkout0         ( rgmii_clk_90p ), 
        .lock            ( rgmii_pll_lock),
        .clkin1          ( clk_125Mhz     ) // ʹ���������ŵĽ���ʱ��
    );

    
    // ֻ�е�����ʱ���ͽ����� PLL �����󣬲���������߼�
    wire eth_rstn = rstn_out & rgmii_pll_lock;
    
   
    assign phy_rstn = eth_rstn;
    

   
   rgmii_interface u_rgmii_interface (
        .rst               ( ~eth_rstn    ),   // ��λ
        .rgmii_clk         ( rgmii_clk    ),   // �Ѳ�����ʱ��������ⲿ�� wire
        .rgmii_clk_90p     ( rgmii_clk_90p),   // ���� PLL ���� 90 ��ʱ��
        .mac_tx_data_valid ( mac_tx_en    ), 
        .mac_tx_data       ( mac_tx_data  ), 
        .mac_rx_error      (              ),
        .mac_rx_data_valid ( mac_rx_dv    ), 
        .mac_rx_data       ( mac_rx_data  ), 
        .rgmii_rxc         ( rgmii_rxc    ),   // �������ţ��������ʱ��
        .rgmii_rx_ctl      ( rgmii_rx_ctl ), 
        .rgmii_rxd         ( rgmii_rxd    ), 
        .rgmii_txc         ( rgmii_txc    ), 
        .rgmii_tx_ctl      ( rgmii_tx_ctl ), 
        .rgmii_txd         ( rgmii_txd    )  
    );

    // =======================================================
    // M0 (RISC-V ��˶�дͨ��)
    // =======================================================
    wire [31:0] m0_awaddr;   wire [3:0] m0_awid;    wire [3:0] m0_awlen;
    wire        m0_awready;  wire       m0_awvalid;
    wire [255:0]m0_wdata;    wire [31:0]m0_wstrb;   wire       m0_wlast;
    wire        m0_wvalid;   wire       m0_wready;
    wire        m0_bready;   wire       m0_bvalid;  wire [3:0] m0_bid;   wire [1:0] m0_bresp;
    wire [31:0] m0_araddr;   wire [3:0] m0_arid;    wire [3:0] m0_arlen;
    wire        m0_arvalid;  wire       m0_arready;
    wire        m0_rready;   wire [255:0]m0_rdata;  wire       m0_rvalid;
    wire        m0_rlast;    wire [3:0] m0_rid;
    
    // M1 (ԭͼ��дͨ��)
    wire [27:0] m1_awaddr;  wire [3:0] m1_awid;   wire [3:0] m1_awlen;  wire [2:0] m1_awsize;
    wire [1:0]  m1_awburst; wire       m1_awready;wire       m1_awvalid;
    wire [255:0]m1_wdata;   wire [31:0]m1_wstrb;  wire       m1_wvalid;
    wire        m1_wready;  wire [3:0] m1_bid;
    wire [27:0] m1_araddr;  wire [3:0] m1_arid;   wire [3:0] m1_arlen;  wire [2:0] m1_arsize;
    wire [1:0]  m1_arburst; wire       m1_arvalid;wire       m1_arready;
    wire        m1_rready;  wire [255:0]m1_rdata; wire       m1_rvalid; wire       m1_rlast;
    wire [3:0]  m1_rid;

    // M2 (��ֵ��ͼ��дͨ��)
    wire [27:0] m2_awaddr;  wire [3:0] m2_awid;   wire [3:0] m2_awlen;  wire [2:0] m2_awsize;
    wire [1:0]  m2_awburst; wire       m2_awready;wire       m2_awvalid;
    wire [255:0]m2_wdata;   wire [31:0]m2_wstrb;  wire       m2_wvalid;
    wire        m2_wready;  wire [3:0] m2_bid;
    
    // =====  M2 ��ͨ��  =====
    wire [27:0] m2_araddr;  wire [3:0] m2_arid;   wire [3:0] m2_arlen;  wire [2:0] m2_arsize;
    wire [1:0]  m2_arburst; wire       m2_arready;wire       m2_arvalid;
    wire [255:0]m2_rdata;   wire [3:0] m2_rid;    wire       m2_rvalid;
    wire        m2_rlast;   wire       m2_rready;

    // S0 (����� DDR IP ������)
    wire [27:0] s_awaddr;   wire [3:0] s_awid;    wire [3:0] s_awlen;   wire       s_awready;
    wire        s_awvalid;  wire [255:0]s_wdata;  wire [31:0]s_wstrb;   
    wire        s_wvalid;   wire       s_wready;  
    wire        s_bready;
    wire [27:0] s_araddr;   wire [3:0] s_arid;    wire [3:0] s_arlen;   wire       s_arready;
    wire        s_arvalid;  wire [255:0]s_rdata;  wire [3:0] s_rid;     wire       s_rlast;
    wire        s_rvalid;   wire       s_rready;

    assign ddr_init_done_led = ddr_init_done;

    // ====================================================
    // ���� M1 �� M2 �� wlast ����
    // ====================================================
    wire ddr_wlast; 
    
    // ֻ�е��Լ�����д���� (wvalid=1) ʱ���ų��� DDR ������ wlast �Ǹ��Լ���
   wire m1_wlast = ddr_wlast  & m1_wready; // ���� & m1_wready
   wire m2_wlast = ddr_wlast  & m2_wready; // ���� & m2_wready

    // α�� B ͨ����Ӧ�������һ�����ֳɹ�ʱ���� bvalid��������
    wire s_bvalid = s_wvalid & s_wready & ddr_wlast;



    // ====================================================
    // 视频处理子系统 (原hdmi_top)
    // ====================================================
    hdmi_ddr_ov5640_top u_video_subsystem (
        .sys_clk         (sys_clk),
        .key_sel         (key_sel),
        .core_clk        (core_clk),
        .ddr_init_done   (ddr_init_done),
        .rgmii_clk      ( rgmii_clk    ),
        .mac_tx_en      ( mac_tx_en    ),
        .mac_tx_data    ( mac_tx_data  ),
        .mac_rx_dv      ( mac_rx_dv    ),
        .mac_rx_data    ( mac_rx_data  ),
        .pixclk_in(pixclk_in), .vs_in(vs_in), .hs_in(hs_in), .de_in(de_in), 
        .r_in(r_in), .g_in(g_in), .b_in(b_in),
        .rstn_out(rstn_out), .iic_tx_scl(iic_tx_scl), .iic_tx_sda(iic_tx_sda), .hdmi_int_led(hdmi_int_led),
        .pix_clk(pix_clk), .vs_out(vs_out), .hs_out(hs_out), .de_out(de_out), .r_out(r_out), .g_out(g_out), .b_out(b_out),
        .rgmii_txc(rgmii_txc), .rgmii_tx_ctl(rgmii_tx_ctl), .rgmii_txd(rgmii_txd),
        .heart_beat_led(heart_beat_led),
        
        .frame_freeze       (frame_freeze),  // 新增连接,帧冻结控制信号

        // AXI M1 (传入隔离后的 m1_wlast)
        .m1_awaddr(m1_awaddr), .m1_awid(m1_awid), .m1_awlen(m1_awlen), .m1_awsize(m1_awsize), .m1_awburst(m1_awburst), .m1_awready(m1_awready), .m1_awvalid(m1_awvalid),
        .m1_wdata(m1_wdata), .m1_wstrb(m1_wstrb), .m1_wlast(m1_wlast), .m1_wvalid(m1_wvalid), .m1_wready(m1_wready), .m1_bid(m1_bid),
        .m1_araddr(m1_araddr), .m1_arid(m1_arid), .m1_arlen(m1_arlen), .m1_arsize(m1_arsize), .m1_arburst(m1_arburst), .m1_arvalid(m1_arvalid), .m1_arready(m1_arready),
        .m1_rready(m1_rready), .m1_rdata(m1_rdata), .m1_rvalid(m1_rvalid), .m1_rlast(m1_rlast), .m1_rid(m1_rid),
        
        // AXI M2 (传入隔离后的 m2_wlast)
        .m2_awaddr(m2_awaddr), .m2_awid(m2_awid), .m2_awlen(m2_awlen), .m2_awsize(m2_awsize), .m2_awburst(m2_awburst), .m2_awready(m2_awready), .m2_awvalid(m2_awvalid),
        .m2_wdata(m2_wdata), .m2_wstrb(m2_wstrb), .m2_wlast(m2_wlast), .m2_wvalid(m2_wvalid), .m2_wready(m2_wready), .m2_bid(m2_bid),
        
        // ===== 新增连线：M2 AXI 读通道 =====
        .m2_araddr(m2_araddr), .m2_arid(m2_arid), .m2_arlen(m2_arlen), .m2_arsize(m2_arsize), .m2_arburst(m2_arburst), .m2_arvalid(m2_arvalid), .m2_arready(m2_arready),
        .m2_rready(m2_rready), .m2_rdata(m2_rdata), .m2_rvalid(m2_rvalid), .m2_rlast(m2_rlast), .m2_rid(m2_rid)
    );


// ====================================================
    // С��ȸ RISC-V SoC ʵ����
    // ====================================================
    sparrow_soc u_sparrow_soc (
        .clk              (sys_clk),        // ϵͳ��ʱ�� 27MHz
        .hard_rst_n       (hard_rst_n),     
        .core_active      (core_active),

        .JTAG_TMS         (JTAG_TMS),
        .JTAG_TDI         (JTAG_TDI),
        .JTAG_TDO         (JTAG_TDO),
        .JTAG_TCK         (JTAG_TCK),

        .sd_clk           (sd_clk),
        .sd_cmd           (sd_cmd),
        .sd_dat           (sd_dat),
        .fpioa            (fpioa),
         
        .frame_freeze       (frame_freeze),  // ��������
        .led4             (led4),
        .led5             (led5), // ���޸ġ������ڲ� wire

        // DDR ��ʱ�����ź�
        .ddr_clk          (core_clk),       // DDR IP �ṩ�� 125MHz ʱ��
        .ddr_init_done    (ddr_init_done),  // DDR ��ʼ������ź�

        // AXI AR (����ַͨ��)
        .axi_araddr       (m0_araddr),
        .axi_arlen        (m0_arlen),
        .axi_aruser_id    (m0_arid),
        .axi_aruser_ap    (),               // ��ռ���
        .axi_arvalid      (m0_arvalid),
        .axi_arready      (m0_arready),

        // AXI R (������ͨ��)
        .axi_rdata        (m0_rdata),
        .axi_rid          (m0_rid),
        .axi_rlast        (m0_rlast),
        .axi_rvalid       (m0_rvalid),
        .axi_rready       (m0_rready),

        // AXI AW (д��ַͨ��)
        .axi_awaddr       (m0_awaddr),
        .axi_awlen        (m0_awlen),
        .axi_awuser_id    (m0_awid),
        .axi_awuser_ap    (),               // ��ռ���
        .axi_awvalid      (m0_awvalid),
        .axi_awready      (m0_awready),

        // AXI W (д����ͨ��)
        .axi_wdata        (m0_wdata),
        .axi_wstrb        (m0_wstrb),
        .axi_wusero_id    (),               // ��ռ���
        .axi_wusero_last  (m0_wlast),
        .axi_wvalid       (m0_wvalid),
        .axi_wready       (m0_wready),

        // AXI B (д��Ӧͨ��)
        .axi_bvalid       (m0_bvalid),
        .axi_bready       (m0_bready)
    );



    // ====================================================
    // AXI 3to1 �ٲ���
    // ====================================================
    axi_arbiter_3to1 #(
        .DATA_WIDTH(256), .ADDR_WIDTH(28), .ID_WIDTH(4)
    ) u_axi_arbiter (
        .clk(core_clk), .rst_n(ddr_init_done),
        
        // M0: RISC-V ��˽���
        .m0_awaddr(m0_awaddr[27:0]), .m0_awlen(m0_awlen), .m0_awid(m0_awid), .m0_awvalid(m0_awvalid), .m0_awready(m0_awready),
        .m0_wdata(m0_wdata), .m0_wstrb(m0_wstrb), .m0_wlast(m0_wlast), .m0_wvalid(m0_wvalid), .m0_wready(m0_wready),
        .m0_bresp(m0_bresp), .m0_bid(m0_bid), .m0_bvalid(m0_bvalid), .m0_bready(m0_bready),
        .m0_araddr(m0_araddr[27:0]), .m0_arlen(m0_arlen), .m0_arid(m0_arid), .m0_arvalid(m0_arvalid), .m0_arready(m0_arready),
        .m0_rdata(m0_rdata), .m0_rlast(m0_rlast), .m0_rid(m0_rid), .m0_rvalid(m0_rvalid), .m0_rready(m0_rready),
        
        // M1: ԭͼ����д��
        .m1_awaddr(m1_awaddr), .m1_awlen(m1_awlen), .m1_awid(m1_awid), .m1_awvalid(m1_awvalid), .m1_awready(m1_awready),
        .m1_wdata(m1_wdata), .m1_wstrb(m1_wstrb), .m1_wlast(m1_wlast), .m1_wvalid(m1_wvalid), .m1_wready(m1_wready),
        .m1_bresp(), .m1_bid(m1_bid), .m1_bvalid(), .m1_bready(1'b1),
        .m1_araddr(m1_araddr), .m1_arlen(m1_arlen), .m1_arid(m1_arid), .m1_arvalid(m1_arvalid), .m1_arready(m1_arready),
        .m1_rdata(m1_rdata), .m1_rlast(m1_rlast), .m1_rid(m1_rid), .m1_rvalid(m1_rvalid), .m1_rready(m1_rready),

        // M2: ��ֵ��ͼ��ֻд��
        .m2_awaddr(m2_awaddr), .m2_awlen(m2_awlen), .m2_awid(m2_awid), .m2_awvalid(m2_awvalid), .m2_awready(m2_awready),
        .m2_wdata(m2_wdata), .m2_wstrb(m2_wstrb), .m2_wlast(m2_wlast), .m2_wvalid(m2_wvalid), .m2_wready(m2_wready),
        .m2_bresp(), .m2_bid(m2_bid), .m2_bvalid(), .m2_bready(1'b1),
        .m2_araddr(m2_araddr), .m2_arlen(m2_arlen), .m2_arid(m2_arid), .m2_arvalid(m2_arvalid), .m2_arready(m2_arready),
        .m2_rdata(m2_rdata), .m2_rlast(m2_rlast), .m2_rid(m2_rid), .m2_rvalid(m2_rvalid), .m2_rready(m2_rready),
        
        // S0: ��� DDR
        .s_awaddr(s_awaddr), .s_awlen(s_awlen), .s_awid(s_awid), .s_awvalid(s_awvalid), .s_awready(s_awready),
        .s_wdata(s_wdata), .s_wstrb(s_wstrb), 
        .s_wlast(), //�����߶�������ͻ
        .s_wvalid(s_wvalid), .s_wready(s_wready),
        .s_bresp(2'b00), .s_bid(s_awid), .s_bvalid(s_bvalid), .s_bready(s_bready),
        .s_araddr(s_araddr), .s_arlen(s_arlen), .s_arid(s_arid), .s_arvalid(s_arvalid), .s_arready(s_arready),
        .s_rdata(s_rdata), .s_rlast(s_rlast), .s_rid(s_rid), .s_rvalid(s_rvalid), .s_rready(s_rready)
    );

    // ====================================================
    // DDR3 IP
    // ====================================================
    ddr3_test u_ddr3_test_h (
        .ref_clk                  (clk_125Mhz),
        .resetn                   (rstn_out),
        .ddr_init_done            (ddr_init_done),
        .pll_lock                 (pll_lock),
        .core_clk                 (core_clk),

        .axi_awaddr               (s_awaddr),
        .axi_awuser_ap            (GND),
        .axi_awuser_id            (s_awid),
        .axi_awlen                (s_awlen),
        .axi_awready              (s_awready),
        .axi_awvalid              (s_awvalid),
        .axi_wdata                (s_wdata),
        .axi_wstrb                (s_wstrb),
        .axi_wready               (s_wready),
        .axi_wusero_id            (),
        .axi_wusero_last          (ddr_wlast), // ��������������߼�
        
        .axi_araddr               (s_araddr),
        .axi_aruser_ap            (GND),
        .axi_aruser_id            (s_arid),
        .axi_arlen                (s_arlen),
        .axi_arready              (s_arready),
        .axi_arvalid              (s_arvalid),
        .axi_rdata                (s_rdata),
        .axi_rid                  (s_rid),
        .axi_rlast                (s_rlast),
        .axi_rvalid               (s_rvalid),
        
        .apb_clk                  (1'b0),
        .apb_rst_n                (1'b1),
        .apb_sel                  (1'b0),
        .apb_enable               (1'b0),
        .apb_addr                 (8'b0),
        .apb_write                (1'b0),
        .apb_ready                (), 
        .apb_wdata                (16'b0),
        .apb_rdata                (),
        
        .mem_rst_n(mem_rst_n), .mem_ck(mem_ck), .mem_ck_n(mem_ck_n), .mem_cke(mem_cke),
        .mem_cs_n(mem_cs_n), .mem_ras_n(mem_ras_n), .mem_cas_n(mem_cas_n), .mem_we_n(mem_we_n),
        .mem_odt(mem_odt), .mem_a(mem_a), .mem_ba(mem_ba), .mem_dqs(mem_dqs), .mem_dqs_n(mem_dqs_n),
        .mem_dq(mem_dq), .mem_dm(mem_dm),
        
        .dbg_gate_start(GND), .dbg_cpd_start(GND), .dbg_ddrphy_rst_n(1'b1), .dbg_gpll_scan_rst(GND),
        .samp_position_dyn_adj(GND), .init_samp_position_even(32'd0), .init_samp_position_odd(32'd0),
        .wrcal_position_dyn_adj(GND), .init_wrcal_position(32'd0), .force_read_clk_ctrl(GND),
        .init_slip_step(16'd0), .init_read_clk_ctrl(12'd0), .debug_cpd_offset_adj(GND),
        .debug_cpd_offset_dir(GND), .debug_cpd_offset(10'd0), .ck_dly_en(GND), .init_ck_dly_step(8'h0)
    );

endmodule


