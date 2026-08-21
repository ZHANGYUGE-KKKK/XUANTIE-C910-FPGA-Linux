# LINUX_BOOT 子工程

## 1. 目标

本子工程用于完成 Linux 启动链路中的 OpenSBI 最小启动验证。

当前阶段验证：

```text
BootROM -> BRAM stub -> ebreak -> JTAG 写入 DTB/OpenSBI -> BRAM stub 跳 OpenSBI
```

## 2. OpenSBI 来源

OpenSBI 不从零编写，使用官方源码：

```text
third_party/opensbi
```

当前下载版本：

```text
337c23dd
```

本工程自己维护的内容是：

```text
1. BRAM stub
2. 地址规划
3. 最小 DTS
4. GDB 加载脚本
```

## 3. 构建

在工程根目录执行：

```powershell
make -f MAKEFILE\Makefile LINUX_BOOT
```

该命令会构建：

```text
BOOTROM/build/bootrom.coe
BRAM/build/bram.coe
MAKEFILE/COEFILES/build_bootrom/bootrom.coe
MAKEFILE/COEFILES/build_ram/bram.coe
```

默认构建不会编译 `JTAG` 目录，也不会编译 OpenSBI 或 DTB。

OpenSBI ELF 和 DTB 由外部流程生成后，放入：

```text
build-output/
```

## 4. 上板流程

1. 使用本子工程生成的 BootROM/BRAM COE 更新 Vivado BRAM 初始化文件。
2. 重新生成 bitstream 并烧写 FPGA。
3. 打开串口终端。
4. 程序输出 `LINUX_BOOT_STUB_READY` 后停在 `ebreak`。
5. 启动 DebugServer 并连接 GDB。
6. 执行：

```gdb
source D:/Xilinx_FPGA/C910_SOC/MAKEFILE/LINUX_BOOT/JTAG/load_opensbi.gdb
```

7. 如果 `load` 后 PC 被改写，按 `BRAM/build/bram.dump` 设置到 `ebreak` 后一条指令。
   当前 BRAM stub 直接编译检查结果为：

```text
ebreak 地址       = 0x10074
ebreak 后一条地址 = 0x10076
```

8. 执行：

```gdb
continue
```

## 5. 通过标准

串口预期先看到：

```text
LINUX_BOOT_STUB_READY
JUMP_OPENSBI
```

随后如果 OpenSBI 串口初始化成功，应看到 OpenSBI banner。

## 6. 当前风险

当前 DTS 只包含 CPU、memory 和 UART Lite。

timer/CLINT/PLIC 尚未确认，因此本阶段只以 OpenSBI banner 输出作为通过标准，不要求继续进入 U-Boot 或 Linux。
