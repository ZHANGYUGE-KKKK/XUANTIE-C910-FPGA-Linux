# IFU 取指单元 RTL 结构报告

## 1. 范围与结论

本文只覆盖 `gen_rtl/ifu/rtl` 目录中的 50 个 Verilog 文件（与该目录实际清单/filelist 一致），并以 `ct_ifu_top` 的真实具名端口连接、子模块实例和关键状态机为依据。本文没有修改任何 IFU RTL；来自其他目录的模块只作为连接边界记录。

当前 IFU 可以概括为一条“PC 生成—预测—I-cache/预取—IF/IP—IB—IDU”流水线，同时带有两条旁路：预测器更新/检查通路，以及 BIU refill/prefetch 通路。

```text
CP0/MMU/RTU/IU/HAD/VFDSU/LSU
              │  控制、地址翻译、flush、异常、调试
              ▼
pcgen ──► IFCTRL/IFDP ──► IPCTRL/IPDP ──► IBCTRL/IBDP ──► IBUF ──► IDU
  │            │              │              │             │
  │            │              │              │             └─ LBUF 旁路/循环执行
  │            │              │              └─ PCFIFO → IU 控制流检查点
  │            │              └─ BTB/L0/ind-BTB/RAS/SFP/BHT 查询与更新
  │            └─ I-cache tag/data/predecode
  ├─ BHT/BTB/L0-BTB/ind-BTB/RAS/SFP
  └─ IPCTRL → L1_REFILL ↔ IPB ↔ BIU；refill data → I-cache/IFDP
```

### 1.1 主要结论

- `ct_ifu_top` 的外部边界不是简单的“取一条指令”：它同时承担 MMU VA 请求、BIU cache-line 请求/响应、CP0/LSU I-cache 维护、RTU/IU 控制流纠错、IDU 三路指令输出、IU PCFIFO 创建信息、HAD/VFDSU 观测和向量异常入口。
- `ct_ifu_pcgen` 是全局 PC/取消/优先级中心。PC load 的优先级为 HAD、向量、RTU、IU、ADDRGEN、IB、IP reissue/IP change-flow、IF reissue/IF change-flow，最后才是顺序 PC；见 `gen_rtl/ifu/rtl/ct_ifu_pcgen.v:387-481`。
- IF、IP、IB 不是三个独立 FIFO，而是通过 `*_stall`、`*_cancel`、`*_pipe_cancel`、`*_pcload`、`*_chgflw` 组合控制保持/重取/清空；`pcgen` 对高优先级 redirect 的统一取消传播见 `ct_ifu_pcgen.v:531-710`。
- 分支预测由 BHT、BTB、L0 BTB、间接 BTB、RAS 和 SFP 协同完成；实际指令/目标校验在 IP/IB 阶段完成，更新分别回到预测器和 IU/RTU。
- 本目录内的 SRAM wrapper 只覆盖部分宏名；若工程的 filelist 需要来自 `gen_rtl/lsu/rtl` 或工艺/FPGA 宏库的 wrapper，必须以实际 filelist 为准，不能仅凭本目录判断可独立编译。详见第 9 节。

## 2. 文件与实例层次

### 2.1 `ct_ifu_top` 的直接实例

`ct_ifu_top` 从 `gen_rtl/ifu/rtl/ct_ifu_top.v:18` 开始，直接实例化下表模块。实例位置是源码中的真实位置；其中同一模块的控制面/数据面分别列出，是因为 RTL 明确将它们作为独立实例连接。

| 实例 | module | 作用 | 主要实例位置 |
|---|---|---|---:|
| `x_ct_ifu_addrgen` | `ct_ifu_addrgen` | IP 阶段分支目标计算、BTB/L0 BTB 更新、分支误预测校验 | 1736 |
| `x_ct_ifu_bht` | `ct_ifu_bht` | bi-mode BHT，含全局历史、taken/not-taken、select 阵列和更新 buffer | 1776 |
| `x_ct_ifu_btb` | `ct_ifu_btb` | L1 BTB tag/data 查询、way prediction、更新和失效 | 1829 |
| `x_ct_ifu_l0_btb` | `ct_ifu_l0_btb` | 16-entry、低延迟 BTB；覆盖 IF/IP/IB 控制流早期命中 | 1876 |
| `x_ct_ifu_sfp` | `ct_ifu_sfp` | speculative-failure/no-spec、SF/BAR/VL 预测 | 1926 |
| `x_ct_ifu_ibctrl` | `ct_ifu_ibctrl` | IB 控制仲裁、stall、flush、间接 BTB/RAS、IBUF/LBUF 选择 | 1967 |
| `x_ct_ifu_ibdp` | `ct_ifu_ibdp` | 将 IP halfword/decode 信息组装为 IB 指令/控制流元数据 | 2088 |
| `x_ct_ifu_ibuf` | `ct_ifu_ibuf` | 32-entry 指令缓冲，向 IDU 提供三路指令 | 2619 |
| `x_ct_ifu_icache_if` | `ct_ifu_icache_if` | I-cache tag/data/predecode 阵列的读写仲裁和维护访问 | 2817 |
| `x_ct_ifu_ifctrl` | `ct_ifu_ifctrl` | IF 有效/暂停/取消、I-cache 失效状态机、IP 交接 | 2877 |
| `x_ct_ifu_ifdp` | `ct_ifu_ifdp` | cache/refill 数据选择、halfword 切分、物理属性/异常生成 | 2993 |
| `x_ct_ifu_ind_btb` | `ct_ifu_ind_btb` | 间接跳转 BTB，保存 target/privilege/valid 并维护路径历史 | 3211 |
| `x_ct_ifu_ipb` | `ct_ifu_ipb` | refill/prefetch 请求仲裁、4-beat 预取 buffer、BIU 读响应分流 | 3258 |
| `x_ct_ifu_ipctrl` | `ct_ifu_ipctrl` | IP valid/stall/refill/reissue、分支选择和 L0/L1 命中控制 | 3317 |
| `x_ct_ifu_ipdp` | `ct_ifu_ipdp` | 两路解码、8 个 halfword 的 branch/PC/异常/vector 元数据 | 3498 |
| `x_ct_ifu_l1_refill` | `ct_ifu_l1_refill` | I-cache line refill 的请求、4 个响应 beat、取消/错误处理 | 3845 |
| `x_ct_ifu_lbuf` | `ct_ifu_lbuf` | 16-entry loop buffer，捕获并重放循环体 | 3915 |
| `x_ct_ifu_pcfifo_if` | `ct_ifu_pcfifo_if` | 从 IB/LBUF halfword 选出最多两条控制流检查点送 IU | 4088 |
| `x_ct_ifu_pcgen` | `ct_ifu_pcgen` | 全局 PC、redirect 优先级、取消/flush、MMU VA 和预测器索引 | 4145 |
| `x_ct_ifu_ras` | `ct_ifu_ras` | 12-entry return-address stack，提供 return target 和 push 信息 | 4253 |
| `x_ct_ifu_vector` | `ct_ifu_vector` | reset/invalidate/异常向量状态机及异常 PC | 4280 |
| `x_ct_ifu_debug` | `ct_ifu_debug` | 汇聚 IFU 调试状态到 83-bit HAD 信息 | 4306 |

这些实例的完整顶层端口连接从 `ct_ifu_top.v:1967` 到 `ct_ifu_top.v:4364` 展开；例如 IPB 的 BIU 端口在 `3258-3274`，PCGEN 的控制连接在 `4145` 之后，RAS/vector/debug 的连接在 `4253-4364`。

### 2.2 直接下一级实例

| module | 本目录内的下一级实例 |
|---|---|
| `ct_ifu_bht` | `ct_ifu_bht_pre_array` ×2、`ct_ifu_bht_sel_array` ×1；BHT 的 64K-bit bi-mode 结构和阵列连接见 `ct_ifu_bht.v:323-334,1941-1957`。 |
| `ct_ifu_btb` | `ct_ifu_btb_tag_array`、`ct_ifu_btb_data_array`；BTB 以 tag/data 分离并带 refill buffer。 |
| `ct_ifu_l0_btb` | `ct_ifu_l0_btb_entry` ×16；entry 是 latch/register 形式的单项 tag、target、way prediction、counter、RAS 元数据，实例展开在 `ct_ifu_l0_btb.v:686-1287`。 |
| `ct_ifu_ind_btb` | `ct_ifu_ind_btb_array` ×1，阵列内部使用 `ct_spsram_256x23`，见 `ct_ifu_ind_btb.v:627-668` 和 `ct_ifu_ind_btb_array.v:74-86`。 |
| `ct_ifu_sfp` | `ct_ifu_sfp_entry` ×12，实例展开在 `ct_ifu_sfp.v:815-1102`。 |
| `ct_ifu_ipdecode` | `ct_ifu_decd_normal`，两路 `ct_ifu_ipdecode` 由 `ct_ifu_ipdp` 实例化；IPDP 另引用 IDU 侧 `ct_idu_id_decd_special`，其定义不在本目录。 |
| `ct_ifu_ibuf` | `ct_ifu_ibuf_entry` ×32；入口实例从 `ct_ifu_ibuf.v:1429` 开始，容量参数为 32。 |
| `ct_ifu_lbuf` | `ct_ifu_lbuf_entry` ×16，用于保存循环体指令和控制流元数据。 |
| `ct_ifu_l1_refill` | `ct_ifu_precode` ×1，把 refill 的 128-bit line 预译码为 cache predecode bits。 |
| `ct_ifu_icache_if` | `ct_ifu_icache_tag_array`、`ct_ifu_icache_data_array0/1`、`ct_ifu_icache_predecd_array0/1`，实例见 `ct_ifu_icache_if.v:558-562`。 |

### 2.3 目录内的存储 wrapper

`ct_spsram_1024x59`、`1024x64`、`128x16`、`2048x32_split`、`2048x59`、`256x23`、`256x59`、`512x22`、`512x44`、`512x59` 均是统一的 `A/CEN/CLK/D/GWEN/Q/WEN` 端口 wrapper，内部选择 FPGA `ct_f_spsram_*` 宏；以 `ct_spsram_1024x64.v:51-69` 和 `ct_spsram_2048x32_split.v:51-66` 为例，TSMC 宏连接被保留为注释。

### 2.4 50 个文件的完整 module/作用索引

下面的索引按 `gen_rtl/ifu/rtl/*.v` 实际清单逐一列出，补充 array/entry/helper 文件的真实 module 和连接关系。`module` 起始行用于确认定义文件；后面的行号指向关键实例、存储连接或功能逻辑。

#### 流水线、控制和数据通路

| 文件 | module | 实际作用/连接 | 证据 |
|---|---|---|---|
| `ct_ifu_top.v` | `ct_ifu_top` | IFU 顶层边界，实例化全部 IFU 控制/数据/预测模块。 | `:18`, 实例 `:1736-4364` |
| `ct_ifu_addrgen.v` | `ct_ifu_addrgen` | 分支 offset/target 计算、误预测比较，向 PCGEN/BTB/L0 BTB 提供更新。 | `:17`, `:168-302` |
| `ct_ifu_pcgen.v` | `ct_ifu_pcgen` | PC redirect 优先级、顺序 PC、MMU VA、取消/flush、预测器索引。 | `:17`, `:387-974` |
| `ct_ifu_ifctrl.v` | `ct_ifu_ifctrl` | IF valid/stall/reissue、I-cache 维护状态机和 IP 交接。 | `:17`, `:488-757` |
| `ct_ifu_ifdp.v` | `ct_ifu_ifdp` | cache/refill 数据选择、halfword 切分、tag/PA compare、MMU/断点异常。 | `:17`, `:866-1798` |
| `ct_ifu_ipctrl.v` | `ct_ifu_ipctrl` | IP valid/stall、分支选择、L0/L1 hit、refill、way reissue。 | `:17`, `:946-1453,1905-1994` |
| `ct_ifu_ipdp.v` | `ct_ifu_ipdp` | 两路 IP decode 的数据面，组织 8 个 halfword、H0 跨界、目标/异常/vector 元数据。 | `:17`, `:2128-2339,5560-5884,6118-6872` |
| `ct_ifu_ipdecode.v` | `ct_ifu_ipdecode` | 对 h0-h8 形成 32-bit 指令窗口，并为每个 halfword 实例化 normal decoder。 | `:17`, 指令拼接 `:506-514`，decoder `:518-742` |
| `ct_ifu_decd_normal.v` | `ct_ifu_decd_normal` | 普通指令语义/控制流预译码：branch、JAL/JALR、pc_oper、load/store、pcall/preturn、indirect 等。 | `:17`, `:111-301` |
| `ct_ifu_precode.v` | `ct_ifu_precode` | 对 refill 的 128-bit line 按 8 个 halfword 产生 branch/absolute-branch 等 predecode bits。 | `:17`, halfword `:121-128`，branch decode `:131-` |
| `ct_ifu_ibctrl.v` | `ct_ifu_ibctrl` | IB 阶段仲裁：IBUF/LBUF 选择、stall、flush、bypass、indirect BTB/RAS/PCFIFO 控制。 | `:17`, `:537-980` |
| `ct_ifu_ibdp.v` | `ct_ifu_ibdp` | 将 IP halfword/decode 信息组装成 73-bit ID packet 和 IB 控制流元数据。 | `:17`, 字段 `:1815-1838` |
| `ct_ifu_ibuf.v` | `ct_ifu_ibuf` | 32-entry 指令 buffer，执行 create/retire/merge/pop/bypass，输出三路指令。 | `:17`, entry 实例 `:1429-`，输出约 `:9526-9618` |
| `ct_ifu_ibuf_entry.v` | `ct_ifu_ibuf_entry` | IBUF 单 entry 的 valid、PC、指令 metadata 和 speculative 信息寄存器。 | `:17`, 时序存储 `:219-393` |
| `ct_ifu_lbuf.v` | `ct_ifu_lbuf` | 16-entry loop buffer，执行 fill/front branch/cache/active 状态和循环重放。 | `:17`, 状态/entry `:1216-1470,2532-` |
| `ct_ifu_lbuf_entry.v` | `ct_ifu_lbuf_entry` | LBUF 单 entry 的 valid、指令、PC、branch/BHT/vector metadata 存储。 | `:17`, valid/data 更新 `:175-231` |
| `ct_ifu_pcfifo_if.v` | `ct_ifu_pcfifo_if` | 从 IB/LBUF 的 halfword 控制流中选择最多两个 IU PCFIFO create slot。 | `:17`, target/选择 `:293-298,1008-1070` |
| `ct_ifu_ipb.v` | `ct_ifu_ipb` | refill/prefetch 共享 BIU 请求、tag compare、4-beat prefetch buffer 和响应分流。 | `:17`, 状态 `:289-520`、BIU `:581-848` |
| `ct_ifu_l1_refill.v` | `ct_ifu_l1_refill` | I-cache line refill 请求、4 beat 接收、错误/取消、precode 和 cache 写入。 | `:17`, FSM `:268-411`，数据/BIU `:450-620` |
| `ct_ifu_vector.v` | `ct_ifu_vector` | reset/invalidate 与异常 vector PCLOAD 状态机。 | `:17`, FSM/PC `:146-273` |
| `ct_ifu_debug.v` | `ct_ifu_debug` | 汇聚 IFU 各 stage、预测、refill、vector、VFDSU 状态到 HAD debug 信息。 | `:17`，顶层连接 `ct_ifu_top.v:4306-4364` |

#### 预测器及其 array/entry helper

| 文件 | module | 实际作用/连接 | 证据 |
|---|---|---|---|
| `ct_ifu_bht.v` | `ct_ifu_bht` | bi-mode BHT 控制、GHR、update buffer、invalidate；实例化两个 pre array 和一个 select array。 | `:17`, 子实例 `:1941-1975` |
| `ct_ifu_bht_pre_array.v` | `ct_ifu_bht_pre_array` | BHT taken/not-taken 2-bit counter 阵列 wrapper，实例化 `ct_spsram_1024x64`。 | `:17`, enable `:82`, SRAM `:86` |
| `ct_ifu_bht_sel_array.v` | `ct_ifu_bht_sel_array` | BHT select counter 阵列 wrapper，实例化 `ct_spsram_128x16`。 | `:17`, enable `:82`, SRAM `:86` |
| `ct_ifu_btb.v` | `ct_ifu_btb` | L1 BTB 的 index、tag/data 读写、way prediction、refill buffer 和 invalidate。 | `:17`, helper 实例 `:830-860` |
| `ct_ifu_btb_tag_array.v` | `ct_ifu_btb_tag_array` | BTB tag/valid 阵列，4 个 way 的 write enable 拆成两个 bank，使用两个 `ct_spsram_512x22`。 | `:17`, write split `:83-91`，SRAM `:117-159` |
| `ct_ifu_btb_data_array.v` | `ct_ifu_btb_data_array` | BTB target/way-pred data 阵列，4-way 写使能拆 bank，使用两个 `ct_spsram_512x44`。 | `:17`, write split `:83-91`，SRAM `:116-158` |
| `ct_ifu_l0_btb.v` | `ct_ifu_l0_btb` | 低延迟 16-entry BTB，管理命中、WAIT、创建指针、更新和 IF/IP/IB 输出。 | `:17`, entry 实例 `:686-1287` |
| `ct_ifu_l0_btb_entry.v` | `ct_ifu_l0_btb_entry` | L0 BTB 单 entry 的 valid/tag/target/way/counter/RAS 寄存器。 | `:17`, 存储 `:108-155` |
| `ct_ifu_ind_btb.v` | `ct_ifu_ind_btb` | 间接 BTB 控制、path/GHR index、读写和全表 invalidate。 | `:17`, array/状态 `:309-668` |
| `ct_ifu_ind_btb_array.v` | `ct_ifu_ind_btb_array` | 间接 BTB 256×23 存储 wrapper，内部实例化 `ct_spsram_256x23`。 | `:17`, SRAM `:83-110` |
| `ct_ifu_ras.v` | `ct_ifu_ras` | 12-entry return-address stack，处理 pcall push、preturn pop、privilege 检查和 L0 BTB push。 | `:17`, entry/output `:835-1497,1810-1919` |
| `ct_ifu_sfp.v` | `ct_ifu_sfp` | 12-entry speculative-failure/SF/BAR/VL 预测器控制和更新。 | `:17`, entry 实例 `:815-1102` |
| `ct_ifu_sfp_entry.v` | `ct_ifu_sfp_entry` | SFP 单 entry 的 SF/BAR PC、计数器和 VL 相关状态存储。 | `:17`, 存储/计数 `:116-221` |

#### I-cache array helper

| 文件 | module | 实际作用/连接 | 证据 |
|---|---|---|---|
| `ct_ifu_icache_if.v` | `ct_ifu_icache_if` | 统一仲裁 tag、两路 data、两路 predecode 的读/写/维护访问。 | `:17`, 五类 array 实例 `:745-832` |
| `ct_ifu_icache_tag_array.v` | `ct_ifu_icache_tag_array` | 按 `ICACHE_256K/128K/64K/32K` 选择深度的 tag/FIFO 存储。 | `:25`, 容量选择 `:86-129` |
| `ct_ifu_icache_data_array0.v` | `ct_ifu_icache_data_array0` | way0 四 bank、128-bit line data 存储；根据容量/ECC 选择 SRAM。 | `:24`, bank 拼接 `:108-161`，宏选择 `:166-343` |
| `ct_ifu_icache_data_array1.v` | `ct_ifu_icache_data_array1` | way1 四 bank、128-bit line data 存储；结构与 way0 对称。 | `:24`, bank 拼接 `:108-161`，宏选择 `:166-343` |
| `ct_ifu_icache_predecd_array0.v` | `ct_ifu_icache_predecd_array0` | way0 预译码 bit 存储，与 data way0 同 index/write 时序。 | `:16`, enable `:68-71`，宏选择 `:75-115` |
| `ct_ifu_icache_predecd_array1.v` | `ct_ifu_icache_predecd_array1` | way1 预译码 bit 存储，与 data way1 对称。 | `:16`, enable `:68-71`，宏选择 `:75-115` |

#### 本目录内的 10 个 SRAM wrapper

| 文件/module | 宽度/深度 | 实际连接 |
|---|---:|---|
| `ct_spsram_1024x59.v` / `ct_spsram_1024x59` | 1024×59 | 通用 59-bit tag/metadata wrapper，FPGA `ct_f_spsram_1024x59`，定义 `:17-69`。 |
| `ct_spsram_1024x64.v` / `ct_spsram_1024x64` | 1024×64 | BHT pre array 使用，FPGA `ct_f_spsram_1024x64`，定义 `:17-72`。 |
| `ct_spsram_128x16.v` / `ct_spsram_128x16` | 128×16 | BHT select array 使用，FPGA `ct_f_spsram_128x16`，定义 `:17-70`。 |
| `ct_spsram_2048x32_split.v` / `ct_spsram_2048x32_split` | 2048×32 | I-cache 64K data/predecode 非 ECC 变体，FPGA 宏实例 `:65`。 |
| `ct_spsram_2048x59.v` / `ct_spsram_2048x59` | 2048×59 | I-cache 256K tag 非 ECC 变体，FPGA 宏实例 `:65`。 |
| `ct_spsram_256x23.v` / `ct_spsram_256x23` | 256×23 | indirect BTB array 使用，FPGA 宏实例 `:65`。 |
| `ct_spsram_256x59.v` / `ct_spsram_256x59` | 256×59 | I-cache 32K tag 非 ECC 变体，FPGA 宏实例 `:65`。 |
| `ct_spsram_512x22.v` / `ct_spsram_512x22` | 512×22 | BTB tag array 两个 bank 使用，FPGA 宏实例 `:65`。 |
| `ct_spsram_512x44.v` / `ct_spsram_512x44` | 512×44 | BTB data array 两个 bank 使用，FPGA 宏实例 `:65`。 |
| `ct_spsram_512x59.v` / `ct_spsram_512x59` | 512×59 | I-cache 64K tag 非 ECC 变体，FPGA 宏实例 `:65`。 |

因此，之前只按高层模块统计的清单遗漏了 21 个文件；修订后的 50-file 清单已经包含所有 array、entry、decoder、precode 和本目录 SRAM wrapper。I-cache 的 `data_array1`/`predecd_array1` 并非未使用文件，而是由 `ct_ifu_icache_if` 明确实例化的第二路，见 `ct_ifu_icache_if.v:778-814`。

## 3. 顶层边界与信号协议

### 3.1 时钟、复位和门控

- 主时钟为 `forever_cpuclk`，主复位为低有效 `cpurst_b`；`ct_ifu_top` 的顶层端口从 `ct_ifu_top.v:18-415` 声明。
- 各功能块通过 `gated_clk_cell` 使用 `forever_cpuclk`，全局使能通常是 `cp0_yy_clk_en`，模块使能是 `cp0_ifu_icg_en`，扫描旁路为 `pad_yy_icg_scan_en`。PCGEN 的 debug gate 见 `ct_ifu_pcgen.v:714-733`，vector gate 见 `ct_ifu_vector.v:114-131`，RAS 的 entry gate 见 `ct_ifu_ras.v:1340-1347`。
- `cpurst_b` 不仅清寄存器，也驱动 vector `RESET` 状态；vector 只有收到 `cp0_ifu_rst_inv_done` 才回到 IDLE，并产生 `ifu_xx_sync_reset`/`ifu_cp0_rst_inv_req`，见 `ct_ifu_vector.v:146-206`。

### 3.2 BIU 读请求/响应

`ct_ifu_top` 对 BIU 的请求输出在 `ct_ifu_top.v:352-364`，返回输入在 `219-224`。实际请求由 IPB 产生、由 refill/prefetch 两类请求共享。

| 项目 | RTL 行为 |
|---|---|
| 请求源 | `ipb` 将 `l1_refill_ipb_req` 和 prefetch 请求编码为一个 BIU read；`ifu_biu_rd_req = (ref_req_for_biu || pref_req_for_biu) && cp0_yy_clk_en`。 |
| ID | refill 使用 `rd_id=0`，prefetch 使用 `rd_id=1`；返回按 `biu_ifu_rd_id` 分流。对应逻辑在 `ct_ifu_ipb.v` 的 BIU request/response 区域（约 `581-800`）。 |
| 数据 | 每个 beat 为 `biu_ifu_rd_data[127:0]`，`rd_data_vld` 表示有效，`rd_last` 表示最后一个 beat，`rd_resp[1]` 表示传输错误；refill 正常收集 4 beats。 |
| 地址/长度 | refill 地址为 line 对齐的 physical address，prefetch 地址为下一 cache line；cacheable line 使用 4-beat burst，`rd_size=3'b100`（16B beat），非 line 请求使用单 beat。 |
| 属性 | `rd_prot`、`rd_cache`、`rd_domain`、`rd_snoop`、`rd_user` 由 refill 的 cacheable/bufferable/share/secure/supervisor/machine 属性形成，不由 IFU 重新翻译。 |
| ready | `ifu_biu_r_ready` 在 IPB 侧由 `~l1_refill_ipb_ctc_inv` 控制；I-cache 维护期间可以阻止返回继续推进。 |

`ct_ifu_l1_refill.v:268-411` 的状态机为 `IDLE → REQ → WFD1..WFD4`，发生 change-flow、invalidate 或 response error 时进入对应取消/失效路径；完成后把数据写入 I-cache，并把 reissue/数据有效信息交给 IF/IDP。`ct_ifu_ipb.v:289-304,381-464` 另外维护 prefetch 的 `PF_REQ/PF0..PF3` 和 4-entry prefetch buffer。

### 3.3 MMU VA 请求与响应

- `pcgen` 输出 `ifu_mmu_va[62:0]`、`ifu_mmu_va_vld`、`ifu_mmu_abort`；VA 由当前 IF PC 和高位 sign-extension/special-PC 组成，见 `ct_ifu_pcgen.v:735-759`。
- `ifu_mmu_abort` 在 IF 取消、全局时钟关闭或 vector reset-on 时有效；`ifu_mmu_va_vld` 按当前 RTL 保持有效。
- MMU 返回 `mmu_ifu_pavld/pa/pgflt/deny/ca/buf/sec`，由 IFDP/IPCTRL/IBDP 形成 cache 属性、访问异常、refill 属性和下游指令异常；顶层输入声明见 `ct_ifu_top.v:291-298`。
- IFDP 对 cache tag 的解释是 valid + 28-bit physical tag；`ct_ifu_ifdp.v` 的 tag compare 区域（约 `1224-1273`）将返回 tag 与 MMU PA 分段比较。

### 3.4 CP0/LSU I-cache 维护

CP0 输入包括 BHT/BTB/I-cache/ind-BTB/L0-BTB/LBUF/RAS enable/invalidate，I-cache read request/index/tag/way，以及 `cp0_ifu_rst_inv_done` 等；输出包括 `ifu_cp0_icache_inv_done`、读完成和读数据，端口分组见 `ct_ifu_top.v:225-260,365-371`。

`ct_ifu_ifctrl.v:748-757` 定义 I-cache 维护状态：`IDLE/READ_REQ/READ_RD/READ_ST/INV_ALL/INS_TAG_REQ/INS_TAG_RD/INS_CMP/INS_INV/INS_INV_ALL`。CP0/LSU 的 all/line/instruction invalidate 被转成一次请求或按 VIPT index 组合遍历；line read 返回 tag/data。LSU 的 invalidation 完成信号在顶层 `ct_ifu_top.v:408-415`。

## 4. PC、redirect、flush 和流水线协议

### 4.1 PC 生成和优先级

`ct_ifu_pcgen.v:387-481` 的 `pc_bus` 选择优先级如下，前者覆盖后者：

1. HAD `had_ifu_pcload`；
2. vector `vector_pcgen_pcload`；
3. RTU `rtu_ifu_chgflw_vld`；
4. IU `iu_ifu_chgflw_vld`；
5. ADDRGEN 分支误预测；
6. IB 侧控制流改变；
7. IP reissue，再是 IP branch change-flow；
8. IF reissue，再是 IF change-flow；
9. 顺序 `if_pc + 8B`。

IF PC 在 `ct_ifu_pcgen.v:470-481` 复位后由 redirect load，否则在非 stall 时按 fetch block 递增；reissue 保留必要的低位 PC。BTB/BHT index 主要来自 `pc_bus[12:3]`，I-cache index 使用 `pc_bus[15:0]`，见 `ct_ifu_pcgen.v:812-855,928-974`。

### 4.2 取消与流水线级联

- IF：`pcgen_ifctrl_cancel` 覆盖非 L0 高优先级 redirect、RTU exception 和 debug；IF pipe cancel 进一步覆盖 IP cancel、LBUF mask、IP check error/reissue，见 `ct_ifu_pcgen.v:640-673`。
- IP：`pcgen_ipctrl_cancel` 覆盖 HAD/vector/RTU/IU/ADDRGEN/IB/exception/debug；IP pipe cancel 还包含 LBUF mask、IB redirect 和 IP stall 条件，见 `ct_ifu_pcgen.v:674-688`。
- IB：`pcgen_ibctrl_cancel` 覆盖 HAD/vector/RTU/IU/exception/debug；同时产生 IBUF/LBUF flush，见 `ct_ifu_pcgen.v:689-710`。
- IFCTRL 只有在 `inst_data_vld && pc_vld && !cancel && !self_stall` 时形成 IF valid；`if_stage_stall` 由自身 stall 或 IPCTRL stall 形成，见 `ct_ifu_ifctrl.v:488-587`。
- IPCTRL 的 stall 主要来自 branch missigned、miss-under-refill、超过一个控制流以及 IB 侧 stall；refill 请求在没有 tag hit 时发出，见 `ct_ifu_ipctrl.v:1380-1453`。
- IBCTRL 将 mispredict、FIFO/IBUF full、indirect BTB miss、PCFIFO 超量等合并为 IP/IB/PCFIFO stall；IBUF/LBUF 选择和 bypass 控制在 `ct_ifu_ibctrl.v:599-882`。

### 4.3 ADDRGEN 与 BTB/L0 BTB

ADDRGEN 对条件分支计算 `base + sign_extend(offset<<1)`，与预测 target 比较并生成 `addrgen_pcgen_pcload`；分支在 LBUF active/cache 路径时被屏蔽，因为循环末端才允许改变流，见 `ct_ifu_addrgen.v:168-188,270-302`。

L0 BTB 的读使能依赖 CP0 enable、PCGEN change-flow 或非 stall，命中结果在 IF/IP/IB 间流水；它有 IDLE/WAIT 两态，并以 16 个 `ct_ifu_l0_btb_entry` 保存 target/way/counter/RAS 元数据，见 `ct_ifu_l0_btb.v:322-390,523-636,1330-1343`。PCGEN 对 L0 change-flow 有专门 mask，避免低优先级 L0 命中覆盖 HAD/vector/RTU/ADDRGEN/IU 等高优先级 redirect，见 `ct_ifu_pcgen.v:856-927`。

## 5. 预测器与控制流预测

### 5.1 BHT

`ct_ifu_bht.v:323-334` 明确给出 bi-mode 结构：总容量 64K bits，由 taken/not-taken 两个 pre array 和一个 select array 组成；pre array 为 1K×64 SRAM，select array 为 128×16 SRAM。读取在 PCGEN change-flow/顺序访问、IP/LBUF branch、BJU mispredict 或 RTU flush 等条件下启动，见 `ct_ifu_bht.v:354-455`。

- pre-array index 使用 PC 与 GHR hash；select-array index 为 `pcgen_bht_pcindex[9:3]`。
- `rtughr_reg[21:0]` 保存退休历史，`vghr_reg[21:0]` 保存预测路径历史；RTU flush、IU change-flow、LBUF/IP branch 会更新虚拟历史，见 `ct_ifu_bht.v:582-697`。
- 预测结果被送给 IPCTRL/IPDP/PCFIFO；BJU retire/mispredict 更新进入 update buffer；invalidate 期间输出 `bht_ifctrl_inv_on/done`，见 `ct_ifu_bht.v:1670-1760,1897-1927`。

### 5.2 L1 BTB

`ct_ifu_btb.v:225-231` 给出 tag 布局：tag entry 携带 valid/tag，data entry 携带 way prediction 和 target；读 index 在 invalidate、refill buffer、PCGEN index 之间选择。BTB 结果经过寄存器，支持 way mismatch/reissue，并将四路结果送 IFDP。更新通过 refill buffer 暂存，等高优先级 change-flow 结束后再写阵列，见 `ct_ifu_btb.v:377-416,454-610,700-819`。

### 5.3 间接 BTB 与 RAS

- `ct_ifu_ind_btb.v:187-284` 在 CP0 enable 且发生 RTU jump mispredict、IB indirect check 或 IP indirect detect 时读/写；数据为 `{valid, priv_mode[1:0], target[19:0]}`。读写 index 分别结合 path register 与 GHR，见 `ct_ifu_ind_btb.v:309-603`。invalidate 是 8-bit 全表 sweep，见 `627-668`。
- `ct_ifu_ibctrl.v:546-559` 将 `ind_btb_dout[22]` 解释为 valid；无 valid 时生成 indirect-BTB miss stall/check，RAS return 则走 RAS target。
- RAS 为 12-entry，`ras_pop = ibctrl_ras_preturn_vld`，top pointer 选择当前 return PC；push 结果同时送 IPDP 和 L0 BTB，见 `ct_ifu_ras.v:835-1497,1810-1919`。
- PCFIFO 对 indirect target 先减去 branch offset；若是 return 则优先使用 RAS target，见 `ct_ifu_pcfifo_if.v:293-298`。

### 5.4 SFP

SFP 用 12 个 `ct_ifu_sfp_entry` 比较 PC 高位和 SF/BAR/VL 相关元数据；RTU retired no-spec/hit/miss/vl 信息驱动更新，输出命中/类型/预测低位给 IPDP。它负责标记 speculative failure/no-spec 和 vector 相关属性，不直接成为 PC redirect 源，见 `ct_ifu_sfp.v:250-491,815-1102`。

## 6. I-cache、预解码和 refill

### 6.1 I-cache 组织

`ct_ifu_icache_if.v:248-510` 将 I-cache 拆成：

- 一个 tag array：每行保存 FIFO 位和两路 `{valid, 28-bit tag}`；
- 两个 data array（way0/way1），每个 way 四个 bank；
- 两个 predecode array，与 data way 对齐；
- way prediction、顺序访问、change-flow、refill 写入和 CP0/LSU 维护的 chip-enable 仲裁。

IFDP 从 way0/way1 cache 数据或 refill 数据中选源，并切出 8 个 halfword；预解码同样按 halfword 对齐。IFDP 的数据来源和 8-halfword 切分见 `ct_ifu_ifdp.v:866-948`，MMU PA/tag hit 比较见约 `1224-1273`。

### 6.2 容量参数与 SRAM

`ct_ifu_icache_tag_array.v:86-129` 和 data/predecode array 文件依据 `ICACHE_256K/128K/64K/32K` 选择深度：

| 配置 | tag array（非 ECC） | data/predecode（非 ECC） |
|---|---|---|
| 256K | `ct_spsram_2048x59` | 4×`ct_spsram_8192x32` |
| 128K | `ct_spsram_1024x59` | 4×`ct_spsram_4096x32` |
| 64K | `ct_spsram_512x59` | 4×`ct_spsram_2048x32_split` |
| 32K | `ct_spsram_256x59` | 4×`ct_spsram_1024x32` |

ECC 分支使用 `61`/`33` 位相关宏，实际选择见 `ct_ifu_icache_tag_array.v:102-128` 和 `ct_ifu_icache_data_array0.v:166-343`；predecode array 的选择见 `ct_ifu_icache_predecd_array0.v:74-128`。本目录只定义了部分这些 wrapper，未定义项见第 9 节。

### 6.3 Refill 与 prefetch

- IPCTRL 在 tag miss 且没有互斥工作时发 `ipctrl_l1_refill_miss_req`，传递 VPC/PPC、cacheable/bufferable/share/secure 等属性。
- L1_REFILL 在 `REQ` 期间等待 BIU grant；grant 后收集 `WFD1..WFD4`，把 data/precode 写入 I-cache，并通知 IFDP/IFCTRL。change-flow 会取消后续 beat 或转入 invalidate wait，见 `ct_ifu_l1_refill.v:319-411,450-620`。
- IPB 将 refill 和 prefetch 复用 BIU，prefetch 只在 enable、cacheable、无 invalidate 且不跨 4KB 时启动，见 `ct_ifu_ipb.v:500-520`；预取数据先进入 4-entry buffer，随后写回 cache。
- refill data 的 byte order/precode 由 L1_REFILL 统一处理，避免 IFDP 直接解释 BIU 原始 beat。

## 7. IF/IP/IB 数据流与下游协议

### 7.1 IF 与 IP

IFDP 将 fetch line 转换为 8 个 halfword、当前 PC、VPC/物理属性、predecode、branch mask、breakpoint 和 MMU/refill 异常。`if_mmu_expt_vld` 由 page fault/refill error 等组合形成，见 `ct_ifu_ifdp.v:1418-1475,1476-1798`。

IPDP 对两路数据分别调用 `ct_ifu_ipdecode`；正常指令语义由 `ct_ifu_decd_normal` 提供。它根据 predecode/BHT/L0/L1 BTB/RAS/SFP 选择第一条控制流，生成 conditional/absolute/indirect branch、JAL/JALR、目标地址、load/store、fence、vector VSETVLI 等信息。两路 decode 实例和正常 decoder 见 `ct_ifu_ipdp.v:2128-2339`。

IP 阶段保留跨 fetch block 的 H0 halfword；H0 只有在 `h0_update_vld` 且没有 stall/cancel/MMU deny 时更新，见 `ct_ifu_ipdp.v:5560-5776`。这样 32-bit 指令跨边界时可以与下一 fetch block 合并。

IPCTRL 用 tag hit/refill-way0、异常、cancel、debug 和 branch mask 形成 `ip_data_vld/ip_vld`；branch taken/mistaken 形成 IP redirect 或 reissue，见 `ct_ifu_ipctrl.v:946-980,1230-1357,1905-1994`。

### 7.2 IB、IBUF 与 LBUF

- IBDP 将 IP 的 8 halfword 信息按 H0..H8 组织，带 PC、opcode、branch、split/fence、exception/vector、breakpoint、no-spec、VL/VSEW/VLMUL 等元数据；IB packet 的 73-bit 字段定义见 `ct_ifu_ibdp.v:1815-1838`。
- IBCTRL 选择普通 IBUF 或 active LBUF，负责 create/retire/merge/bypass、间接目标和 RAS、mispredict/fifo/full stall，见 `ct_ifu_ibctrl.v:771-980`。
- IBUF 参数为 32 entry，实例化 32 个 `ct_ifu_ibuf_entry`；末端对 merge/pop/bypass 结果形成三路 `inst0/1/2` 及其 metadata，见 `ct_ifu_ibuf.v:1429-1925` 及文件末端约 `9526-9618`。
- LBUF 参数为 16 entry，状态包括 `IDLE/FILL/FRONT_BRANCH/CACHE/ACTIVE/FRONT_FILL/FRONT_CACHE`；捕获到循环末端后进入 ACTIVE，给 IBCTRL/PCGEN 提供 loop change-flow 和 valid mask，并可以直接送三路指令，见 `ct_ifu_lbuf.v:1216-1470,6746-6945`。

### 7.3 IDU 与 IU 输出

`ct_ifu_top` 向 IDU 输出三路 73-bit `ifu_idu_ib_inst{0,1,2}_data` 和 valid，端口声明见 `ct_ifu_top.v:381-387`，实际由 IBUF/LBUF/IBDP 路径组成。

IB/PCFIFO 侧向 IU 提供两个 create slot。PCFIFO 根据 `hn_pc_oper` 从 8 个 halfword 选择最多两条控制流；LBUF active 时改用 LBUF 的 inst target/BHT/GHR 信息。输出包括 current PC、target PC、JAL/JALR、dst_vld、BHT prediction、check index、jump mispredict，见 `ct_ifu_pcfifo_if.v:1008-1070`；当控制流超过两个时输出 `pcfifo_if_ibctrl_more_than_two`。

## 8. 异常、向量、调试和维护控制

### 8.1 异常向量

`ct_ifu_vector.v:146-206` 的状态机只有有效 RTL 状态 `RESET/IDLE/PCLOAD`：复位进入 RESET，等待 CP0 I-cache reset/invalidate 完成；RTU exception 进入 PCLOAD，并产生一次 vector PC load。异常 PC 由 `cp0_ifu_vbr`、`cp0_ifu_rvbr` 和 `rtu_ifu_xx_expt_vec` 形成，`reset_expt` 选择 reset VBR，具体计算在 `ct_ifu_vector.v:218-240`；输出 PC/load 在 `271-273`。

vector reset-on 同时参与 PCGEN redirect/取消、IFCTRL/I-cache 状态和同步 reset；debug-on 时 vector 回到 IDLE，避免调试模式继续推进异常向量状态机。

### 8.2 HAD/debug

`ct_ifu_debug` 不改变取指数据通路，而是收集 IFCTRL、IFDP、IPCTRL、IPB、L1_REFILL、L0 BTB、IBCTRL/IBDP、LBUF、PCGEN、vector 及 VFDSU 状态，生成 `ifu_had_debug_info[82:0]`；顶层连接见 `ct_ifu_top.v:4306-4364`。

HAD 指令/PC load 直接进入 PCGEN 优先级最高的路径；IPDP 在 `rtu_yy_xx_dbgon` 时支持 HAD IR/decoded metadata 路径。debug transition 还会产生 IF/IP/IB cancel，防止旧流水线数据进入 IDU。

### 8.3 cache invalidate 与 predictor invalidate

CP0/LSU invalidate 由 IFCTRL 状态机执行；BHT、BTB、indirect BTB 各有自己的 invalidate 计数/完成信号。`ct_ifu_top` 将它们的 done/on 信号分别回送 CP0 或用于 stall；未观察到把不同预测器合成一个共享 RAM 的逻辑。

## 9. 需要外部 filelist/宏库确认的项目

下列项目是从本目录 RTL 明确观察到的引用，但定义不在 `gen_rtl/ifu/rtl` 内，不能在本目录范围内确认最终实现：

1. I-cache 256K/128K data 选择的 `ct_spsram_8192x32`、`ct_spsram_4096x32`、`ct_spsram_1024x32` 在 `gen_rtl/lsu/rtl` 可见，而不在 IFU 目录；它们是否由同一 filelist 复用需由构建文件确认。
2. ECC 路径引用的 `ct_spsram_2048x33`、`ct_spsram_1024x33`、`ct_spsram_512x61`、`ct_spsram_256x61`，以及 BTB ECC/容量变体 `ct_spsram_1024x22`、`ct_spsram_1024x44`，在本目录未找到定义；很可能来自外部宏 wrapper 或未选中的配置分支。
3. `ct_ifu_ipdp` 引用 `ct_idu_id_decd_special`；该 decoder 不属于 IFU 目录，不能在本报告中展开其语义。
4. 宏 `ICACHE_*`、`L1_CACHE_ECC`、`BTB_*`、`PC_WIDTH` 等的最终取值由更高层配置/filelist 决定。本目录只能确认 module 内的分支和默认参数，不能确认当前综合产品的唯一容量配置。
5. SRAM wrapper 中 FPGA `ct_f_spsram_*` 与注释的 TSMC 宏连接，哪一路被综合由工程宏和 filelist 决定；本报告不假定某一工艺实现。

上述不确定项不影响 IFU 的逻辑级连接结论，但在独立编译或做门级存储替换时必须补齐。

## 10. 关键证据索引

| 主题 | 证据 |
|---|---|
| 顶层端口/实例 | `gen_rtl/ifu/rtl/ct_ifu_top.v:18-415,1736-1967,2619,2817,2877,2993,3211,3258,3317,3498,3845,3915,4088,4145,4253-4364` |
| PC 优先级/PC register | `gen_rtl/ifu/rtl/ct_ifu_pcgen.v:387-481` |
| cancel/flush/mask | `gen_rtl/ifu/rtl/ct_ifu_pcgen.v:531-710` |
| MMU VA/I-cache request | `gen_rtl/ifu/rtl/ct_ifu_pcgen.v:735-759,812-974` |
| IF valid/stall/reissue | `gen_rtl/ifu/rtl/ct_ifu_ifctrl.v:488-620,625-757` |
| IFDP halfword/tag/exception | `gen_rtl/ifu/rtl/ct_ifu_ifdp.v:866-948,1224-1273,1418-1798` |
| BHT 结构/GHR/invalidate | `gen_rtl/ifu/rtl/ct_ifu_bht.v:323-455,582-697,1670-1760,1941-1957` |
| BTB refill buffer | `gen_rtl/ifu/rtl/ct_ifu_btb.v:225-231,377-416,454-610,700-819` |
| L0 BTB entries | `gen_rtl/ifu/rtl/ct_ifu_l0_btb.v:322-390,523-636,686-1287,1330-1343` |
| indirect BTB/RAS | `gen_rtl/ifu/rtl/ct_ifu_ind_btb.v:187-333,355-668`; `ct_ifu_ras.v:835-1497,1810-1919` |
| refill/prefetch/BIU | `gen_rtl/ifu/rtl/ct_ifu_l1_refill.v:268-620`; `ct_ifu_ipb.v:289-520,581-848` |
| IP branch/refill/reissue | `gen_rtl/ifu/rtl/ct_ifu_ipctrl.v:946-980,1230-1453,1905-1994` |
| IP decode/H0/metadata | `gen_rtl/ifu/rtl/ct_ifu_ipdp.v:2128-2339,4831-5884,6118-6872` |
| IB/IBUF/LBUF | `gen_rtl/ifu/rtl/ct_ifu_ibctrl.v:537-980`; `ct_ifu_ibuf.v:1429-1925,9526-9618`; `ct_ifu_lbuf.v:1216-1470,6746-6945` |
| PCFIFO/IU output | `gen_rtl/ifu/rtl/ct_ifu_pcfifo_if.v:293-298,1008-1070` |
| vector/debug | `gen_rtl/ifu/rtl/ct_ifu_vector.v:146-273`; `ct_ifu_debug.v` and `ct_ifu_top.v:4306-4364` |
| cache arrays/macros | `gen_rtl/ifu/rtl/ct_ifu_icache_if.v:248-562`; `ct_ifu_icache_tag_array.v:86-129`; `ct_ifu_icache_data_array0.v:166-343`; `ct_ifu_icache_predecd_array0.v:74-128` |
