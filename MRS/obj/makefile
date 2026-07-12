################################################################################
# MRS Version: 2.3.0
# Automatically-generated file. Do not edit!
################################################################################
-include ../makefile.init

RM := rm -rf

# All of the sources participating in the build are defined here
-include sources.mk
-include main.c±¸·Ý/subdir.mk
-include lib/startup/subdir.mk
-include lib/perip/src/subdir.mk
-include lib/driver/src/subdir.mk
-include app/subdir.mk
-include subdir.mk
-include objects.mk

ifneq ($(MAKECMDGOALS),clean)
ifneq ($(strip $(S_DEPS)),)
-include $(S_DEPS)
endif
ifneq ($(strip $(S_UPPER_DEPS)),)
-include $(S_UPPER_DEPS)
endif
ifneq ($(strip $(ASM_DEPS)),)
-include $(ASM_DEPS)
endif
ifneq ($(strip $(ASM_UPPER_DEPS)),)
-include $(ASM_UPPER_DEPS)
endif
ifneq ($(strip $(C_DEPS)),)
-include $(C_DEPS)
endif
endif

-include ../makefile.defs

# Add inputs and outputs from these tool invocations to the build variables 
SECONDARY_FLASH += \
SparrowRV_APP.bin \

SECONDARY_LIST += \
SparrowRV_APP.lst \

SECONDARY_SIZE += \
SparrowRV_APP.siz \


# All Target
all: 
	$(MAKE) --no-print-directory main-build 

main-build: SparrowRV_APP.elf secondary-outputs

# Tool invocations
SparrowRV_APP.elf: $(OBJS) $(USER_OBJS_ESCAPE)
	@	riscv-wch-elf-gcc -march=rv32im -mabi=ilp32 -msmall-data-limit=8 -mno-save-restore -fmax-errors=20 -O3 -fmessage-length=0 -ffunction-sections -fdata-sections -g -T "d:/PDS/test/Sparrow_RISC-V/MRS/link.lds" -nostartfiles -Xlinker --gc-sections -Wl,-Map,"SparrowRV_APP.map" --specs=nano.specs --specs=nosys.specs -o "SparrowRV_APP.elf" $(OBJS) $(LIBS)
SparrowRV_APP.bin: SparrowRV_APP.elf
	@	riscv-wch-elf-objcopy -O binary "SparrowRV_APP.elf" "SparrowRV_APP.bin"
SparrowRV_APP.lst: SparrowRV_APP.elf
	@	riscv-wch-elf-objdump --source --all-headers --demangle --line-numbers --wide "SparrowRV_APP.elf" > "SparrowRV_APP.lst"
SparrowRV_APP.siz: SparrowRV_APP.elf
	riscv-wch-elf-size --format=berkeley "SparrowRV_APP.elf"

# Other Targets
clean:
	-$(RM) $(DIR_OBJS) $(SECONDARY_FLASH)$(SECONDARY_LIST)$(SECONDARY_SIZE) SparrowRV_APP.elf
	-$(RM) $(DIR_EXPANDS) $(CALLGRAPH_DOT)
	-$(RM) $(DIR_DEPS)
secondary-outputs: $(SECONDARY_FLASH) $(SECONDARY_LIST) $(SECONDARY_SIZE)

.PHONY: all clean dependents

-include ../makefile.targets