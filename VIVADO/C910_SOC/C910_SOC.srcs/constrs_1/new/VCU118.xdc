## AXVU13P �?发板引脚约束
## 引脚来源：AXVU13P_UG.pdf

## VCU118 DDR4 C1，当�? C910_SOC_wrapper 接口�? 64bit
## 引脚来源：vcu118_rev2.0_12082017.xdc；保留工程现�? BADJ_CLK/C0_DDR4 端口命名
## C1 参�?�时钟：250MHZ_CLK1_P/N，Bank 71；MIG 输入时钟�?配置�? 250 MHz
set_property -dict {PACKAGE_PIN E12 IOSTANDARD DIFF_SSTL12} [get_ports BADJ_CLK_clk_p]
set_property -dict {PACKAGE_PIN D12 IOSTANDARD DIFF_SSTL12} [get_ports BADJ_CLK_clk_n]
create_clock -period 4.000 -name C1_DDR4_SYSCLK1_250M [get_ports BADJ_CLK_clk_p]

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
set_property PACKAGE_PIN F11 [get_ports {C0_DDR4_dq[0]}]
set_property PACKAGE_PIN E11 [get_ports {C0_DDR4_dq[1]}]
set_property PACKAGE_PIN F10 [get_ports {C0_DDR4_dq[2]}]
set_property PACKAGE_PIN F9 [get_ports {C0_DDR4_dq[3]}]
set_property PACKAGE_PIN H12 [get_ports {C0_DDR4_dq[4]}]
set_property PACKAGE_PIN G12 [get_ports {C0_DDR4_dq[5]}]
set_property PACKAGE_PIN E9 [get_ports {C0_DDR4_dq[6]}]
set_property PACKAGE_PIN D9 [get_ports {C0_DDR4_dq[7]}]
set_property PACKAGE_PIN R19 [get_ports {C0_DDR4_dq[8]}]
set_property PACKAGE_PIN P19 [get_ports {C0_DDR4_dq[9]}]
set_property PACKAGE_PIN M18 [get_ports {C0_DDR4_dq[10]}]
set_property PACKAGE_PIN M17 [get_ports {C0_DDR4_dq[11]}]
set_property PACKAGE_PIN N19 [get_ports {C0_DDR4_dq[12]}]
set_property PACKAGE_PIN N18 [get_ports {C0_DDR4_dq[13]}]
set_property PACKAGE_PIN N17 [get_ports {C0_DDR4_dq[14]}]
set_property PACKAGE_PIN M16 [get_ports {C0_DDR4_dq[15]}]
set_property PACKAGE_PIN L16 [get_ports {C0_DDR4_dq[16]}]
set_property PACKAGE_PIN K16 [get_ports {C0_DDR4_dq[17]}]
set_property PACKAGE_PIN L18 [get_ports {C0_DDR4_dq[18]}]
set_property PACKAGE_PIN K18 [get_ports {C0_DDR4_dq[19]}]
set_property PACKAGE_PIN J17 [get_ports {C0_DDR4_dq[20]}]
set_property PACKAGE_PIN H17 [get_ports {C0_DDR4_dq[21]}]
set_property PACKAGE_PIN H19 [get_ports {C0_DDR4_dq[22]}]
set_property PACKAGE_PIN H18 [get_ports {C0_DDR4_dq[23]}]
set_property PACKAGE_PIN F19 [get_ports {C0_DDR4_dq[24]}]
set_property PACKAGE_PIN F18 [get_ports {C0_DDR4_dq[25]}]
set_property PACKAGE_PIN E19 [get_ports {C0_DDR4_dq[26]}]
set_property PACKAGE_PIN E18 [get_ports {C0_DDR4_dq[27]}]
set_property PACKAGE_PIN G20 [get_ports {C0_DDR4_dq[28]}]
set_property PACKAGE_PIN F20 [get_ports {C0_DDR4_dq[29]}]
set_property PACKAGE_PIN E17 [get_ports {C0_DDR4_dq[30]}]
set_property PACKAGE_PIN D16 [get_ports {C0_DDR4_dq[31]}]
set_property PACKAGE_PIN D17 [get_ports {C0_DDR4_dq[32]}]
set_property PACKAGE_PIN C17 [get_ports {C0_DDR4_dq[33]}]
set_property PACKAGE_PIN C19 [get_ports {C0_DDR4_dq[34]}]
set_property PACKAGE_PIN C18 [get_ports {C0_DDR4_dq[35]}]
set_property PACKAGE_PIN D20 [get_ports {C0_DDR4_dq[36]}]
set_property PACKAGE_PIN D19 [get_ports {C0_DDR4_dq[37]}]
set_property PACKAGE_PIN C20 [get_ports {C0_DDR4_dq[38]}]
set_property PACKAGE_PIN B20 [get_ports {C0_DDR4_dq[39]}]
set_property PACKAGE_PIN N23 [get_ports {C0_DDR4_dq[40]}]
set_property PACKAGE_PIN M23 [get_ports {C0_DDR4_dq[41]}]
set_property PACKAGE_PIN R21 [get_ports {C0_DDR4_dq[42]}]
set_property PACKAGE_PIN P21 [get_ports {C0_DDR4_dq[43]}]
set_property PACKAGE_PIN R22 [get_ports {C0_DDR4_dq[44]}]
set_property PACKAGE_PIN P22 [get_ports {C0_DDR4_dq[45]}]
set_property PACKAGE_PIN T23 [get_ports {C0_DDR4_dq[46]}]
set_property PACKAGE_PIN R23 [get_ports {C0_DDR4_dq[47]}]
set_property PACKAGE_PIN K24 [get_ports {C0_DDR4_dq[48]}]
set_property PACKAGE_PIN J24 [get_ports {C0_DDR4_dq[49]}]
set_property PACKAGE_PIN M21 [get_ports {C0_DDR4_dq[50]}]
set_property PACKAGE_PIN L21 [get_ports {C0_DDR4_dq[51]}]
set_property PACKAGE_PIN K21 [get_ports {C0_DDR4_dq[52]}]
set_property PACKAGE_PIN J21 [get_ports {C0_DDR4_dq[53]}]
set_property PACKAGE_PIN K22 [get_ports {C0_DDR4_dq[54]}]
set_property PACKAGE_PIN J22 [get_ports {C0_DDR4_dq[55]}]
set_property PACKAGE_PIN H23 [get_ports {C0_DDR4_dq[56]}]
set_property PACKAGE_PIN H22 [get_ports {C0_DDR4_dq[57]}]
set_property PACKAGE_PIN E23 [get_ports {C0_DDR4_dq[58]}]
set_property PACKAGE_PIN E22 [get_ports {C0_DDR4_dq[59]}]
set_property PACKAGE_PIN F21 [get_ports {C0_DDR4_dq[60]}]
set_property PACKAGE_PIN E21 [get_ports {C0_DDR4_dq[61]}]
set_property PACKAGE_PIN F24 [get_ports {C0_DDR4_dq[62]}]
set_property PACKAGE_PIN F23 [get_ports {C0_DDR4_dq[63]}]

## VCU118 C1 DM[0:7]
set c1_dm_pins {G11 R18 K17 G18 B18 P20 L23 G22}
set_property PACKAGE_PIN G11 [get_ports {C0_DDR4_dm_n[0]}]
set_property PACKAGE_PIN R18 [get_ports {C0_DDR4_dm_n[1]}]
set_property PACKAGE_PIN K17 [get_ports {C0_DDR4_dm_n[2]}]
set_property PACKAGE_PIN G18 [get_ports {C0_DDR4_dm_n[3]}]
set_property PACKAGE_PIN B18 [get_ports {C0_DDR4_dm_n[4]}]
set_property PACKAGE_PIN P20 [get_ports {C0_DDR4_dm_n[5]}]
set_property PACKAGE_PIN L23 [get_ports {C0_DDR4_dm_n[6]}]
set_property PACKAGE_PIN G22 [get_ports {C0_DDR4_dm_n[7]}]

## VCU118 C1 DQS[0:7]
set c1_dqs_c_pins {D10 P16 J19 E16 A18 M22 L20 G23}
set c1_dqs_t_pins {D11 P17 K19 F16 A19 N22 M20 H24}
set_property PACKAGE_PIN D10 [get_ports {C0_DDR4_dqs_c[0]}]
set_property PACKAGE_PIN D11 [get_ports {C0_DDR4_dqs_t[0]}]
set_property PACKAGE_PIN P16 [get_ports {C0_DDR4_dqs_c[1]}]
set_property PACKAGE_PIN P17 [get_ports {C0_DDR4_dqs_t[1]}]
set_property PACKAGE_PIN J19 [get_ports {C0_DDR4_dqs_c[2]}]
set_property PACKAGE_PIN K19 [get_ports {C0_DDR4_dqs_t[2]}]
set_property PACKAGE_PIN E16 [get_ports {C0_DDR4_dqs_c[3]}]
set_property PACKAGE_PIN F16 [get_ports {C0_DDR4_dqs_t[3]}]
set_property PACKAGE_PIN A18 [get_ports {C0_DDR4_dqs_c[4]}]
set_property PACKAGE_PIN A19 [get_ports {C0_DDR4_dqs_t[4]}]
set_property PACKAGE_PIN M22 [get_ports {C0_DDR4_dqs_c[5]}]
set_property PACKAGE_PIN N22 [get_ports {C0_DDR4_dqs_t[5]}]
set_property PACKAGE_PIN L20 [get_ports {C0_DDR4_dqs_c[6]}]
set_property PACKAGE_PIN M20 [get_ports {C0_DDR4_dqs_t[6]}]
set_property PACKAGE_PIN G23 [get_ports {C0_DDR4_dqs_c[7]}]
set_property PACKAGE_PIN H24 [get_ports {C0_DDR4_dqs_t[7]}]

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

## DDR4 MIG 使用 DCI 标准；CK �? SSTL 差分时钟，DQ/DM/DQS �? POD 数据接口
set_property IOSTANDARD SSTL12_DCI [get_ports {C0_DDR4_act_n C0_DDR4_adr[*] C0_DDR4_ba[*] C0_DDR4_bg[*] C0_DDR4_cke[*] C0_DDR4_cs_n[*] C0_DDR4_odt[*]}]
set_property IOSTANDARD DIFF_SSTL12_DCI [get_ports {C0_DDR4_ck_c[*] C0_DDR4_ck_t[*]}]
set_property IOSTANDARD POD12_DCI [get_ports {C0_DDR4_dm_n[*] C0_DDR4_dq[*]}]
set_property IOSTANDARD DIFF_POD12_DCI [get_ports {C0_DDR4_dqs_c[*] C0_DDR4_dqs_t[*]}]
set_property IOSTANDARD LVCMOS12 [get_ports C0_DDR4_reset_n]

## VCU118 DDR4 C1 使用 FPGA Bank 71/72/73，板�? VREF 未外�?
set_property INTERNAL_VREF 0.6 [get_iobanks {71 72 73}]

## VCU118 Rev2 SW5 CPU_RESET 按键，高有效：松开为低、按下为高；L19，Bank 73，VCCO=1.2V
set_property PACKAGE_PIN L19 [get_ports sys_rst]
set_property IOSTANDARD LVCMOS12 [get_ports sys_rst]
set_false_path -from [get_ports sys_rst]

## VCU118 板载 CP2105 USB-UART（UART1）：CP2105 TXD_SCI_O -> FPGA rx(AW25)，FPGA tx(BB21) -> CP2105 RXD_SCI_I
set_property PACKAGE_PIN AW25 [get_ports rx]
set_property PACKAGE_PIN BB21 [get_ports tx]
set_property IOSTANDARD LVCMOS18 [get_ports {rx tx}]

## C910 JTAG 调试口，FMC IO 子卡接入 VCU118 J22（FMCP HSPC�?
## 子卡 J20-17 / K17 = HA_N_17 -> J22 FMCP_HSPC_HA17_CC_N -> VCU118 P11 -> jtag_tclk
## 子卡 J20-18 / K16 = HA_P_17 -> J22 FMCP_HSPC_HA17_CC_P -> VCU118 R11 -> jtag_tms
## 子卡 J20-19 / J19 = HA_N_18 -> J22 FMCP_HSPC_HA18_N    -> VCU118 N15 -> jtag_tdi
## 子卡 J20-20 / J18 = HA_P_18 -> J22 FMCP_HSPC_HA18_P    -> VCU118 P15 -> jtag_tdo
## 子卡 J20-21 / H20 = LA_N_15 -> J22 FMCP_HSPC_LA15_N    -> VCU118 AG33 -> jtag_trstn
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
set_clock_groups -asynchronous -group [get_clocks C910_JTAG_TCK] -group [get_clocks -include_generated_clocks C1_DDR4_SYSCLK1_250M]
set_false_path -from [get_ports jtag_trstn]
