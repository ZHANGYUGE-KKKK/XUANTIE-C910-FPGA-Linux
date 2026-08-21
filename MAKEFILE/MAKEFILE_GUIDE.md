# MAKEFILE 目录规范

## 1. 目标

本文档用于约束 `MAKEFILE` 目录下后续实验、任务和启动流程的文件组织方式。

所有新增任务应优先复用当前顶层 Makefile：

```text
MAKEFILE/Makefile
```

不要为每个任务重复实现一套 BootROM/BRAM 构建流程，除非该任务确实不符合现有结构。

## 2. 标准构建命令

在工程根目录执行：

```powershell
make -f MAKEFILE\Makefile <任务目录名>
```

示例：

```powershell
make -f MAKEFILE\Makefile UART
make -f MAKEFILE\Makefile DDR
make -f MAKEFILE\Makefile DDR_JTAG
make -f MAKEFILE\Makefile LINUX_DDR_execute
```

如果当前目录已经切换到 `MAKEFILE`，也可以执行：

```powershell
make <任务目录名>
```

## 3. 标准任务目录结构

每个可由顶层 Makefile 管理的任务目录，应放在 `MAKEFILE` 目录下。

标准结构如下：

```text
MAKEFILE/
  <任务目录名>/
    BOOTROM/
      bootrom.s
      bootrom.ld
    BRAM/
      start.S
      main.c
      bram.ld
    JTAG/
      Makefile
      <payload>.S
      <payload>.ld
      <load_script>.gdb
```

其中 `JTAG` 目录是可选的。只有任务需要额外的 JTAG/GDB 操作脚本或独立 payload 时才添加。

## 4. 子工程独立性约定

`MAKEFILE` 下每个任务目录都应保持源码和脚本层面的独立性。

允许共享的公共内容只有：

```text
MAKEFILE/Makefile
MAKEFILE/Xuantie-900-gcc-elf-newlib-mingw-V3.2.0/
MAKEFILE/COEFILES/
```

各任务目录之间不应互相引用源码、链接脚本或操作脚本。

例如，`ebreaktest` 不能引用：

```text
MAKEFILE/UART/BOOTROM/bootrom.s
MAKEFILE/UART/BRAM/start.S
MAKEFILE/DDR_JTAG/BRAM/main.c
```

即使某些文件内容完全相同，也应复制到当前任务目录中：

```text
MAKEFILE/ebreaktest/BOOTROM/bootrom.s
MAKEFILE/ebreaktest/BOOTROM/bootrom.ld
MAKEFILE/ebreaktest/BRAM/start.S
MAKEFILE/ebreaktest/BRAM/main.c
MAKEFILE/ebreaktest/BRAM/bram.ld
```

这样每个任务目录都可以独立阅读、独立维护，避免后续修改某个实验时影响其他实验。

## 5. 必须保持的文件名

为了复用顶层 Makefile，以下文件名和目录名必须保持一致：

```text
BOOTROM/bootrom.s
BOOTROM/bootrom.ld
BRAM/start.S
BRAM/main.c
BRAM/bram.ld
```

不要在新任务中自行改成其他入口名，例如：

```text
boot.S
link.ld
main_bram.c
startup.S
```

如确实需要多个源码文件，应先确认顶层 Makefile 是否需要扩展；不要在任务目录中私自绕开统一构建入口。

## 6. BootROM 约定

当前工程的 BootROM 约定如下：

| 项目 | 约定 |
| --- | --- |
| 链接地址 | `0x00000000` |
| 镜像大小 | 4KB |
| 入口符号 | `_start` |
| 主要职责 | 设置基础 trap 向量，然后跳转到 BRAM |
| BRAM 跳转地址 | `0x00010000` |

BootROM 应保持极简，不应放入复杂业务逻辑或大型初始化流程。

## 7. BRAM 约定

当前工程的 BRAM 约定如下：

| 项目 | 约定 |
| --- | --- |
| 链接地址 | `0x00010000` |
| 镜像大小 | 64KB |
| 入口符号 | `_start` |
| 启动文件 | `BRAM/start.S` |
| 主程序 | `BRAM/main.c` |
| 链接脚本 | `BRAM/bram.ld` |

`start.S` 通常负责：

```text
1. 设置栈
2. 清零 BSS
3. 调用 main
4. main 返回后进入 wfi 死循环
```

`main.c` 只实现当前任务需要验证的最小逻辑，避免引入无关模块。

## 8. JTAG 目录约定

如果任务需要通过 DebugServer/GDB 向 DDR 或其他地址写入 payload，可添加：

```text
JTAG/
  Makefile
  <payload>.S
  <payload>.ld
  <load_script>.gdb
```

`JTAG/Makefile` 由该任务自行管理 payload 构建，但应复用工程内工具链路径：

```text
MAKEFILE/Xuantie-900-gcc-elf-newlib-mingw-V3.2.0/bin
```

顶层 Makefile 默认不会构建 JTAG payload。需要构建时，应显式调用：

```powershell
make -f MAKEFILE\Makefile PROGRAM=<任务目录名> jtag
```

显式调用时，顶层 Makefile 会检查以下文件：

```text
<任务目录名>/JTAG/Makefile
```

如果任务没有 `JTAG/Makefile`，`jtag` 目标会跳过 JTAG 构建。

## 9. 构建产物约定

各任务自己的构建产物应放在对应子目录的 `build` 目录中：

```text
BOOTROM/build/
BRAM/build/
JTAG/build/
```

默认构建只处理 BootROM 和 BRAM。顶层 Makefile 会将 BootROM 和 BRAM 的构建结果同步到统一输出目录：

```text
MAKEFILE/COEFILES/build_bootrom/
MAKEFILE/COEFILES/build_ram/
```

Vivado 当前使用的 BRAM 初始化文件应优先从统一输出目录获取：

```text
MAKEFILE/COEFILES/build_bootrom/bootrom.coe
MAKEFILE/COEFILES/build_ram/bram.coe
```

## 10. 地址约定

当前工程常用地址如下：

| 模块 | 地址/范围 |
| --- | --- |
| BootROM | `0x00000000`，4KB |
| BRAM | `0x00010000`，64KB |
| UART Lite | `0x40000000` |
| DDR4 | `0x0200000000`，8GB |

新增任务应优先复用这些地址。

如确实需要新增地址或修改地址，应先确认 Vivado BD 地址图，并在任务 README 中明确说明。

## 11. 命名规范

任务目录名应清晰表达实验目标。

推荐格式：

```text
UART
DDR
DDR_JTAG
LINUX_DDR_execute
```

避免使用含义不清的目录名，例如：

```text
test
new
demo2
tmp
```

目录名一旦被 README、脚本或操作文档引用，不应随意改名。

## 12. 新增任务流程

新增一个可复用顶层 Makefile 的任务时，建议按以下步骤：

```text
1. 在 MAKEFILE 下创建任务目录
2. 创建 BOOTROM/bootrom.s 和 BOOTROM/bootrom.ld
3. 创建 BRAM/start.S、BRAM/main.c 和 BRAM/bram.ld
4. 如需要 JTAG payload，再创建 JTAG/Makefile 和相关 payload 文件
5. 确认上述源码和链接脚本均来自当前任务目录，不跨引用其他任务目录
6. 在任务 README 中说明目标、地址、构建命令、上板步骤和预期输出
7. 使用 make -f MAKEFILE\Makefile <任务目录名> 构建
8. 检查 build 产物和 COEFILES 同步结果
```

## 13. 修改约束

新增任务时应保持低侵入：

```text
1. 优先新增任务目录，不直接修改已有任务目录
2. 不随意改动顶层 Makefile 的公共变量和默认地址
3. 不将临时文件、大镜像或未分类资料放在 MAKEFILE 根目录
4. 不将 Linux Image、rootfs、initramfs 等大文件转换为 COE/MIF 固化进 FPGA
5. 需要大镜像时，优先通过 JTAG/GDB 写入 DDR
6. 不跨任务目录引用 BootROM、BRAM、JTAG 源码或链接脚本
```

如果确实需要修改顶层 Makefile，应确保已有任务仍可按原命令构建：

```text
UART
DDR
DDR_JTAG
LINUX_DDR_execute
```

## 14. 清理约定

顶层清理命令：

```powershell
make -f MAKEFILE\Makefile PROGRAM=<任务目录名> clean
```

或在 `MAKEFILE` 目录内执行：

```powershell
make PROGRAM=<任务目录名> clean
```

清理操作只应删除对应任务目录下的构建产物，不应删除源码、README、脚本或 Vivado 工程文件。
