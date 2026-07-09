//#include "system.h"
#include <stdint.h>
//系统信息
uint32_t system_cpu_freq;//处理器频率
uint32_t system_cpu_freqM;//处理器频率，单位M
uint32_t system_iram_size;//指令存储器大小kb
uint32_t system_sram_size;//数据存储器大小kb
uint32_t system_vendorid;//Vendor ID

extern void trap_vector_tab();//声明外部的中断向量表

#define __read_csr(reg) ({ unsigned long __tmp; \
  asm volatile ("csrr %0, " #reg : "=r"(__tmp)); \
  __tmp; })
#define __write_csr(reg, val) ({ \
  if (__builtin_constant_p(val) && (unsigned long)(val) < 32) \
    asm volatile ("csrw " #reg ", %0" :: "i"(val)); \
  else \
    asm volatile ("csrw " #reg ", %0" :: "r"(val)); })
#define read_csr(reg)        __read_csr(reg)       //读取CSR
#define write_csr(reg, val)  __write_csr(reg, val) //写入CSR

//系统初始化，会在main()函数之前执行
void sparrowrv_system_init()
{
    uint32_t tmp;
    //设置中断向量表基地址
    write_csr(mtvec, &trap_vector_tab);
    //读取系统信息
    tmp=read_csr(mimpid);
    system_cpu_freq = (tmp & 0x00007FFF) * 10000;//读取时钟频率Hz
    system_cpu_freqM = system_cpu_freq / 1000000UL;//读取时钟频率MHz
    system_iram_size = ((tmp & 0x00FF0000) >> 16)*1024;//读取程序存储器iram的大小
    system_sram_size = (tmp >> 24)*1024;//读取数据存储器sram的大小
    system_vendorid = read_csr(mvendorid);//读取版本ID

    //可以写点其他的初始化代码
}
