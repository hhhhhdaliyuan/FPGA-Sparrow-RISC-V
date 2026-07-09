module gaussian5x5 #(
    parameter IMG_WIDTH = 1280
) (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       in_vsync,
    input  wire       in_hsync,
    input  wire       in_de,
    input  wire [7:0] in_pix,
    output reg        out_vsync,
    output reg        out_hsync,
    output reg        out_de,
    output reg [7:0]  out_pix
);

wire [7:0] line1_data;
wire [7:0] line2_data;
wire [7:0] line3_data;
wire [7:0] line4_data;

reg [11:0] x_cnt;
reg [11:0] y_cnt;

reg in_de_d;
reg in_vsync_d;
wire sof_rise;
wire de_fall;
reg [11:0] x_cnt_d;
reg [7:0]  in_pix_d;

reg [7:0] tap1;
reg [7:0] tap2;
reg [7:0] tap3;
reg [7:0] tap4;

reg [7:0] w00, w01, w02, w03, w04;
reg [7:0] w10, w11, w12, w13, w14;
reg [7:0] w20, w21, w22, w23, w24;
reg [7:0] w30, w31, w32, w33, w34;
reg [7:0] w40, w41, w42, w43, w44;

reg [15:0] gauss_sum;
wire win_valid;
reg  win_valid_d;
reg  vsync_d;
reg  hsync_d;

wire rst;

assign rst = ~rst_n;

assign sof_rise = in_vsync & (~in_vsync_d);
assign de_fall  = in_de_d & (~in_de);
assign win_valid = in_de && (x_cnt >= 12'd4) && (y_cnt >= 12'd4);

wire line1_has_x;
wire line2_has_x;
wire line3_has_x;
wire line4_has_x;
wire gauss_has_x;

assign line1_has_x = (^line1_data === 1'bx);
assign line2_has_x = (^line2_data === 1'bx);
assign line3_has_x = (^line3_data === 1'bx);
assign line4_has_x = (^line4_data === 1'bx);
assign gauss_has_x = (^gauss_sum  === 1'bx);

line_buffer u_line1 (
    .wr_data   (in_pix_d),
    .wr_addr   (x_cnt_d[10:0]),
    .wr_en     (in_de_d),
    .wr_clk    (clk),
    .wr_clk_en (1'b1),
    .wr_rst    (rst),
    .rd_data   (line1_data),
    .rd_addr   (x_cnt[10:0]),
    .rd_clk    (clk),
    .rd_clk_en (1'b1),
    .rd_rst    (rst)
);

line_buffer u_line2 (
    .wr_data   (line1_data),
    .wr_addr   (x_cnt_d[10:0]),
    .wr_en     (in_de_d),
    .wr_clk    (clk),
    .wr_clk_en (1'b1),
    .wr_rst    (rst),
    .rd_data   (line2_data),
    .rd_addr   (x_cnt[10:0]),
    .rd_clk    (clk),
    .rd_clk_en (1'b1),
    .rd_rst    (rst)
);

line_buffer u_line3 (
    .wr_data   (line2_data),
    .wr_addr   (x_cnt_d[10:0]),
    .wr_en     (in_de_d),
    .wr_clk    (clk),
    .wr_clk_en (1'b1),
    .wr_rst    (rst),
    .rd_data   (line3_data),
    .rd_addr   (x_cnt[10:0]),
    .rd_clk    (clk),
    .rd_clk_en (1'b1),
    .rd_rst    (rst)
);

line_buffer u_line4 (
    .wr_data   (line3_data),
    .wr_addr   (x_cnt_d[10:0]),
    .wr_en     (in_de_d),
    .wr_clk    (clk),
    .wr_clk_en (1'b1),
    .wr_rst    (rst),
    .rd_data   (line4_data),
    .rd_addr   (x_cnt[10:0]),
    .rd_clk    (clk),
    .rd_clk_en (1'b1),
    .rd_rst    (rst)
);

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        in_de_d    <= 1'b0;
        in_vsync_d <= 1'b0;
        x_cnt_d    <= 12'd0;
        in_pix_d   <= 8'd0;
        x_cnt      <= 12'd0;
        y_cnt      <= 12'd0;

        tap1 <= 8'd0;
        tap2 <= 8'd0;
        tap3 <= 8'd0;
        tap4 <= 8'd0;

        w00 <= 8'd0; w01 <= 8'd0; w02 <= 8'd0; w03 <= 8'd0; w04 <= 8'd0;
        w10 <= 8'd0; w11 <= 8'd0; w12 <= 8'd0; w13 <= 8'd0; w14 <= 8'd0;
        w20 <= 8'd0; w21 <= 8'd0; w22 <= 8'd0; w23 <= 8'd0; w24 <= 8'd0;
        w30 <= 8'd0; w31 <= 8'd0; w32 <= 8'd0; w33 <= 8'd0; w34 <= 8'd0;
        w40 <= 8'd0; w41 <= 8'd0; w42 <= 8'd0; w43 <= 8'd0; w44 <= 8'd0;

        gauss_sum <= 16'd0;
        win_valid_d <= 1'b0;
        vsync_d <= 1'b0;
        hsync_d <= 1'b0;

        out_vsync <= 1'b0;
        out_hsync <= 1'b0;
        out_de    <= 1'b0;
        out_pix   <= 8'd0;
    end else begin
        in_de_d    <= in_de;
        in_vsync_d <= in_vsync;
        x_cnt_d    <= x_cnt;
        in_pix_d   <= in_pix;

        if (sof_rise) begin
            x_cnt <= 12'd0;
            y_cnt <= 12'd0;
        end else begin
            if (in_de) begin
                x_cnt <= x_cnt + 12'd1;
            end
            if (de_fall) begin
                x_cnt <= 12'd0;
                y_cnt <= y_cnt + 12'd1;
            end
        end

        if (in_de) begin
    `ifndef SYNTHESIS
            tap1 <= line1_has_x ? 8'd0 : line1_data;
            tap2 <= line2_has_x ? 8'd0 : line2_data;
            tap3 <= line3_has_x ? 8'd0 : line3_data;
            tap4 <= line4_has_x ? 8'd0 : line4_data;
    `else
            tap1 <= line1_data;
            tap2 <= line2_data;
            tap3 <= line3_data;
            tap4 <= line4_data;
    `endif

            w00 <= w01; w01 <= w02; w02 <= w03; w03 <= w04; w04 <= tap4;
            w10 <= w11; w11 <= w12; w12 <= w13; w13 <= w14; w14 <= tap3;
            w20 <= w21; w21 <= w22; w22 <= w23; w23 <= w24; w24 <= tap2;
            w30 <= w31; w31 <= w32; w32 <= w33; w33 <= w34; w34 <= tap1;
            w40 <= w41; w41 <= w42; w42 <= w43; w43 <= w44; w44 <= in_pix;
        end

        gauss_sum <=
            (w00 + (w01 << 2) + (w02 * 6) + (w03 << 2) + w04) +
            ((w10 << 2) + (w11 << 4) + (w12 * 24) + (w13 << 4) + (w14 << 2)) +
            ((w20 * 6) + (w21 * 24) + (w22 * 36) + (w23 * 24) + (w24 * 6)) +
            ((w30 << 2) + (w31 << 4) + (w32 * 24) + (w33 << 4) + (w34 << 2)) +
            (w40 + (w41 << 2) + (w42 * 6) + (w43 << 2) + w44);

        win_valid_d <= win_valid;
        vsync_d <= in_vsync;
        hsync_d <= in_hsync;

        out_vsync <= vsync_d;
        out_hsync <= hsync_d;
        out_de    <= win_valid_d;
    `ifndef SYNTHESIS
        out_pix   <= win_valid_d ? (gauss_has_x ? 8'd0 : gauss_sum[15:8]) : 8'd0;
    `else
        out_pix   <= win_valid_d ? gauss_sum[15:8] : 8'd0;
    `endif
    end
end

endmodule
