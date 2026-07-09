#include <stdint.h>
#include <string.h>
#include "core.h"
#include "system.h"
#include "uart.h"
#include "printf.h"

#define DDR_RAW_FRAME           0xA4000000  // 原图
#define RAW_W                   1920
#define IMG_H                   1080
#define DDR_STRIDE32            960         // 1920/2

#define TARGET_W                440
#define TARGET_H                140
#define FIXED_SHIFT             8
#define FIXED_SCALE             (1 << FIXED_SHIFT)

// DDR内存映射
#define MEM_DST                 ((volatile uint16_t*)0xA1900000)  // 校正后原图
#define MEM_BW                  ((volatile uint32_t*)0xA1A00000)  // 二值图
#define MEM_PROJ_H              ((volatile uint16_t*)0xA1C00000)  // 水平投影
#define MEM_PROJ_V              ((volatile uint16_t*)0xA1C01000)  // 垂直投影
#define MAP_TABLE               ((volatile int*)0xA2000000)       // 映射表
#define MAP_XY(y,x)             MAP_TABLE[((y)*TARGET_W+(x))*2]
#define MAP_YY(y,x)             MAP_TABLE[((y)*TARGET_W+(x))*2+1]

int max(int a,int b){return a>b?a:b;}
int min(int a,int b){return a<b?a:b;}
void delay(uint32_t c){for(volatile uint32_t i=0;i<c;i++);}

int div_int(int n,int d){
    if(d==0)return 0;int r=0;
    while(n>=d){int t=d,m=1;while(n>=(t<<1)&&(t<<1)>t){t<<=1;m<<=1;}n-=t;r+=m;}
    return r;
}

void uart_byte(uint8_t c){uart_send_date(UART0,c);for(volatile int n=0;n<15;n++);}
void uart16(uint16_t v){uart_byte((v>>8)&0xFF);uart_byte(v&0xFF);}

// 32位读原图像素
uint16_t get_px(int sx,int sy){
    if(sx<0||sx>=RAW_W||sy<0||sy>=IMG_H)return 0;
    volatile uint32_t* r32=(volatile uint32_t*)DDR_RAW_FRAME;
    uint32_t w=r32[sy*DDR_STRIDE32+(sx>>1)];
    return (w>>((sx&1)?16:0))&0xFFFF;
}

// ===== 生成透视映射表 =====
void init_map(int tl_x,int tl_y,int tr_x,int tr_y,int bl_x,int bl_y,int br_x,int br_y){
    printf("[0] 透视映射表...\r\n");
    for(int y=0;y<TARGET_H;y++){
        int fy=div_int(y*FIXED_SCALE,TARGET_H-1),iv_fy=FIXED_SCALE-fy;
        for(int x=0;x<TARGET_W;x++){
            int fx=div_int(x*FIXED_SCALE,TARGET_W-1),iv_fx=FIXED_SCALE-fx;
            MAP_XY(y,x)=((iv_fx*iv_fy>>FIXED_SHIFT)*tl_x+(fx*iv_fy>>FIXED_SHIFT)*tr_x+
                         (fx*fy>>FIXED_SHIFT)*br_x+(iv_fx*fy>>FIXED_SHIFT)*bl_x)>>FIXED_SHIFT;
            MAP_YY(y,x)=((iv_fx*iv_fy>>FIXED_SHIFT)*tl_y+(fx*iv_fy>>FIXED_SHIFT)*tr_y+
                         (fx*fy>>FIXED_SHIFT)*br_y+(iv_fx*fy>>FIXED_SHIFT)*bl_y)>>FIXED_SHIFT;
        }
    }
    printf("  完成\r\n");
}

// ===== 1. 透视校正 =====
void perspective_correct(){
    printf("[1/5] 透视校正 %dx%d...\r\n",TARGET_W,TARGET_H);
    volatile uint16_t* dst=MEM_DST;
    for(int y=0;y<TARGET_H;y++){
        for(int x=0;x<TARGET_W;x+=4){
            dst[y*TARGET_W+x+0]=get_px(MAP_XY(y,x+0),MAP_YY(y,x+0));
            dst[y*TARGET_W+x+1]=get_px(MAP_XY(y,x+1),MAP_YY(y,x+1));
            dst[y*TARGET_W+x+2]=get_px(MAP_XY(y,x+2),MAP_YY(y,x+2));
            dst[y*TARGET_W+x+3]=get_px(MAP_XY(y,x+3),MAP_YY(y,x+3));
        }
        if((y&31)==0)for(volatile int n=0;n<10;n++);
    }
    printf("  完成\r\n");
}

// ===== 2. 蓝牌二值化 =====
void binarize_plate(){
    printf("[2/5] 蓝牌二值化...\r\n");
    volatile uint16_t* dst=MEM_DST;
    volatile uint32_t* bw=MEM_BW;
    int wpl=TARGET_W>>2,white=0;
    for(int y=0;y<TARGET_H;y++){
        for(int x=0;x<TARGET_W;x+=4){
            uint32_t word=0;
            for(int k=0;k<4;k++){
                uint16_t px=dst[y*TARGET_W+x+k];
                int r=(px>>11)&0x1F;r=(r<<3)|(r>>2);
                if(r>120){word|=(255<<(k*8));white++;}
            }
            bw[y*wpl+(x>>2)]=word;
        }
    }
    printf("  白字:%d/%d\r\n",white,TARGET_W*TARGET_H);
}

// ===== 3. 字符分割 =====
int segment_chars(int* xs,int* xe,int* pyt,int* pyb){
    printf("[3/5] 字符分割...\r\n");
    volatile uint32_t* bw=MEM_BW;
    volatile uint16_t* ph=MEM_PROJ_H;
    volatile uint16_t* pv=MEM_PROJ_V;
    int wpl=TARGET_W>>2,mh=0;

    for(int y=0;y<TARGET_H;y++){int c=0;
        for(int w=0;w<wpl;w++){uint32_t v=bw[y*wpl+w];
            for(int k=0;k<4;k++)if((v>>(k*8))&0xFF)c++;}
        ph[y]=c;if(c>mh)mh=c;
    }
    int ht=(mh*153)>>10;if(ht<2)ht=2;

    int yt=-1,yb=-1,cs=-1,ml=0;
    for(int y=0;y<TARGET_H;y++){
        if(ph[y]>ht){if(cs<0)cs=y;}
        else if(cs>=0){int l=y-cs;if(l>ml){ml=l;yt=cs;yb=y-1;}cs=-1;}
    }
    if(cs>=0){int l=TARGET_H-cs;if(l>ml){ml=l;yt=cs;yb=TARGET_H-1;}}
    *pyt=yt;*pyb=yb;
    if(yt<0||yb-yt<5){printf("  未找到字符行\r\n");return 0;}

    int mv=0;
    for(int x=0;x<TARGET_W;x++){int c=0;
        for(int y=yt;y<=yb;y++){uint32_t v=bw[y*wpl+(x>>2)];
            if((v>>((x&3)*8))&0xFF)c++;}
        pv[x]=c;if(c>mv)mv=c;
    }
    int vt=(mv*102)>>10;if(vt<1)vt=1;

    int cc=0,in=0;
    for(int x=0;x<TARGET_W;x++){
        if(pv[x]>=vt){if(!in){xs[cc]=x;in=1;}}
        else if(in){xe[cc]=x-1;if(xe[cc]-xs[cc]+1>=4)cc++;in=0;}
    }
    if(in&&(TARGET_W-1-xs[cc]+1>=4)){xe[cc]=TARGET_W-1;cc++;}
    printf("  字符:%d个\r\n",cc);
    for(int i=0;i<cc;i++)printf("    [%d]x=%d~%d w=%d\r\n",i+1,xs[i],xe[i],xe[i]-xs[i]+1);
    return cc;
}

// ===== 4. 串口发送图像 =====
void send_type_header(uint8_t type,int w,int h){
    uart_byte(0xAA);uart_byte(0x55);uart_byte(type);
    uart16(w);uart16(h);
}

// 发送校正后原图(440x140 RGB565)
void send_raw_corrected(){
    printf("  发送校正原图(%dx%d)...\r\n",TARGET_W,TARGET_H);
    send_type_header(1,TARGET_W,TARGET_H);
    volatile uint16_t* dst=MEM_DST;
    for(int y=0;y<TARGET_H;y++)
        for(int x=0;x<TARGET_W;x++){
            uint16_t px=dst[y*TARGET_W+x];
            uart_byte((px>>8)&0xFF);uart_byte(px&0xFF);
        }
    uart_byte(0x55);uart_byte(0xAA);
}

// 发送二值图(440x140, 每像素8bit)
void send_binary(){
    printf("  发送二值图(%dx%d)...\r\n",TARGET_W,TARGET_H);
    send_type_header(2,TARGET_W,TARGET_H);
    volatile uint32_t* bw=MEM_BW;
    int wpl=TARGET_W>>2;
    for(int y=0;y<TARGET_H;y++)
        for(int x=0;x<TARGET_W;x+=4){
            uint32_t v=bw[y*wpl+(x>>2)];
            uart_byte((v>>0)&0xFF);
            uart_byte((v>>8)&0xFF);
            uart_byte((v>>16)&0xFF);
            uart_byte((v>>24)&0xFF);
        }
    uart_byte(0x55);uart_byte(0xAA);
}

// 发送每个字符
void send_chars(int* xs,int* xe,int cc,int yt,int yb){
    printf("  发送%d个字符...\r\n",cc);
    volatile uint32_t* bw=MEM_BW;
    int wpl=TARGET_W>>2,ch=yb-yt+1;
    for(int i=0;i<cc;i++){
        int cw=xe[i]-xs[i]+1;
        printf("    字符%d: %dx%d\r\n",i+1,cw,ch);
        send_type_header(3,cw,ch);
        uart_byte(i+1);
        for(int y=yt;y<=yb;y++)
            for(int x=xs[i];x<=xe[i];x+=4){
                uint32_t v=bw[y*wpl+(x>>2)];
                for(int k=0;k<4&&(x+k)<=xe[i];k++)uart_byte((v>>(k*8))&0xFF);
            }
        uart_byte(0x55);uart_byte(0xAA);
        for(volatile int n=0;n<2000;n++);
    }
}

// ===== 主流程 =====
int main(){
    init_uart0_printf(115200,0);
    printf("\r\n===== 车牌识别(图像发送) =====\r\n");

    // 四个角坐标（可修改）
    int tl_x=740,tl_y=477,tr_x=1180,tr_y=476;
    int bl_x=742,bl_y=607,br_x=1185,br_y=607;

    init_map(tl_x,tl_y,tr_x,tr_y,bl_x,bl_y,br_x,br_y);
    delay(30000000);

    int frame=0;
    while(1){
        printf("\r\n--- 第%d帧 ---\r\n",++frame);
        perspective_correct();
        binarize_plate();
        int xs[20],xe[20],yt,yb;
        int cc=segment_chars(xs,xe,&yt,&yb);
        send_raw_corrected();
        for(volatile int n=0;n<5000;n++);
        send_binary();
        for(volatile int n=0;n<5000;n++);
        if(cc>0)send_chars(xs,xe,cc,yt,yb);
        printf("[5/5] 完成!\r\n");
        delay(50000000);  // 等下一帧
    }
}
