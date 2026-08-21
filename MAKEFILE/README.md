# Linux Boot 方案规划

## 1. 目标

本目录用于规划和后续承载 C910 SoC 的 Linux 启动链路适配工作。

当前阶段的目标是：

```text
BootROM -> BRAM 跳转程序 -> JTAG 写入 DDR 镜像 -> OpenSBI -> U-Boot -> Linux Kernel
```

最终观察目标是 Linux 串口启动日志输出。

## 2. To-do List

### 2.1 验证 DDR 取指执行能力

状态：

```text
代码已完成，已上板验证
```

目标：

```text
验证 C910 不仅能读写 DDR，还能从 DDR 取指并执行代码。
```

原因：

```text
当前工程已经验证 JTAG 可写 DDR、C910 可从 DDR 读数据。
但 Linux boot 的前提是 BRAM stub 能跳到 DDR，随后 CPU 从 DDR 中取指执行 OpenSBI。
因此必须先单独验证 DDR execute 路径。
```

计划新增内容：

```text
LINUX_BOOT/BRAM/
  start.S
  main.c
  bram.ld

LINUX_BOOT/JTAG/
  ddr_exec_payload.S
  ddr_exec_payload.ld
  Makefile
  load_ddr_exec.gdb
```

执行流程：

```text
1. BootROM 从 0x00000000 启动
2. BootROM 跳到 0x00010000
3. BRAM stub 初始化栈和 BSS
4. BRAM stub 等待 DDR 初始化
5. BRAM stub 通过 UART 输出状态
6. BRAM stub 执行 ebreak，等待 GDB 接管
7. GDB 将 DDR payload 写入 0x0200000000
8. GDB 设置 PC 到 ebreak 后一条指令并 continue
9. BRAM stub 跳转到 0x0200000000
10. DDR payload 通过 UART 输出成功标记
```

通过标准：

```text
串口能依次看到 BRAM stub 状态输出和 DDR payload 输出，例如：

BRAM_STUB_READY
DDR_EXEC_OK
```

该步骤完成后，才能进入 OpenSBI 适配。

### 2.2 建立 Linux Boot 固定地址规划

状态：

```text
代码已完成，待 OpenSBI 构建和上板验证
```

目标：

```text
确定 OpenSBI、U-Boot、Linux Image、DTB、initramfs 在 DDR 中的加载地址。
```

计划内容：

```text
1. 根据 DDR 基地址 0x0200000000 规划各镜像地址
2. 预留足够间隔，避免镜像互相覆盖
3. 将地址集中写入 README 和后续 GDB 脚本
4. 避免在多个源码文件中重复散落硬编码
```

初始规划：

```text
OpenSBI    : 0x0200000000
U-Boot     : 0x0200200000
Linux Image: 0x0204000000
DTB        : 0x0210000000
initramfs  : 0x0220000000，可选
```

通过标准：

```text
地址规划明确，且每个镜像的最大预期大小不会覆盖下一个镜像区域。
```

### 2.3 准备 OpenSBI 最小启动验证

状态：

```text
代码已完成，待 OpenSBI 构建和上板验证
```

目标：

```text
将 BRAM stub 的 DDR 跳转目标从测试 payload 替换为 OpenSBI。
```

计划内容：

```text
1. 确认 OpenSBI 使用的 platform 配置
2. 确认 OpenSBI 入口地址与 DDR 地址规划一致
3. 通过 GDB 将 OpenSBI 写入 DDR
4. BRAM stub 从 ebreak 恢复后跳转 OpenSBI
5. 观察 UART 是否输出 OpenSBI banner
```

通过标准：

```text
串口出现 OpenSBI 启动输出。
```

注意：

```text
该阶段只验证 OpenSBI 可运行，不要求继续启动 U-Boot。
```

### 2.4 准备设备树初稿

状态：

```text
待完成
```

目标：

```text
为 OpenSBI、U-Boot、Linux Kernel 准备当前 C910 SoC 的 DTS。
```

必须描述的当前硬件：

```text
CPU        : C910 单核 hart0
memory     : DDR，基地址 0x0200000000
serial     : AXI UARTLite，基地址 0x0040000000
chosen     : stdout-path 指向 UART
```

需要进一步确认的硬件：

```text
timer/clocksource
CLINT 或等价定时器
PLIC 或外部中断控制器
UART 中断是否接入
```

通过标准：

```text
DTS 能被 dtc 编译为 DTB，且地址与 Vivado BD 当前地址图一致。
```

### 2.5 验证 OpenSBI 跳转 U-Boot

状态：

```text
待完成
```

目标：

```text
OpenSBI 运行后能进入 U-Boot。
```

计划内容：

```text
1. 构建或准备 U-Boot ELF/bin
2. 通过 GDB 将 U-Boot 写入规划好的 DDR 地址
3. 配置 OpenSBI next address 指向 U-Boot
4. 配置 OpenSBI next mode 为 S-mode
5. 观察 U-Boot 串口输出
```

通过标准：

```text
串口出现 U-Boot 启动输出，并进入 U-Boot 命令行或启动流程。
```

### 2.6 验证 U-Boot 加载 Linux Image 和 DTB

状态：

```text
待完成
```

目标：

```text
U-Boot 使用 DDR 中已有的 Linux Image 和 DTB 启动内核。
```

计划内容：

```text
1. 通过 GDB 将 Linux Image 写入 DDR
2. 通过 GDB 将 DTB 写入 DDR
3. 在 U-Boot 中设置 bootargs
4. 在 U-Boot 中执行 booti
5. 观察 Linux early boot 输出
```

通过标准：

```text
串口出现 Linux Kernel early boot log。
```

### 2.7 补齐 Linux 正常运行所需外设

状态：

```text
待完成
```

目标：

```text
在 early boot log 的基础上，继续推进到 Linux 稳定运行。
```

可能需要补齐：

```text
1. timer/clocksource
2. CLINT 或等价定时器映射
3. PLIC 或外部中断控制器
4. UART 中断或轮询 console 策略
5. rootfs/initramfs
6. Linux 驱动和设备树兼容字符串
```

通过标准：

```text
Linux 能完成基本启动流程，并进入 shell 或明确的 initramfs/init 阶段。
```

## 3. 核心约束

Linux 启动相关的大镜像不应直接转换为 Vivado BRAM 初始化文件。

也就是说，以下文件不应作为 COE/MIF 固化进 FPGA bitstream：

```text
OpenSBI
U-Boot
Linux Image
DTB
initramfs
rootfs
```

原因是这些镜像体积较大，若每次修改镜像都重新生成 BRAM 初始化文件并更新 Vivado 工程，会显著增加 Vivado 综合、实现或 bitstream 更新耗时。

FPGA 中应固化的内容只保留极小的启动代码：

```text
BootROM : 从 0x00000000 跳转到 0x00010000
BRAM    : Linux boot stub，负责等待 DDR、进入调试停机点、跳转到 DDR 入口
```

后续 OpenSBI、U-Boot、Linux Kernel、设备树等大镜像均通过 JTAG/DebugServer/GDB 写入 DDR。

## 4. 当前工程依据

当前工程已经验证过以下基础链路：

| 项目 | 当前状态 |
| --- | --- |
| BootROM | 固定链接到 `0x00000000`，跳转到 `0x00010000` |
| BRAM | 固定链接到 `0x00010000`，大小 64KB |
| UART Lite | 基地址 `0x0040000000`，裸机串口输出已验证 |
| DDR4 | 基地址 `0x0200000000`，大小 8GB，读写回环已验证 |
| JTAG 写 DDR | 已通过 DebugServer/GDB 将 ELF payload 写入 DDR 并由 C910 读回 |

因此 Linux boot 的第一版实现应复用已有路径：

```text
小程序固化到 BRAM，大文件通过 JTAG 写 DDR。
```

## 5. BRAM Boot Stub 职责

Linux boot stub 应保持很小，职责单一：

```text
1. 初始化栈和 BSS
2. 等待 DDR 初始化完成
3. 通过 UART 输出短状态信息
4. 执行 ebreak，等待 DebugServer/GDB 接管
5. 用户通过 GDB 将 OpenSBI、U-Boot、Linux Image、DTB 等镜像写入 DDR
6. 从 ebreak 后继续执行
7. 设置必要参数并跳转到 DDR 中的 OpenSBI 入口
8. 若跳转失败，进入 wfi 死循环
```

第一版建议采用手动模式：

```text
BRAM stub 执行 ebreak 停住 CPU
用户手动通过 GDB 写 DDR
用户手动设置 PC 到 ebreak 后一条指令
用户 continue
BRAM stub 跳转 OpenSBI
```

这样与当前 `DDR_JTAG` 实验流程一致，便于定位问题。

后续如有需要，可以扩展为自动模式：

```text
BRAM stub 轮询某个 DDR/BRAM flag
GDB 写完镜像后修改 flag
stub 检测到 flag 后自动跳转
```

## 6. DDR 镜像地址规划

以下为初始规划地址，后续应根据实际镜像大小调整。

| 镜像 | 建议地址 | 说明 |
| --- | --- | --- |
| OpenSBI | `0x0200000000` | BRAM stub 首先跳转的入口 |
| U-Boot | `0x0200200000` | 可由 OpenSBI 跳转或作为 payload |
| Linux Image | `0x0204000000` | U-Boot 启动内核时使用 |
| DTB | `0x0210000000` | 设备树二进制 |
| initramfs | `0x0220000000` | 可选 |

地址规划应集中维护，避免在 BRAM stub、GDB 脚本、U-Boot 环境、设备树说明中各自硬编码不同值。

## 7. JTAG 加载方式

### 7.1 ELF 镜像

对于带有正确 load segment 地址的 ELF，可使用：

```gdb
load path/to/image.elf
```

适合对象：

```text
OpenSBI ELF
U-Boot ELF
专用 DDR payload ELF
```

### 7.2 裸二进制镜像

对于 Linux Image、DTB、initramfs 等裸二进制文件，应使用：

```gdb
restore path/to/Image binary 0x0204000000
restore path/to/c910_soc.dtb binary 0x0210000000
restore path/to/initramfs.cpio.gz binary 0x0220000000
```

### 7.3 手动继续运行

如果 BRAM stub 停在 `ebreak`，写入 DDR 后需要将 PC 设置到 `ebreak` 后一条指令，再继续执行。

示例：

```gdb
set $pc = 0x10048
continue
```

具体地址必须以最新生成的 BRAM 反汇编文件为准，不能固定沿用旧值。

## 8. 建议目录结构

后续可在本目录下按需新增：

```text
LINUX_BOOT/
  README.md
  BRAM/
    start.S
    main.c
    bram.ld
  JTAG/
    load_linux.gdb
  DTS/
    c910_soc.dts
  IMAGES/
    .gitignore
  BUILD/
```

说明：

```text
BRAM  : 只放小型 boot stub
JTAG  : 放 GDB 加载脚本
DTS   : 放设备树源文件
IMAGES: 可作为本地镜像放置目录，但大镜像不建议提交到 git
BUILD : 放本目录构建产物
```

目录名后续可根据工程现有命名风格调整，但职责应保持清晰、低耦合。

## 9. 启动验证顺序

建议按以下顺序逐步验证：

```text
1. BRAM stub 能从 0x00010000 启动，并通过 UART 输出状态
2. BRAM stub 能稳定执行 ebreak，DebugServer/GDB 可接管
3. GDB 可将测试 payload 写入 DDR，stub 可跳转到 DDR 执行
4. GDB 写入 OpenSBI，stub 跳转后可看到 OpenSBI 串口输出
5. OpenSBI 跳转 U-Boot，可看到 U-Boot 串口输出
6. U-Boot 使用 DDR 中的 Linux Image 和 DTB 启动内核
7. Linux 输出 early boot 串口日志
```

每一步只验证一个新增条件，避免同时引入多个不确定因素。

## 10. 关键风险

当前 C910 wrapper 中已有 `pad_cpu_sys_cnt` 输入，但 PLIC 外部中断输入当前固定为 0：

```verilog
.pad_cpu_sys_cnt  (sys_cnt)
.pad_plic_int_cfg (144'b0)
.pad_plic_int_vld (144'b0)
```

这意味着第一阶段应优先追求：

```text
OpenSBI 输出
U-Boot 输出
Linux early serial log
```

若要 Linux 稳定进入 shell，后续大概率还需要继续确认或补齐：

```text
1. C910 可用 timer/clocksource 的设备树描述
2. CLINT 或等价定时器是否可通过当前 SoC 暴露
3. PLIC 或外部中断控制器是否需要接入
4. UART 中断是否必须启用，或是否可以先采用轮询/earlycon
5. rootfs/initramfs 加载方式
```

这些内容不应在第一版 BRAM stub 中一次性假设完成，应逐项验证。
