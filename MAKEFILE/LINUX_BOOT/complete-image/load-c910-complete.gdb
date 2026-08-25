set confirm off

printf "Loading C910 FPGA complete image into DDR...\n"
restore opensbi-c910-fpga-fw_jump.bin binary 0x200000000
restore u-boot-c910-soc-minimal.bin binary 0x200200000
restore linux-c910-fpga-Image.bin binary 0x200600000
restore rootfs-c910-lite.cpio.gz binary 0x204000000
restore c910-soc-system.dtb binary 0x210000000

# OpenSBI entry arguments: hartid=0, system FDT=0x210000000.
# OpenSBI clears C910 MXSTATUS/SXSTATUS MAEE before entering U-Boot.
set $a0 = 0
set $a1 = 0x210000000
set $pc = 0x200000000

printf "OpenSBI entry instructions:\n"
x/4i $pc
printf "System DTB magic (expected little-endian 0xedfe0dd0):\n"
x/4wx 0x210000000
printf "Starting OpenSBI at 0x200000000; no manual MAEE write is required.\n"
continue
