## VCU118 Rev2.0 - C910 wrapper / x16 DDR3 on J2 FMC_HPC1.
## This pinout REQUIRES a signal-remapping adapter; it is NOT a straight-through cable.
## Canonical connector mapping: DATASHEET/FMC_DDR3/adapter_fmc_hpc1/pinmap.json
## Carrier VADJ/VCCO and DRAM VDD/VDDQ MUST be 1.5 V; internal VREF = 0.75 V.
## VADJ is shared with other FMC banks: review external JTAG voltage before hardware use.

## Adapter MUST supply a 250 MHz differential reference clock on J2 G6/G7.
## G6/G7 = FMC_HPC1_LA00_CC_P/N = AY9/BA9, Bank 66 / SLR1.
## E12/D12 is in SLR2 and cannot be used as this MIG's direct system clock.
## LVDS receiver, no internal differential termination; fit 100 ohms on adapter.
## MIG reference input must separately be configured for 4000 ps / 250 MHz.
set_property -dict {PACKAGE_PIN AY9 IOSTANDARD LVDS DIFF_TERM_ADV TERM_NONE} [get_ports BADJ_CLK_clk_p]
set_property -dict {PACKAGE_PIN BA9 IOSTANDARD LVDS DIFF_TERM_ADV TERM_NONE} [get_ports BADJ_CLK_clk_n]
create_clock -period 4.000 -name BOARD_SYSCLK_250M [get_ports BADJ_CLK_clk_p]

## Address/control/CK/reset: Bank 66. All DDR address/control stays in one bank.
## DQ[7:0]/DQS0/DM0: Bank 67 T0; DQ[15:8]/DQS1/DM1: Bank 67 T3.
## DQS uses N6/N7; DM uses N0; DQ uses N2/N3/N4/N5/N8/N9/N10/N11.
# FMC_HPC1_LA03_P, J2-G9 -> adapter -> J4-D9; IO_L1P_T0L_N0_DBC_66
set_property PACKAGE_PIN BD12 [get_ports {C0_DDR3_0_addr[0]}]
# FMC_HPC1_LA03_N, J2-G10 -> adapter -> J4-D8; IO_L1N_T0L_N1_DBC_66
set_property PACKAGE_PIN BE12 [get_ports {C0_DDR3_0_addr[1]}]
# FMC_HPC1_LA04_P, J2-H10 -> adapter -> J4-G9; IO_L2P_T0L_N2_66
set_property PACKAGE_PIN BF12 [get_ports {C0_DDR3_0_addr[2]}]
# FMC_HPC1_LA04_N, J2-H11 -> adapter -> J4-G10; IO_L2N_T0L_N3_66
set_property PACKAGE_PIN BF11 [get_ports {C0_DDR3_0_addr[3]}]
# FMC_HPC1_LA02_P, J2-H7 -> adapter -> J4-H14; IO_L3P_T0L_N4_AD15P_66
set_property PACKAGE_PIN BC11 [get_ports {C0_DDR3_0_addr[4]}]
# FMC_HPC1_LA02_N, J2-H8 -> adapter -> J4-H13; IO_L3N_T0L_N5_AD15N_66
set_property PACKAGE_PIN BD11 [get_ports {C0_DDR3_0_addr[5]}]
# FMC_HPC1_LA06_P, J2-C10 -> adapter -> J4-D15; IO_L4P_T0U_N6_DBC_AD7P_66
set_property PACKAGE_PIN BD13 [get_ports {C0_DDR3_0_addr[6]}]
# FMC_HPC1_LA06_N, J2-C11 -> adapter -> J4-D14; IO_L4N_T0U_N7_DBC_AD7N_66
set_property PACKAGE_PIN BE13 [get_ports {C0_DDR3_0_addr[7]}]
# FMC_HPC1_LA05_P, J2-D11 -> adapter -> J4-H7; IO_L5P_T0U_N8_AD14P_66
set_property PACKAGE_PIN BE14 [get_ports {C0_DDR3_0_addr[8]}]
# FMC_HPC1_LA05_N, J2-D12 -> adapter -> J4-H8; IO_L5N_T0U_N9_AD14N_66
set_property PACKAGE_PIN BF14 [get_ports {C0_DDR3_0_addr[9]}]
# FMC_HPC1_LA08_P, J2-G12 -> adapter -> J4-H11; IO_L6P_T0U_N10_AD6P_66
set_property PACKAGE_PIN BE15 [get_ports {C0_DDR3_0_addr[10]}]
# FMC_HPC1_LA08_N, J2-G13 -> adapter -> J4-H10; IO_L6N_T0U_N11_AD6N_66
set_property PACKAGE_PIN BF15 [get_ports {C0_DDR3_0_addr[11]}]
# FMC_HPC1_LA12_P, J2-G15 -> adapter -> J4-C11; IO_L19P_T3L_N0_DBC_AD9P_66
set_property PACKAGE_PIN BC14 [get_ports {C0_DDR3_0_addr[12]}]
# FMC_HPC1_LA12_N, J2-G16 -> adapter -> J4-C10; IO_L19N_T3L_N1_DBC_AD9N_66
set_property PACKAGE_PIN BC13 [get_ports {C0_DDR3_0_addr[13]}]
# FMC_HPC1_LA15_P, J2-H19 -> adapter -> J4-G13; IO_L20P_T3L_N2_AD1P_66
set_property PACKAGE_PIN BB16 [get_ports {C0_DDR3_0_addr[14]}]
# FMC_HPC1_LA15_N, J2-H20 -> adapter -> J4-G12; IO_L20N_T3L_N3_AD1N_66
set_property PACKAGE_PIN BC16 [get_ports {C0_DDR3_0_addr[15]}]
# FMC_HPC1_LA07_P, J2-H13 -> adapter -> J4-C14; IO_L21P_T3L_N4_AD8P_66
set_property PACKAGE_PIN BC15 [get_ports {C0_DDR3_0_ba[0]}]
# FMC_HPC1_LA07_N, J2-H14 -> adapter -> J4-C15; IO_L21N_T3L_N5_AD8N_66
set_property PACKAGE_PIN BD15 [get_ports {C0_DDR3_0_ba[1]}]
# FMC_HPC1_LA11_P, J2-H16 -> adapter -> J4-G16; IO_L22P_T3U_N6_DBC_AD0P_66
set_property PACKAGE_PIN BA16 [get_ports {C0_DDR3_0_ba[2]}]
# FMC_HPC1_LA09_P, J2-D14 -> adapter -> J4-C18; IO_L23P_T3U_N8_66
set_property PACKAGE_PIN BA14 [get_ports {C0_DDR3_0_ras_n}]
# FMC_HPC1_LA11_N, J2-H17 -> adapter -> J4-C19; IO_L22N_T3U_N7_DBC_AD0N_66
set_property PACKAGE_PIN BA15 [get_ports {C0_DDR3_0_cas_n}]
# FMC_HPC1_LA09_N, J2-D15 -> adapter -> J4-G15; IO_L23N_T3U_N9_66
set_property PACKAGE_PIN BB14 [get_ports {C0_DDR3_0_we_n}]
# FMC_HPC1_LA10_P, J2-C14 -> adapter -> J4-G19; IO_L24P_T3U_N10_66
set_property PACKAGE_PIN BB13 [get_ports {C0_DDR3_0_cs_n[0]}]
# FMC_HPC1_LA10_N, J2-C15 -> adapter -> J4-G18; IO_L24N_T3U_N11_66
set_property PACKAGE_PIN BB12 [get_ports {C0_DDR3_0_cke[0]}]
# FMC_HPC1_LA16_P, J2-G18 -> adapter -> J4-G6; IO_L16P_T2U_N6_QBC_AD3P_66
set_property PACKAGE_PIN AV9 [get_ports {C0_DDR3_0_odt[0]}]
# FMC_HPC1_LA16_N, J2-G19 -> adapter -> J4-G7; IO_L16N_T2U_N7_QBC_AD3N_66
set_property PACKAGE_PIN AV8 [get_ports {C0_DDR3_0_reset_n}]
# FMC_HPC1_CLK0_M2C_P, J2-H4 -> adapter -> J4-D11; IO_L12P_T1U_N10_GC_66
set_property PACKAGE_PIN BC9 [get_ports {C0_DDR3_0_ck_p[0]}]
# FMC_HPC1_CLK0_M2C_N, J2-H5 -> adapter -> J4-D12; IO_L12N_T1U_N11_GC_66
set_property PACKAGE_PIN BC8 [get_ports {C0_DDR3_0_ck_n[0]}]
# FMC_HPC1_LA19_P, J2-H22 -> adapter -> J4-G30; IO_L2P_T0L_N2_67
set_property PACKAGE_PIN AW12 [get_ports {C0_DDR3_0_dq[0]}]
# FMC_HPC1_LA19_N, J2-H23 -> adapter -> J4-G31; IO_L2N_T0L_N3_67
set_property PACKAGE_PIN AY12 [get_ports {C0_DDR3_0_dq[1]}]
# FMC_HPC1_LA20_P, J2-G21 -> adapter -> J4-H31; IO_L3P_T0L_N4_AD15P_67
set_property PACKAGE_PIN AW11 [get_ports {C0_DDR3_0_dq[2]}]
# FMC_HPC1_LA20_N, J2-G22 -> adapter -> J4-H32; IO_L3N_T0L_N5_AD15N_67
set_property PACKAGE_PIN AY10 [get_ports {C0_DDR3_0_dq[3]}]
# FMC_HPC1_LA22_P, J2-G24 -> adapter -> J4-G34; IO_L5P_T0U_N8_AD14P_67
set_property PACKAGE_PIN AW13 [get_ports {C0_DDR3_0_dq[4]}]
# FMC_HPC1_LA22_N, J2-G25 -> adapter -> J4-G33; IO_L5N_T0U_N9_AD14N_67
set_property PACKAGE_PIN AY13 [get_ports {C0_DDR3_0_dq[5]}]
# FMC_HPC1_LA21_P, J2-H25 -> adapter -> J4-H34; IO_L6P_T0U_N10_AD6P_67
set_property PACKAGE_PIN AU11 [get_ports {C0_DDR3_0_dq[6]}]
# FMC_HPC1_LA21_N, J2-H26 -> adapter -> J4-H35; IO_L6N_T0U_N11_AD6N_67
set_property PACKAGE_PIN AV11 [get_ports {C0_DDR3_0_dq[7]}]
# FMC_HPC1_LA26_P, J2-D26 -> adapter -> J4-G36; IO_L20P_T3L_N2_AD1P_67
set_property PACKAGE_PIN AK15 [get_ports {C0_DDR3_0_dq[8]}]
# FMC_HPC1_LA26_N, J2-D27 -> adapter -> J4-G37; IO_L20N_T3L_N3_AD1N_67
set_property PACKAGE_PIN AL15 [get_ports {C0_DDR3_0_dq[9]}]
# FMC_HPC1_LA30_P, J2-H34 -> adapter -> J4-H38; IO_L21P_T3L_N4_AD8P_67
set_property PACKAGE_PIN AK12 [get_ports {C0_DDR3_0_dq[10]}]
# FMC_HPC1_LA30_N, J2-H35 -> adapter -> J4-H37; IO_L21N_T3L_N5_AD8N_67
set_property PACKAGE_PIN AL12 [get_ports {C0_DDR3_0_dq[11]}]
# FMC_HPC1_LA31_P, J2-G33 -> adapter -> J4-G22; IO_L23P_T3U_N8_67
set_property PACKAGE_PIN AM13 [get_ports {C0_DDR3_0_dq[12]}]
# FMC_HPC1_LA31_N, J2-G34 -> adapter -> J4-G24; IO_L23N_T3U_N9_67
set_property PACKAGE_PIN AM12 [get_ports {C0_DDR3_0_dq[13]}]
# FMC_HPC1_LA33_P, J2-G36 -> adapter -> J4-G25; IO_L24P_T3U_N10_67
set_property PACKAGE_PIN AK14 [get_ports {C0_DDR3_0_dq[14]}]
# FMC_HPC1_LA33_N, J2-G37 -> adapter -> J4-H29; IO_L24N_T3U_N11_67
set_property PACKAGE_PIN AK13 [get_ports {C0_DDR3_0_dq[15]}]
# FMC_HPC1_LA25_P, J2-G27 -> adapter -> J4-H28; IO_L1P_T0L_N0_DBC_67
set_property PACKAGE_PIN AT12 [get_ports {C0_DDR3_0_dm[0]}]
# FMC_HPC1_LA27_P, J2-C26 -> adapter -> J4-C23; IO_L19P_T3L_N0_DBC_AD9P_67
set_property PACKAGE_PIN AL14 [get_ports {C0_DDR3_0_dm[1]}]
# FMC_HPC1_LA28_P, J2-H31 -> adapter -> J4-D26; IO_L4P_T0U_N6_DBC_AD7P_67
set_property PACKAGE_PIN AV10 [get_ports {C0_DDR3_0_dqs_p[0]}]
# FMC_HPC1_LA28_N, J2-H32 -> adapter -> J4-D27; IO_L4N_T0U_N7_DBC_AD7N_67
set_property PACKAGE_PIN AW10 [get_ports {C0_DDR3_0_dqs_n[0]}]
# FMC_HPC1_LA32_P, J2-H37 -> adapter -> J4-C26; IO_L22P_T3U_N6_DBC_AD0P_67
set_property PACKAGE_PIN AJ13 [get_ports {C0_DDR3_0_dqs_p[1]}]
# FMC_HPC1_LA32_N, J2-H38 -> adapter -> J4-C27; IO_L22N_T3U_N7_DBC_AD0N_67
set_property PACKAGE_PIN AJ12 [get_ports {C0_DDR3_0_dqs_n[1]}]

## Match the generated 1.5 V MIG electrical standards; DDR3 is not POD12.
set_property IOSTANDARD SSTL15_DCI [get_ports {C0_DDR3_0_addr[*] C0_DDR3_0_ba[*] C0_DDR3_0_ras_n C0_DDR3_0_cas_n C0_DDR3_0_we_n C0_DDR3_0_cke[*] C0_DDR3_0_cs_n[*] C0_DDR3_0_odt[*] C0_DDR3_0_dm[*] C0_DDR3_0_dq[*]}]
set_property IOSTANDARD DIFF_SSTL15_DCI [get_ports {C0_DDR3_0_ck_p[*] C0_DDR3_0_ck_n[*] C0_DDR3_0_dqs_p[*] C0_DDR3_0_dqs_n[*]}]
set_property IOSTANDARD SSTL15 [get_ports C0_DDR3_0_reset_n]
# Match MIG's recommended output slew; reset_n retains its default slew.
set_property SLEW FAST [get_ports {C0_DDR3_0_addr[*] C0_DDR3_0_ba[*] C0_DDR3_0_ras_n C0_DDR3_0_cas_n C0_DDR3_0_we_n C0_DDR3_0_cke[*] C0_DDR3_0_cs_n[*] C0_DDR3_0_odt[*] C0_DDR3_0_dm[*] C0_DDR3_0_dq[*] C0_DDR3_0_ck_p[*] C0_DDR3_0_ck_n[*] C0_DDR3_0_dqs_p[*] C0_DDR3_0_dqs_n[*]}]
set_property INTERNAL_VREF 0.75 [get_iobanks {66 67}]
## VCU118 schematic sheet 12: VRP66/67 have their own 240-ohm resistors; no DCI cascade.
## No severity downgrade and no DDR CLOCK_DEDICATED_ROUTE FALSE waiver is used.

## VCU118 Rev2 SW5 CPU_RESET: active high; L19, Bank 73, VCCO = 1.2 V.
set_property PACKAGE_PIN L19 [get_ports sys_rst]
set_property IOSTANDARD LVCMOS12 [get_ports sys_rst]
set_false_path -from [get_ports sys_rst]

## VCU118 CP2105 UART: TXD_SCI_O -> FPGA rx(AW25); FPGA tx(BB21) -> RXD_SCI_I.
set_property PACKAGE_PIN AW25 [get_ports rx]
set_property PACKAGE_PIN BB21 [get_ports tx]
set_property IOSTANDARD LVCMOS18 [get_ports {rx tx}]

## C910 PL JTAG on FMC IO daughtercard at VCU118 J22 (FMCP HSPC).
## FMC IO daughtercard J20-17 / K17 = HA_N_17 -> J22 FMCP_HSPC_HA17_CC_N -> VCU118 P11 -> jtag_tclk
## FMC IO daughtercard J20-18 / K16 = HA_P_17 -> J22 FMCP_HSPC_HA17_CC_P -> VCU118 R11 -> jtag_tms
## FMC IO daughtercard J20-19 / J19 = HA_N_18 -> J22 FMCP_HSPC_HA18_N    -> VCU118 N15 -> jtag_tdi
## FMC IO daughtercard J20-20 / J18 = HA_P_18 -> J22 FMCP_HSPC_HA18_P    -> VCU118 P15 -> jtag_tdo
## FMC IO daughtercard J20-21 / H20 = LA_N_15 -> J22 FMCP_HSPC_LA15_N    -> VCU118 AG33 -> jtag_trstn
set_property PACKAGE_PIN P11 [get_ports jtag_tclk]
set_property PACKAGE_PIN R11 [get_ports jtag_tms]
set_property PACKAGE_PIN N15 [get_ports jtag_tdi]
set_property PACKAGE_PIN P15 [get_ports jtag_tdo]
set_property PACKAGE_PIN AG33 [get_ports jtag_trstn]
set_property IOSTANDARD LVCMOS18 [get_ports {jtag_tclk jtag_tms jtag_tdi jtag_tdo jtag_trstn}]
set_property PULLDOWN true [get_ports jtag_tclk]
set_property PULLUP true [get_ports {jtag_tms jtag_tdi jtag_trstn}]
set_property CLOCK_BUFFER_TYPE NONE [get_ports jtag_tclk]
# Low-speed debug TCK: allow fabric routing only on the IBUF-to-BUFG input net.
set_property CLOCK_DEDICATED_ROUTE FALSE [get_nets {jtag_tclk_IBUF_inst/O}]
create_clock -period 100.000 -name C910_JTAG_TCK [get_ports jtag_tclk]
set_clock_groups -asynchronous -group [get_clocks C910_JTAG_TCK] -group [get_clocks -include_generated_clocks BOARD_SYSCLK_250M]
set_false_path -from [get_ports jtag_trstn]
