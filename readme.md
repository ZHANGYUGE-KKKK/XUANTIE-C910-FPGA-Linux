# C910 SoC FPGA 验证工程

## 项目简介

本工程围绕开源 RISC-V C910 处理器核心开展 FPGA 验证与上板工作，目标是在 FPGA 上实现完整的 SoC 系统，并最终运行 Linux 系统。
FPGA PL端包含以下部分：
1.C910 RTL核心，包含JTAG接口，它只是PL部分一组普通IO口模拟的，名为JTAG的接口，注意区分FPGA开发板上的JTAG接口。
2.uart控制器（连接到了开发板上的uart2usb模块上）
3.DDR4控制器（连接到了开发板上的DDR4内存条上）
2.bootrom,bram,axi总线等例化的IP

## 目录结构

| 目录 | 说明 |
| --- | --- |
| `DATASHEET` | FPGA 开发板 AXVU13P 资料，以及 FMC 子板资料。 |
| `VIVADO` | Vivado 工程目录，包含 Vivado 工程文件、生成文件和外部引入 IP。 |
| `MAKEFILE` | 裸机程序构建与镜像生成流程，包含 RISC-V GCC 工具链管理，以及生成 Vivado BRAM 初始化文件的自动化脚本。 |
| `JTAG` | C910 FPGA部分JTAG的用户手册及debugserver，不是开发板的JTAG！ |

## TODOLIST

| 状态 | 说明 |
| --- | --- |
| `已完成` | 将C910 RTL顶层裁剪为单核设计。 |
| `已完成` | 搭建最小系统，裸机下验证uart控制器正确性，通过串口打印helloworld。 |
| `已完成` | 添加DDR4控制器，验证DDR读写回环测试。 |
| `已完成` | 验证C910 JTAG接口，使用debugserver修改bram程序，复位运行查看结果。 |
| `已完成` | 使用ebreak停止核心并使用debugserver修改DDR数据，设置PC地址跳转串口打印修改内容。 |
| `已完成` | 搭建linux系统,完成OpenSBI、U-Boot、Linux Kernel、设备树的启动链路适配，最终实现 Linux 串口启动日志输出|

## 维护约束

- 保持根目录清晰、可读、独立。
- 不要将临时文件、生成文件或未分类资料直接放在根目录。临时文件使用完后，如无保留的必要，则需要清理
- 新增内容应优先归入已有功能目录；确需新增目录时，应保持命名清晰、职责单一。
- 各模块之间应保持低耦合，避免无必要的跨目录依赖。
