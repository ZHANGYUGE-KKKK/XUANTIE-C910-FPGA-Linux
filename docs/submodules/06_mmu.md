# MMU RTL 结构与接口报告

## 1. 范围与结论

本文覆盖 `gen_rtl/mmu/rtl` 下全部 22 个文件，依据实际 `module`、时序/组合逻辑和具名端口连接整理；不修改该目录或其它 RTL。`ct_mmu_top` 是 MMU 的唯一汇聚模块，负责把 IFU、LSU、CP0、BIU、PMP、RTU 和性能计数器接口接入 I-uTLB、D-uTLB、JTLB、PTW、TLB 操作控制、寄存器、仲裁器及 system map。

从源码可以确认的主路径是：

```text
ct_top x_ct_mmu_top
├─ ct_mmu_regs       CP0 TLB/SATP 寄存器、MMU enable、特权属性
├─ ct_mmu_tlboper    TLBP/TLBR/TLBWI/TLBWR/INV* 状态机
├─ ct_mmu_arb        IFU/LSU/PFU/PTW/TLB 操作的共享仲裁和 SRAM 读写选择
├─ ct_mmu_jtlb       共享 4-way JTLB、命中比较、PTW 结果返回、PFU
│  ├─ ct_mmu_jtlb_tag_array ── ct_spsram_256x196
│  └─ ct_mmu_jtlb_data_array ── 2 × ct_spsram_256x84
├─ ct_mmu_ptw        三层页表遍历、PTE 权限/对齐/PMP 检查、JTLB refill
├─ ct_mmu_iutlb      取指 uTLB、refill、32 项 PLRU
│  ├─ ct_mmu_iutlb_fst_entry ×4
│  ├─ ct_mmu_iutlb_entry ×28
│  └─ ct_mmu_iplru
├─ ct_mmu_dutlb      数据 uTLB、双请求端口、refill、17 项 D-PLRU
│  ├─ ct_mmu_dutlb_entry ×16
│  ├─ ct_mmu_dutlb_huge_entry ×1
│  ├─ ct_mmu_dutlb_read ×2
│  └─ ct_mmu_dplru
└─ ct_mmu_sysmap ×5  PA0/PA1/PA2/PA3/PA4 的系统属性查表
```

在 CPU 外层，`ct_core` 真实实例化 `ct_ifu_top`、`ct_lsu_top`、`ct_cp0_top`，位置分别为 `gen_rtl/cpu/rtl/ct_core.v:2480`、`:3985`、`:4488`；`ct_top` 在 `gen_rtl/cpu/rtl/ct_top.v:1320` 实例化 `ct_mmu_top`，并在 `:1476` 实例化 `ct_biu_top`。因此，本报告中的 IFU/LSU/CP0/BIU 端口名均以实际 MMU 顶层连接为准。

## 2. 文件与 module 清单

| 文件 | module | 主要职责与证据 |
|---|---|---|
| `ct_mmu_top.v` | `ct_mmu_top` | MMU 顶层端口、时钟门控、子模块实例和调试汇聚；端口 `:17-242`，实例 `:557-1115`。 |
| `ct_mmu_regs.v` | `ct_mmu_regs` | MIR/MEL/MEH/MCIR/SATP 寄存器，CP0 写入/读出、TLB 命令译码、MMU/特权输出；` :17-120, 229-717`。 |
| `ct_mmu_tlboper.v` | `ct_mmu_tlboper` | TLBP、TLBR、TLBWI、TLBWR，以及按 ASID、全部、VA 的失效操作；` :17-158, 356-1125`。 |
| `ct_mmu_arb.v` | `ct_mmu_arb` | IFU、LSU、PFU、TLB 操作、PTW 的请求优先级，VPN/index/bank、tag/data 选择和 SRAM 写控制；` :17-148, 288-500`。 |
| `ct_mmu_jtlb.v` | `ct_mmu_jtlb` | 共享 JTLB 的 tag/data 读、三级页大小匹配、命中/多命中/缺失、PTW 请求、uTLB refill 和 PFU；` :17-216, 568-1451`。 |
| `ct_mmu_ptw.v` | `ct_mmu_ptw` | 三级页表 PTE 请求、V/R/W/X/U/A/D/SUM/MXR 等检查，PMP/system map 检查，向 JTLB 返回映射；` :17-128, 307-800`。 |
| `ct_mmu_iutlb.v` | `ct_mmu_iutlb` | IFU 侧 32 项 uTLB 的命中、refill、异常、PMP/属性检查和 first-entry 交换；` :17-108, 546-2327`。 |
| `ct_mmu_iutlb_entry.v` | `ct_mmu_iutlb_entry` | 普通 I-uTLB entry 的 VPN/PFN/属性存储、清除和按 4K/2M/1G 匹配；` :17-254`。 |
| `ct_mmu_iutlb_fst_entry.v` | `ct_mmu_iutlb_fst_entry` | I-uTLB first entry 变体，额外支持 VPN 输出及与 secondary entry 的 swap；` :17-72, 120-253`。 |
| `ct_mmu_iplru.v` | `ct_mmu_iplru` | 32 项 I-uTLB 的 invalid-first 选择和 5 层二叉 PLRU；` :17-140, 344-1169`。 |
| `ct_mmu_dutlb.v` | `ct_mmu_dutlb` | LSU 侧 17 项 D-uTLB、两个 VA 请求端口、refill/flush/wakeup、普通项和 huge 项更新；` :17-183, 446-1537`。 |
| `ct_mmu_dutlb_entry.v` | `ct_mmu_dutlb_entry` | D-uTLB 普通 entry 的存储、清除和两个请求端口的完整 VPN 命中；` :17-213`。 |
| `ct_mmu_dutlb_huge_entry.v` | `ct_mmu_dutlb_huge_entry` | D-uTLB huge entry，按高层 VPN 匹配，实例为 entry16；` :17-215`。 |
| `ct_mmu_dutlb_read.v` | `ct_mmu_dutlb_read` | 单个 LSU 请求端口的 D-uTLB 命中选择、权限/异常、属性/PMP 检查和 PA 输出；由 `ct_mmu_dutlb` 实例化两次，逻辑 `:421-776`。 |
| `ct_mmu_dplru.v` | `ct_mmu_dplru` | 16 项普通 D-uTLB 的双读端口命中、invalid-first/PLRU 替换以及双命中更新；` :17-74, 301-933`。 |
| `ct_mmu_jtlb_tag_array.v` | `ct_mmu_jtlb_tag_array` | JTLB tag/fifo 阵列的时钟门控、按 way 写使能和 FPGA SRAM wrapper；` :17-36, 62-125`。 |
| `ct_mmu_jtlb_data_array.v` | `ct_mmu_jtlb_data_array` | JTLB data 阵列的双 bank 时钟/写使能和两个 SRAM wrapper；` :17-40, 73-187`。 |
| `ct_spsram_256x196.v` | `ct_spsram_256x196` | 256 深、196 位单端口 SRAM 的 FPGA wrapper，调用外部 `ct_f_spsram_256x196`；` :17-73`。 |
| `ct_spsram_256x84.v` | `ct_spsram_256x84` | 256 深、84 位单端口 SRAM 的 FPGA wrapper，调用外部 `ct_f_spsram_256x84`；` :17-73`。 |
| `ct_mmu_sysmap.v` | `ct_mmu_sysmap` | 对 PA 页号做 8 段阈值比较并输出 5-bit system-map flag；` :17-26, 75-204`。 |
| `ct_mmu_sysmap_hit.v` | `ct_mmu_sysmap_hit` | 单个阈值的 bottom/upper-bound 比较；` :17-42`。 |
| `sysmap.h` | 无 module | 定义 FPGA 和非 FPGA 分支下的 8 个系统映射阈值/flag 常量；` :2-50`。 |

## 3. `ct_mmu_top` 的真实接口

### 3.1 时钟、复位和配置控制

`ct_mmu_top` 使用 `forever_cpuclk` 作为主时钟、`cpurst_b` 作为低有效复位，`pad_yy_icg_scan_en` 作为扫描门控旁路控制；端口定义见 `ct_mmu_top.v:132-242`。`ct_top` 中这三个连接分别是 `coreclk`、`mmu_rst_b` 和 `pad_yy_icg_scan_en`（`ct_top.v:1337-1338, 1425` 附近）。

`cp0_mmu_icg_en` 参与 `ct_mmu_top` 的 uTLB/JTLB/寄存器等门控时钟。顶层 uTLB 时钟使能还受以下事件影响：复位、TLB 操作清除/INVVA、SATP/MMU 关闭、JTLB 返回 PA、I/D uTLB secondary 更新，见 `ct_mmu_top.v:526-543`。各子模块内部又通过 `gated_clk_cell` 生成局部门控时钟；例如 regs `:243-257`、TLB 操作 `:318-336`、JTLB `:539-551`、I-uTLB `:504-518`、D-uTLB `:461-476`。

### 3.2 IFU 接口

IFU 输入是：

- `ifu_mmu_va[38:0]`、`ifu_mmu_va_vld`：取指虚拟地址及有效；
- `ifu_mmu_abort`：取指请求中止。

输出是：

- `mmu_ifu_pa[27:0]`、`mmu_ifu_pavld`：物理页号/物理地址有效；
- `mmu_ifu_buf`、`mmu_ifu_ca`、`mmu_ifu_sec`：属性结果；
- `mmu_ifu_deny`、`mmu_ifu_pgflt`：访问拒绝和页故障；
- `mmu_hpcp_iutlb_miss`：I-uTLB miss 性能事件。

这些端口在 `ct_mmu_top.v:151-153, 207-218`，实际由 `ct_mmu_iutlb` 连接，实例见 `:557-602`。I-uTLB 在 MMU 关闭或机器态时旁路：PA 直接取 VA 的低物理地址宽度，属性来自 system map/PMA 默认路径，代码证据为 `ct_mmu_iutlb.v:546-614, 2197-2203`。非规范 VA 会置取指页故障，见 `:593-607`。

### 3.3 LSU 接口

LSU 有两个普通地址请求端口和一个 PFU/预取检查端口：

- `lsu_mmu_va0/va1[38:0]`、`lsu_mmu_va0_vld/va1_vld`：两个主请求地址；
- `lsu_mmu_id0/id1[6:0]`、`lsu_mmu_abort0/abort1`：请求 ID 与中止；
- `lsu_mmu_st_inst0/st_inst1`：存储指令标记；
- `lsu_mmu_vabuf0/vabuf1`：buffer 属性输入；
- `lsu_mmu_va2[38:0]`、`lsu_mmu_va2_vld`：PFU/预取检查地址；
- `lsu_mmu_stamo_pa`、`lsu_mmu_stamo_vld`：原子/特殊存储路径；
- `lsu_mmu_data[63:0]`、`lsu_mmu_data_vld`、`lsu_mmu_bus_error`：PTW 返回数据及总线错误；
- `lsu_mmu_tlb_*`：来自 LSU 的按 VA、ASID、全部范围的 TLB 失效请求。

对应端口位于 `ct_mmu_top.v:154-187`。输出包括两个普通端口的 `mmu_lsu_pa0/pa1`、valid、page fault、access fault、cacheability/buffer/share/security/strong-order 属性，以及 PFU 的 `mmu_lsu_pa2`、`mmu_lsu_pa2_vld`、`mmu_lsu_pa2_err`；还包括 `mmu_lsu_tlb_busy`、`mmu_lsu_tlb_wakeup`、`mmu_lsu_tlb_inv_done`、`mmu_lsu_stall*`，见 `ct_mmu_top.v:219-242`。

`ct_mmu_dutlb` 实例化两个 `ct_mmu_dutlb_read`：port0 对应 VA0，按 `!lsu_mmu_st_inst0` 作为普通读属性；port1 对应 VA1，存储/`stamo` 属性单独输入，连接位置见 `ct_mmu_dutlb.v:1246-1502`。D-uTLB miss 时由 `WFG/WFC` 等状态机等待 JTLB/PTW，flush、异常或 abort 会进入中止路径，见 `:578-765`。

### 3.4 CP0、BIU、PMP、RTU 和 HPCP 接口

CP0 控制输入包括：

- `cp0_mmu_wreg/wdata/reg_num`：CP0 写寄存器通道；
- `cp0_mmu_satp_sel`：SATP 写选择；
- `cp0_mmu_cskyee`：命令/特权使能条件；
- `cp0_mmu_mpp/mprv/mxr/sum`：特权和页表访问属性；
- `cp0_mmu_ptw_en`、`cp0_mmu_tlb_all_inv`、`cp0_mmu_no_op_req`；
- `cp0_yy_priv_mode`：当前特权模式。

CP0 输出为 `mmu_cp0_cmplt`、`mmu_cp0_data[63:0]`、`mmu_cp0_satp_data[63:0]`、`mmu_cp0_tlb_done`。regs 的读回 mux 和完成条件见 `ct_mmu_regs.v:659-681`；`ct_top` 的具名连接见 `ct_top.v:1322-1335, 1370-1373`。

BIU 侧输入主要是 `biu_mmu_smp_disable`，PTW 通过 `mmu_lsu_data_req`、`mmu_lsu_data_req_addr[39:0]`、`mmu_lsu_data_req_size` 请求页表 PTE 读取；请求/返回端口在 `ct_mmu_top.v:132-133, 228-230`，PTW 产生逻辑在 `ct_mmu_ptw.v:748-764`。`ct_top` 的 `ct_biu_top` 实例位于 `ct_top.v:1476`，因此 MMU 与外部总线的直接边界是 `ct_top`，不是 `ct_mmu_ptw` 直接连接外部 AXI。

PMP 由 `mmu_pmp_pa0..pa4`、`mmu_pmp_fetch3` 发起物理地址/取指检查，返回 `pmp_mmu_flg0..flg4`；`ct_mmu_top` 端口及五个 system-map 实例的分段连接见 `ct_mmu_top.v:188-205, 1075-1115`。RTU 的 `rtu_yy_xx_flush`、`rtu_mmu_expt_vld`、`rtu_mmu_bad_vpn` 输入参与 refill/PTW abort 和异常同步，端口见 `:177-187`；D-uTLB 的 flush 处理见 `ct_mmu_dutlb.v:587-683`。HPCP 通过 `hpcp_mmu_cnt_en` 使能，输出 I/D/JTLB miss 事件。

## 4. 地址翻译和 refill 数据流

### 4.1 命中路径

1. IFU 将 VA 送入 I-uTLB；LSU 将两个普通 VA 送入 D-uTLB，PFU/VA2 可走 JTLB 的 prefetch 路径。
2. uTLB entry 先按页大小比较 VPN。I-uTLB 普通 entry 的匹配在 `ct_mmu_iutlb_entry.v:229-250`；D-uTLB 普通 entry 是两个请求端口的完整 VPN 比较，见 `ct_mmu_dutlb_entry.v:195-209`；entry16 只比较高层 VPN，见 `ct_mmu_dutlb_huge_entry.v:193-211`。
3. uTLB 命中时以保存的 PFN/属性拼出 PA；未命中则由 `ct_mmu_arb` 发起 JTLB 访问。仲裁优先级和访问类型编码见 `ct_mmu_arb.v:288-319, 472-496`。
4. JTLB 依次尝试 4K、2M、1G 页大小，比较 VPN、ASID 和 G/global 条件；比较与 read FSM 在 `ct_mmu_jtlb.v:710-730, 1026-1123`。
5. JTLB 命中返回 PFN/flags/page-size；JTLB 缺失且允许 PTW 时进入 PTW。PTW 结果返回后同时用于 JTLB refill 和请求端 uTLB refill，返回 mux 见 `ct_mmu_jtlb.v:1184-1187, 1433-1447`。

源码使用 3-bit `pgs` 选择页大小。`ct_mmu_tlboper.v:999-1052` 明确按 `{1G,2M,4K}` 排列选择位；旁路路径的 `3'b001`（I-uTLB，`ct_mmu_iutlb.v:2197-2203`）对应 4K，D-uTLB huge entry 的 `3'b100`（`ct_mmu_dutlb_read.v:659-692`）对应 1G。2M 选择由中间位参与。这里仅记录 RTL 编码，不额外引入规格书名称。

### 4.2 JTLB 阵列和仲裁

JTLB 的 tag 阵列为 256 行、每行 196 bit，数据阵列为两个 256 行、84 bit bank：

- tag 196 bit 包含 4 个 way 的 tag/fifo 信息，`ct_mmu_jtlb.v:568-603`；
- tag wrapper 选择 `ct_spsram_256x196`，`ct_mmu_jtlb_tag_array.v:116-125`；
- 两个 data bank 各为 84 bit，即各包含 2 个 42-bit way，两个 bank 合计 4 个 way；两个 bank 分别实例化 `ct_spsram_256x84`，`ct_mmu_jtlb_data_array.v:157-187`；
- index 为 8 bit，读写使能、way/ bank 选择由 `ct_mmu_arb` 和 JTLB 共同产生。

`ct_mmu_jtlb.v:938-1024` 将阵列数据拆成 tag、fifo 和 PTE data；`ct_mmu_arb.v:429-461` 负责 index、VPN、bank、写入和 refill fifo。JTLB 中 parity-fail 当前在 `ct_mmu_jtlb.v:786` 处硬连为 0，未见实际 parity 注入/校验逻辑。

### 4.3 PTW

PTW 的参数明确给出 `VADDR_WIDTH=39`、`PADDR_WIDTH=40`、`VPN_WIDTH=27`、`PPN_WIDTH=28`、`PTE_LEVEL=3`、每级 `VPN_PERLEL=9`、PTE flag 14 bit、ASID 16 bit，见 `ct_mmu_ptw.v:250-264`。

三次 PTE 地址形成分别是：

```text
level 2: {satp_ppn, vpn[26:18], 3'b0}
level 1: {level2_PPN, vpn[17:9], 3'b0}
level 0: {level1_PPN, vpn[8:0], 3'b0}
```

对应 RTL 为 `ct_mmu_ptw.v:625-636`。每次读取使用 8-byte PTE，地址请求由 `:595-611` 和 `:760-764` 产生，返回数据由 LSU/BIU 侧 `lsu_mmu_data`、`lsu_mmu_data_vld` 提供。

PTW 会检查：V 位；W=1 且 R=0；R/W/X 权限；U/S 与 SUM；A/D；大页的低位 PPN 对齐；叶子 PTE/非叶子 PTE 的层级约束；以及 PMP/system map。具体条件见 `ct_mmu_ptw.v:638-698`。取指使用 X 位，load 使用 R 位，store 使用 W 位，prefetch 使用 R 位，PMP 拒绝位的选择见 `:644-653`。发生访问/页故障时，PTW 仍通过 `:700-724` 组织完成和 fault 返回；无故障且数据有效、仲裁允许时完成 JTLB refill。

PTW 返回的 flags 受 `cp0_mmu_maee` 选择影响：使能时取 `lsu_data_flop[63:59]`，否则取 `sysmap_mmu_flg3`，见 `ct_mmu_ptw.v:700-724`。该信号的更高层语义不在本目录定义。

### 4.4 PA、system map 和 PMP

翻译完成后，JTLB/uTLB/D-uTLB 产生物理页号和页大小，再由 `ct_mmu_sysmap` 对 PA 页号进行 8 个阈值比较。`ct_mmu_sysmap_hit.v:39-42` 定义单段的 bottom/upper-bound hit；`ct_mmu_sysmap.v:154-204` 链接上下界、生成 one-hot hit，并选择 5-bit flag。

`sysmap.h:2-50` 中 FPGA 与非 FPGA 两个分支目前使用相同常量：

| 段 | PA 页号上界 | flag |
|---|---:|---:|
| 0 | `28'h001000` | `5'b01111` |
| 1 | `28'h002000` | `5'b10000` |
| 2 | `28'h0d0000` | `5'b10000` |
| 3 | `28'h0effff` | `5'b01101` |
| 4 | `28'h0fffff` | `5'b01111` |
| 5 | `28'h4000000` | `5'b01111` |
| 6 | `28'h5000000` | `5'b10000` |
| 7 | `28'hfffffff` | `5'b01111` |

`ct_mmu_top.v:1075-1115` 分别对 PA0/PA1/PA2/PA3/PA4 生成 system-map 命中和属性，PMP 结果再与各路径的访问类型合并。具体 cacheability、buffer、share、strong-order、安全等输出的组合路径分别在 `ct_mmu_iutlb.v:578-614`、`ct_mmu_dutlb_read.v:452-500`、`ct_mmu_jtlb.v:1355-1431`。

## 5. uTLB 组织、容量和替换

### 5.1 I-uTLB

`ct_mmu_iutlb.v` 实例化总计 32 个 entry：位置 0、8、16、24 使用 `ct_mmu_iutlb_fst_entry`，其余 28 个位置使用 `ct_mmu_iutlb_entry`，实例展开从 `:895` 开始，first/secondary 切换逻辑见 `:1893-2003`。first entry 优先命中；仅 secondary 命中时产生 swap，使高频命中项进入 first 位置，命中向量和输出选择见 `:2013-2153`。

I-uTLB entry 不保存 ASID，使用当前 SATP/上下文的匹配方式；entry 字段和清除条件注释/逻辑在 `ct_mmu_iutlb_entry.v:127-172`。SATP 写、TLB 操作清除和 INVVA 对应 VPN 低字节匹配会清除 entry。`ct_mmu_iplru` 管理 32 项替换：优先选 invalid entry，否则使用 5 层二叉 PLRU，`ct_mmu_iplru.v:344-506, 509-531, 1132-1169`。

I-uTLB refill FSM 有 IDLE、等待 grant、等待完成、页故障、访问故障和 abort 状态，见 `ct_mmu_iutlb.v:761-842`。JTLB refill 后，I-uTLB 接收 VPN/PFN/flags/pgs，普通页和大页的低 VPN 部分会按页大小选择；具体更新与 first-entry 轮换见 `:1893-2188`。

### 5.2 D-uTLB

`ct_mmu_dutlb.v` 的组织是 16 个普通 entry 加 1 个 huge entry16，总计 17 项，实例位置为普通 entry 展开区域和 `ct_mmu_dutlb_huge_entry`（`ct_mmu_dutlb.v:810` 起及 `:1210-1232`）。`ct_mmu_dplru` 仅管理 16 个普通项；huge entry 有单独路径。D-PLRU 支持两个同时读端口的命中向量和更新，`ct_mmu_dplru.v:301-447, 469-474, 476-933`。

普通 D-uTLB entry 保存 VPN、PFN、PMA/权限属性及有效位；两个读端口各自比较完整 VPN。huge entry 只比较高层 VPN，适配 1G 映射。`ct_mmu_dutlb_read.v:553-692` 将普通 entry 命中、huge entry 命中、旁路路径和 stamo 特殊路径合并成 PA/属性。

D-uTLB refill 记录 VA、请求 ID、读写类型及 page size；两个 `ct_mmu_dutlb_read` 端口的异常分别输出到 `mmu_lsu_*0/1`。RTU flush、请求 abort、JTLB page/access fault 会终止或转换 refill 状态，完成后产生 `mmu_lsu_tlb_wakeup[11:0]`，见 `ct_mmu_dutlb.v:493-499, 587-802`。

## 6. MMU enable、特权、权限和异常

### 6.1 MMU enable 和特权

`ct_mmu_regs.v:621-717` 给出 SATP 和状态输出：

- SATP mode 只接受写数据 `[62:60] == 0` 的形式，并输出 `{wdata[63], 3'b0}` 作为内部 mode；ASID 使用 `[59:44]`，PPN 使用 `[27:0]`；
- `regs_mmu_en` 在内部 mode 为 `4'b1000` 时有效（`:700`）；
- LSU MMU 仅在 mode 有效且有效特权不是 M 时启用（`:702-705`）；
- 全局 MMU enable 由当前特权模式不是 M 决定（`:706-707`）；
- PTW 获得 SATP PPN/ASID，JTLB 获得当前 ASID（`:708-717`）。

因此，代码明确支持 M 态旁路和 S/U 态分页访问；MPRV、MPP、SUM、MXR 等输入会传入 PTW/JTLB/uTLB 的访问类型检查。对于 `cp0_mmu_mprv` 的高层 CSR 更新规则，本目录只展示消费端逻辑，CP0 产生端在 `gen_rtl/cp0`。

### 6.2 PTE 权限和异常

PTW 与 JTLB/PFU 的 fault 逻辑共同覆盖：

- PTE V 无效；
- W=1/R=0 的非法权限组合；
- fetch/load/store 对应 X/R/W 不满足；
- U/S、SUM、MXR 特权规则；
- A 位缺失，store 的 D 位缺失；
- 1G/2M 页的 PPN 对齐；
- 非叶子/叶子层级不匹配；
- system map/PMP 拒绝；
- VA 非规范。

PTW 的页故障条件见 `ct_mmu_ptw.v:656-687`，JTLB/PFU 的 PTE/属性 fault 合并见 `ct_mmu_jtlb.v:1355-1373`，I-uTLB 与 D-uTLB 对外输出 fault 分别见 `ct_mmu_iutlb.v:593-614` 和 `ct_mmu_dutlb_read.v:472-500`。异常输出仍需由 `ct_core`/RTU 解释；MMU 本身输出 fault/deny/PA valid，不在此目录内完成退休。

## 7. TLB 操作、寄存器和同步/失效

### 7.1 CP0 TLB 寄存器

`ct_mmu_regs.v:272-487` 实现 MIR、MEL、MEH，` :500-619` 实现 MCIR，` :621-653` 实现 SATP。

- MIR：保存 TLBP probe 失败、fatal 和 index 等结果；TLBP 完成时更新，见 `:290-340`。
- MEL：保存/读回 PTE 的 PMA、PPN、RSW、D/A/G/U/X/W/R/V 等字段；写入和 TLBR 装载见 `:343-446`。
- MEH：保存 VPN/ASID 等高半部信息；写入、异常和 TLBR 装载见 `:458-487`。
- MCIR 命令：bit26 区分 INVALL/INVASID 选择，bit27 为 INVASID，bit31 为 TLBP，bit29 为 TLBWI，bit28 为 TLBWR，bit30 为 TLBR；命令均受 `cp0_mmu_cskyee` 和译码优先级限制，见 `:500-520`。

### 7.2 TLB 操作状态机

`ct_mmu_tlboper.v` 为四类 CP0 操作分别提供状态机：TLBP `:356-410`、TLBR `:416-468`、TLBWI `:476-528`、TLBWR `:537-600`。LSU 侧的 INVASID、INVALL、INVVA 分别在 `:619-704`、`:711-765`、`:772-936`；INVVA 会依次尝试 4K、2M、1G 页大小。

失效操作使用计数器扫描 JTLB 项：ALL 计数器初值为源码字面量 `11'b00011111111`，ASID 扫描初值为 `10'b1111111111`，递减到 0 结束，见 `ct_mmu_tlboper.v:945-964`。JTLB 操作通过 arb 访问 tag/data 阵列，命中后按 G/global 或 ASID 条件清除。操作完成、CP0 done、uTLB clear/inv_va、PTW abort 等同步输出见 `:967-1125`。

### 7.3 清除和 flush

- SATP 写会产生 `regs_utlb_clr`，`ct_mmu_regs.v:238-239`；
- TLB 操作完成或 INVVA 会触发 I/D uTLB 清除/失效；
- I-uTLB entry 与 D-uTLB entry 都在本地判断 clear、INVVA VPN 匹配和 entry 写入；
- `rtu_yy_xx_flush` 会使 D-uTLB refill 进入 abort/重新等待路径，PTW 也有 abort state；
- TLB busy/wakeup/done 和 CP0 complete 通过 `ct_mmu_top` 回到 LSU/CP0，避免操作期间把半完成的 refill 当成可用翻译。

## 8. SRAM wrapper 与未确认边界

`ct_spsram_256x196.v` 和 `ct_spsram_256x84.v` 只提供 FPGA 行为封装，分别在 `:65-73` 实例化外部 `ct_f_spsram_256x196` 和 `ct_f_spsram_256x84`。文件中的 TSMC SRAM 版本为注释/替代实现，不在本目录内实际实例化。因而可以确认阵列深度/宽度和端口连接，但不能仅凭本目录确认外部 SRAM 宏的综合、读延迟或初始化语义。

以下内容在当前源码中没有足够证据，应视为未确认项：

1. `sysmap.h` 的 5-bit flag 只有常量值；本目录没有完整的命名位定义，不能仅据 `01111/10000/01101` 给每一位强行命名。
2. `PA_WIDTH`、全局 `VADDR_WIDTH` 以及部分产品配置宏的最终来源在 `gen_rtl/mmu/rtl` 外；本报告使用 MMU 内部端口和参数实际出现的 39-bit VA、40-bit PA、27-bit VPN、28-bit PPN。
3. JTLB parity-fail 在 `ct_mmu_jtlb.v:786` 被硬连为 0；当前目录没有可验证的 parity 生成、注入或纠错路径。
4. `ct_mmu_iutlb.v:1951` 附近保留 “Page Mask?” 的 TODO 注释；不能据此推断额外的页掩码功能已经存在。
5. `cp0_mmu_maee`、PMP flag 的最终 CSR 语义和 BIU 对 PTW 请求的实际总线响应协议分别由 `gen_rtl/cp0`、`gen_rtl/pmp`、`gen_rtl/biu` 决定；本报告只记录 MMU 的消费/连接逻辑。

## 9. 证据索引

| 主题 | 主要证据 |
|---|---|
| 顶层端口和子模块层次 | `gen_rtl/mmu/rtl/ct_mmu_top.v:17-242, 557-1115` |
| CPU 侧真实实例 | `gen_rtl/cpu/rtl/ct_top.v:1320-1428, 1476`；`gen_rtl/cpu/rtl/ct_core.v:2480, 3985, 4488` |
| SATP/MMU enable/CP0 寄存器 | `gen_rtl/mmu/rtl/ct_mmu_regs.v:229-239, 272-717` |
| TLB 命令与失效 | `gen_rtl/mmu/rtl/ct_mmu_tlboper.v:356-1125` |
| 仲裁、访问类型、SRAM 控制 | `gen_rtl/mmu/rtl/ct_mmu_arb.v:288-500` |
| JTLB match/refill/PFU | `gen_rtl/mmu/rtl/ct_mmu_jtlb.v:568-730, 1026-1451` |
| PTW 地址与页故障 | `gen_rtl/mmu/rtl/ct_mmu_ptw.v:307-724` |
| I-uTLB/PLRU | `gen_rtl/mmu/rtl/ct_mmu_iutlb.v:546-2327`；`ct_mmu_iplru.v:344-1169` |
| D-uTLB/PLRU | `gen_rtl/mmu/rtl/ct_mmu_dutlb.v:493-1537`；`ct_mmu_dplru.v:301-933` |
| System map 常量和比较 | `gen_rtl/mmu/rtl/sysmap.h:2-50`；`ct_mmu_sysmap.v:75-204`；`ct_mmu_sysmap_hit.v:39-42` |
| JTLB SRAM wrapper | `ct_mmu_jtlb_tag_array.v:62-125`；`ct_mmu_jtlb_data_array.v:73-187`；`ct_spsram_256x196.v:17-73`；`ct_spsram_256x84.v:17-73` |
