`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: Myminieye
// Engineer: Ori
// 
// Create Date:    2021-08-06 15:16 
// Design Name:  
// Module Name:    sync_vg
// QQ Group   :    
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
//    VS     ______                                       ______
//HS  __    |      |_______________����____________________|      |
//   |       h_sync  h_bp       h_act                h_fp
//   |__                    _______________________
//DE    |   _______________|                       |_____________
//      |
//      .
//      |
//    __|
//   |  
//   |__ 
//      |
// Revision: v1.0
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////
`define UD #1

module sync_vg # (
    parameter               X_BITS=12,
    parameter               Y_BITS=12,
 
  //MODE_1080p (参考 HDMI_IN_DDR3_HDMI_OUT 例程)
    parameter V_TOTAL = 12'd1125,  // 场扫描周期
    parameter V_FP    = 12'd4,     // 场显示前沿
    parameter V_BP    = 12'd36,    // 场显示后沿
    parameter V_SYNC  = 12'd5,     // 场同步脉冲
    parameter V_ACT   = 12'd1080,  // 场有效数据
    //parameter H_TOTAL = 12'd1650,
    //parameter H_FP = 12'd110,
    //parameter H_BP = 12'd220,
    // �޸�Ϊ���ӳ� H_BP �� H_TOTAL����
    parameter H_TOTAL = 12'd2200,  // 行扫描周期
    parameter H_FP    = 12'd88,    // 行显示前沿
    parameter H_BP    = 12'd148,   // 行显示后沿
    parameter H_SYNC  = 12'd44,    // 行同步脉冲
    parameter H_ACT   = 12'd1920,  // 行有效显示区域
    parameter HV_OFFSET = 12'd0 

)(
    input                   clk,
    input                   rstn,
    output reg              vs_out,
    output reg              hs_out,
    output reg              de_out,
    output reg              de_re,
    output reg [X_BITS-1:0] x_act,
    output reg [Y_BITS-1:0] y_act
);

    reg [X_BITS-1:0] h_count;
    reg [Y_BITS-1:0] v_count;
    
    /* horizontal counter */
    always @(posedge clk)
    begin
        if (!rstn)
            h_count <= `UD 0;
        else
        begin
            if (h_count < H_TOTAL - 1)
                h_count <= `UD h_count + 1;
            else
                h_count <= `UD 0;
        end
    end
    
    /* vertical counter */
    always @(posedge clk)
    begin
        if (!rstn)
            v_count <= `UD 0;
        else
        if (h_count == H_TOTAL - 1)
        begin
            if (v_count == V_TOTAL - 1)
                v_count <= `UD 0;
            else
                v_count <= `UD v_count + 1;
        end
    end
    
    always @(posedge clk)
    begin
        if (!rstn)
            hs_out <= `UD 4'b0;
        else 
            hs_out <= `UD ((h_count < H_SYNC));
    end
    
    always @(posedge clk)
    begin
        if (!rstn)
            vs_out <= `UD 4'b0;
        else 
        begin
            if ((v_count == 0) && (h_count == HV_OFFSET))
                vs_out <= `UD 1'b1;
            else if ((v_count == V_SYNC) && (h_count == HV_OFFSET))
                vs_out <= `UD 1'b0;
            else
                vs_out <= `UD vs_out;
        end
    end
    
    always @(posedge clk)
    begin
        if (!rstn)
            de_out <= `UD 4'b0;
        else
            de_out <= (((v_count >= V_SYNC + V_BP) && (v_count <= V_TOTAL - V_FP - 1)) && 
                      ((h_count >= H_SYNC + H_BP) && (h_count <= H_TOTAL - H_FP - 1)));
    end

    always @(posedge clk)
    begin
        if (!rstn)
            de_re <= `UD 4'b0;
        else
            de_re <= (((v_count >= V_SYNC + V_BP) && (v_count <= V_TOTAL - V_FP - 1)) && 
                      ((h_count >= H_SYNC + H_BP-2'd2) && (h_count <= H_TOTAL - H_FP - 3)));
    end    
    // active pixels counter output
    always @(posedge clk)
    begin
        if (!rstn)
            x_act <= `UD 'd0;
        else 
        begin
        /* X coords �C for a backend pattern generator */
            if(h_count > (H_SYNC + H_BP - 1'b1))
                x_act <= `UD (h_count - (H_SYNC + H_BP));
            else
                x_act <= `UD 'd0;
        end
    end
    
    always @(posedge clk)
    begin
        if (!rstn)
            y_act <= `UD 'd0;
        else 
        begin
            /* Y coords �C for a backend pattern generator */
            if(v_count > (V_SYNC + V_BP - 1'b1))
                y_act <= `UD (v_count - (V_SYNC + V_BP));
            else
                y_act <= `UD 'd0;
        end
    end
    
endmodule
