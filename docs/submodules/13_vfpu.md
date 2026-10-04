# VFPU 顶层与 RTL 子模块分析

## 1. 阅读范围与结论

本文只依据 `gen_rtl/vfpu/rtl` 目录内的 5 个文件：

- `ct_vfpu_top.v`
- `ct_vfpu_ctrl.v`
- `ct_vfpu_dp.v`
- `ct_vfpu_cbus.v`
- `ct_vfpu_rbus.v`

该目录包含 VFPU 顶层封装、控制路径、数据路径、完成总线和结果总线；VFALU、VFDSU、VFMAU 的具体算术实现不在本目录，本文只分析 `ct_vfpu_top` 对它们暴露和连接的端口，不能据此推断子单元内部的算法或异常标志生成。

整体上，VFPU 是两个并行发射通道 `pipe6`/`pipe7` 的 EX1～EX5 流水结构：`ctrl` 保存指令/数据有效和执行单元选择，`dp` 保存操作数、目的寄存器和结果路径，VFALU/VFDSU/VFMAU 执行计算，`rbus` 向 IDU/RTU 提供前递和写回，`cbus` 向 RTU 提供完成及 IID。当前顶层把 VDIV 和 VDSP 相关路径固定为无效/零值，因此实际激活的计算单元是 VFALU、pipe6 上的 VFDSU、以及两条 VFMAU。

## 2. 模块树

```text
ct_vfpu_top
├── ct_vfpu_ctrl                 # pipe6/pipe7 EX1~EX5 控制、EU_SEL、valid/fwd
├── ct_vfpu_dp                   # EX1~EX5 数据流水、操作数/目的寄存器、结果选择
├── ct_vfpu_cbus                 # IDU 选中指令 -> RTU 完成/IID
├── ct_vfpu_rbus                 # IDU 目的就绪/前递、EX5 向 IDU/RTU 写回
├── ct_vfalu_top_pipe6           # pipe6 FALU
├── ct_vfalu_top_pipe7           # pipe7 FALU
├── ct_vfdsu_top                 # VFDSU，只有 pipe6 数据入口
├── ct_vfmau_top_pipe6           # pipe6 VFMAU
└── ct_vfmau_top_pipe7           # pipe7 VFMAU

外部公共单元：gated_clk_cell、ct_rtu_expand_64
```

顶层四个 VFPU 子模块的实例位于 `ct_vfpu_top.v:1041`、`1130`、`1357`、`1377`；两个 FALU、一个 VFDSU、两个 VFMAU 的实例位于 `ct_vfpu_top.v:1631-1840`。`ct_rtu_expand_64` 在结果总线中把 6-bit 向量寄存器号扩展成 64-bit mask，实例位置见 `ct_vfpu_rbus.v:956-962`、`1265-1271`。

## 3. 顶层跨目录连接

### 3.1 IDU 到 VFPU

IDU 为 pipe6/pipe7 提供成对的 RF 指令入口，包括：

- `*_sel`、`*_gateclk_sel`：指令选择和时钟门控选择；
- `*_eu_sel[11:0]`：执行单元选择；
- `*_func[19:0]`、`*_imm0[2:0]`、`*_inst_type[5:0]`；
- `*_srcv0_fr`、`*_srcv1_fr`、`*_srcv2_fr[63:0]`；
- `*_dst_vreg[6:0]`、`*_dst_ereg[4:0]`、`*_dst_preg[6:0]` 及对应 valid；
- `*_ready_stage[2:0]` 和 VFMAU 的 MLA/VMLA 辅助字段。

这些端口在顶层声明于 `ct_vfpu_top.v:263-327`，并分别扇出到 CTRL、DP、VFDSU、VFMAU 和 CBUS。CTRL 只使用选择、EU_SEL、MTVR valid/指令字段；DP 使用操作数、功能码、目的寄存器和 ready stage；CBUS 只使用 `sel/gateclk_sel/iid`；VFMAU 直接取得 RF 源操作数及 MLA 字段。顶层实际连接关系集中在 `ct_vfpu_top.v:1041-1354`、`1357-1628`、`1675-1840`。

IU 的 MTVR 旁路分别从 `iu_vfpu_ex1_pipe0/pipe1_mtvr_*` 进入 pipe6/pipe7 的 CTRL、DP；EX2 的 MTVR 源操作数直接送到 FALU 的 `*_mtvr_src0`。MTVR 的有效、指令和目标向量寄存器连接见 `ct_vfpu_top.v:1120-1123`、`1287-1290`；FALU MTVR 源端口见 `ct_vfpu_top.v:1631-1669`。

### 3.2 VFPU 内部互连

```text
IDU/IU
  │
  ├──> CTRL ──ctrl_ex*_inst_vld/data_vld/fwd_vld/eu_sel──┐
  │                                                       │
  └──> DP ──操作数/功能码/目的寄存器/ready stage──────────┤
                                                          ├──> VFALU/VFDSU/VFMAU
                                                          │       │
                                                          └<── DP 结果/valid
                                                                │
                               DP 结果、CTRL valid、FMAU wb ───> RBUS ──> IDU/RTU
  IDU sel/iid ───────────────────────────────────────────> CBUS ──> RTU
```

CTRL 的输出 valid/eu_sel 同时驱动 DP 的流水和各执行单元选择；DP 的 `dp_ctrl_ex*_data_vld_pre`、`dp_ctrl_ex*_fwd_vld_pre` 反馈给 CTRL，用于把数据 ready/fwd 信息沿 EX1～EX4 传递。顶层以同名内部 wire 对接，CTRL/DP 的双向控制连接可由 `ct_vfpu_top.v:1041-1354` 直接核对。

FMAU 还存在跨 pipe 的乘加前递和共享 slice 数据：pipe6 VFMAU 接收 pipe6/pipe7 的 FMA 前递信号，pipe7 VFMAU 也接收两条 pipe 的对应信号；两者分别输出 `pipe*_rbus_*` 写回/无前递信号以及 `pipe*_vfmau_*` slice 数据。具体端口连接见 `ct_vfpu_top.v:1710-1771`、`1779-1840`。RBUS 用 `pipe*_rbus_vfmau_*_wb_*` 覆盖普通 FPR/EREG 写回数据，见 `ct_vfpu_rbus.v:1032-1039`、`1121-1125`、`1337-1343`、`1429-1433`。

## 4. 指令类别选择与数据路径

### 4.1 12-bit EU_SEL 的实际映射

CTRL 参数 `EU_WIDTH=12`，见 `ct_vfpu_ctrl.v:316`。普通指令的 12-bit `idu_vfpu_rf_pipe*_eu_sel` 先在 CTRL 的 EX1 锁存，并由 valid 屏蔽后输出 `ctrl_ex1_pipe*_eu_sel`。MTVR 指令不直接沿用 IDU EU_SEL，而是按 MTVR 指令位合成选择：`inst[1:0]` 非零或 `inst[4]` 为真时选择 bit0，否则选择 bit7；pipe6/pipe7 分别见 `ct_vfpu_ctrl.v:1037-1058`、`1063-1084`。

DP 在 EX2 将 12-bit 选择压缩为内部类别选择：

| DP 类别 | 选择条件 | 后续路径 |
| --- | --- | --- |
| FALU | pipe6 为 `ctrl_ex1_pipe6_eu_sel[2:0]` 的归并；pipe7 同样使用 `[2:0]` | `dp_vfalu_ex1_pipe*_sel`，见 `ct_vfpu_dp.v:1395-1398`、`1929-1932` |
| FDSU | `ctrl_ex1_pipe*_eu_sel[3]`；EX2 同时把 bit11 视为 FDSU 类 | pipe6 `dp_vfdsu_ex1_pipe6_sel`，见 `ct_vfpu_dp.v:1402-1407`；pipe7 的 EX2 重编码见 `1613-1616` |
| VFMAU | bit4 | `dp_vfmau_ex1_pipe*_sel`，见 `ct_vfpu_dp.v:1413-1421`、`1937-1945` |
| VDSP/其它向量类 | pipe6 EX2 对 `[10:5]` 做归并，pipe7 仅保留固定为 0 的类别位 | 顶层 VDSP 输入数据/内部前递能力固定为 0，见 `ct_vfpu_top.v:1000-1007` |
| FDSU/VDIV 返回数据 | pipe6 `pipe6_dp_vfdsu_inst_vld || vdivu_vfpu_ex1_pipe6_result_vld` | EX2 选择返回目标和返回阶段，见 `ct_vfpu_dp.v:1024-1047` |

其中 FALU 的 pipe6 选择端口写成 `{1'b0, ctrl_ex1_pipe6_eu_sel[1:0]}`，而 pipe7 直接传 `[2:0]`，这是 RTL 的通道差异，不应把两者简单看成完全相同的编码。VFMAU 的 `dp_vfmau_rf_pipe*_sel` 在 CTRL 中由 EX1 指令 valid 和 `pipe*_eu_sel[4]` 生成，见 `ct_vfpu_ctrl.v:700-701`。

### 4.2 pipe6 数据路径

1. EX1：`idu_vfpu_rf_pipe6_gateclk_sel` 触发 DP EX1 门控寄存器，锁存 func、IID、源操作数、目的寄存器、立即数、ready stage 和 VFMAU MLA 字段；若同时是 MTVR，则覆盖 func/目标 vreg，并把 `dstv_vld` 置 1。数据寄存器入口与 MTVR 优先级见 `ct_vfpu_dp.v:871-1009`。
2. EX1 dispatch：FALU 得到 func/imm/MTVR 源和两个 FPR 源，VFDSU 得到 IID、目标寄存器、imm、两个源和 div issue，VFMAU 得到目标 vreg、imm、inst_type、MLA 信息，见 `ct_vfpu_dp.v:1395-1421`。
3. EX2：DP 把 FALU/FDSU/VFMAU/VDSP/返回数据重新编码到 `dp_ex2_pipe6_eu_sel_pre[4:0]`；VFDSU 或 VDIV 返回时目标 vreg、EREG 和 ready stage 取返回通道，见 `ct_vfpu_dp.v:1024-1047`、`1072-1140`。
4. EX3：根据 `[eu_sel[2], eu_sel[0]]` 在 VFMAU、VFALU 和原始/返回数据之间选择 FPR/EREG 结果；选择逻辑见 `ct_vfpu_dp.v:1245-1274`。
5. EX4/EX5：产生普通 vreg/ereg 写回 valid，并在 ready stage 表示 FMAU 延迟时选择 VFMAU EX4 数据，否则使用 EX3/EX4 保存的数据，见 `ct_vfpu_dp.v:1280-1385`。RBUS 随后把这些结果锁存到 EX5 并输出 IDU/RTU。

### 4.3 pipe7 数据路径

pipe7 同样从 EX1 进入，但在本目录的 RTL 中没有 pipe6 的 VFDSU 返回数据输入；其 EX2 选择只建立 FALU、FDSU、VFMAU 三类，`dp_ex2_pipe7_eu_sel_pre[3]` 固定为 0，见 `ct_vfpu_dp.v:1605-1663`。pipe7 EX3 的结果选择和 EX4/EX5 写回选择见 `ct_vfpu_dp.v:1784-1921`。

pipe6/pipe7 的 DP 目的 vreg 在 EX1、EX2、EX3 各保留多份 duplicate，交给 RBUS 的 IDU ready/依赖检查路径；对应导出赋值见 `ct_vfpu_dp.v:1430-1454`、`1950-1970`，RBUS 再按 EX1/EX2/EX3 扇出到 IDU，见 `ct_vfpu_rbus.v:832-870`、`1141-1168`。

## 5. CTRL、CBUS、RBUS 的握手与回写

### 5.1 CTRL：valid、ready stage 和前递

CTRL 对 pipe6/pipe7 各自生成 EX1～EX5 的 instruction valid、data valid 和 EX3/EX4 forward valid。普通 RF 指令由 `idu_vfpu_rf_pipe*_sel` 进入；MTVR 由 `iu_vfpu_ex1_pipe*_mtvr_vld` 进入；pipe6 的 EX2 还可接收 `pipe6_dp_vfdsu_inst_vld` 和 VDIV 返回 valid，见 `ct_vfpu_ctrl.v:415-489`。数据 valid 不是简单的指令 valid：EX1/EX2/EX3 会与 DP 反馈的 `*_data_vld_pre` 相与，并复制到多个 duplicate 信号，供 IDU 多路旁路检查。

MFVR valid 在 EX1 由 `inst_vld_pre && dp_ex1_pipe*_dst_vld_pre` 形成，然后在 EX2 再打一拍；这些 valid 和目的 preg duplicate 由 DP/RBUS 送回 IDU，见 `ct_vfpu_ctrl.v:361-413`、`999-1026` 及 `ct_vfpu_dp.v:1000-1021`。

### 5.2 CBUS：完成与 IID

CBUS 对两个 pipe 的完成条件分别直接取 `idu_vfpu_rf_pipe6_sel` / `idu_vfpu_rf_pipe7_sel`，gateclk 条件取对应 `gateclk_sel`，见 `ct_vfpu_cbus.v:118-119`、`177-178`。完成 valid 在共享的 `vfpu_inst_vld_clk` 上寄存并输出 RTU；IID 则在 pipe 专用 data clock 上仅当选中指令时锁存 IDU IID，见 `ct_vfpu_cbus.v:124-165`、`183-224`。因此 CBUS 的 RTU 完成是“IDU 已选中并经过一拍”的路径，不是算术结果写回 valid。

### 5.3 RBUS：前递、vreg/ereg 写回

RBUS 将 CTRL 的 EX1/EX2/EX3 data valid 和 DP 的各阶段目的 vreg duplicate 送回 IDU；EX3/EX4 forward 则直接给出目的 vreg 与 FPR 数据，见 `ct_vfpu_rbus.v:832-889`、`1141-1190`。

pipe6 的普通 vreg/ereg 写回 valid 来自 DP 的 `dp_ex4_pipe6_normal_dstv_wb_vld` / `normal_dste_wb_vld`，而这两个信号明确排除了 VFDSU（`!dp_ex4_pipe6_eu_sel[1]`），见 `ct_vfpu_dp.v:1382-1388` 和 `ct_vfpu_rbus.v:896`、`1054`。pipe7 的 valid 分别为 `ctrl_ex4_pipe7_inst_vld && dp_ex4_pipe7_dstv_vld`、`ctrl_ex4_pipe7_inst_vld && dp_ex4_pipe7_dste_vld`，见 `ct_vfpu_rbus.v:1203-1205`、`1362-1365`。

EX5 写回分为：

- vreg：锁存 vreg 号和扩展 mask；FPR 数据在 `pipe*_rbus_vfmau_vreg_wb_vld` 为真时优先取 VFMAU 写回，否则取 DP 普通结果，见 `ct_vfpu_rbus.v:986-1039`、`1299-1343`；
- ereg：锁存 EREG 号和数据；`pipe*_rbus_vfmau_ereg_wb_vld` 为真时优先取 VFMAU EREG 数据，见 `ct_vfpu_rbus.v:1104-1131`、`1412-1438`；
- RTU：输出 EX5 vreg expand、EREG 号和对应 valid；IDU 还得到 FPR/VR valid、重复 vreg 号和写回数据。

本目录把所有 VR0/VR1 数据通道固定为 0、VR valid 固定为 0，说明当前实现只产生 scalar/FPR 形式的 64-bit 结果或 vreg 编号扩展，不在这里实现 128-bit 两半数据的真实写回，证据见 `ct_vfpu_rbus.v:1442-1468`。

## 6. VFALU、VFDSU、VFMAU 的顶层端口边界

### VFALU

pipe6/pipe7 各有一个 VFALU。DP 送入 `func[19:0]`、`imm0[2:0]`、`sel[2:0]`、两个 64-bit FPR 源和 MTVR 源；VFALU 返回 MFVR EX1 数据以及 EX3 的 FPR/EREG 结果。两个实例及端口见 `ct_vfpu_top.v:1631-1669`。

### VFDSU

本顶层只实例化一个 `ct_vfdsu_top`，挂在 pipe6。DP 送入 pipe6 的目标 vreg/EREG、IID、imm、两个 FPR 源和 `sel`，同时送入 `idu_vfpu_is_vdiv_*` 两个 issue 信号；VFDSU 返回 `inst_vld`、FPR/EREG 数据、目标 vreg/EREG，以及 `fdiv_busy`、`inst_wb_req` 和 IFU debug 状态，见 `ct_vfpu_top.v:1675-1707`。这些返回 valid/busy 再进入 DP/CTRL/RBUS 的上层控制；pipe7 没有对应 VFDSU 实例。

### VFMAU

pipe6/pipe7 各有一个 VFMAU。每个实例接收本 pipe 的 `sel`、目标 vreg、imm、func、源 v0/v1/v2，并接收两条 pipe 的 MLA/FMA 前递和 slice 数据；同时向 RBUS 返回 vreg/EREG 写回数据和 valid、FMA 前递 valid、无前递判定。端口连接见 `ct_vfpu_top.v:1710-1771`、`1779-1840`。VFMAU 的具体舍入、异常和乘加算法不在本目录。

## 7. 异常、舍入、flush 与配置

### 7.1 舍入和 NaN 配置

`cp0_vfpu_fxcr[26:24]` 被 DP 提取为 `vfpu_yy_xx_rm[2:0]`，`cp0_vfpu_fxcr[23]` 被提取为 `vfpu_yy_xx_dqnan`，见 `ct_vfpu_dp.v:1973-1975`。这两个信号由顶层同时连到 pipe6/pipe7 VFALU、VFDSU、VFMAU，见 `ct_vfpu_top.v:1631-1840`。本目录没有异常 flag 输出或异常状态寄存器更新逻辑；只能确认配置广播边界，不能确认子单元内部的异常分类/封存行为。

### 7.2 flush

`rtu_yy_xx_flush` 是同步清空控制状态的输入：CTRL 的 EX1～EX5 valid、MFVR valid、EU_SEL 寄存器在 flush 时清零，例证为 `ct_vfpu_ctrl.v:351-413`、`449-489`、`518-614`、`691-809`、`856-979`、`999-1084`；CBUS 的两个完成 valid 在 flush 时清零，见 `ct_vfpu_cbus.v:124-133`、`183-192`；RBUS 的 EX5 valid 在 flush 时清零，见 `ct_vfpu_rbus.v:901-934`、`1059-1067`、`1210-1239`、`1368-1375`。顶层还把 flush 直接传给 VFDSU 和两个 VFMAU，见 `ct_vfpu_top.v:1697`、`1771`、`1840`。

需要注意：`ct_vfpu_dp` 的端口列表没有 `rtu_yy_xx_flush`，其 EX1～EX4 数据寄存器只显式处理 `negedge cpurst_b` 和各自时钟使能。因此 flush 依赖 CTRL 的 valid 抑制、RBUS/CBUS 的 valid 清除和算术子单元自身的 flush 输入，DP 已锁存的数值字段不会由该模块直接清零（`ct_vfpu_dp.v:15-239`）。

### 7.3 参数、宏和未使用配置口

本目录没有实际的 Verilog ``ifdef``/``define`` 分支。文件中的 `// &Depend("cpu_cfig.h")`、`// &Force(...)` 和 `// &Instance(...)` 是生成器/检查器注释，不是当前编译时宏逻辑。主要参数为：

| 文件 | 参数 |
| --- | --- |
| `ct_vfpu_ctrl.v:316` | `EU_WIDTH=12` |
| `ct_vfpu_dp.v:838-845` | `VLEN=128`、`EU_WIDTH=12`、`SILEN=64`、`FPR_MSB=63`、`VREG=7`、`VL=8`、`XLEN=64`、`FUNC_WIDTH=20` |
| `ct_vfpu_rbus.v:822-824` | `FPR_MSB=63`、`SILEN=64`、`VREG=7` |

`cp0_vfpu_fcsr`、`cp0_vfpu_vl`、MTVR 的 VL/LMUL/SEW、两路 `iu_vfpu_ex2_pipe*_mtvr_vld` 在顶层有端口声明，但在这 5 个 RTL 文件中没有实际赋值/功能连接；相关位置只有端口声明和生成器 `Force` 注释，见 `ct_vfpu_top.v:263-327`、`966-995`。因此不能把这些端口当作当前目录已实现的向量 mask/VL 控制路径。

## 8. 时钟与复位

所有时序块使用异步低有效复位 `negedge cpurst_b`；正常时钟来自 `forever_cpuclk` 经 `gated_clk_cell` 生成。门控单元普遍使用：

- `global_en = cp0_yy_clk_en`；
- `module_en = cp0_vfpu_icg_en`；
- `local_en` 由对应 pipe 的 gateclk、valid、返回 valid 或写回 valid 组合；
- `pad_yy_icg_scan_en` 作为扫描使能。

CTRL 为 pipe6/pipe7 各级建立 EX1～EX5 门控时钟，见 `ct_vfpu_ctrl.v:326-331`、`428-429`、`497-498`、`573-574`、`625-626` 及 pipe7 对应 `667-957`；DP 为 pipe6/pipe7 建立 EX1～EX4 门控时钟，见 `ct_vfpu_dp.v:871-875`、`1051-1053`、`1156-1158`、`1293-1295`、`1467-1471`、`1626-1628`、`1714-1716`、`1831-1833`；CBUS 和 RBUS 另外为 IID、结果数据和 EREG/vreg 写回建立门控时钟，见 `ct_vfpu_cbus.v:96-141`、`200-200` 以及 `ct_vfpu_rbus.v:969-984`、`1084-1102`、`1279-1294`、`1392-1410`。

顶层曾有一个覆盖整个 VFPU 的总门控时钟方案，但该段已被注释并标明因 timing reason 删除，实际设计采用各子模块/流水级局部门控，证据见 `ct_vfpu_top.v:1008-1030`。

## 9. 关键结论

1. `ct_vfpu_ctrl` 决定“这条指令在哪条 pipe、哪个 EX 阶段有效”，`ct_vfpu_dp` 决定“操作数/目的寄存器/结果走哪条执行单元路径”，二者通过 `ctrl_*` 和 `dp_ctrl_*_pre` 形成闭环。
2. EU_SEL 的核心类别是 FALU `[2:0]`、FDSU `[3]`/返回类、VFMAU `[4]`；`[10:5]` 的向量类在本顶层没有有效 VDSP 实现，pipe7 还明确将对应内部类别位置 0。
3. VFDSU 只在 pipe6 有实例，且 pipe6 DP 专门接收 VFDSU 的 EX1 返回结果；VDIV 相关 valid/busy/目标信号在顶层全为常量 0。
4. CBUS 的完成来自 IDU `sel`，RBUS 的写回来自 EX4/EX5 数据 valid；二者是不同握手域，不能用算术写回 valid 代替 RTU completion。
5. 舍入模式和 default-quiet-NaN 只在本目录完成抽取和广播；实际异常/舍入计算属于 VFALU/VFDSU/VFMAU 子单元。
