# LINUX_AMO_TEST 实验

## 1. 目标

本实验用于把 Linux 中遇到的 `Store/AMO access fault` 从复杂内核环境中剥离出来，直接在 M-mode 裸机程序里验证 DDR 上的 AMO 指令是否可用。

预期链路：

```text
BootROM -> BRAM stub -> ebreak -> GDB load DDR AMO payload -> BRAM stub 跳 DDR -> AMO 测试串口输出
```

## 2. 固定地址

| 用途 | 地址 |
| --- | --- |
| BootROM 入口 | `0x00000000` |
| BRAM stub 入口 | `0x00010000` |
| DDR payload 入口 | `0x0200000000` |
| AMO 测试地址 | `0x0200100000` |
| UART Lite 基地址 | `0x40000000` |

## 3. 构建

在工程根目录执行：

```powershell
make -f MAKEFILE\Makefile LINUX_AMO_TEST
```

生成文件：

```text
MAKEFILE/LINUX_AMO_TEST/BOOTROM/build/bootrom.coe
MAKEFILE/LINUX_AMO_TEST/BRAM/build/bram.coe
MAKEFILE/LINUX_AMO_TEST/JTAG/build/ddr_exec_payload.elf
MAKEFILE/LINUX_AMO_TEST/JTAG/build/ddr_exec_payload.bin
MAKEFILE/LINUX_AMO_TEST/JTAG/build/ddr_exec_payload.dump
```

## 4. 上板验证流程

1. 用本实验生成的 BootROM/BRAM COE 重新生成并烧录 bitstream。
2. 打开串口，等待：

```text
BRAM_STUB_READY
```

3. C910 在 `ebreak` 停住后，连接 DebugServer/GDB。
4. 在 GDB 中加载 DDR AMO payload：

```gdb
source D:/Xilinx_FPGA/C910_SOC/MAKEFILE/LINUX_AMO_TEST/JTAG/load_amo_test.gdb
```

5. 如果 `load` 后 PC 被改写，按 `BRAM/build/bram.dump` 中的最新地址设置到 `ebreak` 后一条指令。
6. 执行：

```gdb
continue
```

## 5. 判断标准

正常路径应看到：

```text
BRAM_STUB_READY
BRAM_JUMP_DDR
AMO_TEST_START
SW_LW_OK
BEFORE_AMOSWAP
AMOSWAP_OLD=0000000012345678
AMOSWAP_MEM=0000000000000000
AMOADD_OLD=0000000000000005
AMOADD_MEM=000000000000000C
AMO_TEST_DONE
```

如果看到：

```text
AMO_TRAP
mcause=...
mepc=...
mtval=...
```

说明裸机 AMO 也触发异常。若普通 `SW_LW_OK` 已经通过，而异常发生在 `BEFORE_AMOSWAP` 之后，优先怀疑 DDR/AXI/互连/PMA 对 AMO 或原子访问语义的支持问题。
