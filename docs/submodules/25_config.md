# 工程级配置与文件组织报告

## 1. 范围与结论

本报告只新增本文件，核对对象为 `gen_rtl/filelists/C910_asic_rtl.fl`、`gen_rtl/cpu/rtl/cpu_cfig.h`、`gen_rtl/mmu/rtl/sysmap.h`、`gen_rtl/.vscode` 以及根目录和各目录中可见的构建线索。没有修改既有 RTL 或其他报告。

当前树是一个以 Verilog-2001 RTL 为主的 C910 工程快照。`C910_asic_rtl.fl` 虽名为 ASIC，但头文件在第 62 行定义了 `FPGA`；当前 RAM wrapper 链路因此是 FPGA 行为模型链路。工程没有提交 Vivado 工程、约束、综合/实现脚本或 ASIC SRAM macro model，不能仅凭现有文件完成可复现的 ASIC 或 FPGA bitstream 构建。

filelist 与实际文件的静态核对结果：

- filelist 共 486 行，其中第 486 行为空；有效路径条目为 485 个。
- 条目包含 483 个 `.v`、2 个头文件：`cpu_cfig.h` 和 `sysmap.h`。
- `gen_rtl` 下 483 个 `.v` 与这 2 个头文件均被收录，路径均存在、无重复条目。
- 除 filelist 自身外，没有发现 `gen_rtl` 下遗漏的 RTL/配置文件；filelist 自身当然不是自己的条目。
- 未发现 filelist 中的 `-f` 嵌套、`+define+`、include 路径、top 指定或约束引用；这些均由外部工具工程负责。

## 2. 工程目录层级与文件清单

根目录当前可见内容如下：

```text
C910_LEARN/
├─ docs/submodules/
│  ├─ 01_cpu.md                         已有 CPU 外层报告
│  └─ 25_config.md                      本报告
├─ gen_rtl/
│  ├─ .vscode/                          目录存在，但为空
│  ├─ filelists/C910_asic_rtl.fl        唯一 filelist
│  ├─ cpu/rtl/                           8 个 .v + cpu_cfig.h
│  ├─ mmu/rtl/                           21 个 .v + sysmap.h
│  └─ 其余 RTL 子目录                    共 483 个 .v
└─ Temp/
   ├─ scan_rtl.ps1                      已有模块扫描脚本，非构建脚本
   └─ module_scan.txt                   已有扫描结果
```

`gen_rtl` 的实际 `.v` 数量按目录如下；这些目录中的文件均在 filelist 中出现：

| 目录 | `.v` 数量 | 配置/备注 |
|---|---:|---|
| `biu` | 8 | core 内部总线 |
| `ciu` | 37 | 系统/外部总线及 APB 汇聚 |
| `clint` | 2 | CLINT |
| `clk` | 3 | 单核/多核时钟及门控 |
| `common` | 7 | Booth、压缩器、同步器、BUFGCE |
| `cp0` | 4 | CP0 |
| `cpu` | 8 | `openC910`、`ct_top`、`ct_core`、SysIO、golden port |
| `fpga` | 42 | `ct_f_spsram_*` 与 `fpga_ram` |
| `had` | 22 | 调试/HAD |
| `idu` | 57 | 译码、发射、寄存器文件 |
| `ifu` | 50 | 取指、I-cache、预测、取指 RAM wrapper |
| `iu` | 14 | 整数执行、乘除法 |
| `l2c` | 33 | L2 逻辑及 L2 SRAM wrapper |
| `lsu` | 70 | LSU、D-cache、LSU SRAM wrapper |
| `mmu` | 21 | MMU、TLB、MMU SRAM wrapper |
| `plic` | 11 | PLIC |
| `pmp` | 4 | PMP |
| `pmu` | 6 | HPCP/性能计数 |
| `rst` | 2 | 单核/多核复位 |
| `rtu` | 22 | ROB、提交、退休 |
| `vfalu` | 32 | 标量/向量浮点 ALU |
| `vfdsu` | 12 | 向量浮点除法/开方 |
| `vfmau` | 11 | 向量浮点乘加 |
| `vfpu` | 5 | 向量/浮点顶层 |
| 合计 | **483** | 另有两个 `.h` 和一个 `.fl` |

## 3. `C910_asic_rtl.fl` 的规则、路径和顺序

### 3.1 路径规则

每条路径均采用 `${CODE_BASE_PATH}/gen_rtl/...`（`C910_asic_rtl.fl:1-485`）。因此外部工具必须先定义 `CODE_BASE_PATH`，并使其指向工程根目录 `C910_LEARN`；当前树的第一条实际路径应展开为 `D:/Xilinx_FPGA/C910_LEARN/gen_rtl/cpu/rtl/cpu_cfig.h`。filelist 本身没有定义该变量，也没有记录路径分隔符、工具或工作目录约定。

头文件位于最前两项：

- `C910_asic_rtl.fl:1`：`cpu_cfig.h`
- `C910_asic_rtl.fl:2`：`sysmap.h`

这是有意义的配置顺序，但 Verilog 预处理是否把“头文件作为源文件编译”与 `` `include `` 搜索路径等价，仍取决于具体工具。`gen_rtl/common/rtl/booth_code.v:16-17` 明确使用 `` `include "cpu_cfig.h" `` 和 `` `include "sysmap.h" ``，所以编译命令至少应验证两个头文件目录可被 include 搜索到。两个头文件都未见 include guard。

### 3.2 文件分组与编译顺序

filelist 是生成器式的分组清单，不是严格的模块拓扑排序。主要区段如下：

| 行号 | 内容 |
|---:|---|
| 1-53 | 配置、common、PLIC 辅助、BIU、CIU、CLINT、时钟、CPU core、CP0、CIU EBIU |
| 54-94 | 42 个 FPGA SRAM wrapper |
| 95-123 | VFALU/FSPU |
| 124-151 | HAD 与 PMU |
| 152-208 | IDU |
| 209-261 | IFU 与 IU |
| 262-334 | L2C 与 LSU 逻辑 |
| 335-391 | MMU、multi-clock/reset、`openC910`、CIU 外设、PMP、RMU、RTU |
| 392-433 | 各目录的通用 `ct_spsram_*` wrapper |
| 434-436 | CPU SysIO 与 `ct_top` |
| 437-468 | VFALU pipeline、VFDSU、VFMAU、VFPU |
| 469-485 | `fpga_ram`、门控时钟、multi/single golden port、乘法器、PLIC、同步器 |

Verilog module 定义可后于实例化文件出现，工具通常在 elaboration 阶段解析；但本清单没有声明这一点。因此必须用目标 simulator/Verilog 选项实测，而不能把该顺序当作所有工具都接受的保证。尤其要验证：

- `gen_rtl/l2c/rtl/ct_spsram_*` 等通用 wrapper（filelist `392-433`）实例化的 `ct_f_spsram_*` 是否都能解析到 `gen_rtl/fpga/rtl`（`54-94`）。
- `ct_f_spsram_*` 对 `fpga_ram` 的引用能否解析到 filelist `469`。
- `openC910.v` 在 `356`，PLIC 实现主要在 `473-482`；这是合法的模块定义顺序问题，不是缺文件证据。

### 3.3 顶层选择

filelist 没有 top 选择。当前存在多个候选 module：

- `openC910`：定义于 `gen_rtl/cpu/rtl/openC910.v:32`，在 `openC910.v:695` 实例化 `ct_top x_ct_top_0`。
- `ct_top`：定义于 `gen_rtl/cpu/rtl/ct_top.v:20`，在 `ct_top.v:849` 实例化 `ct_core`。
- `top_golden_port`：定义于 `top_golden_port.v:15`，是接口镜像/比较端口，不是功能顶层。
- `mp_top_golden_port`：定义于 `mp_top_golden_port.v:15`，同样是多核比较端口镜像。

当前配置下 `openC910` 是最合理的系统级 top 候选，但仓库内没有 Vivado/simulator 工程证明最终 top。若目标是单核 CPU 外部接口，应显式选择 `openC910`；若只做单个 core 级验证，才选择 `ct_top`。golden port 文件不应被误选为功能 top。

`cpu_cfig.h:238-248` 定义/注释了单核选择，`openC910.v:827-829` 进一步明确 core1 的 `ct_top` 未实例化；相关 core1 信号之后被 tie-off。因此文件里仍有多核时钟、复位、SysIO 和 golden port 端口，不等于当前激活了多核数据路径。

## 4. `cpu_cfig.h` 当前配置与影响

### 4.1 当前有效配置

下表只列当前文件中直接定义或由当前条件派生的有效宏；未把仅出现在 `ifdef` 分支中的备选项算作有效配置。

| 类别 | 有效宏/值 | 证据与影响 |
|---|---|---|
| 版本 | `YEAR1=2`、`YEAR0=1`、`MONTH=A`、`REVISION=1`、`SUB_VERSION=4`、`PATCH=3`、`PRODUCT_ID=0` | `cpu_cfig.h:43-57`，产品/版本标识 |
| FPGA/DFT | `FPGA`、`SCAN_CHAIN_8`、`SMBIST`、`DFT_AT_SPEED` | `62`、`125`、`132`、`138`；改变 RAM/DFT/scan 相关条件路径 |
| TLB/预测 | `JTLB_ENTRY_1024`、`JTLB_ADDR_WIDTH=8`、`BTB`、`BTB_1024`、`IBP`、`IBP_PRO`、`LBUF` | `153`、`171-192`、`323-325`；激活 1024-entry JTLB、BTB/IBP/LBUF |
| L1 cache | `ICACHE_64K`、`DCACHE_64K` | `198`、`203`；IFU/LSU 中选择 64 KiB 分支 |
| L2 cache | `L2_CACHE_16WAY`、`L2_CACHE_1M` | `214`、`219`；选择 16-way、1 MiB 的 tag/data/dirty RAM |
| 单核 | `PROCESSOR_0`；`PLIC_HART_NUM=1` | `238`、`423-437`；当前只有 hart0 的有效 core 实例 |
| PLIC | `PLIC`、`PLIC_INT_NUM=144`、`PLIC_ID_NUM=10`、`PLIC_PRIO_BIT=5`、`MAX_HART_NUM=32` | `253-262`；`openC910.v:1533-1537` 传给 `plic_top`，其中 `INT_NUM` 还加 16 |
| PMP | `PMP`、派生 `PMP_REGION_8` | `159-162`、`272`；启用 8-region PMP 分支 |
| HPCP | `HPCP`、`HPCP_CNT_NUM_16`、group0/1/2 | `282-304`；启用 16 计数器配置 |
| 数据宽度 | `FPR_WIDTH=63`、`VEC_WIDTH=63`、`PA_WIDTH=40`、`VA_WIDTH=39` | `317-318`、`462-463`；浮点/向量数据宽度为 64 bit 编码，物理/虚拟地址分别 40/39 bit |
| LSU 队列 | `SAB_DEPTH=24`、`SAB_RDEPTH=16`、`SAB_WDEPTH=8` | `469-471` |

### 4.2 备选和未激活配置

- `MULTI_PROCESSING` 在 `cpu_cfig.h:241` 被注释，`PROCESSOR_1` 在 `244` 也被注释；`PROCESSOR_2/3` 只有条件分支，没有当前定义。
- `JTLB_ENTRY_2048` 只有 `326-328` 的备选分支，当前未激活。
- L2 的 `8WAY` 和 `128K/256K/512K/2M/4M/8M` 分支在 `333-419` 仍保留，但当前只有 `16WAY + 1M` 命中 `396-400`；其有效派生值为 `L2C_TAG_INDEX_WIDTH=9`、`L2C_TAG_DATA_WIDTH=24`、`L2C_DATA_INDEX_WIDTH=13`。
- IFU 中还存在 `ICACHE_32K/128K/256K` 分支，LSU 中还存在 `DCACHE_32K` 分支；当前由 `64K` 定义选择 64 KiB 路径。
- `LSU_SHAREABLE` 仅在 `PROCESSOR_1`（`442-444`）时定义，当前单核不应有效。
- RTL 中可见 `PLIC_SEC`、`MEM_CFG_IN`、`L1_CACHE_ECC` 等条件名，但 `cpu_cfig.h` 没有定义它们；若外部工具没有额外 `+define+`，这些条件分支应视为关闭，仍需以预处理结果验证。
- 没有发现名为 `ASIC` 或 `SRAM` 的全局选择宏。当前变体由 `FPGA` 及工具/宏外部设置共同决定。

## 5. FPGA、ASIC 与 SRAM wrapper 变体

当前 wrapper 链路为：

```text
ct_l2cache/IFU/LSU/MMU 逻辑
        │ 实例化 ct_spsram_*（l2c/ifu/lsu/mmu）
        ▼
ct_spsram_* wrapper
        │ 当前源码直接实例化 ct_f_spsram_*（例如 l2c/rtl/ct_spsram_8192x128.v:60-72）
        ▼
ct_f_spsram_*（filelist:54-94）
        │ 使用 fpga_ram（例如 fpga/rtl/ct_f_spsram_8192x32.v:16, 110-132）
        ▼
fpga_ram（filelist:469）
```

证据表明：

- `gen_rtl/l2c/rtl/ct_spsram_8192x128.v:60-72` 的“FPGA memory”实例有效，TSMC 实例仅为注释（`74`）。同样模式存在于 `mmu/rtl/ct_spsram_256x196.v:61-68` 和 `lsu/rtl/ct_spsram_1024x32.v:60-73` 等 wrapper。
- `gen_rtl/fpga/rtl/fpga_ram.v:15-50` 是行为 RAM，使用 Verilog `reg` 数组和单时钟读写；它不是 Xilinx Block RAM 原语，也不是 ASIC SRAM macro。
- `cpu_cfig.h:62` 定义 `FPGA`；`l2c/rtl/ct_l2cache_data_array.v:69-87` 在大容量 L2 分支中用 `` `ifndef FPGA `` 包住 scan 端口，说明该宏会改变 SRAM 端口形态。
- `sysmap.h` 虽有 FPGA/非 FPGA 两个分支，但当前两支内容完全相同，见本报告第 6 节；不能据此认为 ASIC map 已被独立验证。

所以当前 filelist 可以支持“RTL + FPGA 行为 RAM”方向的仿真输入集合，但没有证据支持真实 ASIC SRAM 替换，也没有证据说明某个 FPGA wrapper 已映射到特定 Xilinx primitive。若目标是 ASIC，至少需要外部 SRAM macro/model、wrapper 替换策略、DFT/scan 约束和 ASIC 编译选项；若目标是 FPGA，仍需目标器件、时钟/引脚约束和实现脚本。

## 6. `sysmap.h` 地址映射

`gen_rtl/mmu/rtl/sysmap.h` 在 `2-25` 为 `FPGA` 分支，在 `26-50` 为非 FPGA 分支。两支定义完全相同：

| index | `SYSMAP_BASE_ADDR` | `SYSMAP_FLG` |
|---:|---:|---|
| 0 | `28'h01000` | `5'b01111` |
| 1 | `28'h02000` | `5'b10000` |
| 2 | `28'hd0000` | `5'b10000` |
| 3 | `28'heffff` | `5'b01101` |
| 4 | `28'hfffff` | `5'b01111` |
| 5 | `28'h4000000` | `5'b01111` |
| 6 | `28'h5000000` | `5'b10000` |
| 7 | `28'hfffffff` | `5'b01111` |

`ct_mmu_sysmap.v:173-180` 按 hit index 选择 `SYSMAP_FLG0..7`；`ct_mmu_top.v:1074-1114` 实例化 5 个 sysmap 比较器并连接 PA/flag/hit。可验证注意事项：

- 这些是 28-bit 宏值，实际用途是 MMU sysmap/PPN 比较输入，不应未经确认直接当作完整字节地址。
- 修改 FPGA map 时必须同步检查 `else` 分支；当前两支相同意味着任何平台差异尚未在此文件体现。
- `sysmap.h` 与 `cpu_cfig.h` 都没有 include guard；依赖工具的 include/编译策略应单独验证。

## 7. 可验证的构建与配置注意事项

1. **先展开变量并检查路径。** 用工程根目录作为 `CODE_BASE_PATH`，逐行展开 filelist；期望得到 485 个存在文件、0 个缺失、0 个重复。
2. **明确 include 搜索目录。** 至少加入 `gen_rtl/cpu/rtl` 和 `gen_rtl/mmu/rtl`，因为 `booth_code.v:16-17` 使用了无目录的 include 名称。
3. **显式选择 top。** 系统级验证优先尝试 `openC910`；不要将 `top_golden_port` 或 `mp_top_golden_port` 误作为功能 top。若工具需要库解析，确认 `ct_top`、`ct_core`、PLIC、时钟/复位和 SRAM wrapper 都在同一编译集合。
4. **避免宏冲突。** `cpu_cfig.h` 已直接定义 `FPGA`、单核、cache/L2/PMP/PLIC/HPCP 选择；外部 `+define+` 若覆盖这些宏，会改变端口和 RAM 实例，必须把最终预处理宏列表保存为构建证据。
5. **验证单核边界。** 期望 `openC910.v:695-805` 只有 `x_ct_top_0`，`827-829` 明确 core1 未实例化，后续 core1 通道是 tie-off；同时检查 `PLIC_HART_NUM=1` 与 `openC910.v:1533-1537` 的参数一致。
6. **验证 cache/RAM 选择。** 当前应命中 IFU/LSU 的 64K 分支、L2 16-way + 1M 分支，并实例化 `ct_spsram_8192x128` 等对应深度 wrapper；不应因为所有尺寸文件都在 filelist 中就认为所有尺寸同时生效。
7. **区分仿真和实现。** `fpga_ram.v` 是行为模型；没有 `.xdc`、器件 part、时钟约束、引脚约束或 Vivado Tcl，不能把当前源码集合称为可生成 bitstream 的 FPGA 工程。
8. **检查头文件重复定义。** filelist 将两个 `.h` 作为前两项，同时 RTL 又有 `` `include ``；应使用目标工具做一次最小预处理/编译，确认重复 `define` 仅产生可接受 warning，而非错误。
9. **不要依赖 `&Depend` 注释自动生成。** `openC910.v:16-30`、`ct_top.v:16-17`、`ct_core.v:16-17` 的 `&Depend` 是生成器风格注释；本快照没有对应生成脚本或 `.vp`/模板文件，真正输入应以当前 `.v` 和 filelist 为准。

## 8. 已发现的工具、约束和外部依赖缺口

当前目录未发现：

- Vivado `.xpr`、`.xci`、`.bd`、`.xdc`、器件/板卡配置；
- Vivado Tcl、Makefile、Ninja/CMake、仿真启动脚本或 simulator 工程文件；
- SDC/UPF/CPF、ASIC 工艺库、标准单元库、SRAM macro/model、TSMC wrapper；
- 独立的 include/define 配置文件、顶层选择文件、综合/实现阶段的 black-box 绑定；
- 可用于生成 `top_golden_port.v`/`mp_top_golden_port.v` 的 `.vp` 或完整生成器工程。

`gen_rtl/.vscode` 目录存在但为空；没有 `settings.json`、`tasks.json`、`launch.json` 或 file association 可供推断工具链。根目录没有 README 或构建入口。`Temp/scan_rtl.ps1` 与 `Temp/module_scan.txt` 只是已有的模块定义/实例扫描辅助物，不构成可复现构建流程。

## 9. 证据索引

| 结论 | 证据 |
|---|---|
| filelist 变量、条目范围、头文件优先 | `gen_rtl/filelists/C910_asic_rtl.fl:1-2, 485-486` |
| FPGA、单核、cache、PLIC、PMP、HPCP 配置 | `gen_rtl/cpu/rtl/cpu_cfig.h:62, 125-219, 238-304` |
| TLB/L2 派生宽度、hart 数、地址宽度 | `gen_rtl/cpu/rtl/cpu_cfig.h:323-437, 462-471` |
| FPGA/非 FPGA sysmap 两支 | `gen_rtl/mmu/rtl/sysmap.h:2-50` |
| sysmap flag 使用 | `gen_rtl/mmu/rtl/ct_mmu_sysmap.v:164-203` |
| 系统 top 与单核 core0/core1 选择 | `gen_rtl/cpu/rtl/openC910.v:32, 695-805, 827-829` |
| `ct_top`/`ct_core` 层级 | `gen_rtl/cpu/rtl/ct_top.v:20, 849`; `gen_rtl/cpu/rtl/ct_core.v:20` |
| golden port 仅为接口镜像候选 | `gen_rtl/cpu/rtl/top_golden_port.v:15`; `mp_top_golden_port.v:15` |
| 配置头文件 include 方式 | `gen_rtl/common/rtl/booth_code.v:16-17` |
| FPGA RAM 行为模型 | `gen_rtl/fpga/rtl/fpga_ram.v:15-50` |
| 通用 SRAM wrapper 到 FPGA wrapper | `gen_rtl/l2c/rtl/ct_spsram_8192x128.v:60-77`; `gen_rtl/fpga/rtl/ct_f_spsram_8192x32.v:16, 110-132` |
| FPGA 宏改变 L2 RAM scan 端口 | `gen_rtl/l2c/rtl/ct_l2cache_data_array.v:69-87` |
| 现有辅助扫描线索 | `Temp/scan_rtl.ps1`; `Temp/module_scan.txt` |

