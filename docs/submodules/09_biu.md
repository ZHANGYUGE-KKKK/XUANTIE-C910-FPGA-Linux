# BIU（总线接口单元）

## 1. 范围与结论

本节只覆盖 `gen_rtl/biu/rtl` 下的 BIU RTL，并追踪它与 CPU 内部请求源、MMU/配置接口以及 CIU/EBIU 边界的真实连接。BIU 的职责是：把 IFU/LSU 发出的读请求、LSU 的写请求、外部一致性 snoop 请求和 CP0/HPCP 的 CSR 请求整理成可门控、可缓冲的总线通道；再把返回数据、写响应、snoop 返回和 CSR 完成送回相应发起端。

BIU 本身不是 AXI 完整协议转换器：它在 `pad_biu_*` 一侧保留 C910 特有的 ID、domain、bar、snoop、user、WNS 等字段，真正到外部 AXI 的扩展/转换位于 CIU 的 EBIU 路径。BIU RTL 中没有 `rtu_yy_xx_flush`、异常输入或异常处理状态机；上游 IFU/LSU/CP0 负责在握手前撤销无效请求，BIU 对已经接受的事务依赖 ID、`last`、`resp` 和下游 ready 完成收发。

## 2. 模块树与文件职责

```text
ct_biu_top
├── ct_biu_req_arbiter       IFU/LSU 读请求仲裁；LSU 写地址/数据请求透传与 grant
├── ct_biu_read_channel      读地址两项缓冲、R 数据两项缓冲、IFU/LSU 返回分流
├── ct_biu_write_channel     写地址优先级、W FIFO/数据缓冲、B 返回及 back 过程
├── ct_biu_snoop_channel     AC 输入及 CR/CD 返回的双项缓冲
├── ct_biu_lowpower          读写/snoop 各子通道门控时钟及 BIU 空闲指示
├── ct_biu_csr_req_arbiter   CP0/HPCP CSR 请求选择和完成分发
└── ct_biu_other_io_sync     CSR/L2、hart/debug/timer/中断、低功耗等杂项同步
```

顶层实例化关系在 `gen_rtl/biu/rtl/ct_biu_top.v:789-1242`，各文件均为独立 module：

| 文件 | module | 作用与关键证据 |
|---|---|---|
| `ct_biu_top.v` | `ct_biu_top` | 汇聚 CPU 侧端口、`pad_biu_*` 边界、7 个子模块；端口总表在 `:243-466`，实例在 `:789-1242`。 |
| `ct_biu_req_arbiter.v` | `ct_biu_req_arbiter` | 组合仲裁/字段 mux，没有时序状态；读路径在 `:423-498`，写地址/数据在 `:501-553`。 |
| `ct_biu_read_channel.v` | `ct_biu_read_channel` | 两项 AR 缓冲和两项 R 缓冲；地址缓冲在 `:133-508`，返回与 rack 过程在 `:514-735`。 |
| `ct_biu_write_channel.v` | `ct_biu_write_channel` | victim/store AW 源缓冲、12 项 W FIFO、victim/store/round 三路数据缓冲、B/back 返回；分别在 `:411-643`、`:649-962`、`:970-1063`。 |
| `ct_biu_snoop_channel.v` | `ct_biu_snoop_channel` | AC、CR、CD 各有两项缓冲；AC 在 `:181-300`，CR 在 `:302-388`，CD 在 `:394-513`。 |
| `ct_biu_lowpower.v` | `ct_biu_lowpower` | 为读/写/snoop 通道生成 10 个门控时钟，另输出 `biu_yy_xx_no_op`；门控实例在 `:121-344`，空闲判断在 `:353-354`。 |
| `ct_biu_csr_req_arbiter.v` | `ct_biu_csr_req_arbiter` | CP0 优先于 HPCP 驱动共享 CSR 请求，完成/rdata 返回在 `:70-96`。 |
| `ct_biu_other_io_sync.v` | `ct_biu_other_io_sync` | core ID、RVBA/APB、L2 CSR 时钟、外部中断/debug/timer、低功耗和计数器同步；实现集中在 `:195-439`。 |

## 3. 顶层接口与请求仲裁

`ct_biu_top` 的 CPU 侧包括 IFU 读请求/返回、LSU AR/AW/W 及读写返回、LSU AC/CR/CD snoop、CP0/HPCP CSR，以及 `cp0_biu_icg_en`、`biu_yy_xx_no_op` 等时钟/空闲控制；外侧 `pad_biu_*` 包括 AR/AW/W、R/B、AC/CR/CD、CSR 和杂项 IO（`ct_biu_top.v:243-466`）。子模块的连接不是隐含网表，而是在顶层逐项命名连接：读在 `:928-985`，写在 `:988-1086`，snoop 在 `:1089-1126`，低功耗在 `:1129-1162`，CSR 仲裁在 `:1165-1182`，杂项同步在 `:1191-1242`。

### 3.1 读仲裁

`ct_biu_req_arbiter` 只有 IFU 和 LSU 竞争 AR：

```text
ifu_ar_req = ifu_biu_rd_req && !lsu_biu_ar_dp_req
lsu_ar_req = lsu_biu_ar_req &&  lsu_biu_ar_dp_req
arvalid    = ifu_ar_req || lsu_ar_req
```

代码在 `ct_biu_req_arbiter.v:423-436`。因此，LSU 的 data-path 请求标志不仅选择 LSU，也会压住 IFU；这不是 round-robin，而是“LSU data-path 优先，否则 IFU”的组合选择。发往外部的 `arvalid` 还会经过读地址缓冲，真正的接受条件是 `arvalid && arready`。IFU grant 为 `ifu_ar_req && arready`，LSU 的 AR ready 直接为 `arready`（`:497-498`）。

IFU 选中时，BIU 将 ID 改成 5 位 `{4'b1000, ifu_biu_rd_id}`，即 `10000`/`10001` 两类 IFU 事务；地址、len、size、burst、cache、prot、snoop、domain 以及 `{1'b0, ifu_biu_rd_user}` 一并形成 AR（`:463-476`）。LSU 选中时保留 LSU 提供的 AR 字段（`:478-492`）。地址使用 `PA_WIDTH` 低位，宏来自 `cpu_cfig.h` 的构建配置，具体切片见 `ct_biu_req_arbiter.v:466,481` 和 `ct_biu_read_channel.v:293`；仓库的 filelist 将 `cpu_cfig.h` 放在 Verilog 文件前（`gen_rtl/filelists/C910_asic_rtl.fl:1`）。

### 3.2 写请求

BIU 不在 IFU/LSU 之间仲裁写请求，写请求全部来自 LSU。`ct_biu_req_arbiter` 把 victim AW 与 store/WMB AW 两路字段分别透传到 `vict_aw*`、`st_aw*`，把 `biu_lsu_aw_vb_grnt`、`biu_lsu_aw_wmb_grnt` 分别接到外侧两个 AW ready（`ct_biu_req_arbiter.v:501-536`）；W 数据/strb/last 也分别透传并返回两个 W grant（`:539-553`）。

LSU 内部来源选择位于 `gen_rtl/lsu/rtl/ct_lsu_bus_arb.v`：读优先级为 WMB > RB > PFU（`:592-624`），AW 优先级为 VB > WMB（`:686-709`），因此 BIU 的写通道看到的是 LSU 已经选择好的 victim/store 两路，而非 PFU/RB/WMB 原始竞争。

## 4. 读通道：AR、R、IFU/LSU 返回与背压

`ct_biu_read_channel` 的 AR 侧是两项缓冲。`arready` 等于当前地址缓冲可用（`ct_biu_read_channel.v:275-281`）；在 `arcpuclk` 上分别维护 create/pop 指针和两项 valid，地址请求在 `:368-508` 捕获。BIU 对外只在缓冲中有当前项时驱动 AR，当前项字段包括 5 位 ID、PA、len/size/burst、lock、cache、prot、snoop、domain、bar 和 user（`:291-366`）。外侧 `pad_biu_arready` 决定从 BIU 地址缓冲 pop（`:378-386`），所以下游不 ready 时 AR 字段保持稳定。

R 侧同样是两项数据缓冲；`biu_pad_rready=cur_rdata_buf_ready`（`:514-519`），收到 `pad_biu_rvalid` 才创建（`:538`）。返回清除条件按目标端口拆分：IFU 必须 `ifu_biu_r_ready`，LSU linefill 必须 `lsu_biu_r_linefill_ready`，而 LSU 非 linefill 返回无需额外 ready（`:522-526`）。当 rack 已满时，清除被抑制；rack 使用 `rack_valid`/`rack_pending` 组成两阶段保护，`rack_full=rack_valid && rack_pending`（`:546-570`），顶层将 `pad_biu_rack_ready` 固定为 1（`ct_biu_top.v:1187-1188`）。

ID 分类在 `ct_biu_read_channel.v:528-536`：ID 为 `10000` 或 `10001` 时是 IFU，其他 ID 是 LSU；LSU linefill 再由 ID[4:3] 区分。LSU 返回保留 5 位 ID、数据、4 位 resp 和 last（`:708-712`），IFU 返回使用 `rid[0]` 作为 IFU ID，并只返回低 2 位 resp（`:714-718`）。文件注释定义 resp[3] 为 IsShared、resp[2] 为未支持的 passdirty、resp[1] 为 Error、resp[1:0] 为 OKAY/EXOKAY（`:700-707`）。R 通道的 busy/门控条件把 AR 缓冲、R 缓冲、rack 和 rack_pending 都纳入（`:722-735`），防止低功耗关钟时遗漏在途返回。

## 5. 写通道：AW/W、W FIFO、B 与 back

### 5.1 AW 源选择

写通道将 LSU 请求编码为三类事务：`WU=3'b000`、`WLU=3'b001`、`EVICT=3'b100`（`ct_biu_write_channel.v:411-413`）。`aw_ws` 在 WU/WLU 且 domain 为 01，或 bar[0] 置位时为 1；它选择外侧 `pad_biu_ws_awready`，否则选择 `pad_biu_wns_awready`（`:415-423`）。地址输出采用 victim 优先、store 次之的 mux（`:435-515`）；两路各有源缓冲、valid、create/clear，victim 优先保证驱逐/回写不会被普通 store 插队（`:517-643`）。

### 5.2 W 数据与 12 项 FIFO

W FIFO 深度为 12（`W_FIFO_ENTRY=12`，`:649-651`），使用 one-hot/移位式状态保存尚未送出的 AW 事务；非 EVICT 地址握手才创建对应 W 事务，EVICT 只参与地址流程（`:675-695`）。FIFO 空/少于两项的状态和 victim/store 的下一项 ready 决定 `biu_lsu_w_*_ready`（`:693-708`）。

W 数据通路拆成 victim、store、round 三个缓冲以切断时序并支持连续传输（`:725-730`）。选择编码为 victim=`3'b001`、store=`3'b010`、round=`3'b100`，具体 mux/next 逻辑在 `:732-822`；三路源数据、strb、last 在各自门控时钟上捕获（`:825-962`）。对外 W 通道根据 `wns` 选择 WNS/Ws 目标 ready，`biu_pad_werr` 固定为 0（`:717-723`），表示 BIU 不在 W 阶段注入错误。

### 5.3 B 返回与 back

B 响应进入一项/受限返回缓冲；`biu_pad_bready=!back_full`，B 的 capture/clear 在 `ct_biu_write_channel.v:970-999`。LSU 看到的 B valid、resp、事务 ID 在 `:1001-1003`。BIU 另外产生 back 过程：当写事务完成/`last` 条件满足后，`back_valid`、`back_pending` 在 coreclk 上登记，`back_full=back_valid && back_pending`，并以 `biu_pad_back` 对外报告（`:1007-1033`）。顶层把 `pad_biu_back_ready` 固定为 1（`ct_biu_top.v:1187-1188`），所以当前集成中 back 不会因外部 ready 停住；外侧 B 仍受 `back_full` 背压。写通道 busy 覆盖 AW/W/B/back 以及 pending 状态，见 `:1035-1063`。

## 6. Snoop 通道：AC、CR、CD

AC 是 CIU/外部到 LSU 的请求。`pad_biu_acvalid` 在当前 AC 缓冲有空槽时创建，两个槽位由 create/pop 指针维护（`ct_biu_snoop_channel.v:181-269`）；输出给 LSU 的字段包含 valid、地址、snoop 和 prot（`:271-300`），LSU 的 `biu_lsu_ac_ready` 才会 pop。AC 地址使用 `PA_WIDTH`，切片见 `:231,259,284-298`。

CR 是 LSU 到外部的 snoop 响应，`biu_lsu_cr_ready` 反映 CR 缓冲尚有空槽，缓冲满时对 LSU 背压；当前项由 `pad_biu_crvalid`、resp 输出（`:302-388`）。CD 是 LSU 到外部的数据返回，同样为两项缓冲，支持 valid/data/last，`biu_pad_cderr` 固定为 0（`:394-513`）。因此 AC/CR/CD 三条通路彼此独立，AC 的 LSU ready 不会替代 CR/CD 的下游 ready。

`core_snoop_vld` 在 `forever_coreclk` 上由 AC create 置位，只有 LSU 空闲且当前没有 CR/CD 输出时才清零（`:530-549`）；它送给低功耗模块，确保 snoop 尚未完成时保持所需时钟。AC payload 的部分寄存器在 `accpuclk` 块内没有独立复位分支，而 valid/指针复位；应把 valid 视作复位后的有效性保证（`:215-269`）。

## 7. CP0/HPCP CSR 与其他 IO

`ct_biu_csr_req_arbiter` 对共享 CSR 端口采用 CP0 优先：`cp0_biu_sel` 为真时选择 CP0，否则选择 HPCP，字段包括 sel、op、wdata（`ct_biu_csr_req_arbiter.v:70-91`）。完成时 CP0 由 `biu_csr_cmplt && cp0_biu_sel` 接收，但 HPCP 完成直接使用 `biu_csr_cmplt`，没有再与 `hpcp_biu_sel` 相与（`:93-96`）；这是当前 RTL 的真实语义，应由上游保证完成时只有合法请求者。

CP0 请求的生成在 `gen_rtl/cp0/rtl/ct_cp0_iui.v:1453-1463`：仅当 CSR 指令、L2 CSR 选择和权限有效时置 `cp0_biu_sel`，wdata 可来自 DCA、立即数或 src0，op[15:8] 表示 DCA，op[7:4] 是寄存器索引，低位编码读/写/置位/清位。CP0 在 `ct_cp0_iui.v:1495-1523` 用 `biu_cp0_cmplt` 完成指令并采样 rdata。HPCP 在 `gen_rtl/pmu/rtl/ct_hpcp_top.v:4350-4353` 产生 `hpcp_biu_sel/wdata/op/cnt_en`，其完成返回使用 `biu_hpcp_cmplt`（同文件约 `:3010-3014`）。

`ct_biu_other_io_sync` 的功能如下：

- `pad_core_hartid` 直连 CP0 core ID，HAD 只取低 2 位（`:195-200`）；RVBA/APB base 在 coreclk 采样（`:201-214`）。
- PMP 选择固定为 0（`:232`）。L2 CSR 请求在 `biu_csr_sel` 上升沿登记，打包为 `{biu_csr_op,biu_csr_wdata}`，并由 `l2reg_oclk` 输出；完成/rdata 在 `l2reg_iclk` 采样（`:234-314`）。
- ME/MT/MS/SE/ST/SS 六路中断在 `forever_coreclk` 上两级同步并 OR 成 `biu_xx_int_wakeup`（`:323-363`）；debug request 同样两级同步，复位值为 1，wakeup 为第二级取反（`:366-382`）。
- timer 在 coreclk 采样（`:384-391`）；`cp0_biu_lpmd_b` 与 `had_biu_jdb_pm` 在 forever_coreclk 上登记成 pad 低功耗输出，复位时 lpmd 为 1、jdb 为 0（`:397-415`）。计数器使能和 L2 overflow 中断分别在 `:418-437` 同步，`biu_mmu_smp_disable` 固定为 0（`:439`）。

## 8. 时钟、复位、低功耗和宏

BIU 使用 `coreclk`、不门控的 `forever_coreclk` 和由 `ct_biu_lowpower` 派生的局部时钟。读 AR/R、victim/store AW、victim/store/round W、W FIFO、B 共 9 个局部 coreclk 门控域，snoop AC 使用 forever_coreclk，CR/CD 使用 coreclk；每个 `gated_clk_cell` 的 `module_en` 为 `cp0_biu_icg_en`，`global_en=1`、`external_en=0`，scan enable 透传，证据为 `ct_biu_lowpower.v:121-344`。读写通道把缓冲是否有活动请求/返回作为 local enable（读：`ct_biu_read_channel.v:722-735`；写：`ct_biu_write_channel.v:1035-1063`）。

大多数状态寄存器采用 `posedge local_clk or negedge cpurst_b` 异步低有效复位：读地址/R、写 AW/W/B、snoop valid/指针以及杂项 CSR/同步状态均可见于各自文件的 always 块。BIU 顶层的 `cpurst_b` 来自 CPU 顶层的 `mmu_rst_b`（`gen_rtl/cpu/rtl/ct_top.v:1575-1582`），而 coreclk/forever_coreclk 同时由顶层传入。低功耗模块自身没有状态复位逻辑，它只组合地产生门控时钟和 `biu_yy_xx_no_op=!read_busy&&!write_busy`（`ct_biu_lowpower.v:353-354`）。

地址切片依赖 `PA_WIDTH`，本地 BIU 文件不直接 `define` 它；配置来自 `gen_rtl/cpu/rtl/cpu_cfig.h`，filelist 首项为该头文件（`gen_rtl/filelists/C910_asic_rtl.fl:1`）。BIU 文件中的 `&Depend`/`&Connect` 风格注释只是生成器元数据，实际端口连接以 Verilog module 实例为准。

## 9. CPU 内部跨目录连接

```text
IFU (ct_ifu_top/ct_ifu_ipb) ── ifu_biu_* ─┐
                                          ├─ ct_biu_req_arbiter
LSU (ct_lsu_bus_arb) ── lsu_biu_* ────────┘          │
       ▲                    │                        ▼
       └── biu_lsu_* ◄── ct_biu_read/write/snoop ─ pad_biu_*
CP0 (ct_cp0_iui) ── cp0_biu_csr ─ ct_biu_csr_req_arbiter ─ CSR pad
HPCP ───────────── hpcp_biu_csr ────────────────────────┘
MMU ── biu_mmu_smp_disable ─ ct_biu_other_io_sync
```

- `ct_top` 在 `gen_rtl/cpu/rtl/ct_top.v:1473-1701` 实例化 `ct_biu_top`，把 IFU、LSU、CP0/HPCP、coreclk/forever_coreclk、`mmu_rst_b` 和所有 `pad_biu_*` 逐项接入；pad 返回映射集中在 `:1665-1695`。
- `ct_core` 中，IFU 的 BIU 请求/返回接在 `gen_rtl/cpu/rtl/ct_core.v:2477-2549`，LSU 的返回、grant、snoop 接在 `:3982-4004`，LSU 发往 BIU 的 AR/AW/W/AC/CR/CD 接在 `:4149-4212`。IFU 内部由 `ct_ifu_ipb` 产生/消费这些信号（`gen_rtl/ifu/rtl/ct_ifu_top.v:3258-3286`）。
- LSU 的原始 PFU/RB/WMB/VB 请求先在 `gen_rtl/lsu/rtl/ct_lsu_bus_arb.v:592-770` 选择，`lsu_biu_ar_dp_req` 是实际选中 data-path 请求的标志；这解释了 BIU 读仲裁中对该标志的特殊优先级。
- CP0 通过 `ct_cp0_top`/`ct_cp0_iui` 使用 BIU completion/rdata（`gen_rtl/cp0/rtl/ct_cp0_top.v:724-734`，`ct_cp0_iui.v:1495-1523`）。MMU 顶层只把 `biu_mmu_smp_disable` 继续传给 DTLB（`gen_rtl/mmu/rtl/ct_mmu_top.v:132,607`）；当前 BIU 杂项同步将该量固定为 0，因此没有额外的 MMU 动态配置路径。

## 10. CIU/EBIU 与外部 AXI 边界

仓库中可直接确认的边界是：`ct_biu_top` 的 `pad_biu_*` 连接到平台/CIU，而不是在 BIU 内实例化 CIU。`gen_rtl/ciu/rtl/ct_ciu_top.v:20-48` 声明 BIU/EBIU 侧接口，`ct_ebiu_top` 实例位于 `:3723-3881`；其中 AR/AW/W、B ready、R ready 及 rack/back 的逐项连接在 `:3779-3806`，EBIU 返回到 CIU/BIU 的反馈在 `:3869-3880`。当前仓库未找到 `ct_ciu_top` 在 CPU RTL 内的直接实例，因此最后一级连接由更高层平台顶层完成。

BIU 内部主要协议字段如下：

| 通道 | BIU 保留/产生的字段 | 接受与返回 |
|---|---|---|
| AR | 5 位 ID、PA、len、size、burst、lock、cache、prot、snoop、domain、bar、user、valid | `arvalid && pad_biu_arready`；R 由 ID 分类回 IFU/LSU。 |
| AW | 事务 snoop/type、PA、len/size/burst、lock、cache/prot、domain、bar、user，并按 `aw_ws` 选 WNS/WS | victim/store 各自握手；victim 优先。 |
| W | data、strb、last，外加 WNS/WS 路由 | `pad_biu_wvalid && pad_biu_wready`，`biu_pad_werr=0`。 |
| R | 5 位 rid、data、4 位 resp、last | 两项 R 缓冲；IFU 只接 `rid[0]`/低 2 位 resp，LSU 接完整字段。 |
| B | bid、resp | 进入 B 缓冲并受 back_full 限制；LSU 接收响应。 |
| Snoop | AC 地址/snoop/prot；CR resp；CD data/last | AC、CR、CD 各自两项缓冲，CD error 固定 0。 |

CIU/EBIU 外侧使用更宽的 AXI 风格 ID/len 等端口（例如 `ct_ciu_top.v:534-601` 的 EBIU 方向端口），因此从 BIU 的 5 位内部 ID 到外部 AXI 的扩展/映射不应归因于 BIU；BIU 只保证其 `pad_biu_*` 边界字段、握手和返回 ID 语义。snoop、CSR、interrupt/debug 等非基本 AXI 通道也在 CIU 的平台接口中分别暴露（`ct_ciu_top.v:258-330`），但本仓库没有更高层把它们接回 BIU 的单一顶层实例，故文档只确认到该边界，不臆测平台 wiring。

## 11. 背压、异常、flush 与配置要点

1. **背压**：AR 由两项地址缓冲和 `pad_biu_arready` 背压；R 由两项数据缓冲、IFU/LSU ready 和 rack_full 背压；AW/W 由 victim/store 源缓冲、W FIFO、三路 W 数据缓冲和 WNS/WS ready 背压；B 由 back_full 背压；AC/CR/CD 各自按两项缓冲独立背压。BIU 顶层只把 rack/back ready 固定为 1，不能据此推导外部 R/B 永远无阻塞。
2. **异常/错误**：BIU 不生成异常控制流；R 的 `resp[1]` 被保留为 Error，resp 其余语义按读通道注释解释。W `biu_pad_werr`、CD `biu_pad_cderr` 均为 0，说明错误报告依赖 R/B 或外部协议字段，而不是这两个信号。
3. **flush/取消**：BIU 端口和子模块均没有 flush 输入。LSU 通过 `ct_lsu_top` 内部接收 `rtu_yy_xx_flush`（`gen_rtl/lsu/rtl/ct_lsu_top.v:5726,6288`）清理自己的请求源；IFU/CP0 也在各自流水线处理改变流/完成条件。BIU 已经完成的握手不会被一个不存在的 BIU flush 信号回滚，未握手的请求是否消失由上游 valid/队列决定。
4. **配置**：可确认的 BIU 配置量主要是 `PA_WIDTH`、`cp0_biu_icg_en` 和 filelist 头文件宏；本地 BIU RTL 没有独立 `ifdef` 配置分支，也没有动态修改地址宽度的逻辑。`cp0_biu_icg_en` 来自 CP0 局部门控使能（`gen_rtl/cp0/rtl/ct_cp0_regs.v:4361`），并作为所有 BIU 门控单元的 module enable。

综上，BIU 的核心边界是“组合请求选择 + 各通道两项/多项缓冲 + 明确的返回分类/握手 + 局部时钟门控”。IFU/LSU 的请求语义在 CPU 内部已经由 `ct_ifu_ipb` 和 `ct_lsu_bus_arb` 整理，BIU 不重新解释其队列；CIU/EBIU 则承接 `pad_biu_*` 后完成平台级外部总线映射。
