// Pin-planning harness only. This is not the C910 SoC or a DDR traffic test.
module validate_pinout_top (
  input [0:0] BADJ_CLK_clk_p, BADJ_CLK_clk_n,
  input [0:0] sys_rst,
  output [15:0] C0_DDR3_0_addr,
  output [2:0] C0_DDR3_0_ba,
  output C0_DDR3_0_ras_n, C0_DDR3_0_cas_n, C0_DDR3_0_we_n,
  output [0:0] C0_DDR3_0_cke, C0_DDR3_0_odt, C0_DDR3_0_cs_n,
  output [0:0] C0_DDR3_0_ck_p, C0_DDR3_0_ck_n,
  output C0_DDR3_0_reset_n,
  output [1:0] C0_DDR3_0_dm,
  inout [15:0] C0_DDR3_0_dq,
  inout [1:0] C0_DDR3_0_dqs_p, C0_DDR3_0_dqs_n,
  input jtag_tclk, jtag_tdi, jtag_tms, jtag_trstn, rx,
  output [0:0] jtag_tdo,
  output tx
);
  wire sys_clk, ui_clk, ui_reset, calibrated;
  wire reset_i, jtag_clk_i, jtag_tdi_i, jtag_tms_i, jtag_trstn_i, rx_i;
  wire debug_bit_out, tx_out;
  IBUFDS sysclk_ibuf (.I(BADJ_CLK_clk_p[0]), .IB(BADJ_CLK_clk_n[0]), .O(sys_clk));
  IBUF reset_ibuf (.I(sys_rst[0]), .O(reset_i));
  IBUF jtag_tclk_IBUF_inst (.I(jtag_tclk), .O(jtag_clk_i));
  IBUF jtag_tdi_ibuf (.I(jtag_tdi), .O(jtag_tdi_i));
  IBUF jtag_tms_ibuf (.I(jtag_tms), .O(jtag_tms_i));
  IBUF jtag_trstn_ibuf (.I(jtag_trstn), .O(jtag_trstn_i));
  IBUF rx_ibuf (.I(rx), .O(rx_i));
  OBUF tdo_obuf (.I(debug_bit_out), .O(jtag_tdo[0]));
  OBUF tx_obuf (.I(tx_out), .O(tx));
  reg debug_bit;
  always @(posedge jtag_clk_i) debug_bit <= jtag_tdi_i ^ jtag_tms_i ^ jtag_trstn_i;
  assign debug_bit_out = debug_bit;
  assign tx_out = calibrated ^ rx_i;
  (* KEEP_HIERARCHY = "yes" *) C910_SOC_ddr3_0_0 DDR3 (
    .sys_rst(reset_i), .c0_sys_clk_i(sys_clk),
    .c0_ddr3_addr(C0_DDR3_0_addr), .c0_ddr3_ba(C0_DDR3_0_ba),
    .c0_ddr3_ras_n(C0_DDR3_0_ras_n), .c0_ddr3_cas_n(C0_DDR3_0_cas_n),
    .c0_ddr3_we_n(C0_DDR3_0_we_n), .c0_ddr3_cke(C0_DDR3_0_cke),
    .c0_ddr3_odt(C0_DDR3_0_odt), .c0_ddr3_cs_n(C0_DDR3_0_cs_n),
    .c0_ddr3_ck_p(C0_DDR3_0_ck_p), .c0_ddr3_ck_n(C0_DDR3_0_ck_n),
    .c0_ddr3_reset_n(C0_DDR3_0_reset_n), .c0_ddr3_dm(C0_DDR3_0_dm),
    .c0_ddr3_dq(C0_DDR3_0_dq), .c0_ddr3_dqs_p(C0_DDR3_0_dqs_p),
    .c0_ddr3_dqs_n(C0_DDR3_0_dqs_n), .c0_init_calib_complete(calibrated),
    .c0_ddr3_ui_clk(ui_clk), .c0_ddr3_ui_clk_sync_rst(ui_reset),
    .c0_ddr3_aresetn(~ui_reset),
    .c0_ddr3_s_axi_awid(1'b0), .c0_ddr3_s_axi_awaddr(30'b0),
    .c0_ddr3_s_axi_awlen(8'b0), .c0_ddr3_s_axi_awsize(3'd4),
    .c0_ddr3_s_axi_awburst(2'b01), .c0_ddr3_s_axi_awlock(1'b0),
    .c0_ddr3_s_axi_awcache(4'b0), .c0_ddr3_s_axi_awprot(3'b0),
    .c0_ddr3_s_axi_awqos(4'b0), .c0_ddr3_s_axi_awvalid(1'b0),
    .c0_ddr3_s_axi_wdata(128'b0), .c0_ddr3_s_axi_wstrb(16'b0),
    .c0_ddr3_s_axi_wlast(1'b0), .c0_ddr3_s_axi_wvalid(1'b0),
    .c0_ddr3_s_axi_bready(1'b1), .c0_ddr3_s_axi_arid(1'b0),
    .c0_ddr3_s_axi_araddr(30'b0), .c0_ddr3_s_axi_arlen(8'b0),
    .c0_ddr3_s_axi_arsize(3'd4), .c0_ddr3_s_axi_arburst(2'b01),
    .c0_ddr3_s_axi_arlock(1'b0), .c0_ddr3_s_axi_arcache(4'b0),
    .c0_ddr3_s_axi_arprot(3'b0), .c0_ddr3_s_axi_arqos(4'b0),
    .c0_ddr3_s_axi_arvalid(1'b0), .c0_ddr3_s_axi_rready(1'b1)
  );
endmodule
