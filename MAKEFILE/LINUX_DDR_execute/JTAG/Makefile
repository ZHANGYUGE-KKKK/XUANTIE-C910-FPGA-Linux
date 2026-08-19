MAKEFILE_PATH := $(lastword $(MAKEFILE_LIST))
JTAG_DIR := $(patsubst %/,%,$(dir $(MAKEFILE_PATH)))
PROGRAM_DIR := $(JTAG_DIR)/..
MAKEFILE_DIR := $(PROGRAM_DIR)/..

TOOLCHAIN_BIN := $(MAKEFILE_DIR)/Xuantie-900-gcc-elf-newlib-mingw-V3.2.0/bin
CC := $(TOOLCHAIN_BIN)/riscv64-unknown-elf-gcc
OBJCOPY := $(TOOLCHAIN_BIN)/riscv64-unknown-elf-objcopy
OBJDUMP := $(TOOLCHAIN_BIN)/riscv64-unknown-elf-objdump
READELF := $(TOOLCHAIN_BIN)/riscv64-unknown-elf-readelf
SIZE := $(TOOLCHAIN_BIN)/riscv64-unknown-elf-size

ARCH_FLAGS := -march=rv64imafdc_zicsr_zifencei -mabi=lp64d

BUILD_DIR := $(JTAG_DIR)/build
PAYLOAD_SRC := $(JTAG_DIR)/ddr_exec_payload.S
PAYLOAD_LD := $(JTAG_DIR)/ddr_exec_payload.ld
PAYLOAD_ELF := $(BUILD_DIR)/ddr_exec_payload.elf
PAYLOAD_BIN := $(BUILD_DIR)/ddr_exec_payload.bin
PAYLOAD_DUMP := $(BUILD_DIR)/ddr_exec_payload.dump
PAYLOAD_MAP := $(BUILD_DIR)/ddr_exec_payload.map

.PHONY: all check clean

all: $(PAYLOAD_ELF) $(PAYLOAD_BIN) $(PAYLOAD_DUMP) check
	@echo "DDR execute payload ELF is ready: $(PAYLOAD_ELF)"

$(BUILD_DIR):
	@if not exist "$(BUILD_DIR)" mkdir "$(BUILD_DIR)"

$(PAYLOAD_ELF): $(PAYLOAD_SRC) $(PAYLOAD_LD) | $(BUILD_DIR)
	@echo "Building DDR execute payload ELF..."
	@$(CC) $(ARCH_FLAGS) -nostdlib -nostartfiles "-Wl,-T,$(PAYLOAD_LD),-Map,$(PAYLOAD_MAP)" $(PAYLOAD_SRC) -o $@
	@$(SIZE) $@

$(PAYLOAD_BIN): $(PAYLOAD_ELF)
	@$(OBJCOPY) -O binary $< $@

$(PAYLOAD_DUMP): $(PAYLOAD_ELF)
	@powershell -NoProfile -ExecutionPolicy Bypass -Command "$$dump = & '$(OBJDUMP)' -d -S -h '$(PAYLOAD_ELF)'; if ($$LASTEXITCODE -ne 0) { exit $$LASTEXITCODE }; [System.IO.File]::WriteAllLines('$(PAYLOAD_DUMP)', $$dump, [System.Text.Encoding]::ASCII)"

check: $(PAYLOAD_ELF)
	@powershell -NoProfile -ExecutionPolicy Bypass -Command "$$headers = & '$(READELF)' -l '$(PAYLOAD_ELF)'; if ($$LASTEXITCODE -ne 0) { exit $$LASTEXITCODE }; $$text = $$headers -join \"`n\"; if ($$text -notmatch '0x0000000200000000') { throw 'DDR execute payload ELF does not load at 0x0200000000.' }; Write-Host 'DDR execute payload check passed: load address 0x0200000000.'"

clean:
	@if exist "$(BUILD_DIR)" rmdir /S /Q "$(BUILD_DIR)"
