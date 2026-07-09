#include "system.h"

/*串口环回
115200波特率，FPIOA[0]输出，/FPIOA[1]输入，输入数据直接转发输出
不要连续发太多数据，软件处理速度可能跟不上 
*/
int main()
{
    init_uart0_printf(115200,0);//设置printf波特率，FPIOA[0]为TX
    printf("SparrowRV uart loopback\n");
    fpioa_perips_in_set(UART0_RX, 1);//FPIOA[1]为RX
    while(1)
    {
        if(uart_recv_flg(UART0))//收到数据
            uart_send_date(UART0, uart_recv_date(UART0));//发送
    }
}
