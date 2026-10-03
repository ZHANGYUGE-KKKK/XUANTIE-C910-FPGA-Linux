# CoreMark-PRO 裸机 testcase

沿用 `LINUX_DDR_execute` 的 BOOTROM → BRAM → JTAG 加载 DDR 流程，使用本目录独立的启动文件。
移植 EEMBC 官方 CoreMark-PRO 的全部九个标准 workload，保留原算法、输入规模和校验函数。
不需要 Linux、磁盘、SD 卡或目标端文件系统。输入数据编译进 ELF，或由原算法按固定种子生成。

BRAM 只有 64 KiB，原始套件的代码、数据和动态内存装不下。因此 BRAM 只放串口启动桩；
每次通过 JTAG 加载一个 DDR ELF，测完复位再加载下一项。

## 1. 编译

在 `XUANTIE-C910-FPGA-Linux` 目录执行：

```powershell
make -f MAKEFILE/Makefile CoreMark-PRO
```

如果当前机器 PATH 中的 `make.exe` 链接不能启动，可使用已安装的 Vivado 自带版本：

```powershell
& D:/Xilinx/Vivado/2020.2/gnuwin/bin/make.exe -f MAKEFILE/Makefile CoreMark-PRO
```

这会生成 BOOTROM / BRAM 的 ELF、BIN、COE、反汇编，按现有顶层流程更新 `MAKEFILE/COEFILES`
和 Vivado MIF，并编译九个 DDR 镜像。仅重新编译 DDR workload 时：

```powershell
make -f MAKEFILE/CoreMark-PRO/JTAG/Makefile
# 也可以只构建一项：
make -f MAKEFILE/CoreMark-PRO/JTAG/Makefile WORKLOAD=core
```

DDR 构建也可以直接调用 PowerShell：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File MAKEFILE/CoreMark-PRO/build.ps1
```

默认参数：`CPU_HZ=150000000 ITERATIONS=1 RUNS=5 MIN_SECONDS=1`。
`ITERATIONS` 是自动校准的起始值；校准只增加完整 workload 的执行次数，不改变输入规模。
`CPU_HZ` 必须是所测 bitstream 的实际 CPU 时钟。当前 BD 的 `clk_wiz` 配置为 150 MHz；
这里直接读取 `mcycle`，不使用 Linux DTS 中的计时频率。

```powershell
make -f MAKEFILE/CoreMark-PRO/JTAG/Makefile WORKLOAD=core CPU_HZ=150000000 RUNS=5 MIN_SECONDS=1
```

仅为快速连通检查可设置 `RUNS=1 MIN_SECONDS=0`；这种输出不能交给默认评分脚本作为正式比较数据。
参数和完整编译宏保存在每项的 `build.json` 中，ELF 校验值在 `JTAG/build/images.csv` 中。

## 2. 上板运行

1. 按已有 testcase 方法，将本次 `COEFILES/build_bootrom/bootrom.coe` 和
   `COEFILES/build_ram/bram.coe` 用于 BOOTROM、BRAM 初始化，生成并下载 bitstream。
2. 打开串口 **115200 / 8N1**，开启日志保存。复位 CPU，等待 `COREMARK_PRO_LOADER_READY`。
   启动桩沿用原案例的启动延迟，它不读取 MIG 的 calibration 状态；加载前确认 DDR 已校准。
3. 通过原来的 DebugServer/JTAG 连接 GDB，CPU 停在 BRAM 的 `ebreak` 后，执行生成的加载脚本：

```gdb
# 地址替换为你当前 DebugServer 的地址：
target remote 198.18.0.1:1234
source MAKEFILE/CoreMark-PRO/JTAG/build/core/load.gdb
```

脚本会选择 ELF、执行 `load`、设置 PC 为该 ELF 的 `_start`，然后 `continue`。
脚本中的 ELF 路径在构建时生成，移动工程目录后需重新构建。
不要从正在运行的 Linux 跳到本程序；它要求复位后的 M-mode 环境。

看到 `COREMARK_PRO_DONE code=0x0000000000000000` 表示该项完成，CPU 随后停在 WFI。
下一项先复位并回到 BRAM，再加载相应的 `load.gdb`。不能直接覆盖仍启用 cache 的上一项镜像。

九个目录分别是：

| workload | 内容 |
| --- | --- |
| `cjpeg-rose7-preset` | JPEG 压缩 |
| `core` | CoreMark-PRO 中的 CoreMark 工作负载 |
| `linear_alg-mid-100x100-sp` | 单精度 LINPACK |
| `loops-all-mid-10k-sp` | 单精度 Livermore loops |
| `nnet_test` | 神经网络 |
| `parser-125k` | XML 解析 |
| `radix2-big-64k` | 双精度 FFT |
| `sha-test` | SHA-256 |
| `zip-test` | ZIP 压缩 |

## 3. 串口结果

每个 ELF 自动执行：官方 `-v1` 校验 → `-v0` 校准/预热 → 五次计时 → 再次 `-v1` 校验。
计时边界使用官方 MITH 的 `al_signal_start/al_signal_finished`，包含其正常的初始化、执行和释放过程。
新增结果行的串口输出在计时结束后进行。

```text
COREMARK_PRO_BEGIN workload=core cpu_hz=150000000 hart=0 contexts=1
BUILD ...
CONFIG mhcr=... mxstatus=... mccr2=... mhint=... code=data=heap=stack=DDR
MEASURE runs=5 min_seconds=1 timer=mcycle units=cycles
VALIDATION_PASS workload=core
CALIBRATION_DONE iterations=...
RESULT,core,1,<iterations>,<cycles>,<instructions>,<seconds>,<iter/s>,<IPC>,PASS
...
POST_VALIDATION_PASS workload=core
SUMMARY,core,5,<median_iter/s>,PASS
COREMARK_PRO_DONE code=0x0000000000000000
```

上述尖括号是字段说明，不是实际跑分结果。`RESULT` 的指令数来自 `minstret`；
IPC 是该计时区间的指令数/周期数，读取两个计数器之间有少量固定开销。
官方原始报告也保留，里面名为 `time(ns)` 的字段在这个移植中实际是 **mcycle ticks**，
准确的单位以新增 `RESULT` 行为准。`RESULT` 的 PASS 表示当前执行的 MITH 失败计数为零；
整项有效还要求前后两次官方校验通过和最后的 DONE。

陷入异常会打印 `mcause/mepc/mtval` 和 FAILED；内存不足通过 newlib/MITH 的错误路径报告。
程序不会将官方校验失败转换为成功结果。

## 4. 比较 L2 容量与总分

每个 RTL 配置单独保存九项串口日志，例如 `results/L2_1M/*.log`。
固定工具链、ELF、CPU 频率、L1、DDR 和 cache/prefetch 设置，改变待测 CPU/L2 RTL 配置；
先比较每项的五次中位吞吐量，保留周期数和 IPC，观察哪些应用受益。
CPU 初始化启用 L1 I/D cache、write allocate 和分支预测（`MHCR=0x11ff`）。
保留 MCCR2/MHINT 的复位配置并打印原值；当前 RTL 的 L2 enable 固定为 1，
不会用一个通用常数覆盖 FPGA 的 L2 RAM latency。
DDR 在当前 sysmap 中是正常可缓存区域；BRAM 和 UART 属于设备区域。

汇总同一个 RTL 配置的完整九项日志：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File MAKEFILE/CoreMark-PRO/score.ps1 -Logs "MAKEFILE/CoreMark-PRO/results/L2_1M/*.log"
```

脚本检查九项齐全、前后校验、DONE、五次有效测量、频率和构建配置一致，
用周期数重新计算吞吐量，再按照上游 `util/perl/cert_mark.pl` 的参考因子计算
`1000 × geometric_mean(median_iter/s / reference_iter/s)`。
输出 `COREMARK_PRO_RESEARCH_SCORE`；这是采用官方公式的研究用汇总值，不是 EEMBC 认证声明。
L2 容量无法从这些控制 CSR 自动识别，需要在日志目录或实验记录中标明对应的 RTL 配置。

## 5. 内存与文件

- BOOTROM：`0x0`，4 KiB 初始化镜像。
- BRAM：`0x10000`，64 KiB 初始化镜像，仅启动桩。
- DDR：`0x200000000` 起，预留 16 MiB；末尾 256 KiB 为栈，其余为镜像和堆，
  链接时要求至少保留 8 MiB 堆。BSS 由启动代码清零，数据直接由 GDB `load` 写入。
- UART Lite：`0x40000000`；无需 semihosting。
- `BOOTROM/`、`BRAM/`：独立启动桩源码；`port/`：本地裸机适配。
- `vendor/`：完整的固定版本上游；来源和许可证说明见 `UPSTREAM.md`。
- `JTAG/build/<workload>/`：ELF、BIN、MAP、DUMP、GDB 脚本和构建参数。

静态检查命令：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File MAKEFILE/CoreMark-PRO/build.ps1 -CheckOnly
```

本次已完成交叉编译、BOOTROM/BRAM 镜像检查和 DDR ELF 静态检查。
实际硬件上的官方校验、UART 输出及性能数值仍须按第 2 节上板确认。
上游 ZIP 的源码中有一个 ZIP 文件输入分支的旧类型警告；标准 `zip-test` 使用内存输入，
不进入该文件输入分支，未因此修改官方源码。
