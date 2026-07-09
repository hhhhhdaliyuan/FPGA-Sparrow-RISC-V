#include "system.h"
uint8_t cnt;
uint32_t tmp;
//启动定时器外设的比较输出和输入捕获
int main()
{
    init_uart0_printf(115200,0);//设置波特率
    printf("%s", "Timer cmp out and capture in\n");
    printf("%s", "--------------\n");
    fpioa_perips_out_set(TIMER0_CMPO_N, 10);//[10]比较输出-
    fpioa_perips_out_set(TIMER0_CMPO_P, 11);//[11]比较输出+
    fpioa_perips_in_set(TIMER0_CAPI, 1);//[1]捕获输入
    timer_div_set(0);//分频系数0
    timer_cmpol_ctrl(1);//初始极性1
    timer_cmpval_set(10, 15);//设置比较值
    timer_overflow_set(20);//设置溢出值
    timer_en_ctrl(ENABLE);//使能定时器
    timer_capi_trig_set(0, TIMER_TRIG_N);//捕获输入0，下降沿触发
    timer_capi_trig_set(1, TIMER_TRIG_D);//捕获输入1，双沿触发
    delay_mtime_us(100);//延时100us
    tmp = timer_cap_val_read();//读取捕获值
    printf("capi0 = %u, capi1 = %u\n",(tmp&0x0000FFFF),(tmp>>16));
    tmp = timer_cnt_val_read();//读取计数器值
    printf("timer cnt = %u\n",tmp);
    timer_en_ctrl(DISABLE);//关闭定时器外设
}
