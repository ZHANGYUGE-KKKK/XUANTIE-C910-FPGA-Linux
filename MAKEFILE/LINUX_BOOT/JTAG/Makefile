MAKEFILE_PATH := $(lastword $(MAKEFILE_LIST))
JTAG_DIR := $(patsubst %/,%,$(dir $(MAKEFILE_PATH)))
PROGRAM_DIR := $(JTAG_DIR)/..
MAKEFILE_DIR := $(PROGRAM_DIR)/..

OPENSBI_DIR := $(PROGRAM_DIR)/third_party/opensbi
BUILD_DIR := $(PROGRAM_DIR)/BUILD
OPENSBI_BUILD_DIR := $(BUILD_DIR)/opensbi

CROSS_COMPILE ?= $(MAKEFILE_DIR)/Xuantie-900-gcc-elf-newlib-mingw-V3.2.0/bin/riscv64-unknown-elf-
DTC ?= dtc

OPENSBI_LOAD_ADDR := 0x0200000000
UBOOT_LOAD_ADDR := 0x0200200000
DTB_LOAD_ADDR := 0x0210000000

DTS_SRC := $(PROGRAM_DIR)/DTS/c910_soc_minimal.dts
DTB := $(BUILD_DIR)/c910_soc_minimal.dtb
FW_JUMP_ELF := $(OPENSBI_BUILD_DIR)/platform/generic/firmware/fw_jump.elf
FW_JUMP_BIN := $(OPENSBI_BUILD_DIR)/platform/generic/firmware/fw_jump.bin

.PHONY: all opensbi dtb check clean

all: opensbi dtb check
	@echo "Linux boot OpenSBI artifacts are ready."

$(BUILD_DIR):
	@if not exist "$(BUILD_DIR)" mkdir "$(BUILD_DIR)"

dtb: $(DTB)

$(DTB): $(DTS_SRC) | $(BUILD_DIR)
	@$(DTC) -I dts -O dtb -o "$(DTB)" "$(DTS_SRC)"

opensbi:
	@$(MAKE) -C "$(OPENSBI_DIR)" PLATFORM=generic CROSS_COMPILE="$(CROSS_COMPILE)" O="$(OPENSBI_BUILD_DIR)" FW_TEXT_START=$(OPENSBI_LOAD_ADDR) FW_JUMP=y FW_JUMP_ADDR=$(UBOOT_LOAD_ADDR) FW_JUMP_FDT_ADDR=$(DTB_LOAD_ADDR)

check: $(DTB)
	@if not exist "$(FW_JUMP_ELF)" (echo "Missing OpenSBI ELF: $(FW_JUMP_ELF)" & exit /B 1)
	@if not exist "$(FW_JUMP_BIN)" (echo "Missing OpenSBI BIN: $(FW_JUMP_BIN)" & exit /B 1)
	@echo "OpenSBI load address : $(OPENSBI_LOAD_ADDR)"
	@echo "U-Boot next address  : $(UBOOT_LOAD_ADDR)"
	@echo "DTB load address     : $(DTB_LOAD_ADDR)"
	@echo "OpenSBI ELF          : $(FW_JUMP_ELF)"
	@echo "DTB                  : $(DTB)"

clean:
	@if exist "$(BUILD_DIR)" rmdir /S /Q "$(BUILD_DIR)"
