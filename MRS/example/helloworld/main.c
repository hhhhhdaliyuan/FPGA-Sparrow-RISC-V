#include "system.h"
volatile uint32_t cnt;
uint32_t tmp;

//HelloWord，间隔1s循环打印系统信息
int main()
{
    init_uart0_printf(115200,0);//设置波特率
    printf("%s", "Hello world SparrowRV\n");
    printf("%s", "--------------\n");
    while(1)
    {
        printf("%s", "Hello world SparrowRV\n");
        printf("sys freq = %lu Hz\n",system_cpu_freq);//读取CPU主频，RTL综合阶段配置在CPU_CLOCK_HZ
        printf("cpu_iram_size = %lu Byte\n",system_iram_size);//读取iram大小
        printf("cpu_sram_size = %lu Byte\n",system_sram_size);//读取sram大小
        printf("Vendor ID = %lx \n\n",system_vendorid);//读取VID
        delay_mtime_us(1000000);//延迟一秒
    }
}
