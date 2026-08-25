# C910 FPGA Linux Boot Guide

本文档是 C910 SoC FPGA 工程的 Linux 启动快速指南，用于从 FPGA bitstream 烧录后，通过 DebugServer/GDB 将 OpenSBI、U-Boot、Linux Image、initramfs 和 DTB 加载到 DDR，并启动到 Linux shell。

## 1. 启动链路

```text
BootROM -> BRAM stub -> OpenSBI -> U-Boot -> Linux Kernel -> initramfs/rootfs -> shell
```

FPGA bitstream 中只固化 BootROM 和 BRAM stub。OpenSBI、U-Boot、Linux Image、DTB 和 initramfs 通过 GDB 写入 DDR。

## 2. 镜像和地址

完整镜像目录：

```text
MAKEFILE/LINUX_BOOT/complete-image
```

| 镜像 | 文件 | DDR 地址 |
| --- | --- | --- |
| OpenSBI | `opensbi-c910-fpga-fw_jump.bin` | `0x200000000` |
| U-Boot | `u-boot-c910-soc-minimal.bin` | `0x200200000` |
| Linux Image | `linux-c910-fpga-Image.bin` | `0x200600000` |
| initramfs | `rootfs-c910-lite.cpio.gz` | `0x204000000` |
| 系统 DTB | `c910-soc-system.dtb` | `0x210000000` |

`c910-soc-system.dtb` 已包含 initramfs 的 `linux,initrd-start/end`，U-Boot 启动 Linux 时不需要单独传 ramdisk 地址。

## 3. 准备硬件

1. 烧录包含 Linux boot BootROM/BRAM stub 的 FPGA bitstream。
2. 打开串口，参数使用 `115200 8N1`。
3. 等待 BRAM stub 输出并停在 `ebreak`：

```text
LINUX_BOOT_STUB_READY
```

## 4. 启动 GDB

在工程根目录启动工程自带 GDB：

```powershell
.\MAKEFILE\Xuantie-900-gcc-elf-newlib-mingw-V3.2.0\bin\riscv64-unknown-elf-gdb.exe
```

连接 DebugServer：

```gdb
target remote 198.18.0.1:1234
```

如果你的 DebugServer 使用其他地址，请替换成实际地址。

## 5. 加载并启动完整镜像

在 GDB 中执行：

```gdb
cd MAKEFILE/LINUX_BOOT/complete-image
source load-c910-complete.gdb
```

该脚本会执行核心加载动作：

```gdb
restore opensbi-c910-fpga-fw_jump.bin binary 0x200000000
restore u-boot-c910-soc-minimal.bin binary 0x200200000
restore linux-c910-fpga-Image.bin binary 0x200600000
restore rootfs-c910-lite.cpio.gz binary 0x204000000
restore c910-soc-system.dtb binary 0x210000000
set $a0 = 0
set $a1 = 0x210000000
set $pc = 0x200000000
continue
```

注意：Linux Image 必须使用 `restore ... binary ...` 加载。不要用 `load` 加载裸 Image，否则 U-Boot 可能报：

```text
Bad Linux RISCV Image magic!
```

## 6. U-Boot 启动 Linux

U-Boot 默认使用以下命令启动 Linux：

```text
booti 0x200600000 - 0x210000000
```

第二个参数保持 `-`，因为 initramfs 起止地址来自 DTB。第三个参数是系统 DTB 地址。

如果自动启动被打断，也可以在 U-Boot 命令行手动执行：

```text
setenv k 0x200600000
setenv f 0x210000000
booti $k - $f
```

部分串口工具发送长命令时可能把 `0x210000000` 显示或截断异常，使用 `setenv` 分段输入更稳。

## 7. 预期结果

正常启动时，串口会依次看到：

```text
OpenSBI ...
U-Boot ...
Starting kernel ...
Linux version ...
riscv64-xuantie login:
```

登录：

```text
root
```

成功后应看到 shell：

```text
root@riscv64-xuantie:~#
```

FPGA 频率较低时，initramfs 解压和用户态启动可能需要较长时间。只要串口日志仍在推进，就继续等待。

## 8. 常用检查命令

进入 Linux shell 后可先执行：

```sh
uname -a
cat /proc/cpuinfo
cat /proc/meminfo
cat /proc/cmdline
cat /proc/interrupts
sleep 5
cat /proc/interrupts
dmesg | tail -50
```

重点确认 timer interrupt 计数会增长，系统没有 panic、oops 或持续 fault。

## 9. 镜像更新注意

完整镜像目录中提供 `SHA256SUMS`，可在加载前检查文件完整性：

```powershell
cd MAKEFILE\LINUX_BOOT\complete-image
```

```sh
sha256sum -c SHA256SUMS
```

如果替换 `rootfs-c910-lite.cpio.gz`，需要同步更新 `c910-soc-system.dtb` 中的 `linux,initrd-start/end`，否则 Linux 可能读取错误的 initramfs 范围。
