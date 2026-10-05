# VCU118 FMC_HPC1 - DDR3 无源转接板资料

版本 2026-10-04-C。**画原理图请优先使用 [完整逐针对应表](connections.md)**：50 条 DDR、两端电源、逐行全部 GND 和 NC，均直接列明，不需要导入我的图纸或 EDA 工程。

本版独立重查原始 PDF 实际引线，纠正子板端五处误标：B2/F2 由 NC 改为 GND，G17/G26/H6 由 GND 改为 NC；50 条 DDR 映射未改。原 PDF、SVG、800 针网表同步修正。本次仅修改这些连线资料和检查脚本，**没有改 Vivado、XDC、BD 或任何时钟配置，没有运行综合/实现**。

转接板不需要晶振、PLL、时钟缓冲芯片或 FPGA。它只重排 50 根 DDR 信号、连接必要电源和公共地；未用接点明确 NC。MIG 参考输入由 VCU118 母板供给，DRAM CK 由 FPGA 内的 MIG 经 FMC 输出。它不是 400 针同号直通板。

## 1. 两种时钟和现有工程状态（版本 B 的历史改动）

| 用途 | 路径 | 频率 | 经过转接板 |
| --- | --- | --- | --- |
| MIG 参考输入 | 母板 U18 Si570 -> U157 Q2 -> USER_SI570_CLOCK1_P/N -> FPGA AW23/AW22 -> IBUFDS -> BUFG -> MIG / clk_wiz | 250 MHz，4 ns | 否 |
| DRAM CK 输出 | FPGA BC9/BC8 -> 母板 J2 H4/H5 -> 转接板 -> 子板 J4 D11/D12 -> U26 J7/K7 | 800 MHz，1600 MT/s，tCK=1250 ps | 是 |

母板 **J8 必须插上**以选 U18；开路选择固定 300 MHz。U18 默认上电频率是 156.25 MHz，必须在每次断电重启后用匹配母板控制器固件的 SCUI 把 **Si570_0 设置为 250 MHz**，确认读回/实际输出。250 MHz 的 XDC 与 MIG 参数不会自动改变外部时钟器件。本次未执行硬件编程或固件升级。

原固定 250 MHz 输入 E12/D12 位于 SLR2，另一对 AW26/AW27 位于 SLR0；DDR Bank 66/67 位于 SLR1，不能直接恢复为此 MIG 的系统输入。所以使用母板已有、可编程的 U18，而不是转接板晶振。

AW23/AW22 是 Bank 64 GC 输入，同属 SLR1、I/O 列 X1。BD 新增 board_sysclk_bufg_0：IBUFDS -> BUFG -> MIG 与 clk_wiz。XDC 将 BUFG 放在输入 CMT（BUFGCE_X1Y120，X4Y5），到内存 MMCM 使用专用 BACKBONE；没有 CLOCK_DEDICATED_ROUTE FALSE 豁免。母板已有参考接收端终端，转接板不加此终端。

母板 J2 G6/G7 现在 **NC**，不再是参考输入。子板 J4 G6/G7 仍是 ODT / RESET_n，分别由母板 J2 G18/G19 接入，不能同号直通。MIG 已为 4000 ps / 250 MHz；本次保留内存型号、tCK、x16、AXI128、CL11/CWL8 等数值。旧 75 MHz 说明已删除。

## 2. 图纸、网表和接口命名

| 转接板位号 | 安装面 / 料号 | 配对对象 |
| --- | --- | --- |
| J1 | 底面 ASP-134488-01 | VCU118 的 J2 FMC_HPC1，ASP-134486-01 |
| J2 | 顶面 ASP-134486-01 | DDR 子板的 J4，ASP-134488-01 |

转接板 J2 与母板 J2 不是同一器件。两接口各 400 针，行 A/B/C/D/E/F/G/H/J/K，每行 1..40，无 I 行。全部针号是电气针号；上下表面镜像不能改针号。

- [pinmap.json](pinmap.json)：唯一数据源，包含全部 50 条 DDR、FPGA 球号、两端 FMC 真正接点、原始网络名及 U26 球号，电源/地/NC/复位条件。
- [逐针对应表](connections.md)：首选的人工画图资料；含全部 50 根信号和两端全部 GND/NC，接口命名和画图方法。
- [连线核对图及制作指导](output/pdf/FMC_DDR3_passive_adapter.pdf)：11 页，含两接插件全部 800 针的网络/NC、50 条 DDR 两端对照、供电和复位条件、PCB 指导。是辅助连线图，不是可导入并运行 ERC 的原生 CAD 原理图。
- [800 针机器可读网表](output/adapter_netlist.json)：53 个连接网络（50 DDR + GND + 3V3 + VADJ）、逐针状态及可选 R_RESET。NC 不成共享网络。
- output/svg/：同图逐页矢量源。
- generate_adapter_docs.py：从 JSON 生成图纸及网表。不是已验证的 EasyEDA 原生项目或已布线 PCB；没有 Gerber 生产文件。

CK/DQS 正负极性和字节对应必须保持；DQ0..7/DM0/DQS0 属于 Bank 67 T0，DQ8..15/DM1/DQS1 属于 T3。地址、控制与 CK 都在 Bank 66。普通单端地址/DQ 的 LAxx_P/N 或 GPIO_P/N 原名不表示 DDR 差分对，不能按原网络名字交换位序。

## 3. 电源、地、NC 和上电复位

| 接点 / 功能 | 转接板处理 |
| --- | --- |
| 双方 C39、D32、D36、D38、D40 | 公共 3V3 网，全部电源针参与供电 |
| 双方 E39、F40、G39、H40 | VADJ 网；母板实际输出必须设为并测得 1.5 V |
| 双方 C35/C37 | 两端均 NC。母板是 12 V，子板是 NC，**不是 GND** |
| 双方 D1 | 不连。母板 VADJ_PGOOD 与子板经 R2 的 3V3_B 隔离 |
| 母板端 G6/G7 | NC，无参考时钟 |
| 母板端 C34/D35 | 母板已接地的 GA0/GA1，接 GND；子板同号 NC |
| 转接板 J1 H2 | PRSNT_M2C 接 GND表示插卡；本专用板不加 FRU EEPROM，人工设 VADJ |
| 子板端 B2/F2 | GND；旧版 B 的 NC 标记错误，已更正 |
| 子板端 G17/G26/H6 | NC；原图有 NC 叉号，不按标准地针默认接地 |
| 子板端 H2 | GND |
| 全部已确认地针 | 加入同一连续地平面，逐针列于图纸/网表 |
| 其他所有针 | NC，不透传 MGT、HA/HB、I2C、管理 JTAG、其他 GPIO |

主接点中母板端 162 个接 GND（159 标准地 + C34/D35/H2），子板端 157 个（标准地去掉 G17/G26/H6，加 H2）。NC 分别 179 / 184 个。完整列表见 connections.md；额外屏蔽/机械端子按厂商 footprint 单独核对，不混入 400 针。NC 焊盘无网络，不因上下同号而共用过孔。

DDR Bank 66/67 VCCO=1.5 V。XDC 的 SSTL15_DCI / DIFF_SSTL15_DCI、RESET_n=SSTL15、INTERNAL_VREF=0.75 不能代替电源设置。VADJ 与其他 FMC Bank 共享，原 J22 C910 JTAG 使用 LVCMOS18，必须另外解决电平兼容后才连接外部 JTAG；本次未改动它。

子板图中有 U25 LTM4632 和本地升压电路，生成 VDD/VDDQ=1.5 V、VTT/VREF=0.75 V；必须已焊装/工作。若实物真的只焊颗粒而未焊供电、去耦和终端，信号重排板不能补齐这些；不是要求加晶振，而是确认必要供电/无源器件。

采用子板本地电源时，断电按图核查，最后实测：

| 子板选择器 | 选择 | 用途 |
| --- | --- | --- |
| J5（JU94/JU95） | 5-6、7-8；不接 1-2/3-4 | 3V3 -> 3V3_B，隔离 D1 后的来源 |
| J199 / J200 | 各 1-2、3-4；不接 5-6/7-8 | 本地 VDDQ_DDR3 -> DRAM VDD / VDDQ |
| J201 / J202 | 各 1-2、3-4；不接 5-6/7-8 | 本地 VREF / VTT -> DRAM |
| J220（JU67） | 1-2 | 本地 5V_B -> RUN_VDDQ |

R257 调至 1.5 V，确认 VTT/VREF=0.75 V；不得并联本地稳压器与 VADJ。J222 默认本地 1.8 V 的 VADJ_B 是另一辅助网。母板 12 V 不连接，不可替代子板 5V_B。

复位：原图 RN28 的 RESET_n（GPIOR_N_16）有 **39 ohm 接 VTT** 支路。若已焊装，4.7 kohm 对地下拉不足以保持低（静态约 0.744 V）。图纸 R_RESET=4.7 kohm 为 **DNP 可选位**，确认 RESET_n 终端支路未焊装或已单独隔离后，才按 PG150/UG583 的上电复位要求焊装。不要整颗移除 RN28，其余 ODT/A13/A9 仍有终端；返修方式依实物阵列结构确认。已有等效可靠复位则不重复加下拉。没有修改实物子板。

最小 BOM 是两个 FMC；按复位条件选无源下拉，按 PDN 评估选去耦。无晶振或有源器件。

## 4. PCB 制作规范

1. 机械/封装：使用两料号的正式 Samtec land pattern 和 3D 模型，核对公母、高度、定位柱、支撑孔与散热器净空。两次配对高度累加，距离依据实际料号/板厚/支撑柱装配模型。先打印 1:1 封装核对实物，丝印标 A1 和观察方向，不猜焊盘坐标，不共享不同网络的顶底焊盘过孔。
2. 层叠：建议 8 层，例 L1 信号 / L2 GND / L3 信号 / L4 GND / L5 电源 / L6 信号 / L7 GND / L8 信号。板厚、介质、铜厚、线宽由制造厂按阻抗计算。每条 DDR 有连续参考地，不跨地缝/电源岛。6 层只有完成逃线、参考平面和链路预算再采用。
3. 布线：CK/DQS 是差分，DQ/DM 是单端。每字节除逃线尽量同层；差分同步换层、过孔数一致，接地回流过孔距信号过孔不超过 50 mil（1.27 mm）。不加长测试支路或任意加终端。子板已有 20 ohm 串联、51/39 ohm 到 VTT、CK 100 ohm 网络，按实际焊装纳入模型。
4. 阻抗：UG583 数据参考主干 39 ohm +/-10% 单端、76 ohm +/-10% DQS 差分，逃线 50/86 ohm；不是“所有 FMC 都选 100 ohm”。既有板阻抗无法由转接板改变，最终 CK/CA/DQ/DQS 目标依据全链路模型及终端确定。制造厂提供网类/层叠/阻抗券；这些参考值不是投板批准。
5. 延迟：T总=T封装+T母板+T两次接口+T转接板+T子板。取得 FPGA package flight time（min/max 取中值）、既有两板逐线长度/层叠/过孔及接插件模型，再计算本板补偿；几何等长不等于电气等延迟。缺少这些输入不能保证 1600 MT/s。

| UG583 保守全链路参考检查 | 限制 |
| --- | --- |
| 同字节 DQ、DM 相对对应 DQS | +/-10 ps |
| DQS P/N、CK P/N | 各 2 ps |
| 地址/命令/控制相对 CK | +/-8 ps；RESET_n 不要求此等长 |
| CK 到 DQS 偏差 | -149..1796 ps，依指南定义方向 |
| 数据总延迟，含 FPGA 封装 | <=1186 ps |

最终速度等级/工作速率可按官方降额表重审预算，不能无依据放宽。全链路数据参考最大 PCB 过孔数 2，不是每块板各有 2 个；双接口三块 PCB 的偏离必须完整 SI 验证。未知母板/子板长度时不编造毫米等长数，Vivado DRC 不能代替链路检验。

6. 电源/地：3V3、VADJ 分网，12 V 隔离；按最大负载、接点额定电流、温升和压降计算铜宽与过孔。没有负载数据不指定虚假固定线宽。所有地针接公共地平面，连接器附近适量地过孔，避免差分对不对称。
7. 投板审核：原理图 ERC、800 针网表比对、PCB DRC、机械对接、阻抗/总延迟/SI 后才能发布。制造资料应含 Gerber/ODB++、钻孔、层叠/阻抗、尺寸/公差、BOM、坐标、装配图、电测网表和表面处理。当前没有完成布线生产文件。

## 5. 验证与验收边界

版本 C 本次审核：从原始 PDF 的黑色外侧电气针号及实际引线，独立核对母板第 39/40/41 页全部 50 对针号/网络、子板第 4 页全部 400 针引线/地总线/NC、50 对针号/GPIO 网络。U26 球号、CK/DQS 极性和字节归属、供电页和 RN28 另作图面复核。静态检查 50 条 DDR 对 wrapper/XDC/官方 XDC、全部 800 针网表一致，52 个 FPGA DDR/参考引脚唯一。

版本 B 的既有记录（不是本次重新执行）：器件 IO-planning 查询同 SLR/列；BD 验证及 HDL 生成；MIG XCI 328 项配置值与当时修改前一致（除 boundaryDescription 元数据），原地址映射不变。

**没有运行综合、布局布线、bitstream 或硬件编程。新 BUFG/参考路径尚未做新网表物理 DRC/时序验证。** BD 有原有 BRAM_PORTA 未接和 aclk PHASE 参数提示，不是零警告。旧 validation/ 报告只属版本 A 的 FMC 外部参考隔离验证，不能证明版本 B 通过。

verify_pinmap.ps1 是只读静态检查。audit_subcard_source.py 用 pdfplumber 独立读取仓库源 PDF 的引线/NC/地总线，并检查两板 50 对针号/网络；不是用生成图与自身 JSON 相互验证。它依赖本仓库源图的几何/颜色，不是通用 PDF 网表提取器，不替代原生 EDA ERC 或实物测量。validate_pinout.tcl 含综合/实现，未来另获授权才执行，本次未运行。

上电前断电测 50 条信号、电源地和 NC 隔离（特别 C35/C37/D1）、相邻脚短路，用完整网表验收 800 针。先实测 VADJ=1.5 V、DRAM 电源、复位低，再设 J8/U18=250 MHz，最后加载匹配工程观察 init_calib_complete 并做全地址/跨字节/长期压力和温度测试。

## 6. 来源

- 仓库 VCU118 Rev2.0 原理图 sheet 11/12、39/40/41、44；官方 XDC、连接器原生 GND 符号。
- 仓库子板 fmc-ddr-gpio-card-schematics-v1.0(1).pdf 第 3/4 页。蓝色内部针号有错位，以外侧黑色真正电气针号为准。
- [AMD PG150 DDR3 Pin Rules](https://docs.amd.com/r/en-US/pg150-ultrascale-memory-ip/DDR3-Pin-Rules)、PG150 跨 Bank No_Buffer 的 BUFG/BACKBONE 要求。
- [VCU118 UG1224](https://docs.amd.com/api/khub/documents/Uoc4S9pQd1uve6kiGiG2kA/content)：U18/J8/Q2 与默认频率、每次上电重编程。
- [UG583 DDR3 路由预算](https://docs.amd.com/r/en-US/ug583-ultrascale-pcb-design/DDR3-SDRAM-Routing-Constraints)、[数据布线](https://docs.amd.com/r/en-US/ug583-ultrascale-pcb-design/DDR3-SDRAM-Data-Signals-Point-to-Point)、[通用规则](https://docs.amd.com/r/en-US/ug583-ultrascale-pcb-design/General-Memory-Routing-Guidelines)。
- [Samtec ASP-134486-01 图纸](https://suddendocs.samtec.com/prints/asp-134486-01-mkt.pdf)；生产前核对 134488 图纸和实物。

按实际板卡修订、颗粒丝印、焊装、跳线及机械/高速预算复核后再投板。
