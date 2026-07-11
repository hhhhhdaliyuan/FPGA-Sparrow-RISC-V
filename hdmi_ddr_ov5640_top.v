`timescale 1ns / 1ps
`define UD #1
`define CMOS_1      //cmos1作为视频输入；

module hdmi_ddr_ov5640_top#(
	parameter MEM_ROW_ADDR_WIDTH   = 15         ,
	parameter MEM_COL_ADDR_WIDTH   = 10         ,
	parameter MEM_BADDR_WIDTH      = 3          ,
	parameter MEM_DQ_WIDTH         =  32        ,
	parameter MEM_DQS_WIDTH        =  32/8
)(
	input                                sys_clk              ,//50Mhz
    input                                key_sel              ,//key0, active low
    
    input                                core_clk             ,
    input                                ddr_init_done        ,

     // 新增：帧冻结控制输入（来自RISC-V SoC）
    input wire frame_freeze,         // 帧冻结控制信号（1=冻结，0=释放）

    // ====== rgmii 引脚 接口 ====== 
    input                                rgmii_clk            ,
    output                               mac_tx_en             ,
    output     [7:0]                     mac_tx_data           ,
    input                                mac_rx_dv             ,
    input      [7:0]                     mac_rx_data          ,  // <--- 补上这一行！
    input                                pixclk_in            ,
    input                                vs_in                ,
    input                                hs_in                ,
    input                                de_in                ,
    input      [7:0]                     r_in                 ,
    input      [7:0]                     g_in                 ,
    input      [7:0]                     b_in                 ,
    output  [1:0]                        cmos_init_done       ,
    inout                                cmos1_scl            ,
    inout                                cmos1_sda            ,
    input                                cmos1_vsync          ,
    input                                cmos1_href           ,
    input                                cmos1_pclk           ,
    input   [7:0]                        cmos1_data           ,
    output                               cmos1_reset          ,
    inout                                cmos2_scl            ,
    inout                                cmos2_sda            ,
    input                                cmos2_vsync          ,
    input                                cmos2_href           ,
    input                                cmos2_pclk           ,
    input   [7:0]                        cmos2_data           ,
    output                               cmos2_reset          ,
    output reg                           heart_beat_led       ,
    output                               rstn_out             ,
    output                               iic_tx_scl           ,
    inout                                iic_tx_sda           ,
    output                               hdmi_int_led         ,
    output                               pix_clk              ,
    output     reg                       vs_out               , 
    output     reg                       hs_out               , 
    output     reg                       de_out               ,
    output     reg[7:0]                  r_out                , 
    output     reg[7:0]                  g_out                , 
    output     reg[7:0]                  b_out                ,
    output                               rgmii_txc            ,
    output                               rgmii_tx_ctl         ,
    output      [3:0]                    rgmii_txd            ,
    

    // M1 AXI
    output [27:0]                        m1_awaddr     ,
    output [3:0]                         m1_awid       ,
    output [3:0]                         m1_awlen      ,
    output [2:0]                         m1_awsize     ,
    output [1:0]                         m1_awburst    ,
    input                                m1_awready    ,
    output                               m1_awvalid    ,
    output [255:0]                       m1_wdata      ,
    output [31:0]                        m1_wstrb      ,
    input                                m1_wlast      ,
    output                               m1_wvalid     ,
    input                                m1_wready     ,
    input  [3:0]                         m1_bid        ,
    output [27:0]                        m1_araddr     ,
    output [3:0]                         m1_arid       ,
    output [3:0]                         m1_arlen      ,
    output [2:0]                         m1_arsize     ,
    output [1:0]                         m1_arburst    ,
    output                               m1_arvalid    ,
    input                                m1_arready    ,
    output                               m1_rready     ,
    input  [255:0]                       m1_rdata      ,
    input                                m1_rvalid     ,
    input                                m1_rlast      ,
    input  [3:0]                         m1_rid        ,

    // M2 AXI
    output [27:0]                        m2_awaddr     ,
    output [3:0]                         m2_awid       ,
    output [3:0]                         m2_awlen      ,
    output [2:0]                         m2_awsize     ,
    output [1:0]                         m2_awburst    ,
    input                                m2_awready    ,
    output                               m2_awvalid    ,
    output [255:0]                       m2_wdata      ,
    output [31:0]                        m2_wstrb      ,
    input                                m2_wlast      ,
    output                               m2_wvalid     ,
    input                                m2_wready     ,
    input  [3:0]                         m2_bid        ,

    // =====  M2 AXI 读通道端口 =====
    output [27:0]                        m2_araddr     ,
    output [3:0]                         m2_arid       ,
    output [3:0]                         m2_arlen      ,
    output [2:0]                         m2_arsize     ,
    output [1:0]                         m2_arburst    ,
    output                               m2_arvalid    ,
    input                                m2_arready    ,
    output                               m2_rready     ,
    input  [255:0]                       m2_rdata      ,
    input                                m2_rvalid     ,
    input                                m2_rlast      ,
    input  [3:0]                         m2_rid
);

    parameter CTRL_ADDR_WIDTH = MEM_ROW_ADDR_WIDTH + MEM_BADDR_WIDTH + MEM_COL_ADDR_WIDTH;
    parameter TH_1S = 27'd33000000;

    reg  [15:0]                 rstn_1ms            ;
    wire                        initial_en          ;
    wire[15:0]                  cmos1_d_16bit       ;
    wire                        cmos1_href_16bit    ;
    reg [7:0]                   cmos1_d_d0          ;
    reg                         cmos1_href_d0       ;
    reg                         cmos1_vsync_d0      ;
    wire                        cmos1_pclk_16bit    ;
    wire[15:0]                  cmos2_d_16bit       ;
    wire                        cmos2_href_16bit    ;
    reg [7:0]                   cmos2_d_d0          ;
    reg                         cmos2_href_d0       ;
    reg                         cmos2_vsync_d0      ;
    wire                        cmos2_pclk_16bit    ;
    wire[15:0]                  o_rgb565            ;
    wire                        pclk_in_test        ;
    wire                        vs_in_test          ;
    wire                        de_in_test          ;
    wire[15:0]                  i_rgb565            ;
    wire                        ov_pclk_in          ;
    wire                        ov_vs_in            ;
    wire                        ov_de_in            ;
    wire [15:0]                 ov_rgb565           ;
    wire [15:0]                 hdmi_rgb565         ;
    wire [15:0]                 proc_rgb565_o       ;
    wire                        proc_vsync          ;
    wire                        proc_hsync          ;
    wire                        proc_de             ;
    wire [7:0]                  proc_bin            ;
    wire                        de_re               ;
    wire [15:0]                 proc_rgb565         ;
    wire                        init_done           ;
    reg  [2:0]                  key_sync            ;
    reg                         key_lock            ;
    reg  [20:0]                 key_cnt             ;
    reg  [26:0]                 cnt                 ;
    
    wire cfg_clk, clk_25M, locked;

    pll u_pll (
        .clkin1   (  sys_clk    ),
        .clkout0  (  pix_clk    ),
        .clkout1  (  cfg_clk    ),
        .clkout2  (  clk_25M    ),
        .lock     (  locked     )
    );

    wire init_over_tx, init_over_rx;
    ms72xx_ctl ms72xx_ctl(
        .clk             (  cfg_clk        ),
        .rst_n           (  rstn_out       ),
        .init_over       (  init_over_tx   ),
        .init_over_rx    (  init_over_rx   ),
        .iic_scl         (  iic_tx_scl     ),
        .iic_sda         (  iic_tx_sda     ) 
    );

    always @(posedge cfg_clk) begin
    	if(!locked)
    	    rstn_1ms <= 16'd0;
    	else begin
    		if(rstn_1ms == 16'h2710)
    		    rstn_1ms <= rstn_1ms;
    		else
    		    rstn_1ms <= rstn_1ms + 1'b1;
    	end
    end
    
    assign rstn_out = (rstn_1ms == 16'h2710);
    
    power_on_delay	power_on_delay_inst(
    	.clk_50M                 (sys_clk        ),
    	.reset_n                 (1'b1           ),
    	.camera1_rstn            (cmos1_reset    ),
    	.camera2_rstn            (cmos2_reset    ),
    	.camera_pwnd             (               ),
    	.initial_en              (initial_en     ) 
    );

    reg_config	coms1_reg_config(
    	.clk_25M                 (clk_25M            ),
    	.camera_rstn             (cmos1_reset        ),
    	.initial_en              (initial_en         ),
    	.i2c_sclk                (cmos1_scl          ),
    	.i2c_sdat                (cmos1_sda          ),
    	.reg_conf_done           (cmos_init_done[0]  )
    );

    reg_config	coms2_reg_config(
    	.clk_25M                 (clk_25M            ),
    	.camera_rstn             (cmos2_reset        ),
    	.initial_en              (initial_en         ),
    	.i2c_sclk                (cmos2_scl          ),
    	.i2c_sdat                (cmos2_sda          ),
    	.reg_conf_done           (cmos_init_done[1]  )
    );

    always@(posedge cmos1_pclk) begin
        cmos1_d_d0        <= cmos1_data    ;
        cmos1_href_d0     <= cmos1_href    ;
        cmos1_vsync_d0    <= cmos1_vsync   ;
    end

    cmos_8_16bit cmos1_8_16bit(
    	.pclk           (cmos1_pclk       ),
    	.rst_n          (cmos_init_done[0]),
    	.pdata_i        (cmos1_d_d0       ),
    	.de_i           (cmos1_href_d0    ),
    	.vs_i           (cmos1_vsync_d0   ),
    	.pixel_clk      (cmos1_pclk_16bit ),
    	.pdata_o        (cmos1_d_16bit    ),
    	.de_o           (cmos1_href_16bit ) 
    );

    always@(posedge cmos2_pclk) begin
        cmos2_d_d0        <= cmos2_data    ;
        cmos2_href_d0     <= cmos2_href    ;
        cmos2_vsync_d0    <= cmos2_vsync   ;
    end

    cmos_8_16bit cmos2_8_16bit(
    	.pclk           (cmos2_pclk       ),
    	.rst_n          (cmos_init_done[1]),
    	.pdata_i        (cmos2_d_d0       ),
    	.de_i           (cmos2_href_d0    ),
    	.vs_i           (cmos2_vsync_d0   ),
    	.pixel_clk      (cmos2_pclk_16bit ),
    	.pdata_o        (cmos2_d_16bit    ),
    	.de_o           (cmos2_href_16bit ) 
    );

`ifdef CMOS_1
assign     ov_pclk_in      =    cmos1_pclk_16bit    ;
assign     ov_vs_in        =    cmos1_vsync_d0      ;
assign     ov_de_in        =    cmos1_href_16bit    ;
assign     ov_rgb565       =    {cmos1_d_16bit[4:0],cmos1_d_16bit[10:5],cmos1_d_16bit[15:11]};
`elsif CMOS_2
assign     ov_pclk_in      =    cmos2_pclk_16bit    ;
assign     ov_vs_in        =    cmos2_vsync_d0      ;
assign     ov_de_in        =    cmos2_href_16bit    ;
assign     ov_rgb565       =    {cmos2_d_16bit[4:0],cmos2_d_16bit[10:5],cmos2_d_16bit[15:11]};
`endif

assign     hdmi_rgb565     =    {r_in[7:3],g_in[7:2],b_in[7:3]};
// 输入源选择：0=HDMI, 1=摄像头
// input_source_sel 由按键消抖逻辑控制
assign     pclk_in_test    =    input_source_sel ? ov_pclk_in    : pixclk_in;
assign     vs_in_test      =    input_source_sel ? ov_vs_in      : (~vs_in);
assign     de_in_test      =    input_source_sel ? ov_de_in      : de_in;
assign     i_rgb565        =    input_source_sel ? ov_rgb565     : hdmi_rgb565;

always @(posedge sys_clk) begin
    key_sync <= {key_sync[1:0], key_sel};
end

// -------------------------------------------------------------
// 按键消抖逻辑 - 输入源切换 (0=HDMI, 1=摄像头)
// -------------------------------------------------------------
reg key_state;        // 记录按键稳定后的状态
reg input_source_sel; // 0=HDMI输入, 1=摄像头输入

always @(posedge sys_clk) begin
    if (!rstn_out) begin
        input_source_sel <= 1'b0; // 默认HDMI输入
        key_cnt   <= 21'd0;
        key_state <= 1'b1;        // 默认未按下(高电平)
    end else begin
        if (key_sync[2] != key_state) begin
            key_cnt <= key_cnt + 1'b1;
            if (key_cnt >= 21'd1000000) begin 
                key_state <= key_sync[2];
                key_cnt   <= 21'd0;
                
                // 按下动作(低电平)，切换输入源！
                if (key_sync[2] == 1'b0) begin
                    input_source_sel <= ~input_source_sel; // 0=HDMI, 1=摄像头
                end
            end
        end else begin
            key_cnt <= 21'd0;
        end
    end
end

assign    hdmi_int_led    = |i_rgb565;

// ddr_write_en 使用输入的 frame_freeze
wire ddr_write_en = de_in_test & (~frame_freeze);  // frame_freeze=1时冻结


    // 原图缓存 (DDR Offset 0)
    fram_buf #(
        .ADDR_OFFSET    (32'h0100_0000) ,
        .H_NUM          (12'd1280),     
        .V_NUM          (12'd720)       
    ) fram_buf_raw (
        .ddr_clk        (  core_clk             ),
        .ddr_rstn       (  ddr_init_done        ),
        .vin_clk        (  pclk_in_test         ),
        .wr_fsync       (  vs_in_test           ),
        .wr_en          (  ddr_write_en           ),
        .wr_data        (  i_rgb565             ),
        .vout_clk       (  pix_clk              ),
        .rd_fsync       (  vs_o                 ),
        .rd_en          (  de_re                ),
        .vout_de        (  de_o                 ),
        .vout_data      (  o_rgb565             ),
        .init_done      (  init_done            ),
        
        .axi_awaddr     (  m1_awaddr            ),
        .axi_awid       (  m1_awid              ),
        .axi_awlen      (  m1_awlen             ),
        .axi_awsize     (  m1_awsize            ),
        .axi_awburst    (  m1_awburst           ),
        .axi_awready    (  m1_awready           ),
        .axi_awvalid    (  m1_awvalid           ),
        .axi_wdata      (  m1_wdata             ),
        .axi_wstrb      (  m1_wstrb             ),
        .axi_wlast      (  m1_wlast             ),
        .axi_wvalid     (  m1_wvalid            ),
        .axi_wready     (  m1_wready            ),
        .axi_bid        (  m1_bid               ),
        .axi_araddr     (  m1_araddr            ),
        .axi_arid       (  m1_arid              ),
        .axi_arlen      (  m1_arlen             ),
        .axi_arsize     (  m1_arsize            ),
        .axi_arburst    (  m1_arburst           ),
        .axi_arvalid    (  m1_arvalid           ),
        .axi_arready    (  m1_arready           ),
        .axi_rready     (  m1_rready            ),
        .axi_rdata      (  m1_rdata             ),
        .axi_rvalid     (  m1_rvalid            ),
        .axi_rlast      (  m1_rlast             ),
        .axi_rid        (  m1_rid               )
    );

    // =========================================================
    // 二值图缓存 
    // =========================================================
    fram_buf #(
        .ADDR_OFFSET    (32'h0000_0000) ,
        .H_NUM          (12'd1280),     
        .V_NUM          (12'd720)       
    ) fram_buf_bin (
        .ddr_clk        (  core_clk             ),
        .ddr_rstn       (  ddr_init_done        ),
        .vin_clk        (  pix_clk              ),
        
        // 写入端与 image_process 的输出绑定！
        .wr_fsync       (  proc_vsync           ), //  proc_vsync
        .wr_en          (  proc_de              ), // proc_de
        .wr_data        (  proc_rgb565_o        ), 
        
        .vout_clk       (  pix_clk              ),
        
       
        .rd_fsync       (  vs_o          ), 
        .rd_en          (  1'b0                 ), // 永远不读
        
        .vout_de        (                       ),
        .vout_data      (                       ),
        .init_done      (                       ),
        
        .axi_awaddr     (  m2_awaddr            ),
        .axi_awid       (  m2_awid              ),
        .axi_awlen      (  m2_awlen             ),
        .axi_awsize     (  m2_awsize            ),
        .axi_awburst    (  m2_awburst           ),
        .axi_awready    (  m2_awready           ),
        .axi_awvalid    (  m2_awvalid           ),
        .axi_wdata      (  m2_wdata             ),
        .axi_wstrb      (  m2_wstrb             ),
        .axi_wlast      (  m2_wlast             ),
        .axi_wvalid     (  m2_wvalid            ),
        .axi_wready     (  m2_wready            ),
        .axi_bid        (  m2_bid               ),
        
        // =====  AXI 读信号替换为真实端口 =====
        .axi_araddr     (  m2_araddr            ),
        .axi_arid       (  m2_arid              ),
        .axi_arlen      (  m2_arlen             ),
        .axi_arsize     (  m2_arsize            ),
        .axi_arburst    (  m2_arburst           ),
        .axi_arvalid    (  m2_arvalid           ),
        .axi_arready    (  m2_arready           ),
        .axi_rready     (  m2_rready            ),
        .axi_rdata      (  m2_rdata             ),
        .axi_rvalid     (  m2_rvalid            ),
        .axi_rlast      (  m2_rlast             ),
        .axi_rid        (  m2_rid               )
        // ===================================================
    );

    // =========================================================
    // HDMI 输出切换回 o_rgb565 (M1读出的原图)
    // =========================================================
    always@(posedge pix_clk) begin
        r_out  <= {o_rgb565[15:11], 3'b0};
        g_out  <= {o_rgb565[10:5],  2'b0};
        b_out  <= {o_rgb565[4:0],   3'b0};
        vs_out <= vs_o;
        hs_out <= hs_o;
        de_out <= de_o;
    end
//HDMI输出二值化图 ，可以在此处切换
   /*always@(posedge pix_clk) begin
        r_out<={proc_rgb565[15:11],3'b0 };
        g_out<={proc_rgb565[10:5],2'b0  };
        b_out<={proc_rgb565[4:0],3'b0   };
        vs_out<=proc_vsync;
        hs_out<=proc_hsync;
        de_out<=proc_de;
    end*/

    image_process #(
        .IMG_WIDTH     ( 1280 ),
        .IMG_HEIGHT    ( 720  )
    ) u_image_process (
        .clk           ( pix_clk                              ),
        .rst_n         ( ddr_init_done & init_done            ),
        .in_vsync      ( vs_o                                 ),
        .in_hsync      ( hs_o                                 ),
        .in_de         ( de_o                                 ),
        .in_r          ( {o_rgb565[15:11], 3'b0}              ),
        .in_g          ( {o_rgb565[10:5],  2'b0}              ),
        .in_b          ( {o_rgb565[4:0],   3'b0}              ),
        .out_vsync     ( proc_vsync                           ),
        .out_hsync     ( proc_hsync                           ),
        .out_de        ( proc_de                              ),
        .out_bin       ( proc_bin                             )
    );

    assign proc_rgb565_o = {proc_bin[7:3], proc_bin[7:2], proc_bin[7:3]};
    assign proc_rgb565   = proc_rgb565_o;

    ethernet_ddr_streamer ethernet_ddr_streamer (
        .video_clk      ( pix_clk      ),
        .video_vsync    ( vs_o         ),
        .video_de       ( de_o         ),
        .video_data     ( o_rgb565     ),
        .rstn_in        ( rstn_out     ), // 保留复位信号
        
        // MAC 层纯数字连线 
        .rgmii_clk      ( rgmii_clk    ),
        .mac_tx_en      ( mac_tx_en    ),
        .mac_tx_data    ( mac_tx_data  ),
        .mac_rx_dv      ( mac_rx_dv    ),
        .mac_rx_data    ( mac_rx_data  ),
       
        
        .stream_active  (              )
    );

    wire vs_o, hs_o, de_o;
    sync_vg sync_vg(                            
        .clk            (  pix_clk              ),
        .rstn           (  ddr_init_done        ),
        .vs_out         (  vs_o                 ),
        .hs_out         (  hs_o                 ),
        .de_out         (  de_re                ), 
        .de_re          (                       )    
    );

     always@(posedge core_clk) begin
        if (!ddr_init_done)
            cnt <= 27'd0;
        else if ( cnt >= TH_1S )
            cnt <= 27'd0;
        else
            cnt <= cnt + 27'd1;
     end

     always @(posedge core_clk) begin
        if (!ddr_init_done)
            heart_beat_led <= 1'd1;
        else if ( cnt >= TH_1S )
            heart_beat_led <= ~heart_beat_led;
     end

endmodule

