################################################################################
# MRS Version: 2.3.0
# Automatically-generated file. Do not edit!
################################################################################

# Add inputs and outputs from these tool invocations to the build variables 
C_SRCS += \
../main.c代码备份/main.c 

C_DEPS += \
./main.c代码备份/main.d 

OBJS += \
./main.c代码备份/main.o 

DIR_OBJS += \
./main.c代码备份/*.o \

DIR_DEPS += \
./main.c代码备份/*.d \

DIR_EXPANDS += \
./main.c代码备份/*.253r.expand \


# Each subdirectory must supply rules for building sources it contributes
main.c代码备份/%.o: ../main.c代码备份/%.c
	@	riscv-wch-elf-gcc -march=rv32im -mabi=ilp32 -msmall-data-limit=8 -mno-save-restore -fmax-errors=20 -O3 -fmessage-length=0 -ffunction-sections -fdata-sections -g -I"d:/PDS/test/Sparrow_RISC-V/MRS/app" -I"d:/PDS/test/Sparrow_RISC-V/MRS/lib" -I"d:/PDS/test/Sparrow_RISC-V/MRS/lib/perip/include" -I"d:/PDS/test/Sparrow_RISC-V/MRS/lib/driver/include" -I"d:/PDS/test/Sparrow_RISC-V/MRS/example/coremark" -std=gnu99 -MMD -MP -MF"$(@:%.o=%.d)" -MT"$(@)" -c -o "$@" "$<"

