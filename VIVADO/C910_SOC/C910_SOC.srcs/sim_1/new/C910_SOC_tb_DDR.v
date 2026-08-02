`timescale 1 ns / 1 ps

module C910_SOC_tb_DDR;
  localparam real BADJ_CLK_PERIOD_NS = 5.0;
  localparam real TIMEOUT_NS         = 200000000.0;

  reg  [0:0] BADJ_CLK_clk_p;
  wire [0:0] BADJ_CLK_clk_n;
  reg        sys_rstn;
  wire       tx;

  wire        C0_DDR4_act_n;
  wire [16:0] C0_DDR4_adr;
  wire [1:0]  C0_DDR4_ba;
  wire [1:0]  C0_DDR4_bg;
  wire [0:0]  C0_DDR4_ck_c;
  wire [0:0]  C0_DDR4_ck_t;
  wire [0:0]  C0_DDR4_cke;
  wire [0:0]  C0_DDR4_cs_n;
  wire [7:0]  C0_DDR4_dm_n;
  wire [63:0] C0_DDR4_dq;
  wire [7:0]  C0_DDR4_dqs_c;
  wire [7:0]  C0_DDR4_dqs_t;
  wire [0:0]  C0_DDR4_odt;
  wire        C0_DDR4_reset_n;

  wire ddr_aw_hs;
  wire ddr_w_hs;
  wire ddr_b_hs;
  wire ddr_ar_hs;
  wire ddr_r_hs;
  wire init_calib_complete;

  assign BADJ_CLK_clk_n = ~BADJ_CLK_clk_p;

  C910_SOC_wrapper u_dut (
    .BADJ_CLK_clk_n  (BADJ_CLK_clk_n),
    .BADJ_CLK_clk_p  (BADJ_CLK_clk_p),
    .C0_DDR4_act_n   (C0_DDR4_act_n),
    .C0_DDR4_adr     (C0_DDR4_adr),
    .C0_DDR4_ba      (C0_DDR4_ba),
    .C0_DDR4_bg      (C0_DDR4_bg),
    .C0_DDR4_ck_c    (C0_DDR4_ck_c),
    .C0_DDR4_ck_t    (C0_DDR4_ck_t),
    .C0_DDR4_cke     (C0_DDR4_cke),
    .C0_DDR4_cs_n    (C0_DDR4_cs_n),
    .C0_DDR4_dm_n    (C0_DDR4_dm_n),
    .C0_DDR4_dq      (C0_DDR4_dq),
    .C0_DDR4_dqs_c   (C0_DDR4_dqs_c),
    .C0_DDR4_dqs_t   (C0_DDR4_dqs_t),
    .C0_DDR4_odt     (C0_DDR4_odt),
    .C0_DDR4_reset_n (C0_DDR4_reset_n),
    .jtag_tclk       (1'b0),
    .jtag_tdi        (1'b0),
    .jtag_tdo        (),
    .jtag_tms        (1'b1),
    .jtag_trstn      (1'b0),
    .rx              (1'b1),
    .sys_rstn        (sys_rstn),
    .tx              (tx)
  );

`ifdef USE_DDR4_MODEL
  ddr4_model u_ddr4_model (
    .model_enable (1'b1),
    .act_n        (C0_DDR4_act_n),
    .adr          (C0_DDR4_adr),
    .ba           (C0_DDR4_ba),
    .bg           (C0_DDR4_bg),
    .ck           (C0_DDR4_ck_t),
    .ck_n         (C0_DDR4_ck_c),
    .cke          (C0_DDR4_cke),
    .cs_n         (C0_DDR4_cs_n),
    .dm_n         (C0_DDR4_dm_n),
    .dq           (C0_DDR4_dq),
    .dqs          (C0_DDR4_dqs_t),
    .dqs_n        (C0_DDR4_dqs_c),
    .odt          (C0_DDR4_odt),
    .reset_n      (C0_DDR4_reset_n)
  );
`else
  initial begin
    $display("[%0t] ERROR: define USE_DDR4_MODEL and add the MIG example design DDR4 model sources to sim_1.", $time);
    $finish;
  end
`endif

  assign init_calib_complete =
      u_dut.C910_SOC_i.ddr4.c0_init_calib_complete;
  assign ddr_aw_hs =
      u_dut.C910_SOC_i.axi_clock_converter_1_M_AXI_AWVALID &&
      u_dut.C910_SOC_i.axi_clock_converter_1_M_AXI_AWREADY;
  assign ddr_w_hs =
      u_dut.C910_SOC_i.axi_clock_converter_1_M_AXI_WVALID &&
      u_dut.C910_SOC_i.axi_clock_converter_1_M_AXI_WREADY;
  assign ddr_b_hs =
      u_dut.C910_SOC_i.axi_clock_converter_1_M_AXI_BVALID &&
      u_dut.C910_SOC_i.axi_clock_converter_1_M_AXI_BREADY;
  assign ddr_ar_hs =
      u_dut.C910_SOC_i.axi_clock_converter_1_M_AXI_ARVALID &&
      u_dut.C910_SOC_i.axi_clock_converter_1_M_AXI_ARREADY;
  assign ddr_r_hs =
      u_dut.C910_SOC_i.axi_clock_converter_1_M_AXI_RVALID &&
      u_dut.C910_SOC_i.axi_clock_converter_1_M_AXI_RREADY;

  initial begin
    BADJ_CLK_clk_p = 1'b0;
    forever #(BADJ_CLK_PERIOD_NS / 2.0) BADJ_CLK_clk_p = ~BADJ_CLK_clk_p;
  end

  initial begin
    sys_rstn = 1'b0;
    repeat (32) @(posedge BADJ_CLK_clk_p[0]);
    sys_rstn = 1'b1;
    $display("[%0t] INFO: system reset released", $time);
  end

  always @(posedge init_calib_complete) begin
    $display("[%0t] INFO: DDR4 init_calib_complete asserted", $time);
  end

  always @(posedge u_dut.C910_SOC_i.ddr4_0_c0_ddr4_ui_clk) begin
    if (ddr_aw_hs) begin
      $display("[%0t] DDR_AW addr=%h len=%0d size=%0d",
               $time,
               u_dut.C910_SOC_i.axi_clock_converter_1_M_AXI_AWADDR,
               u_dut.C910_SOC_i.axi_clock_converter_1_M_AXI_AWLEN,
               u_dut.C910_SOC_i.axi_clock_converter_1_M_AXI_AWSIZE);
    end
    if (ddr_w_hs) begin
      $display("[%0t] DDR_W data=%h strb=%h last=%0d",
               $time,
               u_dut.C910_SOC_i.axi_clock_converter_1_M_AXI_WDATA,
               u_dut.C910_SOC_i.axi_clock_converter_1_M_AXI_WSTRB,
               u_dut.C910_SOC_i.axi_clock_converter_1_M_AXI_WLAST);
    end
    if (ddr_b_hs) begin
      $display("[%0t] DDR_B resp=%h",
               $time,
               u_dut.C910_SOC_i.axi_clock_converter_1_M_AXI_BRESP);
    end
    if (ddr_ar_hs) begin
      $display("[%0t] DDR_AR addr=%h len=%0d size=%0d",
               $time,
               u_dut.C910_SOC_i.axi_clock_converter_1_M_AXI_ARADDR,
               u_dut.C910_SOC_i.axi_clock_converter_1_M_AXI_ARLEN,
               u_dut.C910_SOC_i.axi_clock_converter_1_M_AXI_ARSIZE);
    end
    if (ddr_r_hs) begin
      $display("[%0t] DDR_R data=%h resp=%h last=%0d",
               $time,
               u_dut.C910_SOC_i.axi_clock_converter_1_M_AXI_RDATA,
               u_dut.C910_SOC_i.axi_clock_converter_1_M_AXI_RRESP,
               u_dut.C910_SOC_i.axi_clock_converter_1_M_AXI_RLAST);
    end
  end

  initial begin
    #(TIMEOUT_NS);
    $display("[%0t] INFO: DDR simulation timeout reached", $time);
    $finish;
  end
endmodule
