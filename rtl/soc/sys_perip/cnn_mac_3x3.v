`timescale 1ns/1ps

module cnn_mac_3x3 (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         en,        // 运算使能

    // 9个 INT8 的输入像素 (特征图)
    input  wire signed [7:0] p0, p1, p2,
    input  wire signed [7:0] p3, p4, p5,
    input  wire signed [7:0] p6, p7, p8,

    // 9个 INT8 的卷积核权重
    input  wire signed [7:0] w0, w1, w2,
    input  wire signed [7:0] w3, w4, w5,
    input  wire signed [7:0] w6, w7, w8,

    // 偏差 (Bias)
    input  wire signed [31:0] bias,
    
    // 控制信号
    input  wire         en_relu,   // 是否激活 ReLU

    // 输出结果 (INT8 量化后的单个像素点累加结果)
    // 这里我们先输出 32-bit 累加结果，方便后续对接软核的缩放量化
    output reg signed [31:0] mac_out,
    output reg               mac_valid
);

    // 第一级：9个并行乘法器 (8bit * 8bit = 16bit)
    // 注意：这里的乘法，紫光 PDS 综合时会自动映射到你图2中的 APM/Multiplier 硬核中
    reg signed [15:0] mult_res [0:8];
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mult_res[0] <= 0; mult_res[1] <= 0; mult_res[2] <= 0;
            mult_res[3] <= 0; mult_res[4] <= 0; mult_res[5] <= 0;
            mult_res[6] <= 0; mult_res[7] <= 0; mult_res[8] <= 0;
        end else if (en) begin
            mult_res[0] <= p0 * w0;
            mult_res[1] <= p1 * w1;
            mult_res[2] <= p2 * w2;
            mult_res[3] <= p3 * w3;
            mult_res[4] <= p4 * w4;
            mult_res[5] <= p5 * w5;
            mult_res[6] <= p6 * w6;
            mult_res[7] <= p7 * w7;
            mult_res[8] <= p8 * w8;
        end
    end

    // 第二级：加法树 (Adder Tree) 与 Bias 累加
    wire signed [31:0] sum = mult_res[0] + mult_res[1] + mult_res[2] + 
                             mult_res[3] + mult_res[4] + mult_res[5] + 
                             mult_res[6] + mult_res[7] + mult_res[8] + bias;

    reg valid_d1;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mac_out <= 0;
            mac_valid <= 0;
            valid_d1 <= 0;
        end else begin
            valid_d1 <= en;
            mac_valid <= valid_d1; // 延迟2拍输出有效信号

            if (valid_d1) begin
                if (en_relu && sum < 0) 
                    mac_out <= 0;   // ReLU: 小于0截断为0
                else 
                    mac_out <= sum; // 正常输出
            end
        end
    end

endmodule