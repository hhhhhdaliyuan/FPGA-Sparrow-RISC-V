`timescale 1ns/1ps

module rgb_hsv #(
    parameter integer H_BLUE_MIN  = 140,
    parameter integer H_BLUE_MAX  = 191,
    parameter integer H_GREEN_MIN = 38,
    parameter integer H_GREEN_MAX = 128,
    // 新增黄牌的 H 阈值参数
    parameter integer H_YELLOW_MIN = 25, 
    parameter integer H_YELLOW_MAX = 55, 
    parameter integer S_MIN       = 77,
    parameter integer V_MIN       = 51
)(
    input  wire [7:0] r,
    input  wire [7:0] g,
    input  wire [7:0] b,
    output reg  [7:0] h,
    output reg  [7:0] s,
    output reg  [7:0] v,
    output reg        mask_blue,
    output reg        mask_green,
    // 新增黄色掩码输出
    output reg        mask_yellow
);

    // --------------------------------------------------------------
    // 组合逻辑除法函数 (无符号，除数为 1~255)
    // 使用移位减法（不依赖任何除号）
    // --------------------------------------------------------------
    function [7:0] div_unsigned;
        input [15:0] dividend;   // 被除数 (最大 255*255 = 65025)
        input [7:0]  divisor;    // 除数 (1~255)
        reg [15:0] remainder;
        reg [7:0]  quotient;
        integer i;
        begin
            remainder = 0;
            quotient = 0;
            for (i = 15; i >= 0; i = i - 1) begin
                remainder = {remainder[14:0], dividend[i]};
                if (remainder >= divisor) begin
                    remainder = remainder - divisor;
                    quotient[i] = 1'b1;
                end
            end
            div_unsigned = quotient;
        end
    endfunction

    // 有符号除法包装 (被除数可能为负，返回整数商，向零舍入)
    function integer div_signed;
        input integer dividend;
        input integer divisor;    // 正数
        reg [15:0] abs_dividend;
        reg [7:0]  abs_quot;
        begin
            if (dividend < 0) begin
                abs_dividend = -dividend;
                abs_quot = div_unsigned(abs_dividend, divisor[7:0]);
                div_signed = -abs_quot;
            end else begin
                abs_dividend = dividend;
                abs_quot = div_unsigned(abs_dividend, divisor[7:0]);
                div_signed = abs_quot;
            end
        end
    endfunction

    // --------------------------------------------------------------
    // 最大值/最小值
    // --------------------------------------------------------------
    function integer max3;
        input integer a, b, c;
        begin
            max3 = (a > b) ? ((a > c) ? a : c) : ((b > c) ? b : c);
        end
    endfunction

    function integer min3;
        input integer a, b, c;
        begin
            min3 = (a < b) ? ((a < c) ? a : c) : ((b < c) ? b : c);
        end
    endfunction

    // --------------------------------------------------------------
    // 主逻辑
    // --------------------------------------------------------------
    integer r_i, g_i, b_i;
    integer max_c, min_c, delta;
    integer h_i, s_i, v_i;
    integer h_inc;

    always @(*) begin
        r_i = r;
        g_i = g;
        b_i = b;

        max_c = max3(r_i, g_i, b_i);
        min_c = min3(r_i, g_i, b_i);
        delta = max_c - min_c;

        // V 分量
        v_i = max_c;

        // S 分量
        if (max_c == 0)
            s_i = 0;
        else
            s_i = div_unsigned(delta * 255, max_c[7:0]);

        // H 分量
        if (delta == 0) begin
            h_i = 0;
        end else begin
            if (max_c == r_i) begin
                h_inc = div_signed(43 * (g_i - b_i), delta);
                h_i = h_inc;
                if (h_i < 0) h_i = h_i + 255;
            end else if (max_c == g_i) begin
                h_inc = div_signed(43 * (b_i - r_i), delta);
                h_i = 85 + h_inc;
            end else begin
                h_inc = div_signed(43 * (r_i - g_i), delta);
                h_i = 171 + h_inc;
            end
        end

        // 模 255 调整
        if (h_i < 0)   h_i = h_i + 255;
        if (h_i > 255) h_i = h_i - 255;

        // 输出
        h = h_i[7:0];
        s = s_i[7:0];
        v = v_i[7:0];

        mask_blue  = (h_i > H_BLUE_MIN ) && (h_i < H_BLUE_MAX ) && (s_i > S_MIN) && (v_i > V_MIN);
        mask_green = (h_i > H_GREEN_MIN) && (h_i < H_GREEN_MAX) && (s_i > S_MIN) && (v_i > V_MIN);
        // 新增的黄牌判断逻辑
        mask_yellow = (h_i > H_YELLOW_MIN) && (h_i < H_YELLOW_MAX) && (s_i > S_MIN) && (v_i > V_MIN);
    end

endmodule