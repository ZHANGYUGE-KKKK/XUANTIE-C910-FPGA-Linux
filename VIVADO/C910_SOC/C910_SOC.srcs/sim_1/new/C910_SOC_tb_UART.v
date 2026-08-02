`timescale 1 ns / 1 ps

module C910_SOC_tb_UART;
  localparam real BADJ_CLK_PERIOD_NS = 5.0;
  localparam real UART_BIT_NS        = 1000000000.0 / 115200.0;
  localparam real TIMEOUT_NS         = 50000000.0;

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

  integer i;
  integer uart_count;
  reg [7:0] uart_char;
  reg [87:0] uart_text;

  wire        probe_id_vld;
  wire [31:0] probe_id_inst0;
  wire        probe_id_length;
  wire        probe_retire_vld;
  wire [38:0] probe_retire_pc;
  wire        probe_core_aw_hs;
  wire        probe_core_w_hs;
  wire        probe_bram_aw_hs;
  wire        probe_bram_w_hs;
  wire        probe_bram_port_wr;

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

  assign probe_id_vld =
      u_dut.C910_SOC_i.C910_core.inst.u_openC910.x_ct_top_0.x_ct_core.x_ct_idu_top.ctrl_top_id_inst0_vld;
  assign probe_id_inst0 =
      u_dut.C910_SOC_i.C910_core.inst.u_openC910.x_ct_top_0.x_ct_core.x_ct_idu_top.x_ct_idu_id_dp.id_inst0_inst;
  assign probe_id_length =
      u_dut.C910_SOC_i.C910_core.inst.u_openC910.x_ct_top_0.x_ct_core.x_ct_idu_top.x_ct_idu_id_dp.id_inst0_length;
  assign probe_retire_vld =
      u_dut.C910_SOC_i.C910_core.inst.u_openC910.x_ct_top_0.x_ct_core.x_ct_rtu_top.rob_retire_inst0_vld;
  assign probe_retire_pc =
      u_dut.C910_SOC_i.C910_core.inst.u_openC910.x_ct_top_0.x_ct_core.x_ct_rtu_top.rob_retire_inst0_cur_pc;

  assign probe_core_aw_hs =
      u_dut.C910_SOC_i.C910_core_0_m_axi_AWVALID && u_dut.C910_SOC_i.C910_core_0_m_axi_AWREADY;
  assign probe_core_w_hs =
      u_dut.C910_SOC_i.C910_core_0_m_axi_WVALID && u_dut.C910_SOC_i.C910_core_0_m_axi_WREADY;
  assign probe_bram_aw_hs =
      u_dut.C910_SOC_i.smartconnect_0_M01_AXI_AWVALID && u_dut.C910_SOC_i.smartconnect_0_M01_AXI_AWREADY;
  assign probe_bram_w_hs =
      u_dut.C910_SOC_i.smartconnect_0_M01_AXI_WVALID && u_dut.C910_SOC_i.smartconnect_0_M01_AXI_WREADY;
  assign probe_bram_port_wr =
      u_dut.C910_SOC_i.bram_ctrl_bram_en_a && (u_dut.C910_SOC_i.bram_ctrl_bram_we_a != 16'h0000);

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

  always @(posedge BADJ_CLK_clk_p[0]) begin
    if (sys_rstn) begin
      if (probe_id_vld &&
          ((probe_id_inst0[15:0] == 16'hc43e) ||
           (probe_id_inst0[15:0] == 16'hc21c) ||
           (probe_id_inst0[15:0] == 16'h0705) ||
           (probe_id_inst0[15:0] == 16'hb7ed))) begin
        $display("[%0t] DBG_ID_RVC inst=%h low16=%h length=%0d is16=%0d",
                 $time, probe_id_inst0, probe_id_inst0[15:0],
                 probe_id_length, !probe_id_length);
      end

      if (probe_retire_vld &&
          (probe_retire_pc >= 39'h10034) &&
          (probe_retire_pc <= 39'h10070)) begin
        $display("[%0t] DBG_RETIRE pc=%h", $time, probe_retire_pc);
      end

      if (probe_core_aw_hs) begin
        if (((u_dut.C910_SOC_i.C910_core_0_m_axi_AWADDR >= 40'h0001fff0) &&
             (u_dut.C910_SOC_i.C910_core_0_m_axi_AWADDR <= 40'h0001ffff)) ||
            (u_dut.C910_SOC_i.C910_core_0_m_axi_AWADDR == 40'h40000004)) begin
          $display("[%0t] DBG_CORE_AW addr=%h size=%0d len=%0d",
                   $time,
                   u_dut.C910_SOC_i.C910_core_0_m_axi_AWADDR,
                   u_dut.C910_SOC_i.C910_core_0_m_axi_AWSIZE,
                   u_dut.C910_SOC_i.C910_core_0_m_axi_AWLEN);
        end
      end

      if (probe_core_w_hs) begin
        if ((u_dut.C910_SOC_i.C910_core_0_m_axi_WSTRB == 16'h00ff) ||
            (u_dut.C910_SOC_i.C910_core_0_m_axi_WSTRB == 16'h0f00) ||
            (u_dut.C910_SOC_i.C910_core_0_m_axi_WSTRB == 16'h000f)) begin
          $display("[%0t] DBG_CORE_W strb=%h data=%h data95_64=%h",
                   $time,
                   u_dut.C910_SOC_i.C910_core_0_m_axi_WSTRB,
                   u_dut.C910_SOC_i.C910_core_0_m_axi_WDATA,
                   u_dut.C910_SOC_i.C910_core_0_m_axi_WDATA[95:64]);
        end
      end

      if (probe_bram_aw_hs) begin
        if (u_dut.C910_SOC_i.smartconnect_0_M01_AXI_AWADDR >= 16'hfff0) begin
          $display("[%0t] DBG_BRAM_AW addr=%h size=%0d len=%0d",
                   $time,
                   u_dut.C910_SOC_i.smartconnect_0_M01_AXI_AWADDR,
                   u_dut.C910_SOC_i.smartconnect_0_M01_AXI_AWSIZE,
                   u_dut.C910_SOC_i.smartconnect_0_M01_AXI_AWLEN);
        end
      end

      if (probe_bram_w_hs) begin
        if ((u_dut.C910_SOC_i.smartconnect_0_M01_AXI_WSTRB == 16'h00ff) ||
            (u_dut.C910_SOC_i.smartconnect_0_M01_AXI_WSTRB == 16'h0f00) ||
            (u_dut.C910_SOC_i.smartconnect_0_M01_AXI_WSTRB == 16'h000f)) begin
          $display("[%0t] DBG_BRAM_W strb=%h data=%h data95_64=%h",
                   $time,
                   u_dut.C910_SOC_i.smartconnect_0_M01_AXI_WSTRB,
                   u_dut.C910_SOC_i.smartconnect_0_M01_AXI_WDATA,
                   u_dut.C910_SOC_i.smartconnect_0_M01_AXI_WDATA[95:64]);
        end
      end

      if (probe_bram_port_wr) begin
        $display("[%0t] DBG_BRAM_PORT addr=%h we=%h we0=%0d wrdata=%h wrdata95_64=%h",
                 $time,
                 u_dut.C910_SOC_i.bram_ctrl_bram_addr_a,
                 u_dut.C910_SOC_i.bram_ctrl_bram_we_a,
                 u_dut.C910_SOC_i.bram_ctrl_bram_we_a[0],
                 u_dut.C910_SOC_i.bram_ctrl_bram_wrdata_a,
                 u_dut.C910_SOC_i.bram_ctrl_bram_wrdata_a[95:64]);

        if (u_dut.C910_SOC_i.bram_ctrl_bram_we_a == 16'h0f00) begin
          $display("[%0t] DBG_WARN expected store to byte lanes 8..11. If BMG wea only uses bit0, this write is dropped.",
                   $time);
        end
      end
    end
  end

  initial begin
    uart_count = 0;
    uart_char = 8'h00;
    uart_text = 88'h0;

    forever begin
      @(negedge tx);
      if (sys_rstn) begin
        uart_char = 8'h00;
        #(UART_BIT_NS * 1.5);
        for (i = 0; i < 8; i = i + 1) begin
          uart_char[i] = tx;
          #(UART_BIT_NS);
        end

        if (tx !== 1'b1) begin
          $display("[%0t] ERROR: UART stop bit is not high", $time);
          $finish;
        end

        uart_text = {uart_text[79:0], uart_char};
        uart_count = uart_count + 1;
        $display("[%0t] UART[%0d]: %c (0x%02h)", $time, uart_count, uart_char, uart_char);

        if (uart_count == 11) begin
          $display("[%0t] UART_TEXT: %s", $time, uart_text);
          if (uart_text == "HelloWorld!") begin
            $display("[%0t] PASS: BootROM started the BRAM program", $time);
          end else begin
            $display("[%0t] ERROR: unexpected UART output: %s", $time, uart_text);
          end
          $finish;
        end
      end
    end
  end

  initial begin
    #(TIMEOUT_NS);
    $display("[%0t] ERROR: timeout waiting for HelloWorld! count=%0d text=%s", $time, uart_count, uart_text);
    $finish;
  end
endmodule
