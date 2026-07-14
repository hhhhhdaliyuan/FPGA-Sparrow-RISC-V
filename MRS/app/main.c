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

#define TARGET_W          440
#define TARGET_H          140
#define FIXED_SHIFT       8
#define FIXED_SCALE       (1<<FIXED_SHIFT)

#define Q_SIZE            4096
#define Q_MASK            (Q_SIZE-1)
#define MIN_AREA          500
#define MIN_W             60
#define MIN_H             10
#define MAX_BLOB_AREA     80000
#define WIN_R             30
#define OFF_X             22
#define OFF_Y_BOT         10

// DDR 内存映射
#define DDR_QUEUE  ((volatile uint32_t*)0xA0800000)
#define DDR_VIS    ((volatile uint32_t*)0xA0840000)
#define VIS_WORDS  (IMG_W/32)
#define DDR_RSUM   ((volatile int*)0xA0880000)
#define DDR_CSUM   ((volatile int*)0xA0900000)
#define MEM_DST    ((volatile uint16_t*)0xA1900000)   // 校正后原图
#define MEM_BW     ((volatile uint32_t*)0xA1A00000)   // 二值图
#define MEM_BM     ((volatile uint32_t*)0xA1B00000)   // 形态学位图
#define MEM_TMP    ((volatile uint32_t*)0xA1B01000)
#define MEM_PROJ_H ((volatile uint16_t*)0xA1C00000)   // 水平投影
#define MEM_PROJ_V ((volatile uint16_t*)0xA1C01000)   // 垂直投影
#define MAP_TABLE  ((volatile int*)0xA2000000)        // 映射表
#define MAP_XY(y,x)  MAP_TABLE[((y)*TARGET_W+(x))*2]
#define MAP_YY(y,x)  MAP_TABLE[((y)*TARGET_W+(x))*2+1]

static int g_tlx,g_tly,g_trx,g_try,g_blx,g_bly,g_brx,g_bry;
static uint32_t lb_buf[960];

// ===== 工具函数 =====
void delay(uint32_t c){for(volatile uint32_t i=0;i<c;i++);}
static inline void freeze(void){*(volatile uint32_t*)FRAME_FREEZE_ADDR=1;}
static inline void unfreeze(void){*(volatile uint32_t*)FRAME_FREEZE_ADDR=0;}
void uart_byte(uint8_t c){uart_send_date(UART0,c);for(volatile int n=0;n<200;n++);}
void uart16(uint16_t v){uart_byte((v>>8)&0xFF);uart_byte(v&0xFF);}

int div_int(int n,int d){
    if(d==0)return 0;int r=0;
    while(n>=d){int t=d,m=1;while(n>=(t<<1)&&(t<<1)>t){t<<=1;m<<=1;}n-=t;r+=m;}
    return r;
}

uint16_t get_px(int sx,int sy){
    if(sx<0||sx>=IMG_W||sy<0||sy>=IMG_H)return 0;
    volatile uint32_t* r32=(volatile uint32_t*)DDR_RAW_FRAME;
    uint32_t w=r32[sy*DDR_STRIDE32+(sx>>1)];
    return (w>>((sx&1)?16:0))&0xFFFF;
}

// ===== BFS =====
static inline int is_white(volatile uint32_t* b,int x,int y){
    uint32_t w=b[y*DDR_STRIDE32+(x>>1)];
    return((int)((x&1)?(w>>16):(w&0xFFFF)) > 0x8000);
}
static inline void vis_set(int x,int y){
    volatile uint32_t* p=DDR_VIS+y*VIS_WORDS+(x>>5);
    *p=*p|((uint32_t)1<<(x&0x1F));
}
static inline int vis_get(int x,int y){
    volatile uint32_t* p=DDR_VIS+y*VIS_WORDS+(x>>5);
    return(int)((*p>>(x&0x1F))&1);
}
static inline void vis_clr(void){
    for(int y=SCAN_Y0;y<=SCAN_Y1;y++){
        volatile uint32_t* r=DDR_VIS+y*VIS_WORDS;
        for(int i=0;i<VIS_WORDS;i++)r[i]=0;
    }
}
#define ENC(x,y)  ((uint32_t)(((y)<<11)|(x)))
#define DEC_X(e)  ((int)((e)&0x7FF))
#define DEC_Y(e)  ((int)((e)>>11))

void find_plate_bfs(void){
    printf("[B] ");
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

    // 窗口精修
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
    tl_x+=OFF_X;tr_x+=OFF_X;bl_x+=OFF_X;br_x+=OFF_X;
    bl_y+=OFF_Y_BOT;br_y+=OFF_Y_BOT;
    g_tlx=tl_x;g_tly=tl_y;g_trx=tr_x;g_try=tr_y;
    g_blx=bl_x;g_bly=bl_y;g_brx=br_x;g_bry=br_y;
    printf("  TL%d,%d TR%d,%d\n",tl_x,tl_y,tr_x,tr_y);
    printf("  BL%d,%d BR%d,%d\n",bl_x,bl_y,br_x,br_y);
}

// ===== 灰度 (无浮点无除法) =====
int gray_of(uint16_t px){
    int r5=(px>>11)&0x1F,g6=(px>>5)&0x3F,b5=px&0x1F;
    int r=(r5<<3)|(r5>>2),g=(g6<<2)|(g6>>4),b=(b5<<3)|(b5>>2);
    return (r*77+g*150+b*29)>>8;
}

// ===== 自动检测蓝/绿牌 (从校正后图采样) =====
int detect_type(void){
    volatile uint16_t* d=MEM_DST;
    int bl=0,gr=0;
    for(int y=0;y<TARGET_H;y+=10)for(int x=0;x<TARGET_W;x+=10){
        uint16_t px=d[y*TARGET_W+x];
        int r5=(px>>11)&0x1F,g6=(px>>5)&0x3F,b5=px&0x1F;
        int r=(r5<<3)|(r5>>2),g=(g6<<2)|(g6>>4),b=(b5<<3)|(b5>>2);
        if(b>r+30&&b>g+30)bl++; else if(g>r+30&&g>b+30)gr++;
    }
    return (gr>bl)?1:0;
}

// ===== 透视映射表 =====
void init_map(int tlx,int tly,int trx,int try_,int blx,int bly,int brx,int bry){
    printf("[M] ");
    for(int y=0;y<TARGET_H;y++){
        int fy=div_int(y*FIXED_SCALE,TARGET_H-1),iv_fy=FIXED_SCALE-fy;
        for(int x=0;x<TARGET_W;x++){
            int fx=div_int(x*FIXED_SCALE,TARGET_W-1),iv_fx=FIXED_SCALE-fx;
            MAP_XY(y,x)=((iv_fx*iv_fy>>FIXED_SHIFT)*tlx+(fx*iv_fy>>FIXED_SHIFT)*trx+
                         (fx*fy>>FIXED_SHIFT)*brx+(iv_fx*fy>>FIXED_SHIFT)*blx)>>FIXED_SHIFT;
            MAP_YY(y,x)=((iv_fx*iv_fy>>FIXED_SHIFT)*tly+(fx*iv_fy>>FIXED_SHIFT)*try_+
                         (fx*fy>>FIXED_SHIFT)*bry+(iv_fx*fy>>FIXED_SHIFT)*bly)>>FIXED_SHIFT;
        }
    }
    printf("ok\n");
}

// ===== 透视校正 =====
void warp(void){
    printf("[W] ");
    volatile uint16_t* d=MEM_DST;
    for(int y=0;y<TARGET_H;y++)for(int x=0;x<TARGET_W;x+=4){
        d[y*TARGET_W+x+0]=get_px(MAP_XY(y,x+0),MAP_YY(y,x+0));
        d[y*TARGET_W+x+1]=get_px(MAP_XY(y,x+1),MAP_YY(y,x+1));
        d[y*TARGET_W+x+2]=get_px(MAP_XY(y,x+2),MAP_YY(y,x+2));
        d[y*TARGET_W+x+3]=get_px(MAP_XY(y,x+3),MAP_YY(y,x+3));
    }
    printf("ok\n");
}

// ===== 二值化 =====
void binarize(int tp){
    printf("[BIN] ");
    volatile uint16_t* d=MEM_DST;
    volatile uint32_t* bw=MEM_BW;
    int wpl=TARGET_W>>2;
    for(int y=0;y<TARGET_H;y++)for(int x=0;x<TARGET_W;x+=4){
        uint32_t word=0;
        for(int k=0;k<4&&(x+k)<TARGET_W;k++){
            uint16_t px=d[y*TARGET_W+x+k];
            int white=0;
            if(tp==1){
                if(gray_of(px)<100)white=1;  // 绿牌: 黑字
            }else{
                int r5=(px>>11)&0x1F;int r=(r5<<3)|(r5>>2);
                if(r>120)white=1;            // 蓝牌: 白字
            }
            if(white)word|=(255<<(k*8));
        }
        bw[y*wpl+(x>>2)]=word;
    }
    printf("ok\n");
}

// ===== 字符分割 =====
int seg_chars(int* xs,int* xe,int* pyt,int* pyb){
    printf("[SEG] ");
    volatile uint32_t* bw=MEM_BW;
    volatile uint16_t* ph=MEM_PROJ_H;
    volatile uint16_t* pv=MEM_PROJ_V;
    int wpl=TARGET_W>>2,mh=0;
    for(int y=0;y<TARGET_H;y++){int c=0;
        for(int w=0;w<wpl;w++){uint32_t v=bw[y*wpl+w];
            for(int k=0;k<4;k++)if((v>>(k*8))&0xFF)c++;}
        ph[y]=c;if(c>mh)mh=c;
    }
    if(mh<5){printf("no\n");return 0;}
    int ht=(mh*153)>>10;if(ht<2)ht=2;
    int yt=-1,yb=-1,cs=-1,ml=0;
    for(int y=0;y<TARGET_H;y++){
        if(ph[y]>ht){if(cs<0)cs=y;}
        else if(cs>=0){int l=y-cs;if(l>ml){ml=l;yt=cs;yb=y-1;}cs=-1;}
    }
    if(cs>=0){int l=TARGET_H-cs;if(l>ml){ml=l;yt=cs;yb=TARGET_H-1;}}
    *pyt=yt;*pyb=yb;
    if(yt<0||yb-yt<5){printf("norow\n");return 0;}
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
    printf("%d\n",cc);
    for(int i=0;i<cc;i++)printf("  [%d]%d-%d\n",i,xs[i],xe[i]);
    return cc;
}

// ===== 发送二值图 =====
void send_bin(void){
    volatile uint32_t* bw=MEM_BW;
    int wpl=TARGET_W>>2;
    uart_byte(0xAA);uart_byte(0x55);uart_byte(2);
    uart16(TARGET_W);uart16(TARGET_H);
    for(int y=0;y<TARGET_H;y++)for(int x=0;x<TARGET_W;x+=4){
        uint32_t v=bw[y*wpl+(x>>2)];
        uart_byte((v>>0)&0xFF);uart_byte((v>>8)&0xFF);
        uart_byte((v>>16)&0xFF);uart_byte((v>>24)&0xFF);
    }
    uart_byte(0x55);uart_byte(0xAA);
    printf("[TX] bin\n");
}

// ===== 发送字符 =====
void send_chars(int* xs,int* xe,int cc,int yt,int yb){
    volatile uint32_t* bw=MEM_BW;
    int wpl=TARGET_W>>2,ch=yb-yt+1;
    for(int i=0;i<cc;i++){
        int cw=xe[i]-xs[i]+1;
        uart_byte(0xAA);uart_byte(0x55);uart_byte(3);
        uart16(cw);uart16(ch);
        uart_byte(i+1);
        for(int y=yt;y<=yb;y++)for(int x=xs[i];x<=xe[i];x+=4){
            uint32_t v=bw[y*wpl+(x>>2)];
            for(int k=0;k<4&&(x+k)<=xe[i];k++)uart_byte((v>>(k*8))&0xFF);
        }
        uart_byte(0x55);uart_byte(0xAA);
        printf("[TX] char%d %dx%d\n",i+1,cw,ch);
    }
}

// ===== 主流程 =====
int main(void){
    init_uart0_printf(115200,0);
    printf("go\n");
    unfreeze();
    delay(10000000);
    int n=0;
    while(1){
        //printf("===%d===\n",++n);
        //freeze();delay(200);
        //find_plate_bfs();
        //*if(g_tlx>0){
            //init_map(g_tlx,g_tly,g_trx,g_try,g_blx,g_bly,g_brx,g_bry);
            //warp();
           // int tp=detect_type();
           // printf("tp=%d\n",tp);
           // binarize(tp);
          //  int xs[20],xe[20],yt,yb;
          //  int cc=seg_chars(xs,xe,&yt,&yb);
          //  send_bin();
          //  if(cc>0)send_chars(xs,xe,cc,yt,yb);
       // }
      //  unfreeze();
        delay(300000);
    }
}