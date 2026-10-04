# VFMau 浮点乘加单元

## 1. 范围与结论

本文只描述 `gen_rtl/vfmau/rtl` 下的 VFMau RTL，并补充它在 VFPU 顶层中的真实连接。VFMau 是一个按 pipe6/pipe7 各复制一份的浮点乘法、乘加和 FMA 前递单元，覆盖 scalar double、scalar single、scalar half，以及由 half 专用路径支持的 half 运算。其主路径是：

```text
IDU/VFPU DP 的操作数与译码
        │
        ▼
ct_vfmau_ctrl ── 有效位、pipedown、门控时钟、flush
        │
        ▼
ct_vfmau_dp ── 操作数寄存/格式化、类型/舍入控制、前递匹配
        │
        ▼
ct_vfmau_mult1
   ├─ ct_vfmau_mult_compressor ── Booth 部分积 + 多级 4:2/3:2 压缩
   ├─ ct_vfmau_mult_simd_half ── half 专用乘加/规格化/舍入
   └─ ct_vfmau_lza ── scalar FMA 前导零预测
      └─ ct_vfmau_lza_simd_half ── half FMA 前导零预测
        │
        ▼
VFPU DP / VFPU rbus：EX3、EX4、EX5 结果、异常、FMLA 前递与写回
```

顶层真实实例关系如下：`ct_vfmau_top` 内部实例化一个 `ct_vfmau_ctrl`、一个 `ct_vfmau_dp`，以及当前 RTL 中实际使能的 `ct_vfmau_mult1_slice0`；`ct_vfmau_mult1` 内部再实例化压缩器和 `mult_simd_half0`。可能的 slice1 代码只是生成器注释/预留，当前连接把 `dp_xx_ex1_simd` 固定为 0，实际没有第二个 slice。证据：`gen_rtl/vfmau/rtl/ct_vfmau_top.v:292-549`、`gen_rtl/vfmau/rtl/ct_vfmau_dp.v:614-617`、`gen_rtl/vfmau/rtl/ct_vfmau_mult1.v:3092-3166`。

## 2. 文件清单与真实职责

| 文件 | 真实模块/实例职责 | 关键证据 |
|---|---|---|
| `gen_rtl/vfmau/rtl/ct_vfmau_top.v` | VFMau 单 pipe 封装；汇合 ctrl、dp、mult1，并把 EX3/EX4/EX5 结果、FMLA 前递和 flush 接到 VFPU | `:17-146`、`:292-549` |
| `gen_rtl/vfmau/rtl/ct_vfmau_ctrl.v` | EX1~EX5 有效位、normal/half pipedown、门控时钟、reset/flush 清空 | `:132-170`、`:178-215`、`:221-259`、`:266-339` |
| `gen_rtl/vfmau/rtl/ct_vfmau_dp.v` | 从 IDU/VFPU DP 取三个源操作数；按 double/single/half 格式化；寄存类型、目的寄存器、舍入模式；生成 FMLA 前递匹配 | `:484-625`、`:630-685`、`:982-1245` |
| `gen_rtl/vfmau/rtl/ct_vfmau_mult1.v` | 主 scalar 乘法/FMA 数据通路；特殊数分类、指数对齐、加法、LZA、规格化、舍入、异常和最终格式化 | `:753-1053`、`:1181-1760`、`:1895-2323`、`:2331-3075` |
| `gen_rtl/vfmau/rtl/ct_vfmau_mult_compressor.v` | 54×54 级别的 Booth 部分积生成和多级压缩；输出 scalar 的 sum/carry 以及 half0 product | `:292-310`、`:317-504`、`:578-1007` |
| `gen_rtl/vfmau/rtl/ct_vfmau_mult_simd_half.v` | half 操作数专用路径；half/单精度加数、特殊值、对齐、乘法/FMA、LZA、规格化与舍入 | `:427-567`、`:572-958`、`:1073-1513`、`:1585-1905` |
| `gen_rtl/vfmau/rtl/ct_vfmau_lza.v` | 108-bit scalar FMA 加法结果的前导零预测，分高 64 bit 与低 44 bit 层次编码 | `:72-92`、`:717-723` |
| `gen_rtl/vfmau/rtl/ct_vfmau_lza_simd_half.v` | 24-bit half FMA 加法结果的前导零预测，输出 5-bit shift 和 zero | `:17-23`、`:55-110` |
| `gen_rtl/vfmau/rtl/ct_vfmau_lza_42.v` | LZA 层次节点；4-bit precode 产生两级 propagate/valid | `:17-41` |
| `gen_rtl/vfmau/rtl/ct_vfmau_lza_32.v` | LZA 层次节点；3-bit precode 产生两级 propagate/valid | `:17-41` |
| `gen_rtl/vfmau/rtl/ct_vfmau_ff1_10bit.v` | 10-bit denormal fraction 的 leading-one 搜索，输出 4-bit 位置 | `:17-20`、`:34-48` |

## 3. `ct_vfmau_top` 的接口与实例化

### 3.1 VFMau 内部端口分组

`ct_vfmau_top` 的端口可按真实使用分为以下几组：

| 端口组 | 代表信号 | 作用 |
|---|---|---|
| 时钟/控制 | `forever_cpuclk`、`cp0_yy_clk_en`、`cp0_vfpu_icg_en`、`cp0_yy_priv_mode`、`rtu_yy_xx_flush` | 门控流水寄存器并在 flush 时清除在途指令 |
| IDU 源操作数 | `idu_vfpu_rf_pipex_func`、`..._gateclk_sel`、`..._srcv0_fr`、`..._srcv1_fr`、`..._srcv2_fr` | 指令功能码、RF 读出及门控选择；`x` 在 pipe6/pipe7 实例中分别替换 |
| VFPU DP 译码 | `dp_vfmau_pipex_inst_type`、`..._sel`、`..._vfmau_sel`、`..._dst_vreg`、`..._imm0` | 选择 VFMau、给出类型、目标 vreg 和立即数舍入控制 |
| FMLA 源 vreg/类型 | `dp_vfmau_pipe6/7_mla_srcv2_vld`、`..._srcv2_vreg`、`..._mla_type` | 用于识别第三操作数是否来自另一条 pipe 的 FMLA 前递 |
| 跨 pipe 前递输入 | `pipe6/7_pipex_ex4_fmla_fwd_vld`、`pipe6/7_pipex_ex5_ex1/ex2_fmla_fwd_vld`，及对应 data | EX4 结果和 EX5→EX1/EX2 的 FMLA 第三操作数前递 |
| 结果输出 | `pipex_dp_ex3/ex4_vfmau_{ereg,freg}_data`、`pipex_rbus_vfmau_{ereg,freg}_wb_*` | 分别给 VFPU DP 的中间结果和 rbus 写回 |
| FMLA 前递输出 | `pipex_pipe{6,7}_ex4_fmla_fwd_vld`、`pipex_vfmau_ex4/ex5_fmla_*_data` | 给本 pipe/另一 pipe 的后续 FMLA 使用 |

端口声明集中在 `gen_rtl/vfmau/rtl/ct_vfmau_top.v:17-146`；内部 wire 汇合在 `:151-286`。

### 3.2 当前顶层实例

`gen_rtl/vfpu/rtl/ct_vfpu_top.v` 中实际有两个 `ct_vfmau_top`：

- `x_ct_vfmau_top_pipe6`：`gen_rtl/vfpu/rtl/ct_vfpu_top.v:1709-1771`。
- `x_ct_vfmau_top_pipe7`：`gen_rtl/vfpu/rtl/ct_vfpu_top.v:1778-1840`。

两者都接入各自 pipe 的 IDU/VFPU DP 信号，并且交叉接收 pipe6/pipe7 的 FMLA 前递有效位和数据。pipe6 实例把 pipe7 的 FMLA 信号接到 `pipe7_pipex_*` 端口，pipe7 实例反向接入 pipe6；这说明第三操作数前递是 VFMau 两个实例之间的真实交叉接口，而不是只在本实例内完成。

## 4. 数据格式与操作数准备

### 4.1 指令类型编码与 fraction mask

`ct_vfmau_dp` 对 `dp_vfmau_pipex_inst_type[5:0]` 的注释给出六类编码：bit0 scalar double、bit1 scalar single、bit2 scalar half、bit3 vector double、bit4 vector single、bit5 vector half（`gen_rtl/vfmau/rtl/ct_vfmau_dp.v:529-536`）。当前 slice0 的实际选择在 `:614-617` 将 SIMD 与 widen 固定为 0，因此本文下面以 scalar 路径和实际激活的 half0 路径为主。

fraction mask 在 `:543-555` 明确给出：

- scalar double：`52'hf_ffff_ffff_ffff`；
- scalar single：`52'h0_0000_007f_ffff`；
- scalar half：`52'h0_0000_0000_03ff`。

这一步先保留相应精度的 fraction，再将操作数送入 `mult1`。功能码 bit5/6/7 分别被解释为 double/single/half，bit0 为 FMA，bit1 为 sub，bit2 为 neg；动态舍入模式在 SIMD 或 `imm0==3'b111` 时来自 `vfpu_yy_xx_rm`，否则来自 `imm0[2:0]`。证据：`gen_rtl/vfmau/rtl/ct_vfmau_dp.v:589-625`。

### 4.2 scalar double/single 的内部格式

在 `ct_vfmau_mult1` 中，EX1 将两个乘数拆成：sign=`[63]`、exponent=`[62:52]`、fraction=`[51:0]`（`gen_rtl/vfmau/rtl/ct_vfmau_mult1.v:753-760`）。single 在 DP 中扩展为 64-bit 计算格式：保留 sign 和 31-bit fraction，并按单精度指数位置插入空位；证据：`gen_rtl/vfmau/rtl/ct_vfmau_dp.v:630-667`。

VFMau 还检查 single 的 NaN boxing。`mult1` 用 `high_vld` 判断高 32 bit 是否满足 boxed 形式，single 高位不合法时构造 canonical NaN；证据：`gen_rtl/vfmau/rtl/ct_vfmau_mult1.v:833-860`。

### 4.3 half 专用格式

`ct_vfmau_mult_simd_half` 将 half 操作数解释为 sign=`[15]`、exponent=`[14:10]`、fraction=`[9:0]`；第三操作数按单精度样式解释为 sign=`[31]`、exponent=`[30:23]`、fraction=`[22:0]`，用于 half FMA 的加数路径（`gen_rtl/vfmau/rtl/ct_vfmau_mult_simd_half.v:427-439`）。DP 对 op2 的 half 输入先形成 32-bit 扩展格式，证据为 `gen_rtl/vfmau/rtl/ct_vfmau_dp.v:658-685`。

当前实际只连接 `mult_simd_half0`：`mult1_simd_half0_sel=1'b1`，并将压缩器输出的 `simd_half0_product`、half0 的前递数据和控制连接到该实例，证据：`gen_rtl/vfmau/rtl/ct_vfmau_mult1.v:3117-3166`。因此不能把当前 RTL 描述为已经并行实例化四个 half lane；文件中的 4-lane 生成注释是预留结构，实际激活的是 half0。

## 5. 乘法部分积与压缩树

### 5.1 Booth 部分积

`ct_vfmau_mult_compressor` 先根据类型选择 hidden bit、乘数宽度和 denormal/normal 模式，形成 zero-extended multiplicand/multiplier；证据：`gen_rtl/vfmau/rtl/ct_vfmau_mult_compressor.v:292-310`。随后实例化 `booth_code_v1 #(53)` 的 `x_booth_code0` 到 `x_booth_code26`，共 27 个重叠 3-bit Booth 窗口，输出 `part_product*`、`h` 和 `sign_not`，证据：`gen_rtl/vfmau/rtl/ct_vfmau_mult_compressor.v:317-504`。

也就是说，乘法不是用一个行为级 `*` 直接完成，而是：

1. 对 multiplier 做 radix-4 Booth 重编码；
2. 每个 Booth 窗口生成带符号、带 hidden-bit 处理的部分积；
3. 按 double/single/half 模式对部分积进行移位、符号扩展和 denormal 辅助项插入；
4. 用 4:2 与 3:2 compressor 将多行部分积压缩到 sum/carry 两行。

### 5.2 压缩树层次

文件注释明确给出不同类型的压缩级数（`gen_rtl/vfmau/rtl/ct_vfmau_mult_compressor.v:578-585`）：

- scalar double/single：EX1 经过 `4:2 -> 3:2 -> 4:2`，EX2 继续 `3:2 -> 4:2`；
- scalar half：EX1 经过 `4:2 -> 4:2`，EX2 完成最终相加。

实际结构可按以下层次读：

- level 1：生成 `p0..p6` 等移位/符号处理后的部分积，并通过 `x_comp0_*` 的 `compressor_42`、`compressor_32` 汇合，证据：`:588-793`；
- level 2：4 个 3:2 和 5 个 4:2，并在 double denormal、half 路径重新插入辅助项，证据：`:795-857`；
- level 3：两个 4:2，处理 single denormal 的特殊项，证据：`:859-905`；
- level 4/5：继续两组 3:2 和一个 4:2，证据：`:954-1000`；
- 最终输出 `compressor_mult1_sum=s4_0`，`compressor_mult1_carry={c4_0[104:0],1'b0}`，形成 106-bit sum/carry，证据：`:1006-1007`。

half0 不等待 scalar 的完整 106-bit 结果，而是在 level 3 后直接形成 `simd_half0_product = s1_5 + {c1_5,1'b0}`，证据：`:907-908`；该结果随后送到 `ct_vfmau_mult_simd_half` 的 `simd_half0_product[21:0]`，证据：`gen_rtl/vfmau/rtl/ct_vfmau_mult1.v:3120-3163`、`gen_rtl/vfmau/rtl/ct_vfmau_mult_simd_half.v:1029-1037`。

level 3 后有门控流水寄存器锁存压缩树中间结果和 `mult1_ex1_ex2_pipedown`，证据：`gen_rtl/vfmau/rtl/ct_vfmau_mult_compressor.v:911-952`。因此压缩树不是单周期组合路径贯穿整个 scalar FMA。

## 6. scalar 乘法/FMA 数据路径

### 6.1 EX1：拆包、分类和乘积准备

`mult1` 在 EX1 完成：

- 拆出 op0/op1 的 sign、exponent、fraction；
- FMLA 时从 pipe6/pipe7 的 EX5→EX1 前递中选择 op2，否则将 op2 特殊字段置为非 FMA 默认值；
- 计算 `product_sign = op0_sign ^ op1_sign ^ neg`；
- 按 double/single 检测 zero、inf、denormal、sNaN、qNaN，并建立 canonical NaN/boxing 状态。

证据：`gen_rtl/vfmau/rtl/ct_vfmau_mult1.v:769-891`。

指数路径按格式选择 bias 与 FMA 的加 3 变体，并生成乘积指数及其 `+3` 版本；证据：`:899-940`。同一处还产生 `slicex_dp_mult1_mult_id`，用于 denormal 或负指数需要走 mult_id 分支的情况，证据：`:942-948`。denormal 会先计算调整量并准备移位量，证据：`:964-989`。

NaN 优先级为 sNaN 高于 qNaN，源操作数 op0 高于 op1，并输出 `dqnan`，证据：`:1033-1053`。

### 6.2 EX2：对齐第三操作数并形成未规格化和

EX2 的 FMA 控制字段包括 `FWD_WIDTH=68` 的前递特殊字段：INF、EXPNT_ZERO、QNAN、SNAN 等，证据：`gen_rtl/vfmau/rtl/ct_vfmau_mult1.v:1181-1226`。FMA 第三操作数的选择顺序是：优先使用 EX5 前递数据，否则使用普通输入；`fma_sub_vld` 由乘积符号、op2 符号、sub 和 neg 组合得到，证据：`:1189-1232`。

乘积指数与 op2 指数比较后选择对齐基准；当差值不小于 -2 时偏向乘积指数，否则偏向 op2 指数，证据：`:1253-1305`。随后完成：

- 右移/左移距离计算；
- 2/3/5 bit 级联移位；
- 超范围移位时的 sticky 生成；
- sub 情况下对 op2 补码化；
- 106-bit 乘积 sum/carry 与对齐后的 op2 合并。

对应证据为 `gen_rtl/vfmau/rtl/ct_vfmau_mult1.v:1417-1612` 和 `:1623-1635`。特殊结果编码在 `:1641-1760` 形成，异常判断覆盖 sNaN、`0*inf`、`inf*0`、`inf-inf` 等 invalid 情况，并在 `:1310-1386` 计算 overflow/potential overflow。

### 6.3 EX3/EX4：加法、LZA、规格化和舍入

EX3 对 FMA 的未规格化和同时计算 `a+b` 与 `a+b+1`，根据 add/sub/neg 选择结果；证据：`gen_rtl/vfmau/rtl/ct_vfmau_mult1.v:1901-1935`。随后形成 fraction shift/sticky，并把 108-bit 加法结果送入 `ct_vfmau_lza`，证据：`:1937-1963`。

对普通乘法，EX3 已完成按 double/single 的 GRS 位提取和舍入；舍入控制覆盖 RN-even、toward zero、正/负无穷和 ties-to-max-mag，证据：`:1977-2104`。overflow、underflow、inexact 在 `:2106-2139` 生成，结果按 double/single/special 格式化在 `:2141-2211`。

FMA 在 EX4 继续根据 LZA shift table 与指数 shift table 选择规格化路径，执行 fraction/exponent 形成和第二条 LZA shift 路径，证据：`gen_rtl/vfmau/rtl/ct_vfmau_mult1.v:2369-2549`、`:2671-2756`。随后完成 GRS 舍入、overflow/underflow/inexact、zero sign、NaN/inf/abnormal 选择，证据：`:2554-2667`、`:2758-2916`。

### 6.4 EX5：结果选择和输出包

EX5 选择普通/特殊路径的 exponent、fraction 和 sign，格式化成最终 64-bit result，同时输出 5-bit exception packet，并形成 FMLA 前递包；证据：`gen_rtl/vfmau/rtl/ct_vfmau_mult1.v:3025-3089`。`ct_vfmau_dp` 将 mult1 的 EX3/EX4/EX5 结果分别转接到 `pipex_dp_ex3/ex4_*` 和 rbus 写回信号，证据：`gen_rtl/vfmau/rtl/ct_vfmau_dp.v:982-994`。

## 7. half 路径、LZA 与 FF1

### 7.1 half 专用运算

`ct_vfmau_mult_simd_half` 独立完成 half 的特殊值和规格化逻辑：

- half/单精度加数的 sign、exponent、fraction 拆包与前递：`:427-479`；
- inf、zero、denormal、NaN boxing 和 sNaN/qNaN：`:481-567`；
- half bias、widen bias、FMA `+3` 指数以及 half mult_id：`:572-600`；
- denormal 的 leading-one 位置由两个 `ct_vfmau_ff1_10bit` 搜索，`:631-678`；
- EX2 进行乘法 GRS 舍入和 FMA 39-bit 加法，`:1073-1439`；
- EX2 将 24-bit FMA 加法结果送入 half LZA，`:1441-1458`；
- EX3 依据 LZA 结果规格化、舍入并输出特殊/普通结果，`:1585-1905`。

注意 `ct_vfmau_mult_simd_half.v` 内部的舍入模式注释与 scalar 文件对正/负无穷的文字标签存在不一致；本文只确认 RTL 的模式分支存在，不替源码重新解释该注释命名。实际联调应以 VFPU 的舍入编码定义和仿真结果为准。

### 7.2 scalar LZA

`ct_vfmau_lza` 对输入的 sum/carry 先计算 propagate/generate/kill，再形成 precode，证据：`gen_rtl/vfmau/rtl/ct_vfmau_lza.v:72-92`。层次树将高 64 bit 和低 44 bit 分别编码；高段有效时选择高段结果，否则选择低段，二者均无效时输出 108，证据：`:717-723`。`ct_vfmau_lza_42` 与 `ct_vfmau_lza_32` 只是树的 4-bit/3-bit 局部节点，并不直接执行完整规格化。

### 7.3 half LZA 与 FF1

`ct_vfmau_lza_simd_half` 针对 24-bit sum/carry 形成 p/g/d 和 precode，通过 `casez` 找到 leading one；全零时置 zero，证据：`gen_rtl/vfmau/rtl/ct_vfmau_lza_simd_half.v:55-110`。

`ct_vfmau_ff1_10bit` 则是独立的 10-bit leading-one 检测器，按从高到低的 `casez` 返回 1 到 10 的位置；全零返回 X，证据：`gen_rtl/vfmau/rtl/ct_vfmau_ff1_10bit.v:34-48`。它服务于 half denormal 输入的预移位，不等同于 FMA 加法后的 LZA。

## 8. 启动、完成、流水和 flush

### 8.1 启动与有效位

`ct_vfmau_ctrl` 用 `dp_vfmau_ex1_pipex_sel` 产生 EX1 指令有效：`ctrl_ex1_inst_vld`；再按 half 与 normal 分别产生 `mult1_ex1_ex2_pipedown` 和 `mult_simd_half_ex1_ex2_pipedown`，证据：`gen_rtl/vfmau/rtl/ct_vfmau_ctrl.v:132-134`。

控制流水依次为：

- EX1→EX2：有效位寄存于 `ctrl_ex2_inst_vld`，`:138-170`；
- EX2→EX3：normal/half pipedown 分流，`:178-215`；
- EX3→EX4：normal 一般继续，half 只有 FMA 继续，`:221-259`；
- EX4→EX5：normal 的 FMA 或 mult_id 继续，half 只有 FMA 继续，`:266-312`；
- FMA 的 EX5 writeback valid：`:319-339`。

因此不能把所有运算简单写成固定同一延迟：主 scalar FMA 走完整 EX1~EX5；normal 乘法和 half 非 FMA 根据 `half`、`fma`、`mult_id` 的组合缩短/改变 pipedown。数据通路中的压缩器也在 EX1/EX2 之间有独立门控寄存器，证据：`gen_rtl/vfmau/rtl/ct_vfmau_mult_compressor.v:911-952`。

### 8.2 门控时钟

每一级流水都用“本级当前有效或下一级即将有效”的组合条件生成局部门控时钟，并叠加 `forever_cpuclk`、`cp0_yy_clk_en`、`cp0_vfpu_icg_en` 和 scan enable。例如 EX1、EX2、EX3、EX4、EX5 的门控结构分别见 `gen_rtl/vfmau/rtl/ct_vfmau_ctrl.v:138-150`、`:183-195`、`:227-239`、`:280-292`，数据寄存器对应结构见 `gen_rtl/vfmau/rtl/ct_vfmau_dp.v:493-526`、`:695-750`、`:789-844`、`:863-918`、`:936-967`。

### 8.3 完成/写回

VFMau 没有单独的 `done` 脉冲端口；完成由带目的寄存器的 EX3/EX4/EX5 valid 和 rbus writeback valid 表示。DP 将 mult1 EX5 结果接到 `pipex_rbus_vfmau_freg_wb_data`、`pipex_rbus_vfmau_ereg_wb_data` 及对应 valid，top 的真实端口连接在 `gen_rtl/vfpu/rtl/ct_vfpu_top.v:1755-1768`（pipe6）和 `:1824-1837`（pipe7）。

FMLA 还产生 EX1/EX2/EX3/EX4/EX5 的前递有效信息。DP 中 EX1/EX2/EX3/EX4 通过源 vreg、类型和 valid 比较决定是否命中，证据：`gen_rtl/vfmau/rtl/ct_vfmau_dp.v:1003-1189`；EX5 前递数据和 valid 在 `:1191-1245` 输出。

### 8.4 reset 与 flush

ctrl 的每一级有效寄存器在 reset 或 `rtu_yy_xx_flush` 时清零，代表 flush 会阻止在途 VFMau 指令继续产生 valid；证据：`gen_rtl/vfmau/rtl/ct_vfmau_ctrl.v:162-170`、`:207-215`、`:251-259`、`:304-312`、`:330-339`。DP 的 FMLA 前递 valid 寄存器也在 reset/flush 时清零，证据：`gen_rtl/vfmau/rtl/ct_vfmau_dp.v:1026-1047`、`:1121-1159`、`:1191-1235`。top 将同一个 `rtu_yy_xx_flush` 接到 pipe6/pipe7 的两个 VFMau 实例，证据：`gen_rtl/vfpu/rtl/ct_vfpu_top.v:1771`、`:1840`。

## 9. 异常与特殊值控制

VFMau 的异常不是在顶层重新计算，而是在 mult1/half 路径随数据流水生成并随 result 一起携带。已能从 RTL 直接确认的控制包括：

- sNaN、qNaN 的分类和优先级；
- single 非法 NaN boxing 转 canonical NaN；
- `0*inf`、`inf*0`、`inf-inf` 等 invalid 条件；
- overflow、underflow、inexact 的检测；
- zero、inf、NaN、denormal 的特殊结果选择；
- FMA 相消后的 zero sign 选择；
- round-to-nearest-even、toward zero、正/负无穷、ties-to-max-mag 等舍入分支。

scalar 特殊检测与异常组合：`gen_rtl/vfmau/rtl/ct_vfmau_mult1.v:795-891`、`:1033-1053`、`:1310-1386`、`:2106-2139`；half 对应逻辑：`gen_rtl/vfmau/rtl/ct_vfmau_mult_simd_half.v:481-567`、`:807-958`、`:1282-1305`、`:1755-1863`。源码输出为 5-bit `expt`/`result_expt` 包；在 VFMau 文件中没有给出可安全独立命名的每一位架构枚举，因此本文不臆测 5 位的位序。

## 10. 与 VFPU、VFALU、VFDSU、IDU、RTU 的接口关系

### 10.1 与 VFPU

VFMau 是 VFPU 顶层的两个 pipe-specific 子单元。VFPU DP 负责从 IDU 信号形成 `dp_vfmau_*` 选择、类型、目的寄存器、第三操作数 vreg 信息；VFPU ctrl 负责把 IDU 的 EU select 转换成 VFMau RF 选择：

```verilog
assign dp_vfmau_rf_pipe7_sel = ctrl_ex1_pipe7_inst_vld_pre && pipe7_eu_sel[4];
assign dp_vfmau_rf_pipe6_sel = ctrl_ex1_pipe6_inst_vld_pre && pipe6_eu_sel[4];
```

证据：`gen_rtl/vfpu/rtl/ct_vfpu_ctrl.v:695-701`。VFPU DP 中 pipe6/pipe7 的 VFMau 选择和 FMLA 源信息分别在 `gen_rtl/vfpu/rtl/ct_vfpu_dp.v:1413-1421`、`:1937-1945`；这些信号接入两份 `ct_vfmau_top`，见 `gen_rtl/vfpu/rtl/ct_vfpu_top.v:1710-1840`。

### 10.2 与 IDU

IDU 不直接连到 compressor 或 LZA，而是通过 VFPU 的 RF/DP/CTRL 接口进入 VFMau。VFMau 直接接收的 IDU 相关信号是 `idu_vfpu_rf_pipex_func`、`..._gateclk_sel`、`..._srcv0_fr`、`..._srcv1_fr`、`..._srcv2_fr`；在 `ct_vfmau_dp` 内寄存并按函数码拆出 FMA、sub、neg、half/single/double、static/dynamic rm，证据：`gen_rtl/vfmau/rtl/ct_vfmau_top.v:84-119`、`gen_rtl/vfmau/rtl/ct_vfmau_dp.v:484-625`。

### 10.3 与 VFALU

当前 RTL 中没有 `ct_vfmau_top` 到 `ct_vfalu_top` 的直接端口。VFALU 是 `ct_vfpu_top` 中与 VFMau 并列的 pipe6/pipe7 执行单元，实例起点在 `gen_rtl/vfpu/rtl/ct_vfpu_top.v:1630-1672`；VFMau 实例起点在 `:1709` 和 `:1778`。二者共享 VFPU 的 pipe dispatch、RF gating、EX3/EX4 DP 结果汇合和 rbus 组织，但 VFMau 的乘法部分积、LZA、异常包不经过 VFALU。

### 10.4 与 VFDSU

VFDSU 同样是 VFPU 顶层的兄弟单元，实例及端口集中在 `gen_rtl/vfpu/rtl/ct_vfpu_top.v:1674-1702`。VFMau 没有直接连接 `vfdsu_dp_fdiv_busy` 或除法完成信号；VFDSU 的 `pipe6_dp_vfdsu_inst_vld` 等状态进入 VFPU ctrl，参与 pipe 的总体有效/选择控制，证据：`gen_rtl/vfpu/rtl/ct_vfpu_ctrl.v:81-132`、`:415-426`、`:622-645`。所以二者的关系是共享 VFPU pipe 控制资源，而不是 VFMau 内部调用 VFDSU。

### 10.5 与 RTU 和 rbus

RTU 通过 `rtu_yy_xx_flush` 直接清空 VFMau ctrl/DP 中的在途有效和 FMLA 前递状态；VFMau 的最终写回由 VFPU rbus 选择。`ct_vfpu_rbus` 的输入明确包含 pipe6/pipe7 的 `vfmau_freg_wb_data`、`vfmau_vreg_wb_vld`、`vfmau_ereg_wb_data`、`vfmau_ereg_wb_vld`，证据：`gen_rtl/vfpu/rtl/ct_vfpu_rbus.v:342-370`；这些信号再进入 pipe6/pipe7 的写回 mux，pipe6 相关选择见 `:1032-1039`、`:1123-1124`，pipe7 相关选择见 `:1338-1340`、`:1431-1432`。

## 11. 阅读时应保留的实现边界

1. 当前 `ct_vfmau_top` 的实际数据通路是 slice0；不要依据生成器注释把未实例化的 slice1 当成已工作的并行 SIMD slice。
2. “完成”由各阶段 valid 和 rbus writeback valid 表示，不存在独立 done 端口。
3. normal、half、FMA、mult_id 的 pipedown 不同，延迟应按 `ct_vfmau_ctrl` 的条件判断理解，不能只用一个固定周期数概括。
4. VFALU/VFDSU 与 VFMau 是 VFPU 顶层兄弟模块；VFMau 只通过 VFPU 的 dispatch、DP 汇合、rbus 和 flush 发生系统级关联。
5. exception packet 的具体架构位序不应从本目录单独臆定；源码只在本单元内提供 5-bit 包的产生和传递。
