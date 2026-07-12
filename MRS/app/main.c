#include <stdint.h>
#include "core.h"
#include "system.h"
#include "uart.h"
#include "printf.h"

#define FRAME_FREEZE_ADDR 0x40000400
#define DDR_BIN_FRAME     0xA0000000
#define DDR_RAW_FRAME     0xA4000000
#define DDR_STRIDE32      960
#define IMG_W             1920
#define IMG_H             1080
#define SCAN_Y0           100
#define SCAN_Y1           (IMG_H-31)
#define MIN_AREA          500
#define MIN_W             60
#define MIN_H             10
#define MIN_RATIO         2
#define MAX_RATIO         6
#define PIPE_DX           27
#define PIPE_DY           5
#define EDGE_M            3

// DDR 投影数组
#define DDR_RSUM  ((volatile int*)0xA0800000)
#define DDR_CSUM  ((volatile int*)0xA0880000)

static int g_box_x0,g_box_y0,g_box_x1,g_box_y1,g_box_area;
static int g_tlx,g_tly,g_trx,g_try,g_blx,g_bly,g_brx,g_bry;
static uint32_t lb_buf[960];

void delay(uint32_t c){for(volatile uint32_t i=0;i<c;i++);}
static inline void freeze(void){*(volatile uint32_t*)FRAME_FREEZE_ADDR=1;}
static inline void unfreeze(void){*(volatile uint32_t*)FRAME_FREEZE_ADDR=0;}
void uart_byte(uint8_t c){uart_send_date(UART0,c);for(volatile int n=0;n<200;n++);}
void uart16(uint16_t v){uart_byte((v>>8)&0xFF);uart_byte(v&0xFF);}

static inline int is_white(volatile uint32_t* base,int x,int y){
    uint32_t wd=base[y*DDR_STRIDE32+(x>>1)];
    uint16_t px=(uint16_t)((x&1)?(wd>>16):(wd&0xFFFF));
    return(px>0x8000);
}

void find_plate(void){
    printf("[1]scan\r\n");
    volatile uint32_t* bin=(volatile uint32_t*)DDR_BIN_FRAME;
    volatile int* rsum=DDR_RSUM;
    volatile int* csum=DDR_CSUM;
    for(int i=SCAN_Y0;i<=SCAN_Y1;i++)rsum[i]=0;
    for(int i=0;i<IMG_W;i++)csum[i]=0;

    // 极值角点跟踪
    int tlx=IMG_W,tly=IMG_H,trx=0,try_=0,blx=IMG_W,bly=0,brx=0,bry=IMG_H;

    for(int y=SCAN_Y0;y<=SCAN_Y1;y++){
        for(int x=0;x<IMG_W;x++){
            if(!is_white(bin,x,y))continue;
            rsum[y]++;csum[x]++;
            if(x+y<tlx+tly){tlx=x;tly=y;}
            if(x-y>trx-try_){trx=x;try_=y;}
            if(y-x>bly-blx){blx=x;bly=y;}
            if(x+y>brx+bry){brx=x;bry=y;}
        }
    }

    printf("[2]proj\r\n");
    // 行列投影找边界
    int row_max=0;
    for(int ry=SCAN_Y0;ry<=SCAN_Y1;ry++){if(rsum[ry]>row_max)row_max=rsum[ry];}
    if(row_max<10){printf("无有效白像素\r\n");return;}
    int thr=row_max/3;
    int row_top=SCAN_Y0,row_bot=SCAN_Y1;
    for(int ry=SCAN_Y0;ry<=SCAN_Y1;ry++){if(rsum[ry]>thr){row_top=ry;break;}}
    for(int ry=SCAN_Y1;ry>=SCAN_Y0;ry--){if(rsum[ry]>thr){row_bot=ry;break;}}

    int col_max=0;
    for(int cx=0;cx<IMG_W;cx++){if(csum[cx]>col_max)col_max=csum[cx];}
    thr=col_max/3;
    int col_left=0,col_right=IMG_W-1;
    for(int cx=0;cx<IMG_W;cx++){if(csum[cx]>thr){col_left=cx;break;}}
    for(int cx=IMG_W-1;cx>=0;cx--){if(csum[cx]>thr){col_right=cx;break;}}

    int bw=col_right-col_left+1,bh=row_bot-row_top+1;
    int area_est=bw*bh;
    int w2=bw*bw,h2=bh*bh;
    if(area_est<MIN_AREA||bw<MIN_W||bh<MIN_H||w2<h2*4||w2>h2*36){
        printf("比例不符: %dx%d area=%d\r\n",bw,bh,area_est);
        return;
    }

    // 极值角点：从投影边界向内对角线走到白像素
    // 左上
    for(int d=0;d<bw+bh;d++){
        int found=0;
        for(int dx=0;dx<=d&&!found;dx++){
            int dy=d-dx;
            int nx=col_left+dx,ny=row_top+dy;
            if(nx<=col_right&&ny<=row_bot&&is_white(bin,nx,ny))
                {tlx=nx;tly=ny;found=1;}
        }
        if(found)break;
    }
    // 右上
    for(int d=0;d<bw+bh;d++){
        int found=0;
        for(int dx=0;dx<=d&&!found;dx++){
            int dy=d-dx;
            int nx=col_right-dx,ny=row_top+dy;
            if(nx>=col_left&&ny<=row_bot&&is_white(bin,nx,ny))
                {trx=nx;try_=ny;found=1;}
        }
        if(found)break;
    }
    // 左下
    for(int d=0;d<bw+bh;d++){
        int found=0;
        for(int dx=0;dx<=d&&!found;dx++){
            int dy=d-dx;
            int nx=col_left+dx,ny=row_bot-dy;
            if(nx<=col_right&&ny>=row_top&&is_white(bin,nx,ny))
                {blx=nx;bly=ny;found=1;}
        }
        if(found)break;
    }
    // 右下
    for(int d=0;d<bw+bh;d++){
        int found=0;
        for(int dx=0;dx<=d&&!found;dx++){
            int dy=d-dx;
            int nx=col_right-dx,ny=row_bot-dy;
            if(nx>=col_left&&ny>=row_top&&is_white(bin,nx,ny))
                {brx=nx;bry=ny;found=1;}
        }
        if(found)break;
    }

    printf("[3]out\r\n");
    g_box_x0=col_left;g_box_y0=row_top;
    g_box_x1=col_right;g_box_y1=row_bot;
    g_box_area=area_est;
    g_tlx=tlx;g_tly=tly;g_trx=trx;g_try=try_;
    g_blx=blx;g_bly=bly;g_brx=brx;g_bry=bry;

    printf("\r\n===== 投影法 =====\r\n");
    printf("区域=%dx%d 峰值R=%d C=%d\r\n",bw,bh,row_max,col_max);
    printf("1.投影轴对齐:\r\n");
    printf("  左上(%d,%d) 右上(%d,%d)\r\n",col_left,row_top,col_right,row_top);
    printf("  左下(%d,%d) 右下(%d,%d)\r\n",col_left,row_bot,col_right,row_bot);
    printf("2.逼真+补偿:\r\n");
    printf("  左上(%d,%d) 右上(%d,%d)\r\n",tlx+PIPE_DX,tly+PIPE_DY,trx+PIPE_DX,try_+PIPE_DY);
    printf("  左下(%d,%d) 右下(%d,%d)\r\n",blx+PIPE_DX,bly+PIPE_DY,brx+PIPE_DX,bry+PIPE_DY);
    printf("===== END =====\r\n\n");
}

void send_raw_blob(void){
    if(g_box_area<MIN_AREA)return;
    volatile uint32_t*raw=(volatile uint32_t*)DDR_RAW_FRAME;
    int rx0=g_box_x0+PIPE_DX,ry0=g_box_y0+PIPE_DY,rx1=g_box_x1+PIPE_DX,ry1=g_box_y1+PIPE_DY;
    int x0=rx0-EDGE_M;if(x0<0)x0=0;
    int y0=ry0-EDGE_M;if(y0<0)y0=0;
    int x1=rx1+EDGE_M;if(x1>=IMG_W)x1=IMG_W-1;
    int y1=ry1+EDGE_M;if(y1>=IMG_H)y1=IMG_H-1;
    int w=x1-x0+1,h=y1-y0+1;
    printf("TX raw (%d,%d)-(%d,%d) %dx%d\r\n",x0,y0,x1,y1,w,h);
    uart_byte(0xAA);uart_byte(0x55);uart_byte(8);uart16((uint16_t)w);uart16((uint16_t)h);
    uint32_t*lb=lb_buf;
    for(int y=y0;y<=y1;y++){
        int base=y*DDR_STRIDE32;
        for(int i=0;i<960;i++)lb[i]=raw[base+i];
        for(int x=x0;x<=x1;x++){
            uint32_t wd=lb[x>>1];
            uint16_t px=(uint16_t)((x&1)?(wd>>16):(wd&0xFFFF));
            uart16(px);
        }
    }
    uart_byte(0x55);uart_byte(0xAA);
    printf(" raw ok\r\n");
}

int main(void){
    init_uart0_printf(115200,0);
    unfreeze();delay(500000);
    freeze();delay(500000);
    unfreeze();delay(2000000);
    int loop=0;
    while(1){
        printf("--- loop %d ---\r\n",++loop);
        freeze();delay(50);
        find_plate();
        //send_raw_blob();
        unfreeze();
        delay(3000000);
    }
}