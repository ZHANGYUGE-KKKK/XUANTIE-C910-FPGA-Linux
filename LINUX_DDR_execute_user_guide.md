# LINUX_DDR_execute 操作指引

## 1. 编译实验镜像

在工程根目录执行：

```powershell
make -f MAKEFILE\Makefile LINUX_DDR_execute
```

## 2. 更新 Vivado BRAM 初始化文件

使用生成的 BootROM/BRAM 初始化文件：

```text
MAKEFILE/LINUX_DDR_execute/BOOTROM/build/bootrom.coe
MAKEFILE/LINUX_DDR_execute/BRAM/build/bram.coe
```

或使用顶层 Makefile 同步后的统一输出：

```text
MAKEFILE/COEFILES/build_bootrom/bootrom.coe
MAKEFILE/COEFILES/build_ram/bram.coe
```

## 3. 烧写 FPGA

在 Vivado 中重新生成 bitstream，并烧写 FPGA。

## 4. 等待 BRAM Stub 停机

打开串口终端，复位 FPGA 后应看到：

```text
BRAM_STUB_READY
```

此时 C910 会停在 BRAM stub 的 `ebreak`。

## 5. 启动 DebugServer

启动 DebugServer，并确认已经识别到 C910。

## 6. 启动 GDB

```powershell
D:\Xilinx_FPGA\C910_SOC\MAKEFILE\Xuantie-900-gcc-elf-newlib-mingw-V3.2.0\bin\riscv64-unknown-elf-gdb.exe
```

## 7. 连接 DebugServer

在 GDB 中执行：

```gdb
target remote 198.18.0.1:1234
```

或按实际情况使用：

```gdb
target remote 192.168.5.11:1234
```

## 8. 加载 DDR Payload

```gdb
load D:/Xilinx_FPGA/C910_SOC/MAKEFILE/LINUX_DDR_execute/JTAG/build/ddr_exec_payload.elf
```

## 9. 恢复 PC

如果 `load` 后 PC 被改写，设置回 BRAM stub 的 `ebreak` 后一条指令：

```gdb
set $pc = 0x10076
```

如果重新编译过，以以下文件中的实际地址为准：

```text
MAKEFILE/LINUX_DDR_execute/BRAM/build/bram.dump
```

## 10. 继续运行

```gdb
continue
```

## 11. 验证结果

串口预期输出：

```text
BRAM_STUB_READY
BRAM_JUMP_DDR
DDR_EXEC_OK
```

看到 `DDR_EXEC_OK` 表示 DDR 取指执行验证通过。

