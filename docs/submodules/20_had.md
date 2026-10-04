# HAD（硬件调试）子系统

## 1. 范围与结论

本文档依据 `gen_rtl/had/rtl` 下的 22 个 Verilog 文件逐一阅读，并向上追踪到 `openC910`、`ct_top`、`ct_core`、CP0/RTU/IFU/IDU/LSU、CIU/L2C、SYSIO、时钟/复位及 JTAG pad。文中行号以当前工作区文件为准；“未确认”表示 RTL 中只有生成器注释、被注释掉的实例，或当前构建将功能常量化，不能据此推断完整实现。

当前真实层次为：

```text
openC910
├─ x_ct_top_0                         gen_rtl/cpu/rtl/openC910.v:689-695
│  ├─ x_ct_core                       gen_rtl/cpu/rtl/ct_top.v:845-849
│  │  ├─ x_ct_ifu_top / x_ct_idu_top  gen_rtl/cpu/rtl/ct_core.v:2476-2480,2682-2686
│  │  ├─ x_ct_iu_top / x_ct_lsu_top   gen_rtl/cpu/rtl/ct_core.v:3472-3473,3981-3985
│  │  ├─ x_ct_cp0_top / x_ct_rtu_top  gen_rtl/cpu/rtl/ct_core.v:4484-4488,4710-4714
│  │  └─ HAD private                   ct_top.v:1705-1709
│  ├─ x_ct_ciu_top / x_ct_l2c_top      openC910.v:971-1002,1371-1374
│  ├─ x_ct_sysio_top                   openC910.v:1640-1644
│  ├─ x_ct_mp_rst_top / x_ct_mp_clk_top openC910.v:1580-1611
│  └─ HAD common/JTAG                  openC910.v:1707-1712
└─ core1 的 HAD/调试输入输出在当前 openC910 构建中被常量禁用
   openC910.v:880-896
```

HAD 分成两部分：

- `ct_had_common_top` 是芯片级 JTAG/TAP、串行链、HACR 的公共选择、公共寄存器和跨核事件/公共 debug-info 通道；它在 `openC910` 直接连接 JTAG pad、`forever_jtgclk`、SYSIO mask、CIU/L2C debug-info。
- `ct_had_private_top` 是单个 core 的调试执行单元；它实例化断点、控制、DDC、PCFIFO、HAD 寄存器、trace、event、debug-info、非 IRV 断点和私有 IR 解码，并把请求/配置/调试数据接到 `ct_core`。

## 2. 芯片级连接与时钟/复位

### 2.1 JTAG、时钟和复位

`openC910` 的顶层端口包含 `had_pad_jtg_tdo`、`had_pad_jtg_tdo_en` 以及 `pad_had_jtg_tclk/tdi/tms/trst_b`（`gen_rtl/cpu/rtl/openC910.v:72-98,126-138,188-189`）。JTAG 公共顶层连接如下：

- `pad_had_jtg_tdi/tms` 进入 `ct_had_common_top`，`had_pad_jtg_tdo/tdo_en` 返回顶层；`tclk` 使用 `forever_jtgclk`，不是 core 的 `forever_coreclk`（`openC910.v:1711-1748`）。
- `ct_mp_clk_top` 直接把 `pad_had_jtg_tclk` 赋给 `forever_jtgclk`（`gen_rtl/clk/rtl/ct_mp_clk_top.v:137`）。
- `ct_mp_rst_top` 用 `pad_had_jtg_trst_b` 与 MBIST 条件形成 `async_trst_b`，在 `forever_jtgclk` 域同步产生 `trst_b`（`gen_rtl/rst/rtl/ct_mp_rst_top.v:181-216`）。`cpurst_b`、各 core reset 和 JTAG reset 由同一个 reset top 汇聚（`openC910.v:1584-1602`）。
- CPU 域的 JTAG `UPDATE_IR/UPDATE_DR` 不能直接当作 core-clock 脉冲使用：`ct_had_sm` 对 `UPDATE_IR` 实例化 `ct_had_sync_3flop`，从 `tclk` 域传到 `forever_cpuclk` 域；DR 的实际 CPU 域同步由 `ct_had_private_ir` 内的 `sync_level2pulse` 完成（`ct_had_sm.v:255-271`、`ct_had_private_ir.v:170-207`）。

### 2.2 CIU、L2C、SYSIO

- `ct_ciu_top` 输出 `ciu_had_dbg_info[292:0]` 和 `l2c_had_dbg_info[43:0]`（`gen_rtl/ciu/rtl/ct_ciu_top.v:603,652`），并在末尾分别转发 `ciu_dbg_info`、`l2c_ciu_dbg_info`（`ct_ciu_top.v:4130-4132`）。
- `ct_l2c_top` 的 `l2c_had_dbg_info` 在 `openC910` 接到同名公共线（`openC910.v:1373-1374` 及 `1230-1237`），随后进入 `ct_had_common_dbg_info`（`ct_had_common_top.v:309-320`）。
- `ct_sysio_top` 输出 `sysio_had_dbg_mask`，并在 `openC910` 连接公共 HAD（`openC910.v:1643-1686,1746`）。公共寄存器把 mask 低两位分别输出为 `core0_had_dbg_mask/core1_had_dbg_mask`，DMS 读数为 mask 与 TEE mask 的组合；当前 TEE mask 被置零（`ct_had_common_regs.v:108-114,163-178`）。

## 3. 公共 HAD/JTAG 链

### 3.1 `ct_had_common_top.v`

职责：公共 JTAG 组合顶层，汇聚 TAP、串行移位、公共/私有 IR 选择、公共寄存器、公共 debug-info 和 ETM 事件；APB trace busif 当前未实例化。

- 实例化 `ct_had_sm`、`ct_had_io`、`ct_had_serial`、`ct_had_ir`、`ct_had_etm`、`ct_had_common_regs`、`ct_had_common_dbg_info`，分别见 `ct_had_common_top.v:171-320`。
- `ct_had_io` 将 pad TDI 直通串行链，将串行 TDO 和 TDO enable 返回 pad，并把 `io_sm_tap_en` 固定为 1（`ct_had_common_top.v:193-202`、`ct_had_io.v:48-71`）。
- `common_regs_data`、core0/core1 私有串行数据回到 `ct_had_ir`；公共顶层向外输出 HACR 解码后的 `ir_corex_wdata` 与 core select（`ct_had_common_top.v:234-271`）。
- 注释中的 `ct_had_pctrace_busif` 没有实际实例；`pready_had=1`、`perr_had=0`、`prdata_had=0`（`ct_had_common_top.v:323-335`）。因此 APB trace 端口目前是 tie-off，不能视作已实现的 APB trace 通道。

### 3.2 `ct_had_sm.v` 与 `ct_had_sync_3flop.v`

`ct_had_sm` 实现 JTAG-5 TAP 状态机：

- 6 位状态编码包含 RESET/IDLE、DR/IR capture/shift/update、pause/exit（`ct_had_sm.v:98-118`）；状态在 `posedge tclk`、`negedge trst_b` 下复位（`ct_had_sm.v:120-127`），下一状态由 TMS 决定（`ct_had_sm.v:129-219`）。
- `sm5_shift_ir/dr`、`sm5_capture_dr` 与 `sm5_update_ir/dr` 是 TAP 状态译码（`ct_had_sm.v:221-228`）；串行 capture/shift 直接在 tclk 域产生（`ct_had_sm.v:246-253`）。
- TDO 仅在 DR shift 且 HACR 指示读时使能；TDO enable 在 tclk 下降沿寄存（`ct_had_sm.v:230-243`）。`sm_xx_write_en = !ir_sm_hacr_rw`，即 HACR bit15 决定读写方向（`ct_had_sm.v:309-320`）。
- `ct_had_sync_3flop` 是慢 `clk2` 到快 `clk1` 的一次脉冲同步器：输入在 clk2 采样，clk1 侧三级采样并用末两级边沿产生 pulse（`ct_had_sync_3flop.v:50-89`）。

### 3.3 `ct_had_io.v`、`ct_had_serial.v`

- `ct_had_io` 不做 JTAG 协议状态处理，只做 TDI/TDO/TDO enable 线路选择；`io_sm_tap_en` 固定为 1（`ct_had_io.v:48-71`）。
- `ct_had_serial` 在 DR capture 时装载 `regs_serial_data`，在 shift 时从最低位移入 TDI；8/16/32/64 位宽由寄存器选择决定，64 位项包括 PCFIFO、BABA/BABB、WBBR、PC、DADDR/DDATA 和两个 debug FIFO（`ct_had_serial.v:123-154,156-185`）。
- 读 DR 时在 tclk 上升沿累积 parity，并在下降沿把 shifter bit0 驱动 TDO；复位时 TDO 为 1（`ct_had_serial.v:187-220`）。

### 3.4 `ct_had_ir.v`：公共 HACR 与 bank/index 解码

- HACR 在 gated `ir_clk` 上更新；初值由 `sm_ir_update_hacr` 触发，数据来自串行链 `serial_xx_data`（`ct_had_ir.v:156-189`）。
- HACR[1:0] 选择 core0..3；再由 HACR[6:4] 选择 bank、[12:8] 选择 index。当前 core2/core3 的私有数据为 0，core debug disable 也固定为 0（`ct_had_ir.v:191-224`）。
- bank0 index：ID=2、OTC=3、MBCA=4、MBCB=5、PCFIFO=6、BABA=7、BABB=8、BAMA=9、BAMB=10、WBBR=17、PC=19、CSR=21、DADDR=24、DDATA=25；bank2：DBGFIFO=4、PIPEFIFO=5；bank3：DBGFIFO2=0、RSR=1、DMS=2（`ct_had_ir.v:242-285`）。
- 读 FIFO 的 pulse 由私有 HACR read bit、对应选择和上一拍 HACR update 生成；DR 写使能为 `update_dr_ff1 & !hacr_rw & core_sel`（`ct_had_private_ir.v:317-327`）。公共 core/private 数据 mux 在 `ct_had_ir.v:220-235`。

### 3.5 `ct_had_common_regs.v`、`ct_had_common_dbg_info.v`

- `ct_had_common_regs` 提供 RSR、HAD ID、DMS。RSR 反映 core0/core1 reset，core2/core3 常量为 1；HAD ID 声明 CSKY V3、DDC、两个 breakpoint、版本字段（`ct_had_common_regs.v:83-161`）。
- 公共读 mux 选择 DBGFIFO2、RSR、ID、DMS（`ct_had_common_regs.v:171-178`）。
- `ct_had_common_dbg_info` 将 `ciu_had_dbg_info[292:0]` 与 `l2c_had_dbg_info[43:0]` 拼成 337 位记录（`ct_had_common_dbg_info.v:166-184`），在 core0/core1 debug-ack-PC 上升沿记录；core2/core3 ack 当前强制为 0（`ct_had_common_dbg_info.v:71-114,154-179`）。
- 记录按 6 个 64 位槽读出，最后一个槽只有低 24 位有效；读指针达到深度 6 后回零，gated clock 的使能覆盖读、ack 和回绕条件（`ct_had_common_dbg_info.v:117-149,188-216`）。

### 3.6 `ct_had_etm.v`、`ct_had_etm_if.v`

- `ct_had_etm` 为 core0/core1 建立 event enter/exit 的接口实例；core2/core3 接口也被写出但其 event clock enable 和输出寄存器强制为 0（`ct_had_etm.v:84-143`）。四个 `core*_tee` 均为 0（`ct_had_etm.v:146-149`）。
- core0/core1 的 enter/exit 请求经过组合 mux 汇聚，event clock enable 为各 core enable 的 OR，并经 gated clock 生成 event_clk（`ct_had_etm.v:151-214`）。
- `ct_had_etm_if` 在 event_clk 域寄存输入/输出请求，并以所有请求及其寄存值的 OR 产生 `x_event_clk_en`（`ct_had_etm_if.v:78-115`）；注释中的 `sync_level2pulse` 被普通 always 逻辑替代，不能假设存在额外 handshake。

## 4. 单 core 私有 HAD

### 4.1 `ct_had_private_top.v`

这是 core 级 HAD 的真实组合顶层。模块端口表明确包含 CP0、IFU、IDU、LSU、MMU、RTU、JTAG IR update、event 请求、PCFIFO retire 信息以及输出到 IFU/IDU/LSU/RTU/CP0 的调试控制（`ct_had_private_top.v:17-161,163-306`）。实例树如下：

| 实例 | 职责 | 证据 |
|---|---|---|
| `x_ct_had_bkpta` / `x_ct_had_bkptb` | 两个相同结构的内存/指令断点通道，分别接 MBCA/MBCB、BC[A/B]、RTU A/B 触发与 ack | `ct_had_private_top.v:543-635` |
| `x_ct_had_ctrl` | 汇聚寄存器、断点、trace、event、JTAG 命令，生成 RTU/IFU/CP0 控制及 HSR 更新脉冲 | `ct_had_private_top.v:637-734` |
| `x_ct_had_ddc_ctrl` / `x_ct_had_ddc_dp` | DDC 地址/数据/伪指令状态机与数据通路 | `ct_had_private_top.v:736-768` |
| `x_ct_had_pcfifo` | 分支/跳转目标 PC FIFO | `ct_had_private_top.v:770-784` |
| `x_ct_had_regs` | CPUSCR/HCR/HSR、断点基址/掩码、WBBR/PC/IR/CSR、event enable 和串行读 mux | `ct_had_private_top.v:786-890` |
| `x_ct_had_trace` | OTC 计数器和 trace debug request | `ct_had_private_top.v:892-906` |
| `x_ct_had_event` | debug enter/exit event 输入输出及 core-clock 域处理 | `ct_had_private_top.v:908-927` |
| `x_ct_had_dbg_info` | IFU/IDU/LSU/IU/CP0/RTU/MMU debug-info、PIPESEL/PIPEFIFO/DBGFIFO | `ct_had_private_top.v:929-970` |
| `x_ct_had_nirv_bkpt` | 非 IRV breakpoint 汇聚与 split 指令挂起 | `ct_had_private_top.v:972-990` |
| `x_ct_had_private_ir` | core 选择后的 bank/index 解码、IR/DR 跨域和 FIFO read pulse | `ct_had_private_top.v:992-1034` |

文件末尾原本预留 `ct_had_pctrace_top`，但只有注释，没有实际实例；`had_lsu_pctrace_en` 和 `had_lsu_bus_trace_en` 都被置 0，实际 LSU debug enable 只来自 `had_lsu_dbg_info_en`（`ct_had_private_top.v:1037-1072`）。

### 4.2 `ct_had_private_ir.v`

- `sm_update_ir`、`sm_update_dr` 通过两个 `sync_level2pulse` 进入 `forever_coreclk`，再在 `cpuclk` 域打一拍；当 `ctrl_xx_dbg_disable` 置位时，IR/DR update 被屏蔽（`ct_had_private_ir.v:170-219`）。
- HACR 复位为 `16'h8200`，即默认指向 HAD_ID；bit15=读写、bit14=GO、bit13=EX、bit[12:8]=index、bit[6:4]=bank、bit[1:0]=coreid（`ct_had_private_ir.v:221-269`）。
- bank0 包含 ID/OTC/MBCA/MBCB/PCFIFO/BABA/BABB/BAMA/BAMB/BYPASS/HCR/HSR/WBBR/PSR/PC/IR/CSR/DADDR/DDATA；bank1 的 MBIR index=27；bank2 包含 EVENT_OE/EVENT_IE/DBGFIFO/PIPEFIFO/PIPESEL（`ct_had_private_ir.v:234-305`）。
- `x_ir_ctrl_*_read_pulse` 只在 read+对应选择+HACR update+core select 时产生；`ir_ctrl_exit_dbg_reg` 覆盖 WBBR/PC/IR/CSR/BYPASS，供退出 debug 判断；HAD clock enable 来自 IR/DR update raw pulse（`ct_had_private_ir.v:317-335`）。

### 4.3 `ct_had_regs.v`：寄存器、状态与串行读数据

- CPUSCR 写入 BABA/BABB、BAMA/BAMB、EVENT_OE/IE、WBBR、PC、IR、CSR；HCR 写入字段包括 NICVEN、ADR、DDCEN、SQC、DR、IDRE、TME、FRZC、RC[B/A]、BC[B/A]（`ct_had_regs.v:443-613,615-655`）。
- HSR 在 RTU debug-ack-PC 时锁存 inst-not-wb、ROB/IQ 状态、IDU stall、bus/IFU/exe dead；PS 表示 CPU idle/busy，ADRO/DRO/MBO/SWO/TO/FRZO/SQB/SQA/PRO 按控制脉冲置位、退出 debug 清零（`ct_had_regs.v:660-852`）。HSR 拼接布局在 `ct_had_regs.v:833-836`。
- HCR 对外控制：ADR[21]、DDCEN[20]、SQC[17:16]、DR[15]、TME[13]、FRZC[12]、BCB[10:6]、BCA[4:0]，NIRVEN[31]（`ct_had_regs.v:877-896`）。
- BABA/BABB 及 BAMA/BAMB、RC 输出到 IFU/LSU/RTU（`ct_had_regs.v:921-934`）；WBBR 在 debug mode 且 FFY 时向 IDU 提供写回数据（`ct_had_regs.v:864-869`）。
- 串行读 mux 覆盖 ID/OTC/MBCA/MBCB/PCFIFO/BABA/BABB/BAMA/BAMB/WBBR/PC/IR/CSR/HCR/HSR/MBIR/DADDR/DDATA/EVENT/DBGFIFO/PIPEFIFO/PIPESEL（`ct_had_regs.v:943-974`）。

### 4.4 `ct_had_ctrl.v`：请求优先级、进入/退出 debug 和时钟

- MBCA 只要 BCA 非零即使能；MBCB 还受 SQC[1] 和 SQA 条件控制，并寄存为 `ctrl_bkptb_en`；trace 受 TME 和 SQC[0]/SQB 条件控制（`ct_had_ctrl.v:351-415`）。
- PCFIFO 写入要求未冻结、没有指令断点请求且不在 debug；PIPEFIFO 在非 debug 时写入，三个 FIFO 的读使能来自私有 IR pulse（`ct_had_ctrl.v:417-443`）。
- RTU 请求分三类：异步 `had_rtu_xx_jdbreq`、同步硬件 `had_rtu_hw_dbgreq`、内存断点/trace 请求；实际组合、FBD gating 和 raw request 见 `ct_had_ctrl.v:445-510`。
- `had_cp0_xx_dbg` 是硬件/指令断点/数据断点/trace/异步/event/非 IRV 请求的 OR，再屏蔽 debug-disable（`ct_had_ctrl.v:516-522`）；`had_rtu_pop1_disa`、`had_rtu_dbg_req_en`、`had_rtu_xx_tme` 控制 RTU 单条 retire 和请求采样（`ct_had_ctrl.v:524-543`）。
- HSR 更新优先级和 SQA/SQB/FRZO 更新在 `ct_had_ctrl.v:545-596`。退出 debug 由 TAP update-DR 且 GO+EX、选择 WBBR/PC/IR/CSR/BYPASS，或 event exit 触发；经一拍后产生 `ctrl_regs_exit_dbg`、`had_yy_xx_exit_dbg`、`had_ifu_pcload`（`ct_had_ctrl.v:598-629`）。
- GO 进入 debug 有普通 IR 通道和 DDC 伪指令通道，结果打一拍输出 `had_ifu_ir_vld`（`ct_had_ctrl.v:631-656`）。`x_had_dbg_mask` 在 `forever_coreclk` 域锁存成 debug-disable；HAD 顶层 clock enable 由 IR update/event request 及 PM=11 的保持寄存器组成（`ct_had_ctrl.v:669-704`）。

### 4.5 `ct_had_bkpt.v`、`ct_had_nirv_bkpt.v`

- `ct_had_bkpt` 的注释明确分四级：RTU/LSU 条件发生、HCR 类型过滤、计数器形成 request、`ct_had_ctrl` 做 SQC/最终 request（`ct_had_bkpt.v:141-161`）。它依据 priv mode 和 BC[4:0] 区分 change-flow/normal instruction/normal data/store/load breakpoint（`ct_had_bkpt.v:164-223`）。
- MBC 计数器可由 MBCA/MBCA 选中时写入，正常 retire 且未进入 debug 时递减；counter=0/1 用于处理同周期指令/数据断点 corner case（`ct_had_bkpt.v:225-306`）。split 指令的数据断点用 `data_bkpt_pending` 延后一拍，并在 flush/debug 清除（`ct_had_bkpt.v:308-322`）。
- `ct_had_nirv_bkpt` 从三个 retire slot 的四类 non-IRV 位中汇聚 A 类 bit[1:2]、B 类 bit[0:3]，按 BCA/BCB enable 选择；split 指令先挂起，非 split retire 后产生 `non_irv_bkpt_vld` 和 `nirv_bkpta`（`ct_had_nirv_bkpt.v:85-148`）。

### 4.6 `ct_had_pcfifo.v`

PCFIFO 是深度 16、每项 `PA_WIDTH`（通常 40）位的环形 FIFO，存储三路 retire slot 的 change-flow target PC：

- 三路输入先锁存 `chgflow_valid` 和 next PC；同周期可写 1/2/3 项，写指针按项数递增（`ct_had_pcfifo.v:95-178,239-261`）。
- `pcfifo_reg[15:0]` 在写使能和 one-hot 写指针下更新；读使能将当前 rptr 项送到 `pcfifo_dout`，MMU enable 时做符号扩展到 64 位（`ct_had_pcfifo.v:180-218`）。
- rptr 指向最老未读项；写满时创建新项会丢弃相应最老项，读空时允许 rptr/wptr 对齐推进，具体 empty/full/增量条件见 `ct_had_pcfifo.v:221-296`。

### 4.7 `ct_had_trace.v`

OTC 是 8 位 trace counter。有效 trace 条件为正常 retire、非 split、非 debug、trace enable；counter 非零且没有指令断点时递减，counter 为零且 trace 有效时输出 `trace_ctrl_req`（`ct_had_trace.v:67-123`）。OTC 可在 DR update 且选择 OTC 时写入，读出为 `trace_regs_otc`（`ct_had_trace.v:93-114`）。

### 4.8 `ct_had_event.v`

event 输入先在 `forever_coreclk` 域两级采样；enter enable 置起请求，进入 debug 后清除；exit enable 直接形成 event exit。输出 enter/exit 在 cpuclk 域寄存并按 output enable 发出（`ct_had_event.v:87-172`）。`event_ctrl_had_clk_en` 为同步后的 enter/exit 输入 OR，用于 HAD clock 保活（`ct_had_event.v:162-175`）。

### 4.9 `ct_had_ddc_ctrl.v`、`ct_had_ddc_dp.v`

- DDC controller 状态为 IDLE、ADDR_WAIT/LOAD、DATA_WAIT/LOAD、STW_WAIT/LOAD/FINISH、ADDR_GEN；地址读入后等待正常 retire，再装载数据或生成 store 相关动作（`ct_had_ddc_ctrl.v:74-171`）。
- `ddc_ctrl_dp_addr_sel/data_sel/stw_sel/addr_gen` 由状态译码，CSR/WBBR/IR update 脉冲由相应状态 OR 产生（`ct_had_ddc_ctrl.v:173-200`）。
- DDC datapath 保存 64 位 DADDR/DDATA；地址可由 scan chain 写入，也可在 `ADDR_GEN` 自增；WBBR 输出地址或数据，IR 输出地址加载指令或 `mv x2,x2`（`ct_had_ddc_dp.v:68-110`）。`ddc_regs_ffy` 在地址/数据 load 时置位。

### 4.10 `ct_had_dbg_info.v`

- PIPESEL 可写 0..3；1 选择 IDU、2 选择 RTU retire、3 选择 LSU store，并据此打开对应 debug-info enable（`ct_had_dbg_info.v:186-202`）。
- PIPEFIFO 深度 16、每项 64 位；IDU 三路数据为 40 位零扩展，RTU 为三路 64 位 retire info，LSU 为 store data、store address 两项（`ct_had_dbg_info.v:204-250`）。
- FIFO 满/空及一拍至三拍写入的指针维护在 `ct_had_dbg_info.v:257-365`；DBGFIFO 从 408 位 debug record 切成 7 个 64 位槽，最后一槽仅 24 位有效（`ct_had_dbg_info.v:368-398`）。
- DBGFIFO 记录拼接顺序为 MMU(34)、RTU(43)、CP0(4)、IU(10)、IDU(50)、LSU(184)、IFU(83)，总计 408 位；记录触发依据 `rtu_had_dbg_ack_info` 延迟一拍（`ct_had_dbg_info.v:401-446`）。

## 5. `ct_top`/`ct_core` 真实对接

### 5.1 `ct_top` 与 `ct_core`

`ct_top` 的 `x_ct_core` 同时接入 CP0 HAD 输出、HAD 对 IFU/IDU/LSU/RTU 的控制、断点基址/掩码、debug-info 和 RTU 返回信号（`gen_rtl/cpu/rtl/ct_top.v:849-965,1206-1256`）。同一个 `ct_top` 实例化 `ct_had_private_top`，其 `cpuclk` 使用 `forever_coreclk`、`cpurst_b` 使用 `had_rst_b`（`ct_top.v:1705-1720,1855-1856`）。

在 `ct_core` 内：

- IFU 接收 `had_ifu_ir/ir_vld/pc/pcload`、`had_rtu_xx_jdbreq` 和两组断点配置，并回送 IFU debug-info/no-op/reset-on（`gen_rtl/cpu/rtl/ct_core.v:2479-2533,2557-2560`）。
- IDU 接收 WBBR 数据/valid 和 ID debug enable，并回送三路 ID info、WB data/valid、IQ/pipeline 状态（`ct_core.v:2685-2731`）。
- LSU 接收 bus/debug enable 与两组基址/掩码/RC，并回送 load/store、no-op 和 184 位 debug-info（`ct_core.v:3984-4048,4216-4227`）。
- CP0 输出 `cp0_had_cpuid_0/debug_info/lpmd_b/trace_pm_*`，并接收 `had_cp0_xx_dbg`（`ct_core.v:4484-4510,4651-4654`）。
- RTU 接收所有 `had_rtu_*` 请求/模式控制，并返回断点命中、debug ack、retire info、PC、split、change-flow/next-PC 等（`ct_core.v:4711-4737,4933-4983`）。

### 5.2 RTU 断点和 PC 数据来源

RTU ROB 将断点、store/load 类型、split、change-flow 和 retire 信息导出为 HAD 输入：

- 断点/ROB 状态由 `ct_rtu_rob_rt` 形成，例：`rtu_had_inst_bkpta_vld`、`rtu_had_inst_bkptb_vld`、数据断点、store、BJU、split（`gen_rtl/rtu/rtl/ct_rtu_rob_rt.v:1438-1445`）。
- 三个 retire slot 的 non-IRV breakpoint 位来自 retire 数据 bit[30:27]（`ct_rtu_rob_rt.v:1946-1948`）。
- PCFIFO 的 change-flow、next-PC、pcall/preturn/jmp 等来自 `ct_rtu_retire`（`gen_rtl/rtu/rtl/ct_rtu_retire.v:1696-1716`）。
- `ct_rtu_rob_rt` 接收 HAD 断点请求和 trace/debug 控制，说明请求方向确实是 HAD→RTU、命中/退休/ack 方向是 RTU→HAD（`ct_rtu_rob_rt.v:260-264,437-454`）。

## 6. 典型数据/控制路径

### 6.1 JTAG 读写一个 core 寄存器

```text
JTAG pad
  → ct_had_sm(TAP state/capture/shift/update)
  → ct_had_serial(TDI/TDO shift)
  → ct_had_ir(common HACR: core/bank/index/read-write)
  → ct_had_private_ir(core bank/index + CPU-domain pulse)
  → ct_had_regs / ct_had_pcfifo / ct_had_dbg_info
  → x_regs_serial_data
  → ct_had_ir(core/private mux)
  → ct_had_serial → TDO
```

写操作要求 `sm_xx_update_dr_en` 且 HACR 为 write，更新 BABA/HCR/PC/IR/CSR 等；读 FIFO 则由 HACR read 和 update 产生一次 `x_ir_ctrl_*_read_pulse`，数据先打一拍后被串行 capture。相关证据：`ct_had_sm.v:296-344`、`ct_had_private_ir.v:317-335`、`ct_had_regs.v:946-974`、`ct_had_common_top.v:204-271`。

### 6.2 内存/指令断点进入 debug

```text
RTU/LSU 命中
  → ct_had_bkpt(A/B) 或 ct_had_nirv_bkpt
  → ct_had_ctrl 做 SQC/FRZC/FDB/debug-mode 过滤
  → had_rtu_*_dbgreq + had_cp0_xx_dbg
  → ct_rtu_top / ct_cp0_top
  → rtu_had_dbgreq_ack / bkpt ack
  → ct_had_ctrl 更新 HSR(MBO/SWO/MBIR/SQA/SQB/FRZO)
```

证据：断点级联见 `ct_had_private_top.v:543-734`；请求过滤见 `ct_had_ctrl.v:455-510`；状态更新见 `ct_had_ctrl.v:550-596` 与 `ct_had_regs.v:702-852`。

### 6.3 DBGFIFO/PIPEFIFO/PCFIFO

- PCFIFO 记录 RTU retire 的 branch/jump target，选择 HACR bank0 index6 读出（`ct_had_pcfifo.v:104-218`、`ct_had_private_ir.v:237-255`）。
- PIPEFIFO 由 PIPESEL 选择 IDU、RTU 或 LSU 数据；bank2 index5 读出，PIPESEL 本身为 index6（`ct_had_dbg_info.v:198-250`、`ct_had_private_ir.v:294-304`）。
- DBGFIFO 在 RTU debug ack 后锁存各单元的拼接记录，bank2 index4 分 64 位槽读出（`ct_had_dbg_info.v:368-446`）。
- 公共 DBGFIFO2 记录 CIU+L2C 337 位数据，bank3 index0 读出（`ct_had_common_dbg_info.v:117-149`、`ct_had_ir.v:280-285`）。

## 7. 文件/module 清单（完整覆盖）

| 文件 / module | 职责摘要 | 主要证据 |
|---|---|---|
| `ct_had_bkpt.v` / `ct_had_bkpt` | A/B 内存/指令断点条件、BC 过滤、MBC counter、raw/filtered request | `:141-161,168-223,241-322` |
| `ct_had_common_dbg_info.v` / `ct_had_common_dbg_info` | CIU+L2C 公共 debug-info 记录与 6×64b 读出 | `:111-216` |
| `ct_had_common_regs.v` / `ct_had_common_regs` | RSR、HAD ID、DMS、公共读 mux、debug mask | `:83-178` |
| `ct_had_common_top.v` / `ct_had_common_top` | 公共 JTAG/HAD 顶层及子模块连接；APB tie-off | `:171-335` |
| `ct_had_ctrl.v` / `ct_had_ctrl` | 请求仲裁、RTU/CP0/IFU 控制、HSR 脉冲、进入/退出、clock enable | `:341-704` |
| `ct_had_dbg_info.v` / `ct_had_dbg_info` | PIPESEL、PIPEFIFO、DBGFIFO、408b debug record | `:186-446` |
| `ct_had_ddc_ctrl.v` / `ct_had_ddc_ctrl` | DDC 状态机、地址/数据/指令更新控制 | `:74-200` |
| `ct_had_ddc_dp.v` / `ct_had_ddc_dp` | DADDR/DDATA 保存、WBBR/IR/FFY 输出 | `:68-110` |
| `ct_had_etm_if.v` / `ct_had_etm_if` | event request 的 event-clock 域输入/输出寄存与 clock enable | `:61-115` |
| `ct_had_etm.v` / `ct_had_etm` | core0/1 event interface 汇聚；core2/3 当前禁用 | `:84-214` |
| `ct_had_event.v` / `ct_had_event` | debug enter/exit event 输入输出及 enable | `:87-175` |
| `ct_had_io.v` / `ct_had_io` | JTAG TDI/TDO/TDO enable 线路选择 | `:48-71` |
| `ct_had_ir.v` / `ct_had_ir` | 公共 HACR、core/bank/index 解码、公共/私有串行 mux | `:174-296` |
| `ct_had_nirv_bkpt.v` / `ct_had_nirv_bkpt` | non-IRV A/B 断点汇聚、split pending | `:85-148` |
| `ct_had_pcfifo.v` / `ct_had_pcfifo` | 深度16 PC change-flow 环形 FIFO | `:95-296` |
| `ct_had_private_ir.v` / `ct_had_private_ir` | core 私有 HACR、bank/index、DR/IR 跨域、读 pulse | `:170-335` |
| `ct_had_private_top.v` / `ct_had_private_top` | 单 core HAD 组合顶层；实例化全部私有功能 | `:543-1034` |
| `ct_had_regs.v` / `ct_had_regs` | HAD ID、CPUSCR/HCR/HSR、断点寄存器、数据读 mux | `:393-974` |
| `ct_had_serial.v` / `ct_had_serial` | 8/16/32/64 位串行 shift、capture、parity、TDO | `:115-220` |
| `ct_had_sm.v` / `ct_had_sm` | JTAG TAP5 状态机、TAP status、TDO enable、update sync | `:98-344` |
| `ct_had_sync_3flop.v` / `ct_had_sync_3flop` | tclk→cpuclk 的三级脉冲同步 | `:50-89` |
| `ct_had_trace.v` / `ct_had_trace` | OTC 计数器及 trace request | `:67-123` |

## 8. 已确认的限制/不确定项

1. 当前工作区只有 `openC910` 的 `x_ct_top_0` 有效实例；core1 的 HAD/调试输出在 `openC910.v:880-896` 被常量化，不能把 common top 的 core1 端口误认为当前有效 CPU 通道。
2. `ct_had_etm` 中 core2/core3 的接口代码存在，但输出/clock enable 为 0（`ct_had_etm.v:126-143`）；它们不是当前有效事件路径。
3. `ct_had_common_dbg_info` 注释写有四个 core 的同步器，但 core0/core1 目前直接赋值，core2/core3 为 0（`ct_had_common_dbg_info.v:71-114`）；是否由生成脚本在其他配置替换，单凭当前 RTL 无法确认。
4. `ct_had_sm` 的 DR 跨域实例是注释掉的 `ct_had_sync`，实际私有 IR 使用 `sync_level2pulse`，因此不要根据注释推导不存在的 `sm_update_dr_cpu` 路径（`ct_had_sm.v:281-288`、`ct_had_private_ir.v:191-207`）。
5. `ct_had_pctrace_top` 和 `ct_had_pctrace_busif` 只有注释；当前 pctrace/LSU bus trace/APB trace 输出均为关闭或 tie-off（`ct_had_private_top.v:1037-1072`、`ct_had_common_top.v:323-335`）。
6. `ct_had_etm_if`、`ct_had_event` 中若干 `sync_level2pulse` 也被注释逻辑替代为普通寄存器采样（`ct_had_etm_if.v:64-110`、`ct_had_event.v:90-118`）；其握手/亚稳态保证不能超出当前 RTL 证据推断。
