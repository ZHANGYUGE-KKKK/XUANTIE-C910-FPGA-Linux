# FMC_HPC1 引脚方案验证记录

完成时间：2026-10-04 01:27:18（本机时间）。工具：Vivado 2020.2，Build 3064766，Windows。器件：xcvu9p-flga2104-2L-e。

## 验证对象与范围

验证顶层为 `validate_pinout_top`，沿用正式 wrapper 的全部 60 个顶层 I/O bit，并使用实际 DDR3 MIG PHY、校准逻辑及其生成约束。50 根 DDR3 信号在 J2 FMC_HPC1 的 Bank 66/67；2 根系统参考输入为 Bank 66 AY9/BA9，对应 J2 G6/G7。UART、复位及 C910 PL JTAG 的原有引脚保留。

隔离生成的 MIG 参数为 MT41K512M16HA-125、DDR3 1.5 V、x16、AXI 128 bit/30 bit address/1 bit ID、tCK=1250 ps（1600 MT/s）、参考输入=4000 ps（250 MHz）、System_Clock=No_Buffer、CL=11/CWL=8、Internal_Vref=true。自动生成的 MMCM 参数适用于 250 MHz；未沿用正式工程旧的 75 MHz MMCM 配置。

最终布局布线从已生成且优化完成的隔离 MIG checkpoint 继续执行；重新读取最终工程 XDC，把候选参考输入 G2/G3 改为 G6/G7 后，完整执行 place_design、route_design、默认 DRC、IO/时序报告和 bitstream_checks DRC。50 根 DDR3 信号的分配没有改变。最终执行日志见 [vivado_final.log](vivado_final.log)；重新从源生成的脚本位于上级目录。

## 最终结果

- place_design、route_design 均成功，日志返回码均为 0。
- [route_status.rpt](route_status.rpt)：22133 个可布线网络全部布通，routing errors=0。
- [drc_post_route.rpt](drc_post_route.rpt) 与 [drc_bitstream.rpt](drc_bitstream.rpt)：均为 0 Error、0 Critical Warning；有 1 条 RTSTAT-10 普通 Warning，涉及 MIG 内部无可布线负载的网络，未屏蔽它。
- [io_post_route.rpt](io_post_route.rpt)：最终实物引脚与 pinmap.json 的 50 根 DDR3 + 2 根参考时钟对应。
- [timing_post_route.rpt](timing_post_route.rpt)：WNS=1.156 ns、WHS=0.010 ns、WPWS=0.143 ns，TNS/THS/TPWS 均为 0。此结论仅覆盖本隔离顶层中已约束的路径。
- 未修改 DDR DRC 严重性，没有 DDR CLOCK_DEDICATED_ROUTE FALSE 豁免。原 XDC 中独立的低速 C910 JTAG 时钟布线例外保留，不是 DDR 检查的例外。

最终日志另有 Common 17-741 的环境级 Critical Warning：本机 Tcl Store 目录无写权限、退回安装目录。它不是设计 DRC 违规，且未阻止布局布线；这里的“0 Critical Warning”仅指所列最终设计 DRC 报告，不表示整个日志没有严重警告。

报告中的旧 tmp 路径是生成时的路径，报告原文未改写。保留这些报告与最终日志；失败候选、临时 IP、checkpoint 与原理图截图在整理后清理，均可通过上级目录脚本重新生成。

## 不包含的验证

正式工程 MIG 的输入周期仍为 13334 ps，未改 BD/XCI、未重新生成正式 IP，也未验证整个 C910 SoC 的实现。该参数必须与最终 250 MHz 参考输入同步后，才能要求正式工程通过相应时钟检查。

没有生成 bitstream、下载硬件、测量实际 VADJ/DRAM 电压、验证外部参考时钟、测试 DDR 校准或读写，也没有完成转接板 SI/时延预算。本记录不能作为板级功能通过或 PCB 可投板的证明。尤其 VADJ 调为 1.5 V 后，共用该电源的原 1.8 V FMC JTAG 仍须单独处理。

## 验证输入校验值

SHA-256（最终归档时）：

```text
VCU118.xdc
B062BC6CFAAF9C73D5540BA5E280FB72E7D1B1E570936B1D3355CF980728F62B
pinmap.json
F58E904E2F9D72E4C39F7233B59F1D3AC1655915242FC1DE91AC823760C5B7B2
```

上级目录 verify_pinmap.ps1 还检查了真实 wrapper、工程 XDC、官方 VCU118 XDC 的网络/Bank/引脚功能一致性及 52 个 DDR/时钟 FPGA 引脚无碰撞。原理图对照另确认了母板 52 个接点与子板 50 个信号接点；详细连线与电源注意事项见上级 README。
