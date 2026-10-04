# FPGA SRAM 替代层 RTL 报告

## 1. 范围与结论

本文只覆盖 `gen_rtl/fpga/rtl`：1 个通用 RAM 模型 `fpga_ram.v` 和 41 个 `ct_f_spsram_*` wrapper。结论如下：

1. `fpga_ram` 是可综合的单端口、同步读写行为模型，不是 Xilinx/Intel 专用 primitive，也不是 ASIC SRAM macro。它用 `reg mem` 描述存储阵列，并用 `syn_ramstyle = "no_rw_check"` 提示综合工具推断 RAM。
2. `ct_f_spsram_*` 保持 ASIC SRAM wrapper 的统一端口 `A/CEN/CLK/D/GWEN/Q/WEN`，内部把目标深度和位宽拆成一个或多个 `fpga_ram`。这些模块是 FPGA/RTL 仿真替代实现。
3. `gen_rtl/*/rtl/ct_spsram_*` 是 ASIC-facing 外壳：模块名不带 `_f`，但当前实现直接实例化对应的 `ct_f_spsram_*`；TSMC 宏实例仅以注释保留。因此 `C910_asic_rtl.fl` 这个名字并不意味着本 filelist 使用了真实 ASIC SRAM macro。
4. 当前 `cpu_cfig.h` 定义了 `FPGA`、`ICACHE_64K`、`DCACHE_64K`、`L2_CACHE_16WAY` 和 `L2_CACHE_1M`（`gen_rtl/cpu/rtl/cpu_cfig.h:62,198,203,214,219`），所以实际综合/仿真会从这些尺寸候选中选择相应 wrapper；filelist 仍把全部候选 wrapper 编译进去。

调用关系可以概括为：

```text
cache/TLB/IFU/LSU array
└─ ct_spsram_<depth>x<width>                 ASIC-facing、统一 SRAM 接口
   └─ ct_f_spsram_<depth>x<width>            FPGA/RTL 替代 wrapper
      └─ fpga_ram #(data_width, addr_width)  通用同步 RAM 模型
```

## 2. `fpga_ram` 通用模型

文件：`gen_rtl/fpga/rtl/fpga_ram.v`，module `fpga_ram`。

| 项目 | 结论与证据 |
|---|---|
| 接口 | `PortAClk`、`PortAAddr`、`PortADataIn`、`PortAWriteEnable`、`PortADataOut`；端口定义见 `fpga_ram.v:15-32`。注释掉的 `PortAChipEnable` 不参与功能。 |
| 参数/容量 | `DATAWIDTH` 默认 2，`ADDRWIDTH` 默认 2；`MEMDEPTH = 2**ADDRWIDTH`，存储阵列为 `mem[0:MEMDEPTH-1]`，见 `fpga_ram.v:24-36`。因此 wrapper 的文件名 `<depth>x<width>` 对应 `2**ADDRWIDTH = depth`、`DATAWIDTH = width` 或拆分后的 chunk width。 |
| 写入 | `PortAWriteEnable=1` 时在 `posedge PortAClk` 写 `mem[PortAAddr] <= PortADataIn`，同时 `PortADataOut <= PortADataIn`，见 `fpga_ram.v:39-45`。这是 write-first/写穿透输出语义。 |
| 读取 | 写使能为 0 时在同一上升沿执行 `PortADataOut <= mem[PortAAddr]`，见 `fpga_ram.v:46-50`；因此读数据是同步更新，不是组合读。 |
| 初始化/复位 | 没有 reset 端口、`initial` 块或显式清零；`mem` 和 `PortADataOut` 在仿真启动时未初始化，见 `fpga_ram.v:36-37`。综合到 FPGA 后的 RAM 初值也不由该模块保证。 |
| 综合差异 | `/* synthesis syn_ramstyle = "no_rw_check" */` 仅是综合属性，不能把它等同于某一厂商的 RAM primitive，见 `fpga_ram.v:36`。没有 `ifdef`、厂商库单元或 ASIC macro 绑定。 |

## 3. 统一 wrapper 接口与时序语义

所有 `ct_f_spsram_*` 都使用 `A/CEN/CLK/D/GWEN/Q/WEN`。普通 wrapper 的端口声明可见 `ct_f_spsram_8192x128.v:19-36`；参数和端口化 generate wrapper 的形式可见 `ct_f_spsram_1024x144.v:15-35`。

- `A` 是同步 SRAM 地址；地址宽度为 `log2(depth)`，例如 1024 深度使用 10 bit，8192 深度使用 13 bit。
- `CEN` 和 `GWEN` 为低有效控制，`WEN` 也是低有效。典型写使能是 `!CEN && !WEN[...] && !GWEN`，例如 `ct_f_spsram_8192x32.v:73-76`。
- 当 `CEN=0` 时，wrapper 在 `posedge CLK` 保存 `A` 到 `addr_holding`；随后用 `CEN ? addr_holding : A` 形成送入 `fpga_ram` 的地址，典型代码见 `ct_f_spsram_8192x32.v:90-97`。这样在 CEN 拉高后仍保持上一次有效地址。
- 需要注意，`fpga_ram` 没有 chip-enable。wrapper 只禁止写入，并没有在 `CEN=1` 时禁止 `fpga_ram` 的读时钟；所以每个 `posedge CLK` 仍会把保持地址对应的存储内容更新到 `Q`。这点是当前 FPGA 行为模型的实际语义，不应直接推断为 ASIC macro 的输出保持/高阻语义。
- 写周期的 `Q` 为新写入值，读周期的 `Q` 为一个同步 RAM 读结果。复位和未写地址的初始值未定义。
- 不同 wrapper 对 `WEN` 的保真度不同：逐 bit wrapper 对每一位独立写；按 chunk 拆分的 wrapper 只取每个 chunk 的代表性 WEN 位，例如 32 bit wrapper 用 `WEN[7]、WEN[15]、WEN[23]、WEN[31]`，见 `ct_f_spsram_8192x32.v:73-76`。这与 ASIC wrapper 的宏接口宽度保持一致，但不是对所有 WEN bit 都独立建模。

## 4. FPGA wrapper 文件/module 清单

下表覆盖目录中的全部 41 个文件/module。实现列中的“全宽 1 个”表示一个 `fpga_ram` 直接承载整个数据字；“逐 bit generate”表示生成 `DATA_WIDTH` 个 `1 bit` RAM；“N×W 分片”表示生成 N 个 W-bit RAM；“混合”表示不同宽度的 chunk。证据列使用 `M`（module/头部）、`P`（端口）、`A`（地址保持/选择）、`W`（写使能）、`R`（`fpga_ram` 实例）。

| 文件 / module | 深度×数据宽度 | 内部实现及作用 | 关键证据行 |
|---|---:|---|---|
| `ct_f_spsram_1024x128.v` / `ct_f_spsram_1024x128` | 1024×128 | 全宽 1 个 128×1024 RAM；适配 L2 data 1024 深度候选。 | M19；P30-36；A68-75；W61；R80 |
| `ct_f_spsram_1024x144.v` / `ct_f_spsram_1024x144` | 1024×144 | 逐 bit generate，144 个 1×1024 RAM；每个 `WEN[i]` 独立控制。 | M15；P29-35；A48-55；W62；R63-69 |
| `ct_f_spsram_1024x32.v` / `ct_f_spsram_1024x32` | 1024×32 | 4×8 分片；每片使用一个代表性 WEN 位。 | M19；P30-36；A90-97；W73-76；R111-132 |
| `ct_f_spsram_1024x59.v` / `ct_f_spsram_1024x59` | 1024×59 | 1+29+29 混合分片，分别映射 `D[58]`、`D[57:29]`、`D[28:0]`。 | M19；P30-36；A84-91；W70-72；R103-117 |
| `ct_f_spsram_1024x64.v` / `ct_f_spsram_1024x64` | 1024×64 | 逐 bit generate，64 个 1×1024 RAM。 | M15；P29-35；A48-55；W62；R67-73 |
| `ct_f_spsram_1024x92.v` / `ct_f_spsram_1024x92` | 1024×92 | 4×23 分片。 | M17；P28-34；A90-97；W73-76；R110-131 |
| `ct_f_spsram_128x104.v` / `ct_f_spsram_128x104` | 128×104 | 4×26 分片。 | M17；P28-34；A90-97；W73-76；R110-131 |
| `ct_f_spsram_128x144.v` / `ct_f_spsram_128x144` | 128×144 | 逐 bit generate，144 个 1×128 RAM。 | M15；P29-35；A48-55；W62；R63-69 |
| `ct_f_spsram_128x16.v` / `ct_f_spsram_128x16` | 128×16 | 16 个显式 1×128 RAM，逐位连接 `D/WEN/Q`。 | M19；P30-36；A174-181；W120-135；R218-323 |
| `ct_f_spsram_16384x128.v` / `ct_f_spsram_16384x128` | 16384×128 | 全宽 1 个 128×16384 RAM；L2 2M 候选。 | M19；P30-36；A68-75；W61；R80 |
| `ct_f_spsram_2048x128.v` / `ct_f_spsram_2048x128` | 2048×128 | 全宽 1 个 128×2048 RAM；L2 256K 候选。 | M19；P30-36；A68-75；W61；R80 |
| `ct_f_spsram_2048x144.v` / `ct_f_spsram_2048x144` | 2048×144 | 逐 bit generate，144 个 1×2048 RAM。 | M15；P29-35；A48-55；W62；R67-73 |
| `ct_f_spsram_2048x32.v` / `ct_f_spsram_2048x32` | 2048×32 | 4×8 分片；`ct_spsram_2048x32_split` 也转接到此 FPGA module。 | M19；P30-36；A90-97；W73-76；R111-132 |
| `ct_f_spsram_2048x59.v` / `ct_f_spsram_2048x59` | 2048×59 | 1+29+29 混合分片。 | M19；P30-36；A84-91；W70-72；R103-117 |
| `ct_f_spsram_2048x88.v` / `ct_f_spsram_2048x88` | 2048×88 | 逐 bit generate，88 个 1×2048 RAM。 | M15；P29-35；A48-55；W62；R67-73 |
| `ct_f_spsram_256x100.v` / `ct_f_spsram_256x100` | 256×100 | 4×25 分片。 | M17；P28-34；A90-97；W73-76；R110-131 |
| `ct_f_spsram_256x144.v` / `ct_f_spsram_256x144` | 256×144 | 逐 bit generate，144 个 1×256 RAM。 | M15；P29-35；A48-55；W62；R63-69 |
| `ct_f_spsram_256x196.v` / `ct_f_spsram_256x196` | 256×196 | 4+48+48+48+48 混合分片；高 4 bit 与四个 48 bit chunk 分开。 | M17；P28-34；A96-103；W76-80；R119-147 |
| `ct_f_spsram_256x23.v` / `ct_f_spsram_256x23` | 256×23 | 全宽 1 个 23×256 RAM。 | M19；P30-36；A69-76；W61；R84 |
| `ct_f_spsram_256x52.v` / `ct_f_spsram_256x52` | 256×52 | 2×26 分片。 | M19；P30-36；A76-83；W65-66；R93-100 |
| `ct_f_spsram_256x54.v` / `ct_f_spsram_256x54` | 256×54 | 2×27 分片。 | M19；P30-36；A76-83；W65-66；R93-100 |
| `ct_f_spsram_256x59.v` / `ct_f_spsram_256x59` | 256×59 | 1+29+29 混合分片。 | M19；P30-36；A84-91；W70-72；R103-117 |
| `ct_f_spsram_256x7.v` / `ct_f_spsram_256x7` | 256×7 | 7 个显式 1×256 RAM，逐位写使能。 | M19；P30-36；A111-118；W84-90；R137-179 |
| `ct_f_spsram_256x84.v` / `ct_f_spsram_256x84` | 256×84 | 2×42 分片。 | M17；P28-34；A74-81；W63-64；R91-98 |
| `ct_f_spsram_32768x128.v` / `ct_f_spsram_32768x128` | 32768×128 | 逐 bit generate，128 个 1×32768 RAM；L2 4M 候选。 | M15；P29-35；A48-55；W62；R67-73 |
| `ct_f_spsram_4096x128.v` / `ct_f_spsram_4096x128` | 4096×128 | 全宽 1 个 128×4096 RAM；L2 512K 候选。 | M19；P30-36；A68-75；W61；R80 |
| `ct_f_spsram_4096x144.v` / `ct_f_spsram_4096x144` | 4096×144 | 逐 bit generate，144 个 1×4096 RAM。 | M15；P29-35；A48-55；W62；R67-73 |
| `ct_f_spsram_4096x32.v` / `ct_f_spsram_4096x32` | 4096×32 | 4×8 分片。 | M19；P30-36；A90-97；W73-76；R111-132 |
| `ct_f_spsram_4096x84.v` / `ct_f_spsram_4096x84` | 4096×84 | 逐 bit generate，84 个 1×4096 RAM。 | M15；P29-35；A48-55；W62；R67-73 |
| `ct_f_spsram_512x144.v` / `ct_f_spsram_512x144` | 512×144 | 逐 bit generate，144 个 1×512 RAM。 | M15；P29-35；A48-55；W62；R63-69 |
| `ct_f_spsram_512x22.v` / `ct_f_spsram_512x22` | 512×22 | 2×11 分片。 | M19；P30-36；A76-83；W65-66；R93-100 |
| `ct_f_spsram_512x44.v` / `ct_f_spsram_512x44` | 512×44 | 2×22 分片。 | M19；P30-36；A76-83；W65-66；R92-99 |
| `ct_f_spsram_512x52.v` / `ct_f_spsram_512x52` | 512×52 | 2×26 分片。 | M19；P30-36；A76-83；W65-66；R93-100 |
| `ct_f_spsram_512x54.v` / `ct_f_spsram_512x54` | 512×54 | 2×27 分片。 | M19；P30-36；A76-83；W65-66；R93-100 |
| `ct_f_spsram_512x59.v` / `ct_f_spsram_512x59` | 512×59 | 1+29+29 混合分片。 | M19；P30-36；A84-91；W70-72；R103-117 |
| `ct_f_spsram_512x7.v` / `ct_f_spsram_512x7` | 512×7 | 7 个显式 1×512 RAM，逐位写使能。 | M19；P30-36；A111-118；W84-90；R137-179 |
| `ct_f_spsram_512x96.v` / `ct_f_spsram_512x96` | 512×96 | 4×24 分片。 | M17；P28-34；A90-97；W73-76；R110-131 |
| `ct_f_spsram_64x108.v` / `ct_f_spsram_64x108` | 64×108 | 4×27 分片。 | M17；P28-34；A90-97；W73-76；R110-131 |
| `ct_f_spsram_65536x128.v` / `ct_f_spsram_65536x128` | 65536×128 | 逐 bit generate，128 个 1×65536 RAM；L2 8M 候选。 | M15；P29-35；A48-55；W62；R67-73 |
| `ct_f_spsram_8192x128.v` / `ct_f_spsram_8192x128` | 8192×128 | 全宽 1 个 128×8192 RAM；当前 L2 1M 配置使用的候选。 | M19；P30-36；A68-75；W61；R80 |
| `ct_f_spsram_8192x32.v` / `ct_f_spsram_8192x32` | 8192×32 | 4×8 分片；当前 ICACHE 256K/相关候选之一。 | M19；P30-36；A90-97；W73-76；R111-132 |

## 5. 与 ASIC SRAM wrapper 的关系

### 5.1 外壳是接口适配，不是第二套存储实现

`gen_rtl/l2c/rtl/ct_spsram_8192x128.v` 定义 ASIC-facing module `ct_spsram_8192x128`，端口为 `A/CEN/CLK/D/GWEN/Q/WEN`（17-45 行），参数为地址、数据和写使能宽度（51-53 行）。其“FPGA memory”实例在 60-72 行直接调用 `ct_f_spsram_8192x128`；拟使用的 `ct_tsmc_spsram_8192x128` 只在 74 行以注释存在。`ct_spsram_128x16.v:60-76` 展示了相同关系，并保留了该宏的 WEN 分组注释。

`ct_spsram_2048x32_split.v:60-73` 虽然 module 名多了 `_split`，仍然直接调用 `ct_f_spsram_2048x32`，因此 FPGA 目录没有也不需要一个同名 `_split` 的 `ct_f` 文件。

### 5.2 filelist 证据

- `gen_rtl/filelists/C910_asic_rtl.fl:54-94` 连续列出全部 41 个 `gen_rtl/fpga/rtl/ct_f_spsram_*.v`。
- 同一 filelist 在 `:392-433` 列出 42 个 ASIC-facing `ct_spsram_*` wrapper，额外的一个正是 `gen_rtl/ifu/rtl/ct_spsram_2048x32_split.v`。
- `gen_rtl/filelists/C910_asic_rtl.fl:469` 显式加入 `gen_rtl/fpga/rtl/fpga_ram.v`。因此 filelist 同时提供了外壳、FPGA wrapper 和最底层 RAM 定义。

### 5.3 当前配置下的实际调用

当前配置并非所有候选尺寸都会同时成为有效硬件路径。上层引用和选择关系如下：

| 功能块 | 当前/候选 SRAM wrapper | 上层引用证据 |
|---|---|---|
| L2 data | `ct_spsram_8192x128` 在 `L2_CACHE_1M` 下生效；1024/2048/4096/16384/32768/65536 深度是其他容量分支。 | `gen_rtl/l2c/rtl/ct_l2cache_data_array.v:60-89`；当前 `L2_CACHE_1M` 为 `cpu_cfig.h:219`。 |
| L2 dirty | `ct_spsram_{128,256,512,1024,2048,4096}x144`。 | `gen_rtl/l2c/rtl/ct_l2cache_dirty_array_16way.v:56-71`。 |
| L2 tag | `ct_spsram_64x108`、`128x104`、`256x100`、`512x96`、`1024x92`、`2048x88`，按容量/way 组合选择。 | `gen_rtl/l2c/rtl/ct_l2cache_tag_array_16way.v:62-179`。 |
| IFU I-cache data | 非 ECC 分支按 `ICACHE_256K/128K/64K/32K` 选择 `8192x32`、`4096x32`、`ct_spsram_2048x32_split`、`1024x32`；当前 `ICACHE_64K` 选择 `_split`，其底层转到 `ct_f_spsram_2048x32`。 | `gen_rtl/ifu/rtl/ct_ifu_icache_data_array0.v:248-340`，array1 具有相同 bank 结构；当前宏为 `cpu_cfig.h:198`。 |
| IFU I-cache tag | 非 ECC 分支按容量选择 `ct_spsram_2048x59`、`1024x59`、`512x59`、`256x59`；当前 64K 选择 `512x59`。 | `gen_rtl/ifu/rtl/ct_ifu_icache_tag_array.v:116-139`；ECC 分支的 `2048/1024/512/256x61` 见 `:99-115`。 |
| IFU BTB/BHT/indirect BTB | `ct_spsram_512x22`、`512x44`、`1024x64`、`128x16`、`256x23`。 | `ct_ifu_btb_tag_array.v:117,138`；`ct_ifu_btb_data_array.v:116,137`；`ct_ifu_bht_pre_array.v:86`；`ct_ifu_bht_sel_array.v:86`；`ct_ifu_ind_btb_array.v:84`。 |
| LSU D-cache data/tag/dirty | 当前 `DCACHE_64K` 选择 `2048x32`、`512x52`、`512x54`、`512x7`；32K 分支分别是 `1024x32`、`256x52`、`256x54`、`256x7`。 | `ct_lsu_dcache_data_array.v:86-114`；`ct_lsu_dcache_tag_array.v:88-116`；`ct_lsu_dcache_ld_tag_array.v:82-109`；`ct_lsu_dcache_dirty_array.v:81-109`；当前宏为 `cpu_cfig.h:203`。 |
| MMU JTLB | `ct_spsram_256x196` 和 `ct_spsram_256x84`。 | `gen_rtl/mmu/rtl/ct_mmu_jtlb_tag_array.v:117`；`gen_rtl/mmu/rtl/ct_mmu_jtlb_data_array.v:158,179`。 |

## 6. 配置/综合边界与注意事项

1. `ct_f_spsram_*` 没有厂商 primitive、宏库 black-box 或 `ifdef FPGA/ASIC` 双实现；所谓 FPGA 替代来自 `ct_f` 命名、`fpga_ram` 的 RTL 阵列和总 filelist 的组合。不同 FPGA 工具可能把这些 `reg` 阵列映射到不同数量/形状的块 RAM，也可能因端口宽度、逐 bit 拆分和 `no_rw_check` 属性而产生不同资源结果。
2. ASIC 真实宏与当前模型可能在 CEN 无效时的 Q 行为、未初始化内容、读写冲突定义、DFT/scan 端口和 WEN 粒度上不同。当前 wrapper 只保留统一功能端口，未建模 scan、宏初始化或真实宏的所有电气/时序约束。
3. 按 chunk 的 wrapper 只用一个 WEN bit 控制一个 chunk；逐 bit wrapper 才逐 bit 使用 `WEN[i]`。因此验证 byte/segment 写掩码时必须以具体尺寸 wrapper 的连接为准，不能只看 module 名中的数据宽度。
4. `L1_CACHE_ECC` 分支引用 `ct_spsram_2048x33/1024x33` 和 `ct_spsram_512x61/256x61`（例如 `ct_ifu_icache_data_array0.v:180-247`、`ct_ifu_icache_tag_array.v:99-115`），但这些尺寸既不在本目录 41 个 `ct_f` 文件中，也不在 `C910_asic_rtl.fl:54-94` 中。当前 `cpu_cfig.h` 未定义 `L1_CACHE_ECC`，所以这些分支不是当前 filelist/config 的有效 FPGA SRAM 路径；若启用 ECC，需要补齐对应 macro/model 和 filelist。

综上，`gen_rtl/fpga/rtl` 是面向 FPGA/RTL 的 SRAM 替代层：上层仍通过 ASIC 统一 wrapper 名称和端口连接，真正的存储行为由 `ct_f_spsram_*` 的拆分逻辑和 `fpga_ram` 的同步 write-first 模型提供。
