# 先连接 DebugServer，例如：
# target remote 198.18.0.1:1234

# 将最小设备树写入 DDR。
restore D:/Xilinx_FPGA/C910_SOC/MAKEFILE/LINUX_BOOT/BUILD/c910_soc_minimal.dtb binary 0x0210000000

# 将 OpenSBI fw_jump ELF 写入 DDR。
load D:/Xilinx_FPGA/C910_SOC/MAKEFILE/LINUX_BOOT/BUILD/opensbi/platform/generic/firmware/fw_jump.elf

# 如果 load 后 PC 被改写，需要从 BRAM/build/bram.dump 确认 ebreak 后一条指令地址。
# set $pc = <ebreak_next_pc>
# continue
