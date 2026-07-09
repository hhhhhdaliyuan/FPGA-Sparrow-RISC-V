################################################################################
# MRS Version: 2.3.0
# Automatically-generated file. Do not edit!
################################################################################

# Add inputs and outputs from these tool invocations to the build variables 
C_SRCS += \
../lib/startup/init.c 

C_DEPS += \
./lib/startup/init.d 

S_UPPER_SRCS += \
../lib/startup/startup.S 

S_UPPER_DEPS += \
./lib/startup/startup.d 

OBJS += \
./lib/startup/init.o \
./lib/startup/startup.o 

DIR_OBJS += \
./lib/startup/*.o \

DIR_DEPS += \
./lib/startup/*.d \

DIR_EXPANDS += \
./lib/startup/*.253r.expand \


# Each subdirectory must supply rules for building sources it contributes
lib/startup/%.o: ../lib/startup/%.c
	@	riscv-wch-elf-gcc -march=rv32im -mabi=ilp32 -msmall-data-limit=8 -mno-save-restore -fmax-errors=20 -O3 -fmessage-length=0 -ffunction-sections -fdata-sections -g -I"d:/PDS/test/Sparrow_RISC-V/MRS/app" -I"d:/PDS/test/Sparrow_RISC-V/MRS/lib" -I"d:/PDS/test/Sparrow_RISC-V/MRS/lib/perip/include" -I"d:/PDS/test/Sparrow_RISC-V/MRS/lib/driver/include" -I"d:/PDS/test/Sparrow_RISC-V/MRS/example/coremark" -std=gnu99 -MMD -MP -MF"$(@:%.o=%.d)" -MT"$(@)" -c -o "$@" "$<"

lib/startup/%.o: ../lib/startup/%.S
	@	riscv-wch-elf-gcc -march=rv32im -mabi=ilp32 -msmall-data-limit=8 -mno-save-restore -fmax-errors=20 -O3 -fmessage-length=0 -ffunction-sections -fdata-sections -g -x assembler-with-cpp -I"d:/PDS/test/Sparrow_RISC-V/MRS/lib/startup" -MMD -MP -MF"$(@:%.o=%.d)" -MT"$(@)" -c -o "$@" "$<"

