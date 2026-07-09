`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Stream DDR video data to PC over UDP.
//////////////////////////////////////////////////////////////////////////////////

module ethernet_ddr_streamer #(
    parameter       LOCAL_MAC = 48'ha0_b1_c2_d3_e1_e1,
    parameter       LOCAL_IP  = 32'hC0_A8_01_0B,
    parameter       LOCAL_PORT = 16'h1F90,
    parameter       DEST_MAC   = 48'hFF_FF_FF_FF_FF_FF,
    parameter       DEST_IP    = 32'hC0_A8_01_69,
    parameter       DEST_PORT  = 16'h1F90,
    parameter       FIFO_ADDR_WIDTH = 10,
    parameter       UDP_PAYLOAD_BYTES = 16'd1400
)(
    input                          video_clk,
    input                          video_vsync,
    input                          video_de,
    input      [15:0]              video_data,
    input                          rstn_in,

    // ====== 纯数字 MAC 接口 ======
    input                          rgmii_clk,
    output                         mac_tx_en,
    output     [7:0]               mac_tx_data,
    input                          mac_rx_dv,
    input      [7:0]               mac_rx_data,
    // ===================================
    output                         stream_active
);

    localparam HEADER_BYTES  = 16'd8;
    localparam TOTAL_BYTES   = UDP_PAYLOAD_BYTES + HEADER_BYTES;
    localparam PACKET_PIXELS  = UDP_PAYLOAD_BYTES >> 1;

    wire        rgmii_clk;
    wire        rgmii_clk_90p;
    wire        rgmii_pll_lock;
    wire        rstn = rstn_in ;

    wire               mac_rx_dv;
    wire [7:0]         mac_rx_data;
    wire               mac_tx_en;
    wire [7:0]         mac_tx_data;

   

    // Frame counter for packet metadata.
    reg  [15:0]        frame_id_video = 16'd0;
    reg                 video_vsync_d  = 1'b0;
    always @(posedge video_clk) begin
        video_vsync_d <= video_vsync;
        if (video_vsync && !video_vsync_d)
            frame_id_video <= frame_id_video + 16'd1;
    end

    reg  [15:0]        frame_id_sync_1 = 16'd0;
    reg  [15:0]        frame_id_sync_2 = 16'd0;
    always @(posedge rgmii_clk) begin
        frame_id_sync_1 <= frame_id_video;
        frame_id_sync_2 <= frame_id_sync_1;
    end

    // DDR/video side to packet FIFO, store pixels as 16-bit words.
    wire [15:0]        fifo_wr_data   = video_data;
    wire [15:0]        fifo_rd_data;
    wire               fifo_full;
    wire               fifo_almost_full;
    wire               fifo_empty;
    wire               fifo_almost_empty;
    wire [10:0]        fifo_wr_level;
    wire [10:0]        fifo_rd_level;
    wire               fifo_rd_en;
    wire               fifo_wr_en = video_de && !fifo_full;

    ipsxb_distributed_fifo u_pixel_fifo (
        .wr_data        ( fifo_wr_data     ),
        .wr_en          ( fifo_wr_en       ),
        .wr_clk         ( video_clk        ),
        .wr_rst         ( ~rstn            ),
        .full           ( fifo_full        ),
        .almost_full    ( fifo_almost_full ),
        .wr_water_level ( fifo_wr_level    ),
        .rd_data        ( fifo_rd_data     ),
        .rd_en          ( fifo_rd_en       ),
        .rd_clk         ( rgmii_clk        ),
        .rd_rst         ( ~rstn            ),
        .empty          ( fifo_empty       ),
        .almost_empty   ( fifo_almost_empty),
        .rd_water_level ( fifo_rd_level    )
    );

    // UDP application sender.
    reg                arp_req_r = 1'b0;
    reg                app_data_request_r = 1'b0;
    reg                app_data_in_valid_r = 1'b0;
    reg [15:0]         byte_index = 16'd0;
    reg [15:0]         packet_seq = 16'd0;
    reg [15:0]         pixel_hold = 16'd0;
    reg [1:0]          tx_state = 2'd0;

    localparam TX_ARP   = 2'd0;
    localparam TX_REQ   = 2'd1;
    localparam TX_SEND  = 2'd2;
    localparam TX_WAIT  = 2'd3;

    wire               udp_send_ack;
    wire               arp_found;
    wire               mac_not_exist;
    wire               mac_send_end;
    wire [7:0]         udp_rec_rdata;
    wire [15:0]        udp_rec_data_length;
    wire               udp_rec_data_valid;

    wire [7:0]         app_data_in;
    assign app_data_in = (byte_index < HEADER_BYTES) ?
                         (byte_index == 16'd0 ? 8'hA5 :
                          byte_index == 16'd1 ? 8'h5A :
                          byte_index == 16'd2 ? frame_id_sync_2[15:8] :
                          byte_index == 16'd3 ? frame_id_sync_2[7:0]  :
                          byte_index == 16'd4 ? packet_seq[15:8]       :
                          byte_index == 16'd5 ? packet_seq[7:0]        :
                          byte_index == 16'd6 ? UDP_PAYLOAD_BYTES[15:8] :
                                                 UDP_PAYLOAD_BYTES[7:0]) :
                         ((byte_index[0] == 1'b0) ? fifo_rd_data[15:8] : pixel_hold[7:0]);

    assign fifo_rd_en = (tx_state == TX_SEND) && (byte_index >= HEADER_BYTES) && (byte_index[0] == 1'b0);
    assign stream_active = (tx_state != TX_ARP);


    // 1. 在状态机前面定义一个计数器寄存器
   reg [31:0] wait_cnt = 32'd0;
   localparam ONE_SECOND = 32'd125_000_000; // 假设 rgmii_clk 是 125MHz

    always @(posedge rgmii_clk) begin
        if (!rstn) begin
            tx_state            <= TX_ARP;
            arp_req_r           <= 1'b0;
            app_data_request_r  <= 1'b0;
            app_data_in_valid_r <= 1'b0;
            byte_index          <= 16'd0;
            packet_seq          <= 16'd0;
            pixel_hold          <= 16'd0;
        end else begin
            case (tx_state)
               
                 TX_ARP: begin
                        app_data_request_r <= 1'b0;
                        app_data_in_valid_r <= 1'b0;
                        byte_index <= 16'd0;

                      // 定时 1 秒触发一次单脉冲
                     if (wait_cnt >= ONE_SECOND) begin
                     arp_req_r <= 1'b1;      // 计数器满了，拉高 1 拍产生单脉冲
                      wait_cnt <= 32'd0;      // 清零计数器
                  end else begin
                    arp_req_r <= 1'b0;      // 平时保持低电平
                     wait_cnt <= wait_cnt + 1'b1;
                end

                // 等待底层的 found 信号反馈
                  if (arp_found) begin
                    arp_req_r <= 1'b0;      // 拉低
                    wait_cnt  <= 32'd0;     // 清零给后续可能的逻辑备用
                    tx_state  <= TX_REQ;    // 握手成功，进入发图阶段
                end
            end

                TX_REQ: begin
                    arp_req_r <= 1'b0;
                    app_data_request_r <= 1'b1;
                    app_data_in_valid_r <= 1'b0;
                    if (fifo_rd_level >= PACKET_PIXELS) begin
                        if (udp_send_ack) begin
                            app_data_request_r <= 1'b0;
                            app_data_in_valid_r <= 1'b1;
                            byte_index <= 16'd0;
                            tx_state <= TX_SEND;
                        end
                    end else begin
                        app_data_request_r <= 1'b0;
                    end
                end

                TX_SEND: begin
                    app_data_request_r <= 1'b0;
                    app_data_in_valid_r <= 1'b1;

                    if (byte_index >= HEADER_BYTES && byte_index[0] == 1'b0)
                        pixel_hold <= fifo_rd_data;

                    if (byte_index == (TOTAL_BYTES - 16'd1)) begin
                        tx_state <= TX_WAIT;
                        app_data_in_valid_r <= 1'b0;
                    end else begin
                        byte_index <= byte_index + 16'd1;
                    end
                end

                TX_WAIT: begin
                    app_data_request_r <= 1'b0;
                    app_data_in_valid_r <= 1'b0;
                    if (mac_send_end) begin
                        packet_seq <= packet_seq + 16'd1;
                        byte_index <= 16'd0;
                        tx_state <= TX_REQ;
                    end
                end

                default: begin
                    tx_state <= TX_ARP;
                end
            endcase
        end
    end

    udp_ip_mac_top #(
        .LOCAL_MAC ( LOCAL_MAC ),
        .LOCAL_IP  ( LOCAL_IP  ),
        .LOCL_PORT ( LOCAL_PORT),
        .DEST_MAC  ( DEST_MAC  ),
        .DEST_IP   ( DEST_IP   ),
        .DEST_PORT ( DEST_PORT )
    ) u_udp_ip_mac_top (
        .rgmii_clk           ( rgmii_clk          ),
        .rstn                ( rstn               ),
        .app_data_in_valid   ( app_data_in_valid_r),
        .app_data_in         ( app_data_in        ),
        .app_data_length     ( TOTAL_BYTES        ),
        .app_data_request    ( app_data_request_r ),
        .udp_send_ack        ( udp_send_ack       ),
        .arp_req             ( arp_req_r          ),
        .arp_found           ( arp_found          ),
        .mac_not_exist       ( mac_not_exist      ),
        .mac_send_end        ( mac_send_end       ),
        .udp_rec_rdata       ( udp_rec_rdata      ),
        .udp_rec_data_length ( udp_rec_data_length),
        .udp_rec_data_valid  ( udp_rec_data_valid ),
        .mac_data_valid      ( mac_tx_en          ),
        .mac_tx_data         ( mac_tx_data        ),
        .rx_en               ( mac_rx_dv          ),
        .mac_rx_datain       ( mac_rx_data        )
    );

endmodule