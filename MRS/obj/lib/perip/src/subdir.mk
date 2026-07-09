################################################################################
# MRS Version: 2.3.0
# Automatically-generated file. Do not edit!
################################################################################

# Add inputs and outputs from these tool invocations to the build variables 
C_SRCS += \
../lib/perip/src/core.c \
../lib/perip/src/fpioa.c \
../lib/perip/src/plic.c \
../lib/perip/src/sdrd.c \
../lib/perip/src/spi.c \
../lib/perip/src/timer.c \
../lib/perip/src/trap.c \
../lib/perip/src/uart.c 

C_DEPS += \
./lib/perip/src/core.d \
./lib/perip/src/fpioa.d \
./lib/perip/src/plic.d \
./lib/perip/src/sdrd.d \
./lib/perip/src/spi.d \
./lib/perip/src/timer.d \
./lib/perip/src/trap.d \
./lib/perip/src/uart.d 

OBJS += \
./lib/perip/src/core.o \
./lib/perip/src/fpioa.o \
./lib/perip/src/plic.o \
./lib/perip/src/sdrd.o \
./lib/perip/src/spi.o \
./lib/perip/src/timer.o \
./lib/perip/src/trap.o \
./lib/perip/src/uart.o 

DIR_OBJS += \
./lib/perip/src/*.o \

DIR_DEPS += \
./lib/perip/src/*.d \

DIR_EXPANDS += \
./lib/perip/src/*.253r.expand \


# Each subdirectory must supply rules for building sources it contributes
lib/perip/src/%.o: ../lib/perip/src/%.c
	@	riscv-wch-elf-gcc -march=rv32im -mabi=ilp32 -msmall-data-limit=8 -mno-save-restore -fmax-errors=20 -O3 -fmessage-length=0 -ffunction-sections -fdata-sections -g -I"d:/PDS/test/Sparrow_RISC-V/MRS/app" -I"d:/PDS/test/Sparrow_RISC-V/MRS/lib" -I"d:/PDS/test/Sparrow_RISC-V/MRS/lib/perip/include" -I"d:/PDS/test/Sparrow_RISC-V/MRS/lib/driver/include" -I"d:/PDS/test/Sparrow_RISC-V/MRS/example/coremark" -std=gnu99 -MMD -MP -MF"$(@:%.o=%.d)" -MT"$(@)" -c -o "$@" "$<"

