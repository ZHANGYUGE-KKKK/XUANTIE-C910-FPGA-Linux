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
D:\Xilinx_FPGA\C910_SOC_VCU118_DDR4\MAKEFILE\Xuantie-900-gcc-elf-newlib-mingw-V3.2.0\bin\riscv64-unknown-elf-gdb.exe
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

先在 PowerShell 中将原 BIN/DTB 封装成供 GDB 加载的单节 ELF：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File D:\Xilinx_FPGA\C910_SOC_VCU118_DDR4\Temp\prepare-gdb-load-images.ps1
```

脚本只在项目 `Temp` 目录生成文件，不修改原镜像。它将完整原文件放入 ELF 的 `.data`
节并设置目标地址，再转回 binary 比较 SHA256，确认封装前后的字节完全一致。
镜像更新后需要重新执行脚本。

复位 CPU 并暂停后，在 GDB 中依次执行：

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

`load` 使用 GDB 自带的加载进度输出，显示形式取决于 GDB 和 DebugServer。
上述 ELF 的加载地址已记录在 `.data` 节中，因此不追加偏移参数。
使用封装后的 ELF 可以保留原 BIN 的节间填充字节，不直接替换为原构建 ELF，
也不需要使用 `set gnutarget binary`。

不能直接在 auto 模式下 `load linux-c910-fpga-Image.bin`，否则 GDB 可能把 Linux
`Image` 头里的 PE/COFF 信息当成可执行文件解析，而不是把完整 raw Image 原样写入
`0x0200600000`，U-Boot 随后执行 `booti` 时会报：

```text
Bad Linux RISCV Image magic!
```

上述封装已通过本地内容和节地址检查，启动流程尚未上板验证。
如启动异常，先复位 CPU 并暂停，再用原始 `restore` 流程复测，判断异常是否与加载方式有关：

```gdb
cd D:/Xilinx_FPGA/C910_SOC_VCU118_DDR4/MAKEFILE/LINUX_BOOT/complete-image-1gb_50M
set gnutarget auto
restore opensbi-c910-fpga-fw_jump.bin binary 0x0200000000
restore u-boot-c910-soc-minimal.bin binary 0x0200200000
restore linux-c910-fpga-Image.bin binary 0x0200600000
restore rootfs-c910-lite.cpio.gz binary 0x0204000000
restore c910-soc-system-1gb.dtb binary 0x0210000000
set $a0 = 0
set $a1 = 0x0210000000
set $pc = 0x0200000000
continue
```

`restore` 不显示连续传输进度。卡在 OpenSBI 的具体原因仍需结合串口输出定位，
不能仅凭加载命令没有报错判断镜像已经正确启动。
