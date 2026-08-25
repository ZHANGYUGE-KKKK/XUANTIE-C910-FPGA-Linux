# LINUX_CLINT_TEST 实验

## 1. 目标

本实验用于把 Linux init 阶段卡住时发现的 timer tick 问题从 Linux/OpenSBI 环境中剥离出来，直接在 M-mode 裸机 DDR payload 中验证 CLINT `MTIMECMP0` 写读和 `MTIP` 产生是否正常。

预期链路：

```text
BootROM -> BRAM stub -> ebreak -> GDB load DDR CLINT payload -> BRAM stub 跳 DDR -> CLINT 测试串口输出
```

## 2. 固定地址

| 用途 | 地址 |
| --- | --- |
| BootROM 入口 | `0x00000000` |
| BRAM stub 入口 | `0x00010000` |
| DDR payload 入口 | `0x0200000000` |
| UART Lite 基地址 | `0x40000000` |
| CLINT `MTIMECMP0` | `0x0c004000` |
| CLINT `MTIMECMPH0` | `0x0c004004` |
| CLINT `MTIME` low/high | `0x0c00bff8` / `0x0c00bffc` |

## 3. 构建

在工程根目录执行：

```powershell
make -f MAKEFILE\Makefile LINUX_CLINT_TEST
```

生成文件：

```text
MAKEFILE/LINUX_CLINT_TEST/BOOTROM/build/bootrom.coe
MAKEFILE/LINUX_CLINT_TEST/BRAM/build/bram.coe
MAKEFILE/LINUX_CLINT_TEST/JTAG/build/ddr_exec_payload.elf
MAKEFILE/LINUX_CLINT_TEST/JTAG/build/ddr_exec_payload.bin
MAKEFILE/LINUX_CLINT_TEST/JTAG/build/ddr_exec_payload.dump
```

## 4. 上板验证流程

1. 用本实验生成的 BootROM/BRAM COE 重新生成并烧录 bitstream。
2. 打开串口，等待：

```text
BRAM_STUB_READY
```

3. C910 在 `ebreak` 停住后，连接 DebugServer/GDB。
4. 在 GDB 中加载 DDR CLINT payload：

```gdb
source D:/Xilinx_FPGA/C910_SOC/MAKEFILE/LINUX_CLINT_TEST/JTAG/load_clint_test.gdb
```

5. 如果 `load` 后 PC 被改写，按 `BRAM/build/bram.dump` 中的最新地址设置到 `ebreak` 后一条指令。
6. 执行：

```gdb
continue
```

## 5. 判断标准

正常情况下至少应看到固定写读值：

```text
BRAM_STUB_READY
BRAM_JUMP_DDR
CLINT_TEST_START
FIXED_WRITE_READ_START
MTIMECMP_LO=0x0000000011223344
MTIMECMP_HI=0x0000000055667788
```

然后继续看到 `mtime + delta` 写入读回：

```text
MTIME_DELTA_START
MTIME_LO=...
MTIME_HI=...
NEXT_LO_READBACK=...
NEXT_HI_READBACK=...
WAIT_MTIP_START
```

若随后看到：

```text
MTIP_OK mip=0x0000000000000080
CLINT_TEST_DONE
```

说明裸机 M-mode 下 `MTIMECMP0` 写读和 `MTIP` 产生都正常，问题应回到 OpenSBI 的访问路径、特权模式、地址属性或写入顺序。

若固定写读阶段看到：

```text
MTIMECMP_LO=0x0000000000000000
MTIMECMP_HI=0x0000000000000000
```

说明 M-mode 裸机直接写 `0x0c004000/0x0c004004` 也没有写进 CLINT，应优先查 RTL：

```text
paddr -> mreg_wen -> mtimecmp0_wen/mtimecmph0_wen -> mtimecmp0_reg/mtimecmph0_reg
```

若固定写读成功，但最后看到：

```text
MTIP_TIMEOUT mip=...
```

说明 `MTIMECMP0` 寄存器可写，但 compare 到 `clint_core0_mt_int` / CPU `mip.MTIP` 的链路有问题。

若看到：

```text
CLINT_TRAP
mcause=...
mepc=...
mtval=...
```

说明访问 CLINT MMIO 或 CSR 操作触发异常，需根据 `mcause/mepc/mtval` 判断是总线访问异常还是非法 CSR/权限问题。
