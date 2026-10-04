# 复位子系统：`ct_rst_top` / `ct_mp_rst_top`

## 1. 范围与结论

本文只描述 `gen_rtl/rst/rtl` 下两个复位模块及其在 `ct_top`、`openC910` 中的上下游连接，不修改 RTL。

代码中的复位信号统一采用低有效命名（后缀 `_b`）。复位结构的共同原则是：

- 功能复位输入先与 MBIST 条件组合，作为异步置零条件；
- 正常工作模式下，复位释放通过同一时钟域的三级触发器同步；
- `ct_rst_top` 在三级 CPU 复位之后又给 IFU/IDU/LSU/FPU/MMU/HAD 各加一级释放寄存器；
- 扫描模式用 `pad_yy_scan_rst_b` 直接旁路功能复位同步链；
- FIFO 复位同时要求对应 core 复位和全局 CPU 复位已释放；APB 复位直接跟随 CPU 复位；JTAG 复位在 JTAG 时钟域同步，并额外受 CPU 复位同步链约束。

顶层复位树可概括为：

```text
openC910 pads
  ├─ pad_cpu_rst_b / pad_core[0/1]_rst_b / pad_had_jtg_trst_b
  ├─ pad_yy_mbist_mode / pad_yy_scan_mode / pad_yy_scan_rst_b
  └─ pad_yy_dft_clk_rst_b
          │
          ▼
    ct_mp_rst_top                         （forever_cpuclk / forever_jtgclk）
      ├─ cpurst_b ────────────────┬─ ct_top.pad_cpu_rst_b
      ├─ core0_rst_b ─────────────┼─ ct_top_0.pad_core_rst_b
      ├─ core1_rst_b ─────────────┼─ ct_had_common_top / 双核接口
      ├─ core[0/1]_fifo_rst_b ────┼─ CIU/核心统计 FIFO 类寄存器
      ├─ apbrst_b = cpurst_b ─────┼─ APB、CLINT、PLIC、RMU dummy
      ├─ phl_rst_b ───────────────└─ ct_mp_clk_top 外设时钟使能状态
      └─ trst_b ───────────────────── ct_had_common_top JTAG TAP

    ct_top（每个 core 一个）
      └─ ct_rst_top（forever_coreclk）
          ├─ ifu_rst_b ── ct_core.IFU
          ├─ idu_rst_b ── ct_core.IDU/相关 IU
          ├─ lsu_rst_b ── ct_core.LSU
          ├─ fpu_rst_b ── ct_core.VFPU
          ├─ mmu_rst_b ── MMU/PMP/BIU/HPCP
          └─ had_rst_b ── core 私有 HAD
```

## 2. 模块与文件职责

| 模块/文件 | 作用 | 关键证据 |
|---|---|---|
| `ct_rst_top` / `gen_rtl/rst/rtl/ct_rst_top.v` | 单个 `ct_top` 内部的 CPU/core 复位分发。将 core/cpu pad 复位和 MBIST 组合后，在 `forever_coreclk` 域同步释放，并生成六路功能复位。 | 模块端口与寄存器见 `ct_rst_top.v:17-71`；核心复位同步链见 `:77-95`；六路输出见 `:97-155`。 |
| `ct_mp_rst_top` / `gen_rtl/rst/rtl/ct_mp_rst_top.v` | `openC910` 多核/公共逻辑的复位管理，覆盖 CPU、core0/core1、core FIFO、APB、时钟外围和 JTAG。 | 端口见 `ct_mp_rst_top.v:17-56`；CPU/core/FIFO/APB/PHL/JTAG 实现见 `:100-216`。 |
| `ct_top` / `gen_rtl/cpu/rtl/ct_top.v` | 单核 CPU 子系统包装层；实例化 `ct_rst_top`，将六路复位连接到 `ct_core`、MMU、PMP、BIU、HAD 等子模块。 | `ct_core` 实例在 `ct_top.v:849-1308`；MMU/PMP/BIU/HAD 的复位连接见 `:1320-1453`、`:1476-1583`、`:1709-1723`；`ct_rst_top` 实例见 `:1990-2006`。 |
| `openC910` / `gen_rtl/cpu/rtl/openC910.v` | 多核 CPU 顶层；实例化 `ct_mp_rst_top`，把复位结果送入 `ct_top_0`、CIU、APB 外设、时钟和 JTAG。当前配置只实际实例化 core0 的 `ct_top`。 | core0 连接见 `openC910.v:694-805`；单核配置说明及 core1 tie-off 见 `:827-883`；公共复位实例见 `:1581-1603`。 |
| `ct_ciu_top` / `gen_rtl/ciu/rtl/ct_ciu_top.v` | CIU/总线及其 APB/寄存器子系统。接收全局 `cpurst_b` 和每核 `core*_fifo_rst_b`。 | 端口见 `:20-103`、`:377-382`；`ct_ciu_regs` 接线见 `:3917-3937`。 |
| `ct_ciu_regs`、`ct_ciu_regs_kid` | 将每核 FIFO 复位送到核心相关统计/计数寄存器；这些寄存器在多个 L2 统计时钟上用 `x_fifo_rst_b` 异步清零。 | `ct_ciu_regs` 到 core0/core1 的连接见 `ct_ciu_regs.v:576-628`；多时钟复位使用见 `ct_ciu_regs_kid.v:185-191`、`:202-245`、`:263-331`。 |
| `ct_ciu_apbif`、`ct_clint_top`、`plic_top`、`ct_rmu_top_dummy` | APB 访问通路和 APB 外设复位消费者。APB 接口状态机使用 `cpurst_b`；CLINT/PLIC/RMU 使用 `apbrst_b`。 | `ct_ciu_apbif.v:258-326`、`:317-350`；`openC910.v:667-675`、`:1499-1523`、`:1533-1555`。 |
| `ct_had_common_top` | 公共 HAD/JTAG 调试逻辑；TAP 状态机和串行寄存器使用 `trst_b`，CPU 侧调试逻辑使用 `cpurst_b`/core reset。 | JTAG 状态机见 `ct_had_common_top.v:171-191`；串行链见 `:204-231`；core reset 及公共 CPU reset 连接见 `:289-320`。 |
| `ct_mp_clk_top` | 生成 CPU/core/JTAG/APB 时钟；`phl_rst_b` 复位外设时钟使能状态，`pad_yy_dft_clk_rst_b` 复位 MBIST 时钟比例寄存器。 | 时钟映射见 `ct_mp_clk_top.v:121-137`；PHL/APB 时钟使能见 `:145-166`；MBIST 时钟使能及比例寄存器见 `:199-229`、`:285-299`。 |

`C910_asic_rtl.fl` 也明确把这两个复位 RTL 纳入编译文件列表：`ct_mp_rst_top.v` 在 `:354-356`，`ct_rst_top.v` 在 `:367-370`，`ct_top.v` 在 `:434-436`。

## 3. `ct_rst_top`：单核内部复位

### 3.1 输入组合与同步释放

`ct_rst_top` 的功能复位异步条件为：

```verilog
async_corerst_b = pad_core_rst_b & pad_cpu_rst_b & !pad_yy_mbist_mode;
```

对应 RTL 为 `ct_rst_top.v:77`。因此，只要 core reset、CPU reset 任一为低，或者进入 MBIST 模式，异步条件为低。`core_rst_ff_1st/2nd/3rd` 在 `posedge forever_coreclk` 下串行置 1，在 `negedge async_corerst_b` 下异步清 0，见 `:79-93`。

三级链稳定后形成 `corerst_b`；正常模式为 `core_rst_ff_3rd`，扫描模式则选择 `pad_yy_scan_rst_b`，见 `:95`：

```verilog
corerst_b = pad_yy_scan_mode ? pad_yy_scan_rst_b : core_rst_ff_3rd;
```

### 3.2 六路功能复位

IFU、IDU、LSU、FPU、MMU、HAD 各有一个相同结构的寄存器级：以 `corerst_b` 为异步低有效复位，以 `forever_coreclk` 为同步时钟；正常模式下寄存器在 `corerst_b` 释放后的下一个时钟沿置高，扫描模式下输出再次直接选择 `pad_yy_scan_rst_b`。具体范围分别为：

- IFU：`ct_rst_top.v:97-105`；
- IDU：`:107-115`；
- LSU：`:117-125`；
- FPU：`:127-135`；
- MMU：`:137-145`；
- HAD：`:147-155`。

所以正常工作模式的释放路径不是单纯三级：输入复位释放后，先经过 `core_rst_ff_1st/2nd/3rd` 三个 `forever_coreclk` 边沿，再经过各分区输出寄存器的一个边沿，最终六路输出才为高。复位断言则沿异步路径清零：`async_corerst_b` 拉低先清三级链，`core_rst_ff_3rd` 拉低后使 `corerst_b` 拉低，再清六个输出寄存器。

### 3.3 在 `ct_top` 内的下游

`ct_top` 将 pad 输入送入 `x_ct_rst_top`，并导出六路内部线网，见 `ct_top.v:1993-2006`。其中：

- `ct_core` 接收 `fpu_rst_b`、`idu_rst_b`、`ifu_rst_b`、`lsu_rst_b`，见 `ct_top.v:849-932`、`:1012-1042`、`:1153-1157`；`ct_core` 内部再将它们分别作为 IFU、IDU、VFPU、LSU 的 `cpurst_b`，见 `ct_core.v:2521-2522`、`:2705-2706`、`:3495-3496`、`:3733-3740`、`:4039-4040`。
- MMU、PMP、BIU、HPCP 使用 `mmu_rst_b`，见 `ct_top.v:1337-1338`、`:1452-1453`、`:1581-1583`、`:1879-1880`。
- 私有 HAD 使用 `had_rst_b`，时钟为 `forever_coreclk`，见 `ct_top.v:1709-1723`。

这里的 `ct_rst_top` 不生成 APB、FIFO、JTAG 或公共时钟复位；这些由 `openC910` 顶层的 `ct_mp_rst_top` 负责。

## 4. `ct_mp_rst_top`：公共/多核复位

### 4.1 CPU、core0、core1

公共 CPU 复位的异步条件为 `pad_cpu_rst_b & !pad_yy_mbist_mode`，见 `ct_mp_rst_top.v:105`。`cpurst_1ff/2ff/3ff` 在 `forever_cpuclk` 域三级同步释放，见 `:107-121`；正常输出为 `cpurst_3ff`，扫描模式旁路为 `pad_yy_scan_rst_b`，见 `:123`。

core0、core1 分别使用 `pad_core0_rst_b`、`pad_core1_rst_b` 与 MBIST 条件组合，见 `:128`、`:148`。两条链也都在 `forever_cpuclk` 域三级同步释放，见 `:130-144`、`:150-164`，输出分别见 `:146`、`:166`。这使 CPU 总复位和每核复位可以独立断言/释放。

当前 `openC910` 配置实际只实例化 `ct_top_0`：其 `pad_core_rst_b` 接 `core0_rst_b`、`pad_cpu_rst_b` 接 `cpurst_b`，时钟接 `forever_core0_clk`，见 `openC910.v:694-805`。core1 的 `ct_top` 被明确移除，`pad_core1_rst_b` 被 tie-off 为 1，见 `openC910.v:827-883`；但公共复位树仍保留 core1 复位输出，供 CIU/HAD 等双核接口使用。

### 4.2 FIFO 复位

FIFO 输出不是单独的 core 复位，而是：

```verilog
core0_fifo_rst_b = scan ? pad_yy_scan_rst_b : (core0_rst_3ff & cpurst_3ff);
core1_fifo_rst_b = scan ? pad_yy_scan_rst_b : (core1_rst_3ff & cpurst_3ff);
```

RTL 见 `ct_mp_rst_top.v:146-148`、`:166-167`。正常模式下，只有对应 core 和全局 CPU 两条三级链都释放后，FIFO 复位才释放；任一链重新为低，FIFO 复位即为低。扫描模式仍直接旁路到 `pad_yy_scan_rst_b`。

在 `openC910` 中，这两路送入 `ct_ciu_top`，见 `openC910.v:1001-1085`；`ct_ciu_top` 再送入 `ct_ciu_regs`，见 `ct_ciu_top.v:3917-3937`。`ct_ciu_regs` 将它们分别送给 core0/core1 的 `ct_ciu_regs_kid.x_fifo_rst_b`，见 `ct_ciu_regs.v:576-628`。这些寄存器在 `smpr_clk`、L2 读/写访问/未命中和 overflow 等多个时钟上以 `negedge x_fifo_rst_b` 异步清零，见 `ct_ciu_regs_kid.v:185-191`、`:202-245`、`:263-331`。因此这里的 FIFO 复位证据主要落在 CIU 的核心相关 FIFO/统计寄存器域，而不是 `ct_top` 内部的 IFU/IDU/LSU pipeline 复位。

### 4.3 APB 复位

`apbrst_b` 直接赋值为 `cpurst_b`，见 `ct_mp_rst_top.v:169-173`。因此它继承 CPU 复位的扫描旁路行为：正常模式来自 CPU 三级同步输出，扫描模式直接来自 `pad_yy_scan_rst_b`。

下游连接为：

- `ct_rmu_top_dummy.apbrst_b`，`openC910.v:663-675`；
- `ct_clint_top.cpurst_b = apbrst_b`，并使用 `apb_clk`/`forever_cpuclk`，`openC910.v:1499-1523`；
- `plic_top.plicrst_b = apbrst_b`，并使用 `apb_clk`，`openC910.v:1533-1555`；
- `ct_ciu_apbif` 的 APB 状态机使用 `cpurst_b` 异步清零，见 `ct_ciu_apbif.v:258-326`，其数据寄存器也在 `:317-350` 使用同一复位。

因此 APB 复位本身没有独立同步链，也没有独立 pad；它是 CPU 公共复位的别名。

### 4.4 外设时钟控制复位 `phl_rst_b`

正常模式下 `phl_rst_b = cpurst_3ff`；扫描模式下改用 `pad_yy_dft_clk_rst_b`，见 `ct_mp_rst_top.v:175-178`。它送入 `ct_mp_clk_top`，而 `ct_mp_clk_top` 在 `posedge pll_cpu_clk or negedge phl_rst_b` 下清零 `peripheral_clk_en`，见 `ct_mp_clk_top.v:145-151`。

需要区分两个 DFT 复位用途：`phl_rst_b` 复位外设时钟使能状态；`pad_yy_dft_clk_rst_b` 还直接复位 L2 data/tag MBIST 时钟比例寄存器，见 `ct_mp_clk_top.v:219-229`、`:285-295`。

### 4.5 JTAG/TAP 复位

JTAG 有两条复位来源：

1. `async_trst_b = pad_had_jtg_trst_b & !pad_yy_mbist_mode`，见 `ct_mp_rst_top.v:183`。`trst_1ff/2ff/3ff` 在 `forever_jtgclk` 域三级同步释放，见 `:185-199`。
2. CPU 复位也在 JTAG 时钟域复制一份：`cpurst_jtg_1ff/2ff/3ff` 由 `async_cpurst_b` 异步清零，并在 `forever_jtgclk` 域三级释放，见 `:201-215`。

最终 JTAG 复位为：

```verilog
trst_b = pad_yy_scan_mode ? pad_yy_scan_rst_b
                          : (trst_3ff & cpurst_jtg_3ff);
```

见 `ct_mp_rst_top.v:216`。正常模式下，TAP reset 和 CPU reset 在 JTAG 域都释放后才释放 `trst_b`；扫描模式则直接使用扫描复位。`trst_b` 连接到 `ct_had_common_top`，其 TAP 状态机和串行链分别使用该复位，见 `openC910.v:1711-1749` 与 `ct_had_common_top.v:171-191`、`:204-231`。

## 5. 时钟域、MBIST 与 scan 配置

| 复位/配置 | 时钟域或使用点 | 行为 |
|---|---|---|
| `pad_cpu_rst_b` | `forever_cpuclk`；`openC910.v:133-149` 为顶层输入 | 公共 CPU 复位源；在 `ct_mp_rst_top` 中与 MBIST 条件组合，并同时驱动 `cpurst_b` 与 JTAG 域的 `cpurst_jtg_*`。 |
| `pad_core0_rst_b` / `pad_core1_rst_b` | `forever_cpuclk` | 每核独立三级同步链；当前 core0 有实际 `ct_top_0`，core1 `ct_top` 被裁剪。 |
| `pad_core_rst_b` | `forever_coreclk`（各 `ct_top` 内） | 单核内部与 CPU reset 做 AND，再经三级链加分区一级释放；输入来自 `core0_rst_b` 等公共结果。 |
| `pad_had_jtg_trst_b` | `forever_jtgclk = pad_had_jtg_tclk` | JTAG TAP 的功能复位源，经 JTAG 域三级链。时钟映射见 `ct_mp_clk_top.v:133-137`。 |
| `pad_yy_mbist_mode` | 复位组合及 MBIST 时钟门控 | 在正常输出路径中使 `async_cpurst_b`、`async_core*_rst_b`、`async_trst_b` 为低，从而保持 CPU/core/JTAG 功能逻辑复位；同时 `ct_mp_clk_top` 用它开启 `bist_clk`，见 `:199-209`。 |
| `pad_yy_scan_mode` | 复位输出 mux、APB enable、MBIST clock enable | 使 `cpurst_b`、core reset、FIFO reset、`trst_b` 直接取 `pad_yy_scan_rst_b`；`phl_rst_b` 改取 `pad_yy_dft_clk_rst_b`；还使 `apb_clk_en` 逻辑输出为 1，见 `ct_mp_rst_top.v:123`、`:146-178`、`:216` 和 `ct_mp_clk_top.v:158`。 |
| `pad_yy_scan_rst_b` | 无专属同步器，作为 scan mux 直通 | 扫描模式下直接成为多路复位输出，不能按功能模式的三级同步释放来理解。 |
| `pad_yy_dft_clk_rst_b` | `bist_clk` 域 | 扫描/DFT 时复位外设时钟状态与 L2 MBIST 比例寄存器；不是 `ct_rst_top` 的输入。 |
| `pad_yy_icg_scan_en` | 各 gated-clock cell | 是时钟门控扫描使能，传给 `ct_core`、CIU、HAD、`ct_mp_clk_top` 等；它不参与两个 reset top 的逻辑组合。 |
| `pad_yy_scan_enable` | `openC910` 顶层输入 | 当前 RTL 中仅保留端口声明和 scan-chain force 注释（`openC910.v:1757-1759`），未接入 `ct_mp_rst_top` 或 `ct_rst_top`；不要将它与实际参与复位 mux 的 `pad_yy_scan_mode` 混同。 |

时钟关系的直接证据是：`ct_mp_clk_top` 将 `forever_cpuclk` 直接赋为 `pll_cpu_clk`，并让 `forever_core0_clk`、`forever_core1_clk` 同源，见 `ct_mp_clk_top.v:121-129`；`forever_jtgclk` 则来自 `pad_had_jtg_tclk`，见 `:133-137`。`ct_top` 内部的 `ct_clk_top` 将 `forever_coreclk` 赋为该实例的 `pll_core_clk`，见 `ct_top.v:2013-2023` 及 `ct_clk_top.v:59`。当前 `openC910` 将 core0 的 `pll_core_clk` 接到 `forever_core0_clk`，见 `openC910.v:778-789`，所以当前单核配置下 core reset synchronizer 与 CPU 时钟同源；JTAG 复位则明确处在独立 TCK 域。

## 6. 关键条件与证据路径汇总

| 输出 | 正常模式来源 | scan 模式来源 | 主要消费者 |
|---|---|---|---|
| `cpurst_b` | `cpurst_3ff`，由 `pad_cpu_rst_b & !pad_yy_mbist_mode` 异步清零、`forever_cpuclk` 三级释放 | `pad_yy_scan_rst_b` | `ct_top.pad_cpu_rst_b`、CIU、SYSIO、APB 相关公共逻辑、HAD |
| `core0_rst_b` / `core1_rst_b` | 对应 core pad 与 MBIST 条件形成的三级链 | `pad_yy_scan_rst_b` | `ct_top.pad_core_rst_b`、HAD common |
| `core0_fifo_rst_b` / `core1_fifo_rst_b` | `core*_rst_3ff & cpurst_3ff` | `pad_yy_scan_rst_b` | `ct_ciu_top` → `ct_ciu_regs` → `ct_ciu_regs_kid.x_fifo_rst_b` |
| `apbrst_b` | `cpurst_b` | 间接为 `pad_yy_scan_rst_b` | RMU dummy、CLINT、PLIC |
| `phl_rst_b` | `cpurst_3ff` | `pad_yy_dft_clk_rst_b` | `ct_mp_clk_top` 外设时钟使能寄存器 |
| `trst_b` | `trst_3ff & cpurst_jtg_3ff`，均在 `forever_jtgclk` 域释放 | `pad_yy_scan_rst_b` | `ct_had_common_top` TAP/串行链 |
| `ifu/idu/lsu/fpu/mmu/had_rst_b` | `ct_rst_top` 的 core/cpu/MBIST 组合，经 core 域三级链后再经各输出一级寄存器 | `pad_yy_scan_rst_b` | `ct_core` 分区、MMU/PMP/BIU/HPCP、私有 HAD |

## 7. 需要特别注意的实现细节

1. “异步复位、同步释放”只适用于功能模式的触发器链。scan 模式通过 mux 直接选择 `pad_yy_scan_rst_b`，因此外部 scan reset 的释放时序由 DFT 环境承担。
2. MBIST 信号不是一个单独的输出复位，而是嵌入三条异步条件：CPU、core0/core1、JTAG。它同时开启 `bist_clk`；所以 MBIST 模式下功能逻辑被复位，但 L2 MBIST 时钟路径被使能。
3. `core*_fifo_rst_b` 比对应 `core*_rst_b` 更严格，必须等待公共 CPU 复位也释放；这避免 core 已启动而 CIU 核心相关 FIFO/统计寄存器仍处于不一致状态。
4. `ct_top` 的 `mmu_rst_b` 实际还复位 MMU、PMP、BIU、HPCP 等公共/后端子模块；不要只按信号名把它理解为 MMU 单一复位。
5. 当前 `openC910` 是单核裁剪配置：`ct_mp_rst_top` 保留 core1 及双核公共 reset 输出，但 core1 `ct_top` 本体没有实例化，`pad_core1_rst_b` 也被 tie-off 为 1。
