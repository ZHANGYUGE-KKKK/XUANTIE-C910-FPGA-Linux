# PMU/HPCP（`gen_rtl/pmu/rtl`）RTL 结构说明

## 1. 范围与结论

本文只描述 `gen_rtl/pmu/rtl` 下的六个目标文件，并向上追踪 `ct_top`、`ct_core`、MMU、BIU、L2C/CIU 和 SysIO 的实际端口连接；不修改任何 RTL。

当前快照中的 PMU（源码命名为 HPCP）是一个以 `ct_hpcp_top` 为顶层的硬件性能计数器单元，功能可以概括为：

- CP0/CSR 侧通过 `cp0_hpcp_*` 端口访问控制寄存器、事件选择寄存器、计数器和溢出状态。
- `MHPMEVT3..18` 实例保存 6 bit 事件号；每个有效事件计数器通过 `ct_hpcp_adder_sel` 从 42 个事件加法器中选择一个 4 bit 增量。
- 当前配置宏激活 16 个 HPM 计数器（`HPM3..18`）；`MHPMEVT19..31`、`MHPMCNT19..31` 等在 `ct_hpcp_top` 中只保留生成模板注释，没有实际实例。
- `MCYCLE` 每个计数周期加 1，`MINSTRET` 按退休指令数量加计数，`MHPMCNT3..18` 按所选事件加计数。计数器是 64 bit，溢出脉冲由 `ct_hpcp_cntof_reg` 变成粘滞位。
- 普通事件 1..15、20..42 在 PMU 内部生成；事件 16..19 在本快照中被绑为 0，因为 L2 访问/缺失计数由 CIU/L2C 维护，再通过 4 路 L2 计数/溢出通道返回 PMU。
- PMU 实例位于 `ct_top`，使用 `coreclk` 和 `mmu_rst_b`；IFU、IDU、LSU、MMU、RTU 通过 `ct_top/ct_core` 的具名 `hpcp_*` 端口接入。SysIO 不直接实例化 PMU，但提供 `TIME` 计数值的源头。

## 2. 层级与真实互联

```text
openC910
├─ ct_top x_ct_top_0
│  ├─ ct_core x_ct_core
│  │  ├─ ct_ifu_top      ── ifu_hpcp_* 事件
│  │  ├─ ct_idu_top      ── idu_hpcp_* 事件
│  │  ├─ ct_lsu_top      ── lsu_hpcp_* 事件
│  │  ├─ ct_cp0_top      ── cp0_hpcp_* 配置/CSR访问
│  │  └─ ct_rtu_top      ── rtu_hpcp_* 退休/分支/PC事件
│  ├─ ct_mmu_top         ── mmu_hpcp_* miss事件
│  ├─ ct_biu_top         ── BIU CSR读写、TIME、L2溢出同步
│  ├─ ct_hpcp_top        ── 本文 PMU 顶层
│  ├─ ct_rst_top          ── 派生 mmu_rst_b 等局部复位
│  └─ ct_clk_top          ── coreclk/forever_coreclk
├─ ct_ciu_top
│  ├─ ct_piu_other_io    ── 输出 pad_ibiu0_hpcp_l2of_int
│  └─ ct_ciu_regs        ── core0_l2of_int / core0_hpcp_cnt_en
├─ ct_l2c_top
│  ├─ ct_l2c_sub_bank_0  ── ciu_l2c_hpcp_bus / l2c_ciu_hpcp_*_bank_0
│  └─ ct_l2c_sub_bank_1  ── ciu_l2c_hpcp_bus / l2c_ciu_hpcp_*_bank_1
└─ ct_sysio_top
   └─ sysio_xx_time      ── pad_xx_time ── BIU biu_hpcp_time ── PMU TIME
```

关键层次证据：`ct_top` 在 `ct_top.v:1862-1984` 实例化 `ct_hpcp_top`；`ct_core` 中 IFU、IDU、LSU、CP0、RTU 实例分别位于 `ct_core.v:2480`、`:2686`、`:3985`、`:4488`、`:4714`；MMU 实例在 `ct_top.v:1320-1375`。总 filelist 也按 `adder_sel`、`cnt`、`cntinten_reg`、`cntof_reg`、`event`、`top` 的顺序加入六个 PMU 文件（`gen_rtl/filelists/C910_asic_rtl.fl:146-151`）。

## 3. 文件与 module 作用

| 文件 | module | 作用 | 关键证据 |
|---|---|---|---|
| `gen_rtl/pmu/rtl/ct_hpcp_top.v` | `ct_hpcp_top` | PMU 顶层：CP0 访问状态机、CSR 地址译码、模式/抑制控制、42 路事件加法器、HPM 事件选择、MCYCLE/MINSTRET/HPM 计数器、溢出中断、L2 计数桥接、读数据 mux。 | 端口 `:17-261`；配置参数 `:896-1045`；时钟/FSM `:1047-1121`；事件归一化 `:1123-1212`；事件加法器 `:1412-1463`；计数器实例 `:3697-4023`；读 mux `:4053-4193`；L2/输出 `:4195-4377`。 |
| `gen_rtl/pmu/rtl/ct_hpcp_event.v` | `ct_hpcp_event` | 一个 6 bit `MHPMEVT` 事件选择寄存器。写入时只接受高位全 0 且事件号不超过 `HPMCNT_NUM` 的值。 | 门控时钟 `:60-71`；复位/写入 `:83-90`；合法性 `:93-97`。 |
| `gen_rtl/pmu/rtl/ct_hpcp_cnt.v` | `ct_hpcp_cnt` | 通用 64 bit 计数器。捕获 `cnt_en/cnt_adder`，执行 CSR 写入或加法，产生一拍溢出脉冲。 | 门控时钟 `:70-91`；使能捕获 `:94-111`；计数/写入 `:116-126`；溢出 `:128-145`。 |
| `gen_rtl/pmu/rtl/ct_hpcp_cntinten_reg.v` | `ct_hpcp_cntinten_reg` | 单 bit 中断使能寄存器；`ct_hpcp_top` 实例化 32 个，组成 `MCNTINTEN/SCNTINTEN`。 | `:17-23`；复位和写入 `:42-50`；实例组起点 `ct_hpcp_top.v:2627-2630`。 |
| `gen_rtl/pmu/rtl/ct_hpcp_cntof_reg.v` | `ct_hpcp_cntof_reg` | 单 bit 溢出状态寄存器。CSR 写入（经过 L2 读写完成条件）优先，否则对计数器溢出做 OR，形成粘滞状态。 | `:17-25`；行为 `:48-56`；PMU 中实例 `ct_hpcp_top.v:3035-3437`。 |
| `gen_rtl/pmu/rtl/ct_hpcp_adder_sel.v` | `ct_hpcp_adder_sel` | 事件选择 mux：按 `mhpmevtx_value[5:0]` 在 `event01_adder..event42_adder` 中选一路 4 bit 增量。 | 端口 `:17-108`；选择 case `:163-251`；非法/未配置值输出 X（`:250`）。 |

## 4. 配置宏、CSR 地址和有效实例

### 4.1 编译宏

`gen_rtl/cpu/rtl/cpu_cfig.h:282-304` 显式定义 `HPCP` 和 `HPCP_CNT_NUM_16`，并由后者打开 `HPCP_CNT_GROUP0..2`。因此当前构建选择 16 个 HPM 计数器。`HPCP_CNT_NUM_4/8/29` 的分支仍在头文件中，但当前没有被定义（`:291-312`）。

`ct_hpcp_top` 同时定义 `HPMCNT_NUM=42`、`HPMEVT_WIDTH=6`（`:894-899`）。这里的 42 是事件编码空间上限：`ct_hpcp_adder_sel` 支持事件号 1..42；它不等于当前实际实例化的 HPM 计数器数量。当前实际有：

- `ct_hpcp_event x_hpcp_mhpmevent3..18`：18 个 6 bit 事件选择寄存器（实例起始于 `ct_hpcp_top.v:3450`，连续到 `:3668`）。
- `ct_hpcp_cnt x_hpcp_mcycle`、`x_hpcp_minstret`、`x_hpcp_mhpmcnt3..18`：1 个周期计数器、1 个退休计数器和 16 个 HPM 计数器（`:3700-4023`）。
- `MHPMEVT19..31` 和 `MHPMCNT19..31` 只剩 `&Instance` 注释（`:3670-3695`、`:4026-4051`），不能据此认为硬件中存在这些实例。

### 4.2 CSR 地址范围

地址参数全部在 `ct_hpcp_top.v:900-1045`：

| 类别 | CSR | 地址范围/代表地址 | 说明 |
|---|---|---|---|
| 机器控制 | `MCNTINHBT`、`MCNTINTEN`、`MCNTOF` | `0x320`、`0x7CA`、`0x7CB` | 计数抑制、中断使能、溢出状态。 |
| 机器控制 | `MHPMCR`、`MHPMSP`、`MHPMEP` | `0x7F0`、`0x7F1`、`0x7F2` | TME/TS/PMD/SCE、起始 PC、结束 PC。 |
| 机器事件 | `MHPMEVT3..18` | `0x323..0x332` | 事件号；高位必须为 0，低 6 bit 为 1..42 或 0。 |
| 机器计数 | `MCYCLE`、`MINSTRET`、`MHPMCNT3..18` | `0xB00`、`0xB02`、`0xB03..0xB12` | 64 bit 计数值；S/U 别名读写同一组实体计数器。 |
| Supervisor | `SCNTINTEN/SCNTOF/SCNTINHBT/SHPMCR/SHPMSP/SHPMEP` | `0x5C4..0x5CB` 中的定义地址 | S 模式可见值受 `cp0_hpcp_mcntwen` 掩码限制。 |
| User | `CYCLE/TIME/INSTRET/HPMCNT3..18` | `0xC00..0xC12` | `TIME` 直接选择 `biu_hpcp_time`；其余计数器复用机器实体。 |

### 4.3 CP0 访问时序

`hpcp_wen = cp0_hpcp_op[3] && (cur_state==EX2)`，状态机在 EX1 看到 `cp0_hpcp_sel` 后进入 EX2，完成后回到 EX1；复位或 `rtu_yy_xx_flush` 回到 EX1（`ct_hpcp_top.v:1091-1121`）。各控制寄存器、事件寄存器和计数器的写使能由 `cp0_hpcp_index` 与 CSR 参数比较得到（`:1214-1273`）。

读侧在 `ct_hpcp_top.v:4106-4190` 用 `cp0_hpcp_index` 选择 `data_out`；`TIME` 选择 `biu_hpcp_time`（`:4171-4173`）。读 L2 计数器或 L2 溢出状态时，`hpcp_cp0_cmplt` 等待 BIU 返回；普通 PMU 寄存器则在 EX2 完成（`:4315-4341`）。

## 5. 计数控制、时钟和复位

### 5.1 统一计数使能

- 当前特权模式若对应 `PMDM/PMDS/PMDU` 位置 1，则 `cnt_mode_dis` 置位，阻止计数；判断逻辑在 `ct_hpcp_top.v:1278-1290`。
- `hpcp_cnt_en` 由 `TME` 和 `TS` 控制：TME=0 时允许计数；TME=1 或 2 时只有 TS=1 才允许；TME=3 在当前表达式下不允许（`:1291-1293`）。
- `MCYCLE` 还需不在 debug、未被 `MCNTINHBT.CY` 抑制；`MINSTRET` 对应 `IR` 抑制位；HPM3..18 还需未被 `cnt_mask`、`MCNTINHBT` 抑制且事件选择非零（`:1296-1315`）。
- `hpcp_xx_cnt_en = !rtu_yy_xx_dbgon && !cnt_mode_dis`，再分别输出给 IFU、MMU、IDU、RTU、LSU（`:4345-4377`）。这些输出只是单元级允许信号，具体事件仍由 PMU 中的 adder 计算。

### 5.2 门控时钟

`ct_hpcp_top` 用 `gated_clk_cell` 从 `forever_cpuclk` 生成 `hpcp_clk`（`:1047-1059`）。`hpcp_clk_en` 在寄存器写、L2 完成/状态更新、CP0 访问、flush、溢出或模式切换时打开（`:1067-1086`）。

每个 `ct_hpcp_event` 和 `ct_hpcp_cnt` 还各自使用 `gated_clk_cell`，共同由 `cp0_hpcp_icg_en`、scan enable 和局部 enable 控制（`ct_hpcp_event.v:63-71`、`ct_hpcp_cnt.v:74-82`）。计数器局部时钟使能由“计数允许、CSR 写、溢出处理”组成（`ct_hpcp_top.v:2322-2339`）。

### 5.3 复位

所有 PMU 状态使用低有效异步 `cpurst_b`。`ct_top` 把 `ct_hpcp_top.cpurst_b` 实际连接到 `mmu_rst_b`，把 `forever_cpuclk` 连接到 `coreclk`（`ct_top.v:1879-1880`）；`mmu_rst_b` 由同一 `ct_top` 中的 `ct_rst_top` 派生（`:1993-2005`）。因此文档中的 PMU 复位应理解为 core 外层派生的 MMU/core reset，而不是 SysIO 的独立 `sysio_clk` 复位。

`ct_hpcp_top` 还在 `forever_cpuclk` 域更新 `TS` 和 stop 延迟寄存器（`:2392-2417`），其余主控制/寄存器状态在 `hpcp_clk` 域更新；这是源码实际存在的双时钟写法。

## 6. 计数器与事件选择数据通路

```text
IFU/IDU/LSU/MMU/RTU/CP0事件
              │
              ▼
      event01_adder..event42_adder   (4 bit)
              │
              ├─ ct_hpcp_adder_sel × HPM3..18
              │       └─ MHPMEVT3..18[5:0] 选择事件号
              ▼
      ct_hpcp_cnt × HPM3..18 / MCYCLE / MINSTRET
              │
              ├─ value[63:0]
              └─ cnt_of（一拍溢出脉冲）
                      │
                      ▼
              ct_hpcp_cntof_reg × 32
                      │
              MCNTOF/SCNTOF 与 cntinten
                      │
                      ▼
              hpcp_cp0_int_vld
```

`ct_hpcp_cnt` 的关键时序是：先在 `cnt_clk` 上捕获 `cnt_en` 和 `cnt_adder`，下一次有效时钟才执行加法；CSR 写入优先于计数加法；加法器按 64 bit 计数器加 4 bit 增量并输出第 64 位进位（`ct_hpcp_cnt.v:94-145`）。因此事件加法器一次最多增加 8（例如 8 路 latch fail）或 4（4 路 IR 类型），不会超过 4 bit 表达范围。

`ct_hpcp_event` 的写入值为 `hpcp_wdata[5:0]`，但仅在 `hpcp_wdata[63:6]` 全 0 且值 `<=42` 时有效（`ct_hpcp_event.v:83-97`）。`ct_hpcp_adder_sel` 对 1..42 做完整 case 选择，未配置值输出 X（`ct_hpcp_adder_sel.v:207-250`）。

## 7. 事件编号与来源

下面是 `ct_hpcp_top.v:1413-1463` 的实际映射。加法器单位为每个 PMU 时钟周期内的事件数量，而不是所有事件都固定加 1。

| 事件号 | PMU 加法器含义 | 实际来源/组合 |
|---:|---|---|
| 1 | I-cache access | `ifu_hpcp_icache_access` |
| 2 | I-cache miss | `ifu_hpcp_icache_miss` |
| 3 | I-UTLB miss | `mmu_hpcp_iutlb_miss` |
| 4 | D-UTLB miss | `mmu_hpcp_dutlb_miss` |
| 5 | JTLB miss | `mmu_hpcp_jtlb_miss` |
| 6 | BHT mispredict | RTU inst0 valid 且 `rtu_hpcp_inst0_bht_mispred` |
| 7 | conditional branch | RTU 三路 `condbr` 求和 |
| 8 | jump mispredict | RTU inst0 valid 且 `rtu_hpcp_inst0_jmp_mispred` |
| 9 | jump | RTU 三路 `jmp` 求和 |
| 10 | speculation fail | RTU inst0 valid 且 `spec_fail` |
| 11 | retired store | RTU 三路 `store` 求和 |
| 12 | D-cache read access | `lsu_hpcp_cache_read_access` |
| 13 | D-cache read miss | `lsu_hpcp_cache_read_miss` |
| 14 | D-cache write access | `lsu_hpcp_cache_write_access` |
| 15 | D-cache write miss | `lsu_hpcp_cache_write_miss` |
| 16..19 | L2 read access/read miss/write access/write miss | 当前均为 `4'b0`；原 L2 事件映射只在注释中保留 |
| 20 | RF latch fail | IDU pipe0..7 latch fail 求和 |
| 21 | RF register latch fail | IDU pipe3/4/5 register latch fail 求和 |
| 22 | RF instruction valid | IDU pipe0..7 instruction valid 求和 |
| 23 | load/store cross-4K stall | LSU load 与 store cross-4K stall 求和 |
| 24 | load/store other stall | LSU load 与 store other stall 求和 |
| 25 | SQ replay discard | `lsu_hpcp_replay_discard_sq` |
| 26 | SQ data discard | `lsu_hpcp_replay_data_discard` |
| 27 | BTB target mispredict | `ifu_hpcp_btb_mispred` |
| 28 | BTB target instruction | `ifu_hpcp_btb_inst` |
| 29 | ALU instruction | IDU 四路 IR 类型 bit0，排除 bit2/bit6 |
| 30 | load/store instruction | IDU 四路 IR 类型 bit1，排除 bit5 |
| 31 | vector instruction | IDU 四路 IR 类型 bit2，排除 bit5 |
| 32 | CSR instruction | IDU 四路 IR 类型 bit3 |
| 33 | sync instruction | IDU 四路 IR 类型 bit5 |
| 34 | unaligned instruction | LSU `lsu_hpcp_unalign_inst[1:0]` |
| 35 | interrupt acknowledge | `rtu_hpcp_inst0_ack_int && retired_inst0_valid` |
| 36 | interrupt disable | `cp0_hpcp_int_disable` |
| 37 | ecall instruction | IDU 四路 IR 类型 bit4 |
| 38 | long jump | RTU 三路 valid 且 PC offset over 8M |
| 39 | frontend stall | `ifu_hpcp_frontend_stall` |
| 40 | backend stall | `idu_hpcp_backend_stall` |
| 41 | sync/fence stall | `lsu_hpcp_fence_stall || idu_hpcp_fence_sync_vld` |
| 42 | FPU instruction | IDU 四路 IR 类型 bit6 |

这些事件在 `ct_top/ct_core` 中的真实来源连接如下：IFU 连接 `hpcp_ifu_cnt_en` 及五个 `ifu_hpcp_*` 输出（`ct_core.v:2534-2565`）；IDU 连接 `hpcp_idu_cnt_en`、四路 IR 类型/valid、八路 RF valid/latch fail 和 stall 信号（`ct_core.v:2710-2761`）；LSU 连接 `hpcp_lsu_cnt_en` 及 cache/stall/replay/unaligned 输出（`ct_core.v:4049-4050`、`:4228-4239`）；RTU 连接 `hpcp_rtu_cnt_en` 及三路退休信息（`ct_core.v:4738-4740`、`:4984-5020`）；MMU 则由 `ct_top` 连接 `hpcp_mmu_cnt_en` 和三个 miss 输出（`ct_top.v:1337-1375`）。

## 8. 溢出状态与中断

### 8.1 本地计数器溢出

`ct_hpcp_cnt` 在发生 64 bit 进位时把 `cnt_overflow` 置位，并在下一次该计数器时钟自动清零，因此 `cnt_of` 是一拍脉冲（`ct_hpcp_cnt.v:128-145`）。`ct_hpcp_top` 将有效溢出拼接为 `counter_overflow[31:0]`：bit0 为 `MCYCLE`，bit2 为 `MINSTRET`，bit3..18 为 `HPM3..18`，bit1 和高位未实现位置为 0（`ct_hpcp_top.v:3440-3443`）。

`ct_hpcp_cntof_reg` 默认执行 `cntof_x <= cntof_x | counter_overflow_x`，所以软件读取到的是粘滞状态；写入路径只有在 `cntof_wen_x && l2cnt_cmplt_ff` 时才覆盖该 bit（`ct_hpcp_cntof_reg.v:48-56`）。`cntof[1]` 被显式绑为 0（`ct_hpcp_top.v:3048`）。

### 8.2 中断输出

`cntinten[31:0]` 由 32 个 `ct_hpcp_cntinten_reg` 组成，机器值直接返回，Supervisor 值再与 `cp0_hpcp_mcntwen` 相与（`ct_hpcp_top.v:2617-2625`）。最终 PMU 中断为：

```text
hpcp_cp0_int_vld = |(cntinten_value[31:0] & cntof_int[31:0])
```

证据为 `ct_hpcp_top.v:4342-4343`。`cntof_int` 对普通计数器取 `cntof`，对被 `cnt_mask` 标记的 L2 计数器取 `l2of_int`（`:3022-3027`）。`ct_top` 将 `hpcp_cp0_int_vld` 接回 `ct_core`，再由 CP0 使用（`ct_top.v:1885-1888`、`ct_core.v:4654-4657`）。

## 9. L2 计数器/溢出真实通道

### 9.1 PMU 内的 L2 选择

事件 16..19 的加法器为 0，源码明确写有“tie to zero for L2 counter”，原始 L2 事件信号也被注释（`ct_hpcp_top.v:1428-1436`）。L2 通道由 `cnt_mask` 和四个 `cnt*_event_index` 维护：

- 复位时 `cnt_mask=0`，四个事件索引置为 `6'b100000`，即 bit5 置位表示未选择有效 L2 lane（`:4199-4207`）。
- 当对 `MHPMEVT` 索引写入事件编码高 4 bit 为 `0100` 的值时，`cnt_mask_set` 置位对应 HPM index，并按写数据低 2 bit 把该 HPM 绑定到 L2 lane 0..3（`:4235-4261`）。
- `cnt_mask` 置位后，`cntof_value/cntof_int` 用 `l2of_data/l2of_int` 替代同 index 的本地计数器状态（`:3022-3027`）。
- 四路 L2 计数使能还需索引 bit5 为 0、对应 inhibit 位为 0、非 debug、非 mode disable 且 `hpcp_cnt_en` 有效；最终 `l2cnt_en[3:0]` 输出到 BIU（`:4291-4301`）。
- `l2cnt_reg_idx` 将 lane 选择编码成 L2 的读 access、read miss、write access、write miss 寄存器选择，`l2cnt_idx` 再拼接操作码和写使能（`:4303-4310`）。

### 9.2 读写和完成握手

PMU 输出 `hpcp_biu_sel/op/wdata`，在需要访问 L2 计数器或 L2 溢出寄存器时等待 `biu_hpcp_cmplt`；返回数据从 `biu_hpcp_rdata[63:0]` 进入 CP0，普通寄存器仍从 `data_out` 返回（`ct_hpcp_top.v:4334-4353`）。

`ct_biu_csr_req_arbiter` 在 CP0 CSR 请求未选中时把 `hpcp_biu_sel/op/wdata` 送到 BIU CSR 通道，并把 CSR 完成/读数据回送为 `biu_hpcp_cmplt/biu_hpcp_rdata`（`gen_rtl/biu/rtl/ct_biu_csr_req_arbiter.v:70-96`）；`ct_biu_top` 的实例连接见 `ct_biu_top.v:1165-1182`。

### 9.3 L2C/CIU 到 PMU 的返回路径

L2C 本身在两个 sub-bank 上接收 `ciu_l2c_hpcp_bus_bank_0/1`，并输出 `l2c_ciu_hpcp_acc_inc_bank_*`、`l2c_ciu_hpcp_mid_bank_*`、`l2c_ciu_hpcp_miss_inc_bank_*`（`ct_l2c_top.v:525-570`、`:599-644`）。这些是 L2C/CIU 内部的性能计数通道，不是 `ct_hpcp_top` 的 event16..19 加法器。

在 CIU 中，core0 的 `ct_piu_other_io` 将 `ciu_ibiu_hpcp_l2of_int` 输出到 `pad_ibiu0_hpcp_l2of_int`（`gen_rtl/ciu/rtl/ct_ciu_top.v:1848-1859`）；`ct_ciu_regs` 将 core0 的 L2 溢出和计数使能分别接到 `regs_piu0_hpcp_l2of_int`、`core0_hpcp_cnt_en`（`ct_ciu_regs.v:651-654`）。顶层 `openC910` 将这些信号连接到 core0 的 `ct_top`（`openC910.v:761`、`:1263-1267`）；`ct_top` 再把 `pad_biu_hpcp_l2of_int` 接进 `ct_biu_top`（`ct_top.v:1675-1683`、`ct_biu_top.v:1230`）。

计数使能的另一半路径也有明确的 pad 级连接：`ct_hpcp_top.hpcp_biu_cnt_en` 进入 `ct_biu_top` 的 `hpcp_biu_cnt_en`，由 `ct_biu_other_io_sync` 产生 `biu_pad_cnt_en`（`ct_biu_top.v:1208-1227`、`ct_biu_other_io_sync.v:418-428`）；`ct_top` 将该输出暴露为 `biu_pad_cnt_en`（`ct_top.v:1554`），`openC910` 接到 `ibiu0_pad_cnt_en`（`openC910.v:730`），随后 CIU 的 PIU 同步逻辑采样 `ibiu_ciu_cnt_en` 到 `piu_regs_hpcp_cnt_en`（`ct_piu_other_io_sync.v:301-314`）。

BIU 的 `ct_biu_other_io_sync` 在 `forever_coreclk` 域采样：

- `hpcp_biu_cnt_en` 被寄存为送往 L2C/CIU 的 `biu_pad_cnt_en`（`ct_biu_other_io_sync.v:418-428`）。
- 外部 `pad_biu_hpcp_l2of_int` 被寄存为回 PMU 的 `biu_hpcp_l2of_int`（`:430-437`）。

所以完整的 L2 溢出回路是：

```text
PMU l2cnt_en
  → ct_top/ct_biu_top hpcp_biu_cnt_en
  → BIU biu_pad_cnt_en
  → CIU/L2C 计数与溢出
  → pad_ibiu0_hpcp_l2of_int
  → ct_top pad_biu_hpcp_l2of_int
  → BIU biu_hpcp_l2of_int
  → PMU l2of_int/l2of_data/cntof_int
```

## 10. SysIO 与 TIME 计数值

SysIO 不直接连接 `ct_hpcp_top` 的事件端口。它的作用是产生 CPU 系统时间值：`ct_sysio_top` 在 `sysio_clk` 上采样 `pad_cpu_sys_cnt` 到 `ccvr`，并把 `ccvr` 同时输出为 `sysio_clint_mtime` 和 `sysio_xx_time`（`gen_rtl/cpu/rtl/ct_sysio_top.v:247-270`）。`openC910` 将 `sysio_xx_time` 接到 core0 BIU 的 `pad_xx_time`（`openC910.v:781-784`），BIU `ct_biu_other_io_sync` 再在 `coreclk` 上采样为 `biu_hpcp_time`（`gen_rtl/biu/rtl/ct_biu_other_io_sync.v:384-391`）。

最后，`ct_top` 将 `biu_hpcp_time` 接入 `ct_hpcp_top`（`ct_top.v:1490-1493`、`:1862-1866`），PMU 读 `TIME` CSR 时直接返回该值（`ct_hpcp_top.v:4171-4173`）。因此 `TIME` 是 SysIO/系统计数器经 BIU 同步后的只读观察值，不是 PMU 内部 `MCYCLE` 的别名。

## 11. 读写/计数/中断主流程

```text
CP0 CSR 指令
  │ cp0_hpcp_sel/index/op/wdata
  ▼
ct_hpcp_top
  ├─ 本地 CSR：EX1→EX2，读 data_out 或写寄存器
  ├─ MHPMEVT：写入 6 bit event code
  ├─ 本地 counter：按事件 adder 加法，产生 overflow pulse
  ├─ L2 CSR：生成 hpcp_biu_sel/op/wdata，等待 biu_hpcp_cmplt
  └─ cntinten & cntof_int → hpcp_cp0_int_vld

IFU/IDU/LSU/MMU/RTU
  └─ 事件信号 → event01..42_adder → HPM3..18
```

需要特别注意两处“源码现状”：

1. 事件 16..19 的注释名称仍然保留 L2 read/miss/write/miss，但实际赋值是 0；可用的 L2 统计是另一条 CIU/L2C/BIU 旁路。
2. `HPMCNT_NUM=42` 表示事件编码上限，不表示当前有 42 个计数器；当前宏和实际 RTL 实例只支持 MCYCLE、MINSTRET、HPM3..18，以及由 mask 映射到 L2C 的四路外部计数。
