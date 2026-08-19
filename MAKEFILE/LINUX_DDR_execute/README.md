# LINUX_DDR_execute 实验

## 1. 目标

本实验用于验证 C910 能否从 DDR 取指并执行代码。

预期链路：

```text
BootROM -> BRAM stub -> ebreak -> GDB load DDR payload -> BRAM stub 跳 DDR -> DDR payload UART 输出
```

## 2. 固定地址

| 用途 | 地址 |
| --- | --- |
| BootROM 入口 | `0x00000000` |
| BRAM stub 入口 | `0x00010000` |
| DDR payload 入口 | `0x0200000000` |
| UART Lite 基地址 | `0x40000000` |

## 3. 构建

在工程根目录执行：

```powershell
make -f MAKEFILE\Makefile LINUX_DDR_execute
```

该命令会统一构建：

```text
BOOTROM/build/bootrom.elf
BOOTROM/build/bootrom.coe
BRAM/build/bram.elf
BRAM/build/bram.coe
JTAG/build/ddr_exec_payload.elf
JTAG/build/ddr_exec_payload.bin
```

## 4. 上板验证流程

1. 烧录包含本实验 BootROM/BRAM 初始化内容的 bitstream。
2. 打开串口，等待 BRAM stub 输出：

```text
BRAM_STUB_READY
```

3. C910 在 `ebreak` 停住后，连接 DebugServer/GDB。
4. 在 GDB 中加载 DDR payload：

```gdb
load D:/Xilinx_FPGA/C910_SOC/MAKEFILE/LINUX_DDR_execute/JTAG/build/ddr_exec_payload.elf
```

5. 如果 `load` 后 PC 被改写，按 `BRAM/build/bram.dump` 中的最新地址设置到 `ebreak` 后一条指令。
   当前构建中：

```text
ebreak 地址       = 0x10074
ebreak 后一条地址 = 0x10076
```

6. 执行：

```gdb
continue
```

## 5. 通过标准

串口能依次看到：

```text
BRAM_STUB_READY
BRAM_JUMP_DDR
DDR_EXEC_OK
```

看到 `DDR_EXEC_OK` 表示 CPU 已经从 `0x0200000000` 取指并执行 DDR 中的代码。
