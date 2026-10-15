# C910 SoC VCU118 FMC DDR3 验证工程

## 项目简介

本工程基于开源 RISC-V C910 核心，在 VCU118 上搭建 SoC，目标是完成 DDR 读写、C910 JTAG 调试及 OpenSBI / U-Boot / Linux 启动链路验证。

当前重点是通过 **VCU118 J2 FMC_HPC1 → 无源转接板 → FMC DDR3 子板 J4** 接入 x16 DDR3。由于直插线序无法满足当前 MIG 的同 SLR 引脚规划，需要重排信号；当前分支使用外接 DDR3，历史 AXVU13P / 板载 DDR4 方案不作为本分支的接线依据。

FPGA PL 主要包含：

1. 单核 C910 RTL 及其调试 JTAG 接口；该接口使用普通 PL I/O，与开发板配置 FPGA 的 JTAG 不同。
2. UART 控制器，连接母板 USB-UART。
3. DDR3 MIG，配置颗粒 MT41K512M16HA-125、x16、1600 MT/s（目标速率，尚待实测）。
4. Boot ROM、BRAM、AXI 总线及复位/时钟逻辑。

VCU118 复位按键松开为低、按下为高，与历史 AXVU13P 平台相反。

## 当前任务与进度

转接板的设计目标是**最简、尽量小，仅装两个 FMC 连接器**，只重排 50 根 DDR 信号并连接必要电源与公共地，不增加晶振、时钟芯片或其他功能电路。DDR 引脚集中在同一 I/O 列、同一 SLR1 的 Bank66/67；MIG 参考时钟使用母板已有 Si570，经 AW23/AW22 输入 FPGA，不经过转接板。

| 状态 | 任务 |
| --- | --- |
| 已完成 | C910 单核裁剪及最小系统 UART 裸机打印验证。 |
| 已完成（静态） | DDR3 引脚重排及全部 50 根 MIG 到子板 U26 功能引脚的端到端连线复审。 |
| 待确认 | 子板供电、跳线及 RESET# 上电状态；现有资料保留可选 R_RESET，下拉需求尚未确认，严格两连接器方案需由母板/子板已有设计保证可靠复位。 |
| 待完成 | 转接板制作验收、全链路信号完整性及当前时钟路径的综合/实现验证；旧方案报告不代表当前工程已通过。 |
| 待完成 | 上板观察 MIG 校准完成，进行 DDR 读写回环及压力测试，验证目标速率。 |
| 待完成 | 验证 C910 JTAG / debugserver、DDR 程序加载与断点调试。 |
| 待完成 | 适配并验证 OpenSBI、U-Boot、Linux Kernel 和设备树，输出 Linux 串口启动日志。 |

硬件前提：母板 VADJ=1.5 V；J8 选中 U18，且每次断电重启后将 Si570_0 设为 250 MHz。共享 VADJ 下的外部 C910 JTAG 电平兼容也需确认。详细条件见 [转接板说明](EDA/adapter_fmc_hpc1/README.md)，连线依据见 [逐针对应表](EDA/adapter_fmc_hpc1/connections.md) 和 [独立复审报告](EDA/adapter_fmc_hpc1/REVIEW_SCHEMATIC_CONNECTIVITY.md)。

## 目录结构

| 目录 | 说明 |
| --- | --- |
| `DATASHEET` | VCU118 / 历史 AXVU13P 开发板、FMC IO 与 FMC DDR3 子板资料。 |
| `EDA` | 转接板 EDA 工程包；`adapter_fmc_hpc1/` 保存映射、逐针接线表、参考图纸、静态检查脚本及复审记录。 |
| `VIVADO/C910_SOC` | 当前 SoC 的 Vivado 工程、约束、BD 和 RTL。 |
| `MAKEFILE` | 裸机及 Linux 链路相关构建、测试与镜像生成流程。 |
| `JTAG` | C910 调试 JTAG 的用户手册及 debugserver。 |

## 维护约束

- 保持根目录清晰、可读、独立。
- 不要将临时文件、生成文件或未分类资料直接放在根目录。临时文件使用完后，如无保留的必要，则需要清理
- 新增内容应优先归入已有功能目录；确需新增目录时，应保持命名清晰、职责单一。
- 各模块之间应保持低耦合，避免无必要的跨目录依赖。
