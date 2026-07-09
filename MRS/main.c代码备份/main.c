#include <stdint.h>
#include <string.h>
#include "core.h"
#include "system.h"
#include "uart.h"
#include "printf.h"

// ===== 权重（存DDR 0xA2000000） =====
// mlp_weights.h 中的 fc1_w[512][256], fc1_b[256]
// fc2_w[256][128], fc2_b[128], fc3_w[128][65], fc3_b[65]
#define WEIGHT_BASE             ((volatile int8_t*)0xA2000000)
// 偏移: fc1_w @ 0, fc1_b @ 512*256, fc2_w @ 512*256+256, etc.

// ===== MLP参数 =====
#define INPUT_DIM   512   // 16x32
#define HIDDEN1     256
#define HIDDEN2     128
#define OUTPUT_DIM  65

int max(int a,int b){return a>b?a:b;}
int min(int a,int b){return a<b?a:b;}

// 通过串口接收字符图并分类
// 协议: AA55 + w + h + pixels + 55AA
int classify_char() {
    // 这里简化: 从MEM_BW_IMG读已经分割好的字符
    // 实际使用时要传入x1,x2,yt,yb
    return -1;
}

// ===== MLP推理（纯整数，无浮点无除法） =====
// 输入: 16x32 二值图 (0/255) → 展开512维
// 权重已存DDR 0xA2000000
int mlp_infer(uint8_t* img_16x32) {
    volatile int8_t* w = WEIGHT_BASE;
    int8_t h1[HIDDEN1], h2[HIDDEN2];
    int32_t sum;
    int i, j;

    // ---------- FC1: 512→256 ----------
    // 权重偏移: fc1_w @ 0 (512*256 int8)
    // 偏置偏移: fc1_b @ 512*256 (256 int8)
    for (i = 0; i < HIDDEN1; i++) {
        sum = 0;
        for (j = 0; j < INPUT_DIM; j++) {
            int8_t pix = (int8_t)((int)img_16x32[j] - 128);
            sum += (int)pix * (int)w[j * HIDDEN1 + i];  // 权重: [input_dim][hidden]
        }
        // + bias
        sum += (int)w[INPUT_DIM * HIDDEN1 + i];
        // 右移8位缩放
        sum >>= 8;
        // ReLU
        if (sum < 0) sum = 0;
        if (sum > 127) sum = 127;
        h1[i] = (int8_t)sum;
    }

    // ---------- FC2: 256→128 ----------
    int fc2_off = INPUT_DIM * HIDDEN1 + HIDDEN1; // 跳过fc1_w+fc1_b
    volatile int8_t* w2 = w + fc2_off;
    for (i = 0; i < HIDDEN2; i++) {
        sum = 0;
        for (j = 0; j < HIDDEN1; j++) {
            sum += (int)h1[j] * (int)w2[j * HIDDEN2 + i];  // 权重: [hidden1][hidden2]
        }
        sum += (int)w2[HIDDEN1 * HIDDEN2 + i];
        sum >>= 12;  // 右移12位
        if (sum < 0) sum = 0;
        if (sum > 127) sum = 127;
        h2[i] = (int8_t)sum;
    }

    // ---------- FC3: 128→65 ----------
    int fc3_off = fc2_off + HIDDEN1 * HIDDEN2 + HIDDEN2;
    volatile int8_t* w3 = w + fc3_off;
    int best_val = -10000, best_idx = 0;
    for (i = 0; i < OUTPUT_DIM; i++) {
        sum = 0;
        for (j = 0; j < HIDDEN2; j++) {
            sum += (int)h2[j] * (int)w3[j * OUTPUT_DIM + i];  // 权重: [hidden2][output]
        }
        sum += (int)w3[HIDDEN2 * OUTPUT_DIM + i];
        // 最后层不需要缩放，直接比大小
        if (sum > best_val) {
            best_val = sum;
            best_idx = i;
        }
    }

    return best_idx;  // 输出类别索引
}

// 类别名称（对应mlp_weights.h的65类）
const char* class_names[] = {
    "0","1","2","3","4","5","6","7","8","9",
    "A","B","C","D","E","F","G","H","J","K",
    "L","M","N","P","Q","R","S","T","U","V",
    "W","X","Y","Z",
    "川","鄂","赣","甘","贵","桂","黑","沪","吉","冀",
    "津","晋","京","辽","鲁","蒙","闽","宁","青","琼",
    "陕","苏","晋","皖","湘","新","渝","豫","粤","云",
    "藏","浙"
};

int main() {
    init_uart0_printf(115200, 0);
    printf("MLP推理测试 (权重DDR 0xA2000000)\n");
    printf("类别数: %d\n", OUTPUT_DIM);
    
    // 测试: 生成一个假字符图16x32（全零）
    uint8_t test_img[512];
    memset(test_img, 0, 512);
    
    int cls = mlp_infer(test_img);
    printf("全黑图 → 类别%d: %s\n", cls, class_names[cls]);
    
    while(1);
}

