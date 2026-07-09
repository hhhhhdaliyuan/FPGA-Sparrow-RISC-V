#include <stdint.h>
#include "core.h"

/*********************************************************************
 * @fn      mtime_value_get
 *
 * @brief   读取mtime值
 *
 * @param   无
 *
 * @return  返回uint64_t的mtime值
 */
uint64_t mtime_value_get()
{
    uint64_t temp;
    mtime_en_ctr(DISABLE);
    temp = read_csr(mtime);
    temp += (uint64_t)(read_csr(mtimeh)) << 32;
    mtime_en_ctr(ENABLE);
    return temp;
}

/*********************************************************************
 * @fn      mtime_value_set
 *
 * @brief   写入mtime
 *
 * @param   value64b - uint64_t的写入值
 *
 * @return  无
 */
void mtime_value_set(uint64_t value64b)
{
    uint32_t temp;
    temp = value64b;
    write_csr(mtime, temp);
    temp = value64b>>32;
    write_csr(mtimeh, temp);
}

/*********************************************************************
 * @fn      mtime_en_ctr
 *
 * @brief   mtime计数开关
 *
 * @param   mtime_en - 输入开关状态
 *              ENABLE - 打开mtime计数
 *             DISABLE - 关闭mtime计数
 *
 * @return  无
 */
void mtime_en_ctr(uint8_t mtime_en)
{
    if(mtime_en == ENABLE)
        set_csr(mcctr, 0b00100);
    else
        clear_csr(mcctr, 0b00100);

}

/*********************************************************************
 * @fn      mtimecmp_value_set
 *
 * @brief   写入mtimecmp
 *
 * @param   value64b - uint64_t的写入值
 *
 * @return  无
 */
void mtimecmp_value_set(uint64_t value64b)
{
    uint32_t temp;
    temp = value64b;
    write_csr(mtimecmp, temp);
    temp = value64b>>32;
    write_csr(mtimecmph, temp);
}

/*********************************************************************
 * @fn      minstret_value_get
 *
 * @brief   读取minstret值
 *
 * @param   无
 *
 * @return  返回uint64_t的minstret值
 */
uint64_t minstret_value_get()
{
    uint64_t temp;
    minstret_en_ctr(DISABLE);
    temp = read_csr(minstret);
    temp += (uint64_t)(read_csr(minstreth)) << 32;
    minstret_en_ctr(ENABLE);
    return temp;
}

/*********************************************************************
 * @fn      minstret_value_set
 *
 * @brief   写入minstret
 *
 * @param   value64b - uint64_t的写入值
 *
 * @return  无
 */
void minstret_value_set(uint64_t value64b)
{
    uint32_t temp;
    temp = value64b;
    write_csr(minstret, temp);
    temp = value64b>>32;
    write_csr(minstreth, temp);
}

/*********************************************************************
 * @fn      minstret_en_ctr
 *
 * @brief   minstret计数开关
 *
 * @param   minstret_en - 输入开关状态
 *              ENABLE - 打开minstret计数
 *             DISABLE - 关闭minstret计数
 *
 * @return  无
 */
void minstret_en_ctr(uint8_t minstret_en)
{
    if(minstret_en == ENABLE)
        set_csr(mcctr, 0b00010);
    else
        clear_csr(mcctr, 0b00010);

}

/*********************************************************************
 * @fn      delay_mtime_us
 *
 * @brief   硬件延时函数
 *
 * @param   us - 延时单位us
 *
 * @return  无
 */
//延时使用mtime完成，影响定时器相关功能
void delay_mtime_us(uint32_t us)
{
    uint64_t count;
    mtime_en_ctr(DISABLE);//暂停定时器
    trap_en_ctrl(TRAP_TCMP, DISABLE);//关闭定时器中断
    count = us * system_cpu_freqM;//计算计数值
    mtimecmp_value_set(count);//设置比较值
    mtime_value_set(0);//设置定时器值
    mtime_en_ctr(ENABLE);//启动定时器
    while (!trap_mip_state(TRAP_TCMP));//等定时器中断被触发
}

/*********************************************************************
 * @fn      core_reset_enable
 *
 * @brief   软件复位
 *
 * @param   无
 *
 * @return  无
 */
void core_reset_enable()
{
    set_csr(mcctr, 0b01000);
}

/*********************************************************************
 * @fn      core_sim_end
 *
 * @brief   仿真结束
 *
 * @param   无
 *
 * @return  无
 */
void core_sim_end()
{
    write_csr(mends,1);
}

/*********************************************************************
 * @fn      core_soft_interrupt
 *
 * @brief   触发软件中断
 *
 * @param   无
 *
 * @return  无
 */
void core_soft_interrupt()
{
    set_csr(msip, 0x01);
}

/*********************************************************************
 * @fn      csr_msprint_string
 *
 * @brief   仿真打印字符
 *
 * @param   str - 待打印的字符串，NULL结束
 *
 * @return  无
 */
void csr_msprint_string(uint8_t *str)
{
    while (*str)//检测字符串结束标志
    {
        write_csr(msprint, *str++);//msprint打印当前字符
    }
}