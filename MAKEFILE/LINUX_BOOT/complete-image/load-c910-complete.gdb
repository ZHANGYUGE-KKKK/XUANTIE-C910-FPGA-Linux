set confirm off

restore opensbi-c910-fpga-fw_jump.bin binary 0x200000000
restore u-boot-c910-soc-minimal.bin binary 0x200200000
restore linux-c910-fpga-Image.bin binary 0x200600000
restore rootfs-c910-lite.cpio.gz binary 0x204000000
restore c910-soc-system.dtb binary 0x210000000

set $a0 = 0
set $a1 = 0x210000000
set $pc = 0x200000000

x/4i $pc
x/4wx 0x210000000
continue
