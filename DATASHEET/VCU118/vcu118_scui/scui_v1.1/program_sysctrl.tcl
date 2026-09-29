open_hw
catch {disconnect_hw_server localhost:3121}
connect_hw_server -url localhost:3121
current_hw_target [get_hw_targets */xilinx_tcf/Xilinx/*]
set_property PARAM.FREQUENCY 6000000 [get_hw_targets */xilinx_tcf/Xilinx/*]
open_hw_target
current_hw_device [get_hw_devices xc7z010_1]
refresh_hw_device -update_hw_probes false [lindex [get_hw_devices xc7z010_1] 0]
create_hw_cfgmem -hw_device [lindex [get_hw_devices xc7z010_1] 0] [lindex [get_cfgmem_parts {mt25qu128-qspi-x4-single}] 0]
set_property PROGRAM.BLANK_CHECK  0 [ get_property PROGRAM.HW_CFGMEM [lindex [get_hw_devices xc7z010_1] 0]]
set_property PROGRAM.ERASE  1 [ get_property PROGRAM.HW_CFGMEM [lindex [get_hw_devices xc7z010_1] 0]]
set_property PROGRAM.CFG_PROGRAM  1 [ get_property PROGRAM.HW_CFGMEM [lindex [get_hw_devices xc7z010_1] 0]]
set_property PROGRAM.VERIFY  1 [ get_property PROGRAM.HW_CFGMEM [lindex [get_hw_devices xc7z010_1] 0]]
set_property PROGRAM.CHECKSUM  0 [ get_property PROGRAM.HW_CFGMEM [lindex [get_hw_devices xc7z010_1] 0]]
refresh_hw_device [lindex [get_hw_devices xc7z010_1] 0]
set_property PROGRAM.ADDRESS_RANGE  {entire_device} [ get_property PROGRAM.HW_CFGMEM [lindex [get_hw_devices xc7z010_1] 0]]
set_property PROGRAM.FILES [list "BOOT_v1.00.bin" ] [ get_property PROGRAM.HW_CFGMEM [lindex [get_hw_devices xc7z010_1] 0]]
set_property PROGRAM.ZYNQ_FSBL [list zynq_fsbl.elf] [ get_property PROGRAM.HW_CFGMEM [lindex [get_hw_devices xc7z010_1] 0]]
set_property PROGRAM.BLANK_CHECK  0 [ get_property PROGRAM.HW_CFGMEM [lindex [get_hw_devices xc7z010_1] 0]]
set_property PROGRAM.ERASE  1 [ get_property PROGRAM.HW_CFGMEM [lindex [get_hw_devices xc7z010_1] 0]]
set_property PROGRAM.CFG_PROGRAM  1 [ get_property PROGRAM.HW_CFGMEM [lindex [get_hw_devices xc7z010_1] 0]]
set_property PROGRAM.VERIFY  1 [ get_property PROGRAM.HW_CFGMEM [lindex [get_hw_devices xc7z010_1] 0]]
set_property PROGRAM.CHECKSUM  0 [ get_property PROGRAM.HW_CFGMEM [lindex [get_hw_devices xc7z010_1] 0]]
program_hw_cfgmem -hw_cfgmem [ get_property PROGRAM.HW_CFGMEM [lindex [get_hw_devices xc7z010_1] 0]]
close_hw_target [current_hw_target [get_hw_targets]]
disconnect_hw_server localhost:3121
close_hw
