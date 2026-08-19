# DDR_JTAG 实验复现流程

## 1. 本实验的关键流程

```text
BRAM 程序等待 DDR 初始化 -> ebreak 停住 C910 -> GDB load payload ELF 写 DDR
-> 设置 PC 到 ebreak 后 -> continue -> BRAM 从 DDR 读取 256 字节并原样 UART 输出
```

本目录只验证一件事：DebugServer/GDB 是否能通过 JTAG 将数据写入 DDR，并由 C910 从 DDR 读出。

## 2. 固定地址和数据范围

| 用途 | 地址/长度 |
| --- | --- |
| BRAM 程序入口 | `0x00010000` |
| DDR 写入/读取起始地址 | `0x0200000000` |
| DDR payload 长度 | `256` 字节 |
| UART Lite 基地址 | `0x40000000` |

BRAM 程序读取范围：

```text
[0x0200000000, 0x02000000FF]
```

JTAG payload 当前写入内容：

```text
JTAG_DDR_OK_1234\r\n
```

后续补 `0x00` 到 256 字节。

## 3. BRAM 程序行为

文件：

```text
BRAM/main.c
```

当前行为：

```text
1. 等待 DDR 初始化完成
2. 执行 ebreak，等待 DebugServer/GDB 接管
3. resume 后执行 fence
4. 从 0x0200000000 连续读取 256 字节
5. 将读到的数据逐字节写入 UART
6. 进入 wfi 死循环
```

关键代码：

```c
wait_for_ddr_ready_time();
__asm__ volatile ("ebreak");

__asm__ volatile ("fence rw, rw" ::: "memory");

for (i = 0U; i < DDR_JTAG_READ_BYTES; ++i) {
    uart_putc((char)ddr_data[i]);
}
```

`ebreak` 用来稳定制造调试停机点，避免人工抢 DDR 写入时机。

## 4. JTAG Payload ELF

目录：

```text
JTAG/
```

关键文件：

```text
JTAG/payload.S
JTAG/payload.ld
JTAG/Makefile
```

生成文件：

```text
JTAG/build/ddr_payload.elf
JTAG/build/ddr_payload.bin
JTAG/build/ddr_payload.dump
JTAG/build/ddr_payload.map
```

`ddr_payload.elf` 不是给 CPU 执行的程序，而是用于让 GDB/DebugServer 执行 `load` 时按 ELF 的
loadable segment 地址写 DDR。

必须满足：

```text
LOAD VirtAddr/PhysAddr = 0x0000000200000000
FileSiz/MemSiz         = 0x100
```

## 5. 构建

### 5.1 构建 BRAM 镜像

在工程根目录执行：

```powershell
make -f MAKEFILE\Makefile DDR_JTAG
```

重点产物：

```text
BRAM/build/bram.elf
BRAM/build/bram.bin
BRAM/build/bram.dump
BRAM/build/bram.coe
```

如果重新编译 BRAM，需要从 `BRAM/build/bram.dump` 重新确认 `ebreak` 地址和下一条指令地址。

当前一次构建中：

```text
ebreak 地址       = 0x10046
ebreak 后一条地址 = 0x10048
```

### 5.2 构建 JTAG payload

进入：

```powershell
cd D:\Xilinx_FPGA\C910_SOC\MAKEFILE\DDR_JTAG\JTAG
```

执行：

```powershell
make
```

检查 ELF load 地址：

```powershell
..\..\Xuantie-900-gcc-elf-newlib-mingw-V3.2.0\bin\riscv64-unknown-elf-readelf.exe -l build\ddr_payload.elf
```

应看到 `LOAD` 段地址为：

```text
0x0000000200000000
```

## 6. 上板操作

### 6.1 烧录 FPGA

烧录包含当前 `DDR_JTAG/BRAM` 程序的 bitstream。

注意：按板上复位会复位 DDR4 IP，DDR 内容不能保留。每次复位后都要重新写 payload。

### 6.2 连接 DebugServer

DebugServer 当前识别到：

```text
Debug Arch is CKHAD
CPU Type is XT-C9101FDT
HWBKPT number is 2
HWWP number is 2
```

GDB 连接命令示例：

```gdb
target remote 198.18.0.1:1234
```

或：

```gdb
target remote 192.168.5.11:1234
```

### 6.3 写 DDR 并继续运行

C910 应停在 BRAM 程序内的 `ebreak`。

加载 payload ELF：

```gdb
load D:/Xilinx_FPGA/C910_SOC/MAKEFILE/DDR_JTAG/JTAG/build/ddr_payload.elf
```

如果 `load` 后 PC 被改到 payload ELF 的入口，需要手动设置回 `ebreak` 后一条指令。

当前构建：

```gdb
set $pc = 0x10048
continue
```

若确认 PC 没有被改，也可以直接：

```gdb
continue
```

## 7. 预期结果

UART 输出开头应为：

```text
JTAG_DDR_OK_1234
```

后面可能跟随 `0x00` 字节，取决于串口工具如何显示 NUL。

看到该字符串即可说明：

```text
GDB/DebugServer 已通过 JTAG 将 payload 写入 DDR，
C910 已从 0x0200000000 读出该数据，
UART 输出链路正常。
```

## 8. 常见问题

### 8.1 复位后读不到 payload

板上复位会复位 DDR4 IP。复位后必须重新执行：

```gdb
load D:/Xilinx_FPGA/C910_SOC/MAKEFILE/DDR_JTAG/JTAG/build/ddr_payload.elf
```

### 8.2 load 后程序跑飞

`ddr_payload.elf` 只是数据载荷，不是执行程序。

重新设置 PC 到 BRAM 的 `ebreak` 后一条指令：

```gdb
set $pc = 0x10048
continue
```

地址以最新 `BRAM/build/bram.dump` 为准。

### 8.3 看不到串口输出

检查：

```text
1. FPGA 中是否烧录了包含 ebreak 版本 BRAM 的 bitstream
2. C910 是否已经停在 ebreak
3. 是否 load 了 JTAG/build/ddr_payload.elf
4. load 后 PC 是否回到 ebreak 后一条指令
5. UART 波特率和串口号是否正确
```
