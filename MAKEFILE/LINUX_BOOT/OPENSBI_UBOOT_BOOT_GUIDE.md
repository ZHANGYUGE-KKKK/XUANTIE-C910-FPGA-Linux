# OpenSBI 到 U-Boot 启动操作指引

本文档记录从 FPGA 烧写 bitstream 后，通过 GDB 加载 OpenSBI、U-Boot 并手动设置 PC 启动的完整流程。

当前流程不依赖 BRAM 中的软件 `ebreak`，而是通过 GDB 直接设置 OpenSBI 入口参数和 PC。

## 1. 地址约定

| 镜像 | 地址 |
| --- | --- |
| OpenSBI | `0x0200000000` |
| U-Boot | `0x0200200000` |
| Linux Image | `0x0200600000` |
| initramfs | `0x0204000000` |
| 系统 DTB | `0x0210000000` |


## 4. 启动 GDB

在 PowerShell 中启动工程自带 GDB：

```powershell
D:\Xilinx_FPGA\C910_SOC\MAKEFILE\Xuantie-900-gcc-elf-newlib-mingw-V3.2.0\bin\riscv64-unknown-elf-gdb.exe
```

连接 DebugServer：

```gdb
target remote 198.18.0.1:1234
```

如果 CPU 仍在运行，可以暂停：

```gdb
interrupt
```

## 5. 推荐流程：U-Boot 使用 OpenSBI 传入的 DTB 并启动 Linux

适用于重新构建后的 U-Boot，即 U-Boot 不再依赖 `devicetree: separate` 的固定 DTB 位置，而是使用 OpenSBI 通过 `a1` 传入的系统 DTB。

在 GDB 中依次执行：

调试阶段，正常不用
cd D:/Xilinx_FPGA/C910_SOC/MAKEFILE/LINUX_BOOT/timer-debug-image
restore opensbi-c910-fpga-timer-debug-fw_jump.bin binary 0x0200000000

```gdb
cd D:/Xilinx_FPGA/C910_SOC/MAKEFILE/LINUX_BOOT/complete-image
restore opensbi-c910-fpga-fw_jump.bin binary 0x0200000000
restore u-boot-c910-soc-minimal.bin binary 0x0200200000
restore linux-c910-fpga-Image.bin binary 0x0200600000
restore rootfs-c910-lite.cpio.gz binary 0x0204000000
restore c910-soc-system.dtb binary 0x0210000000

set $a0 = 0
set $a1 = 0x0210000000
set $pc = 0x0200000000

x/4i $pc
x/16xb 0x0200600000
x/4wx 0x0210000000

continue
```

其中 Linux Image 必须使用 `restore ... binary ...`。如果漏掉 `binary`，GDB 可能把
Linux `Image` 头里的 PE/COFF 信息当成可执行文件解析，而不是把完整 raw Image
原样写入 `0x0200600000`，U-Boot 随后执行 `booti` 时会报：

```text
Bad Linux RISCV Image magic!
```

Linux Image 地址检查应看到开头为 `0x4d 0x5a`，并在偏移 `0x30` 附近包含
`RISCV`；DTB 地址检查应显示首字为 `0xedfe0dd0`。

如果只需要验证 OpenSBI 到 U-Boot，不启动 Linux，也可以只加载 OpenSBI、U-Boot
和 DTB：

```gdb
restore D:/Xilinx_FPGA/C910_SOC/MAKEFILE/LINUX_BOOT/complete-image/c910-soc-system.dtb binary 0x0210000000
load D:/Xilinx_FPGA/C910_SOC/MAKEFILE/LINUX_BOOT/complete-image/opensbi-c910-fpga-fw_jump.elf
load D:/Xilinx_FPGA/C910_SOC/MAKEFILE/LINUX_BOOT/complete-image/u-boot-c910-soc-minimal.elf
set $a0 = 0
set $a1 = 0x0210000000
set $pc = 0x0200000000
continue
```

UART 预期输出顺序：

```text
OpenSBI v...
U-Boot ...
=>
```
