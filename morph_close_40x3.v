module morph_close_40x3 #(parameter IMG_WIDTH=1920)(
input wire clk,rst_n,in_vsync,in_hsync,in_de,in_bin,
output wire out_vsync,out_hsync,out_de,out_bin);
wire d_vsync,d_hsync,d_de,d_bin;
morph_rect_40x3 #(.IMG_WIDTH(IMG_WIDTH),.IS_DILATE(1))
u_d(.clk(clk),.rst_n(rst_n),.in_vsync(in_vsync),.in_hsync(in_hsync),.in_de(in_de),.in_bin(in_bin),
.out_vsync(d_vsync),.out_hsync(d_hsync),.out_de(d_de),.out_bin(d_bin));
morph_rect_40x3 #(.IMG_WIDTH(IMG_WIDTH),.IS_DILATE(0))
u_e(.clk(clk),.rst_n(rst_n),.in_vsync(d_vsync),.in_hsync(d_hsync),.in_de(d_de),.in_bin(d_bin),
.out_vsync(out_vsync),.out_hsync(out_hsync),.out_de(out_de),.out_bin(out_bin));
endmodule

module morph_rect_40x3 #(parameter IMG_WIDTH=1920,parameter IS_DILATE=1)(
input wire clk,rst_n,in_vsync,in_hsync,in_de,in_bin,
output reg out_vsync,out_hsync,out_de,out_bin);
wire [7:0] line1_data,line2_data;
reg [11:0] x_cnt,y_cnt;
reg in_de_d,in_vsync_d,tap1,tap2;
reg r0_0;
reg r0_1;
reg r0_2;
reg r0_3;
reg r0_4;
reg r0_5;
reg r0_6;
reg r0_7;
reg r0_8;
reg r0_9;

reg r0_10;
reg r0_11;
reg r0_12;
reg r0_13;
reg r0_14;
reg r0_15;
reg r0_16;
reg r0_17;
reg r0_18;
reg r0_19;

reg r0_20;
reg r0_21;
reg r0_22;
reg r0_23;
reg r0_24;
reg r0_25;
reg r0_26;
reg r0_27;
reg r0_28;
reg r0_29;

reg r0_30;
reg r0_31;
reg r0_32;
reg r0_33;
reg r0_34;
reg r0_35;
reg r0_36;
reg r0_37;
reg r0_38;
reg r0_39;
reg r1_0;
reg r1_1;
reg r1_2;
reg r1_3;
reg r1_4;
reg r1_5;
reg r1_6;
reg r1_7;
reg r1_8;
reg r1_9;

reg r1_10;
reg r1_11;
reg r1_12;
reg r1_13;
reg r1_14;
reg r1_15;
reg r1_16;
reg r1_17;
reg r1_18;
reg r1_19;

reg r1_20;
reg r1_21;
reg r1_22;
reg r1_23;
reg r1_24;
reg r1_25;
reg r1_26;
reg r1_27;
reg r1_28;
reg r1_29;

reg r1_30;
reg r1_31;
reg r1_32;
reg r1_33;
reg r1_34;
reg r1_35;
reg r1_36;
reg r1_37;
reg r1_38;
reg r1_39;
reg r2_0;
reg r2_1;
reg r2_2;
reg r2_3;
reg r2_4;
reg r2_5;
reg r2_6;
reg r2_7;
reg r2_8;
reg r2_9;

reg r2_10;
reg r2_11;
reg r2_12;
reg r2_13;
reg r2_14;
reg r2_15;
reg r2_16;
reg r2_17;
reg r2_18;
reg r2_19;

reg r2_20;
reg r2_21;
reg r2_22;
reg r2_23;
reg r2_24;
reg r2_25;
reg r2_26;
reg r2_27;
reg r2_28;
reg r2_29;

reg r2_30;
reg r2_31;
reg r2_32;
reg r2_33;
reg r2_34;
reg r2_35;
reg r2_36;
reg r2_37;
reg r2_38;
reg r2_39;
wire win_valid,op_or_w,op_and_w;
reg win_valid_d,vsync_d,hsync_d;
wire rst=~rst_n;
assign sof_rise=in_vsync&(~in_vsync_d);
assign de_fall=in_de_d&(~in_de);
assign win_valid=in_de&&(x_cnt>=12'd39)&&(y_cnt>=12'd2);
assign op_or_w=r0_0|
        r0_1|
        r0_2|
        r0_3|
        r0_4|
        r0_5|
        r0_6|
        r0_7|
        r0_8|
        r0_9|
        |
        r0_10|
        r0_11|
        r0_12|
        r0_13|
        r0_14|
        r0_15|
        r0_16|
        r0_17|
        r0_18|
        r0_19|
        |
        r0_20|
        r0_21|
        r0_22|
        r0_23|
        r0_24|
        r0_25|
        r0_26|
        r0_27|
        r0_28|
        r0_29|
        |
        r0_30|
        r0_31|
        r0_32|
        r0_33|
        r0_34|
        r0_35|
        r0_36|
        r0_37|
        r0_38|
        r0_39|
        r1_0|
        r1_1|
        r1_2|
        r1_3|
        r1_4|
        r1_5|
        r1_6|
        r1_7|
        r1_8|
        r1_9|
        |
        r1_10|
        r1_11|
        r1_12|
        r1_13|
        r1_14|
        r1_15|
        r1_16|
        r1_17|
        r1_18|
        r1_19|
        |
        r1_20|
        r1_21|
        r1_22|
        r1_23|
        r1_24|
        r1_25|
        r1_26|
        r1_27|
        r1_28|
        r1_29|
        |
        r1_30|
        r1_31|
        r1_32|
        r1_33|
        r1_34|
        r1_35|
        r1_36|
        r1_37|
        r1_38|
        r1_39|
        r2_0|
        r2_1|
        r2_2|
        r2_3|
        r2_4|
        r2_5|
        r2_6|
        r2_7|
        r2_8|
        r2_9|
        |
        r2_10|
        r2_11|
        r2_12|
        r2_13|
        r2_14|
        r2_15|
        r2_16|
        r2_17|
        r2_18|
        r2_19|
        |
        r2_20|
        r2_21|
        r2_22|
        r2_23|
        r2_24|
        r2_25|
        r2_26|
        r2_27|
        r2_28|
        r2_29|
        |
        r2_30|
        r2_31|
        r2_32|
        r2_33|
        r2_34|
        r2_35|
        r2_36|
        r2_37|
        r2_38|
        r2_39;
assign op_and_w=r0_0&
        r0_1&
        r0_2&
        r0_3&
        r0_4&
        r0_5&
        r0_6&
        r0_7&
        r0_8&
        r0_9&
        &
        r0_10&
        r0_11&
        r0_12&
        r0_13&
        r0_14&
        r0_15&
        r0_16&
        r0_17&
        r0_18&
        r0_19&
        &
        r0_20&
        r0_21&
        r0_22&
        r0_23&
        r0_24&
        r0_25&
        r0_26&
        r0_27&
        r0_28&
        r0_29&
        &
        r0_30&
        r0_31&
        r0_32&
        r0_33&
        r0_34&
        r0_35&
        r0_36&
        r0_37&
        r0_38&
        r0_39&
        r1_0&
        r1_1&
        r1_2&
        r1_3&
        r1_4&
        r1_5&
        r1_6&
        r1_7&
        r1_8&
        r1_9&
        &
        r1_10&
        r1_11&
        r1_12&
        r1_13&
        r1_14&
        r1_15&
        r1_16&
        r1_17&
        r1_18&
        r1_19&
        &
        r1_20&
        r1_21&
        r1_22&
        r1_23&
        r1_24&
        r1_25&
        r1_26&
        r1_27&
        r1_28&
        r1_29&
        &
        r1_30&
        r1_31&
        r1_32&
        r1_33&
        r1_34&
        r1_35&
        r1_36&
        r1_37&
        r1_38&
        r1_39&
        r2_0&
        r2_1&
        r2_2&
        r2_3&
        r2_4&
        r2_5&
        r2_6&
        r2_7&
        r2_8&
        r2_9&
        &
        r2_10&
        r2_11&
        r2_12&
        r2_13&
        r2_14&
        r2_15&
        r2_16&
        r2_17&
        r2_18&
        r2_19&
        &
        r2_20&
        r2_21&
        r2_22&
        r2_23&
        r2_24&
        r2_25&
        r2_26&
        r2_27&
        r2_28&
        r2_29&
        &
        r2_30&
        r2_31&
        r2_32&
        r2_33&
        r2_34&
        r2_35&
        r2_36&
        r2_37&
        r2_38&
        r2_39;
line_buffer u_lb1(.wr_data({7'b0,in_bin}),.wr_addr(x_cnt[10:0]),.wr_en(in_de),.wr_clk(clk),.wr_clk_en(in_de),.wr_rst(rst),.rd_data(line1_data),.rd_addr(x_cnt[10:0]),.rd_clk(clk),.rd_clk_en(in_de),.rd_rst(rst));
line_buffer u_lb2(.wr_data(line1_data),.wr_addr(x_cnt[10:0]),.wr_en(in_de),.wr_clk(clk),.wr_clk_en(in_de),.wr_rst(rst),.rd_data(line2_data),.rd_addr(x_cnt[10:0]),.rd_clk(clk),.rd_clk_en(in_de),.rd_rst(rst));
always@(posedge clk or negedge rst_n)begin
if(!rst_n)begin
in_de_d<=0;in_vsync_d<=0;x_cnt<=0;y_cnt<=0;tap1<=0;tap2<=0;
r0_0<=0; r0_1<=0; r0_2<=0; r0_3<=0; r0_4<=0; r0_5<=0; r0_6<=0; r0_7<=0; r0_8<=0; r0_9<=0;  r0_10<=0; r0_11<=0; r0_12<=0; r0_13<=0; r0_14<=0; r0_15<=0; r0_16<=0; r0_17<=0; r0_18<=0; r0_19<=0;  r0_20<=0; r0_21<=0; r0_22<=0; r0_23<=0; r0_24<=0; r0_25<=0; r0_26<=0; r0_27<=0; r0_28<=0; r0_29<=0;  r0_30<=0; r0_31<=0; r0_32<=0; r0_33<=0; r0_34<=0; r0_35<=0; r0_36<=0; r0_37<=0; r0_38<=0; r0_39<=0; r1_0<=0; r1_1<=0; r1_2<=0; r1_3<=0; r1_4<=0; r1_5<=0; r1_6<=0; r1_7<=0; r1_8<=0; r1_9<=0;  r1_10<=0; r1_11<=0; r1_12<=0; r1_13<=0; r1_14<=0; r1_15<=0; r1_16<=0; r1_17<=0; r1_18<=0; r1_19<=0;  r1_20<=0; r1_21<=0; r1_22<=0; r1_23<=0; r1_24<=0; r1_25<=0; r1_26<=0; r1_27<=0; r1_28<=0; r1_29<=0;  r1_30<=0; r1_31<=0; r1_32<=0; r1_33<=0; r1_34<=0; r1_35<=0; r1_36<=0; r1_37<=0; r1_38<=0; r1_39<=0; r2_0<=0; r2_1<=0; r2_2<=0; r2_3<=0; r2_4<=0; r2_5<=0; r2_6<=0; r2_7<=0; r2_8<=0; r2_9<=0;  r2_10<=0; r2_11<=0; r2_12<=0; r2_13<=0; r2_14<=0; r2_15<=0; r2_16<=0; r2_17<=0; r2_18<=0; r2_19<=0;  r2_20<=0; r2_21<=0; r2_22<=0; r2_23<=0; r2_24<=0; r2_25<=0; r2_26<=0; r2_27<=0; r2_28<=0; r2_29<=0;  r2_30<=0; r2_31<=0; r2_32<=0; r2_33<=0; r2_34<=0; r2_35<=0; r2_36<=0; r2_37<=0; r2_38<=0; r2_39<=0;
win_valid_d<=0;vsync_d<=0;hsync_d<=0;out_vsync<=0;out_hsync<=0;out_de<=0;out_bin<=0;
end else begin
in_de_d<=in_de;in_vsync_d<=in_vsync;
if(sof_rise)begin x_cnt<=0;y_cnt<=0;end else begin if(in_de)x_cnt<=x_cnt+1;if(de_fall)begin x_cnt<=0;y_cnt<=y_cnt+1;end end
if(in_de)begin tap1<=line1_data[0];tap2<=line2_data[0];
r0_39<=r0_38; r0_38<=r0_37; r0_37<=r0_36; r0_36<=r0_35; r0_35<=r0_34; r0_34<=r0_33; r0_33<=r0_32; r0_32<=r0_31; r0_31<=r0_30; r0_30<=r0_29; r0_29<=r0_28; r0_28<=r0_27; r0_27<=r0_26; r0_26<=r0_25; r0_25<=r0_24; r0_24<=r0_23; r0_23<=r0_22; r0_22<=r0_21; r0_21<=r0_20; r0_20<=r0_19; r0_19<=r0_18; r0_18<=r0_17; r0_17<=r0_16; r0_16<=r0_15; r0_15<=r0_14; r0_14<=r0_13; r0_13<=r0_12; r0_12<=r0_11; r0_11<=r0_10; r0_10<=r0_9; r0_9<=r0_8; r0_8<=r0_7; r0_7<=r0_6; r0_6<=r0_5; r0_5<=r0_4; r0_4<=r0_3; r0_3<=r0_2; r0_2<=r0_1; r0_1<=r0_0; r0_0<=tap2;
r1_39<=r1_38; r1_38<=r1_37; r1_37<=r1_36; r1_36<=r1_35; r1_35<=r1_34; r1_34<=r1_33; r1_33<=r1_32; r1_32<=r1_31; r1_31<=r1_30; r1_30<=r1_29; r1_29<=r1_28; r1_28<=r1_27; r1_27<=r1_26; r1_26<=r1_25; r1_25<=r1_24; r1_24<=r1_23; r1_23<=r1_22; r1_22<=r1_21; r1_21<=r1_20; r1_20<=r1_19; r1_19<=r1_18; r1_18<=r1_17; r1_17<=r1_16; r1_16<=r1_15; r1_15<=r1_14; r1_14<=r1_13; r1_13<=r1_12; r1_12<=r1_11; r1_11<=r1_10; r1_10<=r1_9; r1_9<=r1_8; r1_8<=r1_7; r1_7<=r1_6; r1_6<=r1_5; r1_5<=r1_4; r1_4<=r1_3; r1_3<=r1_2; r1_2<=r1_1; r1_1<=r1_0; r1_0<=tap1;
r2_39<=r2_38; r2_38<=r2_37; r2_37<=r2_36; r2_36<=r2_35; r2_35<=r2_34; r2_34<=r2_33; r2_33<=r2_32; r2_32<=r2_31; r2_31<=r2_30; r2_30<=r2_29; r2_29<=r2_28; r2_28<=r2_27; r2_27<=r2_26; r2_26<=r2_25; r2_25<=r2_24; r2_24<=r2_23; r2_23<=r2_22; r2_22<=r2_21; r2_21<=r2_20; r2_20<=r2_19; r2_19<=r2_18; r2_18<=r2_17; r2_17<=r2_16; r2_16<=r2_15; r2_15<=r2_14; r2_14<=r2_13; r2_13<=r2_12; r2_12<=r2_11; r2_11<=r2_10; r2_10<=r2_9; r2_9<=r2_8; r2_8<=r2_7; r2_7<=r2_6; r2_6<=r2_5; r2_5<=r2_4; r2_4<=r2_3; r2_3<=r2_2; r2_2<=r2_1; r2_1<=r2_0; r2_0<=in_bin;
end
win_valid_d<=win_valid;vsync_d<=in_vsync;hsync_d<=in_hsync;
out_vsync<=vsync_d;out_hsync<=hsync_d;out_de<=win_valid_d;
if(win_valid_d)out_bin<=IS_DILATE?op_or_w:op_and_w;
else out_bin<=1'b0;
end end
endmodule