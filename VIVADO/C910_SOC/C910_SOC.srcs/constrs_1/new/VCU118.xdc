## AXVU13P 开发板引脚约束
## 引脚来源：AXVU13P_UG.pdf

## VCU118 DDR4 C1，当前 C910_SOC_wrapper 接口为 64bit
## 引脚来源：vcu118_rev2.0_12082017.xdc；保留工程现有 BADJ_CLK/C0_DDR4 端口命名
set_property -dict {PACKAGE_PIN G31 IOSTANDARD DIFF_SSTL12} [get_ports BADJ_CLK_clk_p]
set_property -dict {PACKAGE_PIN F31 IOSTANDARD DIFF_SSTL12} [get_ports BADJ_CLK_clk_n]
create_clock -period 3.333 -name C1_DDR4_SYSCLK1_300M [get_ports BADJ_CLK_clk_p]

## VCU118 C1 DQ[0:63]
set c1_dq_pins {
  F11 E11 F10 F9 H12 G12 E9 D9 R19 P19
  M18 M17 N19 N18 N17 M16 L16 K16 L18 K18
  J17 H17 H19 H18 F19 F18 E19 E18 G20 F20
  E17 D16 D17 C17 C19 C18 D20 D19 C20 B20
  N23 M23 R21 P21 R22 P22 T23 R23 K24 J24
  M21 L21 K21 J21 K22 J22 H23 H22 E23 E22
  F21 E21 F24 F23
}
for {set i 0} {$i < 64} {incr i} {
  set_property PACKAGE_PIN [lindex $c1_dq_pins $i] [get_ports [format {C0_DDR4_dq[%d]} $i]]
}

## VCU118 C1 DM[0:7]
set c1_dm_pins {G11 R18 K17 G18 B18 P20 L23 G22}
for {set i 0} {$i < 8} {incr i} {
  set_property PACKAGE_PIN [lindex $c1_dm_pins $i] [get_ports [format {C0_DDR4_dm_n[%d]} $i]]
}

## VCU118 C1 DQS[0:7]
set c1_dqs_c_pins {D10 P16 J19 E16 A18 M22 L20 G23}
set c1_dqs_t_pins {D11 P17 K19 F16 A19 N22 M20 H24}
for {set i 0} {$i < 8} {incr i} {
  set_property PACKAGE_PIN [lindex $c1_dqs_c_pins $i] [get_ports [format {C0_DDR4_dqs_c[%d]} $i]]
  set_property PACKAGE_PIN [lindex $c1_dqs_t_pins $i] [get_ports [format {C0_DDR4_dqs_t[%d]} $i]]
}

## VCU118 C1 address/control
set_property PACKAGE_PIN D14 [get_ports {C0_DDR4_adr[0]}]
set_property PACKAGE_PIN B15 [get_ports {C0_DDR4_adr[1]}]
set_property PACKAGE_PIN B16 [get_ports {C0_DDR4_adr[2]}]
set_property PACKAGE_PIN C14 [get_ports {C0_DDR4_adr[3]}]
set_property PACKAGE_PIN C15 [get_ports {C0_DDR4_adr[4]}]
set_property PACKAGE_PIN A13 [get_ports {C0_DDR4_adr[5]}]
set_property PACKAGE_PIN A14 [get_ports {C0_DDR4_adr[6]}]
set_property PACKAGE_PIN A15 [get_ports {C0_DDR4_adr[7]}]
set_property PACKAGE_PIN A16 [get_ports {C0_DDR4_adr[8]}]
set_property PACKAGE_PIN B12 [get_ports {C0_DDR4_adr[9]}]
set_property PACKAGE_PIN C12 [get_ports {C0_DDR4_adr[10]}]
set_property PACKAGE_PIN B13 [get_ports {C0_DDR4_adr[11]}]
set_property PACKAGE_PIN C13 [get_ports {C0_DDR4_adr[12]}]
set_property PACKAGE_PIN D15 [get_ports {C0_DDR4_adr[13]}]
set_property PACKAGE_PIN H14 [get_ports {C0_DDR4_adr[14]}]
set_property PACKAGE_PIN H15 [get_ports {C0_DDR4_adr[15]}]
set_property PACKAGE_PIN F15 [get_ports {C0_DDR4_adr[16]}]
set_property PACKAGE_PIN G15 [get_ports {C0_DDR4_ba[0]}]
set_property PACKAGE_PIN G13 [get_ports {C0_DDR4_ba[1]}]
set_property PACKAGE_PIN H13 [get_ports {C0_DDR4_bg[0]}]
set_property PACKAGE_PIN E14 [get_ports {C0_DDR4_ck_c[0]}]
set_property PACKAGE_PIN F14 [get_ports {C0_DDR4_ck_t[0]}]
set_property PACKAGE_PIN A10 [get_ports {C0_DDR4_cke[0]}]
set_property PACKAGE_PIN F13 [get_ports {C0_DDR4_cs_n[0]}]
set_property PACKAGE_PIN C8 [get_ports {C0_DDR4_odt[0]}]
set_property PACKAGE_PIN E13 [get_ports C0_DDR4_act_n]
set_property PACKAGE_PIN N20 [get_ports C0_DDR4_reset_n]

set_property IOSTANDARD SSTL12 [get_ports {C0_DDR4_act_n C0_DDR4_adr[*] C0_DDR4_ba[*] C0_DDR4_bg[*] C0_DDR4_cke[*] C0_DDR4_cs_n[*] C0_DDR4_odt[*]}]
set_property IOSTANDARD POD12 [get_ports {C0_DDR4_ck_c[*] C0_DDR4_ck_t[*] C0_DDR4_dm_n[*] C0_DDR4_dq[*]}]
set_property IOSTANDARD DIFF_POD12 [get_ports {C0_DDR4_dqs_c[*] C0_DDR4_dqs_t[*]}]
set_property IOSTANDARD LVCMOS12 [get_ports C0_DDR4_reset_n]

## VCU118 DDR4 C1 使用 FPGA Bank 71/72/73，板上 VREF 未外接
set_property INTERNAL_VREF 0.6 [get_iobanks 71 72 73]

## 用户复位按键，低有效，手册第 46 页；BF35 位于 Bank 62，原理图 VCCO_62 为 1.2V
set_property PACKAGE_PIN BF35 [get_ports sys_rstn]
set_property IOSTANDARD LVCMOS12 [get_ports sys_rstn]
set_property PULLUP true [get_ports sys_rstn]
set_false_path -from [get_ports sys_rstn]

## 临时 FPGA 运行指示信号，FMC1+ -> BYSS-FMCH-BO J18-2
## J18-2 FMC管脚D14=LA_P_9 -> FMC1_LA09_P=BD15
set_property PACKAGE_PIN BD15 [get_ports fpga_alive_led]
set_property IOSTANDARD LVCMOS18 [get_ports fpga_alive_led]

## VCU118 板载 CP2105 USB-UART（UART1）：CP2105 TXD_SCI_O -> FPGA rx(AW25)，FPGA tx(BB21) -> CP2105 RXD_SCI_I
set_property PACKAGE_PIN AW25 [get_ports rx]
set_property PACKAGE_PIN BB21 [get_ports tx]
set_property IOSTANDARD LVCMOS18 [get_ports {rx tx}]

## C910 JTAG 调试口，接到 FMC1+ 子卡 J20 插针组
## J20-17 FMC管脚K17=HA_N_17 -> FMC1_HA17_CC_N=BA23 -> jtag_tclk
## J20-18 FMC管脚K16=HA_P_17 -> FMC1_HA17_CC_P=AY23 -> jtag_tms
## J20-19 FMC管脚J19=HA_N_18 -> FMC1_HA18_N=AP23 -> jtag_tdi
## J20-20 FMC管脚J18=HA_P_18 -> FMC1_HA18_P=AN23 -> jtag_tdo
## J20-21 FMC管脚H20=LA_N_15 -> FMC1_LA15_N=AL15 -> jtag_trstn
set_property PACKAGE_PIN AP23 [get_ports jtag_tdi]
set_property PACKAGE_PIN AY23 [get_ports jtag_tms]
set_property PACKAGE_PIN BA23 [get_ports jtag_tclk]
set_property PACKAGE_PIN AN23 [get_ports jtag_tdo]
set_property PACKAGE_PIN AL15 [get_ports jtag_trstn]
set_property IOSTANDARD LVCMOS18 [get_ports {jtag_tclk jtag_tms jtag_tdi jtag_tdo jtag_trstn}]
set_property PULLDOWN true [get_ports jtag_tclk]
set_property PULLUP true [get_ports {jtag_tms jtag_tdi jtag_trstn}]
set_property CLOCK_BUFFER_TYPE NONE [get_ports jtag_tclk]
create_clock -period 100.000 -name C910_JTAG_TCK [get_ports jtag_tclk]
set_clock_groups -asynchronous -group [get_clocks C910_JTAG_TCK] -group [get_clocks -include_generated_clocks C1_DDR4_SYSCLK1_300M]
set_false_path -from [get_ports jtag_trstn]
