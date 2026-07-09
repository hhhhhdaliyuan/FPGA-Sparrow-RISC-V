`timescale 1ns/1ns
`include "defines.v"
module tb_soc(); 

`define CorePath inst_sparrow_soc.inst_core
`define IRAMPath inst_sparrow_soc.inst_iram.RAM

//测试DUT信号
logic clk;//时钟信号
logic randem;//产生异步信号
logic rst_n;//复位
logic core_ex_trap_valid, core_ex_trap_ready;//外部中断线
logic JTAG_TCK,JTAG_TMS,JTAG_TDI,JTAG_TDO;//jtag
wire sd_clk,sd_cmd,sd_dat;//sd卡
wire [2:0]sd_dat123;//sd卡上拉线
wire [`FPIOA_PORT_NUM-1:0]fpioa;

//仿真显示信号
logic [63:0] sim_cycle_cnt = '0;//仿真周期计数器
localparam sim_printf_line_length = 64;//显示printf的最大单行字符数
int sim_printf_p = sim_printf_line_length;//仿真csr printf的显示终端指针
logic [7:0] sim_printf_ascii = '0;//仿真csr printf的字符
logic [sim_printf_line_length*8-1:0] sim_printf_line = '0;//仿真csr printf的显示终端，和处理器运行状态同步

//assign fpioa[3:2] = 0;

assign fpioa[1]=randem;

wire uart0_tx=fpioa[0];//fpioa[1]

//测试信号
assign fpioa[7] = 1'b1;

integer r;//计数工具人
//寄存器监测
wire [31:0] x3  = `CorePath.inst_regs.regs[3];
`ifndef RV32E_BASE_ISA
wire [31:0] x26 = `CorePath.inst_regs.regs[26];
wire [31:0] x27 = `CorePath.inst_regs.regs[27];
`endif
wire mends = `CorePath.inst_csr.mends;//抓取仿真结束标志CSR mends

// 读入程序
initial begin
    for(r=0; r<`IRamSize; r=r+1) begin//先填充0
        `IRAMPath[r] = 32'h0;
    end
    $readmemh ("inst.txt", `IRAMPath);//把程序(inst.txt)写进去
end

// 生成clk
initial begin
    clk = '0;
    forever #(5) clk = ~clk;
end

// 生成异步信号
initial begin
    randem = '0;
    forever #(61) randem = ~randem;
end

//仿真周期计数
always @(posedge clk) 
    sim_cycle_cnt <= sim_cycle_cnt+1;


//启动仿真流程
initial begin
    sysrst();//复位系统
    #10;
`ifdef ISA_TEST  //通过宏定义，查看是否是指令集测试程序
    isa_test_task();//抓取关键信号
`else //不做ISA测试，执行其他程序
    //自定义操作
    ex_trap();//测试外部中断
`endif
end

initial begin//超时强制结束
    #500000;
`ifdef ISA_TEST
    $display("*Sim tool:ISA_TEST Timeout, Err");//ISA测试超时
    $display("*Sim tool:Sim cycle = %d", sim_cycle_cnt);
`else 
    $display("*Sim tool:Normal Sim Timeout");//普通仿真超时
    $display("*Sim tool:Sim cycle = %d", sim_cycle_cnt);
`endif
    $stop;
end

//软件控制仿真结束
initial begin
    #30;
    wait(mends === 1'b1)//CSR mends写1结束仿真
    $display("*Sim tool:CSR MENDS END, stop sim");
    $display("*Sim tool:Sim cycle = %d", sim_cycle_cnt);
    #10;
    $stop;
end

task sysrst;//复位任务
    core_ex_trap_valid=0;//关闭外部中断线
    JTAG_TCK=0;//JTAG不工作
    JTAG_TMS=0;
    JTAG_TDI=0;
    rst_n <= '0;//复位
    #20
    rst_n <= '1;
    #10;
endtask : sysrst

task isa_test_task;
    wait(x26 == 32'b1);   // x26 == 1，测试程序结束
    @(posedge clk);//等3个周期
    @(posedge clk);
    @(posedge clk);
    if (x27 == 32'b1) begin //x27写1则通过测试
    $display("~~~~~~~~~~~~~~~~~~~ TEST_PASS ~~~~~~~~~~~~~~~~~~~");
    $display("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~");
    $display("~~~~~~~~~ #####     ##     ####    #### ~~~~~~~~~");
    $display("~~~~~~~~~ #    #   #  #   #       #     ~~~~~~~~~");
    $display("~~~~~~~~~ #    #  #    #   ####    #### ~~~~~~~~~");
    $display("~~~~~~~~~ #####   ######       #       #~~~~~~~~~");
    $display("~~~~~~~~~ #       #    #  #    #  #    #~~~~~~~~~");
    $display("~~~~~~~~~ #       #    #   ####    #### ~~~~~~~~~");
    $display("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~");
    end else begin //错误
    $display("~~~~~~~~~~~~~~~~~~~ TEST_FAIL ~~~~~~~~~~~~~~~~~~~~");
    $display("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~");
    $display("~~~~~~~~~~######    ##       #    #     ~~~~~~~~~~");
    $display("~~~~~~~~~~#        #  #      #    #     ~~~~~~~~~~");
    $display("~~~~~~~~~~#####   #    #     #    #     ~~~~~~~~~~");
    $display("~~~~~~~~~~#       ######     #    #     ~~~~~~~~~~");
    $display("~~~~~~~~~~#       #    #     #    #     ~~~~~~~~~~");
    $display("~~~~~~~~~~#       #    #     #    ######~~~~~~~~~~");
    $display("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~");
    $display("fail testnum = %2d", x3); //x3记录测试case
    for (r = 1; r < 32; r = r + 1)
        $display("x%2d = 0x%x", r, `CorePath.inst_regs.regs[r]);
    end
    $stop;//结束
endtask : isa_test_task

task ex_trap;//外部中断测试
    #15000;
    core_ex_trap_valid=1;//使能外部中断线
    #30;
    wait(core_ex_trap_ready);//等待响应
    core_ex_trap_valid=0;//取消信号
endtask : ex_trap


genvar i;
generate
    for ( i=0; i<`FPIOA_PORT_NUM ; i++) begin//fpioa信号弱下拉，防止出现不定态
        assign (weak1,weak0) fpioa[i] = 1'b0;
    end
endgenerate

//显示printf单行内容，遇到转义符n r则刷新
//以ASCII模式查看sim_printf_line
always @(posedge clk) begin
    if(`CorePath.inst_csr.printf_valid) begin
        sim_printf_ascii = `CorePath.inst_csr.idex_csr_wdata_i[7:0];//读取printf的内容
        if(sim_printf_ascii==8'h0A || sim_printf_ascii==8'h0D) begin
            sim_printf_p = sim_printf_line_length;
            sim_printf_line = '0;
        end
        else begin
            for (int printf_bitp = 0; printf_bitp < 8; printf_bitp=printf_bitp+1) begin
                sim_printf_line[(sim_printf_p-1)*8+printf_bitp] = sim_printf_ascii[printf_bitp];
            end
            sim_printf_p = sim_printf_p-1;
        end
    end 
end
//如果inst.txt读入失败，停止仿真
initial begin
    wait(rst_n===1'b1);
    if(`IRAMPath[0]==32'h0) begin
        $display("*Sim tool:Inst Load error, Miss inst.txt");
        #10;
        $stop;
    end
end

//打印trace.log，显示程序执行流
`ifdef SIM_TRACE_LOG
reg core_if_req_r;//if_req缓存1拍
always_ff @(posedge clk) begin
    core_if_req_r <= `CorePath.if_req_o;
end
integer file;
wire trace_core_icb_hsk = `CorePath.core_icb_cmd_valid & `CorePath.core_icb_cmd_ready;//内核ICB总线握手
initial begin
    file = $fopen("./trace.log", "w");//新建或覆盖/tb/trace.log
    forever begin
        @(posedge clk);
        #0;
        if(`CorePath.inst_valid & core_if_req_r & ~`CorePath.trap_in & `CorePath.rst_n) begin//取指成功，指令不重复，不是异常
            $fdisplay(file, "%0d ->PC:%h INST:%h", sim_cycle_cnt, `CorePath.pc, `CorePath.inst);//仿真周期计数    PC:PC值 inst:指令码
        end
        if(`CorePath.reg_we_sctr & `CorePath.rst_n) begin//写回寄存器
            $fdisplay(file, "%0d  [REG W] X%0d:%h", sim_cycle_cnt, `CorePath.reg_waddr, `CorePath.reg_wdata);
        end
        if(trace_core_icb_hsk & `CorePath.rst_n) begin//访存
            if (`CorePath.core_icb_cmd_read)//读总线
                $fdisplay(file, "%0d  [MEM R]ADDR:%h", sim_cycle_cnt, `CorePath.core_icb_cmd_addr);
            else//写总线
                $fdisplay(file, "%0d  [MEM W]ADDR:%h DATA:%h", sim_cycle_cnt, `CorePath.core_icb_cmd_addr, `CorePath.core_icb_cmd_wdata);
        end
        if (`CorePath.trap_jump & (`CorePath.inst_trap.sta_n == `CorePath.inst_trap.IDLE)) begin//发生异常
            if (`CorePath.inst_csr.mcause[31] == 1'b1) //中断
                $fdisplay(file, "%0d ->[Trap] Type: interrupt :", sim_cycle_cnt);
            else//异常
                $fdisplay(file, "%0d ->[Trap] Type: exception :", sim_cycle_cnt);
            case (`CorePath.inst_csr.mcause)//检测类型
                `TRAP_EXCEP : $fdisplay(file, "Trap cause: System Exception");
                `TRAP_ZERO  : $fdisplay(file, "Trap cause: ZERO  ");
                `TRAP_ERESV : $fdisplay(file, "Trap cause: Excep RESV");
                `TRAP_SOFTI : $fdisplay(file, "Trap cause: Soft Interrupt");
                `TRAP_TIMER : $fdisplay(file, "Trap cause: Timer CMP");
                `TRAP_PLIC0 : $fdisplay(file, "Trap cause: PLIC0 ");
                `TRAP_PLIC1 : $fdisplay(file, "Trap cause: PLIC1 ");
                `TRAP_PLIC2 : $fdisplay(file, "Trap cause: PLIC2 ");
                `TRAP_PLIC3 : $fdisplay(file, "Trap cause: PLIC3 ");
                `TRAP_PLIC4 : $fdisplay(file, "Trap cause: PLIC4 ");
                `TRAP_PLIC5 : $fdisplay(file, "Trap cause: PLIC5 ");
                `TRAP_PLIC6 : $fdisplay(file, "Trap cause: PLIC6 ");
                `TRAP_PLIC7 : $fdisplay(file, "Trap cause: PLIC7 ");
                `TRAP_PLIC8 : $fdisplay(file, "Trap cause: PLIC8 ");
                `TRAP_PLIC9 : $fdisplay(file, "Trap cause: PLIC9 ");
                `TRAP_PLIC10: $fdisplay(file, "Trap cause: PLIC10");
                `TRAP_PLIC11: $fdisplay(file, "Trap cause: PLIC11");
                `TRAP_PLIC12: $fdisplay(file, "Trap cause: PLIC12");
                `TRAP_PLIC13: $fdisplay(file, "Trap cause: PLIC13");
                `TRAP_PLIC14: $fdisplay(file, "Trap cause: PLIC14");
                `TRAP_PLIC15: $fdisplay(file, "Trap cause: PLIC15");
                default: $fdisplay(file, "Trap cause: NULL  ");
            endcase
            $fdisplay(file, "mstatus:%h", `CorePath.inst_csr.mstatus);
            $fdisplay(file, "mepc   :%h"   , `CorePath.inst_csr.mepc);
            $fdisplay(file, "mcause :%h" , `CorePath.inst_csr.mcause);
            $fdisplay(file, "mtval  :%h"  , `CorePath.inst_csr.mtval);
            $fdisplay(file, "mtvec  :%h"  , `CorePath.inst_csr.mtvec);
        end
    end
end
`endif

sparrow_soc inst_sparrow_soc (
    .clk               (clk), 
    .hard_rst_n        (rst_n), 
    .core_active       (),
`ifdef JTAG_DBG_MODULE
    .JTAG_TCK          (JTAG_TCK),
    .JTAG_TMS          (JTAG_TMS),
    .JTAG_TDI          (JTAG_TDI),
    .JTAG_TDO          (JTAG_TDO),
`endif
    .sd_clk            (sd_clk),
    .sd_cmd            (sd_cmd),
    .sd_dat            ({sd_dat123,sd_dat}),
    .fpioa             (fpioa)//处理器IO接口
);


`ifdef SIM_SD_MODEL
sd_fake inst_sd_fake
(
    .rstn_async       (rst_n),
    .sdclk            (sd_clk),
    .sdcmd            (sd_cmd),
    .sddat            ({sd_dat123, sd_dat}),
    .show_status_bits (),
    .show_sdcmd_en    (),
    .show_sdcmd_cmd   (),
    .show_sdcmd_arg   ()
);
`endif

//输出波形
initial begin
    $dumpfile("tb.vcd");  //生成lxt的文件名称
    $dumpvars(0,tb_soc);   //tb中实例化的仿真目标实例名称   
end

endmodule