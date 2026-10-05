# C910 FPGA Linux 启动步骤

## 1. 准备硬件

烧录 FPGA bitstream，启动 DebugServer，复位 CPU。打开串口，参数为 `115200 8N1`。

## 2. 生成加载文件并启动 GDB

在 PowerShell 中执行：

```powershell
cd D:\Xilinx_FPGA\C910_SOC_VCU118_DDR4
powershell -NoProfile -ExecutionPolicy Bypass -File .\Temp\prepare-gdb-load-images.ps1
.\MAKEFILE\Xuantie-900-gcc-elf-newlib-mingw-V3.2.0\bin\riscv64-unknown-elf-gdb.exe
```

镜像更新后，重新执行上述封装脚本。

## 3. 加载并启动

在 GDB 中连接 DebugServer；地址不同时替换为实际地址：

```gdb
target remote 198.18.0.1:1234
```

如果 CPU 仍在运行，先执行 `interrupt` 暂停，再执行：

```gdb
cd D:/Xilinx_FPGA/C910_SOC_VCU118_DDR4/Temp
set gnutarget auto
load opensbi-c910-fpga-fw_jump.bin.load.elf
load u-boot-c910-soc-minimal.bin.load.elf
load linux-c910-fpga-Image.bin.load.elf
load rootfs-c910-lite.cpio.gz.load.elf
load c910-soc-system-1gb.dtb.load.elf

set $a0 = 0
set $a1 = 0x0210000000
set $pc = 0x0200000000
continue
```

## 4. 登录 Linux

等待串口自动启动 Linux，出现 `riscv64-xuantie login:` 后输入 `root`。

如果停在 U-Boot 命令行，手动执行：

```text
booti 0x0200600000 - 0x0210000000
```
