# CLINT 子模块分析

## 1. 范围与结论

本节覆盖 `gen_rtl/clint/rtl` 下的 CLINT RTL，并追踪其在 `openC910` 中的 APB、系统计数器和核中断连接。CLINT 的实际状态机/寄存器/比较器都在 `ct_clint_func`；`ct_clint_top` 只负责封装并实例化它。当前 `openC910` 实例把 CLINT 的 core0 中断接入 `ct_sysio_top`，但把 core1 的四路 CLINT 输入固定为 `1'b0`，因此 RTL 可确认的有效软件/定时器中断通路是 core0；core1 侧虽有 CLINT 输出和 CIU/PIU 通路，但在 `openC910` 顶层此处被截断。

## 2. module / file 作用

| 文件 / module | 作用 | 证据 |
|---|---|---|
| `gen_rtl/clint/rtl/ct_clint_top.v` / `ct_clint_top` | CLINT 外壳；声明 APB、时钟/复位、mtime 输入和两核各自的 MS/MT/SS/ST 中断端口，并实例化唯一的 `ct_clint_func`。 | `ct_clint_top.v:17-68, 99-128` |
| `gen_rtl/clint/rtl/ct_clint_func.v` / `ct_clint_func` | 实现 APB 访问、权限/地址检查、MSIP/SSIP 软件中断寄存器、mtimecmp/stimecmp 比较寄存器、mtime 采样和中断输出。 | `ct_clint_func.v:198-203, 206-274, 276-511` |
| `gen_rtl/ciu/rtl/ct_ciu_apbif.v` / `ct_ciu_apbif` | 将 CPU/NCQ APB 请求译成 CLINT 的 `psel/paddr/pwdata/penable/pprot`，并把 CLINT 的读数据、完成和错误合并回 APB 响应。 | `ct_ciu_apbif.v:363-387, 418-438` |
| `gen_rtl/cpu/rtl/ct_sysio_top.v` / `ct_sysio_top` | 产生 `sysio_clint_mtime`；接收 CLINT 中断并通过两个 `ct_sysio_kid` 转发给 PIU/CIU。 | `ct_sysio_top.v:247-284, 297-367` |
| `gen_rtl/cpu/rtl/ct_sysio_kid.v` / `ct_sysio_kid` | 在 CPU 同源门控时钟上采样 CLINT/PLIC 中断，再输出 `sysio_piu_*_int`。 | `ct_sysio_kid.v:151-202` |

## 3. 顶层实例与端口互联

### 3.1 CLINT 实例

`openC910` 在 `x_ct_clint_top` 中连接如下：

- APB：`apb_clk_en`、`paddr`、`penable`、`pprot`、`psel_clint`、`pwdata`、`pwrite` 输入 CLINT；`prdata_clint`、`pready_clint`、`perr_clint` 返回 `ct_ciu_top`/`ct_ciu_apbif`。
- 时钟/复位：`forever_apbclk=apb_clk`、`forever_cpuclk=forever_cpuclk`、`cpurst_b=apbrst_b`，另有 `ciu_clint_icg_en` 和扫描门控信号。
- 时间输入：`sysio_clint_mtime` 接收 `ct_sysio_top` 产生的 64 位系统计数值。
- 中断输出：`clint_core0_{ms,mt,ss,st}_int` 和 `clint_core1_{ms,mt,ss,st}_int` 均由 CLINT 产生。 | `openC910.v:1495-1524`

### 3.2 APB 请求路径

`ct_ciu_apbif` 的局部 APB 桥选择 `apbif_addr[26:16] == 11'h400` 时置 `sel_clint`，随后 `psel_clint = apbif_req && sel_clint`；`paddr/pwdata/pwrite/penable/pprot` 分别来自保存的 APB 地址、写数据、方向、状态和保护属性。 | `ct_ciu_apbif.v:366-387`

CLINT 内部只在 `psel_clint && pwrite && penable` 时形成写使能；`pready_clint` 和 `perr_clint` 在 `clint_clk` 上登记，并在选择阶段根据地址错误或权限错误反馈。 | `ct_clint_func.v:210-238`

读数据由合法低 16 位地址选择寄存器值，输出到 `prdata_clint`；非法地址的 `acc_err` 会使 `perr_clint` 置位。 | `ct_clint_func.v:241-271, 421-459`

### 3.3 中断到 core 的路径

core0 的可确认路径为：

```text
ct_clint_func
  -> openC910.clint_core0_{ms,mt,ss,st}_int
  -> ct_sysio_top.x_ct_sysio_core0
  -> ct_sysio_top.sysio_piu0_{ms,mt,ss,st}_int
  -> ct_ciu_top.x_ct_piu0_other_io
  -> pad_ibiu0_{ms,mt,ss,st}_int
  -> openC910.x_ct_top_0
  -> ct_top.x_ct_biu_top
  -> ct_biu_other_io_sync
  -> ct_core.biu_cp0_{ms,mt,ss,st}_int
```

关键连接证据如下：

1. `openC910` 把 CLINT core0 输出送入 `ct_sysio_top`；core1 四路输入在这里明确接 `1'b0`。`openC910.v:1643-1656`
2. `ct_sysio_top` 将 core0/core1 的 CLINT 输入分别接到两个 `ct_sysio_kid`，并接收对应 `sysio_piu_*_int` 输出。`ct_sysio_top.v:303-367`
3. `ct_sysio_kid` 在 `kid_int_clk` 上锁存四类 CLINT 中断，再驱动 `sysio_piu_ms/ss/mt/st_int`。`ct_sysio_kid.v:154-194, 197-202`
4. `ct_ciu_top` 的 PIU0/PIU1 实例把 `sysio_piu_*_int` 直连为 `ciu_ibiu_*_int`，即顶层的 `pad_ibiu*_*_int`。`ct_ciu_top.v:1843-1859, 1892-1899, 1904-1920, 1953-1960`
5. `ct_piu_other_io_sync` 将这些信号直连到 `ciu_ibiu_*_int`；`openC910.x_ct_top_0` 再把 `pad_ibiu0_*_int` 接入核顶层。`ct_piu_other_io_sync.v:316-325`；`openC910.v:695-783`
6. `ct_biu_other_io_sync` 在 `forever_coreclk` 上用两级寄存器采样 `pad_biu_*_int`，输出 `biu_cp0_*_int`；`ct_top` 将这些信号送入 `ct_core` 的 CP0 中断输入。`ct_biu_other_io_sync.v:323-360`；`ct_top.v:849-860, 1476-1500`

## 4. 时钟、门控和复位

### 4.1 APB 寄存器时钟域

`clint_clk` 由 `gated_clk_cell` 从 `forever_apbclk` 生成，局部使能为 `psel_clint || perr_clint || pready_clint`，模块使能为 `ciu_clint_icg_en`，并受 `pad_yy_icg_scan_en` 影响。APB 完成/错误寄存器及 MSIP、SSIP、mtimecmp/stimecmp 寄存器均在该时钟上工作。 | `ct_clint_func.v:178-188, 220-238, 299-417`

在 `openC910` 中，CLINT 的 `forever_apbclk` 是 `apb_clk`，复位端口 `cpurst_b` 实际接 `apbrst_b`，所以 CLINT APB 状态的复位属于 APB 复位域，而不是 `ct_sysio_top` 使用的 `cpurst_b`。 | `openC910.v:1499-1523`

### 4.2 mtime 采样域

`mtime_clk` 由 `gated_clk_cell` 从 `forever_cpuclk` 生成，局部使能为 `apb_clk_en`，模块使能仍为 `ciu_clint_icg_en`。`clint_mtime_reg` 在 `mtime_clk` 上复位为 0，并在 `apb_clk_en` 有效时采样 `sysio_clint_mtime`。 | `ct_clint_func.v:465-493`

`ct_sysio_top` 先在 `sysio_clk` 上、以 `axim_clk_en` 为局部使能采样 `pad_cpu_sys_cnt` 到 `ccvr`，再把 `ccvr` 同时输出为 `sysio_clint_mtime` 和 `sysio_xx_time`。`sysio_clk` 也是由 `forever_cpuclk` 门控得到。 | `ct_sysio_top.v:184-216, 247-270`

因此，mtime 数据路径是 `pad_cpu_sys_cnt -> sysio_clk/ccvr -> mtime_clk/clint_mtime_reg`；两者虽同源于 `forever_cpuclk`，但使用独立门控时钟，相关 RTL 中未见额外的 Gray/握手同步逻辑。CLINT 的 APB 寄存器则属于独立的 `forever_apbclk` 门控域。

### 4.3 中断转发时钟域

`ct_sysio_kid` 的 `kid_int_clk` 从 `forever_cpuclk` 门控得到，局部使能为 `apb_clk_en`，并由 `ciu_sysio_icg_en` 控制；它在 `cpurst_b` 低有效复位时清零中断锁存器。 | `ct_sysio_kid.v:154-185`

随后，`ct_biu_other_io_sync` 在每个 core 的 `forever_coreclk` 上对来自 CIU 的中断做两级同步，复位同为低有效 `cpurst_b`。 | `ct_biu_other_io_sync.v:323-360`

## 5. APB 地址、寄存器和权限

### 5.1 可确认的地址范围

`ct_ciu_apbif` 只在 `apbif_addr[26:16] == 11'h400` 时选择 CLINT；按低 27 位地址解释，对应局部窗口 `0x0400_0000` 起始、覆盖低 16 位寄存器偏移。最终绝对地址基址不是 `ct_clint_func` 内的常量：`ct_sysio_top` 从 `pad_cpu_apb_base[39:27]` 捕获 13 位，形成 `sysio_ciu_apb_base/sysio_xx_apb_base = {apb_base, 27'b0}`，再送往 CIU/各核。 | `ct_ciu_apbif.v:366-381`；`ct_sysio_top.v:272-284`

因此，当前 RTL 足以确认 CLINT 的局部选择编码和寄存器偏移，但不能仅凭 CLINT 文件给出 SoC 固定的完整物理绝对地址；完整基址由 `pad_cpu_apb_base` 配置决定，并可通过核侧 `MAPBADDR` 观察。 | `ct_biu_other_io_sync.v:208-214`；`ct_cp0_regs.v:3680-3683, 3956-3961`

### 5.2 已实现寄存器

下表是 `ct_clint_func` 地址检查、写使能和读数据 case 均实际覆盖的条目。所有寄存器宽度为 32 bit；64 bit compare 值通过相邻的 low/high 两个寄存器拼接。

| 偏移 | 名称 | 作用 / 复位值 | 权限 |
|---:|---|---|---|
| `0x0000` | `MSIP0` | core0 machine software interrupt pending，使用 `pwdata[0]`，复位 0 | machine |
| `0x4000` | `MTIMECMP0` | core0 machine timer compare low，复位 `0xffffffff` | machine |
| `0x4004` | `MTIMECMPH0` | core0 machine timer compare high，复位 `0xffffffff` | machine |
| `0xC000` | `SSIP0` | core0 supervisor software interrupt pending，使用 `pwdata[0]`，复位 0 | supervisor/machine |
| `0xD000` | `STIMECMP0` | core0 supervisor timer compare low，复位 `0xffffffff` | supervisor/machine |
| `0xD004` | `STIMECMPH0` | core0 supervisor timer compare high，复位 `0xffffffff` | supervisor/machine |
| `0x0004` | `MSIP1` | core1 machine software interrupt pending，使用 `pwdata[0]`，复位 0 | machine |
| `0x4008` | `MTIMECMP1` | core1 machine timer compare low，复位 `0xffffffff` | machine |
| `0x400C` | `MTIMECMPH1` | core1 machine timer compare high，复位 `0xffffffff` | machine |
| `0xC004` | `SSIP1` | core1 supervisor software interrupt pending，使用 `pwdata[0]`，复位 0 | supervisor/machine |
| `0xD008` | `STIMECMP1` | core1 supervisor timer compare low，复位 `0xffffffff` | supervisor/machine |
| `0xD00C` | `STIMECMPH1` | core1 supervisor timer compare high，复位 `0xffffffff` | supervisor/machine |

地址参数定义见 `ct_clint_func.v:148-174`；地址合法性见 `ct_clint_func.v:247-269`；各项写使能见 `ct_clint_func.v:280-295`；寄存器复位/写入见 `ct_clint_func.v:299-417`；读回 mux 见 `ct_clint_func.v:421-459`。

源码还声明了 `MSIP2/3`、`MTIMECMP2/3`、`STIMECMP2/3` 及其 high 参数，但地址检查、写使能和读 mux 没有覆盖这些地址，且没有对应寄存器。因此不能把这些声明当作当前实现的可用寄存器。 | `ct_clint_func.v:148-174, 247-269, 280-295, 437-452`

### 5.3 权限与错误

`pprot=2'b00/01/11` 分别识别为 user/supervisor/machine；machine 区（低 16 位高 nibble 为 `0` 或 `4`）要求 machine，supervisor 区（`C` 或 `D`）禁止 user。非法地址或权限不满足时，`perr_clint` 在选择阶段反馈错误。 | `ct_clint_func.v:212-217, 230-238, 273-274`

## 6. 中断生成行为

- 软件中断：`clint_core0_ms_int = msip0_reg`、`clint_core0_ss_int = ssip0_reg`；core1 同理。 | `ct_clint_func.v:495-497, 505-507`
- 定时器中断：`clint_mtime_reg >= {mtimecmph,mtimecmp}` 时置位 MT；`clint_mtime_reg >= {stimecmph,stimecmp}` 时置位 ST。源码使用 `! (compare > clint_mtime_reg)` 表达该关系。 | `ct_clint_func.v:498-501, 508-511`
- `clint_mtime_reg` 不是直接使用 `sysio_clint_mtime` 比较，而是先在 `mtime_clk` 上采样，因此比较器观察到的是 CLINT 内部的最近一次采样值。 | `ct_clint_func.v:485-493`

## 7. 证据索引

- CLINT 顶层封装和端口：`gen_rtl/clint/rtl/ct_clint_top.v:17-128`
- APB 时序、权限和地址错误：`gen_rtl/clint/rtl/ct_clint_func.v:210-274`
- 寄存器定义/读写/复位：`gen_rtl/clint/rtl/ct_clint_func.v:148-174, 280-459`
- mtime 采样和比较器：`gen_rtl/clint/rtl/ct_clint_func.v:465-513`
- APB CLINT 片选：`gen_rtl/ciu/rtl/ct_ciu_apbif.v:363-405`
- 顶层 CLINT 实例：`gen_rtl/cpu/rtl/openC910.v:1495-1524`
- sysio 时间和中断入口：`gen_rtl/cpu/rtl/ct_sysio_top.v:247-284, 303-367`
- CIU/PIU 到核的中断路径：`gen_rtl/ciu/rtl/ct_ciu_top.v:1843-1961`、`gen_rtl/ciu/rtl/ct_piu_other_io_sync.v:316-325`、`gen_rtl/biu/rtl/ct_biu_other_io_sync.v:323-360`
- core CP0 中断输入：`gen_rtl/cpu/rtl/ct_core.v:483-493`、`gen_rtl/cpu/rtl/ct_top.v:849-860`
- RTL 文件清单：`gen_rtl/filelists/C910_asic_rtl.fl:39-40`
