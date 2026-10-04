# 上游来源

- 官方仓库：https://github.com/eembc/coremark-pro
- 固定版本：`4832cc67b0926c7a80a4b7ce0ce00f4640ea6bec`。
- 下载日期：2026-10-03，GitHub `main` 分支 ZIP；版本号取自 ZIP 的 GitHub archive comment。
- ZIP SHA-256：`E4CF0073A41ED34E60680D1F305D0DD1FCBEAE12F400373C24EC86E9E8BE7DEC`。
- 全部 473 个原始文件保留在 `vendor/coremark-pro-main/`，没有修改算法、数据集或 MITH 源文件。
- `vendor.sha256.csv` 从原始 ZIP 的文件内容生成，并与解压后的文件逐一比对。每次构建自动校验。

本地新增代码在 `port/`：C910 启动、UART、计时、newlib 系统调用和 MITH 抽象层。
`port/fp_port.c` 保留上游 `mith/al/src/th_al.c` 的浮点数据转换实现及版权声明。
链接器 `--wrap=mith_main` 观察官方失败计数；仅编译 workload 入口时重命名 `main`，原文件不改。

完整套件将九组 workload、MITH/AL 和 newlib/libm/libgcc 各自部分链接，给每组符号添加私有命名空间，
再合成一个 DDR ELF。新增控制器按普通函数调用 ABI 顺序运行九项，保留各项的原始输入和浮点宏；
各项拥有独立的数据和堆，控制器统一初始化硬件并汇总串口结果。
这些入口和链接包装均在本地适配及构建脚本中实现，没有编辑 `vendor/` 的原始文件，
原 `vendor.sha256.csv` 源码完整性清单继续适用。

许可证及上游声明原样保留在 `vendor/coremark-pro-main/LICENSE.md`，以及各原始文件中。
此移植用于本工程的性能研究；汇总脚本采用上游归一化公式，不代表 EEMBC 认证结果。
