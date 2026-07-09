#include "system.h"
uint8_t cnt;
uint32_t tmp;
//测试FPIOA_ELI外部异常
int main()
{
    init_uart0_printf(115200,0);//设置波特率
    printf("%s", "ELI CH0-4 lian jie dao FPIOA[0]\n");
    printf("%s", "--------------\n");
    fpioa_perips_in_set(ELI_CH0, 0);//FPIOA[0]映射到ELI_CH0
    fpioa_perips_in_set(ELI_CH1, 0);//FPIOA[0]映射到ELI_CH1
    fpioa_perips_in_set(ELI_CH2, 0);//FPIOA[0]映射到ELI_CH2
    fpioa_perips_in_set(ELI_CH3, 0);//FPIOA[0]映射到ELI_CH3
    fpioa_eli_mode_set(ELI_CH0_SEL, ELI_TRIG_HL, ENABLE);//ELI_CH0高电平触发
    fpioa_eli_mode_set(ELI_CH1_SEL, ELI_TRIG_PE | ELI_TRIG_NE, ENABLE);//ELI_CH1上升或下降沿触发
    fpioa_eli_mode_set(ELI_CH2_SEL, ELI_TRIG_LL, ENABLE);//ELI_CH2低电平触发
    fpioa_eli_mode_set(ELI_CH3_SEL, ELI_TRIG_PE | ELI_TRIG_HL, ENABLE);//ELI_CH3上升沿或高电平触发
    while(1)
    {
        delay_mtime_us(10);
    }
}
