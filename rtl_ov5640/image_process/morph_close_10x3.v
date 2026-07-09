module morph_close_10x3 #(
    parameter IMG_WIDTH = 1280
) (
    input  wire clk,
    input  wire rst_n,
    input  wire in_vsync,
    input  wire in_hsync,
    input  wire in_de,
    input  wire in_bin,
    output wire out_vsync,
    output wire out_hsync,
    output wire out_de,
    output wire out_bin
);

wire d_vsync;
wire d_hsync;
wire d_de;
wire d_bin;

morph_rect_10x3 #(
    .IMG_WIDTH (IMG_WIDTH),
    .IS_DILATE (1)
) u_dilate (
    .clk      (clk),
    .rst_n    (rst_n),
    .in_vsync (in_vsync),
    .in_hsync (in_hsync),
    .in_de    (in_de),
    .in_bin   (in_bin),
    .out_vsync(d_vsync),
    .out_hsync(d_hsync),
    .out_de   (d_de),
    .out_bin  (d_bin)
);

morph_rect_10x3 #(
    .IMG_WIDTH (IMG_WIDTH),
    .IS_DILATE (0)
) u_erode (
    .clk      (clk),
    .rst_n    (rst_n),
    .in_vsync (d_vsync),
    .in_hsync (d_hsync),
    .in_de    (d_de),
    .in_bin   (d_bin),
    .out_vsync(out_vsync),
    .out_hsync(out_hsync),
    .out_de   (out_de),
    .out_bin  (out_bin)
);

endmodule


module morph_rect_10x3 #(
    parameter IMG_WIDTH = 1280,
    parameter IS_DILATE = 1
) (
    input  wire clk,
    input  wire rst_n,
    input  wire in_vsync,
    input  wire in_hsync,
    input  wire in_de,
    input  wire in_bin,
    output reg  out_vsync,
    output reg  out_hsync,
    output reg  out_de,
    output reg  out_bin
);

wire [7:0] line1_data;
wire [7:0] line2_data;

reg [11:0] x_cnt;
reg [11:0] y_cnt;
reg in_de_d;
reg in_vsync_d;
wire sof_rise;
wire de_fall;

reg tap1;
reg tap2;

reg r0_0, r0_1, r0_2, r0_3, r0_4, r0_5, r0_6, r0_7, r0_8, r0_9;
reg r1_0, r1_1, r1_2, r1_3, r1_4, r1_5, r1_6, r1_7, r1_8, r1_9;
reg r2_0, r2_1, r2_2, r2_3, r2_4, r2_5, r2_6, r2_7, r2_8, r2_9;

wire win_valid;
wire op_or_w;
wire op_and_w;
reg  win_valid_d;
reg  vsync_d;
reg  hsync_d;

wire rst;

assign rst = ~rst_n;

assign sof_rise = in_vsync & (~in_vsync_d);
assign de_fall  = in_de_d & (~in_de);
assign win_valid = in_de && (x_cnt >= 12'd9) && (y_cnt >= 12'd2);

assign op_or_w =
    r0_0 | r0_1 | r0_2 | r0_3 | r0_4 | r0_5 | r0_6 | r0_7 | r0_8 | r0_9 |
    r1_0 | r1_1 | r1_2 | r1_3 | r1_4 | r1_5 | r1_6 | r1_7 | r1_8 | r1_9 |
    r2_0 | r2_1 | r2_2 | r2_3 | r2_4 | r2_5 | r2_6 | r2_7 | r2_8 | r2_9;

assign op_and_w =
    r0_0 & r0_1 & r0_2 & r0_3 & r0_4 & r0_5 & r0_6 & r0_7 & r0_8 & r0_9 &
    r1_0 & r1_1 & r1_2 & r1_3 & r1_4 & r1_5 & r1_6 & r1_7 & r1_8 & r1_9 &
    r2_0 & r2_1 & r2_2 & r2_3 & r2_4 & r2_5 & r2_6 & r2_7 & r2_8 & r2_9;

line_buffer u_line1 (
    .wr_data   ({7'b0, in_bin}),
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

        tap1 <= 1'b0;
        tap2 <= 1'b0;

        r0_0 <= 1'b0; r0_1 <= 1'b0; r0_2 <= 1'b0; r0_3 <= 1'b0; r0_4 <= 1'b0;
        r0_5 <= 1'b0; r0_6 <= 1'b0; r0_7 <= 1'b0; r0_8 <= 1'b0; r0_9 <= 1'b0;

        r1_0 <= 1'b0; r1_1 <= 1'b0; r1_2 <= 1'b0; r1_3 <= 1'b0; r1_4 <= 1'b0;
        r1_5 <= 1'b0; r1_6 <= 1'b0; r1_7 <= 1'b0; r1_8 <= 1'b0; r1_9 <= 1'b0;

        r2_0 <= 1'b0; r2_1 <= 1'b0; r2_2 <= 1'b0; r2_3 <= 1'b0; r2_4 <= 1'b0;
        r2_5 <= 1'b0; r2_6 <= 1'b0; r2_7 <= 1'b0; r2_8 <= 1'b0; r2_9 <= 1'b0;

        win_valid_d <= 1'b0;
        vsync_d <= 1'b0;
        hsync_d <= 1'b0;

        out_vsync <= 1'b0;
        out_hsync <= 1'b0;
        out_de    <= 1'b0;
        out_bin   <= 1'b0;
    end else begin
        in_de_d    <= in_de;
        in_vsync_d <= in_vsync;

        if (sof_rise) begin
            x_cnt <= 12'd0;
            y_cnt <= 12'd0;
        end else begin
            if (in_de)
                x_cnt <= x_cnt + 12'd1;
            if (de_fall) begin
                x_cnt <= 12'd0;
                y_cnt <= y_cnt + 12'd1;
            end
        end

        if (in_de) begin
            tap1 <= line1_data[0];
            tap2 <= line2_data[0];

            r0_0 <= r0_1; r0_1 <= r0_2; r0_2 <= r0_3; r0_3 <= r0_4; r0_4 <= r0_5;
            r0_5 <= r0_6; r0_6 <= r0_7; r0_7 <= r0_8; r0_8 <= r0_9; r0_9 <= tap2;

            r1_0 <= r1_1; r1_1 <= r1_2; r1_2 <= r1_3; r1_3 <= r1_4; r1_4 <= r1_5;
            r1_5 <= r1_6; r1_6 <= r1_7; r1_7 <= r1_8; r1_8 <= r1_9; r1_9 <= tap1;

            r2_0 <= r2_1; r2_1 <= r2_2; r2_2 <= r2_3; r2_3 <= r2_4; r2_4 <= r2_5;
            r2_5 <= r2_6; r2_6 <= r2_7; r2_7 <= r2_8; r2_8 <= r2_9; r2_9 <= in_bin;
        end

        win_valid_d <= win_valid;
        vsync_d <= in_vsync;
        hsync_d <= in_hsync;

        out_vsync <= vsync_d;
        out_hsync <= hsync_d;
        out_de    <= win_valid_d;

        if (win_valid_d) begin
            if (IS_DILATE)
                out_bin <= op_or_w;
            else
                out_bin <= op_and_w;
        end else begin
            out_bin <= 1'b0;
        end
    end
end

endmodule
