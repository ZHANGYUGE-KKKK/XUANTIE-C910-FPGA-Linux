# 先连接 DebugServer，例如：
# target remote 198.18.0.1:1234
#
# BRAM stub 停在 ebreak 后，加载 DDR 执行载荷。
load D:/Xilinx_FPGA/C910_SOC/MAKEFILE/LINUX_DDR_execute/JTAG/build/ddr_exec_payload.elf
#
# 如果 load 后 PC 被改写，需要从 BRAM/build/bram.dump 确认 ebreak 后一条指令地址。
# 当前构建中 ebreak 地址为 0x10074，后一条指令地址为 0x10076：
# set $pc = 0x10076
# continue
