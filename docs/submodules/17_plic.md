# PLIC（Platform-Level Interrupt Controller）

本文档基于 `gen_rtl/plic/rtl` 下的全部 RTL、`gen_rtl/cpu/rtl/openC910.v` 和 `gen_rtl/cpu/rtl/cpu_cfig.h` 整理。行号均按当前工作区文件记录；文中“读 claim”指 APB 读 claim 寄存器，“写 complete”指 APB 写同一 claim/complete 地址。

## 1. 功能概览

PLIC 接收外部/内部的电平或脉冲中断，经过两级同步、pending/active 管理、priority/enable 配置和每个 hart 的优先级仲裁，分别产生 machine/supervisor 外部中断请求。软件通过一条来自 CIU 的 APB 从接口访问 PLIC；`plic_top` 先按 PLIC 大块地址把访问分给 priority、pending、enable、threshold/claim、控制寄存器（以及安全扩展）等子接口，再由各子接口给出 `prdata/pready/pslverr`。

当前 `openC910` 配置是单核：`PROCESSOR_0` 开启、`MULTI_PROCESSING` 注释，PLIC 使用 144 个 pad 输入、160 个内部槽位（多出的 16 个槽位承载内部保留/ L2 ECC 事件）、10 bit 中断 ID、5 bit priority、最大 hart 数 32；`PLIC_HART_NUM` 在单核配置下为 1。证据见 `gen_rtl/cpu/rtl/cpu_cfig.h:238-259,423-437` 和 `gen_rtl/cpu/rtl/openC910.v:1533-1537`。

## 2. 层级树

```text
openC910
└─ x_plic_top : plic_top
   ├─ x_csky_apb_1tox_matrix : csky_apb_1tox_matrix
   │  ├─ x_plic_ctrl              : plic_ctrl
   │  ├─ x_plic_hreg_busif        : plic_hreg_busif
   │  │  └─ x_prio_1tox_matrix    : csky_apb_1tox_matrix（每 hart 的 enable）
   │  ├─ x_plic_kid_busif         : plic_kid_busif
   │  │  ├─ x_plic_int_sync       : sync_level2level（目录外 common RTL）
   │  │  ├─ INT_KID[i]             : plic_int_kid（i=1..INT_NUM-1）
   │  │  └─ x_prio_1tox_matrix    : csky_apb_1tox_matrix（priority 分片）
   │  └─ PLIC_SEC 配置时：x_plic_sec_busif : plic_sec_busif（本目录未提供定义）
   └─ HART_ARB[i] : plic_hart_arb（i=0..HART_NUM-1）
      ├─ x_plic_arb_ctrl           : plic_arb_ctrl
      │  └─ x_arb_ctrl_ready_gateclk : gated_clk_cell（目录外 clk RTL）
      └─ x_plic_32to1_arb          : plic_32to1_arb
         ├─ x_round_sel_*          : nor_sel（每 32 个候选中按轮次抽取）
         ├─ FIRST_SEL[*]           : plic_granu2_arb（4-to-1）
         └─ x_secd_prio_selection10: plic_granu_arb（9-to-1）
```

顶层实例和连接见 `gen_rtl/plic/rtl/plic_top.v:200-229,437-586`。`plic_hart_arb` 内部实例见 `plic_hart_arb.v:97-151`；`plic_32to1_arb` 的两级选择见 `plic_32to1_arb.v:124-175,216-264`。

## 3. 文件和 module 作用

| 文件 | module | 作用 |
|---|---|---|
| `csky_apb_1tox_matrix.v` | `csky_apb_1tox_matrix` | 通用 APB 1-to-N 译码/转发。按 `(addr & mask)==base` 产生各 master 的 `psel`，可把 APB 时序寄存一级，并汇聚 `prdata/pready/pslverr`。 |
| `plic_top.v` | `plic_top` | PLIC 封装顶层。定义参数、连接大块 APB matrix、控制/寄存器/kid 接口和每 hart 仲裁器，并导出 hart M/S 中断。 |
| `plic_ctrl.v` | `plic_ctrl` | 控制区 `0xffc`（及 `PLIC_SEC` 下 `0xff8`）的权限/AMP 寄存器；输出 supervisor 访问权限、AMP mode/lock，并返回 APB 错误。 |
| `plic_hreg_busif.v` | `plic_hreg_busif` | hart 维度的 enable、threshold、claim/complete APB 接口；维护 MIE/SIE、MTH/STH、MCLAIM/SCLAIM 对应状态，并把总线事件启动给仲裁器。 |
| `plic_kid_busif.v` | `plic_kid_busif` | 中断 ID 维度的 pending 和 priority APB 接口；同步 pad 输入，实例化每个 `plic_int_kid`，把 pending/priority/claim/complete 事件汇总给 hart 侧。 |
| `plic_int_kid.v` | `plic_int_kid` | 单个中断源的 pending、active、priority 状态机。区分脉冲/电平配置，处理软件 pending 写、claim 清除、complete 重置和新的输入事件。 |
| `plic_hart_arb.v` | `plic_hart_arb` | 一个 hart 的封装，将 enable、M/S 模式、阈值和安全过滤交给 `plic_arb_ctrl`，并把 1024 路选择结果交给 `plic_32to1_arb`。 |
| `plic_arb_ctrl.v` | `plic_arb_ctrl` | 仲裁控制状态机。过滤不可用请求，按 `INT_NUM/32` 轮次启动 1024 路选择，锁存结果，在 WRITE_CLAIM 阶段产生 M/S 请求和 claim ready。 |
| `plic_32to1_arb.v` | `plic_32to1_arb` | 固定 1024 输入的分层 priority 选择：按 32 路 round 取候选，8 组 4-to-1，再用 9-to-1 合并（8 组结果加上级流水结果）。同时生成 ID。 |
| `plic_granu2_arb.v` | `plic_granu2_arb` | 专用 4-to-1 priority 组合选择；priority 相等时低编号输入优先，见 `plic_granu2_arb.v:68-96`。 |
| `plic_granu_arb.v` | `plic_granu_arb` | 通用 priority 选择，先按 priority 展开，再选择最高有效 priority 和对应位置/ID；文件内的 `prio_sel` 负责 one-hot 选择，见 `plic_granu_arb.v:61-136,138-205`。 |

目录外的直接依赖是 `sync_level2level`（`gen_rtl/common/rtl/sync_level2level.v`）和 `gated_clk_cell`（`gen_rtl/clk/rtl/gated_clk_cell.v`）。`PLIC_SEC` 分支还实例化 `plic_sec_busif`，但 `gen_rtl/plic` 目录当前没有该 module 的源文件，见 `plic_top.v:315-336`。

## 4. 参数与当前实例化

### 4.1 顶层参数

`plic_top.v:39-50` 默认值为 `INT_NUM=1024`、`ID_NUM=10`、`HART_NUM=4`、`PRIO_BIT=5`、`MAX_HART_NUM=32`；`PLIC_SEC` 时 `SLV_NUM=6`，否则 `SLV_NUM=5`。这些默认值不是 openC910 当前实际值，真正的 SoC 实例在 `openC910.v:1533-1537` 显式传入：

```text
INT_NUM      = `PLIC_INT_NUM + 16 = 160
HART_NUM     = `PLIC_HART_NUM   = 1（当前 PROCESSOR_0）
ID_NUM       = `PLIC_ID_NUM     = 10
PRIO_BIT     = `PLIC_PRIO_BIT   = 5
MAX_HART_NUM = `MAX_HART_NUM    = 32
```

`plic_hreg_busif` 默认 `IE_ADDR=13`、`ICT_ADDR=18`（`plic_hreg_busif.v:64-74`），顶层分别以 `.IE_ADDR(13)`、`.ICT_ADDR(18)` 传入（`plic_top.v:457-464`）。`plic_hart_arb` 使用 `ECH_RD=32`，并把 `plic_32to1_arb` 固定为 `INT_NUM=1024、SEL_NUM=4`，即内部仲裁总线始终补零扩展到 1024 路，见 `plic_hart_arb.v:136-150` 和 `plic_arb_ctrl.v:57-58,168-178`。

### 4.2 输入槽位

`openC910.v:1572-1573` 形成 160 位向量：

```text
plic_int_vld[159:0] = {pad_plic_int_vld[143:0], 14'b0, l2c_plic_ecc_int_vld, 1'b0};
plic_int_cfg[159:0] = {pad_plic_int_cfg[143:0], 16'b0};
```

因此 ID 0 保留不用，L2 ECC 位和 pad 输入之间留有保留槽；`plic_kid_busif` 对 ID 0 也固定为无 active/pending、priority 0、请求 1 的伪源（`plic_kid_busif.v:225-233`）。每个真实 `plic_int_kid` 从 ID 1 生成到 `INT_NUM-1`（`plic_kid_busif.v:199-224`）。

## 5. 顶层接口和 APB 互联

### 5.1 `plic_top` 外部端口

端口定义在 `plic_top.v:15-73`：

- `ciu_plic_paddr[26:0]`、`psel/penable/pwrite/pwdata/pprot`：来自 CIU 的 APB 从接口；返回 `plic_ciu_prdata/pready/pslverr`。
- `pad_plic_int_vld[INT_NUM-1:0]`：输入中断有效电平，进入两级同步后使用。
- `pad_plic_int_cfg[INT_NUM-1:0]`：每个源的配置，`1` 表示按脉冲路径处理，`0` 表示按电平路径处理；实际 pending 逻辑见 `plic_int_kid.v:103-108`。
- `plic_hartx_mint_req/sint_req[HART_NUM-1:0]`：每个 hart 的 machine/supervisor 外部中断请求。
- `plic_clk`、低有效异步复位 `plicrst_b`，以及 `ciu_plic_icg_en/pad_yy_icg_scan_en` 时钟门控控制。
- `PLIC_SEC` 下额外有 `ciu_plic_psec[7:0]` 和每 hart 的 `ciu_plic_core_sec[HART_NUM*8-1:0]`。

顶层把 CIU APB 接到第一层 `csky_apb_1tox_matrix`，地址宽 27 位，见 `plic_top.v:200-229`。各 slave 的地址/掩码如下（基地址定义于 `plic_top.v:295-307` 或非安全分支 `418-428`）：

| 区域 | 基地址 | mask | 子接口 | 说明 |
|---|---:|---:|---|---|
| priority | `0x0000000` | `0x7fff000` | `plic_kid_busif` | 以 0x200 步长分片，每片最多 128 个 priority 字；当前 160 源需要 2 个分片。 |
| pending/IP | `0x0001000` | `0x7fff000` | `plic_kid_busif` | 每个 32-bit 字包含 32 个 pending 位。 |
| enable/IE | `0x0002000` | `0x7fff000` | `plic_hreg_busif` | 再按 hart 分片，每 hart 0x100 字节；MIE/SIE 由地址 bit 7 区分。 |
| security（仅 `PLIC_SEC`） | `0x01fe000` | `0x7fff000` | `plic_sec_busif` | 每中断源安全属性。 |
| PLIC control | `0x01ff000` | `0x7fff000` | `plic_ctrl` | `0xffc` 权限寄存器，安全扩展另有 `0xff8`。 |
| threshold/claim/complete（ICT） | `0x0200000` | `0x7fc0000` | `plic_hreg_busif` | 每 hart 0x2000 字节，低半区 M、bit 12 置位的高半区 S。 |

矩阵译码使用 `slave_addr_sel[i] = ((slv_paddr & mask)==base)`（`csky_apb_1tox_matrix.v:117-125`），APB 的有效阶段定义为 `psel && !penable`（`csky_apb_1tox_matrix.v:128-136`）。默认 `FLOP=1`：矩阵在 selected slave 上锁存地址、写数据、prot 和 psec，并在下一个阶段汇聚 ready/data/error，见 `csky_apb_1tox_matrix.v:165-189,217-280`。

### 5.2 priority 和 pending/IP

`plic_kid_busif.v:62-67` 将 priority 端口按 128 个源划分：`PRIO_SPLIT1=INT_NUM/128`，当前 `160` 对应 2 个分片；分片基址在 `plic_kid_busif.v:274-280` 以 `j<<<9`（0x200）生成。每个 priority entry 用 APB 写数据低 `PRIO_BIT` 位，读数据零扩展为 32 bit（`plic_kid_busif.v:326-341,355-389`）。非安全模式或源安全属性允许时，priority 读写才有效（`plic_kid_busif.v:331-335`）。priority/IP 写入或外部新事件都拉起 `kid_hreg_new_int_pulse`，从而启动 hart 仲裁（`plic_kid_busif.v:487-488`）。

IP 区以地址 `[11:2]` 选择 32-bit 字，写 1 置 pending、写 0 清 pending；对不允许的源，写入的 1 会保留硬件 pending，见 `plic_kid_busif.v:427-445`。地址超出 `INT_NUM/32` 或 APB prot[1] 为 0 时返回错误（`plic_kid_busif.v:467-482`）。

### 5.3 enable/IE

`plic_hreg_busif` 内部再实例化一个 `csky_apb_1tox_matrix`，每 hart 的基址是 `j<<<8`，mask 保留高位、屏蔽低 8 位，即每 hart 0x100 字节窗口（`plic_hreg_busif.v:245-284`）。在每个 hart 窗口内：

- 地址 bit 7=0 访问 MIE，bit 7=1 访问 SIE；
- 地址 `[6:2]` 选择 `INT_NUM/32` 中的 32-bit 字；
- 读返回对应 MIE/SIE 字，写数据经过安全 mask 后写入；
- ID 0 被强制清零，不参与仲裁。

上述译码和读写数据见 `plic_hreg_busif.v:294-342,348-365`；MIE/SIE 寄存器和 ID 0 清零见 `plic_hreg_busif.v:417-455`。enable APB 的 `pready/prdata/pslverr` 采用门控时钟下的寄存器握手（`plic_hreg_busif.v:370-411`）。送给仲裁器的 enable 是 MIE|SIE，M 模式标志由 MIE 位保留，见 `plic_hreg_busif.v:752-764`。

### 5.4 threshold、claim、complete

ICT 地址为 18 bit，hart 编号由 `bus_mtx_ict_paddr[ICT_ADDR-1:13]` 选择；每 hart 窗口大小为 0x2000。低半区（bit 12=0）使用 M 权限，地址 0 为 MTHRESHOLD、地址 4 为 MCLAIM；高半区（bit 12=1）使用 S 权限，地址 0 为 STHRESHOLD、地址 4 为 SCLAIM。对应读写条件在 `plic_hreg_busif.v:477-528`。

读 threshold 返回低 `PRIO_BIT` 位；读 claim 返回已锁存的 ID；写 claim 地址的低 `ID_NUM` 位作为 complete ID，见 `plic_hreg_busif.v:529-548,611-632,798-806`。M/S claim flop 的更新/清除握手是：

1. 仲裁器在 `WRITE_CLAIM` 状态输出 `arbx_hreg_claim_reg_ready` 与选中的 ID；
2. `plic_hreg_busif` 按 `arbx_hreg_claim_mmode` 把 ID 写入 M 或 S claim flop（`plic_hreg_busif.v:627-632,651-668`）；
3. 读 claim 直接产生对应 hart 的 `hart_mclaim_clr/hart_sclaim_clr`，读取动作也作为 `hreg_claim_vld` 通知 kid；
4. 写 complete 产生 `hreg_cmplt_vld` 和 `hreg_kid_cmplt_id`，再按 ID 送到相应 `plic_int_kid`。

claim/complete 还会比较所有 hart 的 M/S claim 值，清除同一个 ID 在其他 claim 寄存器中的副本；比较向量和清除逻辑见 `plic_hreg_busif.v:633-646,720-747`。所有 claim/complete、外部新脉冲、priority/IP 写和 enable/threshold 写都会触发新的仲裁启动条件 `arb_start_en`，见 `plic_hreg_busif.v:769-775`；起始 flop 位于 `plic_hreg_busif.v:777-786`。

## 6. 单个中断源的状态与外部输入

`plic_kid_busif` 先对 `pad_plic_int_vld` 做 `sync_level2level` 两级同步（`plic_kid_busif.v:172-181`），再把同步位送给 `plic_int_kid`（`plic_kid_busif.v:199-222`）。每个 `plic_int_kid` 有四个关键寄存器：

- `int_vld_ff`：同步输入上一拍，用于形成 `int_pulse = int_vld && !int_vld_ff`；
- `int_pending`：pending 位。软件 clear 或 claim 清零，软件 set 或新事件置位（`plic_int_kid.v:113-121`）；
- `int_priority`：priority 写寄存器，复位为 0（`plic_int_kid.v:124-133`）；
- `int_active`：claim 后置 1、complete 后清 0（`plic_int_kid.v:135-147`）。

`pad_plic_int_cfg_x=1` 时按脉冲路径使用新上升沿；为 0 时按电平路径，在 complete 时重新采样当前电平（`plic_int_kid.v:103-108`）。只有 `pending=1、active=0、priority!=0` 才向仲裁器输出有效请求（`plic_int_kid.v:149-156`），所以 claim 后同一个源不会再次被选中，直到 complete 清 active。

ID 0 是保留槽：`kid_arb_int_req[0]=1` 但 priority 为 0，最终不会成为有效中断；其余槽位的 priority/pending/active 分别来自 `plic_int_kid`。`plic_kid_busif` 把请求和 priority 送到 `plic_hart_arb`，并把 ID 0 的低位填充逻辑固定在 `plic_kid_busif.v:225-233,509-511`。

## 7. 每 hart 仲裁和 M/S 输出

### 7.1 请求过滤

`plic_arb_ctrl` 先把每个源拼成 `{mmode, priority}`，其中 `mmode=1` 表示该源由 MIE 打开；见 `plic_arb_ctrl.v:170-178`。有效请求为：

```text
int_in_req = kid_yy_int_req
           & {hreg_arbx_int_en[INT_NUM-1:1], 1'b1}
           & {int_sec_ctrl[INT_NUM-2:0], 1'b1};
```

即 enable、源安全属性/AMP mode 都要通过；ID 0 保持放行但 priority 为零（`plic_arb_ctrl.v:162-169`）。当 AMP mode 关闭时，`int_sec_ctrl` 全部放行；打开时按 `int_sec_infor` 与 hart 安全属性比较，见 `plic_arb_ctrl.v:162-164`。

### 7.2 1024-to-1 分层选择

`plic_hart_arb` 将 `ctrl_arb_int_prio/req` 接到 `plic_32to1_arb`（`plic_hart_arb.v:136-150`）。后者为每个输入生成固定 ID `i`（`plic_32to1_arb.v:95-101`），把 1024 路按 32 路分为 32 个 round。`nor_sel` 根据 `int_select_round` 从每个位置抽取当前 round（`plic_32to1_arb.v:110-150,270-303`）；8 组 4-to-1 `plic_granu2_arb` 先得到候选，再由 9-to-1 `plic_granu_arb` 得到最终 ID/priority/request，见 `plic_32to1_arb.v:157-175,216-264`。

`plic_granu2_arb` 和 `prio_sel` 的比较使用 `>=`，因此 priority 相等时选择较低的输入位置/编号；证据见 `plic_granu2_arb.v:68-96` 和 `plic_granu_arb.v:167-204`。

### 7.3 仲裁握手和 M/S threshold

`plic_arb_ctrl` 状态机是 `IDLE -> ARBTRATE -> ARB_DELAY -> WRITE_CLAIM -> IDLE`（`plic_arb_ctrl.v:199-231`）。

- `hreg_arbx_arb_start` 在 IDLE 进入 ARBTRATE 时得到 `arbx_hreg_arb_start_ack`（`plic_arb_ctrl.v:234-238`）；
- ARBTRATE 每个 `arb_clk` 递增 round，`RD_NUM=INT_NUM/32`，当前 160 源仍按 1024 路扩展实现，round 计数定义见 `plic_arb_ctrl.v:50-58,183-197`；
- `arb_ctrl_int_req` 在 WRITE_CLAIM 阶段成为 claim 候选，`arbx_hreg_claim_reg_ready` 同时有效（`plic_arb_ctrl.v:239-240`）；
- M/S 路径由选中 priority 的最高位 `mmode` 区分，低 `PRIO_BIT` 位必须严格大于对应 MTH/STH 才产生请求：`plic_arb_ctrl.v:244-265`；
- M/S 请求分别锁存到 `mint_out_req/sint_out_req`，claim 或阈值变化会清除旧请求（`plic_arb_ctrl.v:266-305`），最终输出是 `arbx_hartx_mint_req/sint_req`（`plic_arb_ctrl.v:307-308`）。

因此 priority 等于 threshold 时不会发出外部中断；只有 `priority > threshold` 才输出。claim 读动作由 `plic_hreg_busif` 产生清除信号，经 `hreg_arbx_mint_claim/sint_claim` 回到仲裁器，形成完整的“请求—claim—active—complete”闭环。

## 8. `plic_ctrl` 控制寄存器和安全分支

非 `PLIC_SEC` 时，控制区只接受 APB 地址 `0xffc` 且 `pprot==2'b11`，读数据是 `{31'b0, plic_s_permission_t}`；写入 bit 0 更新 supervisor 权限寄存器，见 `plic_ctrl.v:176-196`。`plic_ctrl_pready` 在选中后的 APB 有效阶段寄存一拍返回，`pslverr` 直接输出预计算错误，见 `plic_ctrl.v:198-215`。

`PLIC_SEC` 时：

- `0xff8` 为安全控制寄存器，仅安全 APB 访问可读写；写 bit 30 设置 `plic_amp`，bit 31 设置不可逆/锁存意义上的 `plic_sec_lock`，见 `plic_ctrl.v:111-146`；
- `0xffc` 为权限寄存器。AMP mode 打开后，非安全写入更新 `plic_s_permission`，安全侧权限由 `plic_s_permission_t` 保持，见 `plic_ctrl.v:148-174`；
- 非安全访问 `0xff8` 会触发 `plic_ctrl_nt_vio`，未命中 `0xff8/0xffc` 或 `pprot!=2'b11` 也返回错误（`plic_ctrl.v:113-129`）。

顶层将安全/非安全 `pprot` 按每个 slave 的权限位改写，再送入 priority/IP/IE/ICT 子接口；地址、`psel`、`pready`、`pslverr` 汇聚在 `plic_top.v:233-314`。非安全编译分支把所有 `int_sec_infor` 置 1、`ctrl_xx_core_sec` 置全 1、`ciu_plic_psec_in` 置 1，见 `plic_top.v:365-435`。

## 9. 时钟、复位和 APB 握手

- 顶层实例使用 `plic_clk=apb_clk`、`plicrst_b=apbrst_b`，证据为 `openC910.v:1550-1554`。
- 所有状态寄存器使用低有效异步复位：`plic_int_kid.v:95-101,113-147`、`plic_hreg_busif.v:651-668`、`plic_arb_ctrl.v:183-208,274-305` 均以 `posedge gated_clock or negedge plicrst_b` 描述。
- `csky_apb_1tox_matrix` 在 `psel && !penable` 采样访问，内部 selected slave 的 `psel/penable/address/data/prot` 由门控时钟锁存；slave 返回 ready 后，矩阵锁存 `prdata/pslverr/pready`，见 `csky_apb_1tox_matrix.v:128-179,217-280`。
- priority/IP/IE/ICT/control 等子模块也把 ready、read data 和 error 在 APB access 阶段锁存。例如 IP 的 `pready/prdata/pslverr` 在 `plic_kid_busif.v:447-482`，IE 在 `plic_hreg_busif.v:370-411`，ICT 在 `plic_hreg_busif.v:555-601`。
- `ciu_plic_icg_en` 是模块级时钟门控使能，`pad_yy_icg_scan_en` 是 scan 门控控制；门控实例分布于 matrix、kid、hreg、arb 控制路径。仲裁控制仅在有启动、仲裁状态、已有 M/S 请求时打开局部时钟，见 `plic_arb_ctrl.v:143-156`。

## 10. openC910 中的 APB、输入和 CPU 连接

### 10.1 APB 来源

`ct_ciu_top` 提供 `paddr/penable/pprot/pwdata/pwrite` 及 `psel_plic`，并接收 `prdata_plic/pready_plic/perr_plic`；这些端口在 `openC910.v:1315-1339` 连接。`plic_top` 使用地址低 27 位（`openC910.v:1540-1548`），时钟和复位来自 SoC APB 时钟域（`openC910.v:1550-1554`）。

### 10.2 外部输入和内部事件

顶层端口 `pad_plic_int_cfg/vld` 在 `openC910.v:141-142` 声明为 144 bit，`plic_top` 的输入来自 `plic_int_cfg/vld` 扩展向量（`openC910.v:1546-1547`）。该扩展向量将 pad 输入、L2 ECC 中断和保留位映射到 160 个 PLIC 槽位，具体拼接见 `openC910.v:1572-1573`。

### 10.3 hart 和 CPU/sysio

`plic_top` 输出向量先在 `openC910.v:1576-1579` 映射：

```text
plic_core0_me_int = plic_hartx_mint_req[0];
plic_core0_se_int = plic_hartx_sint_req[0];
plic_core1_me_int = 1'b0;
plic_core1_se_int = 1'b0;
```

随后 `ct_sysio_top` 接收这四个 PLIC 信号（`openC910.v:1679-1682`），并向 CIU/CPU 的 sysio 中断路径提供 `sysio_piu0_me_int/sysio_piu0_se_int` 等信号（`openC910.v:1687-1700`）。`ct_ciu_top` 同时把 `sysio_piu0_me_int/sysio_piu0_se_int` 等送到 core0 的 `pad_ibiu0_me_int/pad_ibiu0_se_int`（`openC910.v:1267-1277,1340-1355`），而 core0 实例消费对应 `pad_biu_me_int/pad_biu_se_int`（`openC910.v:762-772`）。

在当前单核配置，实际生效链路可以简化为：

```text
pad_plic_int_vld/cfg 或 L2 ECC
  -> openC910 plic_int_vld/cfg[159:0]
  -> plic_top -> plic_kid_busif -> plic_int_kid
  -> plic_hart_arb[0] -> plic_hartx_mint_req/sint_req[0]
  -> plic_core0_me/se_int
  -> ct_sysio_top -> ct_ciu_top
  -> core0 pad_biu_me_int/se_int
```

## 11. 关键读写握手总结

| 事件 | 触发 | PLIC 内部动作 | 证据 |
|---|---|---|---|
| 新外部中断 | 同步后的 `int_vld` 上升沿，或电平源保持有效 | `int_pending` 置 1；若未 active，则产生 kid 新事件脉冲 | `plic_int_kid.v:93-121` |
| 软件 set/clear IP | IP 区 APB 写，地址 `[11:2]` 选 32-bit 字 | 逐 bit 生成 `busif_set_kid_ip/busif_clr_kid_ip` | `plic_kid_busif.v:427-445` |
| 修改 priority | priority 区 APB 写 | 更新 `int_priority`，触发一次新仲裁 | `plic_kid_busif.v:326-341,487-488`; `plic_int_kid.v:127-133` |
| 修改 MIE/SIE | IE 区 APB 写 | 更新对应 hart 的 enable，触发一次新仲裁 | `plic_hreg_busif.v:304-329,417-455,769-775` |
| 产生 M/S 外部中断 | 仲裁结果 priority 严格大于 MTH/STH | WRITE_CLAIM 阶段锁存 `mint_out_req/sint_out_req` | `plic_arb_ctrl.v:244-265,274-308` |
| 读 M/S claim | ICT 地址 `hart*0x2000 + 0x4` 或 `+0x1004`，读 | 返回 claim ID；清对应 claim flop，并向 kid 发 claim 清除 | `plic_hreg_busif.v:492-501,519-528,540-548,633-646` |
| 写 M/S complete | 同上地址写，数据低 10 bit 为 ID | 产生 complete ID，清该源 active；电平源会重新采样当前输入 | `plic_hreg_busif.v:519-528,804-824`; `plic_int_kid.v:103-108,139-147` |
| 非法 APB | 地址越界、prot 不允许或安全属性冲突 | 子接口 `pslverr` 置位，矩阵汇聚到 `plic_ciu_pslverr` | `plic_kid_busif.v:467-482`; `plic_hreg_busif.v:398-400,584-590`; `csky_apb_1tox_matrix.v:151-153` |

## 12. 阅读边界和实现注意点

1. `plic_hart_arb`/`plic_arb_ctrl` 的内部仲裁总线显式按 1024 路实现，即使 `openC910` 当前只实例化 160 个槽位；多出的请求和 priority 由 `ADD_NUM` 补零，不会成为有效候选，见 `plic_arb_ctrl.v:57,168-178`。
2. `plic_hreg_busif` 的 `hreg_arbx_int_en` 是 MIE|SIE，而 `hreg_arbx_int_mmode` 仅从 MIE 提取模式位；因此同一源可由 M 或 S enable，但其输出目标由 MIE 的 mode 位决定，代码见 `plic_hreg_busif.v:752-764`。
3. 本文只描述现有 RTL；没有修改 `gen_rtl/plic/rtl` 中任何文件。`PLIC_SEC` 分支所需 `plic_sec_busif` 未在本目录出现，若启用该宏，需由工程文件列表提供该 module。
