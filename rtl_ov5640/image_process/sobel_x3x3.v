module sobel_x3x3 #(
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

reg [11:0] x_cnt;
reg [11:0] y_cnt;

reg in_de_d;
reg in_vsync_d;
wire sof_rise;
wire de_fall;

reg [7:0] tap1;
reg [7:0] tap2;

reg [7:0] w00, w01, w02;
reg [7:0] w10, w11, w12;
reg [7:0] w20, w21, w22;

wire win_valid;
reg  win_valid_d;
reg  vsync_d;
reg  hsync_d;

wire rst;

assign rst = ~rst_n;

wire signed [11:0] gx_pos_w;
wire signed [11:0] gx_neg_w;
wire signed [12:0] gx_val_w;
wire [12:0] gx_abs_w;

assign sof_rise = in_vsync & (~in_vsync_d);
assign de_fall  = in_de_d & (~in_de);
assign win_valid = in_de && (x_cnt >= 12'd2) && (y_cnt >= 12'd2);

assign gx_pos_w = $signed({1'b0, w02}) + $signed({1'b0, w22}) + $signed({1'b0, w12, 1'b0});
assign gx_neg_w = $signed({1'b0, w00}) + $signed({1'b0, w20}) + $signed({1'b0, w10, 1'b0});
assign gx_val_w = gx_pos_w - gx_neg_w;
assign gx_abs_w = gx_val_w[12] ? (~gx_val_w + 13'd1) : gx_val_w[12:0];

line_buffer u_line1 (
    .wr_data   (in_pix),
    .wr_addr   (x_cnt[10:0]),
    .wr_en     (in_de),
    .wr_clk    (clk),
    .wr_clk_en (in_de),
    .wr_rst    (rst),
    .rd_data   (line1_data),
    .rd_addr   (x_cnt[10:0]),
    .rd_clk    (clk),
    .rd_clk_en (in_de),
    .rd_rst    (rst)
);

line_buffer u_line2 (
    .wr_data   (line1_data),
    .wr_addr   (x_cnt[10:0]),
    .wr_en     (in_de),
    .wr_clk    (clk),
    .wr_clk_en (in_de),
    .wr_rst    (rst),
    .rd_data   (line2_data),
    .rd_addr   (x_cnt[10:0]),
    .rd_clk    (clk),
    .rd_clk_en (in_de),
    .rd_rst    (rst)
);

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        in_de_d    <= 1'b0;
        in_vsync_d <= 1'b0;
        x_cnt      <= 12'd0;
        y_cnt      <= 12'd0;

        tap1 <= 8'd0;
        tap2 <= 8'd0;

        w00 <= 8'd0; w01 <= 8'd0; w02 <= 8'd0;
        w10 <= 8'd0; w11 <= 8'd0; w12 <= 8'd0;
        w20 <= 8'd0; w21 <= 8'd0; w22 <= 8'd0;

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
            tap1 <= line1_data;
            tap2 <= line2_data;

            w00 <= w01; w01 <= w02; w02 <= tap2;
            w10 <= w11; w11 <= w12; w12 <= tap1;
            w20 <= w21; w21 <= w22; w22 <= in_pix;
        end

        win_valid_d <= win_valid;
        vsync_d <= in_vsync;
        hsync_d <= in_hsync;

        out_vsync <= vsync_d;
        out_hsync <= hsync_d;
        out_de    <= win_valid_d;

        if (win_valid_d) begin
            if (gx_abs_w > 13'd255)
                out_pix <= 8'd255;
            else
                out_pix <= gx_abs_w[7:0];
        end else begin
            out_pix <= 8'd0;
        end
    end
end

endmodule
