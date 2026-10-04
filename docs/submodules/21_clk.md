# 21. 时钟生成、门控与时钟域

## 1. 范围与结论

本节覆盖 `gen_rtl/clk/rtl` 下的 3 个模块，并追踪其在单核 `ct_top` 和多核封装 `openC910` 中的实际连接。该时钟目录没有 PLL 或分频器；外部 `pll_cpu_clk`/`pll_core_clk` 和 JTAG pad 时钟由上层提供，目录内主要完成时钟直通、`BUFGCE` 门控、APB/L2C bank 时钟使能，以及 MBIST/scan 下的 L2C 时钟脉冲控制。

需要特别注意：本仓库中的 `gated_clk_cell` 是 FPGA/仿真替身，最后把 `clk_out` 直接连到 `clk_in`。因此，RTL 仿真中该单元本身不会真正停钟；门控意图仍由 `global_en/module_en/local_en/external_en` 表达，实际可见的时钟截断由 `BUFGCE` 完成。

## 2. 模块树与实例位置

```text
openC910
├─ ct_mp_rst_top x_ct_mp_rst_top                 // 多核 CPU/APB/JTAG/clkgen 复位
├─ ct_mp_clk_top x_ct_mp_clk_top                 // CPU/APB/JTAG/L2C data/tag 时钟
│  ├─ BUFGCE apb_clk_buf
│  ├─ gated_clk_cell x_data_bist_gated_clk       // MBIST/scan 控制时钟
│  ├─ BUFGCE data_bank0_clk_buf/data_bank1_clk_buf
│  └─ BUFGCE tag_bank0_clk_buf/tag_bank1_clk_buf
├─ ct_ciu_top x_ct_ciu_top                       // 下游 CIU 自身再生成 ciu_top_clk
├─ ct_l2c_top x_ct_l2c_top                       // 接收两组 data/tag bank 时钟
│  ├─ ct_l2c_sub_bank x_ct_l2c_sub_bank_0
│  └─ ct_l2c_sub_bank x_ct_l2c_sub_bank_1
└─ ct_top x_ct_top_0
   ├─ ct_rst_top x_ct_rst_top                    // 单核 core 内部复位
   └─ ct_clk_top x_ct_clk_top                    // 单核 forever/core 时钟

ct_clk_top / ct_mp_clk_top 的注释中还保留了 ASIC ICG/clock buffer 的生成模板；这些 `// &Instance` 注释不是当前 Verilog 实例。
```

多核封装当前只实例化了 `x_ct_top_0`；`core1` 的 `ct_top` 在 `openC910.v:827-896` 被明确移除并将相关信号 tie-off。`ct_mp_clk_top` 仍输出 `forever_core0_clk` 和 `forever_core1_clk`，二者在当前 RTL 都来自同一个 CPU 时钟。

## 3. 文件作用

| 文件 | 作用 | 关键证据 |
|---|---|---|
| `gen_rtl/clk/rtl/gated_clk_cell.v` | 通用 ICG 接口模型；组合计算门控条件和 scan 选择，但当前实现直通时钟 | `:16-47` |
| `gen_rtl/clk/rtl/ct_clk_top.v` | 单核 core 的 free-running 时钟和功能 coreclk 门控 | `:17-76` |
| `gen_rtl/clk/rtl/ct_mp_clk_top.v` | 多核共享 CPU、JTAG、APB，以及 L2C data/tag 两 bank 时钟 | `:17-348` |

## 4. 接口与配置

### 4.1 `ct_clk_top`

- 输入 `pll_core_clk`：core 根时钟。
- 输入 `biu_xx_normal_work`、`biu_xx_int_wakeup`、`biu_xx_dbg_wakeup`、`biu_xx_snoop_vld`、`biu_xx_pmp_sel`：BIU 工作、唤醒、调试、snoop、PMP 访问请求。
- 输入 `had_xx_clk_en`、`cp0_xx_core_icg_en`：HAD/CP0 保活或局部门控请求。
- 输出 `forever_coreclk`：直接等于 `pll_core_clk`，不受功能 gate 影响。
- 输出 `coreclk`：`BUFGCE` 的门控输出。

接口定义见 `ct_clk_top.v:17-40`。门控使能在 `:63-69` 作 OR 汇总，`coreclk` 由 `BUFGCE` 在 `:72-76` 输出。

### 4.2 `ct_mp_clk_top`

输入可分为四组：

1. 根/外设时钟：`pll_cpu_clk`、`pad_had_jtg_tclk`。
2. 普通低功耗使能：`axim_clk_en`、四个 L2C data/tag RAM `*_ram_clk_en_bank_*`。
3. DFT/scan：`pad_yy_mbist_mode`、`pad_yy_scan_mode`、`pad_yy_icg_scan_en`、`pad_yy_dft_clk_rst_b`、`phl_rst_b`。
4. MBIST 比率：`pad_l2c_data_mbist_clk_ratio[2:0]`、`pad_l2c_tag_mbist_clk_ratio[2:0]`。

输出包括 `forever_cpuclk`、`forever_core0_clk`、`forever_core1_clk`、`forever_jtgclk`、`apb_clk`/`apb_clk_en`、`axim_clk_en_f`，以及 data/tag 各 bank 的时钟。完整端口和位宽见 `ct_mp_clk_top.v:17-70`。

三个时钟 RTL 文件没有 `parameter/localparam`，也没有 `` `ifdef/`define/`include ``；配置通过端口输入完成。`BUFGCE` 是 Xilinx 原语，`ct_mp_clk_top.v:117` 仅保留了生成器依赖注释。

## 5. 时钟生成与启停条件

### 5.1 CPU 与 core 时钟

`ct_mp_clk_top` 中：

```text
pll_cpu_clk -> forever_cpuclk -> forever_core0_clk
                              -> forever_core1_clk
```

对应直连在 `ct_mp_clk_top.v:122-129`。`openC910.x_ct_top_0` 把 `forever_core0_clk` 接到 `ct_top.pll_core_clk`，见 `openC910.v:695-788`；随后 `ct_top.x_ct_clk_top` 在 `ct_top.v:2013-2024` 接收这个根时钟。

在单核 core 内，`ct_clk_top` 再形成：

```text
pll_core_clk -> forever_coreclk                  // 永久在线
             -> BUFGCE(core_clk_en) -> coreclk  // 功能时钟
```

`core_clk_en` 的启停条件是：

```text
biu_xx_normal_work | biu_xx_int_wakeup | biu_xx_dbg_wakeup |
biu_xx_snoop_vld | had_xx_clk_en | biu_xx_pmp_sel |
cp0_xx_core_icg_en
```

`ct_top` 把 `coreclk` 和 `forever_coreclk` 分别送给 BIU 等功能模块，真实连接证据为 `ct_top.v:1569-1582`；HAD 同时使用 `forever_coreclk`，见 `ct_top.v:1718-1721`。因此，`forever_coreclk` 是 core reset、HAD 和需要保持运行的逻辑的边界，`coreclk` 是可停的功能流水线边界。

### 5.2 APB 时钟

APB 使用 `pll_cpu_clk` 作为 `BUFGCE` 输入：

1. `peripheral_clk_en` 在 `pll_cpu_clk` 上、由低有效 `phl_rst_b` 异步清零；释放复位后每个上升沿翻转，见 `ct_mp_clk_top.v:145-151`。
2. `apb_clk_en_f` 在下一段 `pll_cpu_clk` 时序块中采样 `peripheral_clk_en`，见 `:153-156`。
3. `apb_clk` 的 `BUFGCE.CE` 使用 `apb_clk_en_f`，见 `:162-166`。
4. 对外的 `apb_clk_en` 在 scan mode 下被强制为 1，否则输出 `apb_clk_en_f`，见 `:158`。

所以 APB 分支仍以 `pll_cpu_clk` 为源，`apb_clk_en_f` 决定实际 `apb_clk` 是否通过。当前 RTL 中 scan override 只直接作用于 `apb_clk_en` 输出，而 `BUFGCE` 的 CE 仍写成 `apb_clk_en_f`，这是接口状态与物理时钟门控之间需要注意的实现差异。

`openC910` 中 APB 时钟实际连接到 RMU、CLINT、PLIC 等模块：`openC910.v:667-674`、`:1499-1513`、`:1549-1554`；`apb_clk_en` 还传给 sysio，见 `:1644-1647`。

### 5.3 JTAG 时钟

JTAG 不经过 CPU clock gate，`forever_jtgclk = pad_had_jtg_tclk`，见 `ct_mp_clk_top.v:133-137`。`openC910` 将其送入 `ct_mp_rst_top` 的 JTAG reset 域（`openC910.v:1584-1602`），并送给 HAD/JTAG 逻辑（`openC910.v:1732-1747`）。这是相对于 CPU/APB/L2C 的独立外部时钟域。

### 5.4 L2C data/tag bank 时钟

正常工作时，L2C 自身产生每个 bank 的 RAM 时钟请求：

- `ct_l2c_top` 对外输出四个 `*_ram_clk_en_bank_*`，并输入四个 bank 时钟，端口见 `ct_l2c_top.v:180-190`、`:243-248`。
- `openC910.x_ct_l2c_top` 将这些信号闭环接回 `ct_mp_clk_top`，见 `openC910.v:1475-1485` 和 `:1620-1627`。
- `ct_mp_clk_top` 在非 MBIST/scan 时直接采用这些 enable；data 的选择逻辑在 `ct_mp_clk_top.v:231-234`，tag 的选择逻辑在 `:297-300`。
- 四个 `BUFGCE` 都以 `pll_cpu_clk` 为输入，分别生成 data bank0/1 和 tag bank0/1，见 `:241-250`、`:306-315`。

L2C 两个 sub-bank 分别接收对应的 data/tag 时钟，并把 enable 反馈给上层，见 `ct_l2c_top.v:581-590`、`:655-664`。下游 cache array 将 tag/dirty 使用 tag 时钟、data array 使用 data 时钟，见 `ct_l2cache_top.v:100-117`、`:128-138`、`:156-187`。

## 6. MBIST、scan、低功耗与门控模型

### 6.1 通用 `gated_clk_cell`

设计意图中的门控条件是：

```text
clk_en_bf_latch = (global_en && (module_en || local_en)) || external_en
SE              = pad_yy_icg_scan_en
```

证据为 `gated_clk_cell.v:28-40`。但当前实现 `assign clk_out = clk_in`（`:42-47`），所以 `SE`、门控条件和 `external_en` 在当前 RTL 仿真中都不会截断输出时钟。该替身仍被 `ct_mp_clk_top` 的 MBIST 时钟调用，也被 CIU 等上游模块使用。

### 6.2 L2C MBIST/scan 节拍

`bist_clk_en = pad_yy_mbist_mode | pad_yy_scan_mode`，见 `ct_mp_clk_top.v:199-208`。`x_data_bist_gated_clk` 以 `pll_cpu_clk` 为输入生成 `bist_clk`；随后：

- data 比率计数器在 `bist_clk` 上、由 `pad_yy_dft_clk_rst_b` 异步清零；空闲时加载 `pad_l2c_data_mbist_clk_ratio`，否则递减，见 `:219-228`。
- tag 比率计数器使用同样机制，加载 `pad_l2c_tag_mbist_clk_ratio`，见 `:285-295`。
- 计数值为 0 时，bank clock enable 为 1；非 0 时为 0。因此 MBIST/scan 下每个 bank 的时钟按各自 3 位比率产生脉冲，正常模式则回到 L2C 的 RAM enable。

`pad_yy_icg_scan_en` 被传给 MBIST `gated_clk_cell`（`:201-208`），表达 scan ICG 选择；受上述直通替身影响，当前 RTL 中不会独立产生 scan bypass 的波形差异。

### 6.3 其他低功耗控制

`axim_clk_en_f` 在 `forever_cpuclk` 上采样 `axim_clk_en`，见 `ct_mp_clk_top.v:186-193`；它作为 `ct_ciu_top` 的 AXIM/总线 enable 使用，`openC910.v:1079-1085` 可见。CIU 还在 `forever_cpuclk` 上根据 core request、L2C reset/flush 和全局 ICG 请求更新 `ciu_top_clk_en_f`，再调用 `gated_clk_cell` 生成 `ciu_top_clk`，见 `ct_ciu_top.v:4071-4111`。这属于 clock 目录之外的下游二级门控。

## 7. 复位相关控制

- `ct_clk_top` 本身没有 reset 输入；其 `forever_coreclk` 直接来自 PLL，core reset 由外部 `ct_rst_top` 在该时钟域内同步释放，见 `ct_rst_top.v:77-105`、`:127-155`。
- 多核 `ct_mp_rst_top` 以 `forever_cpuclk` 同步生成 `cpurst_b` 和各 core reset；MBIST mode 会参与异步 reset 条件，scan mode 可直接选择 `pad_yy_scan_rst_b`，见 `ct_mp_rst_top.v:105-123`、`:128-178`。
- `phl_rst_b` 专门供 `ct_mp_clk_top` 的 APB/peripheral enable 和 clock-generator reset 使用：普通模式取 `cpurst_3ff`，scan mode 取 `pad_yy_dft_clk_rst_b`，见 `ct_mp_rst_top.v:169-178`。
- JTAG reset 在 `forever_jtgclk` 域中同步处理，MBIST mode 会屏蔽异步 JTAG reset 释放条件，见 `ct_mp_rst_top.v:181-216`。
- L2C MBIST 比率计数器不用 `phl_rst_b`，而使用独立的 `pad_yy_dft_clk_rst_b` 异步清零，见 `ct_mp_clk_top.v:219-228`、`:285-295`。

## 8. 时钟域边界摘要

| 时钟/域 | 根源与门控 | 主要消费者/边界 |
|---|---|---|
| `forever_cpuclk` | `pll_cpu_clk` 直通 | CIU、L2C 控制、系统级 CPU 逻辑；不会被 `ct_clk_top` 的 core 功能 gate 影响 |
| `forever_coreclk` | 每个 `ct_top` 内由 `pll_core_clk` 直通 | core reset、HAD、BIU 中需要常开的逻辑 |
| `coreclk` | `forever_coreclk` 经 `BUFGCE`，OR 汇总工作/唤醒/调试/ICG 请求 | 单核 core 功能流水线及其多数时序逻辑 |
| `apb_clk` | `pll_cpu_clk` 经 `BUFGCE(apb_clk_en_f)` | RMU、CLINT、PLIC 等 APB 外设 |
| `forever_jtgclk` | `pad_had_jtg_tclk` 直通 | JTAG/HAD，独立于 CPU clock gate |
| `l2c_data_clk_bank_[0:1]` | `pll_cpu_clk` 经 bank 独立 `BUFGCE` | 对应 L2C data array/ECC；enable 来自 L2C，MBIST/scan 时来自 data 比率计数器 |
| `l2c_tag_clk_bank_[0:1]` | `pll_cpu_clk` 经 bank 独立 `BUFGCE` | 对应 tag/dirty array；enable 来自 L2C，MBIST/scan 时来自 tag 比率计数器 |
| `bist_clk` | `pll_cpu_clk` 经 `gated_clk_cell` 模型 | 两个 MBIST 比率计数器；当前 RTL 替身中为直通 |

总体上，CPU/APB/L2C 时钟都以 CPU PLL 为同源时钟的不同门控分支，JTAG 是外部独立域；core 的 `forever_coreclk` 与功能 `coreclk` 是最重要的低功耗边界。文档未修改任何 RTL。

