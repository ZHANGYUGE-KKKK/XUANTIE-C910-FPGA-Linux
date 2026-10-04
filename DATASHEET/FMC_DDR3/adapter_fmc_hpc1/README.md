# VCU118 J2 FMC_HPC1 -> FMC DDR3 子板转接板连线资料

版本：2026-10-04-A。目标器件：xcvu9p-flga2104-2L-e。信号映射共 50 根 DDR3 + 2 根外部参考时钟。

## 1. 适用范围与必须先确认的事项

本方案是**信号重新排列的转接板**，不是 400 针直通板。母板为 VCU118 Rev2.0 的 **J2 FMC_HPC1**，不是 J22 FMCP_HSPC；子板为所提供 Efinix FMC DDR3 GPIO 原理图中的 **J4 ASP-134488-01**。文中“子板 FMC pin”均指 J4 的真实接插件针号。

已修改工程实际使用的 [VCU118.xdc](D:/Xilinx/PROJECT/C910_SOC_VCU118_FMC_DDR3_MIG/XUANTIE-C910-FPGA-Linux/VIVADO/C910_SOC/C910_SOC.srcs/constrs_1/new/VCU118.xdc)。本次没有修改正式工程 BD、MIG 参数或 C910 JTAG/UART 的原有针脚。机器可读完整表见 [pinmap.json](D:/Xilinx/PROJECT/C910_SOC_VCU118_FMC_DDR3_MIG/XUANTIE-C910-FPGA-Linux/DATASHEET/FMC_DDR3/adapter_fmc_hpc1/pinmap.json)，包含 MIG 端口名、完整网络名和 FPGA 引脚功能。

硬件与工程前提：

- DDR 使用 1.5 V 模式；VCU118 Bank 66/67 的真实 VCCO/VADJ 必须为 1.5 V。XDC 不会改变稳压器输出。
- 子板 DRAM VDD/VDDQ 为 1.5 V，VREF/VTT 为 0.75 V；需检查子板供电选择跳线并实测。
- XDC 使用 SSTL15_DCI（单端）、DIFF_SSTL15_DCI（CK/DQS）、SSTL15（reset_n），高速 DDR 信号 SLEW=FAST，Bank 66/67 INTERNAL_VREF=0.75。母板两 Bank 已有各自 240 ohm VRP 电阻，无需 DCI cascade。
- 新参考时钟输入为 J2 G6/G7，转接板需提供 250 MHz LVDS 差分时钟源（或同等合规外部源）。原板载 E12/D12 时钟不再用于此 wrapper。
- **正式工程当前 MIG 的输入周期仍是 13334 ps（约 75 MHz），必须另行改为 4000 ps（250 MHz）并重新生成 IP。** 当前 XDC 的时钟约束已按 250 MHz 设置，不能靠放宽 DRC 消除这个参数不匹配。
- VADJ 与其他 FMC I/O Bank 共享。原工程 C910 JTAG 在 J22 上且使用 LVCMOS18；VADJ 改成 1.5 V 后必须另行处理 JTAG 电平/约束兼容性，不能维持 1.8 V 外部驱动直接接入。这里没有修改 JTAG。
- **禁止把母板 J2 C35/C37 的 12 V 连到子板 J4 C35/C37（子板接地）。禁止 J2 D1 直连 J4 D1。**

## 2. DDR 地址、控制、时钟：Bank 66

下面每一行表示转接板上的独立网络：`母板 J2-针号 <-> 子板 J4-针号`。FPGA 球号仅用于核对 XDC，不是连接器针号。地址、控制、CK 均在同一个 Bank 66；reset_n 也安排在此 Bank。

| Wrapper 端口（前缀 C0_DDR3_0_） | 母板 J2 针号 | 子板 J4 针号 | FPGA 球号 | 母板网络（前缀 FMC_HPC1_） | 子板网络 | U26 球号 |
| --- | --- | --- | --- | --- | --- | --- |
| `addr[0]` | G9 | D9 | BD12 | LA03_P | GPIOR_N_31 | N3 |
| `addr[1]` | G10 | D8 | BE12 | LA03_N | GPIOR_P_31_PLLIN1 | P7 |
| `addr[2]` | H10 | G9 | BF12 | LA04_P | GPIOR_P_28 | P3 |
| `addr[3]` | H11 | G10 | BF11 | LA04_N | GPIOR_N_28 | N2 |
| `addr[4]` | H7 | H14 | BC11 | LA02_P | GPIOR_N_26_CLK9_N | P8 |
| `addr[5]` | H8 | H13 | BD11 | LA02_N | GPIOR_P_26_CLK9_P | P2 |
| `addr[6]` | C10 | D15 | BD13 | LA06_P | GPIOR_N_25_CLK10_N | R8 |
| `addr[7]` | C11 | D14 | BE13 | LA06_N | GPIOR_P_25_CLK10_P | R2 |
| `addr[8]` | D11 | H7 | BE14 | LA05_P | GPIOR_P_24_CLK11_P | T8 |
| `addr[9]` | D12 | H8 | BF14 | LA05_N | GPIOR_N_24_CLK11_N | R3 |
| `addr[10]` | G12 | H11 | BE15 | LA08_P | GPIOR_N_23_CLK12_N | L7 |
| `addr[11]` | G13 | H10 | BF15 | LA08_N | GPIOR_P_23_CLK12_P | R7 |
| `addr[12]` | G15 | C11 | BC14 | LA12_P | GPIOR_N_22_CLK13_N | N7 |
| `addr[13]` | G16 | C10 | BC13 | LA12_N | GPIOR_P_22_CLK13_P | T3 |
| `addr[14]` | H19 | G13 | BB16 | LA15_P | GPIOR_N_21_CLK14_N | T7 |
| `addr[15]` | H20 | G12 | BC16 | LA15_N | GPIOR_P_21_CLK14_P | M7 |
| `ba[0]` | H13 | C14 | BC15 | LA07_P | GPIOR_P_20_CLK15_P | M2 |
| `ba[1]` | H14 | C15 | BD15 | LA07_N | GPIOR_N_20_CLK15_N | N8 |
| `ba[2]` | H16 | G16 | BA16 | LA11_P | GPIOR_N_19 | M3 |
| `ras_n` | D14 | C18 | BA14 | LA09_P | GPIOR_P_18 | J3 |
| `cas_n` | H17 | C19 | BA15 | LA11_N | GPIOR_N_18 | K3 |
| `we_n` | D15 | G15 | BB14 | LA09_N | GPIOR_P_19 | L3 |
| `cs_n[0]` | C14 | G19 | BB13 | LA10_P | GPIOR_N_17 | L2 |
| `cke[0]` | C15 | G18 | BB12 | LA10_N | GPIOR_P_17 | K9 |
| `odt[0]` | G18 | G6 | AV9 | LA16_P | GPIOR_P_16_PLLIN1 | K1 |
| `reset_n` | G19 | G7 | AV8 | LA16_N | GPIOR_N_16 | T2 |
| `ck_p[0]` | H4 | D11 | BC9 | CLK0_M2C_P | GPIOR_P_27_CLK8_P | J7 |
| `ck_n[0]` | H5 | D12 | BC8 | CLK0_M2C_N | GPIOR_N_27_CLK8_N | K7 |

其中 CK 是 FPGA 输出的 DRAM 时钟，当前 MIG 配置为 800 MHz（1600 MT/s，tCK=1250 ps）。虽然母板网络原名为 CLK0_M2C，这对线在本设计中作为 DDR CK 输出使用；这是重定义 FPGA I/O 用途，不是参考时钟输入。

## 3. DDR 数据低字节：Bank 67，Byte T0

DQ[7:0]、DM[0]、DQS[0] 同属 Bank 67 T0。DQS 使用 N6/N7，DM 使用 N0；DQ 使用 N2/N3/N4/N5/N8/N9/N10/N11。

| Wrapper 端口（前缀 C0_DDR3_0_） | 母板 J2 针号 | 子板 J4 针号 | FPGA 球号 | 母板网络（前缀 FMC_HPC1_） | 子板网络 | U26 球号 |
| --- | --- | --- | --- | --- | --- | --- |
| `dq[0]` | H22 | G30 | AW12 | LA19_P | GPIOB_P_34 | E3 |
| `dq[1]` | H23 | G31 | AY12 | LA19_N | GPIOB_N_34 | F7 |
| `dq[2]` | G21 | H31 | AW11 | LA20_P | GPIOB_P_33_CDI31 | F2 |
| `dq[3]` | G22 | H32 | AY10 | LA20_N | GPIOB_N_33_CDI30 | F8 |
| `dq[4]` | G24 | G34 | AW13 | LA22_P | GPIOB_N_32_CDI29 | H3 |
| `dq[5]` | G25 | G33 | AY13 | LA22_N | GPIOB_P_32_CDI28 | H8 |
| `dq[6]` | H25 | H34 | AU11 | LA21_P | GPIOB_P_31_CDI27 | G2 |
| `dq[7]` | H26 | H35 | AV11 | LA21_N | GPIOB_N_31_CDI26 | H7 |
| `dm[0]` | G27 | H28 | AT12 | LA25_P | GPIOB_P_26_CDI16 | E7 |
| `dqs_p[0]` | H31 | D26 | AV10 | LA28_P | GPIOB_P_25_CDI15 | F3 |
| `dqs_n[0]` | H32 | D27 | AW10 | LA28_N | GPIOB_N_25_CDI14 | G3 |

## 4. DDR 数据高字节：Bank 67，Byte T3

DQ[15:8]、DM[1]、DQS[1] 同属 Bank 67 T3，规则与低字节相同。

| Wrapper 端口（前缀 C0_DDR3_0_） | 母板 J2 针号 | 子板 J4 针号 | FPGA 球号 | 母板网络（前缀 FMC_HPC1_） | 子板网络 | U26 球号 |
| --- | --- | --- | --- | --- | --- | --- |
| `dq[8]` | D26 | G36 | AK15 | LA26_P | GPIOB_P_30_CDI25 | D7 |
| `dq[9]` | D27 | G37 | AL15 | LA26_N | GPIOB_N_30_CDI24 | C3 |
| `dq[10]` | H34 | H38 | AK12 | LA30_P | GPIOB_N_29_CDI23 | C8 |
| `dq[11]` | H35 | H37 | AL12 | LA30_N | GPIOB_P_29_CDI22 | C2 |
| `dq[12]` | G33 | G22 | AM13 | LA31_P | GPIOB_N_28_CDI20 | A7 |
| `dq[13]` | G34 | G24 | AM12 | LA31_N | GPIOB_P_27_CDI19 | A2 |
| `dq[14]` | G36 | G25 | AK14 | LA33_P | GPIOB_N_27_CDI18 | B8 |
| `dq[15]` | G37 | H29 | AK13 | LA33_N | GPIOB_N_26_CDI17 | A3 |
| `dm[1]` | C26 | C23 | AL14 | LA27_P | GPIOB_N_23_CDI12 | D3 |
| `dqs_p[1]` | H37 | C26 | AJ13 | LA32_P | GPIOB_P_24_EXTFB | C7 |
| `dqs_n[1]` | H38 | C27 | AJ12 | LA32_N | GPIOB_N_24_CDI13 | B7 |

母板网络名或子板 GPIO 网络名中的 P/N 对普通单端 ADDR/DQ 没有差分极性含义。CK 和 DQS 必须按本表保持正负极性与字节对应，不要依据 GPIO 名重新交换数据位。

## 5. 独立参考时钟：转接板新增电路，不连子板 DDR CK

| Wrapper 端口 | 母板 J2 针号 | FPGA 球号 | 母板网络 | 对端连接 |
| --- | --- | --- | --- | --- |
| BADJ_CLK_clk_p[0] | G6 | AY9 | FMC_HPC1_LA00_CC_P | 250 MHz LVDS 时钟源正端 |
| BADJ_CLK_clk_n[0] | G7 | BA9 | FMC_HPC1_LA00_CC_N | 250 MHz LVDS 时钟源负端 |

G6/G7 位于 Bank 66 的 GC 差分输入、SLR1，与 DDR Bank 66/67 同一 SLR，并与本次 MIG 的 MMCM 位于同一时钟区域。原板载 E12/D12 位于 Bank 71、SLR2；实际 MIG 检查拒绝它作为本组 DDR 的直接系统参考输入。初步候选 G2/G3（Bank 67）在布局时出现参考输入 BUFG 与 MMCM 跨时钟区域错误，已弃用，不是最终方案。

XDC 使用 LVDS 输入，`DIFF_TERM_ADV=TERM_NONE`。Bank 66 供电 1.5 V 时不启用需要 1.8 V 的内部 LVDS 终端；转接板须提供外部 100 ohm 差分终端并保证输入摆幅、共模符合 VU9P LVDS 输入规格。终端布置应结合整条传输线，尽量靠近 FPGA 接收端，且避免重复终端。这个时钟在正式 SoC 中也供给原先使用 BADJ_CLK 的时钟向导。

注意两对时钟完全不同：

- 参考输入：新增时钟源 -> J2 G6/G7 -> FPGA，250 MHz。
- DRAM CK：FPGA -> J2 H4/H5 -> 子板 J4 D11/D12 -> U26，800 MHz。

不能把它们短接，也不能把子板 D11/D12 当作提供参考时钟的振荡器。母板 J2 G6/G7 只接新增时钟源，不能直连子板 J4 G6/G7（子板这两个接点为 ODT/reset_n，已在第 2 节从其他母板接点引入）。

## 6. 电源、地与不能直连的针脚

以下仅列确定需要的电源连接，不能据此把未列出的 400 针按同针号全部直通。

| 母板 J2 接点/电源 | 子板 J4 接点/电源 | 转接板处理 |
| --- | --- | --- |
| C39、D32、D36、D38、D40：3.3 V | C39、D32、D36、D38、D40：3V3 | 按供电电流、时序与去耦设计连接对应 3.3 V；不得反向灌电 |
| E39、F40、G39、H40：VADJ_1V8_FPGA | E39、F40、G39、H40：VADJ | 只在母板 VADJ 实际设为 1.5 V 后连接；网络名中的 1V8 不表示本方案需要 1.8 V |
| C35、C37：12 V | C35、C37：GND | **不得直连**；母板这两个 12 V 接点隔离/NC，子板这两个接点接转接板 GND |
| D1：VADJ_1V8_PGOOD | D1 经 R2 接 3V3_B | **不得直连**；母板 PGOOD 与子板内部供电网隔离，子板 3V3_B 的来源按子板跳线/供电电路核实 |
| 双方原理图确认的 GND 接点 | 双方原理图确认的 GND 接点 | 连接完整公共地平面；保留 CK/DQS/DQ 邻近回流路径 |

子板电源原理图含 U25 LTM4632，可产生 VDDQ/VTT/VREF；J199/J200/J201/J202 分别选择送到 DRAM 的 VDD/VDDQ/VREF/VTT 来源，R257 可调整 VDDQ。必须按实物跳线核查选中的来源，不能仅凭默认标注假定电压正确。J5/J222 等还影响 3V3_B/VADJ_B 来源。子板所需 5V_B 来自其 3.3 V 升压电路，不能用母板 12 V 直接替代。

采用子板本地 LTM4632 供 DRAM 电源时，可按原理图核对下面的选择（操作跳线前断电，最终以实测电压为准）：

| 子板跳线 | 连接选择 | 作用/测量目标 |
| --- | --- | --- |
| J5（JU94/JU95） | 5-6、7-8；不接 1-2/3-4 | 3V3 -> 3V3_B；这样隔离 J4 D1 后仍有本地 3.3 V 来源 |
| J199（JU86/JU87） | 1-2、3-4；不接 5-6/7-8 | VDDQ_DDR3 -> VDD_MEM_DDR3，1.5 V |
| J200（JU88/JU89） | 1-2、3-4；不接 5-6/7-8 | VDDQ_DDR3 -> VDDQ_MEM_DDR3，1.5 V |
| J201（JU90/JU91） | 1-2、3-4；不接 5-6/7-8 | VREF_DDR3 -> VREF_MEM_DDR3，0.75 V |
| J202（JU92/JU93） | 1-2、3-4；不接 5-6/7-8 | VTT_DDR3 -> VTT_MEM_DDR3，0.75 V |
| J220（JU67） | 1-2 | 5V_B -> RUN_VDDQ，启用本地电源 |

先把 R257 调至 VDDQ_DDR3=1.5 V 并确认 VTT/VREF=0.75 V。每个选择器右侧输出为公共网络，不能同时接不同来源（例如同时短接 J199 的 1-2 与 5-6，否则会把本地稳压器与 VADJ 并联）。J222 默认 1-2/3-4 选择本地 1.8 V 给 VADJ_B，VADJ_B 不等于 DRAM 的 VDD_MEM_DDR3；附加 GPIO/排针用途需另行检查。

未用 GPIO、HA/HB、MGT、I2C、FMC JTAG、PGOOD 等不按同号直通；若另有需求，应单独按两端原理图设计。尤其母板 FMC 管理 JTAG 不等于 C910 PL JTAG。

## 7. 画图、PCB 与上电核对

- 转接板靠母板的一端应与 VCU118 J2 的 ASP-134486-01 配合；靠子板的一端应与其 J4 ASP-134488-01 配合。具体连接器高度、公母、安装方向与 footprint 必须核实实物及 Samtec 图纸。
- 所有表格使用原理图的电气针号；从 PCB 顶视/底视或两板对接视图看到的左右翻转，不能改变电气接点名称。优先按 Pin1/机械定位键核对，不能手工“镜像针号”。
- 原理图建议用 DDR_A0..A15、DDR_BA0..BA2、DDR_DQ0..DQ15、DDR_DM0/1、DDR_DQS0/1_P/N、DDR_CK_P/N 等统一网络名，连接器旁另标母板和子板原始网络名。
- CK、DQS 按差分对走线，DQ/DM 与各自 DQS 按字节分组；地址/命令按 DDR3 拓扑规划。不能跨字节换 DQS/DM。
- 800 MHz / 1600 MT/s 的可用性还取决于 VCU118 既有 FMC 走线 + 两个连接器/转接板 + 子板走线的总传播延迟、阻抗、反射与串扰。子板已有串联/并联终端电阻网络，设计时一并计入。按 PG150 PCB 指南做完整链路预算/SI 检查，不能只把转接板自身等长，也不能由 Vivado DRC 通过推断实板能稳定校准。
- 第一版建议保留电源测点、参考时钟测点以及必要的可选终端位置；测点设计避免给 DDR 总线造成长支路。
- 核对 DRAM reset_n 在上电、FPGA 未配置期间保持低；PG150 建议 4.7 kohm 下拉。应结合子板已有电阻网络确认，XDC 不能代替未配置期间的板级复位电路。
- 上电前断电测通断：逐行核对 50 根信号、2 根参考时钟，确认 12 V 未接入子板/地、3.3 V 与 VADJ 无短路。
- 初次上电先测 VCCO66/67、DRAM VDD/VDDQ/VREF/VTT，再观察参考时钟、MIG `init_calib_complete`，最后做读写压力测试。本表不是功能测试通过证明。

## 8. Vivado 验证状态与复现

**引脚方案已完成实际 MIG 布局布线验证。** Vivado 2020.2，器件 xcvu9p-flga2104-2L-e，最终参考输入为 Bank 66 的 AY9/BA9（J2 G6/G7）。验证于 2026-10-04 01:27 完成，保存的结果如下：

| 检查 | 最终结果 | 报告 |
| --- | --- | --- |
| 最终 IO 分配 | 50 根 DDR3 + 2 根参考时钟与本表一致 | [io_post_route.rpt](validation/io_post_route.rpt) |
| 布线 | 22133 / 22133 个可布线网络完全布通，0 个 routing errors | [route_status.rpt](validation/route_status.rpt) |
| 布线后默认 DRC | 0 Error，0 Critical Warning；1 条 RTSTAT-10 Warning（MIG 内部无可布线负载网络） | [drc_post_route.rpt](validation/drc_post_route.rpt) |
| bitstream_checks DRC | 0 Error，0 Critical Warning；同一条 RTSTAT-10 Warning | [drc_bitstream.rpt](validation/drc_bitstream.rpt) |
| 已约束路径时序 | WNS=1.156 ns，WHS=0.010 ns，TNS/THS=0；报告显示所有用户指定时序约束满足 | [timing_post_route.rpt](validation/timing_post_route.rpt) |

这是**隔离的 250 MHz MIG 验证顶层**的结果，不是正式 C910 工程全部通过的结论；也未生成 bitstream 或上板测试。验证使用真实 MIG PHY/校准逻辑，没有通过改 DDR DRC 严重性或放宽 DDR 专用时钟布线规则绕过检查。详细范围、配置与文件校验值见 [validation/README.md](validation/README.md)。

同时确认：

- wrapper 的 50 根 DDR3 端口均有唯一 PACKAGE_PIN，全部来自 J2 的 Bank 66/67；两 Bank 均在 SLR1、同一 I/O 列。
- 低/高字节的 DQ/DQS/DM 分组与位置满足 DDR3 Pin Rules；所有地址/控制在 Bank 66。
- **正式工程 MIG 仍未修改**：75 MHz 参数与 250 MHz XDC 不匹配，原参数验证报告 AVAL-46：MMCM FVCO=4000 MHz 超出 800..1600 MHz。需要完成下面的参数同步后，再验证完整正式工程。

附带 [validate_pinout.tcl](D:/Xilinx/PROJECT/C910_SOC_VCU118_FMC_DDR3_MIG/XUANTIE-C910-FPGA-Linux/DATASHEET/FMC_DDR3/adapter_fmc_hpc1/validate_pinout.tcl) 和 [validate_pinout_top.v](D:/Xilinx/PROJECT/C910_SOC_VCU118_FMC_DDR3_MIG/XUANTIE-C910-FPGA-Linux/DATASHEET/FMC_DDR3/adapter_fmc_hpc1/validate_pinout_top.v)。默认读取当前工程 MIG OOC DCP；`isolated_250` 模式在输出目录创建相同关键内存/AXI配置、250 MHz 输入的临时 MIG，只验证本次 XDC 物理方案，不修改正式工程。

先可执行本目录 verify_pinmap.ps1 检查 JSON、wrapper、工程 XDC 与官方 VCU118 XDC 一致性。然后在终端中用独立 batch 实例执行：

```text
# 默认：验证当前工程实际 MIG；需要已成功生成 MIG OOC DCP。
# <output-directory> 为单独的输出目录，不要与正式工程生成目录重合。
vivado -mode batch -source validate_pinout.tcl -tclargs <output-directory>
# 隔离验证：只在输出目录生成 250 MHz 的临时 MIG。
vivado -mode batch -source validate_pinout.tcl -tclargs <output-directory> isolated_250
```

脚本执行 synth_design / opt_design / place_design / route_design、输出 IO/DRC/时序报告。验证顶层并非完整 C910 SoC，也不产生 bitstream，不代表全 SoC 时序或上板 DDR 功能已验证。

正式工程还需要的最小参数同步（本次未执行）：打开 BD 中 DDR3 单元的配置，将参考输入设为 250 MHz / 4000 ps，保持 System Clock=No_Buffer、Memory Clock Period=1250 ps、数据位宽 16、AXI 数据位宽 128、CL=11/CWL=8。使用自动 MMCM 参数计算，不继续保留旧 75 MHz 的 M=16/D=1/O=6。重新 Validate BD、保存并生成 DDR3 IP 输出产物，重跑该 MIG 的 OOC 综合，再重跑顶层综合/实现；不要用旧 checkpoint 验证新参数。

## 9. 核对依据

- [VCU118 Rev2.0 原理图](D:/Xilinx/PROJECT/C910_SOC_VCU118_FMC_DDR3_MIG/XUANTIE-C910-FPGA-Linux/DATASHEET/VCU118/HW-U1-VCU118_REV2_0_SCHEMATIC_7-14-2017.pdf)：sheet 12（Bank 66/67 与 VRP）、39/40/41（J2）、供电及原时钟页。
- [DDR3 子板原理图](D:/Xilinx/PROJECT/C910_SOC_VCU118_FMC_DDR3_MIG/XUANTIE-C910-FPGA-Linux/DATASHEET/FMC_DDR3/fmc-ddr-gpio-card-schematics-v1.0(1).pdf)：PDF 第 3 页电源、第 4 页 J4/U26 与供电。J4 符号部分蓝色内部文字有行错位，本表依据外侧真实电气针号及网络线核对。
- [VCU118 官方 XDC](D:/Xilinx/PROJECT/C910_SOC_VCU118_FMC_DDR3_MIG/XUANTIE-C910-FPGA-Linux/DATASHEET/VCU118/vcu118-schematic-xtp450_cluster/vcu118-xdc-rdf0400/vcu118_rev2.0_12082017.xdc)：母板网络、FPGA 球号、Bank 与引脚功能。
- [AMD PG150 DDR3 Pin Rules](https://docs.amd.com/r/en-US/pg150-ultrascale-memory-ip/DDR3-Pin-Rules)：数据字节、DQS/DM、地址控制、I/O列/SLR和系统时钟要求。
- [AMD UG571 SelectIO](https://docs.amd.com/api/khub/documents/kFbaUC5HGcXyGNauhgU6Gw/content)：Table 1-77 note 1 允许关闭内部差分终端的 LVDS 输入使用不同于输出所需的 VCCO，但仍须满足器件 VIN/VIDIFF/VICM 规格；这正是本方案 Bank 66 1.5 V + 外部终端的前提。

任何 PCB 投板前都需要再以实物板卡版本/颗粒丝印核对本表、连接器方向及电源跳线。
