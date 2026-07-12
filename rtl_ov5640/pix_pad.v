`timescale 1ns / 1ps
// ====================================================================
// pix_pad — 像素行填充模块
// 将每行有效像素从输入宽度填充到 TARGET_WIDTH
// 超出输入 de 的部分输出零（黑色）
// ====================================================================
module pix_pad #(
    parameter TARGET_WIDTH = 12'd1920   // 目标行宽度
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

    reg [11:0] pix_cnt;         // 当前行像素计数器
    reg        in_de_d1;        // in_de 延迟一拍（用于边沿检测）
    reg        padding;         // 正在填充标志
    reg [11:0] pad_cnt;         // 填充计数器

    // in_de 边沿检测
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            in_de_d1 <= 1'b0;
        else
            in_de_d1 <= in_de;
    end

    wire de_rise = in_de && !in_de_d1;   // in_de 上升沿（行开始）
    wire de_fall = !in_de && in_de_d1;   // in_de 下降沿（行数据结束）

    // 像素计数 & 填充控制
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pix_cnt  <= 12'd0;
            padding  <= 1'b0;
            pad_cnt  <= 12'd0;
        end else begin
            if (de_rise) begin
                // 新一行开始
                pix_cnt  <= 12'd0;
                padding  <= 1'b0;
                pad_cnt  <= 12'd0;
            end else if (in_de) begin
                // 正常像素输入
                pix_cnt <= pix_cnt + 12'd1;
            end else if (de_fall) begin
                // de 下降沿：检查是否需要填充
                if (pix_cnt < TARGET_WIDTH) begin
                    padding <= 1'b1;
                    pad_cnt <= pix_cnt + 12'd1;  // 从下一个像素开始填
                end else begin
                    padding <= 1'b0;
                end
            end else if (padding) begin
                // 正在填充
                if (pad_cnt >= TARGET_WIDTH - 1) begin
                    padding <= 1'b0;
                end else begin
                    pad_cnt <= pad_cnt + 12'd1;
                end
            end
        end
    end

    // 输出生成
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_vsync <= 1'b0;
            out_hsync <= 1'b0;
            out_de    <= 1'b0;
            out_bin   <= 8'd0;
        end else begin
            out_vsync <= in_vsync;
            out_hsync <= in_hsync;
            
            if (in_de) begin
                // 正常数据：直通
                out_de  <= 1'b1;
                out_bin <= in_bin;
            end else if (padding) begin
                // 填充阶段：输出 de=1, data=0 (黑色)
                out_de  <= 1'b1;
                out_bin <= 8'd0;
            end else begin
                out_de  <= 1'b0;
                out_bin <= 8'd0;
            end
        end
    end

endmodule
