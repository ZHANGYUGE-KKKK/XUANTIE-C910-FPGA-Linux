# C910 SoC FPGA 验证工程

## 项目简介

本工程围绕开源 RISC-V C910 处理器核心开展 FPGA 验证与上板工作
目标是运行Coremark_Pro裸机测试程序用于测试不同L2CACHE大小的性能表现
主要测试L2CACHE被配置为：1MB & 512KB & 256KB 情况下的性能表现。
输出结果通过串口打印，保存位置为：D:\Xilinx_FPGA\C910_SOC_L2CACHE_Coremark_Pro_Test\XUANTIE-C910-FPGA-Linux\MAKEFILE\CoreMark-PRO\RESULTS

本工程的开发板平台有两块，二选其一：AXVU13P & VCU118,可以根据git的分支名确定,当前使用的开发板应该是VCU118。
Z注意，VCU118的复位按键为松开为低、按下为高，与AXVU13P相反

FPGA PL端包含以下部分：
1.C910 RTL核心，包含JTAG接口，它只是PL部分一组普通IO口模拟的，名为JTAG的接口，注意区分FPGA开发板上的JTAG接口。
2.uart控制器（连接到了开发板上的uart2usb模块上）
3.DDR4控制器（连接到了开发板上的DDR4内存条上）当前分支用的应该是VCU118板载颗粒
2.bootrom,bram,axi总线等例化的IP

## 目录结构

| 目录 | 说明 |
| --- | --- |
| `DATASHEET` | FPGA 开发板 AXVU13P & VCU118 资料， FMC_IO扩展子板资料，FMC_DDR3子板。 |
| `VIVADO` | Vivado 工程目录，包含 Vivado 工程文件、生成文件和外部引入 IP。 |
| `MAKEFILE` | 裸机程序构建与镜像生成流程，包含 RISC-V GCC 工具链管理，以及生成 Vivado BRAM 初始化文件的自动化脚本。 |
| `JTAG` | C910 FPGA部分JTAG的用户手册及debugserver，不是开发板的JTAG！ |



## 维护约束

- 保持根目录清晰、可读、独立。
- 不要将临时文件、生成文件或未分类资料直接放在根目录。临时文件使用完后，如无保留的必要，则需要清理
- 新增内容应优先归入已有功能目录；确需新增目录时，应保持命名清晰、职责单一。
- 各模块之间应保持低耦合，避免无必要的跨目录依赖。
