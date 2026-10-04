# CPU 外层 RTL 结构报告

## 1. 范围与结论

本文只覆盖 `gen_rtl/cpu/rtl` 目录中的 9 个文件：8 个 Verilog 文件和 1 个配置头文件。重点依据实际 `module`、实例化语句和具名端口连接追踪，不按文件名推断。报告涉及的跨目录模块只作为边界和连接对象记录，不对其 RTL 做展开。

当前源码呈现的是单核构建：`cpu_cfig.h` 激活 `PROCESSOR_0`，而 `MULTI_PROCESSING` 和 `PROCESSOR_1` 均为注释；`openC910` 中 `core1` 的 `ct_top` 实例没有生成，相关 AXI/调试/退休/状态信号被显式置零或置为安全值。因此，外部顶层接口仍保留部分双核命名和 PLIC/CLINT 的 core1 通道，但当前有效 CPU 执行路径只有 core0。

顶层真实层次可以概括为：

```text
openC910
├─ ct_rmu_top_dummy                         APB RMU 占位模块
├─ ct_top x_ct_top_0                        core0 CPU 外层
│  ├─ ct_core x_ct_core                      CPU pipeline/core 控制面
│  │  ├─ ct_ifu_top                          取指
│  │  ├─ ct_idu_top                          译码、发射、寄存器相关
│  │  ├─ ct_iu_top                           整数执行/跳转/除法等
│  │  ├─ ct_vfpu_top                         向量/浮点执行
│  │  ├─ ct_lsu_top                          加载存储
│  │  ├─ ct_cp0_top                          CSR/特权/控制状态
│  │  └─ ct_rtu_top                          重排序、提交、异常/调试退休
│  ├─ ct_mmu_top                             地址翻译/TLB/PTW
│  ├─ ct_pmp_top                             物理内存保护
│  ├─ ct_biu_top                             core 内部访存/外部总线接口
│  ├─ ct_had_private_top                     core 私有调试接口
│  ├─ ct_hpcp_top                            性能计数器
│  ├─ ct_rst_top                             core 内部复位派生
│  └─ ct_clk_top                             core 内部时钟/门控
├─ ct_ciu_top                                core/外部总线、L2、APB 汇聚
├─ ct_l2c_top                                L2 cache
├─ ct_clint_top                              CLINT 定时器/软件/外部中断入口
├─ plic_top                                  PLIC
├─ ct_mp_rst_top                             CPU 多核级复位
├─ ct_mp_clk_top                             CPU 多核级时钟
├─ ct_sysio_top
│  ├─ ct_sysio_kid x_ct_sysio_core0           core0 中断/低功耗/调试同步
│  └─ ct_sysio_kid x_ct_sysio_core1           保留的 core1 SysIO 通道
└─ ct_had_common_top                         共享 JTAG/HAD 调试入口
```

其中，`ct_ciu_top`、`ct_l2c_top`、`ct_clint_top`、`plic_top`、`ct_mp_rst_top`、`ct_mp_clk_top`、`ct_had_common_top` 以及 `ct_core` 的七个子模块均来自 `gen_rtl` 的其他子目录或由总 filelist 提供；它们不是本目录内定义的 module。

## 2. 文件与 module 清单

| 文件 | module | 作用和证据 |
|---|---|---|
| `gen_rtl/cpu/rtl/openC910.v` | `openC910` | CPU 多核级 wrapper/系统集成顶层。定义外部 AXI、core0 调试/退休状态、JTAG、时钟复位、PLIC 输入和 L2 flush 接口；实例化 core、CIU、L2、CLINT、PLIC、时钟复位、SysIO、HAD。module/端口起点见 32-190 行；主要实例见 667-675、695-805、1002-1356、1374-1489、1499-1555、1584-1749 行。 |
| `gen_rtl/cpu/rtl/ct_top.v` | `ct_top` | 单个 hart/core 的外层封装，承接 core 级 BIU pad 侧端口、hartid/RVBA、core reset/clock、HAD 和时间/APB base，并把 core、MMU、PMP、BIU、私有 HAD、HPCP、复位、时钟接在一起。module 20 行，外部端口声明 133-241 行；实例见 849、1320、1444、1476、1709、1862、1993、2013 行。 |
| `gen_rtl/cpu/rtl/ct_core.v` | `ct_core` | CPU pipeline/control 汇聚层，集中连接 IFU、IDU、IU、VFPU、LSU、CP0、RTU，并把它们与 BIU、MMU、HAD、HPCP 之间的数百条内部通道暴露给 `ct_top`。module 20 行，输入端口 483-612 行，输出端口 613-940 行；七个主要实例见 2480、2686、3473、3733、3985、4488、4714 行。 |
| `gen_rtl/cpu/rtl/ct_sysio_top.v` | `ct_sysio_top` | CPU 系统 I/O 汇聚：生成 SysIO 门控时钟，采样系统计数器和 APB base，传递 L2 flush/no-op，实例化两个 `ct_sysio_kid`，汇聚每个 core 的 PLIC/CLINT 中断、调试请求及低功耗状态。module/端口 17-136 行；时钟和寄存器逻辑 205-295 行；kid 实例 304-367 行。 |
| `gen_rtl/cpu/rtl/ct_sysio_kid.v` | `ct_sysio_kid` | 每个 core 的 SysIO 子通道。同步 core 调试 mask/dbgrq；在 `kid_int_clk` 上采样 PLIC/CLINT 中断；复位后输出 core 低功耗/调试状态。module/端口 15-72 行，门控时钟实例 157-165 行，中断寄存器和输出 175-202 行。 |
| `gen_rtl/cpu/rtl/ct_rmu_top_dummy.v` | `ct_rmu_top_dummy` | RMU 的 APB dummy。复位后在 APB setup 阶段返回 ready；`acc_err` 和 `priv_err` 固定为 1，因此访问返回错误；读数据固定为 0。端口 15-32 行，行为 49-74 行。 |
| `gen_rtl/cpu/rtl/mp_top_golden_port.v` | `mp_top_golden_port` | 多核顶层比较/黄金模型端口镜像，只有端口声明，没有实例、连续赋值或时序逻辑。module 15 行，端口声明 109-200 行，endmodule 683 行。它与 `openC910` 的 `&Ports("compare", ...)` 对应。 |
| `gen_rtl/cpu/rtl/top_golden_port.v` | `top_golden_port` | 单 core `ct_top`/黄金模型比较端口镜像，只有端口声明，没有功能逻辑。module 15 行，端口声明 127-236 行，endmodule 543 行；`ct_top` 头部通过 `&Depend("top_golden_port.vp")` 声明比较端口依赖。 |
| `gen_rtl/cpu/rtl/cpu_cfig.h` | 无 module | 编译配置头文件，定义产品版本、FPGA/DFT、cache/TLB、核数、PLIC、PMP、HPCP、地址宽度和部分存储队列深度等宏。有效配置见第 7 节。 |

两个 `golden_port` 文件是接口模板/比较端口描述，不是运行时功能模块；局部目录中没有证据表明它们被实例化为功能逻辑。

## 3. `openC910` 顶层与外部接口

### 3.1 外部端口分组

`openC910` 的 module 端口列表位于 `openC910.v:32-110`，方向和宽度位于 `openC910.v:113-190`。主要边界如下：

- 外部内存/系统总线：`biu_pad_ar*`、`biu_pad_aw*`、`biu_pad_bready`、`biu_pad_rready`、`biu_pad_w*`，地址 40 bit、读写数据 128 bit、写 strobe 16 bit；外部返回的 `pad_biu_*` 包含 AR/AW ready、B/R response、R data/id/last/valid 和 W ready。
- 时钟/复位：输入 `pll_cpu_clk`、`pad_cpu_rst_b`、`pad_core0_rst_b`、`pad_had_jtg_trst_b`、DFT/scan 复位和模式；输入 `axim_clk_en`；这些信号在 module 端口声明的 113-149 行可见。
- core0 启动/身份：`pad_core0_hartid[2:0]`、`pad_core0_rvba[39:0]`、`pad_core0_dbg_mask`、`pad_core0_dbgrq_b`、`pad_core0_rst_b`。
- 调试/JTAG：`pad_had_jtg_tclk/tdi/tms/trst_b`，输出 `had_pad_jtg_tdo`、`had_pad_jtg_tdo_en`，以及输出 `cpu_debug_port`。
- 系统控制：`pad_cpu_apb_base[39:0]`、`pad_cpu_sys_cnt[63:0]`、L2 flush request/done、`cpu_pad_no_op`。
- PLIC 输入：`pad_plic_int_cfg[143:0]` 和 `pad_plic_int_vld[143:0]`。
- 观测/提交：core0 的 `core0_pad_mstatus` 和三路 `core0_pad_retire{0,1,2}`/PC；这些输出也在 176-187 行声明。

`mp_top_golden_port.v:15-200` 给出对应的多核比较接口。`openC910.v:112` 用 `&Ports("compare", "../../../gen_rtl/cpu/rtl/mp_top_golden_port.v")` 指向它，说明该文件主要用于接口比对/生成流程，而非额外运行时层次。

### 3.2 core0/core1 选择与连接

`openC910.v:695-805` 是唯一生效的 `ct_top x_ct_top_0` 实例。连接要点是：

- `ct_top` 的 `biu_pad_*` 连接到 `ibiu0_pad_*` 内部通道；`pad_biu_*` 返回端连接到 `pad_ibiu0_*`。
- core 级 reset、hartid、RVBA、时间和 APB base 分别来自 `core0_rst_b`、`pad_core0_hartid`、`pad_core0_rvba`、`sysio_xx_time`、`sysio_xx_apb_base`（`openC910.v:778-788`）。
- core0 的退休、mstatus、调试请求/响应和寄存器串行数据接到顶层 core0 输出或 HAD 内部网（`openC910.v:789-804`）。

core1 并没有真实的 `ct_top` 实例。`openC910.v:819-829` 的生成注释表明原设计可生成 `x_ct_top_1`；当前代码明确写着 single-core 配置并移除该实例。随后 `openC910.v:831-896` 将 `ibiu1_pad_*`、core1 调试/身份/reset/RVBA、退休状态、mstatus 和串行数据全部 tie-off。因而不能把文件中保留的 core1 wire 或 golden port 当成当前活动的第二个 CPU。

### 3.3 CIU、L2、APB 外设和 PLIC

`ct_ciu_top x_ct_ciu_top` 位于 `openC910.v:1002-1356`，是 core BIU 与外部总线/L2/APB 外设之间的汇聚点：

- `ibiu0_pad_*`/`ibiu1_pad_*` 侧连接 core 端通道；顶层 `biu_pad_*` 侧连接最终外部总线。
- 其端口同时连接 `ciu_l2c_*` 大量 bank/一致性/请求响应通道、`sysio_l2c_flush_req`、`sysio_piu*` 中断/低功耗信号，以及 APB 地址/控制/返回通道（`paddr`、`pprot`、`pwrite`、`pwdata`、`penable`、`psel_*`、`pready_*`、`prdata_*`、`perr_*`）。例如 APB 选择和返回连接位于 `openC910.v:1315-1339`，SysIO 连接位于 `openC910.v:1340-1355`。
- CIU 输出 `axim_clk_en_f`、`apb_clk_en`、`ciu_*_icg_en` 和 `ciu_xx_no_op`，供时钟和 SysIO 使用。

`ct_l2c_top x_ct_l2c_top` 位于 `openC910.v:1374-1489`，接收 CIU 的 L2 bank 请求/响应，向 CIU 返回 `l2c_sysio_flush_done`、`l2c_sysio_flush_idle`、`l2c_xx_no_op`，并提供 `l2c_plic_ecc_int_vld`。

`ct_clint_top x_ct_clint_top` 位于 `openC910.v:1499-1524`。它使用 `apb_clk`/`apbrst_b`，接收 SysIO 提供的 `sysio_clint_mtime`，在 APB 侧与 `paddr/penable/pprot/pwdata/pwrite/psel_clint` 交互，并产生 core0/core1 的 M/S 软件和定时器中断。

`plic_top x_plic_top` 位于 `openC910.v:1533-1555`，参数分别是 `INT_NUM` 取 `PLIC_INT_NUM+16`、`HART_NUM` 取 `PLIC_HART_NUM`、`ID_NUM` 取 `PLIC_ID_NUM`、`PRIO_BIT` 取 `PLIC_PRIO_BIT`、`MAX_HART_NUM` 取 `MAX_HART_NUM`。在当前配置下实际为 160 个 PLIC 输入槽、1 个 hart、10 bit ID、5 bit priority，最大 hart 上限 32；其中 144 个外部输入来自 pad，额外槽用于保留/内部事件。`openC910.v:1572-1579` 将 144-bit pad 输入拼接到扩展向量，同时插入 L2 ECC 中断，并把 hart0 的 M/S 请求送往 core0；core1 的 PLIC 中断固定为 0。

APB 本身不是 `openC910` 的外部顶层端口，而是 `ct_ciu_top` 在 CPU 内部生成并分发给 CLINT、PLIC、HAD 和 RMU dummy 的内部总线。RMU dummy 连接见 `openC910.v:667-675`，其固定错误响应行为见 `ct_rmu_top_dummy.v:49-74`。

## 4. `ct_top` 与 `ct_core` 的真实连接

### 4.1 `ct_top` 的职责边界

`ct_top` 的端口分为两层：一侧是面向 `openC910` 的 core BIU pad/调试/退休/时钟复位端口（`ct_top.v:133-241`）；另一侧是面向 `ct_core`、MMU、PMP、BIU、HAD/HPCP 的内部 wire。`ct_core x_ct_core` 在 `ct_top.v:849-1308`，连接覆盖：

- IFU 读请求/返回：`biu_ifu_*`；LSU 访问、读写、snoop 和返回：`biu_lsu_*`。
- CP0 与各单元：`cp0_*` 控制、CSR/APB 返回、特权状态、时钟门控和中断。
- IFU/IDU/IU/VFPU/LSU/RTU 与 HAD/HPCP 的观测、计数、flush、提交和 debug request 通道。
- core 级 `forever_coreclk`、`ifu_rst_b`、`idu_rst_b`、`lsu_rst_b`、`fpu_rst_b` 等局部复位/时钟信号。

### 4.2 MMU、PMP、BIU、HAD、HPCP

- `ct_mmu_top x_ct_mmu_top`：`ct_top.v:1320-1435`。CP0 提供 SATP/特权/访问控制/刷新操作；IFU 提供取指 VA；LSU 提供数据 VA、TLB 操作和访问属性；MMU 返回 IFU/LSU 的 PA、fault、stall、TLB busy/done，并输出 PTW 所需的 BIU 请求。其输入/输出的代表性连接见 `ct_top.v:1321-1375`。
- `ct_pmp_top x_ct_pmp_top`：`ct_top.v:1444-1467`。使用 CP0 的 PMP CSR 写入/索引/特权状态，接收 MMU 的多个 PA/fetch 检查请求，返回 `pmp_mmu_flg0..4` 和 CP0 读数据。
- `ct_biu_top x_ct_biu_top`：`ct_top.v:1476-1701`。这是 core 内部 IFU/LSU/CP0/HPCP 到 `ct_ciu_top`/外部 `biu_pad_*` 的桥。代表性连接包括 IFU 读通道 `biu_ifu_*`、LSU 请求/返回 `biu_lsu_*`、CP0 APB/中断/启动信息和外部 AXI/一致性侧 `biu_pad_*`。
- `ct_had_private_top x_ct_had_private_top`：`ct_top.v:1709-1853`。将 core0 的 IFU/IDU/LSU/RTU/CP0 观测和断点、debug request 输入汇聚到 `x_*` 调试端口；其时钟为 `forever_coreclk`，复位为 `had_rst_b`（`ct_top.v:1718-1724`）。
- `ct_hpcp_top x_ct_hpcp_top`：`ct_top.v:1862-1985`。从 IFU/IDU/LSU/MMU/RTU/BIU 接收事件，使用 CP0 的计数器控制，向各单元返回计数 enable/控制，并向 BIU/L2 输出相关计数/中断信息。
- `ct_rst_top x_ct_rst_top`：`ct_top.v:1993-2006`。以 CPU/core reset 和 MBIST/scan 模式生成 IFU、IDU、LSU、FPU、MMU、HAD 的局部复位。
- `ct_clk_top x_ct_clk_top`：`ct_top.v:2013-2024`。以 `pll_core_clk` 和 BIU/HAD/CP0 的活动/唤醒信号生成 `coreclk`、`forever_coreclk` 及相关门控；局部代码只显示端口连接，具体门控实现位于 `gen_rtl/clk/rtl/ct_clk_top.v`。

### 4.3 `ct_core` 内部七个主要子模块

`ct_core` 不是单一执行单元，而是内部数据/控制网络的显式连接层。其真实实例位置和连接重点如下：

| 实例 | 行号 | 端口连接所证明的职责 |
|---|---:|---|
| `ct_ifu_top x_ct_ifu_top` | `ct_core.v:2480-2678` | 连接 `biu_ifu_rd_*`、CP0 的 I-cache/BTB/BHT/RAS/LBUF 控制、RTU redirect/flush、MMU 取指结果、HAD IFU 观测以及 HPCP 前端计数。 |
| `ct_idu_top x_ct_idu_top` | `ct_core.v:2686-3465` | 连接 IFU 指令流、CP0 解码/寄存器/向量控制、HAD 译码观测、HPCP IDU 事件、IU/LSU/VFPU 发射和 RTU 分配/恢复接口；复位明确接 `idu_rst_b`（`ct_core.v:2705-2706`）。 |
| `ct_iu_top x_ct_iu_top` | `ct_core.v:3473-3725` | 连接 IDU 的 ALU/BJU/MUL/DIV 发射，CP0 异常/向量控制，RTU flush/提交，以及 IU 到 RTU 的结果/异常/写回通道。 |
| `ct_vfpu_top x_ct_vfpu_top` | `ct_core.v:3733-3978` | 连接 CP0 FCSR/FXCR/VL、IDU pipe6/pipe7 的向量/浮点操作、RTU 写回/完成和 HPCP；复位接 `fpu_rst_b`（`ct_core.v:3738-3741`）。 |
| `ct_lsu_top x_ct_lsu_top` | `ct_core.v:3985-4482` | 连接 BIU LSU 访问/返回、CP0 D-cache/内存序/异常控制、MMU 虚实地址和 fault、HAD load/store 观测、HPCP LSU 事件、RTU commit/flush；复位连接 `lsu_rst_b`。 |
| `ct_cp0_top x_ct_cp0_top` | `ct_core.v:4488-4708` | 汇聚 BIU APB/中断/启动信息、HAD 调试、HPCP 计数器、IDU/IFU/IU/LSU/VFPU/RTU 控制与写回，输出各单元 CP0 控制、特权模式和 `cp0_pad_mstatus`；连接开头见 `ct_core.v:4488-4525`。 |
| `ct_rtu_top x_ct_rtu_top` | `ct_core.v:4714-5173` | 汇聚 CP0 中断向量、HAD debug request、IDU 分配、IU/LSU/VFPU 完成和 flush，产生三路 retire、RTU-to-IFU/IDU/LSU 恢复以及 `rtu_cpu_no_retire`；实例开头见 `ct_core.v:4714-4755`，提交/退休输出在 `ct_core.v:5135-5153` 附近。 |

因此，IFU/IDU/IU/VFPU/LSU/CP0/RTU 之间不是通过隐含层次连接，而是在 `ct_core` 中以命名 wire 成组相连；`ct_top` 再将 core 的 BIU/MMU/PMP/HAD/HPCP 侧连接到系统级模块。

## 5. SysIO、时钟、复位、中断和 JTAG

### 5.1 SysIO

`openC910.v:1644-1703` 实例化 `ct_sysio_top`。它接收 `ct_ciu_top` 的 `ciu_xx_no_op`、clock enable、L2 flush done/idle，接收 CLINT/PLIC 到各 core 的中断，接收外部 APB base、系统计数器和 core 调试输入，并输出：

- `sysio_xx_time`：由 `pad_cpu_sys_cnt` 采样得到；`ct_sysio_top.v:251-270` 同时把相同值送给 CLINT 的 `sysio_clint_mtime`。
- `sysio_ciu_apb_base` / `sysio_xx_apb_base`：采样 `pad_cpu_apb_base[39:27]` 后低 27 bit 补零，见 `ct_sysio_top.v:273-284`。
- L2 flush request/done 和 CPU no-op，见 `ct_sysio_top.v:227-245`、`287-295`。
- 每个 core 的 PLIC/CLINT 中断、debug request/mask、低功耗状态，分别通过 `ct_sysio_kid` core0/core1 实例输出。

`ct_sysio_top.v:205-216` 用 `forever_cpuclk`、`axim_clk_en` 和 `ciu_sysio_icg_en` 生成 `sysio_clk`。两个 kid 共享此 SysIO 时钟；每个 kid 又在 `ct_sysio_kid.v:154-165` 用 `apb_clk_en` 生成自己的 `kid_int_clk`。中断在 `kid_int_clk` 上同步并由 `cpurst_b` 异步清零（`ct_sysio_kid.v:175-202`）。

### 5.2 多核级时钟和复位

`ct_mp_rst_top x_ct_mp_rst_top` 位于 `openC910.v:1584-1603`，使用 CPU/core/JTAG/DFT/MBIST/scan 复位输入，输出 `cpurst_b`、`apbrst_b`、core0/core1 reset、FIFO reset、`phl_rst_b` 和 `trst_b`。

`ct_mp_clk_top x_ct_mp_clk_top` 位于 `openC910.v:1611-1637`，使用 `pll_cpu_clk` 和 JTAG/DFT/scan 控制，输出 `forever_cpuclk`、`forever_core0_clk`、`forever_core1_clk`、`forever_jtgclk`、`apb_clk`、`apb_clk_en`、`axim_clk_en`/`axim_clk_en_f` 以及 L2 tag/data RAM 时钟和 enable。

core0 的 `forever_core0_clk` 和派生 `core0_rst_b` 进入 `ct_top_0`（`openC910.v:778-788`）；core1 时钟/复位仍由多核级模块保留，但由于 `ct_top_1` 未实例化，不形成活动指令执行路径。`ct_top` 内再由 `ct_rst_top` 和 `ct_clk_top` 细分到 IFU/IDU/LSU/FPU/MMU/HAD 等单元。

### 5.3 JTAG/HAD

`ct_had_common_top x_ct_had_common_top` 位于 `openC910.v:1712-1749`，连接 JTAG TDI/TMS/TDO、JTAG 时钟/复位、CPU/APB 复位、core0/core1 的 HAD request/ack/serial data、SysIO debug mask，以及 HAD APB 返回通道。core 私有侧由 `ct_top.v:1709-1853` 的 `ct_had_private_top` 连接到 `ct_core` 的 IFU/IDU/LSU/RTU/CP0 观测信号。

## 6. 关键总线与跨模块边界

### 6.1 core BIU 与外部 AXI/一致性侧

`ct_core` 的 IFU/LSU 不直接看到顶层 AXI。路径是：

```text
ct_ifu_top / ct_lsu_top
        │  biu_ifu_* / biu_lsu_*
        ▼
ct_biu_top（ct_top 内）
        │  biu_pad_* / pad_biu_*
        ▼
ct_ciu_top（openC910 内）
        │
        ▼
openC910 外部 biu_pad_* / pad_biu_*
```

core 级 `ct_top` 暴露的地址/ID/属性/握手还包括 snoop、coherence response、CSR 请求和 low-power 信号（`ct_top.v:181-229`）；`openC910` 的多核 wrapper 将 core0 侧改名为 `ibiu0_*`，并由 CIU 汇聚为外部 8-bit ID 的 `biu_pad_*`，其外部方向和宽度见 `openC910.v:150-175`。

### 6.2 APB

APB 只在 `openC910` 内部作为 CIU 到外设的分发总线出现：

```text
ct_ciu_top
  ├─ psel_clint / prdata_clint / pready_clint / perr_clint → ct_clint_top
  ├─ psel_plic  / prdata_plic  / pready_plic  / perr_plic  → plic_top
  ├─ psel_had   / prdata_had   / pready_had   / perr_had   → ct_had_common_top
  └─ psel_rmr   / prdata_rmr   / pready_rmr   / perr_rmr   → ct_rmu_top_dummy
```

总线公共信号 `paddr/pprot/pwrite/pwdata/penable` 由 `ct_ciu_top` 端口连接，证据在 `openC910.v:1315-1339`；各从设备实例连接在 `openC910.v:1499-1524`、`1533-1555`、`667-675` 和 `1712-1749`。

### 6.3 中断

- CLINT 产生 core0/core1 的 `ms/mt/ss/st`，经 `ct_sysio_top` 的 `ct_sysio_kid` 同步后输出为 `sysio_piu{0,1}_{m,s}{s,t}_int`，再通过 `ct_top`/`ct_core` 的 `biu_cp0_*_int` 到 CP0。
- PLIC 产生 `me/se`，路径为 `plic_top → plic_core{0,1}_{me,se}_int → ct_sysio_kid → sysio_piu{0,1}_{me,se}_int → ct_top/ct_core`。core1 PLIC/CLINT 当前在 `openC910.v:1653-1656` 和 `1578-1579` 处被接成 0。
- `ct_core.v:483-493` 的 `biu_cp0_*_int` 端口证明最终由 BIU/系统侧送入 CP0；CP0 再通过内部 `cp0_*` 控制影响 IFU/IDU/IU/VFPU/LSU/RTU。

## 7. 时钟/复位/配置宏来源

### 7.1 配置文件和编译顺序

`openC910.v:16-30`、`ct_top.v:16-17`、`ct_core.v:16-17` 使用生成器风格的 `&Depend` 声明 `cpu_cfig.h` 和 golden port 依赖。本目录的 Verilog 没有普通文本 `` `include "cpu_cfig.h" ``；实际 filelist 将 `cpu_cfig.h` 放在首项（`gen_rtl/filelists/C910_asic_rtl.fl:1`），随后才列出 `ct_core.v`（42）、`openC910.v`（356）、`ct_rmu_top_dummy.v`（368）、`ct_sysio_kid.v`/`ct_sysio_top.v`/`ct_top.v`（434-436）和两个 golden port（471、485）。因此，能确认的宏来源是该 filelist/生成器依赖机制；未在本仓库中发现更高层 Vivado/编译命令来证明是否另有 `+define+` 覆盖，若存在外部工程覆盖，最终预处理结果仍需以工程设置为准。

### 7.2 当前头文件中激活的关键宏

证据均来自 `gen_rtl/cpu/rtl/cpu_cfig.h`：

- FPGA/测试：`FPGA`（62）、`SCAN_CHAIN_8`（125）、`SMBIST`（132）、`DFT_AT_SPEED`（138）。
- 前端和 TLB：`JTLB_ENTRY_1024`（153），`BTB`/`BTB_1024`（171-177），`IBP`/`IBP_PRO`（182-187），`LBUF`（192）。
- cache：`ICACHE_64K`（198）、`DCACHE_64K`（203）、`L2_CACHE_16WAY`（214）和 `L2_CACHE_1M`（219）。16-way、1 MiB 对应的 L2 tag/data index 宏在 377-400 行分支内定义。
- hart 数：`PROCESSOR_0`（238）；`MULTI_PROCESSING`（241）被注释，`PROCESSOR_1`（244）也被注释。由此派生 `PLIC_HART_NUM=1`（423-437），并在 `openC910.v:1533-1537` 传给 `plic_top`。
- 中断控制器：`PLIC`（253），`PLIC_INT_NUM=144`、`PLIC_ID_NUM=10`、`PLIC_PRIO_BIT=5`、`MAX_HART_NUM=32`（255-259）。
- 保护/计数：`PMP`（272）；`HPCP`（282）和 `HPCP_CNT_NUM_16`（284-289），计数器 group0/1/2 在 300-304 派生。
- 数据宽度和队列：`FPR_WIDTH=63`、`VEC_WIDTH=63`（317-318），`PA_WIDTH=40`、`VA_WIDTH=39`（462-463），`SAB_DEPTH=24`、读深度 16、写深度 8（469-471）。
- 条件派生：`JTLB_ADDR_WIDTH=8` 由 1024-entry 分支产生（323-328）；`LSU_SHAREABLE` 只有在 `PROCESSOR_1` 时才定义（442-444），所以当前单核配置不会激活该分支。

## 8. 与其他目录的边界

本目录只保存 CPU 外层 wrapper、core 连接层、SysIO 两级封装、RMU dummy、比较端口和配置头。实际功能分布在 filelist 所列的其他目录：

| 本目录边界对象 | 连接到的目录/模块 | 连接证据 |
|---|---|---|
| `ct_top` 的 `ct_biu_top` | `gen_rtl/biu/rtl/ct_biu_top.v` | `ct_top.v:1476-1701`；filelist `C910_asic_rtl.fl:9-16`。 |
| `ct_top` 的 `ct_mmu_top` | `gen_rtl/mmu/rtl/ct_mmu_top.v` | `ct_top.v:1320-1435`；filelist 335-353。 |
| `ct_top` 的 `ct_pmp_top` | `gen_rtl/pmp/rtl/ct_pmp_top.v` | `ct_top.v:1444-1467`；filelist 363-366。 |
| `ct_top` 的 `ct_cp0_top` | `gen_rtl/cp0/rtl/ct_cp0_top.v` | 经 `ct_core.v:4488-4708`；filelist 43-46。 |
| IFU/IDU/IU/LSU/RTU/VFPU | `gen_rtl/ifu`、`idu`、`iu`、`lsu`、`rtu`、`vfpu` 等 | `ct_core.v` 七个实例位置；filelist 列出对应实现，CPU 目录不重复定义这些 module。 |
| `ct_ciu_top` | `gen_rtl/ciu/rtl` | `openC910.v:1002-1356`；filelist 17-38 及 47-53。 |
| `ct_l2c_top` | `gen_rtl/l2c/rtl` | `openC910.v:1374-1489`；filelist 中 L2 实现及 RAM 条目。 |
| `ct_clint_top` | `gen_rtl/clint/rtl` | `openC910.v:1499-1524`；filelist 39-40。 |
| `plic_top` | `gen_rtl/plic/rtl` | `openC910.v:1533-1555`；filelist 中 PLIC/APB 依赖及 `gen_rtl/plic/rtl/plic_top.v`。 |
| `ct_mp_clk_top` / `ct_clk_top` | `gen_rtl/clk/rtl` | `openC910.v:1611-1637`、`ct_top.v:2013-2024`；filelist 41、354。 |
| `ct_mp_rst_top` / `ct_rst_top` | `gen_rtl/rst/rtl` | `openC910.v:1584-1603`、`ct_top.v:1993-2006`；filelist 355、369。 |
| `ct_had_common_top` / `ct_had_private_top` | `gen_rtl/had/rtl` | `openC910.v:1712-1749`、`ct_top.v:1709-1853`；具体实现不在 CPU 目录。 |

边界结论：CPU 目录负责“顶层壳、core 级连线、系统 I/O 和构建配置”，并不包含 AXI/BIU、CIU、L2、CLINT、PLIC、MMU、PMP、时钟复位、HAD 或各执行单元的具体实现。`ct_core` 虽然把这些单元的端口全部汇聚在一个大 module 中，但实际功能仍由其他目录的实例提供。

## 9. 不确定项和阅读限制

1. `&Depend`、`&ConnRule`、`&Instance`、`&Ports` 是生成器风格注释/元指令。当前报告以同文件中的真实 Verilog 实例为准；仅有注释而没有真实实例的 core2/core3、`ct_ciu_bus_io` 和 `ct_top_uvc*` 不计为当前综合层次。
2. `ct_ciu_top` 的 APB 地址译码、BIU 聚合、L2 一致性协议，以及 `ct_mp_clk_top`/`ct_mp_rst_top`/`ct_had_common_top` 的具体内部实现位于其他目录；本报告只确认 CPU 目录中它们的实例端口和连接，未将外部模块内部行为冒充为本目录证据。
3. `cpu_cfig.h` 的宏在 filelist 中首先列出，但仓库内没有完整的 Vivado/仿真命令行或工程属性文件来证明是否有外部宏覆盖。因此“当前配置”指按本地头文件和本地 Verilog 条件/实例所能确认的默认构建；实际工程若追加宏定义，应重新预处理核对。
4. `top_golden_port.v` 和 `mp_top_golden_port.v` 的命名来自 `.v` 文件，但 `&Depend` 注释使用 `.vp` 后缀，这是生成/比较流程的文件名约定差异；本目录中实际存在并被 filelist 列出的文件是 `.v` 版本（`C910_asic_rtl.fl:471`、`485`）。
