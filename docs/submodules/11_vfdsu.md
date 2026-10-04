# VFDSU：向量/浮点除法与平方根单元

## 1. 范围与结论

本说明基于 `gen_rtl/vfdsu/rtl` 下 12 个 Verilog 文件逐文件阅读，并补充反查了 VFPU 顶层、VFPU 数据通路、VFPU 控制、IFU debug、整数 SRT 复用点。这里的“VFDSU”是 VFPU pipe6 上的标量浮点除法/平方根后端；它接收一对 64-bit 源操作数，内部按双精度、单精度或半精度选择字段。当前真实结构不是顶层注释中所描述的多套 half/single lane 展开：`ct_vfdsu_top` 实际只实例化 `ct_vfdsu_ctrl`、`ct_vfdsu_double`、`ct_vfdsu_scalar_dp`（`gen_rtl/vfdsu/rtl/ct_vfdsu_top.v:225-325`），而多 lane 实例化只保留为注释（同文件 `:137-224`）。

数据通路为：

```text
IDU/RF -> ct_vfpu_dp(pipe6) -> ct_vfdsu_top
       -> scalar_dp/prepare -> SRT radix16 -> round -> pack
       -> ct_vfdsu_scalar_dp(EX4 metadata + result)
       -> ct_vfpu_dp(EX2) -> VFPU result/forwarding/writeback
```

VFALU 与 VFMAU 是同一 `ct_vfpu_top` 下的并列执行单元，不是 VFDSU 的子模块，也没有发现 VFDSU 与它们之间的直接操作数或结果数据连接；它们主要共享 VFPU 的 issue、时钟门控、flush、舍入/NaN 配置和 DP 级结果选择（`gen_rtl/vfpu/rtl/ct_vfpu_top.v:1635-1705`、`:1710-1774`）。

## 2. 文件与层次

| 文件 | 实际职责 |
|---|---|
| `ct_vfdsu_top.v` | 顶层端口、三个内部实例和连接；`double` 负责数值流水，`scalar_dp` 负责操作类型译码、源/目的寄存器元数据和结果出口（`:18-48`、`:225-325`）。 |
| `ct_vfdsu_ctrl.v` | SRT 迭代状态/计数器、EX1→EX2→EX3→EX4 valid、除法 writeback 状态机、门控时钟和 busy/WB 信号（`:183-275`、`:304-361`、`:364-514`）。 |
| `ct_vfdsu_scalar_dp.v` | 从 IDU function 位译码 div/sqrt/单/双精度；锁存 EX2/EX3/EX4 目的寄存器信息；把 `ex4_out_*` 送回 pipex（`:170-230`、`:237-313`）。 |
| `ct_vfdsu_double.v` | 组合 `prepare`、SRT、round、pack，名称虽为 double，但通过 precision 位复用 half/single/double 路径（`:172-363`）。 |
| `ct_vfdsu_prepare.v` | IEEE 类别识别、非规格数归一化、指数准备、特殊结果、NaN payload/sign、舍入模式和 SRT 初值（`:243-360`、`:390-485`、`:498-647`、`:649-747`）。 |
| `ct_vfdsu_ff1.v` | 对 52-bit fraction 做 leading-one 查找，输出移位后的 fraction 和指数校正值（`:15-24`、`:34-92`）。 |
| `ct_vfdsu_srt.v` | EX2 指数/溢出/下溢及跳过条件，接收最终 remainder/quotient，并把 EX2 结果寄存到 EX3；实例化实际浮点 SRT 核（`:268-378`、`:503-613`、`:648-686`）。 |
| `ct_vfdsu_srt_radix16_with_sqrt.v` | 浮点除法和平方根共用的 radix-16 SRT 核；维护 remainder、正/负 quotient 累积、digit selection 和 58-bit quotient（`:17-58`、`:275-412`、`:420-510`、`:860-1065`）。 |
| `ct_vfdsu_srt_radix16_bound_table.v` | 7-bit bound index 到 9 个 12-bit digit boundary 的查表；包含普通除法、sqrt 首轮和 sqrt 第二轮正/负 remainder 表（`:17-46`、`:102-113`、`:1126-1163`）。 |
| `ct_vfdsu_srt_radix16_only_div.v` | 另一套 66/71/68-bit、带 borrow-flop 接口的纯除法 SRT 核；本目录内没有被 VFDSU 浮点路径实例化。它被整数除法 `ct_iu_div_srt_radix16` 复用（`gen_rtl/vfdsu/rtl/ct_vfdsu_srt_radix16_only_div.v:17-72`；`gen_rtl/iu/rtl/ct_iu_div_srt_radix16.v:172-200`）。 |
| `ct_vfdsu_round.v` | EX3 quotient/remainder 的舍入判定、非规格数移位、NX/UF/OF 等 EX4 中间结果（`:279-358`、`:685-750`、`:752-889`、`:891-1013`）。 |
| `ct_vfdsu_pack.v` | EX4 组合 exponent/fraction，选择 normal/denormal/zero/qNaN/Inf/LFN，并生成 5-bit exception（`:140-155`、`:280-376`、`:378-412`）。 |

## 3. 启动、迭代、完成和取消

### 3.1 启动与 issue

`ct_vfdsu_scalar_dp` 在 `idu_vfpu_rf_pipex_gateclk_sel` 下采样 `idu_vfpu_rf_pipex_func`：bit0=`div`、bit1=`sqrt`、bit16=`double`、bit15=`single`（`gen_rtl/vfdsu/rtl/ct_vfdsu_scalar_dp.v:169-185`）。`ex1_scalar` 常量为 1，舍入立即数直接取 `dp_vfdsu_ex1_pipex_imm0[2:0]`，源操作数直接取 `srcf0/srcf1`（同文件 `:187-195`）。

真正的 VFDSU 选择来自 VFPU DP 的 `ctrl_ex1_pipe6_eu_sel[3]`；`dp_vfdsu_idu_fdiv_issue` 和 gate-clock issue 来自 IDU 的 `idu_vfpu_is_vdiv_issue` / `idu_vfpu_is_vdiv_gateclk_issue`（`gen_rtl/vfpu/rtl/ct_vfpu_dp.v:1400-1408`）。

除法 writeback 状态机为 `IDLE -> RF -> EX1 -> EX2 -> WB_REQ -> WB`。IDLE 看到 `dp_vfdsu_idu_fdiv_issue` 进 RF；RF 下一拍进 EX1；EX1 只有 `dp_vfdsu_ex1_pipex_sel` 为真才进入 EX2；EX2 等 SRT 最后一轮；WB_REQ 等 `ex4_pipedown`；WB 完成后可接收下一条 issue（`gen_rtl/vfdsu/rtl/ct_vfdsu_ctrl.v:364-435`）。`ex1_pipedown` 就是 `dp_vfdsu_ex1_pipex_sel`（同文件 `:150-151`）。

### 3.2 SRT 迭代

在 EX1 首拍，SRT core 由 `initial_srt_en=ex1_pipedown` 装入 remainder/divisor 和选择模式。浮点顶层把 divisor 扩成 `{ex1_divisor,3'b000}`，把 remainder 装成 `{2'b00,ex1_remainder[59:1]}`；除法用 divisor 高位作为初始 bound index，sqrt 使用 0（`gen_rtl/vfdsu/rtl/ct_vfdsu_srt.v:648-658`）。

`ct_vfdsu_ctrl` 用 `srt_cur_state` 表示 SRT idle/busy；busy 状态在 `srt_last_round` 时退出。最后一轮条件是 `skip_srt`、remainder 为 0 或计数器为 0，且 SRT 当前为 busy（`gen_rtl/vfdsu/rtl/ct_vfdsu_ctrl.v:183-227`）。

精度计数器的实际 RTL 是：double 初值 `5'b01101`（13），single 为 6，half/其它为 3（同文件 `:243-248`）。每个 busy 周期减 1（`:229-240`），所以按实现应理解为“首轮装载 + 计数驱动的 radix-16 迭代”，而不是按旧注释中的 double=28/single=14（注释 `:243-245`）解释。旧注释与当前赋值不一致；精确的首轮是否计入外部 cycle 计数，应以门级时钟/波形为准。

当最后一轮条件成立且仍处于除法状态 EX2 时，`ex2_pipedown` 拉高（`:250-251`）。该信号随后在 EX2→EX3、EX3→EX4 各经过一级 valid 寄存器（`:304-361`）。因此，特殊值或指数路径跳过 SRT 也不会绕过 EX2/EX3/EX4 控制流水，只是 `srt_ctrl_skip_srt` 使迭代提前结束。

### 3.3 完成、WB 和 busy

`vfdsu_ex3_vld` 是 EX2→EX3 的 valid，`vfdsu_ex4_vld` 是 EX3→EX4 的 valid；`vfdsu_dp_inst_wb_req= vfdsu_ex3_vld`，表示结果请求写回；`pipex_dp_vfdsu_inst_vld` 只在 writeback 状态 WB 时为 1；`vfdsu_dp_fdiv_busy=div_cur_state[2]`（`gen_rtl/vfdsu/rtl/ct_vfdsu_ctrl.v:309-361`、`:506-514`）。注意 busy 不是简单的“从 issue 到 WB 全程为 1”，它由状态 bit[2] 解码，RF/EX1 阶段不置位。

flush 或 reset 会清空 SRT state/counter、div state、EX2/EX3/EX4 valid 和各级结果寄存器（例如 `gen_rtl/vfdsu/rtl/ct_vfdsu_ctrl.v:184-191`、`:394-401`、`gen_rtl/vfdsu/rtl/ct_vfdsu_srt.v:525-554`）。`ct_vfdsu_top` 的 `rtu_yy_xx_flush` 直接连入控制器（`gen_rtl/vfdsu/rtl/ct_vfdsu_top.v:225-257`）。

## 4. 精度、输入格式和特殊值

### 4.1 精度字段

`prepare` 根据 `ex1_double/ex1_single` 选择 sign、exponent、fraction：double 使用 `[63] / [62:52] / [51:0]`，single 使用 `[31] / [30:23] / [22:0]`，half 使用 `[15] / [14:10] / [9:0]`（`gen_rtl/vfdsu/rtl/ct_vfdsu_prepare.v:248-294`）。single/half fraction 会左填 0 扩展到 52-bit 运算宽度（`:384-389`），SRT 公共路径最终通过不同指数边界和 quotient 位段截取实现。

实际顶层只提供一对 64-bit `srcf0/srcf1`；源数据由 VFPU DP 从 RF 读出并同时送给 VFALU、VFDSU 的 pipe6 路径（`gen_rtl/vfpu/rtl/ct_vfpu_dp.v:2098-2109`）。因此这里的“向量”更多是 VFPU/DP 的架构上下文，不能从当前 `ct_vfdsu_top` 得出内部同时处理多个 lane 的结论。

### 4.2 类别识别与异常前置

`prepare` 识别 infinity、zero、denormal、sNaN、qNaN；标量 half/single 还会用高位 all-one 检测 cNaN（`gen_rtl/vfdsu/rtl/ct_vfdsu_prepare.v:299-360`）。denormal 通过两个 `ct_vfdsu_ff1` 找最高有效位并产生校正指数（`:361-389`）。

前置 invalid 条件包括 div 的 sNaN、0/0、Inf/Inf，以及 sqrt 的 sNaN 或负 normal/Inf（`:430-452`）；divide-by-zero 是 normal/zero divisor（`:470-475`）。特殊结果 zero/qNaN/Inf 及 default qNaN 条件在 `:485-528` 形成，special result 会通过 `ex1_srt_skip` 跳过正常 SRT（`:654-657`）。

### 4.3 NaN 和全局配置

舍入模式选择为：当立即数为 `3'b111` 或不是 scalar 时使用全局 `vfpu_yy_xx_rm`，否则使用指令立即数（`gen_rtl/vfdsu/rtl/ct_vfdsu_prepare.v:533-535`）。本模块按代码注释将 000/001/010/011/100 分别作为 RNE/RTZ/RDN/RUP/RMM 处理（`:536-552`）。

全局 `vfpu_yy_xx_rm` 来自 `cp0_vfpu_fxcr[26:24]`，`vfpu_yy_xx_dqnan` 来自 `cp0_vfpu_fxcr[23]`（`gen_rtl/vfpu/rtl/ct_vfpu_dp.v:1970-1975`）。`dqnan` 打开时优先保留被选中的 sNaN/qNaN payload/sign，否则回退到 canonical/default qNaN；default qNaN 的 fraction 为 `{1'b1,51'b0}`、sign 为 0（`gen_rtl/vfdsu/rtl/ct_vfdsu_prepare.v:589-646`）。

## 5. 指数、SRT 结果和舍入

EX2 由 `vfdsu_ex2_expnt_add0 - vfdsu_ex2_expnt_add1` 得到指数差；sqrt 将结果右移一位并保留符号位作为除以 2 的效果（`gen_rtl/vfdsu/rtl/ct_vfdsu_srt.v:268-273`）。double/single/half 各自有 overflow、potential overflow、underflow、potential underflow 阈值（`:274-346`）。`srt_ctrl_skip_srt` 在 overflow、某些非规格数已经足够小、或 EX1 特殊结果时有效（`:368-378`）。

### 5.1 radix-16 核

浮点实际实例是 `ct_vfdsu_srt_radix16_with_sqrt`，参数为 `DATA_WIDTH=56`、`REM_WIDTH=61`、`QT_WIDTH=58`（`gen_rtl/vfdsu/rtl/ct_vfdsu_srt_radix16_with_sqrt.v:275-277`）。它维护：

- 61-bit signed remainder；
- 56-bit divisor；
- 58-bit 正 quotient `total_qt_rt` 与负 quotient `total_qt_rt_minus`；
- 每轮右移 4 位的 digit weight。

初始化时 quotient 清零、weight 置为 `0001` 后跟 0；每轮 weight 右移 4 位，正负 quotient 根据选出的 digit 累积（同文件 `:377-412`、`:887-1030`）。当前 remainder 左移 4 位后，针对 digit 0..9 计算候选 remainder；bound compare 的 9 个结果按 `111111111`、`011111111` … `000000000` 映射到 0..9（`:501-509`、`:801-858`、`:1037-1064`）。负 remainder 时使用负 quotient 累积，最终 `vdiv_qt_rt` 根据 remainder sign 在正/负累积之间选择（`:408-410`）。

除法的候选操作数由 divisor 的 1/2/4/8 倍及组合项构成（`:698-768`）；sqrt 则使用当前 root/quotient 反馈形成候选项（`:584-696`）。两条候选路径由 `srt_sel_div`/`srt_sel_sqrt` 选择（`:772-799`）。

### 5.2 bound table

`ct_vfdsu_srt_radix16_bound_table` 输入 7-bit `bound_sel`，输出 9 个 12-bit boundaries（`gen_rtl/vfdsu/rtl/ct_vfdsu_srt_radix16_bound_table.v:17-46`）。普通除法表按 bound index 查 `ori_digit_bound_1..9`，表项从 `7'h40` 开始（`:102-130`，普通表结束于 `:962`）。sqrt 首轮使用固定边界 `2, 0x10, 0x35, 0x5f, 0xa0, 0xf0, 0x14f, 0x1c2, 0x23a`；第二轮依据 remainder sign 在 `p2/m2` 表之间选择（`:1126-1163`）。with_sqrt 版本在 sqrt 首轮使用固定表，在后续第二轮更新 `bound_sel` 为下一 quotient 的高位（`gen_rtl/vfdsu/rtl/ct_vfdsu_srt_radix16_with_sqrt.v:345-355`、`:420-439`）。

### 5.3 舍入

round 模块按照 quotient 最高有效位位置选择 double/single/half 的 guard/round/sticky 区间；文件注释明确 double 目标为 52+1 有效位、single 为 23+1 有效位（`gen_rtl/vfdsu/rtl/ct_vfdsu_round.v:279-290`）。它同时为指数在最小 normal 以下的 denormal 结果建立移位后的 round operand（`:361-530`、`:542-683`）。

正常数和非规格数分别计算 RNE/RTZ/RDN/RUP/RMM 的加一或减一条件（`:694-750`），再按 `vfdsu_ex3_rm` 选择 `frac_add_1`、`frac_sub_1`、原值以及 tiny-fraction 标志（`:752-820`）。最终 fraction 由 quotient、舍入加数和减数组合而成（`:868-889`）；NX 由正常结果的 quotient/remainder 非零或 denormal round 条件产生（`:891-898`）。

EX4 再根据 fraction 进位调整 exponent，并把 fraction/flags 锁存到 EX4（`:907-1013`）。

## 6. pack 与异常输出

pack 在 EX4 形成 normal、denormal、zero、qNaN、Inf、largest finite number 六类候选结果：

- normal：使用调整后的 exponent 和规格化 fraction（`gen_rtl/vfdsu/rtl/ct_vfdsu_pack.v:329-362`）；
- denormal：按 exponent shift fraction；half/single 结果在 64-bit 总线上以高位全 1 的形式承载（`:159-291`）；
- qNaN/Inf/LFN/zero：各自有 double、single、half 的构造（`:295-328`）；
- denormal 舍入进位为 normal，以及 overflow 的 Inf/LFN 选择分别由 `ex4_denorm_potnt_norm` 和 `ex4_of_plus` 处理（`:280-314`）。

异常输出打包为 `{NV,DZ,OF,UF,NX}`（`gen_rtl/vfdsu/rtl/ct_vfdsu_pack.v:364-376`）。结果选择优先由 denormal、qNaN、Inf、LFN、zero、normal 条件决定（`:378-410`）。`ct_vfdsu_scalar_dp` 将该 5-bit 异常直接接到 `pipex_dp_vfdsu_ereg_data`，64-bit 结果接到 `pipex_dp_vfdsu_freg_data`（`gen_rtl/vfdsu/rtl/ct_vfdsu_scalar_dp.v:310-313`）。

## 7. 与 VFPU/VFALU/VFMAU/IDU/RTU 的真实互联

### VFPU 顶层

`ct_vfpu_top` 在 pipe6 实例化 `ct_vfdsu_top`，完整连接源操作数、目的寄存器、IDU function/gateclk、结果元数据、flush、busy/WB 和全局 rm/dqnan（`gen_rtl/vfpu/rtl/ct_vfpu_top.v:1673-1705`）。同一顶层还分别实例化 pipe6/pipe7 的 VFALU（`:1633-1670`）和 VFMAU（`:1708-1774`）；这些实例之间没有 VFDSU 专用内部数据端口。

### IDU 与 VFPU DP

VFPU DP 将 IDU 的 pipe6 控制、destination、immediate、RF 源操作数拆成 VFDSU 专用端口；选择来自 `ctrl_ex1_pipe6_eu_sel[3]`，issue 来自 `idu_vfpu_is_vdiv_*`（`gen_rtl/vfpu/rtl/ct_vfpu_dp.v:1400-1408`）。源寄存器数据先锁存到 VFPU DP 的 `dp_ex1_pipe6_vfpu_srcf0/srcf1`，再同时送 VFALU 和 VFDSU（`:2098-2109`）。

VFDSU 结果返回后，DP 把 `pipe6_dp_vfdsu_inst_vld` 作为 FDSU result-valid；它驱动 EX2 执行单元选择、目的 vreg/ereg 和 ready-stage，且覆盖普通 EX1 指令的对应字段（`gen_rtl/vfpu/rtl/ct_vfpu_dp.v:1024-1049`）。随后 DP 在 EX2 锁存 FDSU freg/ereg result（`:1117-1136`）。

### VFALU/VFMAU

VFALU/VFMAU 与 VFDSU 共享 `idu_vfpu_rf_pipe6_func`、`idu_vfpu_rf_pipe6_gateclk_sel` 等 RF/译码上下文以及 `vfpu_yy_xx_rm/dqnan`，但各自接收 `dp_vfalu_*` 或 `dp_vfmau_*` 专用端口（`gen_rtl/vfpu/rtl/ct_vfpu_top.v:1633-1670`、`:1710-1774`）。VFDSU 不读取 VFALU/VFMAU 的中间结果；VFPU DP 统一负责执行单元选择和结果回收。

### RTU 与 IFU debug

`rtu_yy_xx_flush` 从 VFPU 顶层传入 VFDSU，清除除法状态机和各级流水 valid（`gen_rtl/vfpu/rtl/ct_vfpu_top.v:1697-1704`；`gen_rtl/vfdsu/rtl/ct_vfdsu_ctrl.v:184-191`、`:394-401`）。VFDSU 的 writeback request/busy 回到 VFPU DP，并进一步形成 `vfpu_idu_vdiv_wb_stall` 与 `vfpu_idu_vdiv_busy`：前者包含 `vfdsu_dp_inst_wb_req`，后者包含 `vfdsu_dp_fdiv_busy`（`gen_rtl/vfpu/rtl/ct_vfpu_dp.v:1446-1447`）。

IFU debug 三个输出在 VFDSU 控制器内当前是：`ex2_wait=0`、`pipe_busy=0`、`idle=(div_cur_state==IDLE)`（`gen_rtl/vfdsu/rtl/ct_vfdsu_ctrl.v:511-514`）；IFU debug 模块仅把它们转成 `vfdsu_pipe_busy/vfdsu_ex2_wait/vfdsu_idle`（`gen_rtl/ifu/rtl/ct_ifu_debug.v:314-318`）。

## 8. 时钟与配置

SRT state、除法状态机、EX1/EX2/EX3 数据和 pipe valid 都使用 gated clock；门控由 `cp0_yy_clk_en`、`cp0_vfpu_icg_en`、局部 enable 和 scan enable 组合（例如 `gen_rtl/vfdsu/rtl/ct_vfdsu_ctrl.v:160-181`、`:285-306`、`:372-392`、`:446-504`）。SRT core 自身把 `initial_srt_en || srt_sm_on` 用于 remainder/quotient 时钟，把 `initial_srt_en` 用于 divisor 时钟（`gen_rtl/vfdsu/rtl/ct_vfdsu_srt_radix16_with_sqrt.v:281-313`）。

## 9. 不能从当前 RTL 确认的点

1. `ct_vfdsu_top.v` 中被注释的 `ct_vfdsu_half/single` 多实例是否来自另一版本生成模板、是否曾用于 SIMD 多 lane，当前 RTL 不能确认；这里只能确认它们未参与当前 elaboration（`gen_rtl/vfdsu/rtl/ct_vfdsu_top.v:137-224`）。
2. `ct_vfdsu_ctrl.v` 的旧注释把 double/single 迭代计数写成 28/14，但实际赋值是 13/6/3；本文以实际赋值为准，确切 latency 仍需结合仿真波形确认（`gen_rtl/vfdsu/rtl/ct_vfdsu_ctrl.v:243-248`）。
3. `vfdsu_dp_fdiv_busy` 只由 `div_cur_state[2]` 解码，代码没有提供“从 RF issue 开始全程 busy”的独立语义；若上层需要该语义，应以 `vfpu_idu_vdiv_busy` 和状态机波形为准（`gen_rtl/vfdsu/rtl/ct_vfdsu_ctrl.v:506-514`、`gen_rtl/vfpu/rtl/ct_vfpu_dp.v:1446-1447`）。
4. `ct_vfdsu_srt_radix16_only_div` 的 borrow-flop 接口、`last_sel_bit` 由整数除法路径定义，不是 VFDSU 浮点路径的接口；本文件只说明其复用关系，不把它的整数 latency 套用到浮点 VFDSU（`gen_rtl/iu/rtl/ct_iu_div_srt_radix16.v:155-200`）。
