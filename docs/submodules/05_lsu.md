# LSU（加载存储单元）设计分析

## 1. 范围、阅读结论与证据约定

本文只分析 `gen_rtl/lsu/rtl`。该目录本次盘点得到 70 个 Verilog 文件，约 65k 行，包含 `ct_lsu_top`、Load/Store 流水级、D-cache、LQ/SQ、RB/WMB/VB/LFB、PFU、snoop、一致性/原子控制以及 SRAM wrapper。本文没有修改任何 RTL；所有结论均以本目录中的端口、组合逻辑、寄存器状态和顶层实例为依据。

文中证据使用 `文件:行号` 表示，例如 `gen_rtl/lsu/rtl/ct_lsu_top.v:2797`。行号按当前工作区 UTF-8 文件计数；若宏展开或上层模块另有约束，本文只把本目录能直接证明的内容作为“真实互联”结论。

总体上，LSU 是一个以顺序提交为边界、以多个非阻塞队列承载未完成访问的两发射 Load/Store 子系统：

```text
IDU pipe3(load) ─> ld_ag ─> ld_dc ─> ld_da ─> ld_wb ─> IDU/RTU pipe3
                         │       │       │
                         │       │       ├─ LQ / forward / RB / LFB
                         │       └───────── D-cache lookup / dependency
                         └─ MMU VA0/PA0

IDU pipe4(store/ICC) ─> st_ag ─> st_dc ─> st_da ─> st_wb ─> RTU pipe4
                          │        │       │
                          │        │       ├─ SQ / WMB / VB / RB / snoop
                          │        └──────── D-cache tag/dirty lookup
                          └─ MMU VA1/PA1

RB/WMB/PFU ─> bus_arb ─> BIU AR/AW/W
BIU AC ─> snoop arbiter ─> SNQ/CTCQ ─> BIU CR/CD
```

当前生成配置还保留了若干未启用路径：顶层 VMB 实例被注释，`vmb_empty` 被硬连为 1，ECC 相关模块和数据通路被注释或置零；因此，端口名虽然保留了向量/ECC能力，不能据此推断该配置已经实现这些功能（`ct_lsu_top.v:6358-6364`、`ct_lsu_ld_da.v:2271-2353`、`ct_lsu_st_da.v:804-806`）。

## 2. 顶层实例与外部互联

### 2.1 `ct_lsu_top` 的边界

`ct_lsu_top` 的端口从 `ct_lsu_top.v:17` 开始，外部边界可以按以下几类理解。

| 外部模块/协议 | LSU 端口实物 | 作用与证据 |
|---|---|---|
| BIU | `biu_lsu_ac_*`、`biu_lsu_ar_ready`、`biu_lsu_aw_*_grnt`、`biu_lsu_w_*_grnt`、`biu_lsu_r_*`、`biu_lsu_b_*`、`biu_lsu_cr_ready`、`biu_lsu_cd_ready` | AC 是外部 snoop 请求输入；AR/AW/W 是 LSU 发出的读写请求；R/B 是完成/响应；CR/CD 是 snoop 响应。端口定义见 `ct_lsu_top.v:18-36`，LSU 出口见 `ct_lsu_top.v:181-244`。 |
| CP0 | D-cache 开关/清除/无效、prefetch、AMR、flush/forward disable、权限/虚拟模式、timeout 等 | 控制缓存、预取、顺序与异常策略；端口集中在 `ct_lsu_top.v:37-81`。 |
| IDU/IU | pipe3 Load RF，pipe4 Store/ICC RF，pipe5 Store data，以及 LSU 的 AG/DC/WB forwarding、queue full/wakeup/pop | Load 从 `idu_lsu_rf_pipe3_*` 进入；Store/ICC 从 `idu_lsu_rf_pipe4_*` 进入；Store data 从 pipe5 进入，定义见 `ct_lsu_top.v:82-179`。回送端口从 `ct_lsu_top.v:272` 起。 |
| MMU | VA0/VA1/VA2 请求，PA、页属性、PF/UTLB miss、stall/busy、TLB wakeup | Load/Store 各自使用 VA0/VA1；PFU 使用 VA2。MMU 端口见 `ct_lsu_top.v:393-417`、`ct_lsu_top.v:462-493`。 |
| RTU/flush | commit iid、flush、spec-fail、fence、异常提交 | 影响 LQ/SQ pop、队列清空、WB 异常和重启，端口见 `ct_lsu_top.v:418-461`、`ct_lsu_top.v:496-511`。 |
| IFU | `ifu_lsu_icache_inv_done` | 指令缓存无效操作的完成反馈，`ct_lsu_top.v:180`。 |

目录内没有 `ciu_*` 或 `l2c_*` 顶层端口；因此不能把 LSU 描述成直接连 CIU/L2C 的独立模块。可直接确认的是：LSU 的一致性传输走 BIU 的 AC/CR/CD，L2 预取走 PFU/BIU，缓存属性通过 BIU AR/AW 的 cache/domain/bar/snoop/prot 等字段携带。这个边界由 `ct_lsu_top.v:18-36`、`181-244` 和 `6036-6303` 的 `bus_arb`/`pfu` 实例映射共同证明。上层把 BIU 连接到 CIU/L2C 是本目录之外的集成关系，本文不臆测其内部实现。

### 2.2 顶层实例顺序

顶层实例顺序就是 LSU 的主要数据与控制拓扑：

| 行号 | 实例 | 作用 |
|---:|---|---|
| 2797 | `ct_lsu_ld_ag` | pipe3 Load 地址生成、MMU VA0、早期 forwarding/等待 |
| 2943 | `ct_lsu_st_ag` | pipe4 Store/ICC 地址生成、MMU VA1 |
| 3088 | `ct_lsu_sd_ex1` | Store data/第二拍数据路径辅助 |
| 3119 | `ct_lsu_mcic` | machine-check/incoherent load 处理 |
| 3159 | `ct_lsu_dcache_arb` | 多请求源的 D-cache 读写端口仲裁 |
| 3372 | `ct_lsu_dcache_top` | tag/dirty/data array 封装 |
| 3416 | `ct_lsu_ld_dc` | Load DC、LQ 创建、依赖/命中/转发判定 |
| 3638 | `ct_lsu_st_dc` | Store DC、SQ 创建、tag/dirty 命中与重启 |
| 3801 | `ct_lsu_lq` | 16 项 Load queue |
| 3843 | `ct_lsu_sq` | 12 项 Store queue |
| 4016 | `ct_lsu_ld_da` | Load data select、forward、miss/RB/LFB、WB |
| 4269 | `ct_lsu_st_da` | Store commit、D-cache 更新、RB/WMB/VB/ICC |
| 4451 | `ct_lsu_rb` | 8 项 Read buffer，处理 cache refill/NC/atomic response |
| 4631 | `ct_lsu_wmb` | 8 项 write merge buffer |
| 4873 | `ct_lsu_wmb_ce` | SQ pop 到 WMB 的 create/merge 分类 |
| 4961 | `ct_lsu_ld_wb` | Load WB、RTU pipe3、IDU forwarding |
| 5084 | `ct_lsu_st_wb` | Store WB/RTU pipe4 |
| 5132 | `ct_lsu_lfb` | 8 地址项/2 数据项的 line fill buffer |
| 5248 | `ct_lsu_vb` | victim buffer 地址/回写状态机 |
| 5406 | `ct_lsu_vb_sdb_data` | VB 的 3 项 512-bit 数据/ snoop data buffer |
| 5462 | `ct_lsu_snoop_req_arbiter` | AC 请求分流和 SNQ/CTCQ 顺序记录 |
| 5503 | `ct_lsu_snoop_resp` | SNQ/CTCQ CR/CD 归并到 BIU |
| 5525 | `ct_lsu_snoop_ctcq` | cache/TLB control transaction queue |
| 5562 | `ct_lsu_snoop_snq` | normal snoop queue |
| 5678 | `ct_lsu_lm` | 原子锁/Load-Reserved 相关状态 |
| 5739 | `ct_lsu_amr` | AMR/写合并窗口判定 |
| 5760 | `ct_lsu_icc` | D-cache invalidate/read/clean 控制 |
| 5830 | `ct_lsu_ctrl` | 全局 full/wakeup/stall/fence/异常汇总 |
| 6036 | `ct_lsu_bus_arb` | RB/WMB/VB/PFU 到 BIU 的请求选择 |
| 6205 | `ct_lsu_pfu` | L1/L2 stride prefetch、MMU/BIU/LFB 交互 |
| 6306 | `ct_lsu_cache_buffer` | split-load 的 16B/边界缓存 |
| 6332 | `ct_lsu_spec_fail_predict` | no-spec store 与 load speculation fail 跟踪 |

这些实例和行号来自 `ct_lsu_top.v:2797-6332` 的实例声明；顶层还在 `ct_lsu_top.v:6358-6364` 明确关闭 VMB/ECC 路径。

## 3. Load 流水与请求生命周期

### 3.1 AG：地址、类型、MMU 和异常前置

`ct_lsu_ld_ag` 接收 IDU pipe3 的 iid、PC、base/offset、访问大小、原子/向量/非推测等信息，并对接 MMU0 与 D-cache arb；端口和输出组见 `ct_lsu_ld_ag.v:17-302`。

- 参数包含 `LSIQ_ENTRY=12`、`VMB_ENTRY=8`、`PC_LEN=15`，见 `ct_lsu_ld_ag.v:533-540`。
- AG valid 在 flush 时清除，在 stall 时保持，正常情况下从 pipe3 采样，见 `ct_lsu_ld_ag.v:582-592`；源操作数、iid、preg/vreg、异常相关字段在 `626-692` 保存。
- 地址由 base 加偏移/偏移加法路径生成；跨边界第二条地址选择 `offset_plus`，见 `ct_lsu_ld_ag.v:785-810`。这解释了为什么一个未对齐/跨 4K Load 可能形成两个 LQ 项和两个 cache-buffer 半块。
- 普通 Load、LR、LD-AMO、prefetch 类型映射在 `815-835`；当前向量相关 `ld_ag_inst_vls`、`ld_ag_inst_fof`、`ld_ag_vmb_merge_vld` 等多处被硬连关闭，不能按完整向量 LSU 推断。
- 访问大小、对齐、16-byte mask 与低/高半块选择在 `842-985`。
- MMU 请求 `lsu_mmu_va0_vld` 基于 AG 指令有效，VA 主要使用 base；跨页、原子未提交、D-cache stall、misalign 或 flush 会形成 abort，见 `1032-1058`。MMU 返回 CA/BUF/SEC/SH/SO、UTLB miss/PF 等属性，PA 由 PPN 与 VA 页内部分拼接，见 `1062-1083`。
- D-cache 请求使用 PA tag/index，tag index 取 `PA[14:6]`，并按访问大小产生 bank enable/low/high index，见 `1122-1190`。
- 异常包括 misalign、page fault、LDAMO 非 cacheable/access fault；异常向量映射和 `expt_vld` 在 `1199-1241`。Load PF/atomic PF 与 access fault 的具体 DC 级向量也在 `ct_lsu_ld_dc.v:1212-1267` 再次掩码。
- stall/restart 的核心条件是跨 4K、首半块特殊属性、D-cache arb 未得、MMU stall、atomic 尚未 commit，见 `1244-1336`。其中注释明确要求依赖、TLB 和 cache 资源在正确顺序下重新启动（`1287-1293`）。
- AG 产生 `ld_ag_dc_inst_vld`、load-ahead/early-forward、IDU 等待/预测信号，见 `1341-1456`。当前 ahead predict 逻辑有效，但向量 ahead 路径仍有硬连关闭部分。

### 3.2 DC：依赖、LQ、tag hit 与前递

`ct_lsu_ld_dc` 的输入集合已经体现它是 Load 的冲突/命中中心：AG、D-cache arb tag/borrow、LQ/SQ/WMB/PFU/RB、MMU busy/en 等端口在 `ct_lsu_ld_dc.v:17-456`，阶段参数在 `789-796`。

- DC 锁存 AG 信息、异常、VPN、访问属性，见 `1074-1167`；borrow 记录 D-cache arb 借用者，覆盖 MMU、ICC、SNQ、VB 等来源，见 `1008-1032`。
- 异常屏蔽包括 misalign-no-page/PF、LDAMO 非 CA 的额外 access fault；向量码在 `1212-1267`：普通 misalign 为 4，原子 misalign 为 6，Load PF 为 13，原子 PF 为 15，带 page 的 access fault 为 5。
- LQ 创建需要 iid 未重复、无 UTLB miss、无异常，见 `1283-1319`；跨边界的第二项在 `1323` 附近创建，并可因为 cache buffer 命中而改变创建条件。`ld_dc_lq_create_vld` 还会避开被 Store 地址依赖判定丢弃的情况。
- 对 LQ/SQ/WMB 的查找信号在 `1325-1348`；与同周期 Store DC 的直接依赖在 `1375-1400`。
- forwarding 优先从 SQ 取最新 Store 数据，只有 SQ 未命中/无依赖时再看 WMB；mask 选择在 `1407-1427`。这是真实的数据顺序协议，而不是只由队列年龄推断的抽象优先级。
- restart 依次处理 UTLB miss、立即依赖、LQ full，并考虑 TLB busy，见 `1435-1475`。
- D-cache tag compare 读出的 store/load tag 采用两路：load tag 每路含 tag 与 valid，way0 为 `tag[25:0]`+valid bit26，way1 为 `tag[52:27]`+valid bit53；与 `PA[39:14]` 比较，见 `1600-1649`。`ld_dc_dcache_hit` 是 way0/way1 的合取，低/高 16B 区域分别判定。
- `ld_dc_cb_addr_create_vld` 在 `1743-1774` 创建 cache buffer 地址；要求 load 有效、无异常/UTLB、无同 index 写冲突。命中 cache buffer 且未取消、无 LQ hit 时允许 merge。
- D-cache hit 且没有 forward disable/异常/Store-WMB 取消时产生 ahead WB，见 `1777-1800`；向量 ahead 当前关闭。

### 3.3 DA：数据选择、miss、RB/LFB 和 WB

`ct_lsu_ld_da` 接收八个 32-bit D-cache bank、DC 控制、SQ/WMB/RB/LFB/LM 反馈和 forwarding 数据，输出 Load 数据、LQ/WB/IDU/RTU、RB/LFB/MCIC 等控制；子模块 `ct_lsu_rot_data` 在 `ct_lsu_ld_da.v:1872`、`1946` 实例化，用于字节旋转/选择。

核心语义如下：

1. 命中路径优先组合 D-cache 数据、SQ/WMB forward、cache-buffer 边界数据，并按 sign/size 形成 64-bit WB 数据。
2. cache miss、跨行/跨页、原子、MMU borrow 等会生成 RB create；异常和 forward discard 会抑制 create。RB/LFB/LM 同 index 或 ECC 条件会使本次创建丢弃，并在需要时改为 LFB wakeup，见 `ct_lsu_ld_da.v:2016-2142`。
3. 第二个 split Load 可走 RB merge，相关判断在 `2109-2134`；`ld_da_rb_create_lfb` 以 page CA 属性决定是否按 line fill 处理。
4. SQ/WMB multi-forward、命中 index 和 dependency discard 在 `2181-2263` 汇总，同时产生 LQ/SQ/WMB/IDU 的等待、重启、forward 状态。
5. ECC 相关 stall/wakeup/error 输出当前整体置零或实例注释掉，见 `2271-2353`，所以不能以端口名推断 ECC 已在该配置中启用。
6. cache buffer 接收 D-cache 命中的低/高 128-bit 数据，要求无异常/flush/forward，见 `2355-2374`；PFU、RB/VB/SNQ/ICC/MMU borrow 接口分别在 `2376-2504`。
7. WB 请求、LQ pop/IDU 结果在 `2404-2608`；split miss latch 与 speculation-fail 检查在 `2650-2702`。

### 3.4 WB：多个返回源竞争 pipe3

`ct_lsu_ld_wb` 的输入同时包含 DA 直接数据、RB refill/NC 数据、WMB forwarding 数据和 VMB 数据，输出 IDU pipe3 preg/vreg writeback 与 RTU pipe3 异常/完成，端口定义见 `ct_lsu_ld_wb.v:17-136`、`148-258`。其本质是返回源和数据格式化级：

- 保存数据、iid、preg/vreg、sign-select、异常、flush、spec-fail 等字段，寄存器定义在 `261-308`。
- 直接 DA、RB、WMB 请求在该级汇合，产生 `ld_wb_data_vld`、`ld_wb_rb_cmplt_grnt`、`ld_wb_rb_data_grnt`、`ld_wb_wmb_data_grnt`，再输出 IDU forward 和 RTU pipe3 完成/异常。
- 通过 `rot_data` 结果和 sign-select 形成整型/向量写回；同一个返回通道上还保留 vreg expand/duplicate 信号。由于顶层把向量 VMB 置空，当前配置主要使用标量路径（`ct_lsu_top.v:6358-6361`）。

## 4. Store 流水与提交边界

### 4.1 AG/DC

`ct_lsu_st_ag` 与 Load AG 对称但额外识别 ICC、cache/TLB 操作、fence 和 store/atomic 类型；输入 pipe4、MMU1、LM、D-cache arb，端口见 `ct_lsu_st_ag.v:17-302`，参数见 `538-544`。

- pipe4 有效和数据采样在 `ct_lsu_st_ag.v:550-671`；地址生成在 `790-812`。
- 指令类型覆盖普通 Store、AMO、ICC、D-cache/I-cache/L2/TLBI 操作，见 `815-856`。因此 `pipe4_icc` 并不是普通 Store 的别名，而是由后级 `ct_lsu_icc`/SQ 分类处理。
- 对齐/bytes/mask 在 `860-1008`；MMU abort、CA/BUF/SEC/SH/SO 和 PA 形成在 `1052-1117`。
- D-cache tag/dirty 请求在 `1125-1158`；原子未 commit、跨 4K、MMU/D-cache stall 会像 Load 一样阻塞或重启。

`ct_lsu_st_dc` 接收 AG、D-cache arb 的 tag/dirty/borrow、SQ 和 MMU 反馈，输出 SQ create、DA 控制和 restart/wakeup；参数在 `ct_lsu_st_dc.v:561-568`。

- DC 锁存 AG/borrow/异常约在 `742-856`，VA/PFU 信息在 `878-895`。
- 异常向量在 `907-964`，涵盖 illegal=2、misalign=6、PF（按 Load/Store 方向区分）及带 page 的 access fault=7 等。
- SQ create 要求指令有效、iid 不重复、无 UTLB miss/异常，见 `1042-1053`。
- Store write-port hit 的 index 按 `DCACHE_32K` 使用 `addr[13:6]`，按 `DCACHE_64K` 使用 `addr[14:6]`，见 `1110-1121`；这与 array 的 256/512 项深度一致。
- UTLB miss 优先于 SQ full 触发 restart，见 `1127-1150`；tag/dirty 读取与早期 Store 地址回送在 `1208-1229`。
- store tag 两路比较和 DA 信息输出在 `1238-1280`；SQ full/wakeup 回送 IDU 在 `1284-1294`。

### 4.2 DA、SQ/WMB/VB 与 D-cache 更新

`ct_lsu_st_da` 的端口直接暴露 D-cache tag/dirty 写入、SQ/ SNQ/ VB 属性、RB create、ICC、WMB completion 和 RTU pipe4，见 `ct_lsu_st_da.v:17-184`、`206-374`。

- DC 级字段在控制/异常/实例时钟中锁存，关键时钟和 valid 在 `675-754`，tag/dirty 阵列读回在 `811-823`。
- 当前 ECC stall/fatal/update 信号置零，`ct_lsu_st_da.v:804-806`。
- Store DA 重新计算 access fault 与异常向量，并将异常/wb 信息送 `st_wb`，见 `1010-1046`。
- D-cache hit/dirty/share/valid/replace way、SQ data/way、SNQ borrow、VB reissue 与 RB create 是该阶段的核心输出，信号定义见 `292-374`，组合判断分布在 `1010` 之后。
- 正常 Store 的顺序边界是 SQ commit/CE/WMB，而不是 D-cache 写入本身；SQ 中保存 data/bytes/age/dependency 和 dcache info，提交后由 WMB CE 选择立即写、合并或等待。

### 4.3 Store WB

`ct_lsu_st_wb` 是非常窄的提交仲裁级：DA completion 有优先权，WMB completion 只有在 DA 没有请求时才获得 grant，准确逻辑在 `ct_lsu_st_wb.v:175-210`。该级锁存 flush/spec/breakpoint/异常后向 RTU pipe4 输出，寄存器与输出在 `216-343`。所以 Store 的 WB 完成并不等于所有 cache writeback 已结束；WMB/VB/RB 仍可能有后台事务。

## 5. LQ、SQ 及依赖语义

### 5.1 LQ：Load 的顺序检查窗口

`ct_lsu_lq` 参数为 `LQ_ENTRY=16`（`ct_lsu_lq.v:159`），实例化 16 个 `ct_lsu_lq_entry`（约 `ct_lsu_lq.v:192-837`）。创建指针选择最低可用项，支持 split Load 的 create0/create1，见 `877-962`；full/less2/inst-hit/RAR/RAW 输出在 `968-974`。

单项 `ct_lsu_lq_entry` 保存 `addr_tto4`、bytes valid、iid、secd 和 valid，见 `ct_lsu_lq_entry.v:17-101`。其生命周期是 create0/create1 写入、RTU iid commit pop、flush 清除，见 `203-261`。LQ 不只是“未完成 Load 计数器”：

- RAR：较新 Load 与当前 Load 的地址/byte overlap，见 `272-320`。
- RAW：较新 Store 与当前 Load 的地址/byte overlap，见 `324-359`。
- `cp0_lsu_corr_dis` 可关闭校正/推测检查；entry 输出 `inst_hit`、`rar_spec_fail`、`raw_spec_fail` 给 DC/控制。

### 5.2 SQ：Store 数据、年龄、forward 与提交

`ct_lsu_sq` 使用 `SQ_ENTRY=12`、`LSIQ_ENTRY=12`，参数在 `ct_lsu_sq.v:824-827`，对应 12 个 `ct_lsu_sq_entry`。单项 entry 还保存地址、age vector、data、bytes、D-cache valid/share/dirty/way、dependency、atomic/ICC/fence、wakeup 等状态，并实例化 `ct_lsu_dcache_info_update`（`ct_lsu_sq_entry.v:1134`）。

SQ 的实际职责：

- 接收 `st_dc` create，记录 Store 的逻辑顺序和 data；
- 对 Load 提供最新 Store 数据和 bytes mask；
- 对 Store/ICC 进行 dependency、同地址 newest、age-vector 和 data wakeup；
- commit 后把 entry 分类为正常 Store、D-cache 操作、atomic/fence/TLBI 等。

其 pop/CE 分类在 `ct_lsu_sq.v:3521-3564`：普通 Store、D-cache/ICC、one-line/all-line cache operation、同步/异步 flush 等决定是直接 pop、发 WMB merge、等待 WMB CE 还是保留。RB hit 会阻止错误的 WMB merge（`3566-3571`）；ICC request/clear/invalidate 在 `3587-3592`；`sync.i` 类 flush 清掉全部 entry 在 `3597-3602`。WMB CE 的 data/bytes/dcache info mux 在 `3608-3683`，SQ RTU commit 和 IDU not-full/HAD 状态在 `3728-3736`。

## 6. RB、LFB、WMB、VB：后台事务与缓存线生命周期

### 6.1 RB（Read Buffer）

`ct_lsu_rb` 参数为 `RB_ENTRY=8`，另有 `VMB_ENTRY=8`、BIU NC/atomic ID 等，见 `ct_lsu_rb.v:769`；单项 `ct_lsu_rb_entry` 的状态定义说明 state[2] 区分 BIU 请求前后，`REQ_BIU=4'b1001`、`WAIT_MERGE=4'b1110`，见 `ct_lsu_rb_entry.v:603-615`。

RB 负责把 Load miss、NC/atomic、同步/fence 和部分 Store miss 变成 BIU AR，并将 R response 变回 WB/LQ wakeup：

- AR 选择要求 entry 有效、没有 flush/hit-index；cacheable 请求还要 LFB 有空间或走 non-cache 路径，见 `ct_lsu_rb.v:2462-2522`。
- cacheable linefill、sync/fence、SO、NC atomic 使用不同 ID/len/size/lock；snoop opcode 由 atomic/readunique、Store CA share、shared refill 等属性决定，见 `2522-2580`。
- domain/bar/cache/prot/user 等 BIU 属性在 `2584-2600`，grant/状态在 `2605-2624`。
- WB completion pointer、数据 pointer、metadata、grant 在 `2627-2765`；BIU response 按 NC/SO/linefill ID 分类并识别 SLVERR/OKAY/DECERR，见 `2852-2863`。
- cacheable response 生成 LFB create，MCIC/LM 使用专用响应路径，full/not-full/HAD 状态在 `2874-2912`。

### 6.2 LFB（Line Fill Buffer）

`ct_lsu_lfb` 的关键参数为 `LSIQ_ENTRY=12`、`BIU_LFB_ID_T=2'b00`、OKAY response，见 `ct_lsu_lfb.v:514`。地址 entry 负责“哪一条线/哪一个依赖”，数据 entry 负责“返回的 512-bit line 数据”。

- `ct_lsu_lfb_addr_entry` 保存 valid、RB/PFU create、line address、cache info、response/dependency；create/pop/linefill permit 在 `ct_lsu_lfb_addr_entry.v:308-467`。
- 它比较 Load DA、RB、PFU、WMB read/write 的 index，形成 hit-index/合并/阻塞，见 `511-543`。
- `ct_lsu_lfb_data_entry` 将 BIU R 数据、last/bias/share/error 与地址项绑定，向 D-cache bank/tag/dirty 写入前形成 linefill data；端口/寄存器在 `ct_lsu_lfb_data_entry.v:17-161`，容量参数在 `170`，create/pop、linefill permit、四个 beat data pass 和 full/wakeup 信号在 `176` 之后。
- LFB 的 data entry create、BIU response mapping、D-cache refill state machine 在 `ct_lsu_lfb.v:1430-1750`；tag/dirty/data 写入在 `1704-1739`，通常写入 valid/share tag 与 line data。
- flush 清醒/依赖 pop/wakeup queue 在 `1751-1808`；no-rready 计数和 BIU R ready 在 `1811-1840`；empty/full/less2 状态在 `1846-1879`。

### 6.3 WMB（Write Merge Buffer）

`ct_lsu_wmb` 参数为 `WMB_ENTRY=8`，normal read ID、NC write ID 等在 `ct_lsu_wmb.v:1167`。顶层实例化 8 个 `ct_lsu_wmb_entry`，见 `ct_lsu_wmb.v:1510-2882`；WMB entry 还会使用 `ct_lsu_dcache_info_update`（`ct_lsu_wmb_entry.v:1514`）。

WMB 的状态语义是：SQ commit 先到 CE，再按同 cache line、privilege、类型和数据完整性选择 merge、D-cache write、BIU write 或等待。

- `ct_lsu_wmb_ce` 从 SQ pop 捕获地址、page/atomic/ICC/fence/mode/bytes，见 `ct_lsu_wmb_ce.v:328-423`。
- merge/stall 在 `428-455`；同 line 比较和 privilege 匹配在 `598-621`。同地址且属性一致才允许 merge；privilege mismatch 会 stall。
- CE 把普通 Store、atomic/SC、D-cache、sync fence、TLBI/CTC 分到不同 create/pop/read/write immediate 路径，见 `500-596`。
- WMB 本体在 `4112-4309` 选择写 D-cache 的 entry、data/bytes/way，并避开 LFB/SNQ/VB hit index；没有 D-cache hit 才创建 VB，见 `4311-4320`。
- BIU AW 的 ID、burst、cache/snoop/domain/bar 在 `4325-4463`；W channel 在 `4467-4479`；Store WB 在 `4480-4569`。
- WMB 维护 dependency wakeup queue，flush 清空，依赖 pop 后再唤醒 Load，在 `4571-4660`；hit-index/HAD 状态在 `4715-4744`。

### 6.4 VB（Victim Buffer）

`ct_lsu_vb` 使用 `BIU_VB_ID_T=3'b000`、`VB_ADDR_ENTRY=2`，见 `ct_lsu_vb.v:606`；地址项承载被替换/写回 cache line 的来源，数据部分由 3 个 `ct_lsu_vb_sdb_data_entry` 承载，`ct_lsu_vb_sdb_data.v:171-179`、`179-320`。

- `ct_lsu_vb_addr_entry` 的 valid/create/pop 和 source 区分 ICC、LFB、WMB，见 `ct_lsu_vb_addr_entry.v:292-356`；它还比较 RB/PFU/WMB/LFB/SNQ 地址，见 `407-451`。
- `ct_lsu_vb_sdb_data_entry` 保存 512-bit 数据，按两个 256-bit 读窗口写入，见 `ct_lsu_vb_sdb_data_entry.v:110-118`、`353-368`；状态从 GET_VB_DATA/GET_SNQ_DATA 到 REQ_WRITE_ADDR/REQ_WRITE_DATA/CD，见 `301-460`。
- `ct_lsu_vb` 先确定 replacement way；LFB refill 或 hit dirty 触发 data entry create，见 `1242-1277`。cache read/write 和 tag/dirty 更新在 `1279-1343`，数据 entry pointer/full 在 `1365-1398`。
- victim AW 是 4×128-bit burst，包含 cache/snoop/domain/bar/unique 属性，见 `1400-1511`；W data/pop 在 `1514-1590`；B response 在 `1597-1616`。
- VB 与 LFB/WMB/SNQ 的 hit/dependency 和 empty/full 输出在 `1622-1663`；`vb_empty` 是地址项和数据项同时空，`vb_wmb_empty` 只统计 WMB 来源。

## 7. D-cache、仲裁与 cache buffer

### 7.1 Array 组织

`ct_lsu_dcache_top` 是 array 封装，不决定访问协议。它实例化 load tag、store tag、dirty 和 8 个 data bank，分别在 `ct_lsu_dcache_top.v:152`、`175`、`198`、`294-455`。

| 阵列 | 32 KiB 宏 | 64 KiB 宏 | 语义 |
|---|---|---|---|
| Data | `ct_spsram_1024x32` | `ct_spsram_2048x32` | 8 个 32-bit bank 组成 256-bit line，见 `ct_lsu_dcache_data_array.v:87-114` |
| Store tag | `ct_spsram_256x52` | `ct_spsram_512x52` | tag/写端口，见 `ct_lsu_dcache_tag_array.v:89-116` |
| Load tag | `ct_spsram_256x54` | `ct_spsram_512x54` | 含 valid/额外 load tag 信息，见 `ct_lsu_dcache_ld_tag_array.v:83-109` |
| Dirty/info | `ct_spsram_256x7` | `ct_spsram_512x7` | dirty/share/valid 等状态，见 `ct_lsu_dcache_dirty_array.v:82-109` |

`DCACHE_32K`/`DCACHE_64K` 决定 index 深度和地址位，`MEM_CFG_IN` 决定 memory wrapper 的配置输入，相关宏使用见 D-cache array 与 `ct_lsu_dcache_info_update.v:113-188`。`ct_spsram_4096x32` 与 `ct_spsram_8192x32` 在本目录存在，但搜索未发现被当前 LSU D-cache array 实例化；它们是可供其他配置使用的同样 wrapper。

### 7.2 `ct_lsu_dcache_arb`

`ct_lsu_dcache_arb` 是真正的端口冲突中心，输入源包括 LFB、VB、SNQ、WMB、ICC、MCIC 以及 Load/Store AG/DC。其主要行为：

- 合并 Load bank request、选择低/高数据 index，在 `ct_lsu_dcache_arb.v:986-1054`。
- Store request 按 serial、LFB、VB、SNQ、ICC、WMB 等优先级选择，见 `1095-1162`；borrow 地址和 Store DC/ICC/SNQ/VB 反馈在 `1171-1192`。
- tag read/write 选择在 `1197-1243`；dirty 选择和 D-cache write-port 信息在 `1249-1387`。当前 LFB 是 refill/store tag 的关键写入者。
- 由于 Load 数据口和 Store/tag/dirty 口是共享资源，`ld_ag/ld_dc` 的 stall 以及 `st_dc/st_da` 的 borrow 并非偶然 backpressure，而是由该仲裁级真实产生。

### 7.3 Cache buffer

`ct_lsu_cache_buffer` 保存 split Load 的地址与 256-bit 数据。地址 create 来自 `ld_dc_cb_addr_create_vld`，数据 create 来自 `ld_da_cb_data_vld`，地址项和数据项在 `ct_lsu_cache_buffer.v:149-165`；命中比较、pop 条件和数据返回在 `199-206`。当 D-cache disabled、D-cache load gwen、index 被写入或 ICC 改变状态时会 pop，说明它是边界补片缓存，不是独立 cache。

## 8. Snoop、ICC、LM、MCIC、AMR 与 speculation fail

### 8.1 AC→SNQ/CTCQ→CR/CD

`ct_lsu_snoop_req_arbiter` 直接把 BIU AC 分成 normal snoop 与 CTC：

- `biu_lsu_ac_snoop==4'b1111` 判为 CTC，否则为 normal snoop；创建条件分别要求当前 CTCQ/SNQ entry 可用、ICC permit、LM 不 stall，见 `ct_lsu_snoop_req_arbiter.v:179-214`。
- normal snoop 的依赖向量拼接 WMB 与 VB：`arb_snq_snoop_depd={wmb_snq_depd,vb_snq_depd}`，地址/prot/type 直接取 AC，见 `219-230`。
- CTC 记录 TLB/I-cache 类操作的 type、ASID/VA/PA 和是否二次事务，见 `233-260`。
- 为保持 SNQ/CTCQ 混合响应顺序，arbiter 使用 `COQ_ENTRY=18`，注释要求至少 `SNQ+2*CTCQ`，并记录来源/创建顺序，见 `266-343`。CR 接收时推进 oldest index。

`ct_lsu_snoop_ctcq` 实例化 6 项 CTCQ entry，保存 I-cache invalidate、TLB invalidate/ASID/VA 等 control transaction；create pointer、valid/not-empty、launch/return 在 `ct_lsu_snoop_ctcq.v:237-280` 及其后状态逻辑。`ct_lsu_snoop_ctcq_entry.v` 是单项执行器，负责 PE request、CR response、CTC flush 与 RTU/HAD 完成信号。

`ct_lsu_snoop_snq` 实例化 6 项 SNQ entry，并带有 3 项 snoop data buffer。单项 `ct_lsu_snoop_snq_entry` 保存 valid、依赖、issued、resp、way、tag/data 需求，见 `ct_lsu_snoop_snq_entry.v:139-157`；只有依赖清零且未 issued 才能读 tag，见 `289-325`。如果 line 在 LFB/VB/WMB，SNQ 可以 bypass data、等待 VB、改变 tag 或 invalidate，见 `344-382` 以及端口 `42-74`。

`ct_lsu_snoop_resp` 将 SNQ/CTCQ 的 CR valid/resp OR 归并，CR ready 同时回送两侧，`biu_lsu_cr_resp_acept=valid&&ready`，CD data 取 SDB，见 `ct_lsu_snoop_resp.v:81-92`。

### 8.2 ICC

`ct_lsu_icc` 的状态包括 IDLE、WAIT_FOR_READY、INV_DCACHE_LINE、REQ_VB_WAY0/1、WAIT_VB_EMPTY、READ_DCACHE、WAIT_DATA，见 `ct_lsu_icc.v:250-256`。它不是一个普通 Store，而是由 pipe4 ICC、SQ、WMB/RB/LFB/VB/PFU/SNQ 空闲条件共同约束的 cache control engine：

- start/ready 条件及等待队列 empty 在 `417-446`；CP0 ICC 会等待 SQ 等关键队列空，再发 `icc_wmb_write_imme`。
- 32K/64K line count/overflow 在 `452-464`；D-cache invalidate/read request 与 tag/dirty 信息在 `477-530`。
- dirty line 必须创建 VB，VB 完成后继续 invalidate/read，见 `533-552`。

### 8.3 LM、MCIC、AMR

- `ct_lsu_lm` 负责 LR/SC/AMO 的锁与异常推进。状态包含 IDLE、WAIT_REQ、WAIT_RESP、EX_WAIT_LOCK、AMO_LOCK，见 `ct_lsu_lm.v:225-229`；响应成功/错误、SC fail/eject、与 Load/Store/SNQ/PFU 同地址 lock hit 见 `423-529`。因此原子请求不仅依赖 RB response，还会阻止相关 snoop/访问。
- `ct_lsu_mcic` 对接 BIU R response、D-cache arb、Load DA 的 MMU borrow/error/RB-full/wakeup 和 HAD freeze/data request；其端口在 `ct_lsu_mcic.v` 模块声明处，顶层实例在 `ct_lsu_top.v:3119`。它是错误/不可一致数据到 Load WB/RB 的专用旁路，不应和普通 RB refill 混为一谈。
- `ct_lsu_amr` 用 JUDGE、MEM_SET_0/1/2 状态（`ct_lsu_amr.v:102-104`）统计 Store 合并窗口；计数达到 8/16/48 进入不同阶段，见 `230-261`。当 ICC 非 idle、AMR disabled 或非 CA Store pop 时取消；地址未命中或 bytes 不完整则 fail，见 `311-326`。`amr_l2_mem_set` 是最后阶段的 L2 memory-set 提示，不是直接 L2C 接口。

### 8.4 Speculation fail predictor

`ct_lsu_spec_fail_predict` 跟踪 Store no-spec miss、iid、RTU spec-fail flush 和后续 Load check。状态寄存器在 `183-251`，start/mark/hit 在 `270-341`，输出 `sf_spec_mark`/`sf_spec_hit` 给 Load DA/WB 和 RTU。它只预测/归因 speculation fail，不负责实际清空 LQ/SQ；清空由 RTU flush/`ct_lsu_ctrl`/各队列完成。

## 9. PFU（预取单元）

`ct_lsu_pfu` 的端口很清楚地表明 PFU 既有 L1 prefetch，也有 L2 prefetch：

- CP0 输入为 `cp0_lsu_l2_pref_en`、`cp0_lsu_l2_st_pref_en`、`cp0_lsu_pfu_mmu_dis`、timeout，端口见 `ct_lsu_pfu.v:17-114`。
- 产生第三路 MMU VA2/PA2 请求，`lsu_mmu_va2`/`mmu_lsu_pa2*` 见 `ct_lsu_pfu.v:55-64`、`187-210`。
- 读 LFB/RB/VB/WMB/LM/Load DA/Store DA 的 hit-index 和 full/rready，防止预取与真实访问、victim、linefill 冲突，见 `ct_lsu_pfu.v:41-54`、`92-114`。
- PFU 输出经 bus arb 进入 BIU AR，同时可创建 LFB，见 `pfu_biu_ar_*` 和 `pfu_lfb_create_*`（`ct_lsu_pfu.v:194-214`）。

内部结构：

- `ct_lsu_pfu_pmb_entry` 是 prefetch monitor buffer 的单项，保存 PC、timeout 和 ready/evict/pop；timeout 到期、L2 store-pref disabled 或 AMR cancel 会 pop，见 `ct_lsu_pfu_pmb_entry.v:209-352`。
- `ct_lsu_pfu_pfb_entry` 是 stride/地址预取 buffer 单项，组合 `pfb_l1sm`、`pfb_l2sm` 和 `pfb_tsm`；L1/L2 各自产生 BIU PE request、MMU PE request，等待 LFB hit/miss 或 dcache hit 后推进，相关端口和状态在 `ct_lsu_pfu_pfb_entry.v:17-131` 以及 `ct_lsu_pfu_pfb_tsm.v:171-334`。
- `ct_lsu_pfu_gsdb` 监视 stride，状态为 GET_STRIDE/CHECK_STRIDE/MONITOR_STRIDE，见 `ct_lsu_pfu_gsdb.v:135-147`、`186-366`；confidence 增减决定是否创建 GPFB。
- `ct_lsu_pfu_gpfb` 连接 L1/L2 stride state machine，并在 L2 预取地址过远、LFB hit 或 confidence 条件下 reinit/pop，见 `ct_lsu_pfu_gpfb.v:307-445`、`479-506`。
- `ct_lsu_pfu_sdb_entry`/`ct_lsu_pfu_sdb_cmp` 保存最近 stride/地址样本并比较；这组模块负责学习输入，不直接发 BIU 请求。

PFU 的“L2”含义是预取目的/距离与 BIU 属性选择；目录中没有 L2C 模块实例，所以应把它理解为 LSU 的 L2 prefetch client，而不是 L2 cache implementation。

## 10. 控制与总线仲裁

### 10.1 `ct_lsu_bus_arb`

`ct_lsu_bus_arb` 是 LSU 到 BIU 的最后一级通道封装，module 与端口定义从 `ct_lsu_bus_arb.v:17` 开始，顶层实例位于 `ct_lsu_top.v:6036`，连接持续到 `6202`。它将 RB、WMB、VB、PFU 的请求分别合并为 BIU AR 与两类 AW/W：

- AR 来源是 WMB、RB、PFU。仲裁先把各来源的 `*_ar_dp_req` 锁存成 mask（`ct_lsu_bus_arb.v:535-586`）；WMB 的真实 dp request 优先，之后在 RB/PFU 之间形成互斥 select，并结合 `biu_lsu_ar_ready` 产生 grant/ready，见 `596-624`。
- 被选来源的 addr、ID、len、size、burst、lock、cache、prot、user、snoop、domain、bar 等字段逐字段 mux 到 `lsu_biu_ar_*`，见 `626-684`；因此 RB 的 refill/NC、WMB 的读请求和 PFU 的预取共享同一条 BIU AR 通道。
- AW/W 区分 WMB 的 Store write 与 VB 的 victim write，分别响应 `biu_lsu_aw_vb_grnt`/`aw_wmb_grnt` 和 `w_vb_grnt`/`w_wmb_grnt`，grant 在 `702-709`、`755-758`；两类 AW 属性和 W data 分别直通到 `lsu_biu_aw_vict_*`、`lsu_biu_aw_st_*`、`lsu_biu_w_vict_*`、`lsu_biu_w_st_*`，见 `711-770`。
- 顶层映射从 `ct_lsu_top.v:6036-6202` 可见，LSU 对 BIU 输出的 addr/id/len/size/cache/prot/snoop/domain/bar/lock/user 全部由该级和来源项提供。

### 10.2 `ct_lsu_ctrl`

`ct_lsu_ctrl` 汇总 LQ/SQ/RB/WMB/VB/LFB/PFU/SNQ/CTCQ/ICC/LM 等 empty/full、wakeup、HAD、HPCP、flush 和 oldest 状态，顶层连接在 `ct_lsu_top.v:5830-6032`。它的作用是把局部 backpressure 变为 IDU 的 `lsu_idu_*_full`、stall/wakeup、fence/not-empty 和 no-op 等全局协议；它不替代各队列的 pop/create 状态机。

## 11. Flush、异常、forward 与响应协议

### 11.1 普通 Load hit

1. IDU pipe3 给 `ld_ag`；AG 形成 VA0/PA0、属性、bytes 与 D-cache request。
2. `ld_dc` 进行 UTLB/PF/对齐掩码、LQ create、SQ/WMB dependency 和 tag hit。
3. hit 数据从 D-cache 读出；若有较新 Store，SQ 优先，WMB 次之。
4. `ld_da` 选择数据、形成 sign/size 结果，产生 LQ wakeup/WB。
5. `ld_wb` 竞争 DA/RB/WMB 返回源，向 IDU pipe3 forwarding 与 RTU pipe3 发完成/异常。

### 11.2 Load miss/linefill

1. `ld_da` 创建 RB entry；RB 根据 CA/NC/atomic/fence 选择 AR 属性和 ID。
2. CA linefill 需要 LFB 地址/数据项；BIU R response 由 LFB 按 line beat 接收。
3. LFB 写 D-cache tag/dirty/data，设置 valid/share 并在 dependency queue 上唤醒 Load。
4. RB/LFB 向 `ld_wb` 提供数据或完成；同 index 的 Load/Store/PFU/SNQ/VB 请求会在各自 hit-index 信号上阻塞/merge。

### 11.3 Store commit/writeback

1. `st_ag/st_dc` 形成 Store address 和 SQ entry；Store data 由 pipe5/`ct_lsu_sd_ex1` 补齐。
2. RTU commit 后 `sq` pop 到 `wmb_ce`，按同 line/privilege/类型决定 merge、immediate、D-cache write、RB/VB。
3. WMB 命中 D-cache 可更新 data/dirty/share；需要替换的 dirty line 先进入 VB，再由 AW/W 回写。
4. `st_wb` 只报告 DA 或 WMB 的完成，DA 优先；后台 WMB/VB/BIU 事务不一定在该拍结束。

### 11.4 Snoop/coherence

1. BIU AC 输入进入 `snoop_req_arbiter`；CTC 与 normal snoop 分别创建 CTCQ/SNQ。
2. SNQ 先等 VB/WMB/LFB 依赖清除，再读 tag/dirty/data 或做 bypass/invalidate。
3. CTCQ 执行 I-cache/TLB/控制事务，可有二次 transaction。
4. `snoop_resp` 合并 CR response，SDB 提供 CD data；BIU CR ready/accept 决定 oldest pointer pop。

### 11.5 flush/异常

Load/Store 各阶段把异常分为“不可创建队列”“可进入队列但不可 forward”“WB 报告异常”三类；UTLB miss 多数走 restart，PF/misalign/illegal 进入 WB/RTU。RTU flush 会清 AG/DC valid、LQ/SQ entry、RB/WMB/LFB/PFU/snoop 的局部状态；不同队列的清空逻辑分别位于其 entry/parent 中，而非一个全局 reset。异步 flush、sync.i、ICC flush 和 spec-fail 还会施加各自更窄的清理条件，例如 SQ 的 sync.i 全清在 `ct_lsu_sq.v:3597-3602`，PFU 所有 part 清空在 `ct_lsu_pfu_gsdb.v:191-195` 附近。

## 12. 参数、宏和容量汇总

| 子系统 | 当前 RTL 中可见容量/关键参数 | 证据 |
|---|---|---|
| LQ | 16 entry | `ct_lsu_lq.v:159` |
| SQ | 12 entry；LSIQ 12 | `ct_lsu_sq.v:824-827` |
| RB | RB 8；VMB 8；NC/atomic BIU IDs | `ct_lsu_rb.v:769` |
| WMB | WMB 8；normal/NC IDs | `ct_lsu_wmb.v:1167-1171` |
| LFB | 地址项 8、数据项 2；LSIQ 12 | `ct_lsu_lfb.v:514` 及 `ct_lsu_lfb_addr_entry.v`/`data_entry.v` 实例 |
| VB | 地址项 2、数据项 3 | `ct_lsu_vb.v:606`、`ct_lsu_vb_sdb_data.v:171-179` |
| SNQ/CTCQ | 各 6 项；COQ 18 | `ct_lsu_snoop_req_arbiter.v:273`、`ct_lsu_snoop_snq.v`、`ct_lsu_snoop_ctcq.v` |
| PFU | PMB 8；PFU PC_LEN 15；L2 prefetch ID 25 | `ct_lsu_pfu.v:552` |
| D-cache | DCACHE_32K/64K；tag depth 256/512；data depth 1024/2048×32×8 | `ct_lsu_dcache_*_array.v`、`ct_lsu_dcache_info_update.v:113-188` |
| SRAM | 32-bit data wrappers 1024/2048/4096/8192；tag 52/54-bit；dirty 7-bit | 各 `ct_spsram_*.v:17-53` |

主要宏包括 `DCACHE_32K`、`DCACHE_64K`、`MEM_CFG_IN`、`PA_WIDTH`、`VA_WIDTH`、`LSIQ_ENTRY` 等。宏会改变 index 位宽、array 深度、memory configuration 端口和部分 cache compare；阅读单独模块时必须同时看 array wrapper 和顶层配置，不能只依据信号名字。

## 13. 文件索引：本目录每个 RTL 文件的职责

以下按功能分组列出目录内全部 70 个 `.v` 文件，便于继续追踪；行号给出 module/参数/实例或关键状态的入口证据。新增单列的 `ct_lsu_bus_arb.v` 是顶层到 BIU 的通道仲裁模块，不属于 D-cache arb。

### 顶层、流水和控制

- `ct_lsu_top.v`：LSU 顶层端口和全部实例，`17`、`2797-6332`。
- `ct_lsu_ctrl.v`：全局 full/stall/wakeup/fence/flush 汇总，`17`、`5830` 顶层连接。
- `ct_lsu_ld_ag.v`、`ct_lsu_ld_dc.v`、`ct_lsu_ld_da.v`、`ct_lsu_ld_wb.v`：Load AG/DC/DA/WB，分别见各文件 module 起始和顶层 `2797`、`3416`、`4016`、`4961`。
- `ct_lsu_st_ag.v`、`ct_lsu_st_dc.v`、`ct_lsu_st_da.v`、`ct_lsu_st_wb.v`：Store AG/DC/DA/WB，顶层 `2943`、`3638`、`4269`、`5084`。
- `ct_lsu_sd_ex1.v`：Store data execution/辅助数据拍，顶层 `3088`。
- `ct_lsu_rot_data.v`：Load data byte/half/word/dword rotation，`17`，由 `ld_da.v:1872/1946` 使用。
- `ct_lsu_idfifo_8.v`、`ct_lsu_idfifo_entry.v`：ID/IID 小 FIFO 与 entry 级 valid/data 管理，module 分别从 `17` 开始。

### Queue/后台 buffer

- `ct_lsu_lq.v`、`ct_lsu_lq_entry.v`：16 项 LQ 与单项 RAR/RAW 检查，`lq.v:159`、`lq_entry.v:203-359`。
- `ct_lsu_sq.v`、`ct_lsu_sq_entry.v`：12 项 SQ、年龄/依赖/forward/commit，`sq.v:824`、`sq_entry.v:1134`。
- `ct_lsu_rb.v`、`ct_lsu_rb_entry.v`：8 项 read buffer 与 BIU AR/response/WB，`rb.v:769`、`rb.v:2462-2912`。
- `ct_lsu_wmb.v`、`ct_lsu_wmb_entry.v`、`ct_lsu_wmb_ce.v`：WMB entry、entry 状态、SQ commit 分类，`wmb.v:1167`、`wmb_entry.v:801/1514`、`wmb_ce.v:295/328-621`。
- `ct_lsu_lfb.v`、`ct_lsu_lfb_addr_entry.v`、`ct_lsu_lfb_data_entry.v`：linefill 地址/数据/回填，`lfb.v:514/1430-1879`、addr entry `308-543`。
- `ct_lsu_vb.v`、`ct_lsu_vb_addr_entry.v`、`ct_lsu_vb_sdb_data.v`、`ct_lsu_vb_sdb_data_entry.v`：victim 地址、3 项数据及 BIU 回写，`vb.v:606/1242-1663`、data `171-320`。
- `ct_lsu_cache_buffer.v`：split Load 地址/256-bit 数据补片，`149-206`。

### 总线仲裁

- `ct_lsu_bus_arb.v`：RB/WMB/PFU 的 BIU AR 仲裁，以及 WMB Store/VB victim 的 AW/W 通道封装；module/端口从 `17` 开始，AR mask/选择/grant 在 `535-684`，AW/W grant 与直通在 `702-770`，顶层实例在 `ct_lsu_top.v:6036`。

### D-cache

- `ct_lsu_dcache_arb.v`：Load/Store/LFB/VB/SNQ/WMB/ICC/MCIC 仲裁，`986-1387`。
- `ct_lsu_dcache_top.v`：tag/dirty/data array 总封装，`152-455`。
- `ct_lsu_dcache_data_array.v`：32K/64K 8-bank data，`87-114`。
- `ct_lsu_dcache_tag_array.v`、`ct_lsu_dcache_ld_tag_array.v`：store/load tag，分别 `89-116`、`83-109`。
- `ct_lsu_dcache_dirty_array.v`：dirty/share/valid info，`82-109`。
- `ct_lsu_dcache_info_update.v`：hit/refill/dirty 信息更新，`113-235`。

### 一致性、原子与异常辅助

- `ct_lsu_snoop_req_arbiter.v`：AC 分流、COQ 顺序和依赖拼接，`179-343`。
- `ct_lsu_snoop_resp.v`：CR/CD response merge，`81-92`。
- `ct_lsu_snoop_ctcq.v`、`ct_lsu_snoop_ctcq_entry.v`：6 项控制事务队列与单项状态。
- `ct_lsu_snoop_snq.v`、`ct_lsu_snoop_snq_entry.v`：6 项 normal snoop 与 tag/data/VB/LFB bypass，entry `289-382`。
- `ct_lsu_icc.v`：D-cache invalidate/read/clean，`250-552`。
- `ct_lsu_lm.v`：LR/SC/AMO lock，`225-537`。
- `ct_lsu_mcic.v`：machine-check/incoherent load 旁路，module/top `3119`。
- `ct_lsu_amr.v`：AMR store merge window，`102-326`。
- `ct_lsu_spec_fail_predict.v`：speculation-fail prediction，`183-341`。

### PFU

- `ct_lsu_pfu.v`：PFU 顶层，MMU VA2、BIU AR、LFB create，`17-214`、`552`。
- `ct_lsu_pfu_pmb_entry.v`：PMB entry/timeout/evict，`209-352`。
- `ct_lsu_pfu_pfb_entry.v`：PF buffer entry，`17-131`。
- `ct_lsu_pfu_pfb_l1sm.v`、`ct_lsu_pfu_pfb_l2sm.v`、`ct_lsu_pfu_pfb_tsm.v`：L1/L2 与 top state machine，`ct_lsu_pfu_pfb_tsm.v:171-334`。
- `ct_lsu_pfu_gsdb.v`、`ct_lsu_pfu_gpfb.v`：stride database 与 global prefetch buffer，`gsdb.v:186-416`、`gpfb.v:307-506`。
- `ct_lsu_pfu_sdb_entry.v`、`ct_lsu_pfu_sdb_cmp.v`：stride sample entry 与比较器。

### SRAM wrapper

- `ct_spsram_1024x32.v`、`ct_spsram_2048x32.v`、`ct_spsram_4096x32.v`、`ct_spsram_8192x32.v`：32-bit 单口 SRAM wrapper，module/参数均在 `17-53`；当前 D-cache array 直接使用前两者，4096/8192 在当前目录无调用点。
- `ct_spsram_256x52.v`、`ct_spsram_512x52.v`：52-bit Store tag wrapper，`17-53`。
- `ct_spsram_256x54.v`、`ct_spsram_512x54.v`：54-bit Load tag wrapper，`17-53`。
- `ct_spsram_256x7.v`、`ct_spsram_512x7.v`：7-bit dirty/info wrapper，`17-53`。

这些 wrapper 本身不实现行为级 memory array，而是把 `A/CEN/CLK/D/GWEN/Q/WEN` 原样接到 `ct_f_spsram_*` FPGA primitive；例如 `ct_spsram_256x52.v:58-66`。因此仿真/综合时需要同时提供对应的 FPGA memory primitive，不能把 wrapper 当成可独立运行的 Verilog RAM。

## 14. 结论

本目录中的 LSU 是“流水级 + 顺序队列 + cache/coherence 后台事务”的组合：

1. IDU 只在 pipe3/pipe4/pipe5 提供发射与数据；MMU 提供三路 VA/PA 结果；RTU 决定 commit/pop/flush。
2. LQ/SQ 负责动态内存依赖和 forwarding，RB/LFB 负责读 miss/linefill，WMB/VB 负责 Store 合并和 dirty line 写回。
3. D-cache arb 将真实的多来源读写压缩到共享 array 端口；cache buffer 只补齐 split Load，不替代 LFB。
4. AC 一致性请求由 SNQ/CTCQ 分流，依赖 VB/WMB/LFB 后读 tag/data、bypass 或 invalidate，再通过 CR/CD 返回 BIU。
5. `bus_arb` 是 LSU 到 BIU 的唯一请求汇聚点；目录内没有直连 CIU/L2C 的端口。所谓 L2 主要体现在 PFU 的 L2 prefetch 控制、BIU cache/snoop 属性和 AMR 的 memory-set 提示。
6. 当前生成配置明确关闭 VMB/ECC/部分向量路径；分析接口时必须以硬连/注释后的实现为准，而不能只看保留的端口命名。
