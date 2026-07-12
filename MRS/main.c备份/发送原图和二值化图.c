#include <stdint.h>
#include "core.h"
#include "system.h"
#include "uart.h"
#include "printf.h"

#define DDR_BIN_FRAME           0xA0000000
#define DDR_RAW_FRAME           0xA4000000
#define DDR_STRIDE32            960
#define FRAME_FREEZE_ADDR       0x40000400

#define CROP_X0  650
#define CROP_Y0  400
#define CROP_X1  1300
#define CROP_Y1  650
#define CROP_W   651
#define CROP_H   251

void delay(uint32_t c) { for (volatile uint32_t i = 0; i < c; i++); }

void uart_byte(uint8_t c) {
    uart_send_date(UART0, c);
    for (volatile int n = 0; n < 200; n++);
}

void uart16(uint16_t v) {
    uart_byte((v >> 8) & 0xFF);
    uart_byte(v & 0xFF);
}

static inline void freeze(void)   { *(volatile uint32_t*)FRAME_FREEZE_ADDR = 1; }
static inline void unfreeze(void) { *(volatile uint32_t*)FRAME_FREEZE_ADDR = 0; }

void send_bin_crop(void) {
    volatile uint32_t* r32 = (volatile uint32_t*)DDR_BIN_FRAME;
    printf("TX bin (%d,%d)-(%d,%d) %dx%d\r\n", CROP_X0, CROP_Y0, CROP_X1, CROP_Y1, CROP_W, CROP_H);
    uart_byte(0xAA); uart_byte(0x55); uart_byte(7);
    uart16(CROP_W); uart16(CROP_H);
    for (int y = CROP_Y0; y <= CROP_Y1; y++) {
        int base = y * DDR_STRIDE32;
        uint32_t line_buf[960];
        for (int i = 0; i < 960; i++) line_buf[i] = r32[base + i];
        for (int x = CROP_X0; x <= CROP_X1; x += 8) {
            uint8_t byte = 0;
            for (int k = 0; k < 8; k++) {
                int xx = x + k; if (xx > CROP_X1) break;
                uint32_t wd = line_buf[xx >> 1];
                uint32_t sh = ((uint32_t)xx & 1) ? 16 : 0;
                if (((wd >> sh) & 0xFFFF) > 0x8000) byte |= (1 << (7 - k));
            }
            uart_byte(byte);
        }
    }
    uart_byte(0x55); uart_byte(0xAA);
    printf(" bin ok\r\n");
}

void send_raw_crop(void) {
    volatile uint32_t* r32 = (volatile uint32_t*)DDR_RAW_FRAME;
    printf("TX raw (%d,%d)-(%d,%d) %dx%d\r\n", CROP_X0, CROP_Y0, CROP_X1, CROP_Y1, CROP_W, CROP_H);
    uart_byte(0xAA); uart_byte(0x55); uart_byte(8);
    uart16(CROP_W); uart16(CROP_H);
    for (int y = CROP_Y0; y <= CROP_Y1; y++) {
        int base = y * DDR_STRIDE32;
        uint32_t line_buf[960];
        for (int i = 0; i < 960; i++) line_buf[i] = r32[base + i];
        for (int x = CROP_X0; x <= CROP_X1; x++) {
            uint32_t wd = line_buf[x >> 1];
            uint32_t sh = ((uint32_t)x & 1) ? 16 : 0;
            uint16_t px = (wd >> sh) & 0xFFFF;
            uart_byte((px >> 8) & 0xFF); uart_byte(px & 0xFF);
        }
    }
    uart_byte(0x55); uart_byte(0xAA);
    printf(" raw ok\r\n");
}

int main(void) {
    init_uart0_printf(115200, 0);
    unfreeze();
    printf("\r\n===== 解除冻结 =====\r\n");
    delay(100000000);
    freeze();
    printf("\r\n===== 开始冻结 =====\r\n");
    delay(50000000);
    unfreeze();
    printf("\r\n===== 解除冻结 =====\r\n");
    delay(50000000);
    int loop = 0;
    while (1) {
        send_bin_crop();
        delay(1000000000);
    }
}