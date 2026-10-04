# common/rtl 通用模块

本文档覆盖 `gen_rtl/common/rtl` 目录中的 7 个 RTL module。结论以 RTL 实际实现和工程中的真实实例化为准；仅出现在 `// &Depend`、`// &Instance` 等生成器注释中的引用不计为实例。

## 1. 文件与 module 总览

| 文件 | module | 参数/默认值 | 主要用途 | 真实直接调用者 |
|---|---|---|---|---|
| `compressor_32.v` | `compressor_32` | `B_SIZE=8` | 位并行 3:2 carry-save compressor | `multiplier_65x65_3_stage`、`ct_vfmau_mult_compressor` |
| `compressor_42.v` | `compressor_42` | `B_SIZE=8` | 带 `cin/cout` 链的 4:2 carry-save compressor | `multiplier_65x65_3_stage`、`ct_vfmau_mult_compressor` |
| `booth_code.v` | `booth_code` | `B_SIZE=53` | 带被乘数符号扩展的 radix-4 Booth 部分积编码 | `multiplier_65x65_3_stage`（被 `ct_iu_mult` 间接使用） |
| `booth_code_v1.v` | `booth_code_v1` | `B_SIZE=53` | 面向非负尾数的 Booth 部分积编码 | `ct_vfmau_mult_compressor` |
| `sync_level2level.v` | `sync_level2level` | `SIGNAL_WIDTH=1`、`FLOP_NUM=3` | 多级触发器 level synchronizer | `plic_kid_busif`；也被 `sync_level2pulse` 内部调用 |
| `sync_level2pulse.v` | `sync_level2pulse` | 无 | 将同步后的保持电平变为单周期上升沿脉冲，并输出同步 level | `ct_had_private_ir`（IR/DR 各 1 个） |
| `BUFGCE.v` | `BUFGCE` | 无 | 行为级无毛刺时钟门控模型 | `ct_clk_top`、`ct_mp_clk_top` |

## 2. 调用关系

```text
ct_iu_mult
└─ multiplier_65x65_3_stage
   ├─ 33 × booth_code
   ├─ compressor_42（L1/L3/L5）
   └─ compressor_32（L2/L4/L6）

ct_vfmau_mult_compressor
├─ 27 × booth_code_v1
├─ compressor_42（L1/L2/L3/L5）
└─ compressor_32（L1/L2/L4）

plic_kid_busif ── sync_level2level（SIGNAL_WIDTH=INT_NUM，默认 INT_NUM=1024）

ct_had_private_ir
├─ sync_level2pulse（IR） ── sync_level2level（默认 3 级）
└─ sync_level2pulse（DR） ── sync_level2level（默认 3 级）

ct_clk_top ── BUFGCE ×1
ct_mp_clk_top ── BUFGCE ×5
```

证据：`ct_iu_mult` 将 `multiplier_65x65_3_stage` 接到 EX1/EX2/EX3 数据路径（`gen_rtl/iu/rtl/ct_iu_mult.v:617-629`）；乘法器内部直接实例化 Booth 和压缩器（`gen_rtl/iu/rtl/multiplier_65x65_3_stage.v:61-93,172-243,288-293,385-410,431-457,494-499`）。VFM AU 乘法压缩器的 27 个 `booth_code_v1` 实例位于 `gen_rtl/vfmau/rtl/ct_vfmau_mult_compressor.v:319-504`，各级压缩器位于 `:726-797,836-859,881-906,970-1000`。PLIC、HAD 和时钟实例分别见 `gen_rtl/plic/rtl/plic_kid_busif.v:176-181`、`gen_rtl/had/rtl/ct_had_private_ir.v:173-198`、`gen_rtl/clk/rtl/ct_clk_top.v:72-76` 与 `gen_rtl/clk/rtl/ct_mp_clk_top.v:162-166,241-251,306-316`。

## 3. 压缩器

### 3.1 `compressor_32`

文件：`gen_rtl/common/rtl/compressor_32.v:16-41`

接口均为 `B_SIZE` 位，默认 `B_SIZE=8`：

```text
a, b, c : input  [B_SIZE-1:0]
s, ca   : output [B_SIZE-1:0]
```

对每一位独立计算：

```text
s  = a ^ b ^ c
ca = (a & b) | (b & c) | (a & c)
```

因此每一位满足 `a[i]+b[i]+c[i] = s[i] + 2*ca[i]`。`ca` 本身没有左移，调用者在将它作为下一层部分积相加时负责按位权左移；例如乘法器在构造下一层输入时用 `{c0_0[72:0],1'b0}`（`multiplier_65x65_3_stage.v:257-259`）。

这是纯组合、无时钟、无复位、无进位传播的 carry-save 单元。`B_SIZE` 只决定向量宽度，RTL 没有参数合法性检查；工程中实际使用从 60 到 115 位的实例（VFM AU：`:780,836-839,970-980`；整数乘法器：`:288-293,431-432,494-499`）。

### 3.2 `compressor_42`

文件：`gen_rtl/common/rtl/compressor_42.v:16-46`

接口均为 `B_SIZE` 位，默认 `B_SIZE=8`：

```text
p0, p1, p2, p3, cin : input  [B_SIZE-1:0]
s, ca, cout         : output [B_SIZE-1:0]
```

实现先形成 `xor0=p0^p1`、`xor1=p2^p3`、`xor2=xor0^xor1`，随后逐位产生：

```text
s    = xor2 ^ cin
cout = (xor0 & p2) | (~xor0 & p0)
ca   = (xor2 & cin) | (~xor2 & p3)
```

它是 4:2 compressor 的 carry-save 实现：`s` 与 `ca` 是本级两条部分积，`cout` 则参与各位之间的 carry chain。也就是说，`cout` 不能丢弃或当作普通的“最终进位”处理；调用者将前一位的 `cout` 左移一位形成本级 `cin`，例如 `p*_cin = {cout*[B_SIZE-2:0],1'b0}`（`multiplier_65x65_3_stage.v:119,125,131,137,143,149,155,161`），VFM AU 末级也使用 `{cout4_0[104:0],1'b0}`（`ct_vfmau_mult_compressor.v:991`）。

该 module 也是纯组合逻辑。`B_SIZE` 必须覆盖所有连接的位段，且通常至少为 1；代码没有截断/扩展保护。工程实例宽度随压缩树变化：整数乘法器使用 73、75、84、91、93、130 位等（`multiplier_65x65_3_stage.v:172-243,385-410,450-457`），VFM AU 使用 16、22、60、62、64、80、82、106 位等（`ct_vfmau_mult_compressor.v:726-797,841-859,881-906,993-1000`）。

## 4. Booth 编码器

### 4.1 `booth_code`

文件：`gen_rtl/common/rtl/booth_code.v:23-93`

接口：`A[B_SIZE-1:0]`、`code[2:0]`，输出 `product[B_SIZE:0]`（比 `A` 多 1 位）、`h[1:0]` 和 `sn`。默认 `B_SIZE=53`；整数乘法器显式使用 `B_SIZE=65`，所以输出部分积为 66 位（`multiplier_65x65_3_stage.v:41-49,61-93`）。

它使用 radix-4 Booth 三比特窗口，代码对应关系为：

| `code` | 部分积含义 | `product` 编码 |
|---|---|---|
| `000`、`111` | 0 | 全 0 |
| `001`、`010` | `+A` | `{A_sign,A}` |
| `011` | `+2A` | `{A,1'b0}` |
| `100` | `-2A` | `{~A,1'b1}` |
| `101`、`110` | `-A` | `{~A_sign,~A}` |

`A_sign=A[B_SIZE-1]`（`:42-44`），所以正负部分积会按被乘数的符号扩展。`h` 仅在 `100/101/110` 时为 `2'b01`，其余为 `2'b00`（`:78-90`）；`sn` 是供上层部分积修正使用的标志，`001-011` 输出 `~A_sign`，`100-110` 输出 `A_sign`，零码输出 1（`:63-75`）。

表中的负数是 Booth 数学含义；`product` 对负码采用反码/补码形式，不能脱离 `h` 和 `sn` 的上层修正单独当作已经完成补码加一的整数值。

该编码器没有任何时序逻辑，三个 `always` 块均为组合译码。上层整数乘法器把同一个 65 位 `multiplicand_not` 送入 33 个窗口，窗口从 `{multiplier[1:0],1'b0}` 开始、每次右移 2 位，最后一个窗口为 `{multiplier[64],multiplier[64:63]}`（`multiplier_65x65_3_stage.v:57-93`）。乘法器随后用压缩树处理这些部分积，并在 `pipe1_clk/pipe2_clk` 处寄存（`:304-347,462-479`），因此寄存和流水延迟属于父模块，不属于 `booth_code`。

边界：`product` 和 `h` 对未知/非法 `code` 有显式 `default`，输出置 `X`；`sn` 的 case 没有 `default`（`:63-75`），故非法/未知码下不是受保护的确定组合值，不能把它当作安全的错误处理路径。

### 4.2 `booth_code_v1`

文件：`gen_rtl/common/rtl/booth_code_v1.v:20-84`

接口和默认位宽与 `booth_code` 相同：`A[B_SIZE-1:0]`、`code[2:0]`、`product[B_SIZE:0]`、`h[1:0]`、`sn`。它不是简单的文件重命名版本，核心差异是它**不读取 `A` 的符号位**：

- `001/010` 用 `{1'b0,A}` 产生正 `A`；
- `101/110` 用 `{1'b1,~A}` 产生补码形式的负 `A`；
- `011` 和 `100` 分别为 `+2A` 与 `-2A` 的同样位级编码；
- `sn` 对 `001-011` 固定为 1，对 `100-110` 固定为 0，零码为 1（`:56-66`）。

这里的 `product` 同样是供后续压缩树配合 `h/sn` 修正的 Booth 编码，不应单独解释为已经完成补码加一的数学负数。

VFM AU 先把浮点 fraction 组织成非负尾数：`multiplicand={2'b0,op0_frac}`、`multiplier={2'b0,op1_frac}`（`ct_vfmau_mult_compressor.v:303-310`），再以 `#(53)` 实例化 27 个 `booth_code_v1`（`:319-504`）。因此该版本适配的是非负的尾数乘法和后续压缩树，而不是通用有符号整数乘法。

它同样是纯组合逻辑。对未知/非法 `code`，`product` 和 `h` 有 `X` 默认分支（`:43-53,69-81`），但 `sn` 没有 `default`（`:56-66`）；调用者应保证 Booth 窗口有效。VFM AU 在 L3 与 L4 之间通过 `compresor_ex1_ex2_pipe_clk` 把压缩树中间结果寄存（`:914-950`），不是 Booth 编码器自身的时序。

## 5. 同步与事件转换

### 5.1 `sync_level2level`

文件：`gen_rtl/common/rtl/sync_level2level.v:16-66`

接口：

```text
clk, rst_b
sync_in [SIGNAL_WIDTH-1:0]
sync_out[SIGNAL_WIDTH-1:0]
```

参数 `SIGNAL_WIDTH=1`、`FLOP_NUM=3`。`sync_ff[0]` 在 `posedge clk` 采样输入，后续由 generate 产生 `FLOP_NUM-1` 个串联级，每一级都使用 `posedge clk or negedge rst_b`，输出直接取最后一级（`:31-63`）。复位为异步低有效，并把全部同步级清零（`:41-59`）。

这是真正的 level synchronizer，不会自动产生脉冲或握手。按默认参数，输入稳定变化后要经过 3 个采样沿才到达 `sync_out`；代码和数组索引也说明实际默认是 3 级，尽管 PLIC 周边注释写着 “2-stage flop”（`plic_kid_busif.v:172-193`）。PLIC 实例把 `SIGNAL_WIDTH` 设为 `INT_NUM`，其 module 默认 `INT_NUM=1024`（`plic_kid_busif.v:57,176-181`）。

边界：`FLOP_NUM=1` 时仍可工作（只保留 `sync_ff[0]`）；`FLOP_NUM=0` 会使数组和 `sync_ff[FLOP_NUM-1]` 非法，RTL 没有保护。`SIGNAL_WIDTH` 应为正数。异步复位释放后的同步时序由外部复位策略负责。

### 5.2 `sync_level2pulse`

文件：`gen_rtl/common/rtl/sync_level2pulse.v:16-59`

接口全为 1 位：`clk`、异步低有效 `rst_b`、输入 level `sync_in`，以及 `sync_out` 和 `sync_ack`。内部实例化默认 3 级 `sync_level2level` 得到 `sync_out_level`（`:39-46`），再用一个时钟寄存器保存上一拍同步 level（`:48-54`）：

```text
sync_out = sync_out_level & ~sync_ff
sync_ack = sync_out_level
```

所以 `sync_out` 是同步 level 的上升沿单周期脉冲；`sync_ack` 不是单周期应答，而是已经同步后的保持电平。输入若是短于同步延迟的窄脉冲，可能在同步器中完全消失；输入保持为高时不会重复产生脉冲。复位会把内部历史值清零，因而不会在复位释放时凭空产生脉冲。

真实调用者是 `ct_had_private_ir` 中的 IR/DR 两个更新通道：`sm_update_ir/dr` 进入 `sync_in`，`x_update_ir/dr_cpu_raw` 接收脉冲，`x_update_ir/dr_cpu_ack` 接收同步 level（`gen_rtl/had/rtl/ct_had_private_ir.v:173-207`）。

## 6. 时钟门控模型 `BUFGCE`

文件：`gen_rtl/common/rtl/BUFGCE.v:17-41`

接口无参数，`I`、`CE`、`O` 均为 1 位。实现使用一个在 `I=0` 时透明的 latch 保存 `CE`（`:27-32`），再把 latch 值送入 `clk_en`，最终：

```text
O = I && clk_en
```

因此 `CE` 在输入时钟低电平期间才会被采样，输入时钟高电平期间改变 `CE` 不会直接截断当前高脉冲，意图是行为级模拟无毛刺的时钟门控。它没有时钟、复位或初始化；仿真开始时若 `I` 尚未经历低电平采样，`clk_en`/`O` 可能为 `X`。这也是模型的边界，不应把它当作带复位的普通寄存器。

真实用途是把同一 PLL 时钟按模块使能输出到不同域：`ct_clk_top` 用 `core_clk_en` 门控 `forever_coreclk` 形成 `coreclk`（`gen_rtl/clk/rtl/ct_clk_top.v:59-76`）；`ct_mp_clk_top` 分别门控 APB、L2 data bank 0/1 和 L2 tag bank 0/1 时钟，共 5 个实例（`gen_rtl/clk/rtl/ct_mp_clk_top.v:140-166,231-251,297-316`）。其他时钟门控实例出现在注释中的 `gated_clk_cell` 替代实现，不属于本 `BUFGCE` module 的真实调用。

## 7. 组合/时序边界汇总

| module | 组合/时序 | 复位 | 主要边界 |
|---|---|---|---|
| `compressor_32` | 纯组合 | 无 | `ca` 未移位；位宽由调用者对齐 |
| `compressor_42` | 纯组合 | 无 | `cout` 必须接入下一位 `cin` 链；不能只取 `s/ca` |
| `booth_code` | 纯组合译码 | 无 | 有符号扩展依赖 `A[B_SIZE-1]`；非法码下 `sn` 无 default |
| `booth_code_v1` | 纯组合译码 | 无 | 只适合非负尾数语义；非法码下 `sn` 无 default |
| `sync_level2level` | `FLOP_NUM` 级时序链 | 异步低有效 | 默认 3 级；输入短脉冲可能被滤掉 |
| `sync_level2pulse` | 同步器 + 1 个历史寄存器 | 异步低有效 | `sync_out` 仅上升沿脉冲，`sync_ack` 是 level |
| `BUFGCE` | latch + 门控组合 | 无 | 初始状态可能为 `X`；`CE` 应在低电平阶段稳定 |
