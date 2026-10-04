# CIU/PIU RTL 结构报告

## 1. 范围与结论

本文完整覆盖 `gen_rtl/ciu/rtl` 目录中的 37 个 Verilog 文件。分析依据真实的 `module`、端口声明、实例化、连续赋值和时序逻辑；跨目录模块只作为本目录的连接边界记录，不展开其 RTL。

CIU 是 core 侧 BIU 请求到 L2C、外部 EBIU/AXI-like 总线、APB 和一致性控制面的汇聚层。它把每个 PIU 的请求按属性分为：

- `SNB`：可缓存、需要一致性/窥探的读写路径；由 SAB 保存事务状态，并协调 L2C、其他 core 的 AC/CR/CD、外部 EBIU 和 VB。
- `NCQ`：不可缓存或系统顺序访问路径；在 APB 和外部 EBIU 之间分发，并维护读写顺序、barrier 和 exclusive/GM 状态。
- `CTCQ`：cache/TLB/DVM 控制请求；等待目标 PIU、L2C 和外部 EBIU 的分目标完成。

PIU 是每个 core/device 侧的协议适配器：把 AR/AW/WD/CD/AC/CR/R/B 以及 barrier/寄存器/DCA 请求做排队、路由和响应回送。实际功能 PIU 为 core0/core1；core2/core3 和 device PIU 使用 dummy 变体或被硬置零。SNB 有两套、分别对应两个 L2C bank；L2CIF 再把两套路径接到 bank0/bank1。外部 EBIU 端仍是 AXI-like 的 AR/AW/W/R/B 命名接口，但本文不把它额外归类为完整 AXI 实现。

## 2. 模块树

```text
ct_ciu_top
├─ ct_piu_other_io x_ct_piu0/1_other_io
│  └─ ct_piu_other_io_sync       CSR、DCA/L2C 读、HPC/调试/中断同步
├─ ct_piu_other_io_dummy x_ct_piu2/3_other_io
├─ ct_piu_top x_ct_piu0/1_top    core0/core1 协议 FIFO、路由、响应解包
├─ ct_piu_top_dummy x_ct_piu2/3_top_dummy
├─ ct_piu_top_dummy_device x_ct_piu4_top_dummy
├─ ct_ciu_bmbif
│  └─ ct_ciu_bmbif_kid x_snb0/x_snb1/x_ncq/x_ctcq
├─ ct_ciu_snb x_snb0/1
│  ├─ ct_ciu_snb_arb              PIU/L2C/外部 snoop 仲裁
│  └─ ct_ciu_snb_sab
│     ├─ ct_ciu_snb_sab_entry ×24  一致性事务表项
│     └─ ct_ciu_snb_dp_sel/_16/_8 年龄选择器
├─ ct_ciu_vb                      L2/SNB writeback buffer
│  └─ ct_ciu_vb_aw_entry           writeback AW/W entry
├─ ct_ciu_ebiuif                   SNB/CTCQ 与 EBIU snoop/read 接口
├─ ct_ciu_l2cif                   两个 L2C bank 的请求/响应复用
├─ ct_ciu_ctcq
│  ├─ ct_ciu_ctcq_reqq_entry ×8
│  └─ ct_ciu_ctcq_respq_entry ×16
├─ ct_ciu_ncq
│  └─ ct_ciu_ncq_gm x_core0/1     exclusive/global monitor
├─ ct_ebiu_top
│  ├─ ct_ebiu_read_channel
│  │  └─ ct_fifo                  R 返回缓存
│  ├─ ct_ebiu_snoop_channel_dummy
│  ├─ ct_ebiu_write_channel
│  │  ├─ ct_fifo                  B 返回缓存
│  │  ├─ ct_ebiu_ncwt_entry ×16   non-cacheable write table
│  │  └─ ct_ebiu_cawt_entry ×32   cacheable write table
│  └─ ct_ebiu_lowpower
├─ ct_ciu_regs
│  └─ ct_ciu_regs_kid x_core0/1
└─ ct_ciu_apbif                    NCQ 到 APB bridge

通用叶子：ct_fifo、ct_prio。
```

顶层实例证据集中在 `gen_rtl/ciu/rtl/ct_ciu_top.v:1849-3999`；BMBIF 的四个目标实例在 `ct_ciu_bmbif.v:197-295`；SNB 子模块在 `ct_ciu_snb.v:634-892`；CTCQ/EBIU/寄存器/APB 实例分别在 `ct_ciu_top.v:3278-3999`。顶层的 dummy PIU/device 实例位于 `ct_ciu_top.v:1980-2633`。

## 3. 顶层边界和通道模型

### 3.1 外部边界

`ct_ciu_top` 的端口分组在 `ct_ciu_top.v:20-374`、`481-559` 及其后续系统 IO 端口处：

- core0/core1 的 `ibiu{0,1}_pad_*`：AR/AW/WD/R/B、AC/CR/CD、CSR、interrupt 等 PIU 侧请求和响应。
- 两个 L2C bank：bank0/bank1 的地址、tag/data/ECC、完成、writeback/PRF 等端口，见 `ct_ciu_top.v:481-532`。
- 外部 BIU/AXI-like pad：`pad_biu_*`，包括 AR/AW ready、W ready、R/B valid/data/id/resp/last 等，见 `ct_ciu_top.v:534-545`。
- APB pad：地址、使能、写、选择、读数据、ready/error 和 CLINT/HAD/L2PMP/PLIC/RMR 分段，见 `ct_ciu_top.v:551-559` 及 `ct_ciu_apbif.v:55-79`。

### 3.2 事务通道

| 通道 | 方向/用途 | 主要保存和返回位置 |
|---|---|---|
| AR/AW | core 发起读/写地址 | PIU FIFO；随后进入 SNB、NCQ、CTCQ 或 EBIU |
| WD/CD | 写数据/一致性数据 | PIU WD/CD FIFO；SNB SAB entry 或 NCQ WO/WD/DS 队列 |
| AC/CR | snoop 请求/响应 | PIU AC/CR FIFO；SNB SAB per-core snoop 状态机 |
| R/B | 数据/写响应 | PIU response/unpackage FIFO；NCQ RDQ/WBQ；EBIU R/B FIFO |
| RACK/BACK | core 对 R/B 的接收确认 | PIU/SNB 按 SID 定位原事务 |
| barrier | BMBIF 给 SNB/NCQ/CTCQ 的屏障请求 | 各单元 outstanding 计数、barrier FSM |
| DVM | CTCQ 经 EBIU/L2C/PIU 的控制事务 | CTCQ REQQ/RESPQ 和 DVM RID FIFO |

`ct_ciu_bmbif_kid` 把四个 PIU 的 barrier 请求编码进 4-entry FIFO，保存选中的 PIU 位并产生目标侧 `bar_req/mid/req_bus`；优先级和 FIFO 细节见 `ct_ciu_bmbif_kid.v:129-177`。`mid` 用于把目标响应回送到原 PIU。

## 4. PIU：core 侧协议适配和路由

### 4.1 `ct_piu_top`

`ct_piu_top` 的端口/总线编码在 `ct_piu_top.v:186-347`、`820-860`。AR 的分类依据地址属性、cache/snoop 属性和 route 位：

- `ar_ctc=&arsnoop` 时进入 CTCQ；非 barrier 且非 cacheable 进入 NCQ。
- cacheable 请求按地址位 `addr[6]` 选择 SNB0/SNB1；对应逻辑见 `ct_piu_top.v:871-877`。
- AR FIFO 为 2 项，创建和路由信息在 `ct_piu_top.v:879-957`；`arready` 由 FIFO 未满决定。

AW 使用相同的 cacheable/non-cacheable/双 SNB 路由原则，且区分 WNS/WS、write-through/evict 等属性；编码和路由位见 `ct_piu_top.v:962-1005`。写地址进入 WNS/WS 控制和对应 data FIFO，WNS 写数据 FIFO 深度为 2、WS 写数据 FIFO 深度为 4，见 `ct_piu_top.v:1039-1299`。CD FIFO 为 2 项，见 `ct_piu_top.v:1311-1362`。

AC 从 SNB0、SNB1、CTCQ 汇聚，`ct_prio NUM=3` 做公平选择，并受 CTCQ mask 控制；AC FIFO 深度为 2，见 `ct_piu_top.v:1413-1484`。CR FIFO 深度为 2；CR 依据 response queue 中保存的 xid 回到对应 PIU，见 `ct_piu_top.v:1514-1554`。

响应侧使用 12 项 response queue 和 8 项 CD SID FIFO（`ct_piu_top.v:1557-1678`），再用 535 bit 的 response/unpackage buffer 按 R/B 来源做优先级选择：R FIFO 深度 2、RACK FIFO 深度 8，B FIFO 深度 2、BACK FIFO 深度 8，见 `ct_piu_top.v:2242-2708`。R/B 会按保存的 mid/xid 分发回 core、SNB、NCQ 或 CTCQ。`ct_piu_top.v:1819-1840` 的 package buffer 明确优先 CD 于 WD；barrier FSM 在 `IDLE/REQ/WAIT/W_BAR_CMPLT/RESP` 间运行，见 `ct_piu_top.v:1995-2149`。

### 4.2 other IO、dummy 和 no-op

`ct_piu_other_io` 只是 `ct_piu_other_io_sync` 的封装，实例/连线在 `ct_piu_other_io.v:179-228`。sync 模块用 CSR select/wdata 处理寄存器访问，用 DCA 位区分 L2C read；字段定义、RID/tag/data/way/index 拆分在 `ct_piu_other_io_sync.v:216-285`。L2C 返回数据或寄存器完成后合成 PIU 响应，系统 debug、PM、interrupt 和 HPC enable 在 `ct_piu_other_io_sync.v:300-325` 传递。

`ct_piu_top_dummy` 对部分 AC/AR/CR 做占位握手，其余 R/B/ACK/sideband 输出为零，并将 `piu_xx_no_op` 置 1，见 `ct_piu_top_dummy.v:1-503`，尤其 `483-498`。`ct_piu_top_dummy_device` 将 device PIU 的 SNB 请求/grant 全部置零并置 no-op，见 `ct_piu_top_dummy_device.v:140-164`。`ct_piu_other_io_dummy` 的寄存器/L2C 请求全为零、`piu_xx_regs_no_op=1`，见 `ct_piu_other_io_dummy.v:73-84`。

## 5. BMBIF、SNB/SAB 和一致性路径

### 5.1 SNB 仲裁

每个 `ct_ciu_snb` 接入 PIU0-4、L2C PRF/SNPL2、外部 EBIU snoop，并向 SAB、L2C、VB、EBIU 和 PIU 返回 grant/response，端口在 `ct_ciu_snb.v:17-367`。其内部 `ct_ciu_snb_arb` 位于 `ct_ciu_snb_arb.v:19-522`，参数使用 `SAB_DEPTH/SAB_RDEPTH/SAB_WDEPTH` 和 `CORE_NUM=5`，见 `ct_ciu_snb_arb.v:979-984`。

- AR：PIU0-4 与 L2C PRF 为六路源，经 `ct_prio NUM=6` 选择，并产生 SAB read entry；同时处理 SNPL2 和外部 snoop 优先级，见 `ct_ciu_snb_arb.v:1051-1225`。
- AW：PIU 写、BMB barrier 等六路源经 `ct_prio NUM=6` 选择，写入 SAB write entry；WNS/WC/WB/EVICT 属性在 `ct_ciu_snb_arb.v:1231-1385`。
- CD/WD：五个 PIU 的一致性数据/写数据做仲裁，WD select FIFO 深度 8，见 `ct_ciu_snb_arb.v:1388-1538`。
- AC/CR/RACK/BACK：AC 对每个 core 有缓冲；CR、RACK、BACK 依据 SID 找回 SAB entry，见 `ct_ciu_snb_arb.v:1542-1814`。
- L2C/VB/EBIU：SAB 地址/data 请求分别经过 L2C buffer、VB buffer、EBIU read buffer，并把外部 R/B 和 barrier completion 解包回 PIU，见 `ct_ciu_snb_arb.v:1817-2275`。

### 5.2 SAB 和事务表项

`ct_ciu_snb_sab` 是一致性事务的状态/数据主体，实例化 24 个 `ct_ciu_snb_sab_entry`，并为 PIU AC、L2C、EBIU read/write、R/B response 配置年龄选择器；实例范围见 `ct_ciu_snb_sab.v:859-3327`、`3788-4908`。entry 的控制内容、地址和 data bus 布局见 `ct_ciu_snb_sab_entry.v:604-652`。

entry 状态包括 `IDLE/DEPD/L2C/SNOP/L2CR/L2CW/L2CA/MEMR/L2CT/MEMW/BAR/POP/CR/ECC_ERR`，见 `ct_ciu_snb_sab_entry.v:676-690`。它同时维护：

- 地址依赖和 barrier 依赖：将当前 AR/AW/SNPEXT index 与在途项比较，输出依赖；证据在 `ct_ciu_snb_sab_entry.v:2535-2558`。
- 对 core0-3 的 snoop 状态机：根据 AC 发送、等待 CR/CD/RACK，并在 `SNP0_*` 到 `SNP3_*` 状态间推进，见 `ct_ciu_snb_sab_entry.v:1122-1360`。
- L2C/EBIU 请求和完成：L2C request mask、MEMR/MEMW FSM 以及 EBIU packed bus，见 `ct_ciu_snb_sab_entry.v:930-931`、`1421-1571`。
- 部分写合并：按 byte enable 合并写数据，见 `ct_ciu_snb_sab_entry.v:2169-2240`。

`ct_ciu_snb_dp_sel` 通过每个 entry 的 age vector 只选择没有更老有效项的请求，见 `ct_ciu_snb_dp_sel.v:105-130`；`_16`/`_8` 变体分别按 16/8 深度处理响应选择，见 `ct_ciu_snb_dp_sel_16.v:98-115`、`ct_ciu_snb_dp_sel_8.v:66-75`。因此 SNB 能允许多个事务驻留，但对同一选择点保持年龄公平和依赖约束，并非简单单请求直通。

### 5.3 VB：L2/SNB writeback 汇聚

`ct_ciu_vb` 接收 L2C bank0/1 和 SNB0/1 的 writeback AW/W，选择后向 EBIU 输出 cacheable writeback 的 AW/W，并把外部 B grant/response 以及地址依赖反馈给来源；端口分组见 `ct_ciu_vb.v:17-150`。它按 `vb_ebiu_aw*` 和 `vb_ebiu_w*` 两条外部通道发出 40-bit 地址、128-bit data、strobe、last、mid/id 等字段；writeback 数据的分片和 `wlast` 计算见 `ct_ciu_vb.v:509-542`。

每个 `ct_ciu_vb_aw_entry` 保存 68-bit writeback 地址控制和 535-bit 数据，维护 AW/W valid，比较 EBIUIF/SNB external index 以产生地址命中/依赖，见 `ct_ciu_vb_aw_entry.v:130-227`。VB 的 AW/W 控制时钟只在 entry 创建、EBIU grant 或数据活动时打开，见 `ct_ciu_vb.v:544-582`；因此它是 SNB/L2C 到 EBIU 的独立 writeback 缓冲，而不是把写回重新走 NCQ。

### 5.4 L2CIF 双 bank

`ct_ciu_l2cif` 的端口和两 bank 边界见 `ct_ciu_l2cif.v:17-402`。bank0 接 SNB0，bank1 接 SNB1；每个 bank 的优先级是 CTCQ > DCA > SNB，地址/data valid 互斥条件见 `ct_ciu_l2cif.v:670-713`。SNB0/1 响应直接回传；DCA 响应可来自任一 bank；CTCQ 需要同时等待目标 bank ready 和完成，见 `ct_ciu_l2cif.v:716-873`。

DCA 读请求由 PIU 选择器送入 `RD_IDLE/RD_REQ/RD_CMPLT` FSM，按 index 位 `index[6]` 选择 bank，见 `ct_ciu_l2cif.v:919-1054`。PRF/SNPL2 也按地址低位分到两 bank，向 SNB0/1 返回 data/完成，见 `ct_ciu_l2cif.v:1061-1184`。HPCP 的 read/write access/miss increment 按 PIU 汇出，见 `ct_ciu_l2cif.v:1187-1201`。

## 6. NCQ：非缓存、APB、外部 EBIU 和顺序控制

`ct_ciu_ncq` 接收四个 PIU 的 AR/AW/WCD、BMB barrier、APBIF 和 EBIU 返回，端口范围见 `ct_ciu_ncq.v:17-294`。它不是一致性 cache path，而是 non-cacheable/system-order path：

- AR 先经过 `ct_prio NUM=4` 和 2-entry RAQ；源码注释明确 RAQ 用于切断 EBIU ready 到 PIU grant 的长路径，见 `ct_ciu_ncq.v:628-745`。
- 地址目的地判断在 `ct_ciu_ncq.v:780-829`：WO/SO 请求去 EBIU；SO 且地址高位命中 `sysio_ciu_apb_base[39:27]` 时去 APBIF。特殊 ID `SO_ID=5'b11101`、`WO_EX_ID=5'b11110` 在 `ct_ciu_ncq.v:827-829` 附近定义/使用。
- RDQ 为 2 项，R 响应按 mid 回 PIU，见 `ct_ciu_ncq.v:845-944`。AW 经 2-entry WAQ，支持 APB/EBIU 分发；`aw_needissue` 对 exclusive write 由 GM success 决定，见 `ct_ciu_ncq.v:950-1231`。
- WOQ 深度 16、WDQ 深度 2、DSQ 深度 16、WBQ 深度 2，分别保持写地址/数据顺序、目的地和 B 响应，见 `ct_ciu_ncq.v:1234-1560`。DSQ 明确保存 APB-vs-EBIU 目的地。
- barrier 由 `bmbif_ncq_shareable` 和每个 PIU 的 barrier valid/ostd completion 管理；PIU2/3 的 outstanding 计数硬置 0，见 `ct_ciu_ncq.v:1570-1616`、`1730-1784`。当总 outstanding 完成时 `ncq_xx_no_op` 有效。

`ct_ciu_ncq_gm` 为 core0/core1 的 exclusive/global monitor：读带 lock 时记录地址，写地址匹配时产生 success 并清除锁；core2/core3 的 GM 在 `ct_ciu_ncq.v:1116-1158` 被硬置零。该机制只影响 NCQ exclusive write issue，不改变 SNB cache 一致性状态机。

## 7. CTCQ：DVM、barrier 和多目标完成

`ct_ciu_ctcq` 连接 PIU CTCQ AR/CR/R/AC、EBIU DVM AC/CR、L2C CTCQ，端口见 `ct_ciu_ctcq.v:17-195`。它将一个控制请求拆成可能的 PIU、L2C、EBIU 目标，只有所有被命中的目标完成后才释放 response。

- DVM/barrier FSM 状态为 `S_IDLE/S_WFB/S_WFE/S_REQ/S_RESP/S_WFC/S_WFR/S_CMPLT`，barrier request 由 BMBIF 产生，完成按 `bar_mid` 回 PIU，见 `ct_ciu_ctcq.v:524-653`。
- PIU0-3 加 EBIU DVM 共五路请求用 `ct_prio NUM=5` 选择，见 `ct_ciu_ctcq.v:746-839`。DVM aim 解码包括 TLB/I-cache/L2C、shared domain、op sync 等；`aim_ebiu`、PIU/L2C aim 和双传输判断在 `ct_ciu_ctcq.v:843-890`。
- REQQ 有 8 个 `ct_ciu_ctcq_reqq_entry`，每项保存地址、目标 aim、response queue id、RID、mid 和各目标 pending 位；实例范围 `ct_ciu_ctcq.v:1609-1917`，entry 行为见 `ct_ciu_ctcq_reqq_entry.v:162-173`、`380-400`。
- RESPQ 有 16 个 `ct_ciu_ctcq_respq_entry`；每项保存 DVM/valid 和 EBIU、L2C、PIU 完成位，只有所有目标完成才 pop，见 `ct_ciu_ctcq.v:1360-1467`、`ct_ciu_ctcq_respq_entry.v:87-185`。
- EBIU DVM RID FIFO 深度 16，L2C/PIU/EBIU 各有独立 pop/completion 路径；这保证一个控制事务的多目标完成不会被单一返回提前结束。

## 8. EBIUIF、EBIU channels 和外部总线

### 8.1 EBIUIF

`ct_ciu_ebiuif` 是 CIU 与 `ct_ebiu_top` 之间的桥，端口见 `ct_ciu_ebiuif.v:15-148`。SNB0/1 外部 AR 经 `ct_prio NUM=2` 仲裁，见 `ct_ciu_ebiuif.v:296-339`；外部 R 依据 mid/route 回 SNB。AC snoop 按 snoop code 解码：`DVM_COMP=1110`、`DVM_OP_SYNC=1111` 进入 CTCQ，否则按 `acaddr[6]` 进入 SNB0/SNB1，见 `ct_ciu_ebiuif.v:357-388`。当前 CR/CD 选择路径是 dummy/零值，见 `ct_ciu_ebiuif.v:401-407`。

### 8.2 `ct_ebiu_top` 和 read channel

`ct_ebiu_top` 将 CTCQ DVM、EBIUIF、NCQ、VB 请求汇聚到外部 `pad_ebiu_*`，实例 read channel、dummy snoop、write channel、lowpower，见 `ct_ebiu_top.v:15-190`、`557-765`。`ct_ebiu_read_channel` 在这些源之间选择 AR、向外部发起读，并用 2-entry R FIFO 缓冲外部返回；FIFO 实例见 `ct_ebiu_read_channel.v:537`。外部 R 的 valid/ready、RID/RESP/LAST 和各源 grant 在该模块头部端口及 `ct_ebiu_read_channel.v:17-150` 定义。

### 8.3 write channel、NCWT、CAWT

`ct_ebiu_write_channel` 汇聚 NCQ、VB/SAB cacheable write 和相关 write data，输出外部 AW/W/B；B FIFO 深度 2，见 `ct_ebiu_write_channel.v:820-930`。它用两个表维护写事务和地址依赖：

- 16 个 `ct_ebiu_ncwt_entry` 跟踪 non-cacheable write。entry 保存地址 `[13:6]`、ID 和 B response；对 NCQ AR/AW 同 index 产生依赖并按 ID 选回 PIU，见 `ct_ebiu_ncwt_entry.v:115-217`。这覆盖 NCQ 写后读/写排序以及 `WO_EX_ID` 的特殊处理。
- 32 个 `ct_ebiu_cawt_entry` 跟踪 cacheable/VB write，实例范围 `ct_ebiu_write_channel.v:2033-2901`。entry 将在途 cacheable 写地址与 EBIUIF read、VB write 和 SNB0/1 external snoop index 比较，产生 hit，见 `ct_ebiu_cawt_entry.v:101-152`。

write channel 的 create/pop 指针和 no-op 逻辑见 `ct_ebiu_write_channel.v:1480-1517`；门控控制时钟分别由 AW、WD、NCQ special-order、B/back 活动产生，见 `ct_ebiu_write_channel.v:2926-3057`。因此外部写允许驻留/乱序完成，但依赖表会阻止同地址或相关 snoop/读路径违反顺序。

`ct_ebiu_snoop_channel_dummy` 将 AC/CR/CD 输出清零并置 no-op，见 `ct_ebiu_snoop_channel_dummy.v:70-78`。`ct_ebiu_lowpower` 将 write/snoop/read 三路 no-op 求与，产生 EBIU no-op；同时固定 `cactive=1`，并对 `pad_ebiu_csysreq` 产生同步的 `csysack`，见 `ct_ebiu_lowpower.v:58-74`。

## 9. APB bridge、CIU 配置寄存器和其他 IO

### 9.1 `ct_ciu_apbif`

APBIF 接 NCQ 的 APB AR/AW/W 以及 response grant，端口见 `ct_ciu_apbif.v:15-146`。内部 FSM 为 IDLE/WADDR/REQ/PEND（状态译码 `ct_ciu_apbif.v:303-306`）：读优先于写地址，APB 时钟使能有效且无挂起响应时产生 NCQ grant，见 `ct_ciu_apbif.v:308-312`。写数据从 128 bit NCQ WDATA 按 `addr[3:2]` 取 32 bit，见 `ct_ciu_apbif.v:346-360`。

地址译码为 PLIC、CLINT、HAD、L2PMP、RMR：宏和选择逻辑见 `ct_ciu_apbif.v:363-392`；L2PMP 再按 `apbif_addr[15:14]` 选择四个 core。APB ready/error/读数据被锁存，再通过 NCQ R/B 两类返回；读响应复制到 128 bit，写响应使用 B，见 `ct_ciu_apbif.v:410-475`。其门控时钟由请求、未完成状态和响应 grant 生成，见 `ct_ciu_apbif.v:480-492`。

### 9.2 `ct_ciu_regs`/`ct_ciu_regs_kid`

`ct_ciu_regs` 汇聚 core0/1 PIU CSR 操作、L2C access/miss 计数和 ECC 状态，输出 CIU/L2C/SysIO 门控、SMPEN、barrier/DVM/snoop disable、NCQ SO outstanding disable、L2C latency/setup/IPRF/TPRF/reset 等配置；端口证据在 `ct_ciu_regs.v:15-114`。它实例化两个 `ct_ciu_regs_kid`，见 `ct_ciu_regs.v:579-606`。

`ct_ciu_regs_kid` 按 core 保存 CSR/性能计数器和 per-core 配置；寄存器地址参数 `SMPR=4'h4`、`TEEM=5`、`L2RA=8`、`L2RM=9`、`L2WA=A`、`L2WM=B`、`L2OF=C` 定义在 `ct_ciu_regs_kid.v:133-139`。因此 APB/CSR 配置最终影响的是 CIU 的仲裁门控、barrier/DVM/SO 行为、L2C 时序和 HPCP 统计，而不是新增数据通道。

## 10. 通用 FIFO、优先级与时钟复位

`ct_fifo` 默认深度 2、数据宽度 6、指针宽度 1；用 valid 位、轮转 create pointer 和 pop pointer 管理 full/empty，见 `ct_fifo.v:30-32`、`68-154`。目录中各 FIFO 的实际深度由实例参数决定，不能用默认值替代，例如 PIU response queue、NCQ DSQ、CTCQ DVM FIFO 和 EBIU table 都有独立深度。

`ct_prio` 默认 NUM=2，复位优先矩阵后按公平轮转更新，见 `ct_prio.v:23-56`。CIU 关键仲裁规模为：PIU AC 3 路、SNB AR/AW 6 路、NCQ AR/AW 4 路、CTCQ 5 路、EBIUIF SNB AR 2 路；这些规模分别见前述实例行号。

复位统一以 `cpurst_b` 或局部 `core{0,1}_fifo_rst_b` 的低有效同步/异步条件初始化 FIFO、状态机和 valid 位。顶层用 `ciu_no_op` 汇聚 PIU、BMBIF、SNB0/1、NCQ、CTCQ、EBIU、VB、L2C 和寄存器侧 no-op，见 `ct_ciu_top.v:4059-4064`；core0/1 只有在 AR/AW 或 PIU CSR 请求且未被 L2 reset/flush gate 时打开请求门，见 `ct_ciu_top.v:4071-4087`。顶层 `ciu_top_clk_en_f` 在复位时置 1，由请求置位、全 no-op 时清零，门控 `forever_cpuclk`，见 `ct_ciu_top.v:4092-4110`。

各子模块还有局部门控：PIU 的 FIFO/response 活动、NCQ 的 outstanding/队列、CTCQ 的 REQQ/RESPQ、SNB 的 buffer 活动、APB 请求、EBIU read/write table 活动分别产生 gated clock enable。EBIU write 的局部门控证据在 `ct_ebiu_write_channel.v:2926-3057`，APB 在 `ct_ciu_apbif.v:480-492`，EBIU lowpower/no-op 在 `ct_ebiu_lowpower.v:58-74`。

## 11. 多核、双 bank、缓存一致性和乱序结论

1. **有效 core/PIU 数量。** 真实 PIU 协议逻辑只实例化 core0/core1；core2/core3 使用 `ct_piu_top_dummy`，device PIU 使用 `ct_piu_top_dummy_device`。但 SNB/EBIU 表项仍按 PIU0-3 保存选择位，以支持产品化多核接口扩展；NCQ GM 只有 core0/1 有真实 tracker，core2/3 为零。
2. **双 bank。** SNB0→L2C bank0、SNB1→L2C bank1；cacheable 请求由 PIU 的 `addr[6]` 选择，L2CIF 又按 bank 的 CTCQ/DCA/SNB 优先级复用。这样可以并行承接两个 bank，但 CTCQ 的跨 bank 完成要同时等待相关 bank。
3. **一致性。** SNB/SAB entry 保存 cacheable 事务的依赖、snoop、L2C、外部 memory 和响应状态；AC/CR/CD/RACK/BACK 形成完整 snoop/响应往返。`ct_ciu_snb_sab_entry.v:1122-1662` 与 `2535-2558` 是该结论的直接证据。
4. **非缓存访问。** PIU 将非 cacheable/SO/W-O 路径送 NCQ；NCQ 再按 APB base 命中情况选择 APBIF 或外部 EBIU，并用 RAQ/WAQ/WOQ/WDQ/DSQ/RDQ/WBQ 和 outstanding counter 保持可观测顺序。
5. **乱序和公平。** 请求可以在多个 FIFO、SAB entry、CTCQ REQQ/RESPQ、NCWT/CAWT 中驻留，并按 mid/xid/SID 回送，说明返回不要求全局 in-order；但年龄选择器、依赖比较、barrier completion、write table hit 和各目标 completion 位限制了同地址/一致性相关事务的乱序，避免协议可见的错误顺序。
6. **配置。** `ct_ciu_regs`/APB 只改变门控、L2C 时序、SMP/barrier/DVM/SO 和统计等配置；数据路径的基本分类仍由 PIU 的 cache/snoop/address route 位和 NCQ APB base 命中逻辑决定。

## 12. 文件级证据索引

| 文件 | module/内容 | 关键行 |
|---|---|---|
| `gen_rtl/ciu/rtl/ct_ciu_top.v` | CIU 顶层端口、实例、no-op/请求门/时钟 | 20-374, 481-559, 1849-3999, 4059-4110 |
| `ct_ciu_bmbif.v`, `ct_ciu_bmbif_kid.v` | 四目标 barrier 汇聚与 PIU grant | `ct_ciu_bmbif.v:197-295`; `ct_ciu_bmbif_kid.v:129-177` |
| `ct_piu_top.v` | AR/AW 分类、FIFO、AC/CR、R/B、barrier | 820-1172, 1413-1678, 1819-2149, 2242-2715 |
| `ct_piu_other_io*.v` | CSR/DCA/L2C read、dummy | `ct_piu_other_io.v:179-228`; `ct_piu_other_io_sync.v:216-325`; dummy `73-84` |
| `ct_ciu_snb*.v` | SNB 仲裁、SAB、24 entry、年龄选择和响应 | `ct_ciu_snb.v:634-892`; `ct_ciu_snb_arb.v:1051-2275`; `ct_ciu_snb_sab.v:859-4908` |
| `ct_ciu_snb_sab_entry.v` | 一致性 entry 状态、snoop、依赖、数据合并 | 604-690, 930-931, 1122-1662, 2169-2240, 2535-2558 |
| `ct_ciu_l2cif.v` | 双 bank 复用、DCA/CTCQ/SNB、PRF/SNPL2 | 670-873, 919-1201 |
| `ct_ciu_vb.v`, `ct_ciu_vb_aw_entry.v` | L2/SNB writeback AW/W 缓冲、外部 B、地址依赖 | `ct_ciu_vb.v:17-150, 509-582`; `ct_ciu_vb_aw_entry.v:130-227` |
| `ct_ciu_ncq*.v` | NCQ 队列、APB/EBIU 分发、GM、barrier | `ct_ciu_ncq.v:628-829, 845-1231, 1234-1867`; `ct_ciu_ncq_gm.v:76-101` |
| `ct_ciu_ctcq*.v` | DVM/barrier 多目标请求/响应 | `ct_ciu_ctcq.v:524-1599`; REQQ `162-400`; RESPQ `87-185` |
| `ct_ciu_ebiuif.v` | SNB AR、AC DVM/SNB decode、EBIU R | 296-407 |
| `ct_ebiu_top.v`, `ct_ebiu_read_channel.v` | EBIU 读/写/snoop/lowpower 组合 | `ct_ebiu_top.v:557-765`; read FIFO `ct_ebiu_read_channel.v:537` |
| `ct_ebiu_write_channel.v` | AW/W/B、NCWT/CAWT、依赖和门控 | 820-930, 1480-1517, 1533-2022, 2033-2924, 2926-3057 |
| `ct_ebiu_ncwt_entry.v`, `ct_ebiu_cawt_entry.v` | non-cacheable/cacheable 写跟踪 | NCWT 115-217；CAWT 101-152 |
| `ct_ebiu_snoop_channel_dummy.v`, `ct_ebiu_lowpower.v` | dummy snoop、系统低功耗握手 | dummy 70-78；lowpower 58-74 |
| `ct_ciu_apbif.v` | NCQ-APB FSM、地址译码、R/B 返回、门控 | 303-312, 317-360, 363-475, 480-492 |
| `ct_ciu_regs.v`, `ct_ciu_regs_kid.v` | CIU/L2C/SMP/HPC 配置寄存器 | `ct_ciu_regs.v:15-114, 579-606`; `ct_ciu_regs_kid.v:133-139` |
| `ct_fifo.v`, `ct_prio.v` | 通用 FIFO、公平优先级 | FIFO 30-154；prio 23-56 |

本报告没有修改 `gen_rtl/ciu/rtl` 下任何 RTL 文件；仅新增本文档。
