# VFALU：向量浮点辅助运算单元

## 1. 范围与结论

`gen_rtl/vfalu/rtl` 是 VFPU 两条执行通道中的浮点辅助运算路径。顶层有两个几乎同构的封装：

- `ct_vfalu_top_pipe6`：实例化 FADD、FSPU 和 pipe6 结果选择/汇聚逻辑；文件中明确没有实例化 FCNVT。
- `ct_vfalu_top_pipe7`：实例化 FCNVT、FADD、FSPU 和 pipe7 结果选择/汇聚逻辑。

两个封装均以 EX1 的 20-bit `func`、3-bit `imm0`、3-bit `sel` 和两个 64-bit 浮点源操作数为输入，输出 EX1 的 MFVR 旁路数据、EX3 的 64-bit FPR 数据和 5-bit EREG/异常数据；pipe7 比 pipe6 多一组 FCNVT 的结果与异常旁路。证据：`gen_rtl/vfalu/rtl/ct_vfalu_top_pipe6.v:15-50`、`gen_rtl/vfalu/rtl/ct_vfalu_top_pipe7.v:15-50`。

这里的 `sel` 是执行单元选择而不是 ready/valid 总线：FSPU 由 `sel[0]` 驱动，FADD 由 `sel[1]` 驱动，FCNVT 由 `sel[2]` 驱动。每个子单元再把该选择位延迟为 EX2/EX3 的 `pipedown`，通过门控时钟推进流水；因此握手形式是“选择位 + 固定 EX1→EX2→EX3 有效链”，没有显式 ready/valid 反压接口。

## 2. VFPU 上下游与 pipe6/pipe7 选择

### 2.1 IDU/VFPU-DP 到 VFALU

`ct_vfpu_top` 从 IDU 接收 pipe6/pipe7 的目的寄存器、EU 选择、20-bit `func`、3-bit `imm0`、源寄存器数据和 gate-clock/ready-stage 等控制字段；这些端口定义集中在 `gen_rtl/vfpu/rtl/ct_vfpu_top.v:270-311`。`ct_vfpu_dp` 再把这些字段变成 VFALU/FMAU/FDSU 的局部接口，端口定义见 `gen_rtl/vfpu/rtl/ct_vfpu_dp.v:94-132`。

pipe6 的 VFALU 选择固定补零到高位：

```text
dp_vfalu_ex1_pipe6_sel = {1'b0, ctrl_ex1_pipe6_eu_sel[1:0]}
```

所以 pipe6 只暴露 FSPU/FADD 两类 VFALU 选择；pipe7 直接使用 `ctrl_ex1_pipe7_eu_sel[2:0]`，因此保留 FCNVT 选择位。两条路径同时转发 `func[19:0]`、`imm0[2:0]` 和来自 IU 的 64-bit MFVR 源数据。证据：`gen_rtl/vfpu/rtl/ct_vfpu_dp.v:1393-1398`、`gen_rtl/vfpu/rtl/ct_vfpu_dp.v:1923-1932`。

FPR 源操作数在 VFPU-DP 的 pipe6/pipe7 EX1 门控时钟上锁存，只有 `gateclk_sel && |eu_sel[4:0]` 时装载 IDU 的两个 64-bit `srcv*_fr`，之后送到 VFALU；pipe6 的锁存与连接见 `gen_rtl/vfpu/rtl/ct_vfpu_dp.v:2088-2109`，pipe7 见 `gen_rtl/vfpu/rtl/ct_vfpu_dp.v:2111-2130`。

### 2.2 VFALU、VFMAU、VFDSU 的并行分发

同一 `ct_vfpu_dp` 中，pipe6 的 `eu_sel[3]` 选择 VFDSU，`eu_sel[4]` 选择 VFMAU；pipe6 VFALU 使用 `eu_sel[1:0]`。pipe7 VFMAU 使用 `eu_sel[4]`，其 VFALU 使用 `eu_sel[2:0]`。FMAU 还接收 MLA 的 v2 寄存器、valid、类型、指令类型及 gate-clock 选择；证据：`gen_rtl/vfpu/rtl/ct_vfpu_dp.v:1400-1421`、`gen_rtl/vfpu/rtl/ct_vfpu_dp.v:1934-1945`。

`ct_vfpu_top` 实例化关系如下：

```text
ct_vfpu_top
├─ ct_vfpu_ctrl / ct_vfpu_dp / ct_vfpu_cbus / ct_vfpu_rbus
├─ ct_vfalu_top_pipe6
│  ├─ ct_fadd_top
│  ├─ ct_fspu_top
│  └─ ct_vfalu_dp_pipe6
├─ ct_vfalu_top_pipe7
│  ├─ ct_fcnvt_top
│  ├─ ct_fadd_top
│  ├─ ct_fspu_top
│  └─ ct_vfalu_dp_pipe7
├─ ct_vfdsu_top                 // pipe6
└─ ct_vfmau_top_pipe6 / ct_vfmau_top_pipe7
```

VFALU 两个实例的实际连接在 `gen_rtl/vfpu/rtl/ct_vfpu_top.v:1629-1670`；VFDSU 在 `gen_rtl/vfpu/rtl/ct_vfpu_top.v:1673-1705`；两个 VFMAU 实例从 `gen_rtl/vfpu/rtl/ct_vfpu_top.v:1708` 和 `:1777` 开始。VFALU 文档范围内不改动、也不重新实现 VFMAU/VFDSU。

### 2.3 VFALU 结果汇聚及 IDU/RTU

VFPU-DP 的 EX3 汇聚按 `eu_sel[2:0]` 选择 VFMAU 或 VFALU：`10` 取 VFMAU，`01` 取 VFALU；无对应单元时 pipe6 保留原始路径，pipe7 使用默认未知值。FPR 和 5-bit EREG 的 pipe6 选择见 `gen_rtl/vfpu/rtl/ct_vfpu_dp.v:1246-1271`，pipe7 见 `gen_rtl/vfpu/rtl/ct_vfpu_dp.v:1787-1809`。随后 EX4 锁存结果，EX5 形成 `dp_ex5_pipe{6,7}_freg/ereg_data_pre`，pipe6 关键逻辑见 `gen_rtl/vfpu/rtl/ct_vfpu_dp.v:1314-1377`。

`ct_vfpu_rbus` 将 EX3/EX5 的 FPR 结果、EREG 数据和有效位同时送回 IDU 的 forward/writeback 接口，并送给 RTU 的 pipe6/pipe7 EX5 写回接口；例如 FPR forward 与 EX4 数据来自 `gen_rtl/vfpu/rtl/ct_vfpu_rbus.v:878-884`，RTU pipe6 有效位/扩展数据见 `gen_rtl/vfpu/rtl/ct_vfpu_rbus.v:946-947`、`:1044`、`:1071`，pipe7 对应见 `:1254-1255`、`:1343`。`rtu_yy_xx_flush` 也进入 rbus 的状态清理路径，端口和处理见 `gen_rtl/vfpu/rtl/ct_vfpu_rbus.v:120`、`:370`、`:909-927`。

## 3. 公共时序和握手

FADD、FCNVT、FSPU 的 CTRL 模块结构一致：

1. EX1 `pipedown` 由执行单元选择位直接生成。
2. EX1 valid 门控时钟在 `ex1_pipedown || ex2_pipedown` 时打开，并在时钟沿把 EX1 valid 推到 `ex2_pipedown`。
3. EX2 valid 门控时钟在 `ex2_pipedown || ex3_pipedown` 时打开，并把 EX2 valid 推到 `ex3_pipedown`。
4. `cpurst_b` 异步清除 EX2/EX3 valid；`cp0_vfpu_icg_en`、`cp0_yy_clk_en` 和 `pad_yy_icg_scan_en` 参与门控时钟。

FADD 的 `ex1_pipedown=sel[1]`、EX1/EX2/EX3 valid 推进见 `gen_rtl/vfalu/rtl/ct_fadd_ctrl.v:62-100`、`:121-158`；FCNVT 的 `ex1_pipedown=sel[2]` 见 `gen_rtl/vfalu/rtl/ct_fcnvt_ctrl.v:56-90`、`:93-122`；FSPU 的 `ex1_pipedown=sel[0]` 见 `gen_rtl/vfalu/rtl/ct_fspu_ctrl.v:58-95`、`:98-127`。

## 4. FADD：浮点加/减、比较、min/max

### 4.1 层级和端口

```text
ct_fadd_top
├─ ct_fadd_ctrl
├─ ct_fadd_scalar_dp
├─ ct_fadd_double_dp
│  ├─ ct_fadd_close_s0_d
│  ├─ ct_fadd_close_s1_d ×2
│  └─ ct_fadd_onehot_sel_d
└─ ct_fadd_half_dp
   ├─ ct_fadd_close_s0_h
   ├─ ct_fadd_close_s1_h ×2
   └─ ct_fadd_onehot_sel_h
```

`ct_fadd_top` 的输入是 20-bit `func`、3-bit `imm0`、3-bit `sel`、两个 64-bit `srcf`、3-bit 全局舍入模式和 DQNaN 配置；输出是 `fadd_forward_result[63:0]`、`fadd_forward_r_vld`、`fadd_ereg_ex3_result[4:0]`、`fadd_ereg_ex3_forward_r_vld` 以及 64-bit 比较/MFVR 结果，端口见 `gen_rtl/vfalu/rtl/ct_fadd_top.v:15-52`。

顶层的有效实例在 `gen_rtl/vfalu/rtl/ct_fadd_top.v:210-279`、`:281-325` 和 `:331-375`。注释中保留了生成器原本的多 set/SIMD 实例模板，但当前 Verilog 中实际可执行实例是一个 CTRL、一个 scalar DP、一个 double DP 和一个 half DP；文档不把被注释实例计入活动层级。

### 4.2 指令解码、舍入和结果旁路

`ct_fadd_scalar_dp` 从 `func` 解码格式和操作：`func[16]`/`func[15]` 分别为 double/single，`func[12:8]` 编码 add/sub/cmp/maxnm/minnm，`func[4:0]` 在比较操作下细分 FEQ/FLT/FLE/FORD/FNE；证据：`gen_rtl/vfalu/rtl/ct_fadd_scalar_dp.v:211-257`。`imm0==3'b111` 时切换到 `vfpu_yy_xx_rm`，否则使用静态 `imm0`；RNE/RTZ/RDN/RUP/RMM 分别为 000/001/010/011/100，见 `:211-221`。

EX1→EX2 锁存格式、操作、比较和舍入位于 `gen_rtl/vfalu/rtl/ct_fadd_scalar_dp.v:270-310`；EX2→EX3 只锁存 half/compare 标志，最终根据 `fadd_ex3_half` 选择 16-bit half 结果（比较时零扩展）或 64-bit double/single 结果，valid 与 5-bit EREG 在 EX3 有效时同时给出，见 `:354-375`。

### 4.3 double/single DP

`ct_fadd_double_dp` 的外部结果为 64-bit，异常为 5-bit，除 double 外通过 `ex1_as_single/ex2_single` 复用单精度路径；接口和 EX1/EX2 控制字段见 `gen_rtl/vfalu/rtl/ct_fadd_double_dp.v:63-104`。EX1 先把输入拆为符号、指数、尾数并识别 0、denorm、normal、infinity、sNaN、qNaN、canonical NaN 等特殊值，double/single 共用的格式切换与分类逻辑见 `:641-734`。

有效数路径分为 close/far：double close 采用 53-bit `ct_fadd_close_s0_d`，两路 54-bit `ct_fadd_close_s1_d`，实例连接见 `:1017-1076`；EX1 的加/减、比较和符号选择逻辑见 `:626-639`。EX1 结果在门控 `ex1_pipe_clk` 上锁存到 EX2，锁存内容包括 far adder、close sum、指数、特殊值分类、比较结果和操作方向，见 `:1308-1380`。

EX2 处理 close/far 归一化、G/R/S 舍入、特殊值和比较结果；close 路选择 one-hot 归一化模块 `ct_fadd_onehot_sel_d`，其 54-bit `data_in/onehot/result` 接口见 `gen_rtl/vfalu/rtl/ct_fadd_onehot_sel_d.v:17-26`，调用见 `gen_rtl/vfalu/rtl/ct_fadd_double_dp.v:2063-2088`。异常位在 EX2 形成 NV/OF/NX 等组合，EX2→EX3 锁存特殊结果、普通结果和 5-bit 异常，EX3 最终在两路结果中选择，见 `gen_rtl/vfalu/rtl/ct_fadd_double_dp.v:2440-2502`、`:2506-2569`。

### 4.4 half DP 和 close/one-hot 子模块

`ct_fadd_half_dp` 对 16-bit half 结果使用 11-bit 输入尾数/指数级 close 运算，输出 16-bit `ex3_result`、5-bit `ex3_expt` 和 EX1 compare 结果；端口见 `gen_rtl/vfalu/rtl/ct_fadd_half_dp.v:56-92`。它实例化 `ct_fadd_close_s0_h`、两路 `ct_fadd_close_s1_h` 和 half one-hot 选择器，见 `:866-930`、`:1784-1804`；其时序同样是 EX1 预处理、EX2 舍入/特殊值、EX3 结果输出，EX1/EX2 门控时钟在 `:1126-1144`、`:2193-2272`。

close 子模块职责是“比较两个对齐尾数、做 close 加/减、产生前导零预测 one-hot”：

| 文件 | 输入/输出宽度 | 作用与证据 |
|---|---|---|
| `ct_fadd_close_s0_h.v` | 11-bit + 11-bit → 11-bit sum、4-bit ff1、11-bit one-hot、eq/op-change | half normal close 的 S0；`gen_rtl/vfalu/rtl/ct_fadd_close_s0_h.v:17-34`、`:63-71` |
| `ct_fadd_close_s1_h.v` | 12-bit + 12-bit → 12-bit sum、12-bit sum-1、6-bit ff1、12-bit one-hot | half S1/归一化 close；`gen_rtl/vfalu/rtl/ct_fadd_close_s1_h.v:17-34`、`:78-100` |
| `ct_fadd_close_s0_d.v` | 53-bit + 53-bit → 两个 53-bit 方向 sum、6-bit ff1、53-bit one-hot | double normal close；`gen_rtl/vfalu/rtl/ct_fadd_close_s0_d.v:17-36`、`:68-84` |
| `ct_fadd_close_s1_d.v` | 54-bit + 54-bit、带 single/double 控制 → 54-bit sum、6-bit ff1、54-bit one-hot | double/single S1 close；`gen_rtl/vfalu/rtl/ct_fadd_close_s1_d.v:17-36`、`:82-102` |
| `ct_fadd_onehot_sel_h.v` | 12-bit `data_in`/`onehot` → 12-bit result | 根据 one-hot 做可变移位；`gen_rtl/vfalu/rtl/ct_fadd_onehot_sel_h.v:17-26`、`:39-60` |
| `ct_fadd_onehot_sel_d.v` | 54-bit `data_in`/`onehot` → 54-bit result | double 可变移位；`gen_rtl/vfalu/rtl/ct_fadd_onehot_sel_d.v:17-26`、`:39-103` |

## 5. FCNVT：浮点/整数及半/单/双精度转换

### 5.1 层级和控制

```text
ct_fcnvt_top
├─ ct_fcnvt_ctrl
├─ ct_fcnvt_scalar_dp
└─ ct_fcnvt_double_dp
   ├─ ct_fcnvt_ftoi_sh
   ├─ ct_fcnvt_itof_sh
   ├─ ct_fcnvt_stod_sh / ct_fcnvt_stoh_sh
   ├─ ct_fcnvt_htos_sh
   ├─ ct_fcnvt_dtos_sh / ct_fcnvt_dtoh_sh
   └─ gated EX1/EX2/EX3 result path
```

FCNVT 只在 pipe7 顶层出现；`ct_fcnvt_top` 输入 20-bit `func`、3-bit `imm0`、3-bit `sel`、64-bit 源操作数、3-bit RM 和 DQNaN，输出 64-bit 结果、5-bit 异常和各自 valid，见 `gen_rtl/vfalu/rtl/ct_fcnvt_top.v:15-48`。实际实例连接为 CTRL、scalar DP、一个 double DP，见 `gen_rtl/vfalu/rtl/ct_fcnvt_top.v:147-244`。

`ct_fcnvt_ctrl` 用 `sel[2]` 产生 EX1 valid，并将 valid 推进 EX2/EX3；证据：`gen_rtl/vfalu/rtl/ct_fcnvt_ctrl.v:56-122`。`ct_fcnvt_scalar_dp` 把 `func[16:13]` 解码为源/目的宽度、widen/narrow/sover/equal，把 `func[3:0]` 解码为整数/浮点源目的类型；具体映射见 `gen_rtl/vfalu/rtl/ct_fcnvt_scalar_dp.v:168-221`。它把 `imm0==111` 替换为全局 RM，并形成 5-bit one-hot 式 `ex1_rm`，见 `:168-182`。

### 5.2 转换 DP、舍入与异常

`ct_fcnvt_double_dp` 的输入是 64-bit `dp_ex1_src`、5-bit EX1 RM、源/目的格式和 EX1/EX2 valid；输出为 64-bit `fcnvt_ex3_result` 和 5-bit `fcnvt_ex3_expt`，见 `gen_rtl/vfalu/rtl/ct_fcnvt_double_dp.v:55-90`。

EX1 先分类源操作数并产生规格化指数/尾数、整数到浮点的前导零计数、浮点到整数的移位信息，以及 narrow/widen 的尾数/尾部；这些中间量的宽度可见 `gen_rtl/vfalu/rtl/ct_fcnvt_double_dp.v:122-242`。EX1→EX2 锁存特殊值、指数、尾数、尾部和目标格式，`ex1_pipe_clk` 及锁存逻辑见 `:773-838`。

EX2 根据 RM 计算 `x==0.5`、`x>0.5`、sticky/LSB，并形成 `ex2_round_add`；代码明确支持 RNE/RTZ/RUP/RDN/RMM，见 `gen_rtl/vfalu/rtl/ct_fcnvt_double_dp.v:859-901`。其后分别生成 double/single/half 浮点结果和 64/32/16/8-bit 有符号/无符号整数结果，同时检测 NV、OF、UF、NX；异常组合见 `:993-1025`、`:1106-1119`，整数宽度溢出检测见 `:1028-1113`。

浮点特殊值处理包括 NaN、Infinity、zero 和 DQNaN 策略；single/half 的 Infinity/LFN/NaN/zero 选择见 `:1122-1209`，最终按目标格式选择浮点或整数结果见 `:1261-1267`。EX2→EX3 锁存 4-bit 内部异常和 64-bit 结果，随后把异常编码扩成 5-bit `{NV,0,OF,UF,NX}` 形式，见 `:1269-1305`。

### 5.3 FCNVT 移位/前导零辅助模块

这些模块均为组合查表/移位网络，没有独立流水寄存器：

| 文件 | 接口宽度 | 作用 |
|---|---|---|
| `ct_fcnvt_stod_sh.v` | 23-bit fraction → 12-bit count、24-bit fraction | single→double 非规格化/前导零计数；`gen_rtl/vfalu/rtl/ct_fcnvt_stod_sh.v:17-27`、`:37-136` |
| `ct_fcnvt_stoh_sh.v` | 8-bit count + 23-bit fraction → 11-bit `f_v`、25-bit `f_x` | single→half 对齐/截取；`gen_rtl/vfalu/rtl/ct_fcnvt_stoh_sh.v:17-27`、`:41-97` |
| `ct_fcnvt_htos_sh.v` | 10-bit fraction → 6-bit count、11-bit fraction | half→single 前导零计数；`gen_rtl/vfalu/rtl/ct_fcnvt_htos_sh.v:17-26`、`:37-84` |
| `ct_fcnvt_dtos_sh.v` | 11-bit count + 52-bit fraction → 24-bit `f_v`、54-bit `f_x` | double→single 对齐/尾部形成；`gen_rtl/vfalu/rtl/ct_fcnvt_dtos_sh.v:17-27`、`:41-149` |
| `ct_fcnvt_dtoh_sh.v` | 11-bit count + 52-bit fraction → 11-bit `f_v`、54-bit `f_x` | double→half 对齐/尾部形成；`gen_rtl/vfalu/rtl/ct_fcnvt_dtoh_sh.v:17-27`、`:41-97` |
| `ct_fcnvt_ftoi_sh.v` | 7-bit count + 53-bit fraction → 64-bit integer main、54-bit tail | 浮点→整数移位与尾部生成；`gen_rtl/vfalu/rtl/ct_fcnvt_ftoi_sh.v:17-28`、`:40-308` |
| `ct_fcnvt_itof_sh.v` | 64-bit integer → count、各目标格式 fraction/tail、carry/0.5 判断 | 整数→浮点的前导零、尾部和舍入预计算；`gen_rtl/vfalu/rtl/ct_fcnvt_itof_sh.v:17-56`、`:1391-1392` |

## 6. FSPU：FMV、FSGNJ 和 FCLASS

### 6.1 层级、接口和流水

```text
ct_fspu_top
├─ ct_fspu_ctrl
└─ ct_fspu_dp
   ├─ ct_fspu_double
   ├─ ct_fspu_single ×2（当前活动路径使用 single0）
   └─ ct_fspu_half ×4（当前活动路径使用 half0）
```

顶层端口为 20-bit `func`、两个 64-bit `srcf`、64-bit `mtvr_src0`、3-bit `sel`，输出 64-bit FPR/MFVR 和 valid，见 `gen_rtl/vfalu/rtl/ct_fspu_top.v:18-47`。实际 active DP 实例为 double、single0、half0，见 `gen_rtl/vfalu/rtl/ct_fspu_dp.v:260-330`；文件中还保留被注释的 SIMD/set1 实例模板，不计入活动网表层级。

`ct_fspu_dp` 由 `func[16]`/`func[15]` 判断 double/single，`func[6]` 配合 `func[0:2]` 识别 FSGNJ/FSGNJN/FSGNJX，`func[5]` 识别 FMVFX/FMVXF，`func[18]` 识别 FCLASS；映射见 `gen_rtl/vfalu/rtl/ct_fspu_dp.v:133-155`。源操作数直接取 VFALU 的两个 64-bit 输入；FMVFX 使用 `mtvr_src0`，见 `:260-266`。

标量读出路径按格式选择 FCLASS 或 FMVXF 的 64-bit 结果，MFVR 输出见 `gen_rtl/vfalu/rtl/ct_fspu_dp.v:340-350`；FPR 结果按 double/single/half 选择，见 `:351-354`。EX1 结果经 gated `ex1_pipe_clk` 锁存 EX2，再经 `ex2_pipe_clk` 锁存 EX3，最终 `fspu_forward_r_vld=ex3_pipedown`，见 `:358-428`。

### 6.2 double/single/half 子模块

三个格式模块共同完成四类组合结果：FMV.V.F、FSGNJ、FSGNJN、FSGNJX；同时生成 FCLASS 和 FMV.X.F 结果。它们均无时钟，输入/输出全为组合接口。

| 文件 | 数据格式与宽度 | 关键行为 |
|---|---|---|
| `ct_fspu_double.v` | 两个 64-bit 操作数，64-bit result/FCLASS/MFVR | 直接使用 sign[63]、exp[62:52]、frac[51:0] 分类；FSGNJ 三种 sign 组合；`gen_rtl/vfalu/rtl/ct_fspu_double.v:31-40`、`:79-145` |
| `ct_fspu_single.v` | 64-bit 容器中的 32-bit single，FCLASS 32-bit，结果 64-bit | 标量时检查高 32-bit canonical NaN；结果高 32-bit 填 `ffffffff`；`gen_rtl/vfalu/rtl/ct_fspu_single.v:31-42`、`:88-177` |
| `ct_fspu_half.v` | 64-bit 容器中的 16-bit half，FCLASS 16-bit，结果 64-bit | 标量时检查高 48-bit canonical NaN；结果高 48-bit 填 `ffffffffffff`；`gen_rtl/vfalu/rtl/ct_fspu_half.v:31-42`、`:88-177` |

single/half 的 `check_nan` 允许 FMV.V.F 输入在非 canonical 高位时归一为 canonical qNaN；single 的判断和常量见 `gen_rtl/vfalu/rtl/ct_fspu_single.v:158-162`，half 见 `gen_rtl/vfalu/rtl/ct_fspu_half.v:156-160`。FCLASS 位向量按负无穷、负 normal、负 denorm、负零、正零、正 denorm、正 normal、正无穷、sNaN、qNaN 生成；single/half 证据分别为 `:113-134` 和 `:112-133`。

## 7. 关键数据宽度与异常/舍入汇总

| 路径 | EX1 输入 | 内部/结果 | EX3 对外 |
|---|---|---|---|
| FADD | `func[19:0]`、`imm0[2:0]`、src0/src1 64-bit | double fraction 52-bit + hidden/guard 扩展，close/far 54/55-bit；half 16-bit、11/12-bit close | FPR 64-bit，比较/MFVR 64-bit，异常 EREG 5-bit |
| FCNVT | `func[19:0]`、`imm0[2:0]`、src 64-bit | 64/53/54-bit 尾数/尾部，目标 half/single/double 或 8/16/32/64-bit 整数 | 结果 64-bit，异常 `NV/OF/UF/NX` 扩为 5-bit |
| FSPU | `func[19:0]`、两个 src 64-bit、`mtvr_src0` 64-bit | 16/32/64-bit 格式字段，统一包装到 64-bit | FPR/MFVR 64-bit，无独立异常输出 |

FADD 的异常在 double DP 的 `ex2_expt` 形成并在 EX3 传出，`ct_fadd_top` 再按 half/非-half 选择 EREG，证据：`gen_rtl/vfalu/rtl/ct_fadd_double_dp.v:2497-2569`、`gen_rtl/vfalu/rtl/ct_fadd_top.v:372-375`。FCNVT 的 EX3 异常编码明确为 `{ex3_expt[3],1'b0,ex3_expt[2:0]}`，证据：`gen_rtl/vfalu/rtl/ct_fcnvt_double_dp.v:1291-1305`。pipe7 汇聚时把 FADD 与 FCNVT 的 EREG valid/data 按位 OR 合并，证据：`gen_rtl/vfalu/rtl/ct_vfalu_dp_pipe7.v:77-80`。

## 8. 文件清单（`gen_rtl/vfalu/rtl`）

- VFALU 封装：`ct_vfalu_top_pipe6.v`、`ct_vfalu_top_pipe7.v`、`ct_vfalu_dp_pipe6.v`、`ct_vfalu_dp_pipe7.v`。
- FADD：`ct_fadd_top.v`、`ct_fadd_ctrl.v`、`ct_fadd_scalar_dp.v`、`ct_fadd_double_dp.v`、`ct_fadd_half_dp.v`、`ct_fadd_onehot_sel_d.v`、`ct_fadd_onehot_sel_h.v`、`ct_fadd_close_s0_d.v`、`ct_fadd_close_s0_h.v`、`ct_fadd_close_s1_d.v`、`ct_fadd_close_s1_h.v`。
- FCNVT：`ct_fcnvt_top.v`、`ct_fcnvt_ctrl.v`、`ct_fcnvt_scalar_dp.v`、`ct_fcnvt_double_dp.v`、`ct_fcnvt_stod_sh.v`、`ct_fcnvt_stoh_sh.v`、`ct_fcnvt_htos_sh.v`、`ct_fcnvt_dtos_sh.v`、`ct_fcnvt_dtoh_sh.v`、`ct_fcnvt_ftoi_sh.v`、`ct_fcnvt_itof_sh.v`。
- FSPU：`ct_fspu_top.v`、`ct_fspu_ctrl.v`、`ct_fspu_dp.v`、`ct_fspu_double.v`、`ct_fspu_single.v`、`ct_fspu_half.v`。

文档只描述上述 RTL 和为确认上下游所读取的 VFPU-DP/CTRL/RBUS 连接；未修改任何 RTL 文件。
