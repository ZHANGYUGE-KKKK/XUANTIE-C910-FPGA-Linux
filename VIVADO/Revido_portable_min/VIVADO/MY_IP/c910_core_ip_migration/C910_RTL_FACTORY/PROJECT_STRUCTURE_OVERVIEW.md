# C910 RTL Factory 当前结构概览

本文档用于快速说明当前工程 RTL 的组织方式和 `openC910` 顶层结构。当前工程入口以 `gen_rtl/cpu/rtl/openC910.v` 为主。

## 工程入口

- `gen_rtl/cpu/rtl/openC910.v`：当前 SoC/CPU cluster 顶层封装。
- `gen_rtl/cpu/rtl/cpu_cfig.h`：CPU 特性、cache、PLIC、processor 数量等编译宏配置。
- `gen_rtl/filelists/C910_asic_rtl.fl`：主要 RTL filelist。
- `setup/setup.csh`：工程环境变量设置脚本。

## 当前处理器配置

当前工程按单 hart / 单 core 顶层使用：

- `cpu_cfig.h` 中启用 `PROCESSOR_0`。
- `MULTI_PROCESSING` 未启用。
- `PROCESSOR_1` 未启用。
- `PLIC_HART_NUM` 在当前配置下解析为 `5'h1`。

因此，从 `openC910` 对外接口和 CPU 实例来看，当前顶层只暴露并使用 core0。

## openC910 顶层结构

当前 `openC910` 由一个有效 CPU core 和若干 cluster 级共享模块组成：

```text
openC910
  |
  +-- ct_top x_ct_top_0          core0 CPU 顶层
  |
  +-- ct_ciu_top                 cluster interconnect / 外部 AXI / APB 通路
  +-- ct_l2c_top                 L2 cache
  +-- ct_clint_top               timer/software interrupt
  +-- plic_top                   external interrupt controller
  +-- ct_mp_rst_top              reset 生成
  +-- ct_mp_clk_top              clock 生成
  +-- ct_sysio_top               system IO glue logic
  +-- ct_had_common_top          JTAG / HAD debug common logic
  +-- ct_rmu_top_dummy           reset management dummy block
```

其中 `ct_top x_ct_top_0` 是当前唯一有效的 CPU core 实例。core0 通过 BIU/IBIU 信号接入 `ct_ciu_top`，再访问 L2 cache、APB 外设和外部 AXI 总线。

## 对外接口

`openC910` 当前主要对外暴露以下接口：

- AXI master 总线接口：`biu_pad_*` / `pad_biu_*`
- core0 运行状态接口：`core0_pad_jdb_pm`、`core0_pad_lpmd_b`、`core0_pad_mstatus`、`core0_pad_retire*`
- core0 控制输入：`pad_core0_dbg_mask`、`pad_core0_dbgrq_b`、`pad_core0_hartid`、`pad_core0_rst_b`、`pad_core0_rvba`
- JTAG/HAD 调试接口：`pad_had_jtg_*`、`had_pad_jtg_*`
- PLIC 外部中断输入：`pad_plic_int_vld`、`pad_plic_int_cfg`
- 系统控制输入：`pad_cpu_apb_base`、`pad_cpu_sys_cnt`、`pad_cpu_l2cache_flush_req`
- reset / clock / scan / MBIST / DFT 相关信号

当前顶层对外不再暴露 core1 pad 接口。

## 当前内部连接特点

虽然顶层对外是单 core，且只实例化 core0，但部分 cluster 级子模块仍保持原有多核接口形态。为了维持这些模块的连接完整性，`openC910` 内部仍保留若干 core1/IBIU1/PIU1 兼容信号。

这些信号当前主要用于连接保留的双核风格子模块接口，未对应实际的 core1 CPU 实例：

- `ibiu1_*` 请求侧信号在顶层被绑为无请求状态。
- `pad_core1_*` 内部控制信号被绑为固定值。
- `plic_core1_*` 中断在顶层被固定为无效。
- `cpu_debug_port` 只由 core0 no-retire 状态产生。
- `ct_sysio_top`、`ct_had_common_top`、`ct_mp_rst_top`、`ct_mp_clk_top`、`ct_ciu_top` 内部仍可见 core1/PIU1 风格接口。

因此，当前结构可以理解为：

```text
单 core0 顶层接口
  +
单 active ct_top core0
  +
尚未完全裁剪的 cluster 级兼容壳
```

## 主要子模块职责

### ct_top

`ct_top` 是单个 C910 CPU core 的顶层封装。当前 `openC910` 中只实例化 `x_ct_top_0`。

它内部包含 CPU pipeline、MMU、PMP、BIU、private HAD、PMU、core reset/clock 等 core 级逻辑。

### ct_ciu_top

`ct_ciu_top` 负责 core 侧访问请求、L2 cache、APB 外设和外部 AXI 总线之间的互连。当前 core0 通过 `ibiu0_*` 接入 CIU。

CIU 内部仍保留 `ibiu1_*` / `pad_ibiu1_*` 形式的兼容接口，但当前没有实际 core1 请求源。

### ct_l2c_top

`ct_l2c_top` 是 L2 cache 顶层。当前 L2 cache banking 尚未按单核重新裁剪，仍保持现有 L2 结构。

### ct_clint_top

`ct_clint_top` 提供 timer/software interrupt。当前有效中断最终只送往 core0；模块内部的 hart1 相关结构尚未进一步面积优化。

### plic_top

`plic_top` 负责外部中断仲裁和分发。当前 `HART_NUM` 配置为 1，顶层只使用 hart0 的 machine/supervisor interrupt 输出。

### ct_sysio_top

`ct_sysio_top` 汇总系统控制信号，包括 debug request、interrupt 分发、L2 flush、系统时间、APB base 等。

当前它仍保留 PIU1/core1 风格端口，但对实际顶层功能来说只有 core0 路径有效。

### ct_had_common_top

`ct_had_common_top` 是公共 JTAG/HAD debug 模块。当前 core0 debug 路径有效，core1 debug 相关端口仍作为内部兼容连接存在。

### ct_mp_rst_top / ct_mp_clk_top

`ct_mp_rst_top` 生成 CPU、APB、JTAG、core reset 等复位信号。

`ct_mp_clk_top` 生成 CPU clock、APB clock、JTAG clock、L2 RAM clock 等时钟信号。

当前这两个模块仍保留 core1 相关内部端口。

## 目录职责

- `gen_rtl/cpu/rtl`：CPU 顶层、core 封装、系统 IO、配置头文件。
- `gen_rtl/ciu/rtl`：cluster interconnect 和一致性/访问通路相关逻辑。
- `gen_rtl/l2c/rtl`：L2 cache。
- `gen_rtl/clint/rtl`：CLINT timer/software interrupt。
- `gen_rtl/plic/rtl`：PLIC external interrupt controller。
- `gen_rtl/had/rtl`：JTAG/HAD debug。
- `gen_rtl/rst/rtl`：reset 逻辑。
- `gen_rtl/clk/rtl`：clock 逻辑。
- `gen_rtl/common/rtl`：通用基础模块。
- `gen_rtl/fpga/rtl`：FPGA RAM wrapper。
- `gen_rtl/filelists`：RTL filelist。

## 后续面积优化入口

当前进一步裁剪冗余双核逻辑的待办项记录在：

- `SINGLE_CORE_AREA_OPTIMIZATION_TODO.md`

该表用于后续逐项维护 reset、clock、CLINT、SYSIO、HAD、CIU 和可选 L2C bank 优化状态。
