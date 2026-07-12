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
#define Q_SIZE            4096
#define MIN_AREA          500
#define MIN_W             60
#define MIN_H             10
#define MIN_RATIO         2
#define MAX_RATIO         6
#define PIPE_DX           27
#define PIPE_DY           5
#define EDGE_M            3

#define DDR_QX    ((volatile uint16_t*)0xA0800000)
#define DDR_QY    ((volatile uint16_t*)0xA0840000)
#define DDR_RSUM  ((volatile int*)     0xA0880000)
#define DDR_CSUM  ((volatile int*)     0xA0900000)

static int g_blob_x0,g_blob_y0,g_blob_x1,g_blob_y1,g_blob_area;
static int g_tlx,g_tly,g_trx,g_try,g_blx,g_bly,g_brx,g_bry;
static int g_bfs_tlx,g_bfs_tly,g_bfs_trx,g_bfs_try;
static int g_bfs_blx,g_bfs_bly,g_bfs_brx,g_bfs_bry;
static uint32_t lb_buf[960];

void delay(uint32_t c){for(volatile uint32_t i=0;i<c;i++);}
static inline void freeze(void){*(volatile uint32_t*)FRAME_FREEZE_ADDR=1;}
static inline void unfreeze(void){*(volatile uint32_t*)FRAME_FREEZE_ADDR=0;}
void uart_byte(uint8_t c){uart_send_date(UART0,c);for(volatile int n=0;n<200;n++);}
void uart16(uint16_t v){uart_byte((v>>8)&0xFF);uart_byte(v&0xFF);}

static inline int bin_is_white(volatile uint32_t* base,int x,int y){
    uint32_t wd=base[y*DDR_STRIDE32+(x>>1)];
    uint16_t px=(uint16_t)((x&1)?(wd>>16):(wd&0xFFFF));
    return(px>0x8000);
}

void find_largest_blob(void){
    printf("[1]start\r\n");
    volatile uint32_t* bin=(volatile uint32_t*)DDR_BIN_FRAME;
    volatile uint16_t* qx=DDR_QX;
    volatile uint16_t* qy=DDR_QY;
    volatile int* rsum=DDR_RSUM;
    volatile int* csum=DDR_CSUM;
    printf("[2]clr\r\n");
    for(int i=SCAN_Y0;i<=SCAN_Y1;i++)rsum[i]=0;
    for(int i=0;i<IMG_W;i++)csum[i]=0;
    int best_area=0,best_x0=0,best_y0=0,best_x1=0,best_y1=0;
    int best_tlx=0,best_tly=0,best_trx=0,best_try=0;
    int best_blx=0,best_bly=0,best_brx=0,best_bry=0,total=0;
    printf("[3]scan\r\n");
    for(int y=SCAN_Y0;y<=SCAN_Y1;y++){
        for(int x=0;x<IMG_W;x++){
            if(!bin_is_white(bin,x,y))continue;
            total++;
            int head=0,tail=0,area=0,min_x=x,max_x=x,min_y=y,max_y=y;
            int tlx=x,tly=y,trx=x,try_=y,blx=x,bly=y,brx=x,bry=y;
            qx[tail]=(uint16_t)x;qy[tail]=(uint16_t)y;tail++;area++;
            rsum[y]++;csum[x]++;
            {volatile uint32_t*p=&bin[y*DDR_STRIDE32+(x>>1)];if(x&1)*p&=0x0000FFFF;else*p&=0xFFFF0000;}
            while(head<tail&&tail<Q_SIZE-4){
                int cx=qx[head],cy=qy[head];head++;
                if(cx+cy<tlx+tly){tlx=cx;tly=cy;}
                if(cx-cy>trx-try_){trx=cx;try_=cy;}
                if(cy-cx>bly-blx){blx=cx;bly=cy;}
                if(cx+cy>brx+bry){brx=cx;bry=cy;}
                #define ENQ(nx,ny)do{\
                    rsum[ny]++;csum[nx]++;\
                    volatile uint32_t*p=&bin[(ny)*DDR_STRIDE32+((nx)>>1)];\
                    if(nx&1)*p&=0x0000FFFF;else*p&=0xFFFF0000;\
                    qx[tail]=(uint16_t)(nx);qy[tail]=(uint16_t)(ny);tail++;area++;\
                    if(nx<min_x)min_x=nx;if(nx>max_x)max_x=nx;\
                    if(ny<min_y)min_y=ny;if(ny>max_y)max_y=ny;\
                }while(0)
                if(cy>SCAN_Y0&&bin_is_white(bin,cx,cy-1))ENQ(cx,cy-1);
                if(cy<SCAN_Y1&&bin_is_white(bin,cx,cy+1))ENQ(cx,cy+1);
                if(cx>0&&bin_is_white(bin,cx-1,cy))ENQ(cx-1,cy);
                if(cx<IMG_W-1&&bin_is_white(bin,cx+1,cy))ENQ(cx+1,cy);
                if(cx>0&&cy>SCAN_Y0&&bin_is_white(bin,cx-1,cy-1))ENQ(cx-1,cy-1);
                if(cx<IMG_W-1&&cy>SCAN_Y0&&bin_is_white(bin,cx+1,cy-1))ENQ(cx+1,cy-1);
                if(cx>0&&cy<SCAN_Y1&&bin_is_white(bin,cx-1,cy+1))ENQ(cx-1,cy+1);
                if(cx<IMG_W-1&&cy<SCAN_Y1&&bin_is_white(bin,cx+1,cy+1))ENQ(cx+1,cy+1);
                #undef ENQ
            }
            int dw=trx-tlx,dh_w=try_-tly,dh=blx-tlx,dh_h=bly-tly;
            int w2=dw*dw+dh_w*dh_w,h2=dh*dh+dh_h*dh_h;
            if(area>best_area&&area>=MIN_AREA&&w2>=MIN_W*MIN_W&&h2>=MIN_H*MIN_H&&w2>=h2*4&&w2<=h2*36){
                best_area=area;best_x0=min_x;best_x1=max_x;best_y0=min_y;best_y1=max_y;
                best_tlx=tlx;best_tly=tly;best_trx=trx;best_try=try_;
                best_blx=blx;best_bly=bly;best_brx=brx;best_bry=bry;
                g_bfs_tlx=tlx;g_bfs_tly=tly;g_bfs_trx=trx;g_bfs_try=try_;
                g_bfs_blx=blx;g_bfs_bly=bly;g_bfs_brx=brx;g_bfs_bry=bry;
            }
        }
    }
    printf("[4]proj\r\n");
    if(best_area>=MIN_AREA){
        int px0=best_x0-20;if(px0<0)px0=0;
        int py0=best_y0-20;if(py0<0)py0=0;
        int px1=best_x1+20;if(px1>=IMG_W)px1=IMG_W-1;
        int py1=best_y1+20;if(py1>=IMG_H)py1=IMG_H-1;
        int row_max=0,row_top=py0,row_bot=py1;
        for(int ry=py0;ry<=py1;ry++){if(rsum[ry]>row_max)row_max=rsum[ry];}
        int thr=row_max/3;
        for(int ry=py0;ry<=py1;ry++){if(rsum[ry]>thr){row_top=ry;break;}}
        for(int ry=py1;ry>=py0;ry--){if(rsum[ry]>thr){row_bot=ry;break;}}
        int col_max=0,col_left=px0,col_right=px1;
        for(int cx=px0;cx<=px1;cx++){if(csum[cx]>col_max)col_max=csum[cx];}
        thr=col_max/3;
        for(int cx=px0;cx<=px1;cx++){if(csum[cx]>thr){col_left=cx;break;}}
        for(int cx=px1;cx>=px0;cx--){if(csum[cx]>thr){col_right=cx;break;}}
        best_x0=col_left;best_y0=row_top;
        best_x1=col_right;best_y1=row_bot;
        best_tlx=col_left;best_tly=row_top;
        best_trx=col_right;best_try=row_top;
        best_blx=col_left;best_bly=row_bot;
        best_brx=col_right;best_bry=row_bot;
    }
    printf("[5]out\r\n");
    g_blob_x0=best_x0;g_blob_y0=best_y0;g_blob_x1=best_x1;g_blob_y1=best_y1;
    g_blob_area=best_area;
    g_tlx=best_tlx;g_tly=best_tly;g_trx=best_trx;g_try=best_try;
    g_blx=best_blx;g_bly=best_bly;g_brx=best_brx;g_bry=best_bry;
    printf("\r\n===== BFS =====\r\n");
    printf("Y=%d~%d 连通域=%d\r\n",SCAN_Y0,SCAN_Y1,total);
    if(best_area>=MIN_AREA){
        printf("面积=%d\r\n",best_area);
        printf("1.BFS极值:\r\n");
        printf("  左上(%d,%d) 右上(%d,%d)\r\n",g_bfs_tlx,g_bfs_tly,g_bfs_trx,g_bfs_try);
        printf("  左下(%d,%d) 右下(%d,%d)\r\n",g_bfs_blx,g_bfs_bly,g_bfs_brx,g_bfs_bry);
        printf("2.投影轴对齐:\r\n");
        printf("  左上(%d,%d) 右上(%d,%d)\r\n",best_tlx,best_tly,best_trx,best_try);
        printf("  左下(%d,%d) 右下(%d,%d)\r\n",best_blx,best_bly,best_brx,best_bry);
        printf("3.逼真+补偿:\r\n");
        printf("  左上(%d,%d) 右上(%d,%d)\r\n",g_bfs_tlx+PIPE_DX,g_bfs_tly+PIPE_DY,g_bfs_trx+PIPE_DX,g_bfs_try+PIPE_DY);
        printf("  左下(%d,%d) 右下(%d,%d)\r\n",g_bfs_blx+PIPE_DX,g_bfs_bly+PIPE_DY,g_bfs_brx+PIPE_DX,g_bfs_bry+PIPE_DY);
    }else{printf("未找到\r\n");}
    printf("===== END =====\r\n\n");
}

void send_raw_blob(void){
    if(g_blob_area<MIN_AREA)return;
    volatile uint32_t*raw=(volatile uint32_t*)DDR_RAW_FRAME;
    int rx0=g_blob_x0+PIPE_DX,ry0=g_blob_y0+PIPE_DY,rx1=g_blob_x1+PIPE_DX,ry1=g_blob_y1+PIPE_DY;
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
        find_largest_blob();
        //send_raw_blob();
        unfreeze();
        delay(3000000);
    }
}