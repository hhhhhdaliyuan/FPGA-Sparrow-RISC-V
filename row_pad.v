// ====================================================================
// row_pad — 垂直填充模块
// 在帧顶部插入 PAD_TOP 行黑行，帧尾补黑行至 TARGET_ROWS 行
// ====================================================================
module row_pad #(
    parameter IMG_WIDTH    = 1920,
    parameter TARGET_ROWS  = 1080,
    parameter PAD_TOP      = 10,
    parameter H_BLANK_MAX  = 500    // 超过此周期 de=0 判定为帧结束
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        in_vsync,
    input  wire        in_hsync,
    input  wire        in_de,
    input  wire [7:0]  in_bin,
    output reg         out_vsync,
    output reg         out_hsync,
    output reg         out_de,
    output reg  [7:0]  out_bin
);

    reg        in_vsync_d, in_de_d;
    wire       vsync_rise = in_vsync & ~in_vsync_d;
    wire       de_fall    = ~in_de & in_de_d;

    reg [11:0] x_cnt;        // 列计数 0~1919
    reg [11:0] out_row;      // 已输出行数
    reg [11:0] pad_cnt;      // 填充行计数
    reg [11:0] blank_cnt;    // de=0 持续周期数
    reg [ 1:0] state;

    localparam S_IDLE    = 2'd0;
    localparam S_PAD_TOP = 2'd1;
    localparam S_PASS    = 2'd2;
    localparam S_PAD_BOT = 2'd3;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            in_vsync_d <= 1'b0;
            in_de_d    <= 1'b0;
            x_cnt      <= 12'd0;
            out_row    <= 12'd0;
            pad_cnt    <= 12'd0;
            blank_cnt  <= 12'd0;
            state      <= S_IDLE;
            out_vsync  <= 1'b0;
            out_hsync  <= 1'b0;
            out_de     <= 1'b0;
            out_bin    <= 8'd0;
        end else begin
            in_vsync_d <= in_vsync;
            in_de_d    <= in_de;
            out_vsync  <= in_vsync;
            out_hsync  <= in_hsync;

            case (state)
                // ============================================
                S_IDLE: begin
                    out_de  <= 1'b0;
                    out_bin <= 8'd0;
                    if (vsync_rise) begin
                        state   <= S_PAD_TOP;
                        x_cnt   <= 12'd0;
                        out_row <= 12'd0;
                        pad_cnt <= 12'd0;
                    end
                end

                // ============================================
                S_PAD_TOP: begin
                    out_de  <= 1'b1;
                    out_bin <= 8'd0;
                    x_cnt   <= x_cnt + 12'd1;
                    if (x_cnt == IMG_WIDTH - 1) begin
                        x_cnt    <= 12'd0;
                        out_row  <= out_row + 12'd1;
                        pad_cnt  <= pad_cnt + 12'd1;
                        if (pad_cnt == PAD_TOP - 1) begin
                            state <= S_PASS;
                            blank_cnt <= 12'd0;
                        end
                    end
                end

                // ============================================
                S_PASS: begin
                    if (in_de) begin
                        out_de    <= 1'b1;
                        out_bin   <= in_bin;
                        blank_cnt <= 12'd0;
                    end else begin
                        out_de    <= 1'b0;
                        out_bin   <= 8'd0;
                        blank_cnt <= blank_cnt + 12'd1;
                        // de 持续低电平超过阈值 → 帧有效数据结束
                        if (blank_cnt > H_BLANK_MAX && out_row < TARGET_ROWS) begin
                            state   <= S_PAD_BOT;
                            x_cnt   <= 12'd0;
                            pad_cnt <= 12'd0;
                        end
                    end
                end

                // ============================================
                S_PAD_BOT: begin
                    out_de  <= 1'b1;
                    out_bin <= 8'd0;
                    x_cnt   <= x_cnt + 12'd1;
                    if (x_cnt == IMG_WIDTH - 1) begin
                        x_cnt   <= 12'd0;
                        out_row <= out_row + 12'd1;
                        pad_cnt <= pad_cnt + 12'd1;
                    end
                    // 填满 TARGET_ROWS 行或 vsync 来了就停
                    if (out_row >= TARGET_ROWS || vsync_rise) begin
                        state   <= S_IDLE;
                        out_de  <= 1'b0;
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
