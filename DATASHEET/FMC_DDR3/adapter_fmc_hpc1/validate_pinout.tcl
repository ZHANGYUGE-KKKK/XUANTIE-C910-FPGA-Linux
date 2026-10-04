# Run Vivado batch with -tclargs <absolute output-directory> [isolated_250].
# Default uses the current project's real MIG OOC checkpoint.
# isolated_250 creates ONLY a temporary standalone MIG, not an edit to the SoC.
set_param general.maxThreads 1
set adapter_dir [file dirname [file normalize [info script]]]
set repo_dir [file normalize [file join $adapter_dir ../../..]]
set soc_dir [file join $repo_dir VIVADO C910_SOC]
if {$argc < 1 || $argc > 2} { error "Usage: -tclargs <output-directory> [isolated_250]" }
set check_dir [file normalize [lindex $argv 0]]
file mkdir $check_dir
create_project -in_memory -part xcvu9p-flga2104-2L-e
set gen_dir [file join $soc_dir C910_SOC.gen sources_1 bd C910_SOC ip C910_SOC_ddr3_0_0_1]
set mig_dcp [file join $soc_dir C910_SOC.runs C910_SOC_ddr3_0_0_synth_1 C910_SOC_ddr3_0_0.dcp]
if {$argc == 2} {
  if {[lindex $argv 1] ne "isolated_250"} { error "Unknown validation mode" }
  set copied_ip_dir [file join $check_dir isolated_ip]
  file mkdir $copied_ip_dir
  set standalone_xci [file join $copied_ip_dir C910_SOC_ddr3_0_0 C910_SOC_ddr3_0_0.xci]
  set mig_dcp [file join $copied_ip_dir C910_SOC_ddr3_0_0 C910_SOC_ddr3_0_0.dcp]
  if {[file exists $standalone_xci]} {
    read_ip $standalone_xci
  } else {
    create_ip -name ddr3 -vendor xilinx.com -library ip -version 1.4 -module_name C910_SOC_ddr3_0_0 -dir $copied_ip_dir
  }
  set_property -dict [list \
    CONFIG.C0.DDR3_MemoryPart MT41K512M16HA-125 \
    CONFIG.C0.DDR3_MemoryType Components \
    CONFIG.C0.DDR3_MemoryVoltage 1.5V \
    CONFIG.C0.DDR3_DataWidth 16 \
    CONFIG.C0.DDR3_TimePeriod 1250 \
    CONFIG.C0.DDR3_InputClockPeriod 4000 \
    CONFIG.C0.DDR3_AxiSelection true \
    CONFIG.C0.DDR3_AxiDataWidth 128 \
    CONFIG.C0.DDR3_AxiAddressWidth 30 \
    CONFIG.C0.DDR3_AxiIDWidth 1 \
    CONFIG.C0.DDR3_AxiArbitrationScheme RD_PRI_REG \
    CONFIG.C0.DDR3_AxiNarrowBurst false \
    CONFIG.C0.DDR3_ChipSelect true \
    CONFIG.C0.DDR3_DataMask true \
    CONFIG.C0.DDR3_Slot Single \
    CONFIG.C0.DDR3_Mem_Add_Map ROW_COLUMN_BANK \
    CONFIG.System_Clock No_Buffer \
    CONFIG.Internal_Vref true \
    CONFIG.Debug_Signal Disable] [get_ips C910_SOC_ddr3_0_0]
  generate_target all [get_ips C910_SOC_ddr3_0_0]
  if {![file exists $mig_dcp]} { synth_ip [get_ips C910_SOC_ddr3_0_0] }
  puts "ADAPTER_VALIDATION_MODE isolated_250_original_project_unchanged"
} else {
  read_verilog [file join $gen_dir C910_SOC_ddr3_0_0_stub.v]
  puts "ADAPTER_VALIDATION_MODE current_project"
}
read_verilog [file join $adapter_dir validate_pinout_top.v]
synth_design -top validate_pinout_top -part xcvu9p-flga2104-2L-e -no_iobuf
# Standalone IP is automatically stitched by synth_design; default stub is not.
if {$argc == 1} { read_checkpoint -cell DDR3 $mig_dcp }
read_xdc [file join $soc_dir C910_SOC.srcs constrs_1 new VCU118.xdc]
puts "ADAPTER_BOUND_DDR_PORTS [llength [get_ports C0_DDR3_0_*]]"
foreach check_port [lsort [get_ports C0_DDR3_0_*]] {
  puts "ADAPTER_PIN $check_port [get_property PACKAGE_PIN $check_port] [get_property IOSTANDARD $check_port]"
}
foreach check_bank {66 67 71} {
  puts "ADAPTER_BANK $check_bank SLR=[get_property SLR_INDEX [get_iobanks $check_bank]]"
}
report_io -file [file join $check_dir io.rpt]
report_drc -file [file join $check_dir drc_pre_opt.rpt]
set check_rc [catch {opt_design} check_msg]
puts "ADAPTER_OPT_RESULT $check_rc $check_msg"
if {$check_rc} {
  report_drc -file [file join $check_dir drc_failed_opt.rpt]
  exit 1
}
set check_rc [catch {place_design} check_msg]
puts "ADAPTER_PLACE_RESULT $check_rc $check_msg"
report_drc -file [file join $check_dir drc_post_place.rpt]
write_checkpoint -force [file join $check_dir pincheck.dcp]
if {$check_rc} { exit 1 }
set check_rc [catch {route_design} check_msg]
puts "ADAPTER_ROUTE_RESULT $check_rc $check_msg"
report_drc -file [file join $check_dir drc_post_route.rpt]
report_timing_summary -file [file join $check_dir timing_post_route.rpt]
report_io -file [file join $check_dir io_post_route.rpt]
report_route_status -file [file join $check_dir route_status.rpt]
write_checkpoint -force [file join $check_dir pincheck_routed.dcp]
if {$check_rc} { exit 1 }
report_drc -ruledeck bitstream_checks -file [file join $check_dir drc_bitstream.rpt]
set drc_fatal_count 0
foreach drc_item [get_drc_violations -quiet] {
  set drc_level [get_property SEVERITY $drc_item]
  if {$drc_level eq "Error" || $drc_level eq "Critical Warning"} {
    incr drc_fatal_count
    puts "ADAPTER_DRC_FATAL $drc_item $drc_level"
  }
}
puts "ADAPTER_BITSTREAM_DRC_FATAL_COUNT $drc_fatal_count"
if {$drc_fatal_count} { exit 1 }
puts "ADAPTER_FINISHED"
exit
