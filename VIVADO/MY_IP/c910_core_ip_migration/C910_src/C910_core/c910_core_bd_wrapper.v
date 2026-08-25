// Vivado Block Design friendly wrapper for the openC910 top.
//
// This wrapper keeps the original openC910 RTL untouched and exposes only the
// interfaces that are useful for the minimal simulation SoC:
//   - one AXI4 master port, 128-bit data, 40-bit address
//   - active-low reset and clock
//   - optional JTAG pins

`include "sysmap.h"
`include "cpu_cfig.h"

module c910_core_bd_wrapper #(
  parameter [39:0] RESET_VECTOR = 40'h0000_0000,
  parameter [39:0] CPU_APB_BASE = 40'h0800_0000,
  parameter [2:0]  HART_ID      = 3'b000
) (
  input  wire         aclk,
  input  wire         aresetn,

  output wire [39:0]  m_axi_araddr,
  output wire [1:0]   m_axi_arburst,
  output wire [3:0]   m_axi_arcache,
  output wire [7:0]   m_axi_arid,
  output wire [7:0]   m_axi_arlen,
  output wire         m_axi_arlock,
  output wire [2:0]   m_axi_arprot,
  output wire [2:0]   m_axi_arsize,
  output wire         m_axi_arvalid,
  input  wire         m_axi_arready,

  output wire [39:0]  m_axi_awaddr,
  output wire [1:0]   m_axi_awburst,
  output wire [3:0]   m_axi_awcache,
  output wire [7:0]   m_axi_awid,
  output wire [7:0]   m_axi_awlen,
  output wire         m_axi_awlock,
  output wire [2:0]   m_axi_awprot,
  output wire [2:0]   m_axi_awsize,
  output wire         m_axi_awvalid,
  input  wire         m_axi_awready,

  output wire [127:0] m_axi_wdata,
  output wire         m_axi_wlast,
  output wire [15:0]  m_axi_wstrb,
  output wire         m_axi_wvalid,
  input  wire         m_axi_wready,

  input  wire [7:0]   m_axi_bid,
  input  wire [1:0]   m_axi_bresp,
  input  wire         m_axi_bvalid,
  output wire         m_axi_bready,

  input  wire [127:0] m_axi_rdata,
  input  wire [7:0]   m_axi_rid,
  input  wire         m_axi_rlast,
  input  wire [1:0]   m_axi_rresp,
  input  wire         m_axi_rvalid,
  output wire         m_axi_rready,

  input  wire         jtag_tclk,
  input  wire         jtag_tdi,
  input  wire         jtag_tms,
  input  wire         jtag_trstn,
  output wire         jtag_tdo,
  output wire         jtag_tdo_en
);

  reg [63:0] sys_cnt;

  always @(posedge aclk or negedge aresetn) begin
    if (!aresetn) begin
      sys_cnt <= 64'b0;
    end else begin
      sys_cnt <= sys_cnt + 64'b1;
    end
  end

  wire [1:0] core_jdb_pm_unused;
  wire [1:0] core_lpmd_b_unused;
  wire [63:0] core_mstatus_unused;
  wire       core_retire0_unused;
  wire [39:0] core_retire0_pc_unused;
  wire       core_retire1_unused;
  wire [39:0] core_retire1_pc_unused;
  wire       core_retire2_unused;
  wire [39:0] core_retire2_pc_unused;
  wire       cpu_debug_port_unused;
  wire       cpu_no_op_unused;
  wire       l2cache_flush_done_unused;
  wire       biu_cactive_unused;
  wire       biu_csysack_unused;

  openC910 u_openC910 (
    .axim_clk_en                  (1'b1),

    .biu_pad_araddr               (m_axi_araddr),
    .biu_pad_arburst              (m_axi_arburst),
    .biu_pad_arcache              (m_axi_arcache),
    .biu_pad_arid                 (m_axi_arid),
    .biu_pad_arlen                (m_axi_arlen),
    .biu_pad_arlock               (m_axi_arlock),
    .biu_pad_arprot               (m_axi_arprot),
    .biu_pad_arsize               (m_axi_arsize),
    .biu_pad_arvalid              (m_axi_arvalid),
    .pad_biu_arready              (m_axi_arready),

    .biu_pad_awaddr               (m_axi_awaddr),
    .biu_pad_awburst              (m_axi_awburst),
    .biu_pad_awcache              (m_axi_awcache),
    .biu_pad_awid                 (m_axi_awid),
    .biu_pad_awlen                (m_axi_awlen),
    .biu_pad_awlock               (m_axi_awlock),
    .biu_pad_awprot               (m_axi_awprot),
    .biu_pad_awsize               (m_axi_awsize),
    .biu_pad_awvalid              (m_axi_awvalid),
    .pad_biu_awready              (m_axi_awready),

    .biu_pad_wdata                (m_axi_wdata),
    .biu_pad_wlast                (m_axi_wlast),
    .biu_pad_wstrb                (m_axi_wstrb),
    .biu_pad_wvalid               (m_axi_wvalid),
    .pad_biu_wready               (m_axi_wready),

    .pad_biu_bid                  (m_axi_bid),
    .pad_biu_bresp                (m_axi_bresp),
    .pad_biu_bvalid               (m_axi_bvalid),
    .biu_pad_bready               (m_axi_bready),

    .pad_biu_rdata                (m_axi_rdata),
    .pad_biu_rid                  (m_axi_rid),
    .pad_biu_rlast                (m_axi_rlast),
    .pad_biu_rresp                (m_axi_rresp),
    .pad_biu_rvalid               (m_axi_rvalid),
    .biu_pad_rready               (m_axi_rready),

    .biu_pad_cactive              (biu_cactive_unused),
    .biu_pad_csysack              (biu_csysack_unused),
    .pad_biu_csysreq              (1'b0),

    .core0_pad_jdb_pm             (core_jdb_pm_unused),
    .core0_pad_lpmd_b             (core_lpmd_b_unused),
    .core0_pad_mstatus            (core_mstatus_unused),
    .core0_pad_retire0            (core_retire0_unused),
    .core0_pad_retire0_pc         (core_retire0_pc_unused),
    .core0_pad_retire1            (core_retire1_unused),
    .core0_pad_retire1_pc         (core_retire1_pc_unused),
    .core0_pad_retire2            (core_retire2_unused),
    .core0_pad_retire2_pc         (core_retire2_pc_unused),
    .cpu_debug_port               (cpu_debug_port_unused),
    .cpu_pad_l2cache_flush_done   (l2cache_flush_done_unused),
    .cpu_pad_no_op                (cpu_no_op_unused),

    .had_pad_jtg_tdo              (jtag_tdo),
    .had_pad_jtg_tdo_en           (jtag_tdo_en),
    .pad_had_jtg_tclk             (jtag_tclk),
    .pad_had_jtg_tdi              (jtag_tdi),
    .pad_had_jtg_tms              (jtag_tms),
    .pad_had_jtg_trst_b           (jtag_trstn),

    .pad_core0_dbg_mask           (1'b0),
    .pad_core0_dbgrq_b            (1'b1),
    .pad_core0_hartid             (HART_ID),
    .pad_core0_rst_b              (aresetn),
    .pad_core0_rvba               (RESET_VECTOR),
    .pad_cpu_apb_base             (CPU_APB_BASE),
    .pad_cpu_l2cache_flush_req    (1'b0),
    .pad_cpu_rst_b                (aresetn),
    .pad_cpu_sys_cnt              (sys_cnt),
    .pad_l2c_data_mbist_clk_ratio (3'b000),
    .pad_l2c_tag_mbist_clk_ratio  (3'b000),
    .pad_plic_int_cfg             (144'b0),
    .pad_plic_int_vld             (144'b0),
    .pad_yy_dft_clk_rst_b         (aresetn),
    .pad_yy_icg_scan_en           (1'b0),
    .pad_yy_mbist_mode            (1'b0),
    .pad_yy_scan_enable           (1'b0),
    .pad_yy_scan_mode             (1'b0),
    .pad_yy_scan_rst_b            (aresetn),
    .pll_cpu_clk                  (aclk)
  );

endmodule
