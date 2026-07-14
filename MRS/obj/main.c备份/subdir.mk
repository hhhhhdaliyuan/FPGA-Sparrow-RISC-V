################################################################################
# MRS Version: 2.3.0
# Automatically-generated file. Do not edit!
################################################################################

# Add inputs and outputs from these tool invocations to the build variables 
C_SRCS += \
../main.c备份/BFS+投影法.c \
../main.c备份/BFS环形队列完整代码.c \
../main.c备份/发送原图和二值化图.c \
../main.c备份/角度矫正+二值化处理+字符分割.c 

C_DEPS += \
./main.c备份/BFS+投影法.d \
./main.c备份/BFS环形队列完整代码.d \
./main.c备份/发送原图和二值化图.d \
./main.c备份/角度矫正+二值化处理+字符分割.d 

OBJS += \
./main.c备份/BFS+投影法.o \
./main.c备份/BFS环形队列完整代码.o \
./main.c备份/发送原图和二值化图.o \
./main.c备份/角度矫正+二值化处理+字符分割.o 

DIR_OBJS += \
./main.c备份/*.o \

DIR_DEPS += \
./main.c备份/*.d \

DIR_EXPANDS += \
./main.c备份/*.253r.expand \


# Each subdirectory must supply rules for building sources it contributes
main.c备份/%.o: ../main.c备份/%.c
	@	riscv-wch-elf-gcc -march=rv32im -mabi=ilp32 -msmall-data-limit=8 -mno-save-restore -fmax-errors=20 -O3 -fmessage-length=0 -ffunction-sections -fdata-sections -g -I"d:/PDS/test/Sparrow_RISC-V/MRS/app" -I"d:/PDS/test/Sparrow_RISC-V/MRS/lib" -I"d:/PDS/test/Sparrow_RISC-V/MRS/lib/perip/include" -I"d:/PDS/test/Sparrow_RISC-V/MRS/lib/driver/include" -I"d:/PDS/test/Sparrow_RISC-V/MRS/example/coremark" -std=gnu99 -MMD -MP -MF"$(@:%.o=%.d)" -MT"$(@)" -c -o "$@" "$<"

