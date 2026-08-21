# ebreaktest 实验

## 1. 目标

本实验用于验证 C910 的 `ebreak` 调试停机点是否能被 DebugServer/GDB 正确接管，并在执行 `continue` 后继续运行。

## 2. 构建

在工程根目录执行：

```powershell
make -f MAKEFILE\Makefile ebreaktest
```

## 3. 上板流程

1. 使用生成的 BootROM/BRAM COE 更新 Vivado BRAM 初始化文件。
2. 重新生成 bitstream 并烧写 FPGA。
3. 打开串口终端。
4. 启动 DebugServer 并连接 GDB。
5. 程序在 `ebreak` 停住后，在 GDB 中执行：

```gdb
continue
```

当前构建中：

```text
ebreak 地址       = 0x10064
ebreak 后一条地址 = 0x10066
```

如果重新编译过，以 `BRAM/build/bram.dump` 中的实际地址为准。

## 4. 预期输出

执行到 `ebreak` 前，串口输出：

```text
12345,ebreak test,start
```

GDB 执行 `continue` 后，串口继续输出：

```text
78910,ebreak continue
```
