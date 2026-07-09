module morph_close_25x3 #(
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

morph_rect_25x3 #(
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

morph_rect_25x3 #(
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


module morph_rect_25x3 #(
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

reg r0_0; reg r0_1; reg r0_2; reg r0_3; reg r0_4; reg r0_5; reg r0_6; reg r0_7; reg r0_8; reg r0_9;
reg r0_10; reg r0_11; reg r0_12; reg r0_13; reg r0_14; reg r0_15; reg r0_16; reg r0_17; reg r0_18; reg r0_19;
reg r0_20; reg r0_21; reg r0_22; reg r0_23; reg r0_24;

reg r1_0; reg r1_1; reg r1_2; reg r1_3; reg r1_4; reg r1_5; reg r1_6; reg r1_7; reg r1_8; reg r1_9;
reg r1_10; reg r1_11; reg r1_12; reg r1_13; reg r1_14; reg r1_15; reg r1_16; reg r1_17; reg r1_18; reg r1_19;
reg r1_20; reg r1_21; reg r1_22; reg r1_23; reg r1_24;

reg r2_0; reg r2_1; reg r2_2; reg r2_3; reg r2_4; reg r2_5; reg r2_6; reg r2_7; reg r2_8; reg r2_9;
reg r2_10; reg r2_11; reg r2_12; reg r2_13; reg r2_14; reg r2_15; reg r2_16; reg r2_17; reg r2_18; reg r2_19;
reg r2_20; reg r2_21; reg r2_22; reg r2_23; reg r2_24;

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
assign win_valid = in_de && (x_cnt >= 12'd24) && (y_cnt >= 12'd2);

assign op_or_w =
    r0_0 | r0_1 | r0_2 | r0_3 | r0_4 | r0_5 | r0_6 | r0_7 | r0_8 | r0_9 |
    r0_10 | r0_11 | r0_12 | r0_13 | r0_14 | r0_15 | r0_16 | r0_17 | r0_18 | r0_19 |
    r0_20 | r0_21 | r0_22 | r0_23 | r0_24 |
    r1_0 | r1_1 | r1_2 | r1_3 | r1_4 | r1_5 | r1_6 | r1_7 | r1_8 | r1_9 |
    r1_10 | r1_11 | r1_12 | r1_13 | r1_14 | r1_15 | r1_16 | r1_17 | r1_18 | r1_19 |
    r1_20 | r1_21 | r1_22 | r1_23 | r1_24 |
    r2_0 | r2_1 | r2_2 | r2_3 | r2_4 | r2_5 | r2_6 | r2_7 | r2_8 | r2_9 |
    r2_10 | r2_11 | r2_12 | r2_13 | r2_14 | r2_15 | r2_16 | r2_17 | r2_18 | r2_19 |
    r2_20 | r2_21 | r2_22 | r2_23 | r2_24;

assign op_and_w =
    r0_0 & r0_1 & r0_2 & r0_3 & r0_4 & r0_5 & r0_6 & r0_7 & r0_8 & r0_9 &
    r0_10 & r0_11 & r0_12 & r0_13 & r0_14 & r0_15 & r0_16 & r0_17 & r0_18 & r0_19 &
    r0_20 & r0_21 & r0_22 & r0_23 & r0_24 &
    r1_0 & r1_1 & r1_2 & r1_3 & r1_4 & r1_5 & r1_6 & r1_7 & r1_8 & r1_9 &
    r1_10 & r1_11 & r1_12 & r1_13 & r1_14 & r1_15 & r1_16 & r1_17 & r1_18 & r1_19 &
    r1_20 & r1_21 & r1_22 & r1_23 & r1_24 &
    r2_0 & r2_1 & r2_2 & r2_3 & r2_4 & r2_5 & r2_6 & r2_7 & r2_8 & r2_9 &
    r2_10 & r2_11 & r2_12 & r2_13 & r2_14 & r2_15 & r2_16 & r2_17 & r2_18 & r2_19 &
    r2_20 & r2_21 & r2_22 & r2_23 & r2_24;

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
        r0_10 <= 1'b0; r0_11 <= 1'b0; r0_12 <= 1'b0; r0_13 <= 1'b0; r0_14 <= 1'b0;
        r0_15 <= 1'b0; r0_16 <= 1'b0; r0_17 <= 1'b0; r0_18 <= 1'b0; r0_19 <= 1'b0;
        r0_20 <= 1'b0; r0_21 <= 1'b0; r0_22 <= 1'b0; r0_23 <= 1'b0; r0_24 <= 1'b0;

        r1_0 <= 1'b0; r1_1 <= 1'b0; r1_2 <= 1'b0; r1_3 <= 1'b0; r1_4 <= 1'b0;
        r1_5 <= 1'b0; r1_6 <= 1'b0; r1_7 <= 1'b0; r1_8 <= 1'b0; r1_9 <= 1'b0;
        r1_10 <= 1'b0; r1_11 <= 1'b0; r1_12 <= 1'b0; r1_13 <= 1'b0; r1_14 <= 1'b0;
        r1_15 <= 1'b0; r1_16 <= 1'b0; r1_17 <= 1'b0; r1_18 <= 1'b0; r1_19 <= 1'b0;
        r1_20 <= 1'b0; r1_21 <= 1'b0; r1_22 <= 1'b0; r1_23 <= 1'b0; r1_24 <= 1'b0;

        r2_0 <= 1'b0; r2_1 <= 1'b0; r2_2 <= 1'b0; r2_3 <= 1'b0; r2_4 <= 1'b0;
        r2_5 <= 1'b0; r2_6 <= 1'b0; r2_7 <= 1'b0; r2_8 <= 1'b0; r2_9 <= 1'b0;
        r2_10 <= 1'b0; r2_11 <= 1'b0; r2_12 <= 1'b0; r2_13 <= 1'b0; r2_14 <= 1'b0;
        r2_15 <= 1'b0; r2_16 <= 1'b0; r2_17 <= 1'b0; r2_18 <= 1'b0; r2_19 <= 1'b0;
        r2_20 <= 1'b0; r2_21 <= 1'b0; r2_22 <= 1'b0; r2_23 <= 1'b0; r2_24 <= 1'b0;

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
            r0_5 <= r0_6; r0_6 <= r0_7; r0_7 <= r0_8; r0_8 <= r0_9; r0_9 <= r0_10;
            r0_10 <= r0_11; r0_11 <= r0_12; r0_12 <= r0_13; r0_13 <= r0_14; r0_14 <= r0_15;
            r0_15 <= r0_16; r0_16 <= r0_17; r0_17 <= r0_18; r0_18 <= r0_19; r0_19 <= r0_20;
            r0_20 <= r0_21; r0_21 <= r0_22; r0_22 <= r0_23; r0_23 <= r0_24; r0_24 <= tap2;

            r1_0 <= r1_1; r1_1 <= r1_2; r1_2 <= r1_3; r1_3 <= r1_4; r1_4 <= r1_5;
            r1_5 <= r1_6; r1_6 <= r1_7; r1_7 <= r1_8; r1_8 <= r1_9; r1_9 <= r1_10;
            r1_10 <= r1_11; r1_11 <= r1_12; r1_12 <= r1_13; r1_13 <= r1_14; r1_14 <= r1_15;
            r1_15 <= r1_16; r1_16 <= r1_17; r1_17 <= r1_18; r1_18 <= r1_19; r1_19 <= r1_20;
            r1_20 <= r1_21; r1_21 <= r1_22; r1_22 <= r1_23; r1_23 <= r1_24; r1_24 <= tap1;

            r2_0 <= r2_1; r2_1 <= r2_2; r2_2 <= r2_3; r2_3 <= r2_4; r2_4 <= r2_5;
            r2_5 <= r2_6; r2_6 <= r2_7; r2_7 <= r2_8; r2_8 <= r2_9; r2_9 <= r2_10;
            r2_10 <= r2_11; r2_11 <= r2_12; r2_12 <= r2_13; r2_13 <= r2_14; r2_14 <= r2_15;
            r2_15 <= r2_16; r2_16 <= r2_17; r2_17 <= r2_18; r2_18 <= r2_19; r2_19 <= r2_20;
            r2_20 <= r2_21; r2_21 <= r2_22; r2_22 <= r2_23; r2_23 <= r2_24; r2_24 <= in_bin;
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
