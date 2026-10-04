# PMP RTL 结构与连接报告

## 1. 范围与结论

本文只展开 `gen_rtl/pmp/rtl` 下的四个 RTL 文件，并沿着真实的具名端口连接核对 `ct_core`、`ct_top`、CP0、MMU 和 LSU 边界；不修改 RTL。

结论如下：

- `ct_pmp_top` 是 CP0 PMP CSR 与 MMU PMP 检查之间的封装层，内部实例化 `ct_pmp_regs`、5 个 `ct_pmp_acc`。
- 源码实际实现 8 个活动 PMP 区域（entry 0..7）：`ct_pmp_acc` 只实例化 comparator 0..7，`pmp_hit[15:8]` 被置零；`pmpaddr8..15` 和 `pmpcfg2` 只是 CSR 读回占位，均为零（`ct_pmp_acc.v:140-231,251`；`ct_pmp_regs.v:393,498-505`）。
- 每次检查输入一个 28-bit 物理页号/地址高位 `mmu_pmp_pa_y`，输出 4-bit `{L,X,W,R}` 许可标志。PMP 本身没有异常码或异常 valid 输出；MMU 根据这些标志产生 `mmu_lsu_access_fault0/1`、`mmu_ifu_deny`、PTW deny 或 `mmu_lsu_pa2_err`。
- 当前代码支持 OFF/TOR/NAPOT 三种有效匹配路径；NA4 的匹配信号被硬连为 0，因此模式 `2'b10` 在当前实现中不会命中（`ct_pmp_comp_hit.v:63-69,83-89`）。

## 2. 模块树与文件职责

```text
ct_top x_ct_pmp_top
├─ gated_clk_cell x_pmp_gated_clk
├─ ct_pmp_regs x_ct_pmp_regs
└─ ct_pmp_acc x_ct_pmp_acc0..4       5 个并行检查端口
   └─ ct_pmp_comp_hit x_ct_pmp_comp_hit_0..7
                                      每个端口 8 个活动区域比较器
```

| 文件 | module | 作用 | 代码证据 |
|---|---|---|---|
| `gen_rtl/pmp/rtl/ct_pmp_top.v` | `ct_pmp_top` | 译码 PMP CSR 地址、生成写使能和门控时钟；保存/读取寄存器；为 5 路 MMU 请求复制 `ct_pmp_acc`。 | module/端口 `15-62`；CSR 译码 `145-186`；实例 `189-225,237-337` |
| `gen_rtl/pmp/rtl/ct_pmp_regs.v` | `ct_pmp_regs` | 保存 entry 0..7 的配置位和地址值；实现锁定位、邻接 TOR 锁保护、CSR 读回；entry 8..15/`pmpcfg2` 置零。 | 端口/寄存器 `15-100`；配置写入 `146-376`；读回拼接 `384-393`；地址写入 `402-505`；CP0 mux `520-537` |
| `gen_rtl/pmp/rtl/ct_pmp_acc.v` | `ct_pmp_acc` | 对一个请求选择有效特权级，串联 8 个地址比较器，按最低编号优先选择命中项并输出权限。 | 端口 `15-48`；特权级 `106-109`；底边界链 `113-126`；实例 `140-231`；优先选择 `280-299` |
| `gen_rtl/pmp/rtl/ct_pmp_comp_hit.v` | `ct_pmp_comp_hit` | 将一个 entry 的 A 字段转换为 OFF/TOR/NA4/NAPOT 匹配结果，并计算下一 entry 的 TOR 上界比较结果。 | 端口 `15-30`；模式选择 `58-71`；TOR/NAPOT/NA4 `74-89`；NAPOT mask `96-129` |

## 3. `ct_pmp_top` 接口、CSR 译码和实例化

### 3.1 顶层端口

`ct_pmp_top` 的 CP0 侧输入为：

- `cp0_pmp_icg_en`：PMP 模块时钟门控使能；
- `cp0_pmp_mpp[1:0]`、`cp0_pmp_mprv`、`cp0_yy_priv_mode[1:0]`：当前/替代特权级判断；
- `cp0_pmp_reg_num[4:0]`、`cp0_pmp_wdata[63:0]`、`cp0_pmp_wreg`：PMP CSR 索引、写数据和写请求。

MMU 侧输入为 5 组 `mmu_pmp_pa0..4[27:0]`，另有 `mmu_pmp_fetch3` 指示第 3 路是否为取指检查；输出为 5 组 `pmp_mmu_flg0..4[3:0]`。端口方向和宽度见 `ct_pmp_top.v:15-62`。

### 3.2 CSR 地址译码

`cp0_pmp_addr` 由 `{7'b0011101, cp0_pmp_reg_num[4:0]}` 形成，即覆盖 `0x3A0..0x3BF`（`ct_pmp_top.v:145-164`）。源码定义了：

| `pmp_csr_sel` | CSR 参数 | 地址 |
|---:|---|---:|
| 0 | `PMPCFG0` | `12'h3A0` |
| 1 | `PMPCFG2` | `12'h3A2` |
| 2..17 | `PMPADDR0..PMPADDR15` | `12'h3B0..12'h3BF` |

参数定义和 18 路比较选择见 `ct_pmp_top.v:145-182`。写使能是 `pmp_csr_wen = pmp_csr_sel & {18{cp0_pmp_wreg}}`，并以其归约值 `wr_pmp_regs` 作为局部时钟使能（`ct_pmp_top.v:184-197`）。

### 3.3 五个并行检查端口

`ct_pmp_top` 共享同一组寄存器值，为 `mmu_pmp_pa0..4` 各实例化一个 `ct_pmp_acc`（`ct_pmp_top.v:237-337`）。MPRV 解释按端口区分：

```text
pmp_mprv_status0 = cp0_pmp_mprv
pmp_mprv_status1 = cp0_pmp_mprv
pmp_mprv_status2 = 0
pmp_mprv_status3 = cp0_pmp_mprv && !mmu_pmp_fetch3
pmp_mprv_status4 = cp0_pmp_mprv
```

证据为 `ct_pmp_top.v:228-233`。因此第 2 路不使用 MPRV 替代级别；第 3 路在 `mmu_pmp_fetch3=1` 时也不使用 MPRV，其他情况下才使用 `cp0_pmp_mpp`。

## 4. CSR 字段、参数和区域数量

### 4.1 `pmpcfg0` 字段

`ct_pmp_regs` 将 `cp0_pmp_wdata` 的配置内容拆成 8 个 entry 的寄存器字段。对 entry `i`，其字节偏移为 `8*i`：

| 字段 | 相对位 | 含义（按 RTL 信号名） |
|---|---:|---|
| `R` | `+0` | `pmpNcfg_readable` |
| `W` | `+1` | `pmpNcfg_writable` |
| `X` | `+2` | `pmpNcfg_executeable` |
| `A` | `+4:+3` | `pmpNcfg_addr_mode` |
| `L` | `+7` | `pmpNcfg_lock` |

`+6:+5` 写入时不保存，读回时由 `2'b0` 填充。entry 0..3 的写入字段在 `ct_pmp_regs.v:146-250`，entry 4..7 在 `262-376`；最终 `pmpcfg0_value[63:0]` 拼接见 `384-391`。输出权限在 `ct_pmp_acc` 中按 `{L,X,W,R}` 使用（例如 entry 0 为 `{pmpcfg0_value[7],pmpcfg0_value[2:0]}`，见 `ct_pmp_acc.v:280-288`）。

### 4.2 地址字段和锁定规则

- `ct_pmp_regs` 的 `ADDR_WIDTH = 28+1`，因此 `pmpaddr0_value..pmpaddr7_value` 均为 29 bit（`ct_pmp_regs.v:41-50,137`）。
- 写入地址时取 `cp0_pmp_wdata[ADDR_WIDTH+8:9]`，即当前参数下的 `[37:9]` 29 bit；读回时拼接 9 个低零位（`ct_pmp_regs.v:402-410,520-529`）。
- 每个地址寄存器有自身 L 位保护；如果下一 entry 为锁定的 TOR 区域，还会阻止当前 entry 地址修改。例如 entry 0 的条件为 `!pmpcfg0_value[7] && !(pmpcfg0_value[15] && pmpcfg0_value[12:11]==2'b01)`，其余 entry 按相邻 entry 类推（`ct_pmp_regs.v:402,414,426,438,450,462,474,486`）。
- `pmpcfg0` 的写入由 `pmp_csr_wen[0]` 触发，且每个 entry 的 L 位为 1 后不再更新该 entry（`ct_pmp_regs.v:146-163,175-192`）。

仓库配置头文件给出 `` `PA_WIDTH 40``、`` `VA_WIDTH 39``（`gen_rtl/cpu/rtl/cpu_cfig.h:462-463`）。在 comparator 中因此 `ADDR_WIDTH = PA_WIDTH-12 = 28`，请求地址是 28 bit，entry 地址保存 29 bit，其中比较使用 `pmpaddr[28:1]`（`ct_pmp_comp_hit.v:25-49,74-84`）。

### 4.3 实际活动区域数

代码能确认的活动区域数是 8，而不是 16：

1. `ct_pmp_acc` 实际实例化 `ct_pmp_comp_hit_0..7`（`ct_pmp_acc.v:140-231`）。8..15 的实例只有生成器注释，没有真实 Verilog 实例；`pmp_hit[15:8]` 明确为 `8'b0`（`ct_pmp_acc.v:234-251`）。
2. 只有 `pmpaddr0_value..pmpaddr7_value` 是时序寄存器；`pmpaddr8_value..pmpaddr15_value` 全部连续赋零（`ct_pmp_regs.v:93-100,498-505`）。
3. `pmpcfg2_value` 直接为 `64'b0`（`ct_pmp_regs.v:393`）。因此 `PMPCFG2`/`PMPADDR8..15` 可被译码和读回，但当前 RTL 没有对应的可配置活动区域。

## 5. 地址匹配与权限检查

### 5.1 单 entry 地址匹配

`ct_pmp_comp_hit` 按 A 字段选择：

| A | 代码含义 | 当前行为 |
|---|---|---|
| `2'b00` | OFF | `pmp_mmu_hit_x=0` |
| `2'b01` | TOR | 使用前一 entry 上界和当前 entry 上界 |
| `2'b10` | NA4 | 代码将 `mmu_na4_addr_match` 固定为 0 |
| `2'b11` | NAPOT | 地址与 mask 相等时命中 |

证据为 `ct_pmp_comp_hit.v:63-71,74-89`。TOR 的实现为 `bottom <= addr < top`：当前地址与 `pmpaddr_x_value[28:1]` 相减得到上界比较，`mmu_addr_ge_upaddr_x = !borrow` 供下一个 entry 作为 bottom 判断（`ct_pmp_comp_hit.v:74-81`）。entry 0 的 bottom 固定为 0，后续 bottom 由前一 entry 的 `mmu_addr_ge_upaddr` 串联得到（`ct_pmp_acc.v:113-120`）。

NAPOT mask 由 `pmpaddr_x_value[28:0]` 的连续低位 1 模式生成，代码覆盖 4 KiB 到 1 TiB 的 mask 案例；未匹配时 mask 为 0（`ct_pmp_comp_hit.v:96-129`）。

### 5.2 命中优先级和权限输出

`pmp_hit[7:0]` 按 entry 编号收集，`casez` 从 bit0 到 bit7 逐项选择，因此低编号命中优先（`ct_pmp_acc.v:122-126,280-296`）。命中后输出对应 `pmpcfg` 的 `{L,X,W,R}`；没有命中时：

```text
M-mode:     pmp_default_flg = 4'b0111  （R/W/X 允许，L=0）
非 M-mode:  pmp_default_flg = 4'b0000
```

默认值和 M-mode 判定见 `ct_pmp_acc.v:106-109,256`。有效特权级由 `pmp_mprv_status_y ? cp0_pmp_mpp : cur_priv_mode` 决定。

## 6. 与 `ct_core`、CP0、MMU、LSU 的真实连接

### 6.1 CP0 CSR 写入和读回路径

```text
IUI CSR 地址/源操作数
  → ct_cp0_regs: pmp_regs_sel、cp0_pmp_wreg/reg_num/wdata
  → ct_core:     透传至 ct_top
  → ct_pmp_top:  CSR 译码、pmp_csr_wen、门控 cpuclk
  → ct_pmp_regs: 保存 pmpcfg0 / pmpaddr0..7

ct_pmp_regs.pmp_cp0_data
  → ct_pmp_top.pmp_cp0_data
  → ct_top / ct_core / ct_cp0_top
  → ct_cp0_regs.regs_iui_data_out
```

证据链：

- CP0 用 `iui_regs_addr[11:4]` 识别 `0x3A/0x3B` 为 PMP CSR（`ct_cp0_regs.v:3809-3810`），产生写请求、5-bit 索引和 64-bit 写数据（`ct_cp0_regs.v:4264-4277`）。
- `ct_core` 的 `ct_cp0_top` 实例连接 `cp0_pmp_*` 和 `pmp_cp0_data`（`ct_core.v:4631-4636,4685`）。
- `ct_top` 将这些信号接到 `ct_cp0_top` 和 `ct_pmp_top`；PMP 实例的真实连接在 `ct_top.v:923-930,1204,1444-1467`。
- CP0 读回 mux 在 `pmp_regs_sel` 有效时选择 `pmp_cp0_data`（`ct_cp0_regs.v:3995-4001`）。

### 6.2 时钟和复位

`ct_top` 将 `forever_cpuclk` 接为 `coreclk`，将 PMP 复位接为 `mmu_rst_b`（`ct_top.v:1452-1453`）。`ct_pmp_top` 内部用 `gated_clk_cell` 生成 `cpuclk`：全局使能为 1，模块使能为 `cp0_pmp_icg_en`，局部使能为 `wr_pmp_regs`，扫描使能来自 `pad_yy_icg_scan_en`（`ct_pmp_top.v:189-197`）。

`ct_pmp_regs` 的配置寄存器和地址寄存器均使用 `posedge cpuclk or negedge cpurst_b`，低有效异步复位；复位把配置权限、A、L 和地址清零（代表性代码 `ct_pmp_regs.v:147-173,403-410`）。`ct_pmp_acc` 和 `ct_pmp_comp_hit` 均为组合检查逻辑，没有时钟/复位端口。

### 6.3 五路 MMU 请求/响应路径

| PMP 路 | 请求来源/地址 | PMP 输出消费点 | 形成的拒绝/异常信号 |
|---:|---|---|---|
| 0、1 | `ct_mmu_dutlb` 两个 LSU 数据翻译端口；最终 PA 缓存在 `dutlb_pa_buf` 后送 `mmu_pmp_pa_x`（`ct_mmu_dutlb_read.v:742-772`） | `pmp_mmu_flg0/1` 回到 D-uTLB read | 读/写权限分别参与 `mmu_lsu_access_fault_x`，并输出 `mmu_lsu_access_fault0/1`（`ct_mmu_dutlb_read.v:490-500`）；经 `ct_top.v:1168-1186` 接入 `ct_lsu_top` |
| 2 | `ct_mmu_iutlb` 的取指 PA 缓冲，送 `mmu_pmp_pa2`（`ct_mmu_iutlb.v:2270-2288`） | `pmp_mmu_flg2` | X 权限失败生成 `mmu_ifu_deny`，M-mode 由 L 位覆盖（`ct_mmu_iutlb.v:609-614`）；经 `ct_top.v:1376-1382` 返回 IFU 侧 |
| 3 | `ct_mmu_ptw` 页表访问地址页号，`mmu_pmp_fetch3=ptw_fetch_type`（`ct_mmu_ptw.v:750-756`） | `pmp_mmu_flg3` | 按 fetch/load/store/pref 分别检查 X/R/W/R，生成 `ptw_pmp_deny`（`ct_mmu_ptw.v:644-653`）；PTW 实例连接见 `ct_mmu_top.v:1007-1037` |
| 4 | `ct_mmu_jtlb` 的 PFU PA 缓冲，送 `mmu_pmp_pa4`（`ct_mmu_jtlb.v:1405-1410`） | `pmp_mmu_flg4` | 检查 R 权限生成 `jtlb_pfu_deny`，随后 `mmu_lsu_pa2_err` 标记错误（`ct_mmu_jtlb.v:1422-1430`）；JTLB 连接见 `ct_mmu_top.v:976-979` |

MMU 的 5 路接口在 `ct_top` 的 `ct_pmp_top` 实例中集中连接（`ct_top.v:1454-1466`）。数据侧 LSU 本身没有 `pmp_*` 端口；它通过 MMU 的 `mmu_lsu_access_fault0/1`、PA valid/error、page fault 等返回通道接收结果，具体 LSU/MMU 两端连接见 `ct_top.v:1131-1186` 和 `ct_top.v:1343-1401`。

## 7. 异常语义边界

PMP 输出只有权限标志 `pmp_mmu_flg[3:0]`，位含义由 `ct_pmp_acc.v:281-296` 的拼接直接确认：

```text
pmp_mmu_flg[0] = R
pmp_mmu_flg[1] = W
pmp_mmu_flg[2] = X
pmp_mmu_flg[3] = L
```

异常/拒绝由消费端根据访问类型生成：

- LSU load：`R=0` 时 `mmu_lsu_access_fault_x=1`；store：`W=0` 时置 1；M-mode 且 `L=0` 时允许覆盖该拒绝（`ct_mmu_dutlb_read.v:491-497`）。
- IFU fetch：`X=0` 时 `mmu_ifu_deny=1`，同样有 M-mode/L-bit 特殊处理（`ct_mmu_iutlb.v:611-614`）。
- PTW：按 fetch/load/store/pref 类型分别使用 X/R/W/R（`ct_mmu_ptw.v:648-653`）。
- JTLB/PFU：当前消费路径只检查 R，并输出 `mmu_lsu_pa2_err`（`ct_mmu_jtlb.v:1423-1429`）。

因此，不能把 `pmp_mmu_flg*` 直接称为“异常输出”；它们是 MMU 的权限判定结果，最终 fault/deny 信号由 MMU 产生并送回 IFU/LSU/PTW 控制路径。

## 8. 证据范围说明

本文所称“8 个区域”仅按当前四个 PMP RTL 文件中的真实 Verilog 逻辑确认。`ct_pmp_top.v` 中 `PMPADDR8..15` 参数和 `ct_pmp_acc.v` 中 8..15 的生成器注释不等于已综合的活动区域；实际 RTL 已用 `pmp_hit[15:8]=0`、地址全零和 `pmpcfg2_value=0` 明确限制为 entry 0..7。
