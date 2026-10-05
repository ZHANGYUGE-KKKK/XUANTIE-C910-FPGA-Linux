# CoreMark-PRO 裸机 testcase

沿用 `LINUX_DDR_execute` 的 BOOTROM → BRAM → JTAG 加载 DDR 流程，使用本目录独立的启动文件。
移植 EEMBC 官方 CoreMark-PRO 的全部九个标准 workload，保留原算法、输入规模和校验函数。
不需要 Linux、磁盘、SD 卡或目标端文件系统。输入数据编译进 ELF，或由原算法按固定种子生成。

BRAM 只有 64 KiB，因此只放串口启动桩。九个 workload 的代码、输入数据和运行内存都在 DDR；
通过 JTAG **加载一次套件 ELF，程序自动依次运行九项，并分别打印结果**。

## 1. 编译

在 `XUANTIE-C910-FPGA-Linux` 目录执行：

```powershell
make -f MAKEFILE/Makefile CoreMark-PRO
```

如果当前机器 PATH 中的 `make.exe` 链接不能启动，可使用已安装的 Vivado 自带版本：

```powershell
D:/Xilinx/Vivado/2020.2/gnuwin/bin/make.exe -f MAKEFILE/Makefile CoreMark-PRO
```
这会生成 BOOTROM / BRAM 的 ELF、BIN、COE、反汇编，按现有顶层流程更新 `MAKEFILE/COEFILES`
和 Vivado MIF，并编译一个包含九项的 DDR 套件镜像。仅重新编译 DDR 套件时：

```powershell
make -f MAKEFILE/CoreMark-PRO/JTAG/Makefile
# 诊断时仍可只构建一项；完整套件使用默认 WORKLOAD=all：
make -f MAKEFILE/CoreMark-PRO/JTAG/Makefile WORKLOAD=core
```

DDR 构建也可以直接调用 PowerShell：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File MAKEFILE/CoreMark-PRO/build.ps1
```

默认参数：`CPU_HZ=100000000 ITERATIONS=1 RUNS=3 MIN_SECONDS=1`。
`ITERATIONS` 是自动校准的起始值；校准只增加完整 workload 的执行次数，不改变输入规模。
`CPU_HZ` 必须是所测 bitstream 的实际 CPU 时钟。本工程 CPU 时钟配置为 100 MHz；
这里直接读取 `mcycle`，不使用 Linux DTS 中的计时频率。

```powershell
make -f MAKEFILE/CoreMark-PRO/JTAG/Makefile CPU_HZ=100000000 RUNS=3 MIN_SECONDS=1
```

仅为快速连通检查可设置 `RUNS=1 MIN_SECONDS=0`；这时只打印分项结果和完成状态，不打印总分，
这种输出不能交给评分脚本作为正式比较数据。
参数和完整编译宏保存在构建输出中，ELF 校验值在 `JTAG/build/images.csv` 中。

## 2. 上板运行

1. 按已有 testcase 方法，将本次 `COEFILES/build_bootrom/bootrom.coe` 和
   `COEFILES/build_ram/bram.coe` 用于 BOOTROM、BRAM 初始化，生成并下载 bitstream。
2. 打开串口 **115200 / 8N1**，开启日志保存。复位 CPU，等待 `COREMARK_PRO_LOADER_READY`。
   启动桩沿用原案例的启动延迟，它不读取 MIG 的 calibration 状态；加载前确认 DDR 已校准。
3. 通过原来的 DebugServer/JTAG 连接 GDB，CPU 停在 BRAM 的 `ebreak` 后，执行生成的加载脚本：

```gdb
.\MAKEFILE\Xuantie-900-gcc-elf-newlib-mingw-V3.2.0\bin\riscv64-unknown-elf-gdb.exe

# 地址替换为你当前 DebugServer 的地址：
target remote 198.18.0.1:1234
source MAKEFILE/CoreMark-PRO/JTAG/build/load_suite.gdb
```

脚本会选择 `CoreMark-PRO.elf`、执行 `load`、设置 PC 为 `_start`，然后 `continue`。
之后不需要手动切换 ELF 或在九项之间复位。控制器初始化 cache 一次，再按下表顺序运行。
脚本中的 ELF 路径在构建时生成，移动工程目录后需重新构建。
不要从正在运行的 Linux 跳到本程序；它要求复位后的 M-mode 环境。

每项结束都会打印自己的结果和完成标记；看到
`COREMARK_PRO_SUITE_DONE workloads=9 passed=9 failed=0` 才表示九项全部通过，CPU 随后停在 WFI。
再次跑整套时，先复位 CPU 回到 BRAM，再执行同一个 `load_suite.gdb`。
重新加载前必须回到新复位的启动环境，避免覆盖仍启用 cache 的运行镜像。

九个 workload 分别是：

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

每个 workload 自动执行：官方 `-v1` 校验 → `-v0` 校准/预热 → 三次计时 → 再次 `-v1` 校验。
计时边界使用官方 MITH 的 `al_signal_start/al_signal_finished`，包含其正常的初始化、执行和释放过程。
新增结果行的串口输出在计时结束后进行。

```text
COREMARK_PRO_SUITE_BEGIN workloads=9
... cjpeg-rose7-preset 的校验、计时和结果 ...
COREMARK_PRO_BEGIN workload=core cpu_hz=100000000 hart=0 contexts=1
BUILD ...
CONFIG mhcr=... mxstatus=... mccr2=... mhint=... code=data=heap=stack=DDR
MEASURE runs=3 min_seconds=1 timer=mcycle units=cycles
VALIDATION_PASS workload=core
CALIBRATION_DONE iterations=...
RESULT,core,1,<iterations>,<cycles>,<instructions>,<seconds>,<iter/s>,<IPC>,PASS
RESULT,core,2,<iterations>,<cycles>,<instructions>,<seconds>,<iter/s>,<IPC>,PASS
RESULT,core,3,<iterations>,<cycles>,<instructions>,<seconds>,<iter/s>,<IPC>,PASS
POST_VALIDATION_PASS workload=core
SUMMARY,core,3,<median_iter/s>,PASS
COREMARK_PRO_DONE code=0x0000000000000000
... 其余七项的校验、计时和结果 ...
COREMARK_PRO_RESEARCH_SCORE ...
COREMARK_PRO_SUITE_DONE workloads=9 passed=9 failed=0
```

上面是日志格式示意，尖括号是字段说明。每次正式测量结束后立即输出一条 `RESULT`，
包含本次的周期数、指令数、耗时、吞吐量和 IPC；默认每项输出三条，不是平均值。
三次测量及后校验完成后，另外输出吞吐量中位值 `SUMMARY`，用于套件总分计算。
`RESULT` 的指令数来自 `minstret`；
IPC 是该计时区间的指令数/周期数，读取两个计数器之间有少量固定开销。
官方原始报告也保留，里面名为 `time(ns)` 的字段在这个移植中实际是 **mcycle ticks**，
准确的单位以新增 `RESULT` 行为准。`RESULT` 的 PASS 表示当前执行的 MITH 失败计数为零；
整项有效还要求前后两次官方校验通过和最后的 DONE。

普通校验或运行错误会将该项记为失败，继续下一项，并反映在最终 `failed` 计数中。
硬件异常会打印 `mcause/mepc/mtval` 并终止整套；内存不足通过 newlib/MITH 的错误路径报告。
程序不会将官方校验失败转换为成功结果；九项未全部有效完成时，不产生有效总分。

## 4. 比较 L2 容量与总分

每个 RTL 配置保存一次完整串口日志，例如 `results/L2_1M/suite.log`。
固定工具链、ELF、CPU 频率、L1、DDR 和 cache/prefetch 设置，改变待测 CPU/L2 RTL 配置；
先比较每项的三次测量吞吐量中位值，保留周期数和 IPC，观察哪些应用受益。
CPU 初始化启用 L1 I/D cache、write allocate 和分支预测（`MHCR=0x11ff`）。
保留 MCCR2/MHINT 的复位配置并打印原值；当前 RTL 的 L2 enable 固定为 1，
不会用一个通用常数覆盖 FPGA 的 L2 RAM latency。
DDR 在当前 sysmap 中是正常可缓存区域；BRAM 和 UART 属于设备区域。

套件在串口打印九项的研究用总分。也可以用同一份串口日志在主机重新检查、汇总：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File MAKEFILE/CoreMark-PRO/score.ps1 -Logs "MAKEFILE/CoreMark-PRO/results/L2_1M/suite.log"
```

脚本默认检查九项齐全、前后校验、DONE、三次有效测量、频率和构建配置一致，
用周期数重新计算吞吐量，再按照上游 `util/perl/cert_mark.pl` 的参考因子计算
`1000 × geometric_mean(median_iter/s / reference_iter/s)`。
输出 `COREMARK_PRO_RESEARCH_SCORE`；这是采用官方公式的研究用汇总值，不是 EEMBC 认证声明。
L2 容量无法从这些控制 CSR 自动识别，需要在日志目录或实验记录中标明对应的 RTL 配置。

## 5. 内存与文件

- BOOTROM：`0x0`，4 KiB 初始化镜像。
- BRAM：`0x10000`，64 KiB 初始化镜像，仅启动桩。
- DDR：`0x200000000` 起，完整套件预留 160 MiB。每项使用独立的 16 MiB 堆，
  控制器另有 1 MiB 堆，顺序调用时共享 256 KiB 栈。BSS 由启动代码清零，
  代码和初始化数据约 2.25 MB，直接由 GDB `load` 写入；堆和栈无需传输。
- UART Lite：`0x40000000`；无需 semihosting。
- `BOOTROM/`、`BRAM/`：独立启动桩源码；`port/`：本地裸机适配。
- `vendor/`：完整的固定版本上游；来源和许可证说明见 `UPSTREAM.md`。
- `JTAG/build/CoreMark-PRO.elf`、`.bin`、`.map`、`.dump`：完整套件镜像及检查文件。
- `JTAG/build/load_suite.gdb`：一次加载、自动运行九项的 GDB 脚本。
- `JTAG/build/modules/<workload>/`：完整套件中各项的中间构建文件。
- `JTAG/build/<workload>/`：指定 `WORKLOAD=<名称>` 时的独立诊断镜像及 `load.gdb`。

九项各自使用其原始浮点宏、MITH/AL 和 C 库实例，通过部分链接及私有符号命名空间合并到一个 ELF。
控制器按普通函数调用 ABI 顺序执行，各项的数据和堆互相独立；原始 workload 和 MITH 源码不变。

静态检查命令：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File MAKEFILE/CoreMark-PRO/build.ps1 -CheckOnly
```

构建会执行交叉编译和 DDR ELF 静态检查。
实际硬件上的官方校验、UART 输出及性能数值仍须按第 2 节上板确认。
上游 ZIP 的源码中有一个 ZIP 文件输入分支的旧类型警告；标准 `zip-test` 使用内存输入，
不进入该文件输入分支，未因此修改官方源码。
