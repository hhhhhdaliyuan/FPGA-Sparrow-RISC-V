module image_process #(
	parameter IMG_WIDTH  = 1920,
	parameter IMG_HEIGHT = 1080,
	parameter EDGE_THR   = 48,
	parameter H_BLUE_MIN = 140,
	parameter H_BLUE_MAX = 191,
	parameter H_GREEN_MIN = 38,
	parameter H_GREEN_MAX = 128,
    // ����������ֵ����
	parameter H_YELLOW_MIN = 25,
	parameter H_YELLOW_MAX = 55,
	parameter S_MIN      = 77,
	parameter V_MIN      = 51,
	parameter HSV_CLOSE_ALIGN_LINES = 6
) (
	input  wire        clk,
	input  wire        rst_n,
	input  wire        in_vsync,
	input  wire        in_hsync,
	input  wire        in_de,
	input  wire [7:0]  in_r,
	input  wire [7:0]  in_g,
	input  wire [7:0]  in_b,
	output wire        out_vsync,
	output wire        out_hsync,
	output wire        out_de,
	output wire [7:0]  out_bin
);
// ports
	// gaussian ports
		wire       gauss_vsync;
		wire       gauss_hsync;
		wire       gauss_de;
		wire [7:0] gauss_pix;
		wire [7:0] gauss_r_pix;
		wire [7:0] gauss_g_pix;
		wire [7:0] gauss_b_pix;
	// gray ports
		wire       gray_vsync;
		wire       gray_hsync;
		wire       gray_de;
		wire [7:0] gray_pix;
	// sobel ports
		wire       sobel_vsync;
		wire       sobel_hsync;
		wire       sobel_de;
		wire [7:0] sobel_pix;
		wire       sobel_bin;

		wire       sobel_close_vsync;
		wire       sobel_close_hsync;
		wire       sobel_close_de;
		wire       sobel_close_bin;

		wire       sobel_ccl_vsync;
		wire       sobel_ccl_hsync;
		wire       sobel_ccl_de;
		wire       sobel_ccl_bin;

		wire       sobel_geo_vsync;
		wire       sobel_geo_hsync;
		wire       sobel_geo_de;
		wire       sobel_geo_bin;

		wire       sobel_pack_vsync;
		wire       sobel_pack_hsync;
		wire       sobel_pack_de;
		wire [7:0] sobel_pack_pix;
	// hsv ports
		wire [7:0] color_h;
		wire [7:0] color_s;
		wire [7:0] color_v;
		wire       color_mask_blue;
		wire       color_mask_green;
        wire       color_mask_yellow; // ������һ��

		reg        color_vsync_d0;
		reg        color_vsync_d1;
		reg        color_vsync_d2;
		reg        color_hsync_d0;
		reg        color_hsync_d1;
		reg        color_hsync_d2;
		reg        color_de_d0;
		reg        color_de_d1;
		reg        color_de_d2;
		reg        color_bin_d0;
		reg        color_bin_d1;
		reg        color_bin_d2;

		wire       hsv_vsync;
		wire       hsv_hsync;
		wire       hsv_de;
		wire       hsv_bin;

		wire       hsv_close_vsync;
		wire       hsv_close_hsync;
		wire       hsv_close_de;
		wire       hsv_close_bin;

		wire       hsv_ccl_vsync;
		wire       hsv_ccl_hsync;
		wire       hsv_ccl_de;
		wire       hsv_ccl_bin;

		wire       hsv_geo_vsync;
		wire       hsv_geo_hsync;
		wire       hsv_geo_de;
		wire       hsv_geo_bin;

		wire       hsv_pack_vsync;
		wire       hsv_pack_hsync;
		wire       hsv_pack_de;
		wire [7:0] hsv_pack_pix;

		reg  [10:0] hsv_align_x_cnt;
		reg         hsv_align_de_d;
		wire [7:0]  hsv_align_in;
		wire [7:0]  hsv_align_0;
		wire [7:0]  hsv_align_1;
		wire [7:0]  hsv_align_2;
		wire [7:0]  hsv_align_3;
		wire [7:0]  hsv_align_4;
		wire [7:0]  hsv_align_5;
		wire [7:0]  hsv_align_sel;
		wire        hsv_align_de;
		wire        hsv_align_bin;
		wire        final_fused_bin;
		wire        final_pack_vsync;
		wire        final_pack_hsync;
		wire        final_pack_de;
		wire [7:0]  final_pack_pix;

//////////////////////////////////////////////////////////
// gaussian rgb
	gaussian5x5 #(
		.IMG_WIDTH(IMG_WIDTH)
	) u_gaussian5x5_r (
		.clk      (clk),
		.rst_n    (rst_n),
		.in_vsync (in_vsync),
		.in_hsync (in_hsync),
		.in_de    (in_de),
		.in_pix   (in_r),
		.out_vsync(gauss_vsync),
		.out_hsync(gauss_hsync),
		.out_de   (gauss_de),
		.out_pix  (gauss_r_pix)
	);

	gaussian5x5 #(
		.IMG_WIDTH(IMG_WIDTH)
	) u_gaussian5x5_g (
		.clk      (clk),
		.rst_n    (rst_n),
		.in_vsync (in_vsync),
		.in_hsync (in_hsync),
		.in_de    (in_de),
		.in_pix   (in_g),
		.out_vsync(),
		.out_hsync(),
		.out_de   (),
		.out_pix  (gauss_g_pix)
	);

	gaussian5x5 #(
		.IMG_WIDTH(IMG_WIDTH)
	) u_gaussian5x5_b (
		.clk      (clk),
		.rst_n    (rst_n),
		.in_vsync (in_vsync),
		.in_hsync (in_hsync),
		.in_de    (in_de),
		.in_pix   (in_b),
		.out_vsync(),
		.out_hsync(),
		.out_de   (),
		.out_pix  (gauss_b_pix)
	);

	assign gauss_pix = (gauss_r_pix + gauss_g_pix + gauss_b_pix + 8'd1) / 8'd3;

// rgb to gray
	rgb2gray u_rgb2gray (
		.clk      (clk),
		.rst_n    (rst_n),
		.in_vsync (gauss_vsync),
		.in_hsync (gauss_hsync),
		.in_de    (gauss_de),
		.in_r     (gauss_r_pix),
		.in_g     (gauss_g_pix),
		.in_b     (gauss_b_pix),
		.out_vsync(gray_vsync),
		.out_hsync(gray_hsync),
		.out_de   (gray_de),
		.out_gray (gray_pix)
	);

// sobel_x
	sobel_x3x3 #(
		.IMG_WIDTH(IMG_WIDTH)
	) u_sobel_x3x3 (
		.clk      (clk),
		.rst_n    (rst_n),
		.in_vsync (gray_vsync),
		.in_hsync (gray_hsync),
		.in_de    (gray_de),
		.in_pix   (gray_pix),
		.out_vsync(sobel_vsync),
		.out_hsync(sobel_hsync),
		.out_de   (sobel_de),
		.out_pix  (sobel_pix)
	);

	assign sobel_bin = (sobel_pix >= EDGE_THR);

// rgb to hsv
	rgb_hsv #(
		.H_BLUE_MIN  (H_BLUE_MIN),
		.H_BLUE_MAX  (H_BLUE_MAX),
		.H_GREEN_MIN (H_GREEN_MIN),
		.H_GREEN_MAX (H_GREEN_MAX),
        .H_YELLOW_MIN(H_YELLOW_MIN), // �����ɫ��ֵ����
        .H_YELLOW_MAX(H_YELLOW_MAX), // �����ɫ��ֵ����
		.S_MIN       (S_MIN),
		.V_MIN       (V_MIN)
	) u_rgb_hsv (
		.r          (in_r),
		.g          (in_g),
		.b          (in_b),
		.h          (color_h),
		.s          (color_s),
		.v          (color_v),
		.mask_blue  (color_mask_blue),
		.mask_green (color_mask_green),
        .mask_yellow(color_mask_yellow) // ���ӻ�ɫ�������
	);

	always @(posedge clk or negedge rst_n) begin
		if (!rst_n) begin
			color_vsync_d0 <= 1'b0;
			color_vsync_d1 <= 1'b0;
			color_vsync_d2 <= 1'b0;
			color_hsync_d0 <= 1'b0;
			color_hsync_d1 <= 1'b0;
			color_hsync_d2 <= 1'b0;
			color_de_d0    <= 1'b0;
			color_de_d1    <= 1'b0;
			color_de_d2    <= 1'b0;
			color_bin_d0   <= 1'b0;
			color_bin_d1   <= 1'b0;
			color_bin_d2   <= 1'b0;
		end else begin
			color_vsync_d0 <= in_vsync;
			color_vsync_d1 <= color_vsync_d0;
			color_vsync_d2 <= color_vsync_d1;

			color_hsync_d0 <= in_hsync;
			color_hsync_d1 <= color_hsync_d0;
			color_hsync_d2 <= color_hsync_d1;

			color_de_d0 <= in_de;
			color_de_d1 <= color_de_d0;
			color_de_d2 <= color_de_d1;

			color_bin_d0 <= in_de & (color_mask_blue | color_mask_green | color_mask_yellow | (color_s < 8'd30 & color_v > 8'd180));  // +白色亮度检测(覆盖绿牌渐变)
			color_bin_d1 <= color_bin_d0;
			color_bin_d2 <= color_bin_d1;
		end
	end

// morphological closing --- sobel
	morph_close_25x3 #(
		.IMG_WIDTH(IMG_WIDTH)
	) u_sobel_close_25x3 (
		.clk      (clk),
		.rst_n    (rst_n),
		.in_vsync (sobel_vsync),
		.in_hsync (sobel_hsync),
		.in_de    (sobel_de),
		.in_bin   (sobel_bin),
		.out_vsync(sobel_close_vsync),
		.out_hsync(sobel_close_hsync),
		.out_de   (sobel_close_de),
		.out_bin  (sobel_close_bin)
	);

// sobel out
	binary_frame_out u_sobel_binary_frame_out (
		.clk      (clk),
		.rst_n    (rst_n),
		.in_vsync (sobel_close_vsync),
		.in_hsync (sobel_close_hsync),
		.in_de    (sobel_close_de),
		.in_bin   (sobel_close_bin),
		.in_valid (1'b1),
		.out_vsync(sobel_pack_vsync),
		.out_hsync(sobel_pack_hsync),
		.out_de   (sobel_pack_de),
		.out_pix  (sobel_pack_pix)
	);

	assign hsv_vsync = color_vsync_d2;
	assign hsv_hsync = color_hsync_d2;
	assign hsv_de    = color_de_d2;
	assign hsv_bin   = color_bin_d2;

// morphological closing --- hsv
	morph_close_25x3 #(
		.IMG_WIDTH(IMG_WIDTH)
	) u_hsv_close_25x3 (
		.clk      (clk),
		.rst_n    (rst_n),
		.in_vsync (hsv_vsync),
		.in_hsync (hsv_hsync),
		.in_de    (hsv_de),
		.in_bin   (hsv_bin),
		.out_vsync(hsv_close_vsync),
		.out_hsync(hsv_close_hsync),
		.out_de   (hsv_close_de),
		.out_bin  (hsv_close_bin)
	);

// hsv align
	assign hsv_align_in = {6'b0, hsv_close_de, hsv_close_bin};

	always @(posedge clk or negedge rst_n) begin
		if (!rst_n) begin
			hsv_align_x_cnt <= 11'd0;
			hsv_align_de_d  <= 1'b0;
		end else begin
			hsv_align_de_d <= hsv_close_de;
			if (hsv_close_de) begin
				if (hsv_align_x_cnt == IMG_WIDTH - 1) begin
					hsv_align_x_cnt <= 11'd0;
				end else begin
					hsv_align_x_cnt <= hsv_align_x_cnt + 11'd1;
				end
			end else if (hsv_align_de_d) begin
				hsv_align_x_cnt <= 11'd0;
			end
		end
	end

	line_buffer u_hsv_align_lb0 (
		.wr_data   (hsv_align_in),
		.wr_addr   (hsv_align_x_cnt),
		.wr_en     (hsv_close_de),
		.wr_clk    (clk),
		.wr_clk_en (hsv_close_de),
		.wr_rst    (~rst_n),
		.rd_data   (hsv_align_0),
		.rd_addr   (hsv_align_x_cnt),
		.rd_clk    (clk),
		.rd_clk_en (hsv_close_de),
		.rd_rst    (~rst_n)
	);

	line_buffer u_hsv_align_lb1 (
		.wr_data   (hsv_align_0),
		.wr_addr   (hsv_align_x_cnt),
		.wr_en     (hsv_close_de),
		.wr_clk    (clk),
		.wr_clk_en (hsv_close_de),
		.wr_rst    (~rst_n),
		.rd_data   (hsv_align_1),
		.rd_addr   (hsv_align_x_cnt),
		.rd_clk    (clk),
		.rd_clk_en (hsv_close_de),
		.rd_rst    (~rst_n)
	);

	line_buffer u_hsv_align_lb2 (
		.wr_data   (hsv_align_1),
		.wr_addr   (hsv_align_x_cnt),
		.wr_en     (hsv_close_de),
		.wr_clk    (clk),
		.wr_clk_en (hsv_close_de),
		.wr_rst    (~rst_n),
		.rd_data   (hsv_align_2),
		.rd_addr   (hsv_align_x_cnt),
		.rd_clk    (clk),
		.rd_clk_en (hsv_close_de),
		.rd_rst    (~rst_n)
	);

	line_buffer u_hsv_align_lb3 (
		.wr_data   (hsv_align_2),
		.wr_addr   (hsv_align_x_cnt),
		.wr_en     (hsv_close_de),
		.wr_clk    (clk),
		.wr_clk_en (hsv_close_de),
		.wr_rst    (~rst_n),
		.rd_data   (hsv_align_3),
		.rd_addr   (hsv_align_x_cnt),
		.rd_clk    (clk),
		.rd_clk_en (hsv_close_de),
		.rd_rst    (~rst_n)
	);

	line_buffer u_hsv_align_lb4 (
		.wr_data   (hsv_align_3),
		.wr_addr   (hsv_align_x_cnt),
		.wr_en     (hsv_close_de),
		.wr_clk    (clk),
		.wr_clk_en (hsv_close_de),
		.wr_rst    (~rst_n),
		.rd_data   (hsv_align_4),
		.rd_addr   (hsv_align_x_cnt),
		.rd_clk    (clk),
		.rd_clk_en (hsv_close_de),
		.rd_rst    (~rst_n)
	);

	line_buffer u_hsv_align_lb5 (
		.wr_data   (hsv_align_4),
		.wr_addr   (hsv_align_x_cnt),
		.wr_en     (hsv_close_de),
		.wr_clk    (clk),
		.wr_clk_en (hsv_close_de),
		.wr_rst    (~rst_n),
		.rd_data   (hsv_align_5),
		.rd_addr   (hsv_align_x_cnt),
		.rd_clk    (clk),
		.rd_clk_en (hsv_close_de),
		.rd_rst    (~rst_n)
	);

	assign hsv_align_sel =
		(HSV_CLOSE_ALIGN_LINES <= 0) ? hsv_align_in :
		(HSV_CLOSE_ALIGN_LINES == 1) ? hsv_align_0  :
		(HSV_CLOSE_ALIGN_LINES == 2) ? hsv_align_1  :
		(HSV_CLOSE_ALIGN_LINES == 3) ? hsv_align_2  :
		(HSV_CLOSE_ALIGN_LINES == 4) ? hsv_align_3  :
		(HSV_CLOSE_ALIGN_LINES == 5) ? hsv_align_4  : hsv_align_5;

	assign hsv_align_de   = hsv_align_sel[1];
	assign hsv_align_bin  = hsv_align_sel[0];
	assign final_fused_bin = hsv_align_bin & hsv_align_de;  // 【修改】去掉Sobel AND，直接用HSV色彩掩码

// hsv out
	binary_frame_out u_hsv_binary_frame_out (
		.clk      (clk),
		.rst_n    (rst_n),
		.in_vsync (hsv_close_vsync),
		.in_hsync (hsv_close_hsync),
		.in_de    (hsv_close_de),
		.in_bin   (hsv_close_bin),
		.in_valid (1'b1),
		.out_vsync(hsv_pack_vsync),
		.out_hsync(hsv_pack_hsync),
		.out_de   (hsv_pack_de),
		.out_pix  (hsv_pack_pix)
	);

	binary_frame_out u_final_binary_frame_out (
		.clk      (clk),
		.rst_n    (rst_n),
		.in_vsync (sobel_close_vsync),
		.in_hsync (sobel_close_hsync),
		.in_de    (sobel_close_de),
		.in_bin   (final_fused_bin),
		.in_valid (1'b1),
		.out_vsync(final_pack_vsync),
		.out_hsync(final_pack_hsync),
		.out_de   (final_pack_de),
		.out_pix  (final_pack_pix)
	);

	assign out_vsync = final_pack_vsync;
	assign out_hsync = final_pack_hsync;
	assign out_de    = final_pack_de;
	assign out_bin   = final_pack_pix;

endmodule

