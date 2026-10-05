# FMC DDR3 转接板 C 版独立电气连线复审

审核日期：2026-10-04（Asia/Shanghai）。审核对象：2026-10-04-C；依据同目录 HANDOFF_SCHEMATIC_REVIEW.md。操作方式：只读核查现有设计与图纸，仅新增本报告。

## 1. 结论

**现有资料中的全部 50 根 MIG DDR 信号，沿当前 BD/HDL、wrapper、XDC、VCU118 FMC_HPC1、转接板映射、子板 J4/GPIO/电阻支路，均落到源图 U26 的同一位、正确 DDR 功能引脚上。没有发现需要修正的 DDR 位交换、CK/DQS 极性翻转、DM/DQS 字节互换、信号误接电源/地、重复使用接点或漏接。**

该结论来自原始图纸端点和中间电阻支路的重新追踪，不是仅凭现有两个检查脚本 PASS。第 4 节列出全部 50 位的具体证据。

存在一个非阻断的证据分类待确认项：子板原图 J4 **C22、C30、C31** 是无附着导线、无网络标签的悬空引线，但没有 NC 叉号。转接板把它们明确隔离是合理的，未影响 DDR 链路；不能把“原图未画连接”提升为“原图明确标注 NC”。详见第 6 节。

RESET_n 的 RN28 39 Ω 到 VTT 支路确实存在于原图；这不是 RESET_n 对地导线短路。转接板 R_RESET 为 4.7 kΩ 可选 DNP，与现有资料描述相符。资料无法证明 RN28、跳线和 R_RESET 在实物上的焊装状态，也无法证明实际复位电平。

没有审核 Bank/SLR/时钟区域、MIG 物理合法性、时钟方案、工作速率、SI、机械封装或软件系统。没有运行 Vivado、综合、实现、bitstream、硬件编程、validate_pinout.tcl、生成器或原生 EDA ERC。没有修改现有映射、图纸或已有未提交文件。

## 2. 原始证据与定位约定

下列路径相对 XUANTIE-C910-FPGA-Linux 仓库根目录；第 8 节记录本次实际文件 SHA256。

| 代号 | 原始证据 | 本次读取位置与作用 |
| --- | --- | --- |
| B | VIVADO/C910_SOC/C910_SOC.srcs/sources_1/bd/C910_SOC/C910_SOC.bd | interface_nets.ddr3_0_C0_DDR3：C0_DDR3_0 ↔ DDR3/C0_DDR3；接口宽度与型号 |
| H | VIVADO/C910_SOC/C910_SOC.gen/sources_1/bd/C910_SOC/synth/C910_SOC.v | 41–55 行端口；296–307 行 assign；376–390、428 行 MIG 实例端口 |
| W | VIVADO/C910_SOC/C910_SOC.gen/sources_1/bd/C910_SOC/hdl/C910_SOC_wrapper.v | 40–54 行方向/宽度；93–107 行 C910_SOC_i 同名整总线连接 |
| X | VIVADO/C910_SOC/C910_SOC.srcs/constrs_1/new/VCU118.xdc | 全文件活动 PACKAGE_PIN 设置，表中逐位列行号 |
| O | DATASHEET/VCU118/vcu118-schematic-xtp450_cluster/vcu118-xdc-rdf0400/vcu118_rev2.0_12082017.xdc | 当前球号对应官方 FMC_HPC1 原网络 |
| C | DATASHEET/VCU118/HW-U1-VCU118_REV2_0_SCHEMATIC_7-14-2017.pdf | PDF 39/40/41 页，母板 J2 外侧电气针号与引线原网络 |
| G | DATASHEET/VCU118/vcu118-schematic-xtp450_cluster/vcu118-schematic-source-rdf0398/Libs/GOLDEN_SYMBOLS/sym/asp_134486_01_gnd.1 | 159 个母板标准 GND 接点，辅助原图检查 |
| D | DATASHEET/FMC_DDR3/fmc-ddr-gpio-card-schematics-v1.0(1).pdf | PDF 4 页 J4、U26A/U26B、串并联电阻、J5；PDF 3 页 DDR 电源选择器 |
| I | VIVADO/C910_SOC/C910_SOC.srcs/sources_1/bd/C910_SOC/ip/C910_SOC_ddr3_0_0/C910_SOC_ddr3_0_0.xci | 272、278 行：DataWidth=16、MemoryPart=MT41K512M16HA-125 |

待审连接段使用 pinmap.json、connections.md、output/adapter_netlist.json、output/pdf/FMC_DDR3_passive_adapter.pdf 和 output/svg/sheet_01.svg…sheet_11.svg。它们是同源产物，不能彼此充当原始证据。

子板 PDF 4 页尺寸为 842×595 pt。表中的 `(x,y)` 使用页面左上角为原点，x 向右、y 向下；`U y` 是 U26 对应实际引线的 y 坐标。支路“1…4”指原图电阻阵列由上到下的可见独立支路，**不是未提供的实体电阻封装焊盘号**。子板 J4 分部：A/B=J4-1、C/D=J4-2、E/F=J4-3、G/H=J4-4、J/K=J4-5。

## 3. 独立追踪方法和 HDL 连接事实

先从子板 PDF 外侧黑色针号和实际棕色引线定位 J4 端点，追踪蓝色导线到 GPIO 标签；重新识别十组黑色地符号的四层递减横线，再沿实际连续导线追溯到接点，没有直接引用既有脚本的手工 GROUND_BUS_X 来判地。对导线交点，以线段端点/分支关系处理，未将仅视觉接近或无接点的交叉强行合并。

对 U26，逐个配对外侧球号、对应棕色引线、实际蓝色导线及内部功能文字的固定基线偏移。内部蓝字与外侧黑字不是同一文字行，不能按“最近一行”匹配。U26A 的 50 条有标签信号引线全部重建；RN7/8/9/10/11/25 的 22 个有效串联支路逐个检查左右导线、独立电阻曲线和 DDR3_* 标签，再与 U26 同名别名接合。最后才对照待审映射和生成物。

从 wrapper 的实际声明穷举 50 位：ADDR16、BA3、控制7、CK2、DQ16、DM2、DQS4。DQ、DQS 是 inout，其余为 output。

BD 的一个 DDR 接口网将 DDR3/C0_DDR3 直接接到 C0_DDR3_0，没有中间重排模块。现有生成 HDL 中 12 个输出总线/标量通过 ddr3_0_C0_DDR3_* 网直接赋值，DQ/DQS 三个双向总线在 MIG 实例直接连外部总线；wrapper 又整总线同名连接。未发现片选位数、位序、切片或极性与 BD 矛盾。

| MIG 总线/标量 | 现有生成 HDL 的连接 | 外部总线范围/方向 |
| --- | --- | --- |
| c0_ddr3_addr | ddr3_0_C0_DDR3_ADDR | C0_DDR3_0_addr [15:0]，output |
| c0_ddr3_ba | ddr3_0_C0_DDR3_BA | C0_DDR3_0_ba [2:0]，output |
| c0_ddr3_ras_n | ddr3_0_C0_DDR3_RAS_N | C0_DDR3_0_ras_n 标量，output |
| c0_ddr3_cas_n | ddr3_0_C0_DDR3_CAS_N | C0_DDR3_0_cas_n 标量，output |
| c0_ddr3_we_n | ddr3_0_C0_DDR3_WE_N | C0_DDR3_0_we_n 标量，output |
| c0_ddr3_cs_n | ddr3_0_C0_DDR3_CS_N | C0_DDR3_0_cs_n [0:0]，output |
| c0_ddr3_cke | ddr3_0_C0_DDR3_CKE | C0_DDR3_0_cke [0:0]，output |
| c0_ddr3_odt | ddr3_0_C0_DDR3_ODT | C0_DDR3_0_odt [0:0]，output |
| c0_ddr3_reset_n | ddr3_0_C0_DDR3_RESET_N | C0_DDR3_0_reset_n 标量，output |
| c0_ddr3_ck_p | ddr3_0_C0_DDR3_CK_P | C0_DDR3_0_ck_p [0:0]，output |
| c0_ddr3_ck_n | ddr3_0_C0_DDR3_CK_N | C0_DDR3_0_ck_n [0:0]，output |
| c0_ddr3_dq | C0_DDR3_0_dq[15:0] | C0_DDR3_0_dq [15:0]，inout |
| c0_ddr3_dm | ddr3_0_C0_DDR3_DM | C0_DDR3_0_dm [1:0]，output |
| c0_ddr3_dqs_p | C0_DDR3_0_dqs_p[1:0] | C0_DDR3_0_dqs_p [1:0]，inout |
| c0_ddr3_dqs_n | C0_DDR3_0_dqs_n[1:0] | C0_DDR3_0_dqs_n [1:0]，inout |

## 4. 全部 50 位端到端证据表

每行的 wrapper 位均已由 B/H/W 校验为同位直连；母板球号由 X/O/C 三份原始证据交叉确认。J1 配母板 J2，转接板 J2 配子板 J4，均按电气同号配对；转接板 J1→J2 按实际网络标签重排。表中“直连”只指该 GPIO 到 U26 之间没有串联电阻，不代表不存在 VTT 终端支路。

| MIG 位 | wrapper 位 | FPGA 球号 | 母板原网 / 原图 J2 | 转接板 J1 → 网名 → J2 | 子板 J4 / 原 GPIO | 串联电阻 / DDR3 别名 | U26 球号 / 实际功能 | 原图定位 | 结论 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| c0_ddr3_addr[0] | C0_DDR3_0_addr[0] | BD12 | FMC_HPC1_LA03_P / G9 | G9 → DDR_A0 → D9 | D9 / GPIOR_N_31 | 直连同名 GPIO | N3 / A0 | X:36；C p40 J2.G9；D p4 J4.D9(219.72,66.84)，U y=282.00 | 通过 |
| c0_ddr3_addr[1] | C0_DDR3_0_addr[1] | BE12 | FMC_HPC1_LA03_N / G10 | G10 → DDR_A1 → D8 | D8 / GPIOR_P_31_PLLIN1 | 直连同名 GPIO | P7 / A1 | X:38；C p40 J2.G10；D p4 J4.D8(219.72,63.24)，U y=285.60 | 通过 |
| c0_ddr3_addr[2] | C0_DDR3_0_addr[2] | BF12 | FMC_HPC1_LA04_P / H10 | H10 → DDR_A2 → G9 | G9 / GPIOR_P_28 | 直连同名 GPIO | P3 / A2 | X:40；C p41 J2.H10；D p4 J4.G9(473.76,63.24)，U y=289.08 | 通过 |
| c0_ddr3_addr[3] | C0_DDR3_0_addr[3] | BF11 | FMC_HPC1_LA04_N / H11 | H11 → DDR_A3 → G10 | G10 / GPIOR_N_28 | 直连同名 GPIO | N2 / A3 | X:42；C p41 J2.H11；D p4 J4.G10(473.76,66.84)，U y=292.56 | 通过 |
| c0_ddr3_addr[4] | C0_DDR3_0_addr[4] | BC11 | FMC_HPC1_LA02_P / H7 | H7 → DDR_A4 → H14 | H14 / GPIOR_N_26_CLK9_N | 直连同名 GPIO | P8 / A4 | X:44；C p41 J2.H7；D p4 J4.H14(509.04,80.88)，U y=296.16 | 通过 |
| c0_ddr3_addr[5] | C0_DDR3_0_addr[5] | BD11 | FMC_HPC1_LA02_N / H8 | H8 → DDR_A5 → H13 | H13 / GPIOR_P_26_CLK9_P | 直连同名 GPIO | P2 / A5 | X:46；C p41 J2.H8；D p4 J4.H13(509.04,77.40)，U y=299.64 | 通过 |
| c0_ddr3_addr[6] | C0_DDR3_0_addr[6] | BD13 | FMC_HPC1_LA06_P / C10 | C10 → DDR_A6 → D15 | D15 / GPIOR_N_25_CLK10_N | 直连同名 GPIO | R8 / A6 | X:48；C p39 J2.C10；D p4 J4.D15(219.72,87.96)，U y=303.24 | 通过 |
| c0_ddr3_addr[7] | C0_DDR3_0_addr[7] | BE13 | FMC_HPC1_LA06_N / C11 | C11 → DDR_A7 → D14 | D14 / GPIOR_P_25_CLK10_P | 直连同名 GPIO | R2 / A7 | X:50；C p39 J2.C11；D p4 J4.D14(219.72,84.48)，U y=306.72 | 通过 |
| c0_ddr3_addr[8] | C0_DDR3_0_addr[8] | BE14 | FMC_HPC1_LA05_P / D11 | D11 → DDR_A8 → H7 | H7 / GPIOR_P_24_CLK11_P | 直连同名 GPIO | T8 / A8 | X:52；C p39 J2.D11；D p4 J4.H7(509.04,56.28)，U y=310.20 | 通过 |
| c0_ddr3_addr[9] | C0_DDR3_0_addr[9] | BF14 | FMC_HPC1_LA05_N / D12 | D12 → DDR_A9 → H8 | H8 / GPIOR_N_24_CLK11_N | 直连同名 GPIO | R3 / A9 | X:54；C p39 J2.D12；D p4 J4.H8(509.04,59.76)，U y=313.80 | 通过 |
| c0_ddr3_addr[10] | C0_DDR3_0_addr[10] | BE15 | FMC_HPC1_LA08_P / G12 | G12 → DDR_A10 → H11 | H11 / GPIOR_N_23_CLK12_N | 直连同名 GPIO | L7 / A10/AP | X:56；C p40 J2.G12；D p4 J4.H11(509.04,70.32)，U y=317.28 | 通过 |
| c0_ddr3_addr[11] | C0_DDR3_0_addr[11] | BF15 | FMC_HPC1_LA08_N / G13 | G13 → DDR_A11 → H10 | H10 / GPIOR_P_23_CLK12_P | 直连同名 GPIO | R7 / A11 | X:58；C p40 J2.G13；D p4 J4.H10(509.04,66.84)，U y=320.88 | 通过 |
| c0_ddr3_addr[12] | C0_DDR3_0_addr[12] | BC14 | FMC_HPC1_LA12_P / G15 | G15 → DDR_A12 → C11 | C11 / GPIOR_N_22_CLK13_N | 直连同名 GPIO | N7 / A12/BC# | X:60；C p40 J2.G15；D p4 J4.C11(184.44,73.92)，U y=324.36 | 通过 |
| c0_ddr3_addr[13] | C0_DDR3_0_addr[13] | BC13 | FMC_HPC1_LA12_N / G16 | G16 → DDR_A13 → C10 | C10 / GPIOR_P_22_CLK13_P | 直连同名 GPIO | T3 / A13 | X:62；C p40 J2.G16；D p4 J4.C10(184.44,70.32)，U y=327.84 | 通过 |
| c0_ddr3_addr[14] | C0_DDR3_0_addr[14] | BB16 | FMC_HPC1_LA15_P / H19 | H19 → DDR_A14 → G13 | G13 / GPIOR_N_21_CLK14_N | 直连同名 GPIO | T7 / A14 | X:64；C p41 J2.H19；D p4 J4.G13(473.76,77.40)，U y=331.44 | 通过 |
| c0_ddr3_addr[15] | C0_DDR3_0_addr[15] | BC16 | FMC_HPC1_LA15_N / H20 | H20 → DDR_A15 → G12 | G12 / GPIOR_P_21_CLK14_P | 直连同名 GPIO | M7 / A15 | X:66；C p41 J2.H20；D p4 J4.G12(473.76,73.92)，U y=334.92 | 通过 |
| c0_ddr3_ba[0] | C0_DDR3_0_ba[0] | BC15 | FMC_HPC1_LA07_P / H13 | H13 → DDR_BA0 → C14 | C14 / GPIOR_P_20_CLK15_P | 直连同名 GPIO | M2 / BA0 | X:68；C p41 J2.H13；D p4 J4.C14(184.44,84.48)，U y=267.96 | 通过 |
| c0_ddr3_ba[1] | C0_DDR3_0_ba[1] | BD15 | FMC_HPC1_LA07_N / H14 | H14 → DDR_BA1 → C15 | C15 / GPIOR_N_20_CLK15_N | 直连同名 GPIO | N8 / BA1 | X:70；C p41 J2.H14；D p4 J4.C15(184.44,87.96)，U y=271.44 | 通过 |
| c0_ddr3_ba[2] | C0_DDR3_0_ba[2] | BA16 | FMC_HPC1_LA11_P / H16 | H16 → DDR_BA2 → G16 | G16 / GPIOR_N_19 | 直连同名 GPIO | M3 / BA2 | X:72；C p41 J2.H16；D p4 J4.G16(473.76,87.96)，U y=274.92 | 通过 |
| c0_ddr3_ras_n | C0_DDR3_0_ras_n | BA14 | FMC_HPC1_LA09_P / D14 | D14 → DDR_RAS_N → C18 | C18 / GPIOR_P_18 | 直连同名 GPIO | J3 / RAS# | X:74；C p39 J2.D14；D p4 J4.C18(184.44,98.52)，U y=246.72 | 通过 |
| c0_ddr3_cas_n | C0_DDR3_0_cas_n | BA15 | FMC_HPC1_LA11_N / H17 | H17 → DDR_CAS_N → C19 | C19 / GPIOR_N_18 | 直连同名 GPIO | K3 / CAS# | X:76；C p41 J2.H17；D p4 J4.C19(184.44,102.12)，U y=243.24 | 通过 |
| c0_ddr3_we_n | C0_DDR3_0_we_n | BB14 | FMC_HPC1_LA09_N / D15 | D15 → DDR_WE_N → G15 | G15 / GPIOR_P_19 | 直连同名 GPIO | L3 / WE# | X:78；C p39 J2.D15；D p4 J4.G15(473.76,84.48)，U y=253.80 | 通过 |
| c0_ddr3_cs_n[0] | C0_DDR3_0_cs_n[0] | BB13 | FMC_HPC1_LA10_P / C14 | C14 → DDR_CS_N → G19 | G19 / GPIOR_N_17 | 直连同名 GPIO | L2 / CS# | X:80；C p39 J2.C14；D p4 J4.G19(473.76,98.52)，U y=222.00 | 通过 |
| c0_ddr3_cke[0] | C0_DDR3_0_cke[0] | BB12 | FMC_HPC1_LA10_N / C15 | C15 → DDR_CKE → G18 | G18 / GPIOR_P_17 | 直连同名 GPIO | K9 / CKE | X:82；C p39 J2.C15；D p4 J4.G18(473.76,95.04)，U y=229.08 | 通过 |
| c0_ddr3_odt[0] | C0_DDR3_0_odt[0] | AV9 | FMC_HPC1_LA16_P / G18 | G18 → DDR_ODT → G6 | G6 / GPIOR_P_16_PLLIN1 | 直连同名 GPIO | K1 / ODT | X:84；C p40 J2.G18；D p4 J4.G6(473.76,52.68)，U y=260.88 | 通过 |
| c0_ddr3_reset_n | C0_DDR3_0_reset_n | AV8 | FMC_HPC1_LA16_N / G19 | G19 → DDR_RESET_N → G7 | G7 / GPIOR_N_16 | 直连同名 GPIO | T2 / RESET# | X:86；C p40 J2.G19；D p4 J4.G7(473.76,56.28)，U y=236.16 | 通过（RN28 支路见§5） |
| c0_ddr3_ck_p[0] | C0_DDR3_0_ck_p[0] | BC9 | FMC_HPC1_CLK0_M2C_P / H4 | H4 → DDR_CK_P → D11 | D11 / GPIOR_P_27_CLK8_P | 直连同名 GPIO | J7 / CK | X:89；C p41 J2.H4；D p4 J4.D11(219.72,73.92)，U y=211.44 | 通过 |
| c0_ddr3_ck_n[0] | C0_DDR3_0_ck_n[0] | BC8 | FMC_HPC1_CLK0_M2C_N / H5 | H5 → DDR_CK_N → D12 | D12 / GPIOR_N_27_CLK8_N | 直连同名 GPIO | K7 / CK# | X:92；C p41 J2.H5；D p4 J4.D12(219.72,77.40)，U y=215.04 | 通过 |
| c0_ddr3_dq[0] | C0_DDR3_0_dq[0] | AW12 | FMC_HPC1_LA19_P / H22 | H22 → DDR_DQ0 → G30 | G30 / GPIOB_P_34 | RN7 支路1，20 Ω → DDR3_D0 | E3 / DQ0 | X:94；C p41 J2.H22；D p4 J4.G30(473.76,137.40)，U y=211.44，RN7 y=394.92 | 通过 |
| c0_ddr3_dq[1] | C0_DDR3_0_dq[1] | AY12 | FMC_HPC1_LA19_N / H23 | H23 → DDR_DQ1 → G31 | G31 / GPIOB_N_34 | RN7 支路2，20 Ω → DDR3_D1 | F7 / DQ1 | X:96；C p41 J2.H23；D p4 J4.G31(473.76,140.88)，U y=215.04，RN7 y=398.40 | 通过 |
| c0_ddr3_dq[2] | C0_DDR3_0_dq[2] | AW11 | FMC_HPC1_LA20_P / G21 | G21 → DDR_DQ2 → H31 | H31 / GPIOB_P_33_CDI31 | RN7 支路3，20 Ω → DDR3_D2 | F2 / DQ2 | X:98；C p40 J2.G21；D p4 J4.H31(509.04,140.88)，U y=218.52，RN7 y=402.00 | 通过 |
| c0_ddr3_dq[3] | C0_DDR3_0_dq[3] | AY10 | FMC_HPC1_LA20_N / G22 | G22 → DDR_DQ3 → H32 | H32 / GPIOB_N_33_CDI30 | RN7 支路4，20 Ω → DDR3_D3 | F8 / DQ3 | X:100；C p40 J2.G22；D p4 J4.H32(509.04,144.48)，U y=222.00，RN7 y=405.48 | 通过 |
| c0_ddr3_dq[4] | C0_DDR3_0_dq[4] | AW13 | FMC_HPC1_LA22_P / G24 | G24 → DDR_DQ4 → G34 | G34 / GPIOB_N_32_CDI29 | RN8 支路1，20 Ω → DDR3_D4 | H3 / DQ4 | X:102；C p40 J2.G24；D p4 J4.G34(473.76,151.44)，U y=225.60，RN8 y=419.64 | 通过 |
| c0_ddr3_dq[5] | C0_DDR3_0_dq[5] | AY13 | FMC_HPC1_LA22_N / G25 | G25 → DDR_DQ5 → G33 | G33 / GPIOB_P_32_CDI28 | RN8 支路2，20 Ω → DDR3_D5 | H8 / DQ5 | X:104；C p40 J2.G25；D p4 J4.G33(473.76,147.96)，U y=229.08，RN8 y=423.12 | 通过 |
| c0_ddr3_dq[6] | C0_DDR3_0_dq[6] | AU11 | FMC_HPC1_LA21_P / H25 | H25 → DDR_DQ6 → H34 | H34 / GPIOB_P_31_CDI27 | RN8 支路3，20 Ω → DDR3_D6 | G2 / DQ6 | X:106；C p41 J2.H25；D p4 J4.H34(509.04,151.44)，U y=232.68，RN8 y=426.72 | 通过 |
| c0_ddr3_dq[7] | C0_DDR3_0_dq[7] | AV11 | FMC_HPC1_LA21_N / H26 | H26 → DDR_DQ7 → H35 | H35 / GPIOB_N_31_CDI26 | RN8 支路4，20 Ω → DDR3_D7 | H7 / DQ7 | X:108；C p41 J2.H26；D p4 J4.H35(509.04,155.04)，U y=236.16，RN8 y=430.20 | 通过 |
| c0_ddr3_dq[8] | C0_DDR3_0_dq[8] | AK15 | FMC_HPC1_LA26_P / D26 | D26 → DDR_DQ8 → G36 | G36 / GPIOB_P_30_CDI25 | RN9 支路1，20 Ω → DDR3_D8 | D7 / DQ8 | X:110；C p39 J2.D26；D p4 J4.G36(473.76,158.52)，U y=253.80，RN9 y=444.36 | 通过 |
| c0_ddr3_dq[9] | C0_DDR3_0_dq[9] | AL15 | FMC_HPC1_LA26_N / D27 | D27 → DDR_DQ9 → G37 | G37 / GPIOB_N_30_CDI24 | RN9 支路2，20 Ω → DDR3_D9 | C3 / DQ9 | X:112；C p39 J2.D27；D p4 J4.G37(473.76,162.12)，U y=257.28，RN9 y=447.84 | 通过 |
| c0_ddr3_dq[10] | C0_DDR3_0_dq[10] | AK12 | FMC_HPC1_LA30_P / H34 | H34 → DDR_DQ10 → H38 | H38 / GPIOB_N_29_CDI23 | RN9 支路3，20 Ω → DDR3_D10 | C8 / DQ10 | X:114；C p41 J2.H34；D p4 J4.H38(509.04,165.60)，U y=260.88，RN9 y=451.32 | 通过 |
| c0_ddr3_dq[11] | C0_DDR3_0_dq[11] | AL12 | FMC_HPC1_LA30_N / H35 | H35 → DDR_DQ11 → H37 | H37 / GPIOB_P_29_CDI22 | RN9 支路4，20 Ω → DDR3_D11 | C2 / DQ11 | X:116；C p41 J2.H35；D p4 J4.H37(509.04,162.12)，U y=264.36，RN9 y=454.92 | 通过 |
| c0_ddr3_dq[12] | C0_DDR3_0_dq[12] | AM13 | FMC_HPC1_LA31_P / G33 | G33 → DDR_DQ12 → G22 | G22 / GPIOB_N_28_CDI20 | RN10 支路1，20 Ω → DDR3_D12 | A7 / DQ12 | X:118；C p40 J2.G33；D p4 J4.G22(473.76,109.20)，U y=267.96，RN10 y=468.96 | 通过 |
| c0_ddr3_dq[13] | C0_DDR3_0_dq[13] | AM12 | FMC_HPC1_LA31_N / G34 | G34 → DDR_DQ13 → G24 | G24 / GPIOB_P_27_CDI19 | RN10 支路2，20 Ω → DDR3_D13 | A2 / DQ13 | X:120；C p40 J2.G34；D p4 J4.G24(473.76,116.16)，U y=271.44，RN10 y=472.56 | 通过 |
| c0_ddr3_dq[14] | C0_DDR3_0_dq[14] | AK14 | FMC_HPC1_LA33_P / G36 | G36 → DDR_DQ14 → G25 | G25 / GPIOB_N_27_CDI18 | RN10 支路3，20 Ω → DDR3_D14 | B8 / DQ14 | X:122；C p40 J2.G36；D p4 J4.G25(473.76,119.76)，U y=274.92，RN10 y=476.04 | 通过 |
| c0_ddr3_dq[15] | C0_DDR3_0_dq[15] | AK13 | FMC_HPC1_LA33_N / G37 | G37 → DDR_DQ15 → H29 | H29 / GPIOB_N_26_CDI17 | RN10 支路4，20 Ω → DDR3_D15 | A3 / DQ15 | X:124；C p40 J2.G37；D p4 J4.H29(509.04,133.80)，U y=278.52，RN10 y=479.64 | 通过 |
| c0_ddr3_dm[0] | C0_DDR3_0_dm[0] | AT12 | FMC_HPC1_LA25_P / G27 | G27 → DDR_DM0 → H28 | H28 / GPIOB_P_26_CDI16 | RN25 支路1，20 Ω → DDR3_DM0 | E7 / LDM | X:126；C p40 J2.G27；D p4 J4.H28(509.04,130.32)，U y=296.16，RN25 y=518.40 | 通过 |
| c0_ddr3_dm[1] | C0_DDR3_0_dm[1] | AL14 | FMC_HPC1_LA27_P / C26 | C26 → DDR_DM1 → C23 | C23 / GPIOB_N_23_CDI12 | RN25 支路2，20 Ω → DDR3_DM1 | D3 / UDM | X:128；C p39 J2.C26；D p4 J4.C23(184.44,116.16)，U y=299.64，RN25 y=521.88 | 通过 |
| c0_ddr3_dqs_p[0] | C0_DDR3_0_dqs_p[0] | AV10 | FMC_HPC1_LA28_P / H31 | H31 → DDR_DQS0_P → D26 | D26 / GPIOB_P_25_CDI15 | RN11 支路1，20 Ω → DDR3_DQS_P0 | F3 / LDQS | X:130；C p41 J2.H31；D p4 J4.D26(219.72,126.84)，U y=243.24，RN11 y=493.68 | 通过 |
| c0_ddr3_dqs_n[0] | C0_DDR3_0_dqs_n[0] | AW10 | FMC_HPC1_LA28_N / H32 | H32 → DDR_DQS0_N → D27 | D27 / GPIOB_N_25_CDI14 | RN11 支路2，20 Ω → DDR3_DQS_N0 | G3 / LDQS# | X:132；C p41 J2.H32；D p4 J4.D27(219.72,130.32)，U y=246.72，RN11 y=497.28 | 通过 |
| c0_ddr3_dqs_p[1] | C0_DDR3_0_dqs_p[1] | AJ13 | FMC_HPC1_LA32_P / H37 | H37 → DDR_DQS1_P → C26 | C26 / GPIOB_P_24_EXTFB | RN11 支路3，20 Ω → DDR3_DQS_P1 | C7 / UDQS | X:134；C p41 J2.H37；D p4 J4.C26(184.44,126.84)，U y=285.60，RN11 y=500.76 | 通过 |
| c0_ddr3_dqs_n[1] | C0_DDR3_0_dqs_n[1] | AJ12 | FMC_HPC1_LA32_N / H38 | H38 → DDR_DQS1_N → C27 | C27 / GPIOB_N_24_CDI13 | RN11 支路4，20 Ω → DDR3_DQS_N1 | B7 / UDQS# | X:136；C p41 J2.H38；D p4 J4.C27(184.44,130.32)，U y=289.08，RN11 y=504.24 | 通过 |

位序核对结果：A0–A15、BA0–BA2 和七根控制分别到同一功能；CK_P→J7/CK、CK_N→K7/CK#。低字节 DQ0–7 与 E7/LDM、F3/LDQS、G3/LDQS# 配套；高字节 DQ8–15 与 D3/UDM、C7/UDQS、B7/UDQS# 配套。原 GPIO/LA 名中的 P/N 在单端地址或 DQ 上没有被用来推断 DDR 位序。

## 5. 电源、地、NC 和短接/漏接检查

### 5.1 完整接点覆盖与网络唯一性

| 转接板端 | DDR 接点 | GND 接点 | 3V3 接点 | VADJ 接点 | 独立 NC 接点 | 合计 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| J1（母板端） | 50 | 162 | 5 | 4 | 179 | 400 |
| J2（子板端） | 50 | 157 | 5 | 4 | 184 | 400 |

50 个 MIG 位、wrapper 位、DDR 球号、J1 DDR 接点、J2 DDR 接点分别唯一且完整。当前 XDC 全文件共有 60 条活动 PACKAGE_PIN 分配：50 DDR、2 参考输入、8 其他顶层引脚。检查普通 set_property 和 -dict 两种写法，球号和被约束端口均无重复；未发现覆盖某 DDR 位的后续设置或其他顶层信号复用 DDR 球号。参考输入 AW23/AW22 未进入 50 根 DDR 接点；本次没有评估其时钟设计。

生成网表包含 53 个相连网络：50 DDR、GND、3V3、VADJ。每个 DDR 网只有一个 J1 接点和一个 J2 接点，节点与 contacts 双向对应；未出现两根不同 DDR 网同名、缺节点或一个接点归入多个网。GND 有 319 个节点，3V3 有 10 个，VADJ 有 8 个，50 DDR 共 100 个；相连节点共 437，独立 NC 共 363。

两端的 DDR/GND/3V3/VADJ/NC 接点分类构成各自 400 接点的完整互斥划分，任意两类交集为空。NC 项的 net 为 null，未出现在 nets 中；**NC 不是一个公共相连网络**。转接板不存在以顶底同号隐含直通的网络规则。

### 5.2 每行分类计数（DDR / GND / 3V3 / VADJ / NC）

| 行 | J1 | J2 |
| --- | --- | --- |
| A | 0 / 20 / 0 / 0 / 20 | 0 / 20 / 0 / 0 / 20 |
| B | 0 / 20 / 0 / 0 / 20 | 0 / 20 / 0 / 0 / 20 |
| C | 5 / 21 / 1 / 0 / 13 | 9 / 20 / 1 / 0 / 10 |
| D | 6 / 14 / 4 / 0 / 16 | 8 / 13 / 4 / 0 / 15 |
| E | 0 / 15 / 0 / 1 / 24 | 0 / 15 / 0 / 1 / 24 |
| F | 0 / 14 / 0 / 1 / 25 | 0 / 14 / 0 / 1 / 25 |
| G | 17 / 15 / 0 / 1 / 7 | 19 / 13 / 0 / 1 / 7 |
| H | 22 / 14 / 0 / 1 / 3 | 14 / 13 / 0 / 1 / 12 |
| J | 0 / 15 / 0 / 0 / 25 | 0 / 15 / 0 / 0 / 25 |
| K | 0 / 14 / 0 / 0 / 26 | 0 / 14 / 0 / 0 / 26 |

子板原图 400 接点的独立分类：157 接地；143 有 NC 叉号；3 个无导线且无叉号；其余 97 个有实际连接，其中 87 GPIO、9 个 3V3/VADJ 供电接点和 D1 的 3V3_B 支路。转接板隔离其中未选用的 37 个 GPIO 和 D1，因此 J2 NC=143+3+37+1=184。不能把这 184 个都称为“子板原图 NC”。

母板 159 个标准地针与原生地符号逐项一致；原图 p39 的 C34/GA0、D35/GA1 确实由导线接 GND。J1.H2 是转接板选择拉低母板 p41 的 PRSNT_M2C（该母板网经 R888 4.7 kΩ 上拉到 UTIL_3V3），不是母板原图标准地针；该支路不是 3V3 对地导线短路。子板 J4.H2 的实际引线接地。

### 5.3 重点危险接点的独立核查

| 接点/支路 | 原图事实 | 当前转接板处理 | 结论 |
| --- | --- | --- | --- |
| 子板 J4 B2 | D p4，外侧引线端(106.92,42.12)接 B 行地总线，再到地符号 | J2.B2=GND；生成图 p2 有地标签，无 NC 叉号 | 通过 |
| 子板 J4 F2 | D p4，(371.52,38.64)接 F 行地总线 | J2.F2=GND；生成图 p4 有地标签 | 通过 |
| 子板 J4 G17 | D p4，(473.76,91.56)有 NC 叉号，无导线 | J2.G17=NC；J1 同号为 GND | 通过，顶底无同号直通 |
| 子板 J4 G26 | D p4，(473.76,123.24)有 NC 叉号，无导线 | J2.G26=NC；J1 同号为 GND | 通过 |
| 子板 J4 H6 | D p4，(509.04,52.68)有 NC 叉号，无导线 | J2.H6=NC；J1 同号为 GND | 通过 |
| 子板 J4 H2 | D p4，(509.04,38.64)接 H 行地总线 | J2.H2=GND；J1.H2 用于 PRSNT 拉低 | 通过，区分两端用途 |
| 母板 C34 / D35 | C p39，GA0/GA1 原图接 GND；子板同号有 NC 叉号 | J1 接 GND、J2 同号 NC | 通过 |
| 母板 C35 / C37 | C p39，12P0V_1/2 同接 VCC12_SW；子板同号 D p4 明确 NC | 两个连接器 C35/C37 都 NC | 通过，未接地或 3V3/VADJ |
| 两端 D1 | C p39：VADJ_1V8_PGOOD；D p4：J4.D1→R2 0Ω→3V3_B（相邻 R1=NA 是另一支路） | 两个连接器 D1 都 NC | 通过，PGOOD 与子板 3V3_B 隔离 |
| 母板 G6/G7 | C p40：FMC_HPC1_LA00_CC_P/N | J1.G6/G7 均 NC | 通过，未进入 DDR/参考输入 |
| 子板 G6/G7 | D p4：GPIOR_P_16_PLLIN1→U26.K1/ODT；GPIOR_N_16→U26.T2/RESET# | J1.G18/G19→J2.G6/G7 | 通过，不是同号直通 |
| CK_P / CK_N | C p41 H4/H5→D p4 D11/D12→U26 J7/CK、K7/CK# | 对应 DDR_CK_P/N 两个独立网络 | 通过，极性不反接 |

### 5.4 供电和选择器的实际节点关系

两端 3V3 接点 C39/D32/D36/D38/D40：母板 p39 对应 UTIL_3V3，子板 p4 对应 3V3。VADJ 接点 E39/F40/G39/H40：母板 p40/41 对应共享 VADJ_1V8_FPGA 网，子板 p4 对应 VADJ。本次只确认同名节点关系，不据母板历史网名推断当前实际电压。

| 子板原图位置 | 实际针号与网络 | 资料规定的选择及合并结果 | 核查结果 |
| --- | --- | --- | --- |
| D p4 右上 J5、JU94/JU95 | 外侧1/3=VADJ；5/7=3V3；2/4/6/8=3V3_B | 5–6、7–8；只将3V3接3V3_B，1–2/3–4开路 | 没有合并 VADJ 与3V3；内部蓝字错位不能代替外侧针号 |
| D p3 J199 | 1/3=VDDQ_DDR3；5/7=VADJ；偶数=VDD_MEM_DDR3 | 1–2、3–4，将本地 VDDQ_DDR3 接 DRAM VDD；5–6/7–8开路 | 无本地输出与 VADJ 并联 |
| D p3 J200 | 1/3=VDDQ_DDR3；5/7=VADJ；偶数=VDDQ_MEM_DDR3 | 同上，接 DRAM VDDQ | 通过 |
| D p3 J201 | 1/3=VREF_DDR3；5/7=EXT_VREF_DDR3；偶数=VREF_MEM_DDR3 | 1–2、3–4；5–6/7–8开路 | 本地/外部 VREF 无并联 |
| D p3 J202 | 1/3=VTT_DDR3；5/7=EXT_VTT_DDR3；偶数=VTT_MEM_DDR3 | 1–2、3–4；5–6/7–8开路 | 本地/外部 VTT 无并联 |
| D p3 J222 | 外侧1/3=1V8；5/7=3V3；9/11=VADJ；偶数=VADJ_B | 默认1–2、3–4，只接1V8到VADJ_B | 与3V3、VADJ隔离；VADJ_B不是VADJ别名 |
| D p3 J220/JU67 | 1=5V_B、2=RUN_VDDQ、3=PG_VDDQ | 1–2，未接2–3 | 资料没有把PG_VDDQ与使能/电源误合并 |

这些结论是对指定跳线组合的导线/短接节点审核，实物跳线状态未知。没有将 IC1 升压转换关系误当作 3V3 与 5V_B 的导线直连；也没有把 U25 的稳压输出与其输入网直接合并。DRAM U26B 的 VDD/VDDQ 分别接 VDD_MEM_DDR3/VDDQ_MEM_DDR3，VREFCA/VREFDQ 接 VREF_MEM_DDR3，VSS/VSSQ 接地；源图未显示这些供电网与 DDR 信号的错误导线短接。

### 5.5 电阻支路与 RESET_n

RN7–RN10 每颗四个独立 20 Ω 串联支路分别接 D0–15；RN11 四个独立 20 Ω 支路分别接 DQS_P0/N0/P1/N1；RN25 第一、二支路分别接 DM0/DM1，第三、四支路未接 GPIO。未把阵列四个支路当作同一共用网络。

RN20–RN24 的四个独立 51 Ω 支路、RN26 的 DM 支路分别把 GPIO 接 VTT_MEM_DDR3。这些信号间存在经电阻和 VTT 形成的电阻通路，但没有不经电阻的 GPIO 短接。R240=100 Ω 跨 CK 两端，也是电阻支路，不是 CK_P/N 导线短接。R292=240 Ω 将 U26.L8/ZQ 接地；它不属于50根MIG DDR信号。R293=0 Ω 将未选用的 GPIOB_P_28_CDI21 接 VREF_MEM_DDR3；J4.G21 对应这一 GPIO，而转接板 J2.G21 明确 NC，未把该 VREF 支路误接到母板 DDR_DQ2（DDR_DQ2 在 J1.G21，重排到 J2.H31）。

RN27/28/30/31/32/33/34 为地址/控制的独立 39 Ω 到 VTT 支路。RN28 从上到下：

| RN28 可见支路 | 信号 | 实际 DRAM 功能 | 另一端 |
| --- | --- | --- | --- |
| 1 | GPIOR_P_16_PLLIN1 | U26.K1 ODT | VTT_MEM_DDR3，经39 Ω |
| 2 | GPIOR_N_16 | U26.T2 RESET# | VTT_MEM_DDR3，经39 Ω |
| 3 | GPIOR_P_22_CLK13_P | U26.T3 A13 | VTT_MEM_DDR3，经39 Ω |
| 4 | GPIOR_N_24_CLK11_N | U26.R3 A9 | VTT_MEM_DDR3，经39 Ω |

转接板 PDF p9 / SVG sheet_09 的 R_RESET 标注4.7 kΩ DNP，连接 DDR_RESET_N 与 GND。53网/800接点网表是连接器接点表，没有把可选未装电阻作为短路节点；这与 DNP 状态相容。若 RN28 复位支路和下拉均实装，0.75 V VTT 经39 Ω、4.7 kΩ分压约为0.744 V，已有资料给出的数值正确。**源图确认支路存在；实物支路是否装配、上电是否可靠复位均待实物证据，不能由信号对应关系通过来替代。** 不需要修改50根信号映射；不得整颗拆掉RN28来处理其中一个支路。

### 5.6 图面线端、全局标签和跨页合并

逐项读取 SVG sheet_02–06 和对应 PDF 第2–6页的实际坐标，核对两个连接器全部800个针号、水平引线、末端网络文本与NC叉号：针号和导线在同一行；导线从本分部符号外边缘到正确端点；NC端点各有两条交叉短线，相连网络端点无NC叉号。没有发现某个针号文字配到相邻线、某条线落错针或NC叉号与相连网络矛盾。

800接点图是独立短引线加全局标签的表示法，未画连接器之间的交叉长线；因此没有可被误当作电气连接点的DDR交叉线。J1A/J1B等十个分部属于同一个J1，J2A/J2B等属于同一个J2；按分部并集检查后仍各400个唯一接点。50个DDR标签各出现在一端J1和一端J2上，重复画出的p7/8信号表是同一网络的说明，不是新增器件/接点。GND/3V3/VADJ跨页合并是有意的三张公共网络；NC隔离。p9的三条公共网示意线彼此无交点，R_RESET支路单独画出。

完成了p2–6、p9、p11完整页渲染复查和关键源图局部放大，未发现图面电气标签与网表矛盾。PDF中文文本提取会出现乱码，但渲染中文字可读；ASCII针号、网名及几何检查不受该提取问题影响。未把PDF标题/文本提取顺序当成电气连接依据。

## 6. 非阻断待确认项及最小资料修正建议

### R1：原图悬空引线与“明确 NC”应分开记录

| 接点 | 原始证据 | 当前转接板 | 影响 |
| --- | --- | --- | --- |
| J4.C22 | D p4 J4-2 外侧端(184.44,112.68)：仅棕色引线；无蓝色导线/网络标签/NC叉号 | J2.C22=null/NC，PDF p3/SVG sheet_03有叉号 | 无DDR连接影响；源图意图未明确标注 |
| J4.C30 | D p4 J4-2 (184.44,140.88)，同上 | J2.C30=null/NC | 同上 |
| J4.C31 | D p4 J4-2 (184.44,144.48)，同上 | J2.C31=null/NC | 同上 |

确认事实是“这版源图未画连接”；待确认的是源设计是否有意以无叉号表示不连接，及实际子板修订是否完全相同。没有证据显示这三针应接地、应承载DDR信号或存在漏接，故不报为电气错接。

现有 audit_subcard_source.py 的 `nc = nc or not attached` 把这三针归入nc，同时另外保留nc_cross=False；作为转接板应隔离的分类可接受，作为“源图明确NC”的证据则不充分。最小资料修正建议是保留当前映射不变，在源图核查记录中把C22/C30/C31注明“源图未连接，未画NC叉号；转接板明确NC”，如需修改辅助脚本则分成NC_CROSS与OPEN_UNMARKED两个状态。**本次没有改脚本、映射或既有资料。**

### R2：实物与原生工程证据边界

没有实际PCB封装/布线、子板颗粒丝印、焊装照片/测量记录或原生CAD网表。不能进一步证明封装观察方向/镜像、800焊盘的实际连通、实物焊接短路、跳线/电阻装配、供电及复位实际电平。该项是资料边界，不是已确认的接线错误；不应据此改动本次已验证的50位映射。

## 7. 既有检查脚本的复核结果与局限

在完成原始端点/中间支路重建后，运行 verify_pinmap.ps1 和以 `python -B` 运行 audit_subcard_source.py，均返回PASS。两者为静态读取，没有调用validate_pinout.tcl或Vivado。verify脚本还读取了部分不在本次范围的时钟约束并输出PASS；本报告不采纳那些输出作为物理/时钟设计结论。

本次额外补齐了它们未证明的：MIG实例到BD外部位序、全XDC重复/覆盖扫描、22个GPIO到DDR3_*串联支路、U26全部50个球号/功能、每个字节/极性、实际地符号导线遍历、源图无叉号悬空三针区分、指定跳线组合的网络合并关系，以及生成PDF/SVG的800接点几何和跨页标签检查。独立几何程序仍只适用于这版PDF，不是通用CAD/ERC工具。

Micron官方产品页确认当前配置MT41K512M16HA-125:A属于x16、96-ball封装：[Micron型号页](https://in.micron.com/products/memory/dram-components/ddr3-sdram/part-catalog/part-detail/mt41k512m16ha-125-a)。另查阅了注明Micron作者、包含HA型号的[8Gb DDR3L原厂数据手册镜像](https://www.alliancememory.com/wp-content/uploads/Micron_8Gb_DDR3_SDRAM_PartNo.MT41K512M16HA-107_125.pdf)第1/2页型号信息；这份PDF是Micron文档，不能与Alliance自产型号手册混用。本表的球号/功能证据来自本项目子板源图U26逐引线检查；网页型号信息不证明实物颗粒版本。

## 8. 本次资料指纹

下表对原始证据和主要待审产物记录SHA256。报告写入后复读这些文件确认哈希未变化；11个SVG也纳入该保护检查。本次唯一仓库新增文件是本报告。

| 文件（仓库相对路径） | SHA256 |
| --- | --- |
| README.md | e879a18e3074ec8d47db87de12a7acc5dfa55520f06138b407ee75657dc19122 |
| DATASHEET/FMC_DDR3/adapter_fmc_hpc1/HANDOFF_SCHEMATIC_REVIEW.md | bebbebb303dc0a71e2fc1ff8b0f30bc6cc5c80b7483ec264711554e07a5afc56 |
| DATASHEET/FMC_DDR3/adapter_fmc_hpc1/pinmap.json | 547dab68aece1769af5dbc1c9737dd6a5960d390cb0e9d6366763e9585d5347f |
| DATASHEET/FMC_DDR3/adapter_fmc_hpc1/connections.md | 7b446933906a3ef73fb59d7b0e1b58a2264e4f35f93ea42b617c4d95855d47de |
| DATASHEET/FMC_DDR3/adapter_fmc_hpc1/README.md | 94a4ead1dd88c0e61f4586fe4e55165a8b67951baa5606f44a2209ed6d9c07a2 |
| DATASHEET/FMC_DDR3/adapter_fmc_hpc1/output/adapter_netlist.json | b8e2b7c67e990844bfcd43cb8fa8c5a7b06a2d06e566080a7abf837307faaad6 |
| DATASHEET/FMC_DDR3/adapter_fmc_hpc1/output/pdf/FMC_DDR3_passive_adapter.pdf | 917d01aeb60771fe8a5fdf26126a601e21ccd45ca6c71b66d88c5aa55d82b5d9 |
| DATASHEET/FMC_DDR3/fmc-ddr-gpio-card-schematics-v1.0(1).pdf | 56640b95dcdade8e5a4da6736a55b0062b0142913f98f535ada9aaa6167ef1c2 |
| DATASHEET/VCU118/HW-U1-VCU118_REV2_0_SCHEMATIC_7-14-2017.pdf | 1668aff38f777b480e76b491925eeb4f109ccc0a58b948c9c4ecef3e945cc21d |
| DATASHEET/VCU118/vcu118-schematic-xtp450_cluster/vcu118-xdc-rdf0400/vcu118_rev2.0_12082017.xdc | 5fca111d82b43b30b27f585f0934ff37b512b46bb67c8dee1c91cfde5bbe19ea |
| DATASHEET/VCU118/vcu118-schematic-xtp450_cluster/vcu118-schematic-source-rdf0398/Libs/GOLDEN_SYMBOLS/sym/asp_134486_01_gnd.1 | a379463a199e996bea3b9f5875137a91b021d6a4fef3fe9a38e32fd2d67bcdb2 |
| VIVADO/C910_SOC/C910_SOC.srcs/sources_1/bd/C910_SOC/C910_SOC.bd | 925b78442c115d3944798387c19f8a832bac4cd0a69623aefc8d15ecb985956d |
| VIVADO/C910_SOC/C910_SOC.gen/sources_1/bd/C910_SOC/synth/C910_SOC.v | 0668dfc42c88f0ff73dadff151ee4ce94dc2d3cc7578670bd1e22f6fac6ee9fe |
| VIVADO/C910_SOC/C910_SOC.gen/sources_1/bd/C910_SOC/hdl/C910_SOC_wrapper.v | 5a53688dc85aa6ef6d38bbe4285011ff871968e637af482e5584b21bd306ce3b |
| VIVADO/C910_SOC/C910_SOC.srcs/constrs_1/new/VCU118.xdc | bda680898ab16204b703d32027b9ba90bb777809b69629579477e6eaec65e4d7 |
| VIVADO/C910_SOC/C910_SOC.srcs/sources_1/bd/C910_SOC/ip/C910_SOC_ddr3_0_0/C910_SOC_ddr3_0_0.xci | 88e70edac914e203ff0132f6ed7ea05d817d932ae7c3c29cdbb76dcc3de90428 |
| DATASHEET/FMC_DDR3/adapter_fmc_hpc1/output/svg/sheet_01.svg | 76a461e253fcbf72e56707c569224f018e66323d2867df9d7667ec2318d582b4 |
| DATASHEET/FMC_DDR3/adapter_fmc_hpc1/output/svg/sheet_02.svg | cca26bfb481ed59e8a908c3cb4ff285402836f4994da06b1d52baba8b91c191e |
| DATASHEET/FMC_DDR3/adapter_fmc_hpc1/output/svg/sheet_03.svg | c36f4b8b8ee5ef5b8cf683112b77c0bef519d1dcd3a3e233efe4bcf5b293b475 |
| DATASHEET/FMC_DDR3/adapter_fmc_hpc1/output/svg/sheet_04.svg | ffd3d6246c8ac3d3dbede57ab91b95036a311829893d77b3c1c70008b817c4ec |
| DATASHEET/FMC_DDR3/adapter_fmc_hpc1/output/svg/sheet_05.svg | f124e282591f322e84ec650c511cd7c6a1107f6fcfacb02d15fc97291902451f |
| DATASHEET/FMC_DDR3/adapter_fmc_hpc1/output/svg/sheet_06.svg | b87f30c4dab5061e21c10d765d02498b0b2b99386d5bd47d124ef3e7b5f5b64a |
| DATASHEET/FMC_DDR3/adapter_fmc_hpc1/output/svg/sheet_07.svg | 04931e6caa410f1c7fe9d799fe2e74ed8b6d1ac6471ac4ec85440e2061b68276 |
| DATASHEET/FMC_DDR3/adapter_fmc_hpc1/output/svg/sheet_08.svg | 6e3a129e533ac176be3eef1852180652066163b29bc3e1c14fd35d3c39a2bcac |
| DATASHEET/FMC_DDR3/adapter_fmc_hpc1/output/svg/sheet_09.svg | 555d15cf68db78c389a4351832f246adee4f637da8f5ec5ef7184daa707ce026 |
| DATASHEET/FMC_DDR3/adapter_fmc_hpc1/output/svg/sheet_10.svg | 03ec45b4f9f3fea76f51269330590a391a8ceab85c199b3131e64f92eb1dedf4 |
| DATASHEET/FMC_DDR3/adapter_fmc_hpc1/output/svg/sheet_11.svg | e6efb6739da4e145b1e37b31755eabb4d997aa0bbd7d791a96aa4ab241b46c73 |
