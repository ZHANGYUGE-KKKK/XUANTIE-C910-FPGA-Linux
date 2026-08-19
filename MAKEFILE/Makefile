# Makefile 所在目录和工程根目录，供后续路径统一相对定位。
MAKEFILE_PATH := $(lastword $(MAKEFILE_LIST))
MAKEFILE_DIR := $(patsubst %/,%,$(dir $(MAKEFILE_PATH)))
PROJECT_ROOT := $(MAKEFILE_DIR)/..

# 当前裸机程序目录，可通过 make <文件夹名> 选择。
PROGRAM ?= UART
PROGRAM_DIR := $(MAKEFILE_DIR)/$(PROGRAM)

# BootROM 源文件、链接脚本和构建产物路径。
BOOTROM_DIR := $(PROGRAM_DIR)/BOOTROM
BOOTROM_BUILD_DIR := $(BOOTROM_DIR)/build
BOOTROM_SRC := $(BOOTROM_DIR)/bootrom.s
BOOTROM_LD := $(BOOTROM_DIR)/bootrom.ld
BOOTROM_ELF := $(BOOTROM_BUILD_DIR)/bootrom.elf
BOOTROM_BIN := $(BOOTROM_BUILD_DIR)/bootrom.bin
BOOTROM_DUMP := $(BOOTROM_BUILD_DIR)/bootrom.dump
BOOTROM_COE := $(BOOTROM_BUILD_DIR)/bootrom.coe
BOOTROM_MIF_TARGETS := \
	$(PROJECT_ROOT)/VIVADO/C910_SOC/C910_SOC.gen/sources_1/bd/C910_SOC/ip/C910_SOC_blk_mem_gen_0_0/C910_SOC_blk_mem_gen_0_0.mif \
	$(PROJECT_ROOT)/VIVADO/C910_SOC/C910_SOC.ip_user_files/mem_init_files/C910_SOC_blk_mem_gen_0_0.mif
COEFILES_DIR := $(MAKEFILE_DIR)/COEFILES
COEFILES_BOOTROM_BUILD_DIR := $(COEFILES_DIR)/build_bootrom

# BRAM 用户程序源文件、链接脚本和构建产物路径。
BRAM_DIR := $(PROGRAM_DIR)/BRAM
BRAM_BUILD_DIR := $(BRAM_DIR)/build
BRAM_SRCS := $(BRAM_DIR)/start.S $(BRAM_DIR)/main.c
BRAM_LD := $(BRAM_DIR)/bram.ld
BRAM_ELF := $(BRAM_BUILD_DIR)/bram.elf
BRAM_BIN := $(BRAM_BUILD_DIR)/bram.bin
BRAM_DUMP := $(BRAM_BUILD_DIR)/bram.dump
BRAM_COE := $(BRAM_BUILD_DIR)/bram.coe
BRAM_MIF_TARGETS := \
	$(PROJECT_ROOT)/VIVADO/C910_SOC/C910_SOC.gen/sources_1/bd/C910_SOC/ip/C910_SOC_blk_mem_gen_0_1/C910_SOC_blk_mem_gen_0_1.mif \
	$(PROJECT_ROOT)/VIVADO/C910_SOC/C910_SOC.ip_user_files/mem_init_files/C910_SOC_blk_mem_gen_0_1.mif
COEFILES_BRAM_BUILD_DIR := $(COEFILES_DIR)/build_ram

# 可选 JTAG 载荷构建入口；存在时由当前实验目录自行管理。
JTAG_MAKEFILE := $(PROGRAM_DIR)/JTAG/Makefile

# 玄铁 RISC-V 裸机交叉工具链。
TOOLCHAIN_BIN := $(MAKEFILE_DIR)/Xuantie-900-gcc-elf-newlib-mingw-V3.2.0/bin
CC := $(TOOLCHAIN_BIN)/riscv64-unknown-elf-gcc
OBJCOPY := $(TOOLCHAIN_BIN)/riscv64-unknown-elf-objcopy
OBJDUMP := $(TOOLCHAIN_BIN)/riscv64-unknown-elf-objdump
SIZE := $(TOOLCHAIN_BIN)/riscv64-unknown-elf-size

# RV64 架构/ABI 参数，以及 BootROM、BRAM 镜像尺寸设置。
# 默认启用 RVC 压缩指令；如需强制生成 32-bit 指令，可执行 make ENABLE_RVC=0。
ENABLE_RVC ?= 1
ifeq ($(ENABLE_RVC),1)
ARCH_FLAGS := -march=rv64imafdc_zicsr_zifencei -mabi=lp64d
else
ARCH_FLAGS := -march=rv64imafd_zicsr_zifencei -mabi=lp64d
endif
BOOTROM_SIZE_BYTES := 4096
BRAM_SIZE_BYTES := 65536
BRAM_PAD_TO_ADDR := 131072
INIT_WORD_BYTES := 16

# 声明伪目标，避免与同名文件冲突。
PROGRAM_GOALS := $(filter-out all bootrom bram jtag copy-builds bootrom-check bram-check clean,$(MAKECMDGOALS))
.PHONY: all bootrom bram jtag copy-builds bootrom-check bram-check clean $(PROGRAM_GOALS)

Makefile GNUmakefile MAKEFILE/Makefile: ;

# 默认目标：同时构建 BootROM、BRAM 和可选 JTAG 载荷，并复制构建结果。
all: bootrom bram jtag copy-builds

$(PROGRAM_GOALS):
	@if exist "$(MAKEFILE_DIR)/$@" ($(MAKE) -f "$(MAKEFILE_PATH)" PROGRAM=$@ all) else (echo "Unknown program folder: $(MAKEFILE_DIR)/$@" & exit /B 1)

# BootROM 完整构建流程：ELF、BIN、反汇编、COE 和一致性检查。
bootrom: $(BOOTROM_ELF) $(BOOTROM_BIN) $(BOOTROM_DUMP) $(BOOTROM_COE) $(BOOTROM_MIF_TARGETS) bootrom-check
	@echo "BootROM image is ready: $(BOOTROM_COE)"

# BRAM 完整构建流程：ELF、BIN、反汇编、COE 和一致性检查。
bram: $(BRAM_ELF) $(BRAM_BIN) $(BRAM_DUMP) $(BRAM_COE) $(BRAM_MIF_TARGETS) bram-check
	@echo "BRAM image is ready: $(BRAM_COE)"

# 若当前实验目录提供 JTAG/Makefile，则同步构建 JTAG 载荷。
jtag:
	@if exist "$(JTAG_MAKEFILE)" ($(MAKE) -f "$(JTAG_MAKEFILE)") else (echo "No JTAG payload Makefile for $(PROGRAM), skip.")

# 将本次构建结果复制到统一输出目录。
copy-builds: bootrom bram
	@powershell -NoProfile -ExecutionPolicy Bypass -Command "$$targets = @('$(COEFILES_BOOTROM_BUILD_DIR)', '$(COEFILES_BRAM_BUILD_DIR)'); foreach ($$target in $$targets) { if ([System.IO.Directory]::Exists($$target)) { Remove-Item -LiteralPath $$target -Recurse -Force } }; if (-not [System.IO.Directory]::Exists('$(COEFILES_DIR)')) { [System.IO.Directory]::CreateDirectory('$(COEFILES_DIR)') | Out-Null }; Copy-Item -LiteralPath '$(BOOTROM_BUILD_DIR)' -Destination '$(COEFILES_BOOTROM_BUILD_DIR)' -Recurse; Copy-Item -LiteralPath '$(BRAM_BUILD_DIR)' -Destination '$(COEFILES_BRAM_BUILD_DIR)' -Recurse"
	@echo "Build outputs copied to: $(COEFILES_DIR)"

# 创建 BootROM 构建输出目录。
$(BOOTROM_BUILD_DIR):
	@if not exist "$(BOOTROM_BUILD_DIR)" mkdir "$(BOOTROM_BUILD_DIR)"

# 创建 BRAM 构建输出目录。
$(BRAM_BUILD_DIR):
	@if not exist "$(BRAM_BUILD_DIR)" mkdir "$(BRAM_BUILD_DIR)"

# 编译并链接 BootROM，生成 ELF；不使用标准库和默认启动文件。
$(BOOTROM_ELF): $(BOOTROM_SRC) $(BOOTROM_LD) | $(BOOTROM_BUILD_DIR)
	@echo "Building BootROM ELF..."
	@$(CC) $(ARCH_FLAGS) -nostdlib -nostartfiles "-Wl,-T,$(BOOTROM_LD)" $< -o $@
	@$(SIZE) $@

# 编译并链接 BRAM 用户程序，生成裸机 ELF。
$(BRAM_ELF): $(BRAM_SRCS) $(BRAM_LD) | $(BRAM_BUILD_DIR)
	@echo "Building BRAM ELF..."
	@$(CC) $(ARCH_FLAGS) -mcmodel=medany -msmall-data-limit=0 -nostdlib -nostartfiles -ffreestanding -fno-builtin -Os "-Wl,-T,$(BRAM_LD)" $(BRAM_SRCS) -o $@
	@$(SIZE) $@

# 将 BootROM ELF 转为裸二进制，并填充到固定 4KB 大小。
$(BOOTROM_BIN): $(BOOTROM_ELF)
	@echo "Generating BootROM binary..."
	@$(OBJCOPY) -O binary --gap-fill 0x00 --pad-to $(BOOTROM_SIZE_BYTES) $< $@

# 将 BRAM ELF 转为裸二进制，按链接地址填充到 0x20000。
$(BRAM_BIN): $(BRAM_ELF)
	@echo "Generating BRAM binary..."
	@$(OBJCOPY) -O binary --gap-fill 0x00 --pad-to $(BRAM_PAD_TO_ADDR) $< $@

# 生成 BootROM 反汇编文件，用于人工查看和后续自动检查。
$(BOOTROM_DUMP): $(BOOTROM_ELF)
	@echo "Generating BootROM dump..."
	@powershell -NoProfile -ExecutionPolicy Bypass -Command "$$dump = & '$(OBJDUMP)' -d -S '$(BOOTROM_ELF)'; if ($$LASTEXITCODE -ne 0) { exit $$LASTEXITCODE }; [System.IO.File]::WriteAllLines('$(BOOTROM_DUMP)', $$dump, [System.Text.Encoding]::ASCII)"

# 生成 BRAM 反汇编文件，用于人工查看和后续自动检查。
$(BRAM_DUMP): $(BRAM_ELF)
	@echo "Generating BRAM dump..."
	@powershell -NoProfile -ExecutionPolicy Bypass -Command "$$dump = & '$(OBJDUMP)' -d -S '$(BRAM_ELF)'; if ($$LASTEXITCODE -ne 0) { exit $$LASTEXITCODE }; [System.IO.File]::WriteAllLines('$(BRAM_DUMP)', $$dump, [System.Text.Encoding]::ASCII)"

# 将 BootROM 二进制按 128-bit 小端数据字转换为 Vivado BRAM 初始化用的 COE 文件。
$(BOOTROM_COE): $(BOOTROM_BIN) $(MAKEFILE_PATH)
	@echo "Generating BootROM COE..."
	@powershell -NoProfile -ExecutionPolicy Bypass -Command "$$bytes = [System.IO.File]::ReadAllBytes('$(BOOTROM_BIN)'); if ($$bytes.Length -ne $(BOOTROM_SIZE_BYTES)) { throw 'BootROM binary size must be $(BOOTROM_SIZE_BYTES) bytes.' }; $$lines = New-Object System.Collections.Generic.List[string]; $$lines.Add('memory_initialization_radix=16;'); $$lines.Add('memory_initialization_vector='); for ($$i = 0; $$i -lt $$bytes.Length; $$i += $(INIT_WORD_BYTES)) { $$word = -join ($$bytes[($$i + $(INIT_WORD_BYTES) - 1)..$$i] | ForEach-Object { $$_.ToString('x2') }); if ($$i -eq $$bytes.Length - $(INIT_WORD_BYTES)) { $$lines.Add($$word + ';') } else { $$lines.Add($$word + ',') } }; [System.IO.File]::WriteAllLines('$(BOOTROM_COE)', $$lines, [System.Text.Encoding]::ASCII)"

# 将 BootROM 二进制按 128-bit 小端数据字同步为 Vivado BMG 仿真实际加载的 MIF 文件。
$(BOOTROM_MIF_TARGETS): $(BOOTROM_BIN) $(MAKEFILE_PATH)
	@echo "Generating BootROM MIF: $@"
	@powershell -NoProfile -ExecutionPolicy Bypass -Command "$$target = '$@'; $$dir = [System.IO.Path]::GetDirectoryName($$target); if ($$dir -and -not [System.IO.Directory]::Exists($$dir)) { [System.IO.Directory]::CreateDirectory($$dir) | Out-Null }; $$bytes = [System.IO.File]::ReadAllBytes('$(BOOTROM_BIN)'); if ($$bytes.Length -ne $(BOOTROM_SIZE_BYTES)) { throw 'BootROM binary size must be $(BOOTROM_SIZE_BYTES) bytes.' }; $$lines = New-Object System.Collections.Generic.List[string]; for ($$i = 0; $$i -lt $$bytes.Length; $$i += $(INIT_WORD_BYTES)) { $$word = -join ($$bytes[($$i + $(INIT_WORD_BYTES) - 1)..$$i] | ForEach-Object { [Convert]::ToString($$_, 2).PadLeft(8, '0') }); $$lines.Add($$word) }; [System.IO.File]::WriteAllLines($$target, $$lines, [System.Text.Encoding]::ASCII)"

# 将 BRAM 二进制按 128-bit 小端数据字转换为 Vivado BRAM 初始化用的 COE 文件。
$(BRAM_COE): $(BRAM_BIN) $(MAKEFILE_PATH)
	@echo "Generating BRAM COE..."
	@powershell -NoProfile -ExecutionPolicy Bypass -Command "$$bytes = [System.IO.File]::ReadAllBytes('$(BRAM_BIN)'); if ($$bytes.Length -ne $(BRAM_SIZE_BYTES)) { throw 'BRAM binary size must be $(BRAM_SIZE_BYTES) bytes.' }; $$lines = New-Object System.Collections.Generic.List[string]; $$lines.Add('memory_initialization_radix=16;'); $$lines.Add('memory_initialization_vector='); for ($$i = 0; $$i -lt $$bytes.Length; $$i += $(INIT_WORD_BYTES)) { $$word = -join ($$bytes[($$i + $(INIT_WORD_BYTES) - 1)..$$i] | ForEach-Object { $$_.ToString('x2') }); if ($$i -eq $$bytes.Length - $(INIT_WORD_BYTES)) { $$lines.Add($$word + ';') } else { $$lines.Add($$word + ',') } }; [System.IO.File]::WriteAllLines('$(BRAM_COE)', $$lines, [System.Text.Encoding]::ASCII)"

# 将 BRAM 二进制按 128-bit 小端数据字同步为 Vivado BMG 仿真实际加载的 MIF 文件。
$(BRAM_MIF_TARGETS): $(BRAM_BIN) $(MAKEFILE_PATH)
	@echo "Generating BRAM MIF: $@"
	@powershell -NoProfile -ExecutionPolicy Bypass -Command "$$target = '$@'; $$dir = [System.IO.Path]::GetDirectoryName($$target); if ($$dir -and -not [System.IO.Directory]::Exists($$dir)) { [System.IO.Directory]::CreateDirectory($$dir) | Out-Null }; $$bytes = [System.IO.File]::ReadAllBytes('$(BRAM_BIN)'); if ($$bytes.Length -ne $(BRAM_SIZE_BYTES)) { throw 'BRAM binary size must be $(BRAM_SIZE_BYTES) bytes.' }; $$lines = New-Object System.Collections.Generic.List[string]; for ($$i = 0; $$i -lt $$bytes.Length; $$i += $(INIT_WORD_BYTES)) { $$word = -join ($$bytes[($$i + $(INIT_WORD_BYTES) - 1)..$$i] | ForEach-Object { [Convert]::ToString($$_, 2).PadLeft(8, '0') }); $$lines.Add($$word) }; [System.IO.File]::WriteAllLines($$target, $$lines, [System.Text.Encoding]::ASCII)"

# 检查 BootROM 入口地址、trap 向量和跳转到 BRAM 的关键指令是否存在。
bootrom-check: $(BOOTROM_ELF) $(BOOTROM_DUMP)
	@powershell -NoProfile -ExecutionPolicy Bypass -Command "$$dump = Get-Content -Raw '$(BOOTROM_DUMP)'; if ($$dump -notmatch '0000000000000000 <_start>') { throw 'BootROM _start is not linked at 0x00000000.' }; if ($$dump -notmatch '<bootrom_trap>') { throw 'BootROM trap handler is missing.' }; if ($$dump -notmatch 'csrw\s+mtvec,t0') { throw 'BootROM does not initialize mtvec.' }; if ($$dump -notmatch 'lui\s+t0,0x10') { throw 'BootROM does not load BRAM base 0x00010000 into t0.' }; if ($$dump -notmatch 'fence\.i') { throw 'BootROM does not execute fence.i before BRAM jump.' }; if ($$dump -notmatch 'jr\s+t0|jr\s+0\\(t0\\)|jalr\s+zero,0\\(t0\\)') { throw 'BootROM does not jump through t0.' }; Write-Host 'BootROM check passed: _start at 0x00000000, mtvec initialized, and jump target 0x00010000 found.'"

# 检查 BRAM 入口地址、镜像大小和 main 符号是否符合预期。
bram-check: $(BRAM_ELF) $(BRAM_BIN) $(BRAM_DUMP)
	@powershell -NoProfile -ExecutionPolicy Bypass -Command "$$dump = Get-Content -Raw '$(BRAM_DUMP)'; if ($$dump -notmatch '0000000000010000 <_start>') { throw 'BRAM _start is not linked at 0x00010000.' }; if ((Get-Item '$(BRAM_BIN)').Length -ne $(BRAM_SIZE_BYTES)) { throw 'BRAM binary size must be $(BRAM_SIZE_BYTES) bytes.' }; if ($$dump -notmatch '<main>') { throw 'BRAM image does not contain main.' }; Write-Host 'BRAM check passed: _start at 0x00010000 and 64KB image generated.'"

# 删除 BootROM 和 BRAM 的构建输出目录。
clean:
	@if exist "$(BOOTROM_BUILD_DIR)" rmdir /S /Q "$(BOOTROM_BUILD_DIR)"
	@if exist "$(BRAM_BUILD_DIR)" rmdir /S /Q "$(BRAM_BUILD_DIR)"
	@if exist "$(JTAG_MAKEFILE)" $(MAKE) -f "$(JTAG_MAKEFILE)" clean
