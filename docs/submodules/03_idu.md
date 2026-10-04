# IDU（`gen_rtl/idu/rtl`）模块说明

## 1. 范围与结论

本文档基于当前仓库 `gen_rtl/idu/rtl` 下全部 Verilog 文件的 RTL 结构、端口和时序逻辑整理。证据路径均使用仓库相对路径和源码行号；行号以当前快照为准。

IDU 不是一个单纯的“译码器”，而是从 IFU 指令缓冲区取指，完成三路 ID、指令展开/拆分、四路 IR/重命名依赖跟踪、IS 分发，并把指令放入七类发射队列，最后由 RF 选择八条执行管线（pipe0/1/2/3/4/5/6/7）的发射数据。其主要特征如下：

- ID 输入最多同时观察三条 IFU 指令；IR/IS/ROB 分发数据最多保留四个顺序位置。
- `ct_idu_id_decd`、`ct_idu_id_split_short`、`ct_idu_id_split_long` 和 `ct_idu_id_fence` 共同决定一条输入指令是否需要变成多条内部指令。长拆分最多产生 4 条，短拆分通常产生 1～2 条。
- IR 阶段同时维护整数 PREG、浮点 FREG、向量 VREG、异常/状态 EREG 的分配与依赖信息；RTU 返回物理寄存器分配结果，IR 只在分配结果可用时继续推进。
- IS 阶段按指令类型分派到 AIQ0、AIQ1、BIQ、LSIQ、SDIQ、VIQ0、VIQ1。队列内部使用 valid、age vector、ready、freeze 和 oldest-ready 选择，而不是固定 FIFO 发射。
- RF 阶段从队列读出一条已选指令，执行旁路优先于 PRF 读数据；若源操作数仍未就绪，则通过 `src_no_rdy`/`lch_fail` 反馈到队列，保留并重试该项。
- 当前快照中 `ct_idu_rf_prf_vregfile.v` 的向量数据读口被直接置零；向量/浮点相关可用数据主要由 `ct_idu_rf_fwd.v` 的 VFPU/LSU 旁路和 `ct_idu_rf_prf_fregfile.v` 的存储路径提供。这一点不能仅按文件名推断，见第 8 节。

## 2. 顶层层级

```text
ct_idu_top
├─ ID：ct_idu_id_ctrl / ct_idu_id_dp / ct_idu_id_fence
│  ├─ ct_idu_id_decd ×3
│  │  └─ ct_idu_id_decd_special
│  ├─ ct_idu_id_split_short ×3
│  └─ ct_idu_id_split_long
├─ IR：ct_idu_ir_ctrl / ct_idu_ir_dp / ct_idu_ir_rt
│  ├─ ct_idu_ir_decd
│  └─ ct_idu_dep_reg_src2_entry ×32
├─ 浮点/异常依赖：ct_idu_ir_frt
│  └─ ct_idu_dep_vreg_srcv2_entry ×33
├─ 向量依赖：ct_idu_ir_vrt
│  └─ 当前无有效子实例，输出在源码中为常量/占位路径
├─ IS：ct_idu_is_ctrl / ct_idu_is_dp
│  └─ ct_idu_is_pipe_entry（通用混合源操作数 entry）
├─ 发射队列
│  ├─ ct_idu_is_aiq0 → ct_idu_is_aiq0_entry ×8
│  ├─ ct_idu_is_aiq1 → ct_idu_is_aiq1_entry ×8
│  ├─ ct_idu_is_biq  → ct_idu_is_biq_entry ×12
│  ├─ ct_idu_is_lsiq → ct_idu_is_lsiq_entry ×12
│  ├─ ct_idu_is_sdiq → ct_idu_is_sdiq_entry ×12
│  ├─ ct_idu_is_viq0 → ct_idu_is_viq0_entry ×8
│  └─ ct_idu_is_viq1 → ct_idu_is_viq1_entry ×8
├─ RF：ct_idu_rf_ctrl / ct_idu_rf_dp / ct_idu_rf_fwd
│  ├─ ct_idu_rf_fwd_preg / ct_idu_rf_fwd_vreg
│  └─ pipe0/1/2/3/4/6/7_decd
└─ 物理寄存器文件
   ├─ ct_idu_rf_prf_pregfile → ct_idu_rf_prf_gated_preg ×96
   ├─ ct_idu_rf_prf_fregfile → ct_idu_rf_prf_gated_vreg ×64
   ├─ ct_idu_rf_prf_eregfile → ct_idu_rf_prf_gated_ereg ×32
   └─ ct_idu_rf_prf_vregfile → 当前为两个实例的零数据读口
```

顶层实例连接集中在 `gen_rtl/idu/rtl/ct_idu_top.v:3337-6568`；各阶段的 debug 编码在 `ct_idu_top.v:6589-6615`。

## 3. 文件与 module 作用索引

| 文件 | module | 作用 |
|---|---|---|
| `ct_idu_top.v` | `ct_idu_top` | IDU 顶层连接、跨目录端口、阶段实例、debug 状态。 |
| `ct_idu_id_ctrl.v` | `ct_idu_id_ctrl` | ID 有效位、三路选择、pipedown、stall、时钟门控。 |
| `ct_idu_id_dp.v` | `ct_idu_id_dp` | IFU 73-bit 指令字段寄存、三路译码、IR 178-bit 数据生成。 |
| `ct_idu_id_decd.v` | `ct_idu_id_decd` | RISC-V 标量/浮点/向量操作码、源/目的寄存器、异常和类型译码。 |
| `ct_idu_id_decd_special.v` | `ct_idu_id_decd_special` | fence、短拆分、长拆分特殊类型译码。 |
| `ct_idu_id_split_short.v` | `ct_idu_id_split_short` | JAL/JALR、FP 转换、LSI/LSD、向量多步/多源指令短拆分。 |
| `ct_idu_id_split_long.v` | `ct_idu_id_split_long` | LR/SC/AMO 等长拆分及最多四条内部指令的生成。 |
| `ct_idu_id_fence.v` | `ct_idu_id_fence` | fence/barrier/sync 的等待、发射、完成和 pop 状态机。 |
| `ct_idu_ir_ctrl.v` | `ct_idu_ir_ctrl` | IR valid/stall、动态负载均衡、RTU 分配请求、IQ/ROB/PST 分发控制。 |
| `ct_idu_ir_dp.v` | `ct_idu_ir_dp` | IR 字段展开、目的寄存器元数据和 271-bit IS 数据打包。 |
| `ct_idu_ir_decd.v` | `ct_idu_ir_decd` | IR 侧的执行类型/控制信息再译码。 |
| `ct_idu_ir_rt.v` | `ct_idu_ir_rt` | PREG 源依赖跟踪、源数据/ready/WB、同 bundle 依赖和 RTU 目的分配。 |
| `ct_idu_ir_frt.v` | `ct_idu_ir_frt` | FREG/EREG 源依赖、FREG 数据、同 bundle 匹配和分配跟踪。 |
| `ct_idu_ir_vrt.v` | `ct_idu_ir_vrt` | VREG 依赖接口；当前有效逻辑主要是常量输出，注释中保留了原拟用 entry。 |
| `ct_idu_dep_reg_entry.v` | `ct_idu_dep_reg_entry` | 单个标量 PREG 依赖项，维护 ready/WB/LSU match/旁路 ready。 |
| `ct_idu_dep_reg_src2_entry.v` | `ct_idu_dep_reg_src2_entry` | 带 MLA `src2` ready 的标量依赖项。 |
| `ct_idu_dep_vreg_entry.v` | `ct_idu_dep_vreg_entry` | 单个向量依赖项，接收 VFPU 和 LSU vector load 唤醒。 |
| `ct_idu_dep_vreg_srcv2_entry.v` | `ct_idu_dep_vreg_srcv2_entry` | 带 FMLA/VMLA/V-DSP `srcv2` ready 的向量/浮点依赖项。 |
| `ct_idu_is_ctrl.v` | `ct_idu_is_ctrl` | IS/dispatch valid、IQ/ROB/VMB full、create/pop/选择、分发 stall。 |
| `ct_idu_is_dp.v` | `ct_idu_is_dp` | IS 数据切片、各 IQ create data、依赖 lookahead、ROB/PST 数据。 |
| `ct_idu_is_pipe_entry.v` | `ct_idu_is_pipe_entry` | 通用混合源操作数 entry，供 `is_dp` 的管线化依赖接口使用。 |
| `ct_idu_is_aiq0.v` / `ct_idu_is_aiq0_entry.v` | `ct_idu_is_aiq0` / `ct_idu_is_aiq0_entry` | AIQ0（ALU 类）8 项队列及单项依赖/冻结/年龄逻辑。 |
| `ct_idu_is_aiq1.v` / `ct_idu_is_aiq1_entry.v` | `ct_idu_is_aiq1` / `ct_idu_is_aiq1_entry` | AIQ1（ALU/MLA 类）8 项队列及单项依赖/冻结/年龄逻辑。 |
| `ct_idu_is_biq.v` / `ct_idu_is_biq_entry.v` | `ct_idu_is_biq` / `ct_idu_is_biq_entry` | BJU 分支队列，12 项。 |
| `ct_idu_is_lsiq.v` / `ct_idu_is_lsiq_entry.v` | `ct_idu_is_lsiq` / `ct_idu_is_lsiq_entry` | LSU load/store 队列，12 项，包含 LQ/RB/SQ、barrier、speculation 和 unalign 控制。 |
| `ct_idu_is_sdiq.v` / `ct_idu_is_sdiq_entry.v` | `ct_idu_is_sdiq` / `ct_idu_is_sdiq_entry` | store-data 队列，12 项，维护 store 地址和数据就绪。 |
| `ct_idu_is_viq0.v` / `ct_idu_is_viq0_entry.v` | `ct_idu_is_viq0` / `ct_idu_is_viq0_entry` | VIQ0 向量执行队列，8 项。 |
| `ct_idu_is_viq1.v` / `ct_idu_is_viq1_entry.v` | `ct_idu_is_viq1` / `ct_idu_is_viq1_entry` | VIQ1 向量执行队列，8 项。 |
| `ct_idu_is_aiq_lch_rdy_1.v`, `ct_idu_is_aiq_lch_rdy_2.v`, `ct_idu_is_aiq_lch_rdy_3.v` | 同名 helper | AIQ lookahead ready 组合逻辑，无独立状态。 |
| `ct_idu_is_viq0/1` 使用的 `ct_idu_is_aiq_lch_rdy_1.v` | 同上 | VIQ 侧复用的发射前 ready lookahead。 |
| `ct_idu_rf_ctrl.v` | `ct_idu_rf_ctrl` | RF 时钟门控、各 pipe 发射 valid/pop、旁路向量切片、lch fail。 |
| `ct_idu_rf_dp.v` | `ct_idu_rf_dp` | IQ issue data 解包、源 PREG/VREG 读/旁路索引、各 pipe 输出数据。 |
| `ct_idu_rf_fwd.v` | `ct_idu_rf_fwd` | IU/LSU/VFPU ex/WB 旁路的统一优先选择。 |
| `ct_idu_rf_fwd_preg.v` | `ct_idu_rf_fwd_preg` | 单源标量物理寄存器旁路比较/选择。 |
| `ct_idu_rf_fwd_vreg.v` | `ct_idu_rf_fwd_vreg` | 单源向量/浮点物理寄存器旁路比较/选择。 |
| `ct_idu_rf_pipe0_decd.v`, `ct_idu_rf_pipe1_decd.v`, `ct_idu_rf_pipe2_decd.v`, `ct_idu_rf_pipe3_decd.v`, `ct_idu_rf_pipe4_decd.v`, `ct_idu_rf_pipe6_decd.v`, `ct_idu_rf_pipe7_decd.v` | 同名 pipe decoder | 把 issue record 转成 IU/LSU/VFPU/CP0 所需执行控制、立即数、功能字段。 |
| `ct_idu_rf_prf_pregfile.v` | `ct_idu_rf_prf_pregfile` | 96 项标量 PREG 阵列，多写口和各 pipe 读口。 |
| `ct_idu_rf_prf_fregfile.v` | `ct_idu_rf_prf_fregfile` | 64 项 FREG 存储，使用 `ct_idu_rf_prf_gated_vreg` 单元。 |
| `ct_idu_rf_prf_eregfile.v` | `ct_idu_rf_prf_eregfile` | 32 项 6-bit EREG 状态/累加信息。 |
| `ct_idu_rf_prf_vregfile.v` | `ct_idu_rf_prf_vregfile` | 当前快照只提供固定零值向量读口。 |
| `ct_idu_rf_prf_gated_preg.v` | `ct_idu_rf_prf_gated_preg` | 单个 64-bit PREG 的写数据优先级、门控时钟和寄存器。 |
| `ct_idu_rf_prf_gated_vreg.v` | `ct_idu_rf_prf_gated_vreg` | 单个 64-bit 向量/浮点存储单元。 |
| `ct_idu_rf_prf_gated_ereg.v` | `ct_idu_rf_prf_gated_ereg` | 单个 6-bit EREG 存储单元及 release/retired 处理。 |

## 4. ID：取指、译码、拆分和 fence

### 4.1 ID 控制

`ct_idu_id_ctrl` 把 IFU 的指令缓冲区输入和当前 ID 寄存器组合成三路候选指令。有效位寄存于带门控时钟的寄存器中，`cpurst_b` 低有效复位，`rtu_idu_flush_fe` 或 `iu_yy_xx_cancel` 清空；stall 时保持当前指令（`ct_idu_id_ctrl.v:268-315`）。

普通、fence、long split、short split 的分类在 `:400-414` 完成。`inst1/2/3` 的 pipedown 选择和 valid 对齐在 `:434-627`，后续指令会因前一条 fence/拆分状态而停止。ID stall 的核心条件是当前 `inst0` 有效且 IR stall 或不能完成三路 pipedown（`:641-674`）。

### 4.2 译码数据

`ct_idu_id_dp` 明确使用 IFU 73-bit 输入和 IR 178-bit 输出；opcode 为 `[31:0]`，并携带标量/浮点/向量源目的寄存器、valid、指令类型、split/intmask/exception 等字段（`ct_idu_id_dp.v:421-529`）。三条指令分别实例化 `ct_idu_id_decd`（`:750,804,858`）。

`ct_idu_id_decd` 的实现不是按 module 名称猜测：

- `:400-451` 根据压缩/非压缩长度、move/fmove/MLA/FMLA/VMLA 和源操作数有效性生成基础属性。
- `:476-544` 提取源/目的寄存器；`:579-741` 处理 FP、LSU 和 illegal 条件。
- `:759-851` 形成 ALU/BJU/MULT/DIV/LSU/PIPE/SPECIAL 等类型；`:2839` 以后进入向量宽度、widen/narrow、operand kind、overlap、VLSU/CSR 状态检查。

`ct_idu_id_decd_special` 在 `:73-218` 具体区分 short split、long split、fence，而不是由上层仅凭 opcode 名称判断。

### 4.3 拆分

`ct_idu_id_split_short` 的主要分支在 `:296-880`：JAL/JALR、LSI、LSD、FP 转换和向量多步变换。它把拆分后的目的寄存器、`SPLIT_LAST`、no-spec、VL/VSEW/VLMUL、PC 等重新打包（`:918-950`），并在 `:1206-1220` 选择 inst0/inst1 输出。

`ct_idu_id_split_long` 内含 AMO 状态机：`AMO_IDLE/AMO_SPLIT`、flush 恢复和时钟门控在 `:1086-1209`；LR/SC/AMO 类型判断在 `:1121-1158`；aq+rl 等条件决定是否超过四条内部指令。输出的顺序依赖、IID_PLUS 和多条合成指令在该模块内部建立。

`ct_idu_id_fence` 是独立的等待状态机，状态为 `IDLE → WAIT_ISSUE → ISSUE → WAIT_CMPLT → POP_INST`（`ct_idu_id_fence.v:227-318`）。它把 CP0/barrier/fence/sync 控制信息打包，输出 `fence_ctrl_id_stall`、最多三路 valid 和 `idu_rtu_fence_idle`（`:321-531`）。

## 5. IR：重命名分配与依赖检查

### 5.1 IR 控制和分发

IR 控制类型共 13 位，位定义见 `ct_idu_ir_ctrl.v:851-866`：ALU、MULT、DIV、BJU、LSU、SPLIT、INTMASK、STADDR、SPECIAL、PIPE67、PIPE6、PIPE7、VMB。IR valid 寄存器在 `:1297-` 附近受时钟门控，flush 清空，`ctrl_ir_stall` 时保持。

IR 到 IS 的 pipedown 由 `ctrl_ir_pipedown_stall`、`ctrl_xx_is_inst0_sel` 和 `ctrl_xx_is_inst_sel` 控制（`:953-999`）。IR 侧的分配 stall 包括：

- RTU 的 PREG/VREG/FREG/EREG 分配 valid 未满足；
- ROB/IS/VMB 或目标 IQ 满；
- `rtu_idu_flush_stall`、`iu_idu_mispred_stall`；
- IQ 类型对齐要求造成的 `pre_dis_type_stall`。

这些条件在 `ct_idu_ir_ctrl.v:1040-1136` 组合成阶段 stall，并生成 PREG/VREG/FREG/EREG 分配请求。目标寄存器为 x0 时不申请 PREG。

IR 还做动态负载均衡：比较 AIQ0/AIQ1 和 VIQ0/VIQ1 的计数差，差距达到阈值时把部分 ALU 或 VIQ01 指令重新分类；复位、FE/IS/RTU flush 和 CP0 disable 会关闭该逻辑。该路径位于 `ct_idu_ir_ctrl.v:1500-` 附近，不是静态的“按 opcode 永远固定分队列”。

### 5.2 IR/IS 数据宽度

`ct_idu_ir_dp` 定义 IR 178-bit 字段及 IS 271-bit 数据，包含源寄存器索引、ready/WB/LSU match、目标物理寄存器、控制类型、立即数、向量配置、ROB/PST 所需元数据（`ct_idu_ir_dp.v:1089-1292`）。目的分配结果来自 RTU，字段展开和 IS 数据打包在 `:1348-1508`、`:1530-`。

### 5.3 PREG 依赖

`ct_idu_ir_rt` 为 inst0～3 生成 src0/src1/src2 数据、rel_preg 和匹配向量（`ct_idu_ir_rt.v:197-218`）。

- PREG 依赖 mask 的定义在 `:725-743`。
- PREG0 使用固定数据，PREG1～32 通过 `ct_idu_dep_reg_src2_entry` 实例化（`:835-2267`），因此 MLA src2 有独立 ready 状态。
- 每个依赖项的 create/read 数据格式、ALU/乘法器/除法器/LSU/VFPU 唤醒和 issue-ready 计算在 `ct_idu_dep_reg_entry.v:227-369` 与 `ct_idu_dep_reg_src2_entry.v:239-350`。
- 同 bundle 内年轻指令对前面目的寄存器的匹配在 `ct_idu_ir_rt.v:3719-4068` 一带生成，避免把同一 bundle 的 RAW 依赖误判为已就绪。

普通依赖项的 create 数据是 `{lsu_match,preg,wb,rdy}`；read 数据额外带 `rdy_for_bypass` 和 `rdy_for_issue`。issue-ready 可以接受当前周期 ALU/LSU forward，但 bypass-ready 保留真实已写回状态。带 src2 的 entry 还增加 `mla_rdy` 和 MLA issue data ready。

### 5.4 FREG/EREG/VREG 依赖

`ct_idu_ir_frt` 的输出是 FREG/EREG 数据、rel 编号及同 bundle 匹配（`ct_idu_ir_frt.v:243-268`）。它从 `ct_idu_dep_vreg_srcv2_entry` 建立 33 个状态项（`:827-843,887-2615`），状态既覆盖 FREG，也携带 EREG/MLA 类 ready。FMLA、VMLA、V-DSP、VFPU ex1/ex2/ex3 和 LSU vector load 的唤醒路径见 `ct_idu_dep_vreg_srcv2_entry.v:263-438`。

`ct_idu_ir_vrt` 的接口仍有 VREG source match/data 端口，但源码中原拟实例化的依赖 entry 被注释，实际输出在 `ct_idu_ir_vrt.v:487-512` 为固定 match=0、固定 ready/WB 模式和 rel_vreg=0。因此该快照的向量依赖不能写成“IR VRT 已完整维护 VREG 表”；后续有效依赖更多在 IS entry 和 VFPU/LSU 唤醒路径中完成。

## 6. IS 分发与七类发射队列

### 6.1 分发握手

`ct_idu_is_ctrl` 在 `ct_idu_is_ctrl.v:927-984` 保存 IS valid，在 `:1004-1518` 保存各 IQ create enable、create data 选择、ROB/PST、VMB 和 pipedown 控制。若 `is_dis_pipedown2`，控制逻辑会根据 inst3/IR inst2/3 valid 重新对齐 inst0/1（`:1206-1231`）。

IQ 的 full 结果和 ROB/VMB full 在 `:1571-1763` 汇总为 `ctrl_is_dis_stall`/`ctrl_is_stall`。所以“发不进去”可能是 ROB、任一 IQ、VMB 或类型对齐 stall，而不仅是目标队列计数到满。

`ct_idu_is_dp` 将 IS 数据按队列打包，核心宽度为：AIQ0 227、AIQ1 214、BIQ 82、LSIQ 163、SDIQ 27、VIQ0 151、VIQ1 150（`ct_idu_is_dp.v:1750-2037`）。队列 create entry、依赖展开和 lookahead ready 在 `:2944-3372`、`:3379-`；source no-ready 还会生成 RF 读侧的 ready clear（`:2070-2283`）。

### 6.2 队列行为

| 队列 | 项数/宽度 | 主要入口和发射对象 | 特殊依赖/阻塞 |
|---|---:|---|---|
| AIQ0 | 8 / 227 bit | ALU 类，RF pipe0 | PREG ready、ALU0/ALU1 forward；空队列可 create-bypass；full 在 `cnt==8`。 |
| AIQ1 | 8 / 214 bit | ALU/MLA 类，RF pipe1 | PREG/MLA src2 ready，ALU 和 MLA forward；full 在 `cnt==8`。 |
| BIQ | 12 / 82 bit | 分支，RF pipe2 | PREG 分支源依赖、年龄选择；full 在 `cnt==12`。 |
| LSIQ | 12 / 163 bit | load/store 地址/控制，RF pipe3/4/5 与 LSU | LQ/RB/SQ full、barrier、no-spec、RAW、TLB busy、unaligned、freeze。 |
| SDIQ | 12 / 27 bit | store data/address 辅助，LSU store-data 路径 | PREG/FREG/VREG 展开，store address ready、STQ create。 |
| VIQ0 | 8 / 151 bit | 向量执行，RF pipe6 | VREG/FREG ready、VMLA srcv2 forward；full 在 `cnt==8`。 |
| VIQ1 | 8 / 150 bit | 向量执行，RF pipe7 | VREG/FREG ready、VMLA srcv2 forward；full 在 `cnt==8`。 |

AIQ0 的计数/full、空队列 bypass、8 个 entry 实例、ready/age/issue 和 lch-fail 路径见 `ct_idu_is_aiq0.v:542-626,677-1154,1235-2012`；AIQ1 对应 `ct_idu_is_aiq1.v:553-637,666-1176,1257-2041`。AIQ1 比 AIQ0 多 MLA forward/ready 输入。

BIQ 明确声明 entry0～entry11，计数和 `cnt==12` full 条件在 `ct_idu_is_biq.v:145-179,445-542`；valid、空槽寻找、create 和 age/ready 选择在 `:563-749` 以后。

LSIQ 是 LSU 约束最重的队列。其 12 个 entry 连接了 `lsu_idu_lq_not_full`、`rb_not_full`、`sq_not_full`，并把 barrier、load/store、speculation、TLB、unaligned、freeze 和 pop 传给 `ct_idu_is_lsiq_entry`；代表性 entry11 连接在 `ct_idu_is_lsiq.v:3999-4107`。因此 LSIQ 的 ready 不能只由源寄存器 ready 决定。

SDIQ 的 12 个 entry、27-bit issue data、`cnt==12` full 和 oldest-ready 选择分别可见于 `ct_idu_is_sdiq.v:211-234,612,639-678,721-850,1216-1349`。LSU 在 ex1 给出 entry pop（`:1357-1390`），RF launch fail 清 freeze/ready（`:1393-1408`），pipe4 的 store-address 发射设置 `staddr_rdy`，LSU DC 的 `staddr_stq_create` 在 `:1429-1450` 产生。

VIQ0/VIQ1 结构分别见 `ct_idu_is_viq0.v:468-525,584-1077,1168-1770` 和 `ct_idu_is_viq1.v:462-519,578-1068,1159-1754`。两者均为 8 项，使用 age vector 找最老 ready 项，并分别接收 VMLA forward 控制。

所有队列共用相似的 entry 机制：

1. `create_en` 写入空槽，`create_dp_en` 写入数据，`create_gateclk_en` 控制时钟门控。
2. 每个 entry 保存 valid、age vector、源 ready、freeze 和队列特有状态。
3. ready 向量先排除 invalid/freeze，再排除更老的 ready entry，得到 oldest-ready issue enable。
4. `dp_issue_read_data` 根据 issue entry 向量选择并输出给 RF/LSU；`xx_issue_en` 是队列级有效。
5. RF 的 `lch_fail` 和 LSU 的 pop/ready-set 会清除 freeze 或源 ready，促使 entry 重新尝试，不是简单地丢弃该项。

## 7. RF 发射、读数和旁路

### 7.1 RF 控制握手

`ct_idu_rf_ctrl` 对 AIQ0、AIQ1、BIQ/LSIQ/SDIQ、VIQ0、VIQ1 分别形成门控时钟和发射 valid；相关时钟使能在 `ct_idu_rf_ctrl.v:719-811`，issue valid 寄存器在 `:844-1000`。

队列发射到 RF 后，`rf_pipe0/1/2/6/7_pipedown_vld` 形成对应 queue pop；pipe3/4/5 由 LSU/LSIQ/SDIQ 的专用路径参与。RF 通过 `src_no_rdy` 形成各 pipe 的 `lch_fail`，并把 fail valid 返回对应 entry；同一模块还把 pipe0/1 的 ALU forward 和 pipe6/7 的向量/VMLA forward 切片给各队列（`:1028-`、`:1280-1455`）。

发射对象和执行选择由以下控制字段送出：pipe0 的 ALU/CP0/special/div、pipe1 的 ALU/mult、pipe2 的 BJU、pipe3/4/5 的 LSU、pipe6/7 的 VFPU（`ct_idu_rf_ctrl.v:1402-1465`）。

### 7.2 RF 数据路径

`ct_idu_rf_dp` 按上述队列宽度解包 issue data，在 `ct_idu_rf_dp.v:2070-2179` 形成源 PREG/FREG/VREG 索引和 forward 索引，并在 `:2283-2290` 等位置生成 `src_no_rdy`/ready clear。随后调用 pipe-specific decoder：

- pipe0/1：IU ALU、乘法、特殊/CP0 所需的 opcode、func、立即数、源/目的 PREG 和向量配置；
- pipe2：BJU 条件、目标、分支立即数和预测相关字段；
- pipe3/4/5：LSU 地址、store data、load/store 属性、异常和队列索引；
- pipe6/7：VFPU func、向量寄存器/配置、FMA/VMLA 相关控制。

pipe0 输出到 IU/CP0 的字段连接集中在 `ct_idu_rf_dp.v:2201-2324`；pipe1 及其余 pipe 的同类解包在后续区域。各 `ct_idu_rf_pipe*_decd.v` 是这些执行侧格式的局部译码器，不是新的队列。

### 7.3 旁路优先级

`ct_idu_rf_fwd` 收集：

- IU pipe0/1 的 ex1、ex2、WB PREG id/data/valid；
- LSU pipe3 的 DA/WB PREG/VREG id/data/valid；
- VFPU pipe6/7 的 ex3/ex4/ex5 VREG/FREG id/data/valid；
- CP0 的 `src2_fwd_disable`、`srcv2_fwd_disable`，以及 IU/VFPU 的 MLA/VMLA src2 no-forward。

该接口和各类源在 `ct_idu_rf_fwd.v` 顶部端口与 `:843-1051,1500-,1916-` 等路径明确列出。`ct_idu_rf_fwd_preg.v` 和 `ct_idu_rf_fwd_vreg.v` 是组合比较/优先 mux：物理寄存器号匹配且 producer valid 时，选最近/优先级更高的执行结果；没有匹配时输出 no-forward。

因此一次 RF 读可以按以下顺序理解：

```text
issue queue 的 packed entry
        ↓
RF DP 解包并给出 PREG/FREG/VREG 索引
        ↓
RF FWD 比较当前周期 IU/LSU/VFPU 结果
        ├─ 命中：直接使用 forward data
        └─ 未命中：读取 PRF/FREG/EREG；仍未 ready 则 src_no_rdy
        ↓
RF CTRL 生成 pipe valid / queue pop / lch_fail
```

## 8. PRF、FREG、VREG、EREG

### 8.1 PREG

`ct_idu_rf_prf_pregfile` 实例化 96 个 `ct_idu_rf_prf_gated_preg`；单元为 64-bit，写 valid 来自多个执行/WB 源，写数据带优先级 mux，门控时钟只在写入时打开（`ct_idu_rf_prf_gated_preg.v:63-111`）。PREG 阵列的多写口映射和各 pipe read mux 在 `ct_idu_rf_prf_pregfile.v:1907-2315` 等 case 区域；debug WB 输出在 `:1792-1796`。

### 8.2 FREG/EREG

`ct_idu_rf_prf_fregfile` 实例化 64 个 `ct_idu_rf_prf_gated_vreg`，每项为 64-bit；写入来源包含 VFPU pipe6/7 和 LSU pipe3，映射和 read mux 在 `ct_idu_rf_prf_fregfile.v:271-1240,1315-`。这里的 gated vreg 单元代表 FREG 的物理数据存储，不应与下面的 VREG 文件混淆。

`ct_idu_rf_prf_eregfile` 实例化 32 个 6-bit `ct_idu_rf_prf_gated_ereg`（`:210-675`）。它接收 pipe6/7 的状态写入，另有 retired/released WB mask、FESR accumulator reduction（`:707-905`），用途是异常/向量状态类 EREG，而不是普通整数数据。

### 8.3 VREG 当前快照

`ct_idu_rf_prf_vregfile.v:279-287` 将 pipe5/6/7 的 srcv0/srcv1/srcv2/srcvm 读数据全部赋为 `64'b0`。顶层仍实例化两个副本（`ct_idu_top.v:6523-6555`），但从该文件本身看不是一个真正的 VREG 阵列读路径。文档因此把它标记为 stub/占位，而不把它描述成已实现的向量物理寄存器文件。

## 9. 跨目录连接

| 外部模块 | IDU 接收/发出内容 | 证据与用途 |
|---|---|---|
| IFU | IFU→ID 的 73-bit 指令/PC/valid、IB pipedown、flush/cancel；IDU→IFU 的 stall/取指控制 | `ct_idu_id_dp.v:421-552`、`ct_idu_id_ctrl.v:251-315`、顶层 IFU 端口连接。 |
| RTU | ROB create、PST iid/目的分配、PREG/VREG/FREG/EREG allocate valid/data、flush stall；RTU fence idle/flush | `ct_idu_ir_ctrl.v:1084-1136`、`ct_idu_is_ctrl.v:1239-1370`、`ct_idu_id_fence.v:321-339`。 |
| IU | pipe0/1/2 发射数据、源/目的 PREG、ALU/BJU/mult/div 控制；IU ex/WB 旁路回 IDU | `ct_idu_rf_dp.v:2201-2420`、`ct_idu_rf_fwd.v` 顶部端口。 |
| LSU | pipe3/4/5 issue 数据、LQ/RB/SQ full/not-full、LSU DA/WB 旁路、LSIQ/SDIQ entry pop、store-address ready | `ct_idu_is_lsiq.v` 端口区和 entry11 连接 `:3999-4107`；`ct_idu_is_sdiq.v:1357-1450`。 |
| VFPU | pipe6/7 issue 数据、VFPU ex/WB VREG/FREG/EREG 唤醒和旁路、VMLA/FMLA ready | `ct_idu_rf_fwd.v` VFPU 端口与 `ct_idu_dep_vreg_srcv2_entry.v:284-438`。 |
| CP0/HPCP/HAD | DLB disable、forward disable、fence/sync、HPCP valid、debug/性能状态 | `ct_idu_ir_ctrl.v` 的 DLB/分发控制、`ct_idu_id_fence.v:339-531`、`ct_idu_top.v:6589-6615`。 |

这些接口在顶层均通过 `ct_idu_top` 直接连到子模块；本文没有把 IFU/IU/LSU/VFPU/RTU 的 RTL 纳入修改范围。

## 10. 时钟、复位和 flush 传播

- 各阶段和队列都使用 `cpurst_b` 低有效复位；ID/IR/IS valid 寄存器在 FE flush 或 IU cancel 时清空，其他状态按模块语义保留或清除。
- ID/IR/IS/RF 和 entry 都有 gateclk enable。典型的 ID valid/clock gate 在 `ct_idu_id_ctrl.v:268-315`，IR 在 `ct_idu_ir_ctrl.v:1297-`，IS valid 在 `ct_idu_is_ctrl.v:927-984`，RF issue clocks 在 `ct_idu_rf_ctrl.v:719-811`。
- RF/依赖表另有同步 reset recovery，用于避免 flush 与依赖 entry 更新同周期产生错误状态：PREG 在 `ct_idu_ir_rt.v:2430-2481`，FREG/EREG 在 `ct_idu_ir_frt.v:2951-3007`。
- 队列计数随 create/pop 更新；full 通常以 8 或 12 项比较，另外有 full-update/one-left 预警，用于在下一周期提前阻止 IS 分发。
- `freeze` 是发射失败后的 entry 状态，不等同于 valid 清除。RF `lch_fail`、LSU pop、store-address ready、TLB/unaligned 等事件分别清除或推进对应 freeze/ready 子状态。

## 11. 关键控制通道摘要

| 通道 | 生产者 | 消费者 | 含义 |
|---|---|---|---|
| `ctrl_ir_stall` / `ctrl_is_stall` | IR/IS 控制 | ID/IR pipedown | 依赖分配、ROB/IQ/VMB full 或类型对齐导致的阶段停止。 |
| `*_create_en`, `*_create_dp_en`, `*_create_gateclk_en` | IS ctrl/dp | 各 IQ | 分别控制 entry 有效写入、数据写入和门控时钟。 |
| `*_agevec`, `*_rdy`, `*_issue_en` | 各 IQ entry | IQ arbiter/RF | 形成 oldest-ready 发射选择。 |
| `*_dp_issue_read_data` | IQ | RF DP/LSU | 被选 entry 的 packed 发射记录。 |
| `rf_pipe*_inst_vld` / `*_rf_pop_vld` | RF ctrl | 执行 pipe/queue | 一次发射和对应队列 pop 的握手。 |
| `src_no_rdy`, `rdy_clr` | RF DP | IQ entry/依赖项 | 源操作数尚未可用或需清除 optimistic ready。 |
| `*_rf_lch_fail_vld` / `frz_clr` | RF ctrl | IQ entry | launch 失败后的冻结清除与重试。 |
| `*_alu_reg_fwd_vld`, `*_vmla_reg_fwd_vld` | RF ctrl/FWD | IQ ready | 当前周期结果可直接使队列源 ready。 |
| `staddr_rdy_set`, `staddr_stq_create` | RF/LSU | SDIQ entry | store 地址执行和 STQ 创建的两阶段同步。 |
| `lsu_idu_*_not_full`, `*_pop_entry` | LSU | LSIQ/SDIQ | load/store buffer 资源和已执行 entry 回收。 |

## 12. 结论与注意事项

1. `ct_idu_top` 的真实数据流是“IFU 三路输入 → ID 译码/拆分 → IR 四路依赖/重命名 → IS 七类队列 → RF 八条 pipe”，中间每一级都有独立 valid/stall/flush；不能把它简化为单级 decode。
2. 依赖 ready 分成 issue-ready、bypass-ready、WB/真实 ready，且 scalar MLA、FMLA/VMLA、LSU load、store address 都有额外状态。只看寄存器号不能判断能否发射。
3. 队列既受寄存器依赖也受执行资源状态约束：LSIQ 还受 LQ/RB/SQ/barrier/speculation/TLB/unaligned 影响，SDIQ 还要等待 store 地址/数据阶段。
4. 当前源码中的 `ct_idu_ir_vrt` 和 `ct_idu_rf_prf_vregfile` 是两个必须注明的实现状态：前者为向量依赖接口占位，后者的读数据直接为零。相关文档或验证结论不能假设 VREG PRF 已像 PREG/FREG 一样完整实现。
