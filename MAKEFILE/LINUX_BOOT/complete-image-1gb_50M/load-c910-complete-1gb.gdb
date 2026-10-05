set confirm off

printf "Loading C910 FPGA 1 GiB DDR image set...\n"
restore opensbi-c910-fpga-fw_jump.bin binary 0x200000000
restore u-boot-c910-soc-minimal.bin binary 0x200200000
restore linux-c910-fpga-Image.bin binary 0x200600000
restore rootfs-c910-lite.cpio.gz binary 0x204000000
restore c910-soc-system-1gb.dtb binary 0x210000000

# All addresses are identical to the 8 GiB image set. Only the DTB memory
# size and U-Boot control DTB have changed to 1 GiB.
set $a0 = 0
set $a1 = 0x210000000
set $pc = 0x200000000

printf "OpenSBI entry instructions:\n"
x/4i $pc
printf "1 GiB system DTB magic (expected 0xedfe0dd0):\n"
x/4wx 0x210000000
printf "Starting OpenSBI at 0x200000000.\n"
continue
