# RTU（`gen_rtl/rtu/rtl`）结构与控制流

## 1. 范围与结论

本文只针对 `gen_rtl/rtu/rtl` 目录的 22 个 Verilog 文件进行追踪；未修改任何 RTL。结论以当前源码的实例连接、位宽和时序逻辑为准，不把注释中的生成模板当作实际连接。

RTU 的主路径是：

```text
IDU 分配/重命名
      │
      ├── preg/ereg/vreg 状态表分配物理寄存器
      └── ROB 建立顺序条目并分配 7-bit IID
                │
                ▼
IU pipe0/1/2、LSU pipe3/4、VFPU pipe6/7 完成/异常回报
                │
                ├── ROB 按 IID 标记完成、保存异常和 LSU 附加属性
                └── ROB 头部三项读出
                         │
                         ▼
                 rob_rt 组织 retire/commit 数据
                         │
                         ▼
                 ct_rtu_retire 按序退休、异常/flush/调试仲裁
                    │       │       │
                    │       │       ├── IFU/IDU/LSU flush 与控制流回报
                    │       ├── CP0/MMU 异常、interrupt、向量状态回报
                    │       └── HAD/HPCP/调试回报
                    │
                    └── ROB pop；PST 按 retire IID 释放旧物理寄存器
```

这里的“完成”不是一个统一的 ready/valid 接口，而是各执行管线按 IID 提供的 `cmplt_vld`、异常、flush 和 writeback 信号；“退休”是 ROB 头部的顺序资格；“commit”是 `rob_rt` 产生并经 `ct_rtu_retire` 的屏蔽条件处理后的提交脉冲。

关键配置来自 RTL：4 路 IDU 分配/重命名，ROB 64 项、每项 40 bit，IID 7 bit，ROB 同时读/退休 3 项；preg 状态表 96 项（preg0 常量项 + 95 个 entry），ereg 32 项，vreg/freg 64 项。证据见 `ct_rtu_top.v:40-139`、`ct_rtu_rob.v:633-647`、`ct_rtu_rob_entry.v:168-195`、`ct_rtu_pst_preg.v:1417-5742`、`ct_rtu_pst_ereg.v:630-1839`、`ct_rtu_pst_vreg.v:1134-4095`。

## 2. 完整模块树与实例关系

```text
ct_rtu_top                                      ct_rtu_top.v:15
├── ct_rtu_pst_preg                             ct_rtu_top.v:1555
│   ├── preg0 固定映射/常量逻辑                 ct_rtu_pst_preg.v:1405-1416, 5796-5891
│   ├── 95 × ct_rtu_pst_preg_entry              ct_rtu_pst_preg.v:1417-5742
│   ├── 4 × ct_rtu_expand_96（IDU 分配）         ct_rtu_pst_preg.v:5994-6019
│   └── ct_rtu_encode_96（dealloc/recover）      ct_rtu_pst_preg.v:6955-6976, 8391-8634
├── ct_rtu_pst_ereg                             ct_rtu_top.v:1624
│   ├── 32 × ct_rtu_pst_ereg_entry              ct_rtu_pst_ereg.v:630-1839
│   ├── 6 × ct_rtu_expand_32（分配/WB）          ct_rtu_pst_ereg.v:1922-2009
│   └── ct_rtu_encode_32（dealloc/recover）     ct_rtu_pst_ereg.v:2360-2385, 2733-2740
├── ct_rtu_pst_vreg_dummy                       ct_rtu_top.v:1688
│   └── 整数向量/不跟踪变体的常量回报            ct_rtu_pst_vreg_dummy.v:180-189
├── ct_rtu_pst_vreg                             ct_rtu_top.v:1750（连接为 freg 变体）
│   ├── 64 × ct_rtu_pst_vreg_entry              ct_rtu_pst_vreg.v:1134-4095
│   ├── 4 × ct_rtu_expand_64（IDU 分配）         ct_rtu_pst_vreg.v:4284-4309
│   └── ct_rtu_encode_64（dealloc/recover）     ct_rtu_pst_vreg.v:5028-5053, 6042-6285
├── ct_rtu_rob                                  ct_rtu_top.v:1827
│   ├── 64 × ct_rtu_rob_entry                   ct_rtu_rob.v:1644-3883
│   ├── 3 × ct_rtu_rob_entry（read window）      ct_rtu_rob.v:3885-4000
│   ├── 7 × ct_rtu_expand_64（完成 IID）         ct_rtu_rob.v:4597-4645
│   ├── 3 × ct_rtu_expand_64（pop pointer）      ct_rtu_rob.v:5929-5949
│   ├── ct_rtu_rob_expt                         ct_rtu_rob.v:6160-6248
│   │   └── 13 × ct_rtu_compare_iid             ct_rtu_rob_expt.v:343-434, 754-779
│   └── ct_rtu_rob_rt                           ct_rtu_rob.v:6249-6484
└── ct_rtu_retire                               ct_rtu_top.v:2134
```

`top.v:1679` 的注释保留了另一生成变体的名称，但实际实例是 `ct_rtu_pst_vreg_dummy`；实际的 `ct_rtu_pst_vreg` 实例在 `top.v:1750`，实例名为 `x_ct_rtu_pst_freg`。因此本文按真实实例和端口连接描述，而不是按生成注释推断一个未实例化的 vreg 表。

## 3. 文件清单与职责

| 文件 | 实际职责 | 关键证据 |
|---|---|---|
| `ct_rtu_top.v` | RTU 顶层端口汇总、实例化 PST/ROB/retire、跨单元连线和 debug 压缩信息 | `:15-469`、`:1555-1831`、`:2134-2445`、`:2451-2461` |
| `ct_rtu_rob.v` | 64 项 ROB 阵列、创建指针/IID、完成广播、三项读窗口、pop、ROB 状态 | `:1644-4000`、`:4309-4488`、`:4589-4796`、`:5804-6086` |
| `ct_rtu_rob_entry.v` | 单个 40-bit ROB 项；保存创建元数据、完成计数、LSU 回写属性及有效位 | `:168-195`、`:285-388`、`:394-530` |
| `ct_rtu_rob_expt.v` | 异常信息采集、异常优先级、split spec fail 状态机和 IID 年龄比较 | `:98-174`、`:478-598`、`:658-817` |
| `ct_rtu_rob_rt.v` | ROB 读出项到退休项/提交项的适配；匹配完成、生成 PC/分支信息、commit mask | `:1025-1125`、`:1680-1988`、`:2592-2729` |
| `ct_rtu_retire.v` | 顺序退休判定；异常、interrupt、debug、flush、IFU/IDU/LSU/CP0/HAD/HPCP 输出 | `:1010-1070`、`:1080-1428`、`:1431-1733`、`:1860-2196` |
| `ct_rtu_pst_preg.v` | 96 项整数物理寄存器状态表、分配/dealloc/recover/writeback/释放汇总 | `:1417-5742`、`:5994-6019`、`:6955-6976`、`:8391-8635` |
| `ct_rtu_pst_preg_entry.v` | 单个 preg 生命周期状态、IID 退休匹配、旧映射释放、WB 状态 | `:185-213`、`:268-381`、`:466-571` |
| `ct_rtu_pst_ereg.v` | 32 项异常/特殊寄存器状态表；连接 IDU、VFPU WB、退休和 recover | `:630-1839`、`:1922-2009`、`:2360-2385`、`:2733-2741` |
| `ct_rtu_pst_ereg_entry.v` | 单个 ereg 生命周期及退休释放匹配 | `:185-213`、`:268-381`、`:491-527` |
| `ct_rtu_pst_vreg.v` | 64 项向量/浮点物理寄存器状态表；本顶层实际接为 freg 变体 | `:1134-4095`、`:4284-4309`、`:5028-5053`、`:6042-6286` |
| `ct_rtu_pst_vreg_entry.v` | 单个 vreg 生命周期、WB、退休 IID 匹配和释放 | `:188-213`、`:273-387`、`:471-575` |
| `ct_rtu_pst_vreg_dummy.v` | 不跟踪该寄存器类时的 tie-off；输出 retired/WB 常量和无效分配 | `:17-192`，尤其 `:180-189` |
| `ct_rtu_expand_8.v` | 3-bit 编号转 8-bit one-hot | `:17-46` |
| `ct_rtu_expand_32.v` | 5-bit 编号转 32-bit one-hot | `:17-70` |
| `ct_rtu_expand_64.v` | 6-bit 编号转 64-bit one-hot | `:17-102` |
| `ct_rtu_expand_96.v` | 7-bit 编号转 96-bit one-hot | `:17-134` |
| `ct_rtu_encode_8.v` | 8-bit one-hot 转 3-bit 编号 | `:17-47` |
| `ct_rtu_encode_32.v` | 32-bit one-hot 转 5-bit 编号 | `:17-71` |
| `ct_rtu_encode_64.v` | 64-bit one-hot 转 6-bit 编号 | `:17-103` |
| `ct_rtu_encode_96.v` | 96-bit one-hot 转 7-bit 编号 | `:17-135` |
| `ct_rtu_compare_iid.v` | 7-bit 环形 IID 的先后比较，用于异常/split spec fail 年龄仲裁 | `:17-80` |

## 4. 分配、重命名与 ROB 建立

### 4.1 PST 分配

IDU 为四个 dispatch slot 提供各类寄存器的分配有效、逻辑目的寄存器、旧物理寄存器、new/rel 映射和 IID。`ct_rtu_top` 将这些信号直接分到三个真实状态表或 dummy 表：preg 连接见 `top.v:1555-1621`，ereg 见 `:1624-1675`，整数向量 dummy 见 `:1688-1731`，freg/vreg 变体见 `:1750-1825`。

每个 PST 顶层先把 IDU 给出的编号展开为 one-hot，再把 dealloc/recover 的 one-hot 结果编码回编号。preg 的分配展开在 `pst_preg.v:5994-6019`，dealloc 在 `:6955-6976`，恢复编码在 `:8391-8635`；ereg、vreg 分别采用 32/64 位对应的 helper。这样的连接让每个 entry 可以并行判断“本周期是否被创建、释放、写回或退休”。

preg0 不由普通 entry 管理；`pst_preg.v:5796-5891` 将 preg0 映射固定为有效/初始映射，preg1..31 复位为架构寄存器对应映射，preg32..95 复位为未映射。vreg dummy 则明确输出无效分配 ID、零恢复信息和已满足的 retired/WB 状态，见 `pst_vreg_dummy.v:180-189`。

### 4.2 单 entry 生命周期

三个 entry 文件使用同一类生命周期思想：

```text
DEALLOC → WF_ALLOC → ALLOC → RETIRE → RELEASE → DEALLOC
                   │          │          │
                   └──────────┴──────────┴── flush/release/WB 条件
```

preg entry 的状态编码和转移在 `ct_rtu_pst_preg_entry.v:185-319`；ereg/vreg entry 的对应实现分别在 `ct_rtu_pst_ereg_entry.v:185-381`、`ct_rtu_pst_vreg_entry.v:188-387`。创建时 entry 锁存目的逻辑寄存器、new/rel 映射和 IID；写回状态单独由 WB 子状态机记录，且 dealloc mask 会屏蔽不应继续占用的状态，preg 见 `:345-461`，vreg 见 `:350-437`。

退休时，entry 不靠“第几个物理寄存器”猜测顺序，而是把自身保存的 IID 与 ROB 提供的 `rob_pst_retire_inst0/1/2_iid_updt_val` 比较；只有对应的 PST 类型退休有效且 IID 相等时，才产生 `retire_vld`/release one-hot。preg 的匹配逻辑见 `ct_rtu_pst_preg_entry.v:466-571`，vreg 见 `ct_rtu_pst_vreg_entry.v:471-575`。这就是旧物理映射只能在其拥有者按序退休后释放的关键约束。

### 4.3 ROB 创建与 IID

ROB 为 64 项维护 one-hot 创建指针和 entry 数量。`rob.v:4309-4379` 按本周期 4/3/2/1 个 IDU create enable 旋转 create pointer，并从连续 IID 0、1、2、3 开始分配；因此 create slot 与 ROB entry 的关系由 one-hot pointer 决定，不是静态 slot 到 entry 的绑定。`rob.v:4002-4023` 生成各 create port 的选择，`:4221-4284` 选择写入哪个 create data。

每个 `ct_rtu_rob_entry` 接收四路创建数据、自己的 create select/gateclk、七路完成 one-hot、flush 和 pop。entry 的 40-bit 字段定义位于 `rob_entry.v:168-195`；创建、pop/flush 以及完成计数在 `:285-388`，LSU 侧的 bkpt/no-spec 属性更新在 `:394-443`，最后打包读数据在 `:448-530`。

ROB 数量计数在 `rob.v:4381-4488`，同时计算 empty、1/2 entry、full。对 IDU 的 empty 还要求 ROB empty 与 `retire_rob_retire_empty` 同时成立，因此 LSU 尚有未提交数据时，不能把 RTU 看作完全空闲。

## 5. 执行单元完成、IID 匹配与异常采集

### 5.1 完成广播

完成来源固定为：IU pipe0/1/2、LSU pipe3/4、VFPU pipe6/7。ROB 将各完成信号的 IID 截取低 6 bit，经七个 `ct_rtu_expand_64` 变成 64 项 one-hot，见 `ct_rtu_rob.v:4589-4666`，再广播给所有 ROB entry。entry 按自己的 completion bit 设置完成；对 folded instruction，`cmplt_cnt` 会在 `ct_rtu_rob_entry.v:344-388` 逐步消化 1/2/3 个完成片段。

`rob_rt` 反向做“当前头部 read entry 的 IID”与所有完成管线 IID 的比较，因而能够把完成来源对应的异常、LSU 属性和 VFPU 状态接到正确退休项。匹配逻辑见 `ct_rtu_rob_rt.v:1025-1125`。

### 5.2 异常信息与优先级

`ct_rtu_rob_expt` 把异常入口、flush、mispred、bkpt、MTVAL、异常向量、vstart/vsetvl 等打包成 70-bit exception entry，字段打包见 `ct_rtu_rob_expt.v:478-540`。同一拍多个执行单元有异常时，源码的写入优先级是 pipe4 > pipe3 > pipe2 > pipe0，见 `:543-557`；异常 entry 的有效位在异常完成时置位，在 flush/异常退休时清除，见 `:565-598`。

异常年龄不是普通无符号大小比较。`ct_rtu_compare_iid.v:44-77` 根据 IID 的最高位是否翻转，使用低 6 bit 的环形顺序判断 `x_iid0` 是否更老。`rob_expt.v:343-434` 的 10 个比较器用于普通异常源之间及其与当前 exception entry 的排序；`:754-779` 的 3 个比较器用于 split spec fail。

### 5.3 Split spec fail

split spec fail 在 `rob_expt.v:658-748` 使用 IDLE、WF_RETIRE、RETIRING 三态流程：pipe3/4 发生 split fail 后，先记录按 IID 仲裁的最老项；等待该 IID 到达退休；退休期间通过 `rob_retire_split_spec_fail_srt` 强制 single-retire；同时用 `ssf_split_spec_fail_flush` 只冲刷不属于该 split 项的后续路径。当前 SSF IID 的更新和输出在 `:788-817`。

## 6. ROB 读出、按序退休与提交

### 6.1 三项 read window

ROB 另外实例化三个 `ct_rtu_rob_entry` 作为 read entry，见 `ct_rtu_rob.v:3885-4000`。它们不是再次分配的 64 项，而是保存当前退休窗口的三项数据；读数据输出在 `:5804-5806`。退休项更新有效时，read pointer 按 1/2/3 项推进，`:5822-5903`；ROB pop pointer 则使用三个 expand_64，并按 `rtu_yy_xx_retire0/1/2` 退休脉冲推进，`:5929-6086`。

`rob_rt` 将三项 ROB 数据和当前完成匹配结果组织成 retire data。其 52-bit retire metadata 包含 VL/VSETVLI、向量/浮点 dirty、load/store、bkpt、instruction number、PC offset、BJU、split 和 IID 等，打包见 `ct_rtu_rob_rt.v:1680-1826`；随后拆出各字段并提供给 `ct_rtu_retire`，见 `:1828-1988`。

### 6.2 retire 判定

`ct_rtu_retire.v:1010-1070` 定义单退休模式：`had_rtu_pop1_disa`、debug 请求或 CP0 single-retire 配置会使 IDU/ROB 只退休一项；split spec fail、interrupt 和 CTC flush 也能通过 `retire_rob_srt_en` 进入单退休。

正常资格的源码定义很直接：

```text
retire_inst0_normal_retire = rob_retire_inst0_vld && !rob_retire_inst0_expt_vld
retire_inst1_normal_retire = rob_retire_inst1_vld
retire_inst2_normal_retire = rob_retire_inst2_vld
```

证据见 `ct_rtu_retire.v:1080-1088`。异常、interrupt、debug 只允许命中 retire inst0；inst1/inst2 没有独立异常入口。PST 的 preg/vreg/ereg 退休有效则直接取 ROB 三项中相应的 PST valid，见 `:1090-1110`，entry 再用 IID 做最终确认。

这里的 `normal_retire` 是退休资格，并不等价于所有情况下的 ROB commit。`rob_rt` 先产生 `rob_read0/1/2_commit`，然后将 debug、single-retire、异步异常和同步异常屏蔽施加到 commit：基础 commit 条件在 `ct_rtu_rob_rt.v:2592-2645`，异步/同步 mask 在 `:2647-2683`，commit 脉冲和 IID 锁存于 `:2685-2729`。因此可能出现“ROB 项正常退休信息有效，但新 commit 被单独屏蔽”的中间状态。

### 6.3 PST 更新与旧映射退休

ROB read pointer 推进时，ROB 输出三路 `rob_pst_retire_instN_iid_updt_val`。PST 顶层把这些 IID 与本地 entry 的 IID 匹配，entry 只有在所属寄存器类的退休 valid 和 IID 同时命中时，才从 RETIRE/RELEASE/WB 路径释放。preg 顶层将各 entry 的 retired/released/WB 汇总并反馈 `pst_empty` 与 recover；vreg 的汇总路径可见 `ct_rtu_pst_vreg.v:5411-5424`，preg/ereg 采用相同的生成结构。

flush 或 recovery 时，PST 顶层用 IDU/RTU 给出的 recover one-hot 重新建立映射；preg、ereg、vreg 的 encode recovery 实例分别见 `pst_preg.v:8391-8635`、`pst_ereg.v:2733-2740`、`pst_vreg.v:6042-6285`。这部分是恢复 rename 状态，不是把所有 entry 盲目清零。

## 7. 异常、flush、interrupt 与调试

### 7.1 同步异常与 interrupt

异常源取自 ROB inst0：`rob_retire_inst0_expt_vld` 形成同步异常，`int_vld && !split && !intmask` 形成可响应 interrupt，见 `ct_rtu_retire.v:1114-1149`。异常 vector、MTVAL 和 EPC 的来源与优先级在 `:1150-1326`：

- asynchronous exception 使用 LSU 提供的物理地址作为 MTVAL；
- interrupt 的 MTVAL 为 0；
- IMMU 异常根据当前 PC/next PC 形成跨页地址；
- 普通异常使用 ROB 的 MTVAL；
- 异常指令或 instruction breakpoint 的 EPC 取当前 PC，否则取 next PC；异步异常取 ROB current PC。

IFU 异常 valid/vector 在 `:1248-1295` 锁存；CP0 异常、EPC、MTVAL、interrupt ack 在 `:1307-1333` 输出；MMU bad VPN 取 MTVAL[38:12]，见 `:1298-1305`。FP dirty、vector dirty 汇总三项退休项，见 `:1335-1350`。

### 7.2 VSETVL/VSTART 与向量状态

`ct_rtu_retire` 只对正常退休项产生 VSETVLI/VSETVL 更新资格，见 `:1352-1370`。CP0 的 VL/VTYPE 在 slot0/1/2 中按优先级选择，VSETVL 指令的 VL/VTYPE 则从 MTVAL 对应字段取值，见 `:1371-1421`；vstart valid/value 取 retire inst0 的 ROB 字段，见 `:1424-1428`。split 的 VSETVL FOF 会另外产生 `retire_rob_split_fof_flush`，见 `:1366-1370`。

### 7.3 Flush 状态机

flush 状态编码为 IDLE、IS、FE、IS_BE、FE_BE、BE，见 `ct_rtu_retire.v:1860-1868`。触发条件包括异常、inst flush、debug、异步异常和分支预测错误；`retire_inst0_flush`、`retire_inst0_mispred` 及 gateclk 组合见 `:1874-1889`。状态转移在 `:1907-1951`，会等待 `pst_retire_retired_reg_wb && lsu_rtu_all_commit_data_vld` 的流水线空闲条件后进入后端冲刷。

flush 输出在 `:1959-1990`：

- `rtu_ifu_flush`、`rtu_idu_flush_fe/is`：冲刷取指、取指前端或 decode/issue；
- `rtu_idu_flush_stall`：flush 状态机尚未回到 IDLE 时阻止继续推进；
- `retire_rob_flush`：通知 ROB 清理错误路径；
- `rtu_yy_xx_flush`：通知后端/整体控制逻辑。

同步异常、eret、spec fail 的理由锁存在 `:2022-2051`，分别输出 `rtu_lsu_expt_flush`、`rtu_lsu_eret_flush`、`rtu_lsu_spec_fail_flush`；spec fail IID 在 `:2056-2070` 区分普通项与 SSF 当前项。

JDB/JDBREQ 的异步 flush 通过 `async_flush_ff` 传播到 `retire_pst_async_flush` 和 `rtu_lsu_async_flush`，见 `:1993-2016`。这说明 PST 的 flush 输入和 LSU 的异步 flush 输入都来自 retire 的统一异步路径。

### 7.4 异步异常排空

LSU 异步异常不会直接打断当前 commit。状态机在 `ct_rtu_retire.v:2078-2165` 中分为 AE_IDLE、AE_WFC、AE_WFI、AE_EXPT：

1. AE_WFC 停止新的 commit，但允许已经存在的 commit 完成；
2. AE_WFI 等待 ROB 不再退休且 PST/LSU 数据排空；
3. AE_EXPT 输出异步异常 valid，异常向量固定为 5，并触发 flush。

`retire_rob_async_expt_commit_mask` 只在 WFC 有效，`retire_rob_rt_mask` 在等待阶段阻止新的退休；这两个信号由 `rob_rt` 的 commit/retire mask 消化。

### 7.5 调试/HAD

调试请求只在退休 inst0 应答。硬件、断点、trace、event、JDBREQ 和 non-IRV 的组合及 debug ack 条件见 `ct_rtu_retire.v:1588-1625`；进入/退出 debug mode 的状态在 `:1640-1665`，HAD 的 ack PC、debug ack info、异常 PC、PCFIFO 字段在 `:1672-1723`。debug 请求会强制 single-retire，源码在 `:1010-1021` 明确说明 commit1/2 不能与 debug ack 同时进入。

## 8. 跨模块连接清单

| 对端 | RTU 接收 | RTU 回报 | 真实连接/证据 |
|---|---|---|---|
| IDU | 四路 preg/ereg/vreg/freg allocate、rename、dealloc/recover；四路 ROB create | alloc 后的物理 ID/valid、PST empty、ROB IID/full/empty、退休 valid、FE/IS flush、single-retire | `ct_rtu_top.v:40-139`、`:496-595`、`:1555-1827`、`:2134-2445` |
| IU | pipe0/1/2 completion、IID、异常/flush、mispred、MTVAL/vstart/vsetvl | IFU/整体异常、ROB completion/pop/flush；IU flush/chgflow 由顶层继续转发 | 输入定义 `top.v:143-171,599-627`；ROB completion `rob.v:4589-4796` |
| LSU | pipe3/4 completion、异常、flush、spec fail、writeback、异步异常、CTC flush | async/expt/eret/spec-fail flush、spec-fail IID、LSU commit IID/commit 脉冲 | `top.v:172-215,628-671`、retire `:1993-2070` |
| VFPU | pipe6/7 completion、ereg/freg writeback | ROB 完成匹配、ereg/freg WB/退休释放 | `top.v:216-232,672-687`；ereg `pst_ereg.v:1996-2009` |
| IFU | 当前 PC、debug/异常相关协同 | flush、change-flow PC/valid、退休分支/跳转/return/预测结果、异常 vector | `top.v:140-142,596-598`；retire `:1431-1582` |
| CP0 | interrupt、SRT、clock/config、异常入口相关控制 | EPC、MTVAL、异常 valid、interrupt ack、FP/vector dirty、VTYPE/VL/VSTART | `top.v:16-22,479-495`；retire `:1307-1428` |
| MMU | MMU enable、MMU 异常/配置 | MMU exception valid、bad VPN | `ct_rtu_top.v` CP0/MMU 端口段 `:672-709`；retire `:1298-1305` |
| HAD/调试 | debug request、断点、trace、退出 debug | ack、debug mode、ack PC/PCFIFO、断点 ack、压缩 debug info | `top.v:23-38,479-494`；retire `:1588-1723`；top `:2451-2461` |
| HPCP | counter enable | 三项退休的 branch/store/spec-fail/interrupt/PC offset 统计信息 | top `:39,495`；retire `:1758-1853` |

## 9. 关键时序链路（按一个指令描述）

1. IDU 给出某 dispatch slot 的逻辑目的寄存器、new/rel 物理寄存器、分配有效和 IID；PST 将编号展开并让匹配的 entry 进入 WF_ALLOC/ALLOC。
2. 同周期或相邻周期，ROB 用 create pointer 选中一个 entry，锁存 40-bit create data，并为该指令生成顺序 IID。
3. 执行单元完成时只需带回自己的 IID 和 `cmplt_vld`/异常/WB 属性；ROB 将 IID 映射为 entry one-hot，entry 更新完成计数和 LSU 元数据。
4. ROB read window 观察头部三项。`rob_rt` 把 ROB 元数据、PCFIFO 和完成匹配结果组织为三路 retire entry，并计算 commit 条件。
5. `ct_rtu_retire` 检查 inst0 异常/interrupt/debug/flush；无异常时输出 inst0/1/2 normal retire，按当前 single-retire 策略允许一项或三项。
6. 同一退休事件把三个 PST 类别的 retire valid 和 IID 发回 PST。每个 entry 仅在 IID 相等时进入 retire/release，防止错误路径或同名寄存器提前释放。
7. ROB 根据 retire 脉冲 pop，read pointer 按退休数量前移；commit 脉冲/commit IID 送往 LSU 等消费方。
8. 若发现异常、mispred、debug 或 async exception，retire FSM 选择 IS/FE/BE 组合，冻结相应前端/后端，驱动 ROB/PST/LSU/IFU/IDU 清理和恢复。

## 10. 阅读时应注意的边界

- `rob_retire_instN_vld` 是 ROB read/退休窗口有效，不自动表示该项可写回、可 commit 或不会 flush；要结合 `expt_vld`、debug、flush 和 mask。
- retire inst0 承担全部异常/interrupt/debug 仲裁；inst1/2 只作为顺序退休/统计/分支信息路径。
- PST 的释放由“寄存器类 valid + entry 保存的 IID 匹配”共同决定，不是看到 ROB pop 就释放全部物理寄存器。
- `ct_rtu_pst_vreg_dummy` 是真实使用的 tie-off 变体；顶层实际的实物 vreg 状态表实例名为 `x_ct_rtu_pst_freg`，因此不能仅按注释中的生成实例名判断功能。
- `ct_rtu_compare_iid` 是环形 IID 年龄比较器；在 ROB 回绕后不能用普通 `iid0 < iid1` 替代。
- ROB 完成广播使用 IID 的低 6 bit 选 64 项 entry，但保存和退休比较仍使用完整 7-bit IID；这两个宽度不能混淆。

以上路径覆盖了当前目录中 `ct_rtu_top`、ROB、retire、异常、IID compare、preg/ereg/vreg 状态表以及 encode/expand 辅助模块的实际实例、控制流、握手/有效信号和跨模块回报关系。
