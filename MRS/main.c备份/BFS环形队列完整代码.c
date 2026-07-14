// ============================================================
// BFS_环形队列 — 环形队列BFS + 窗口精修四角坐标
//   1. 环形队列 (Q_SIZE=4096, 2的幂) 
//   2. 32位队列项: entry = (y<<11)|x
//   3. visited位图 (uint32_t*, 32像素/字)
//   4. 队列满时overflow丢弃
//   5. 8邻域蔓延
//   6. 窗口精修四角(保留倾斜信息)
// ============================================================

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

// BFS参数
#define Q_SIZE            4096
#define Q_MASK            (Q_SIZE-1)
#define MIN_AREA          500
#define MIN_W             60
#define MIN_H             10
#define MAX_BLOB_AREA     80000
#define WIN_R             30   // 窗口精修半径
#define OFF_X             18   // X偏移
#define OFF_Y_BOT         10   // 底部Y偏移

// DDR
#define DDR_QUEUE ((volatile uint32_t*)0xA0800000)
#define DDR_VIS   ((volatile uint32_t*)0xA0840000)
#define VIS_WORDS_PER_ROW  (IMG_W / 32)

static int g_tlx,g_tly,g_trx,g_try,g_blx,g_bly,g_brx,g_bry;

void delay(uint32_t c){for(volatile uint32_t i=0;i<c;i++);}
static inline void freeze(void){*(volatile uint32_t*)FRAME_FREEZE_ADDR=1;}
static inline void unfreeze(void){*(volatile uint32_t*)FRAME_FREEZE_ADDR=0;}

static inline int is_white(volatile uint32_t* b,int x,int y){
    uint32_t w=b[y*DDR_STRIDE32+(x>>1)];
    return((int)((x&1)?(w>>16):(w&0xFFFF)) > 0x8000);
}
static inline void vis_set(int x,int y){
    volatile uint32_t* p=DDR_VIS+y*VIS_WORDS_PER_ROW+(x>>5);
    *p=*p|((uint32_t)1<<(x&0x1F));
}
static inline int vis_get(int x,int y){
    volatile uint32_t* p=DDR_VIS+y*VIS_WORDS_PER_ROW+(x>>5);
    return(int)((*p>>(x&0x1F))&1);
}
static inline void vis_clr(void){
    for(int y=SCAN_Y0;y<=SCAN_Y1;y++){
        volatile uint32_t* r=DDR_VIS+y*VIS_WORDS_PER_ROW;
        for(int i=0;i<VIS_WORDS_PER_ROW;i++)r[i]=0;
    }
}
#define ENC(x,y)  ((uint32_t)(((y)<<11)|(x)))
#define DEC_X(e)  ((int)((e)&0x7FF))
#define DEC_Y(e)  ((int)((e)>>11))

void find_plate_bfs(void){
    printf("[B]\r\n");
    volatile uint32_t* bin=(volatile uint32_t*)DDR_BIN_FRAME;
    volatile uint32_t* q=DDR_QUEUE;
    vis_clr();

    int best=0,tot=0,btl=0,btt=0,btr=0,btt2=0,bbl=0,bbb=0,bbr=0,bbb2=0;

    for(int y=SCAN_Y0;y<=SCAN_Y1;y++){
        for(int x=0;x<IMG_W;x++){
            if(!is_white(bin,x,y)||vis_get(x,y))continue;
            tot++;
            int hd=0,tl=0,ar=0,mnx=x,mxx=x,mny=y,mxy=y;
            int tlx=x,tly=y,trx=x,try_=y,blx=x,bly=y,brx=x,bry=y,ov=0;
            q[tl]=ENC(x,y);tl=(tl+1)&Q_MASK;ar++;vis_set(x,y);
            while(hd!=tl&&!ov){
                uint32_t e=q[hd];hd=(hd+1)&Q_MASK;
                int cx=DEC_X(e),cy=DEC_Y(e);
                if(cx+cy<tlx+tly){tlx=cx;tly=cy;}
                if(cx-cy>trx-try_){trx=cx;try_=cy;}
                if(cy-cx>bly-blx){blx=cx;bly=cy;}
                if(cx+cy>brx+bry){brx=cx;bry=cy;}
                #define EQ(nx,ny) do{if((ny)>=SCAN_Y0&&(ny)<=SCAN_Y1&&(nx)>=0&&(nx)<IMG_W&&!vis_get(nx,ny)&&is_white(bin,nx,ny)){vis_set(nx,ny);uint32_t nt=(tl+1)&Q_MASK;if(nt==hd)ov=1;else{q[tl]=ENC(nx,ny);tl=nt;ar++;if((nx)<mnx)mnx=(nx);if((nx)>mxx)mxx=(nx);if((ny)<mny)mny=(ny);if((ny)>mxy)mxy=(ny);}}}while(0)
                EQ(cx,cy-1);EQ(cx,cy+1);EQ(cx-1,cy);EQ(cx+1,cy);
                EQ(cx-1,cy-1);EQ(cx+1,cy-1);EQ(cx-1,cy+1);EQ(cx+1,cy+1);
                #undef EQ
                if(ar>=MAX_BLOB_AREA)ov=1;
            }
            if(ov)continue;
            if(ar>best&&ar>=MIN_AREA){
                int dw=trx-tlx,dw2=try_-tly,dd=blx-tlx,dd2=bly-tly;
                int w2=dw*dw+dw2*dw2,h2=dd*dd+dd2*dd2;
                if(w2>=3600&&h2>=100&&w2>=h2*4&&w2<=h2*36){
                    best=ar;btl=tlx;btt=tly;btr=trx;btt2=try_;
                    bbl=blx;bbb=bly;bbr=brx;bbb2=bry;
                }
            }
        }
    }
    printf("t=%d b=%d\n",tot,best);
    if(best<MIN_AREA){printf("no\n");return;}

    // 窗口精修四角: 在BFS极值点±WIN_R窗口内向外搜最远白像素,保留倾斜
    int tl_x=btl,tl_y=btt;
    for(int d=0;d<=WIN_R*2;d++)for(int s=0;s<=d;s++){
        int dx=s,dy=d-s;
        if(dx<=WIN_R*2&&dy<=WIN_R*2){
            int sx=btl-WIN_R+dx,sy=btt-WIN_R+dy;
            if(sx>=0&&sy>=0&&is_white(bin,sx,sy)){tl_x=sx;tl_y=sy;dx=99;break;}
        }
    }
    int tr_x=btr,tr_y=btt2;
    for(int d=0;d<=WIN_R*2;d++)for(int s=0;s<=d;s++){
        int dx=s,dy=d-s;
        if(dx<=WIN_R*2&&dy<=WIN_R*2){
            int sx=btr+WIN_R-dx,sy=btt2-WIN_R+dy;
            if(sx<IMG_W&&sy>=0&&is_white(bin,sx,sy)){tr_x=sx;tr_y=sy;dx=99;break;}
        }
    }
    int bl_x=bbl,bl_y=bbb;
    for(int d=0;d<=WIN_R*2;d++)for(int s=0;s<=d;s++){
        int dx=s,dy=d-s;
        if(dx<=WIN_R*2&&dy<=WIN_R*2){
            int sx=bbl-WIN_R+dx,sy=bbb+WIN_R-dy;
            if(sx>=0&&sy<IMG_H&&is_white(bin,sx,sy)){bl_x=sx;bl_y=sy;dx=99;break;}
        }
    }
    int br_x=bbr,br_y=bbb2;
    for(int d=0;d<=WIN_R*2;d++)for(int s=0;s<=d;s++){
        int dx=s,dy=d-s;
        if(dx<=WIN_R*2&&dy<=WIN_R*2){
            int sx=bbr+WIN_R-dx,sy=bbb2+WIN_R-dy;
            if(sx<IMG_W&&sy<IMG_H&&is_white(bin,sx,sy)){br_x=sx;br_y=sy;dx=99;break;}
        }
    }

    printf("1.BFS:\n");
    printf("  TL%d,%d TR%d,%d\n",btl,btt,btr,btt2);
    printf("  BL%d,%d BR%d,%d\n",bbl,bbb,bbr,bbb2);
    // 加偏移: X全+18, 底部Y+10
    tl_x+=OFF_X; tr_x+=OFF_X; bl_x+=OFF_X; br_x+=OFF_X;
    bl_y+=OFF_Y_BOT; br_y+=OFF_Y_BOT;

    g_tlx=tl_x;g_tly=tl_y;g_trx=tr_x;g_try=tr_y;
    g_blx=bl_x;g_bly=bl_y;g_brx=br_x;g_bry=br_y;

    printf("2.refine:\n");
    printf("  TL%d,%d TR%d,%d\n",tl_x,tl_y,tr_x,tr_y);
    printf("  BL%d,%d BR%d,%d\n",bl_x,bl_y,br_x,br_y);
}


void uart_byte(uint8_t c){uart_send_date(UART0,c);for(volatile int n=0;n<200;n++);}
void uart16(uint16_t v){uart_byte((v>>8)&0xFF);uart_byte(v&0xFF);}

// 发送原图区域 (四个角坐标的包围盒)
static uint32_t lb_buf[960];
void send_raw_quad(int x0,int y0,int x1,int y1){
    if(x0<0)x0=0;if(y0<0)y0=0;
    if(x1>=IMG_W)x1=IMG_W-1;if(y1>=IMG_H)y1=IMG_H-1;
    int w=x1-x0+1,h=y1-y0+1;
    if(w<10||h<10)return;
    printf("TX %d,%d-%d,%d %dx%d\n",x0,y0,x1,y1,w,h);
    volatile uint32_t* raw=(volatile uint32_t*)DDR_RAW_FRAME;
    uart_byte(0xAA);uart_byte(0x55);uart_byte(8);
    uart16((uint16_t)w);uart16((uint16_t)h);
    for(int y=y0;y<=y1;y++){
        int base=y*DDR_STRIDE32;
        for(int i=0;i<960;i++)lb_buf[i]=raw[base+i];
        for(int x=x0;x<=x1;x++){
            uint32_t wd=lb_buf[x>>1];
            uint16_t px=(uint16_t)((x&1)?(wd>>16):(wd&0xFFFF));
            uart_byte((px>>8)&0xFF);uart_byte(px&0xFF);
        }
    }
    uart_byte(0x55);uart_byte(0xAA);
}
int main(void){
    init_uart0_printf(115200,0);
    printf("go\n");
     unfreeze();
     delay(10000000);
    int n=0;
    while(1){
        printf("-%d-\n",++n);
        freeze();delay(200);
        find_plate_bfs();
        if(g_tlx>0)send_raw_quad(g_tlx,g_tly,g_brx,g_bry);
        unfreeze();
        delay(300000);
    }
}