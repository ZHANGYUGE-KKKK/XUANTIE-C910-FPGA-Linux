# Revision B 参考时钟纠正 - 本次只读/生成验证记录

2026-10-04，Vivado 2020.2，xcvu9p-flga2104-2L-e。

本次修改 XDC 和 BD 的参考路径，保持 MIG 250 MHz 配置和全部 50 根 DDR 引脚。没有调用综合、优化、布局布线、bitstream 或硬件编程。本文不是新方案物理 DRC 通过报告。

## 器件位置查询

使用 in-memory project、design_mode=PinPlanning、open_io_design，查询 package pin -> IOB site -> clock region / SLR。可用本目录 query_device_clock.tcl 复查，不包含综合命令。

| 球号 | Bank | IOB site | Clock region | SLR | 用途 |
| --- | --- | --- | --- | --- | --- |
| E12 / D12 | 71 | IOB_X1Y650 / 651 | X4Y12 | SLR2 | 原固定 250 MHz，不用于本组 MIG |
| AW26 / AW27 | 41 | IOB_X0Y130 / 131 | X2Y2 | SLR0 | 另一固定 250 MHz，不用于本组 MIG |
| AW23 / AW22 | 64 | IOB_X1Y283 / 284 | X4Y5 | SLR1 | 新板载 U18/Q2 参考输入 |
| AY9 / BA9 | 66 | IOB_X1Y390 / 391 | X4Y7 | SLR1 | 旧 FMC G6/G7 输入，已停用 |
| BC9 / BC8 | 66 | IOB_X1Y387 / 388 | X4Y7 | SLR1 | CK 输出保持不变 |
| AW12 | 67 | IOB_X1Y418 | X4Y8 | SLR1 | 低字节代表针 |
| AJ13 | 67 | IOB_X1Y461 | X4Y8 | SLR1 | 高字节 DQS_P |

X4Y5 实际存在 BUFGCE_X1Y120..143，XDC 选择 Y120。此查询证明器件位置，不证明放置/布线或 BUFG 资源无竞争。

## BD 与参数核对

- 新 RTL board_sysclk_bufg.v 只实例化一个 BUFG，不含 PLL/MMCM，不变换频率。
- util_ds_buf_0/IBUF_OUT -> board_sysclk_bufg_0/clk_in。
- board_sysclk_bufg_0/clk_out -> DDR3/c0_sys_clk_i 与 clk_wiz/clk_in1。
- validate_bd_design、save_bd_design、generate_target all 成功返回；生成 C910_SOC.v 已确认同一缓冲网络驱动两者。
- 生成的 module_ref wrapper 使用 board_sysclk_bufg inst，原语位于实例层级下 clk_bufg；XDC 以层级匹配查找，找不到/不唯一即报错。没有新综合网表，因此该约束尚未在最终网表求值。
- 与本次修改前 Git HEAD 作语义比较：MIG XCI 的 328 个 configurableElementValue 不变（除 boundaryDescription 结构/元数据）；BD DDR3 和 clk_wiz 的配置值差异均为 0；BD addressing 和顶层 ports 不变。
- verify_pinmap.ps1 检查 wrapper、XDC、官方母板 XDC、参考输入、BUFG 连接、全部 800 接点网表及原始母板地针。
- PDF 11 页已渲染逐页核图，字体嵌入；图纸/网表由同一 pinmap.json 生成，网表带源文件 SHA256。

BD 警告仍包含原有 BRAM_PORTA 未接以及 C910 aclk PHASE 参数传播提示；另有本机 Tcl Store 权限/长路径提示。未声称无警告，也未修改无关逻辑。

## 硬件操作与后续验证边界

J8 插上，U18 上电后通过 SCUI Si570_0 设置 250 MHz；本次未执行。母板 Bank64 参考接收端已有终端。转接板没有参考输入电路，J1 G6/G7 NC。

以后另获授权再验证整个 SoC 的综合/实现，包括新 BUFG 的定位、BACKBONE、MIG 专用时钟、共享 VADJ 与 JTAG。历史 revision A 报告不可代替本次新时钟路径验证。1600 MT/s 稳定性还需要实际电源/复位和三板全链路 SI/延迟/校准读写测试。
