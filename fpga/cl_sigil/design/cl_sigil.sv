// Sigil SoC as an AWS EC2 F2 Custom Logic (issues #54, #65, #66, #67).
// Small Shell, aws-fpga HDK v2.3.5 (shell 0x10212415), part
// xcvu47p-fsvh2892-2-e. Architecture, register map and clock recipe:
// docs/FPGA_F2.md; memory map: docs/LINUX_PLATFORM.md.
//
//   Shell SDA ---------------------------> AWS_CLK_GEN (clock recipes)
//                                            | clk_extra_b1 = core clock
//                                            | clk_hbm_axi  = HBM AXI (H2 450 MHz)
//   Shell OCL (clk_main_a0) -> AXI-Lite clock converter
//                            -> sigil_fpga_ocl.s_axil (core clock)
//                                 sigil_ocl_regs + sigil_fpga_top
//                                   (SoC, mbus->AXI4 bridge @512 bit,
//                                    80 GiB RAM window, memory engine)
//   sigil_fpga_ocl.m_axi (core clock) -> AXI4 clock converter
//                            -> SmartConnect 2x2 "ATG" port --+
//   Shell PCIS (host, SLR1) -> register slices SLR1, SLR2      |
//                            -> SmartConnect 2x2 "XDMA" port -+  (SLR2)
//          SmartConnect DDRA (AXI 0x0 .. 64 GiB) -> sh_ddr (Shell DDR4, SLR2)
//          SmartConnect DDRB (AXI 0x10_0000_0000 ..)
//            -> register slices SLR2, SLR1, SLR0 -> cl_sigil_hbm (SLR0):
//               AXI4->AXI3 + clock converter -> HBM IP, 16 GiB
//               (EN_HBM = 0: a DECERR responder instead)
//
// SoC physical address = AXI address + 0x8000_0000 for both: DDR4 at
// PA 0x8000_0000 .. 0x10_7FFF_FFFF, HBM at 0x10_8000_0000 ..
// 0x14_7FFF_FFFF; PCIS (AppPF BAR4) offset = AXI address.
//
// Clock domains: clk_main_a0 (250 MHz: Shell interfaces, SmartConnect,
// DDR controller AXI), the core clock clk_extra_b1 from AWS_CLK_GEN
// group B (recipe B1 = 62.5 MHz interim; B5 = 100 MHz once #53
// closes timing), and the HBM clocks (clk_hbm_axi, clk_hbm_ref). The
// only crossings are the Xilinx AXI clock converters (incl. the one in
// the HBM SmartConnect), the HBM wrapper's own XPM cells and XPM CDC
// cells.
//
// Resets: sh_ddr gets rst_main_n only (HDK rule). The main-domain
// fabric uses AWS_CLK_GEN cl_rst_main_n. The core domain and both
// clock converters use cl_rst_b1_n AND cl_rst_main_n, so the
// converters' two sides are reset together; cl_rst_b1_n stays
// asserted after AFI load until the host calls
// aws_clkgen_deassert_resets() (fpga/host/ does), which waits for
// the MMCMs to lock. The SoC itself is additionally held by the
// OCL CTRL.soc_reset_req bit (resets to 1) until the host has
// loaded DDR.
`ifndef SIGIL_CORE_CLK_KHZ
  `define SIGIL_CORE_CLK_KHZ 62500
`endif

module cl_sigil
#(
  parameter EN_DDR = 1,
  parameter EN_HBM = 1
)
(
  `include "cl_ports.vh"
);

`include "cl_id_defines.vh"
`include "cl_sigil_defines.vh"

  //===========================================================================
  // Clocks and resets
  //===========================================================================
  logic rst_main_sync_n;   // rst_main_n synchronized to clk_main_a0

  xpm_cdc_async_rst CDC_RST_MAIN (
    .src_arst  (rst_main_n),
    .dest_clk  (clk_main_a0),
    .dest_arst (rst_main_sync_n)
  );

  logic gen_clk_hbm_ref, gen_clk_main_a0;
  logic gen_clk_extra_a1, gen_clk_extra_a2, gen_clk_extra_a3;
  logic gen_clk_extra_b0, gen_clk_extra_b1;
  logic gen_clk_extra_c0, gen_clk_extra_c1, gen_clk_hbm_axi;
  logic gen_rst_hbm_axi_n, gen_rst_hbm_ref_n, gen_rst_c1_n, gen_rst_c0_n;
  logic gen_rst_b1_n, gen_rst_b0_n, gen_rst_a3_n, gen_rst_a2_n, gen_rst_a1_n;
  logic gen_rst_main_n;

  // All four MMCM groups are enabled (as in the HDK cl_mem_perf
  // example) so the SDK's fpga_clkgen calls, which program and poll
  // every group, work unchanged. Only clk_extra_b1 has loads.
  aws_clk_gen #(
    .CLK_GRP_A_EN (1),
    .CLK_GRP_B_EN (1),
    .CLK_GRP_C_EN (1),
    .CLK_HBM_EN   (1)
  ) AWS_CLK_GEN (
    .i_clk_main_a0       (clk_main_a0),
    .i_rst_main_n        (rst_main_sync_n),
    .i_clk_hbm_ref       (clk_hbm_ref),
    .s_axil_ctrl_awaddr  (sda_cl_awaddr),
    .s_axil_ctrl_awvalid (sda_cl_awvalid),
    .s_axil_ctrl_awready (cl_sda_awready),
    .s_axil_ctrl_wdata   (sda_cl_wdata),
    .s_axil_ctrl_wstrb   (sda_cl_wstrb),
    .s_axil_ctrl_wvalid  (sda_cl_wvalid),
    .s_axil_ctrl_wready  (cl_sda_wready),
    .s_axil_ctrl_bresp   (cl_sda_bresp),
    .s_axil_ctrl_bvalid  (cl_sda_bvalid),
    .s_axil_ctrl_bready  (sda_cl_bready),
    .s_axil_ctrl_araddr  (sda_cl_araddr),
    .s_axil_ctrl_arvalid (sda_cl_arvalid),
    .s_axil_ctrl_arready (cl_sda_arready),
    .s_axil_ctrl_rdata   (cl_sda_rdata),
    .s_axil_ctrl_rresp   (cl_sda_rresp),
    .s_axil_ctrl_rvalid  (cl_sda_rvalid),
    .s_axil_ctrl_rready  (sda_cl_rready),
    .o_clk_hbm_ref       (gen_clk_hbm_ref),
    .o_clk_main_a0       (gen_clk_main_a0),
    .o_clk_extra_a1      (gen_clk_extra_a1),
    .o_clk_extra_a2      (gen_clk_extra_a2),
    .o_clk_extra_a3      (gen_clk_extra_a3),
    .o_clk_extra_b0      (gen_clk_extra_b0),
    .o_clk_extra_b1      (gen_clk_extra_b1),
    .o_clk_extra_c0      (gen_clk_extra_c0),
    .o_clk_extra_c1      (gen_clk_extra_c1),
    .o_clk_hbm_axi       (gen_clk_hbm_axi),
    .o_cl_rst_hbm_axi_n  (gen_rst_hbm_axi_n),
    .o_cl_rst_hbm_ref_n  (gen_rst_hbm_ref_n),
    .o_cl_rst_c1_n       (gen_rst_c1_n),
    .o_cl_rst_c0_n       (gen_rst_c0_n),
    .o_cl_rst_b1_n       (gen_rst_b1_n),
    .o_cl_rst_b0_n       (gen_rst_b0_n),
    .o_cl_rst_a3_n       (gen_rst_a3_n),
    .o_cl_rst_a2_n       (gen_rst_a2_n),
    .o_cl_rst_a1_n       (gen_rst_a1_n),
    .o_cl_rst_main_n     (gen_rst_main_n)
  );

  logic clk_core;
  assign clk_core = gen_clk_extra_b1;

  logic main_rst_n;        // main-domain fabric (PCIS slice, SmartConnect)
  logic core_rst_n;        // core domain + converter core-side
  logic cvt_main_rst_n;    // converter main-side (same source as core_rst_n)
  logic core_rst_src_n;

  xpm_cdc_async_rst CDC_RST_FABRIC (
    .src_arst  (gen_rst_main_n),
    .dest_clk  (gen_clk_main_a0),
    .dest_arst (main_rst_n)
  );

  assign core_rst_src_n = gen_rst_b1_n & gen_rst_main_n;

  xpm_cdc_async_rst CDC_RST_CORE (
    .src_arst  (core_rst_src_n),
    .dest_clk  (clk_core),
    .dest_arst (core_rst_n)
  );

  xpm_cdc_async_rst CDC_RST_CVT_MAIN (
    .src_arst  (core_rst_src_n),
    .dest_clk  (gen_clk_main_a0),
    .dest_arst (cvt_main_rst_n)
  );

  //===========================================================================
  // Globals
  //===========================================================================
  logic sh_cl_flr_assert_q;
  always_ff @(posedge gen_clk_main_a0)
    if (!main_rst_n) begin
      sh_cl_flr_assert_q <= 1'b0;
      cl_sh_flr_done     <= 1'b0;
    end else begin
      sh_cl_flr_assert_q <= sh_cl_flr_assert;
      cl_sh_flr_done     <= sh_cl_flr_assert_q && !cl_sh_flr_done;
    end

  logic ddr_ready;          // clk_main_a0
  logic hbm_ready;          // clk_main_a0
  logic soc_in_reset, soc_mem_err;   // clk_core
  logic [3:0] status_main;  // clk_main_a0 copies for the virtual LEDs

  xpm_cdc_array_single #(.WIDTH(2)) CDC_STATUS (
    .src_clk  (clk_core),
    .src_in   ({soc_mem_err, soc_in_reset}),
    .dest_clk (gen_clk_main_a0),
    .dest_out (status_main[1:0])
  );
  assign status_main[2] = ddr_ready;
  assign status_main[3] = hbm_ready;

  always_comb begin
    cl_sh_status0     = {28'd0, status_main};
    cl_sh_status1     = 32'd0;
    cl_sh_status2     = 32'd0;
    cl_sh_id0         = `CL_SH_ID0;
    cl_sh_id1         = `CL_SH_ID1;
    // vLED[0] SoC held in reset, [1] AXI error, [2] DDR calibrated,
    // [3] HBM ready
    cl_sh_status_vled = {12'd0, status_main};
    cl_sh_dma_wr_full = 1'b0;
    cl_sh_dma_rd_full = 1'b0;
  end

  //===========================================================================
  // OCL: Shell AXI-Lite (clk_main_a0) -> clock converter -> core registers
  //===========================================================================
  logic [31:0] ocl_awaddr, ocl_wdata, ocl_araddr, ocl_rdata;
  logic [3:0]  ocl_wstrb;
  logic [2:0]  ocl_awprot, ocl_arprot;
  logic        ocl_awvalid, ocl_awready, ocl_wvalid, ocl_wready;
  logic [1:0]  ocl_bresp, ocl_rresp;
  logic        ocl_bvalid, ocl_bready, ocl_arvalid, ocl_arready;
  logic        ocl_rvalid, ocl_rready;

  cl_axi_clock_converter_light OCL_CDC (
    .s_axi_aclk    (gen_clk_main_a0),
    .s_axi_aresetn (cvt_main_rst_n),
    .s_axi_awaddr  (ocl_cl_awaddr),
    .s_axi_awprot  (3'b000),
    .s_axi_awvalid (ocl_cl_awvalid),
    .s_axi_awready (cl_ocl_awready),
    .s_axi_wdata   (ocl_cl_wdata),
    .s_axi_wstrb   (ocl_cl_wstrb),
    .s_axi_wvalid  (ocl_cl_wvalid),
    .s_axi_wready  (cl_ocl_wready),
    .s_axi_bresp   (cl_ocl_bresp),
    .s_axi_bvalid  (cl_ocl_bvalid),
    .s_axi_bready  (ocl_cl_bready),
    .s_axi_araddr  (ocl_cl_araddr),
    .s_axi_arprot  (3'b000),
    .s_axi_arvalid (ocl_cl_arvalid),
    .s_axi_arready (cl_ocl_arready),
    .s_axi_rdata   (cl_ocl_rdata),
    .s_axi_rresp   (cl_ocl_rresp),
    .s_axi_rvalid  (cl_ocl_rvalid),
    .s_axi_rready  (ocl_cl_rready),
    .m_axi_aclk    (clk_core),
    .m_axi_aresetn (core_rst_n),
    .m_axi_awaddr  (ocl_awaddr),
    .m_axi_awprot  (ocl_awprot),
    .m_axi_awvalid (ocl_awvalid),
    .m_axi_awready (ocl_awready),
    .m_axi_wdata   (ocl_wdata),
    .m_axi_wstrb   (ocl_wstrb),
    .m_axi_wvalid  (ocl_wvalid),
    .m_axi_wready  (ocl_wready),
    .m_axi_bresp   (ocl_bresp),
    .m_axi_bvalid  (ocl_bvalid),
    .m_axi_bready  (ocl_bready),
    .m_axi_araddr  (ocl_araddr),
    .m_axi_arprot  (ocl_arprot),
    .m_axi_arvalid (ocl_arvalid),
    .m_axi_arready (ocl_arready),
    .m_axi_rdata   (ocl_rdata),
    .m_axi_rresp   (ocl_rresp),
    .m_axi_rvalid  (ocl_rvalid),
    .m_axi_rready  (ocl_rready)
  );

  //===========================================================================
  // Sigil SoC + OCL registers (core clock)
  //===========================================================================
  logic ddr_ready_core, hbm_ready_core;
  xpm_cdc_single CDC_DDR_READY (
    .src_clk  (gen_clk_main_a0),
    .src_in   (ddr_ready),
    .dest_clk (clk_core),
    .dest_out (ddr_ready_core)
  );
  xpm_cdc_single CDC_HBM_READY (
    .src_clk  (gen_clk_main_a0),
    .src_in   (hbm_ready),
    .dest_clk (clk_core),
    .dest_out (hbm_ready_core)
  );
  // SoC RAM window: DDR4 64 GiB + HBM 16 GiB (AXI 0x0 .. 0x14_0000_0000).
  localparam logic [63:0] RAM_SIZE = EN_HBM ? 64'h0000_0014_0000_0000
                                            : 64'h0000_0010_0000_0000;

  // Core-side AXI4 master (512-bit, matches the Shell DDR4 width).
  logic [15:0]  c_awid, c_bid, c_arid, c_rid;
  logic [63:0]  c_awaddr, c_araddr;
  logic [7:0]   c_awlen, c_arlen;
  logic [2:0]   c_awsize, c_arsize, c_awprot, c_arprot;
  logic [1:0]   c_awburst, c_arburst, c_bresp, c_rresp;
  logic         c_awlock, c_arlock;
  logic [3:0]   c_awcache, c_arcache, c_awqos, c_arqos;
  logic         c_awvalid, c_awready, c_wvalid, c_wready, c_wlast;
  logic         c_bvalid, c_bready, c_arvalid, c_arready;
  logic         c_rvalid, c_rready, c_rlast;
  logic [511:0] c_wdata, c_rdata;
  logic [63:0]  c_wstrb;

  sigil_fpga_ocl #(
    .AXI_ID_W     (16),
    .AXI_ADDR_W   (64),
    .AXI_DATA_W   (512),
    .AXI_ID       (16'h0000),
    .RAM_SIZE     (RAM_SIZE),                 // docs/LINUX_PLATFORM.md
    .DDR_BASE     (64'h0),                    // SoC 0x8000_0000 -> AXI 0x0
    .CORE_CLK_KHZ (32'(`SIGIL_CORE_CLK_KHZ)),
    .HBM_PRESENT  (EN_HBM != 0)
  ) SIGIL (
    .clk_i          (clk_core),
    .rst_ni         (core_rst_n),
    .ddr_ready_i    (ddr_ready_core),
    .hbm_ready_i    (hbm_ready_core),
    .soc_in_reset_o (soc_in_reset),
    .mem_err_o      (soc_mem_err),
    .s_axil_awaddr  (ocl_awaddr),
    .s_axil_awvalid (ocl_awvalid),
    .s_axil_awready (ocl_awready),
    .s_axil_wdata   (ocl_wdata),
    .s_axil_wvalid  (ocl_wvalid),
    .s_axil_wready  (ocl_wready),
    .s_axil_bresp   (ocl_bresp),
    .s_axil_bvalid  (ocl_bvalid),
    .s_axil_bready  (ocl_bready),
    .s_axil_araddr  (ocl_araddr),
    .s_axil_arvalid (ocl_arvalid),
    .s_axil_arready (ocl_arready),
    .s_axil_rdata   (ocl_rdata),
    .s_axil_rresp   (ocl_rresp),
    .s_axil_rvalid  (ocl_rvalid),
    .s_axil_rready  (ocl_rready),
    .m_axi_awid     (c_awid),
    .m_axi_awaddr   (c_awaddr),
    .m_axi_awlen    (c_awlen),
    .m_axi_awsize   (c_awsize),
    .m_axi_awburst  (c_awburst),
    .m_axi_awlock   (c_awlock),
    .m_axi_awcache  (c_awcache),
    .m_axi_awprot   (c_awprot),
    .m_axi_awqos    (c_awqos),
    .m_axi_awvalid  (c_awvalid),
    .m_axi_awready  (c_awready),
    .m_axi_wdata    (c_wdata),
    .m_axi_wstrb    (c_wstrb),
    .m_axi_wlast    (c_wlast),
    .m_axi_wvalid   (c_wvalid),
    .m_axi_wready   (c_wready),
    .m_axi_bid      (c_bid),
    .m_axi_bresp    (c_bresp),
    .m_axi_bvalid   (c_bvalid),
    .m_axi_bready   (c_bready),
    .m_axi_arid     (c_arid),
    .m_axi_araddr   (c_araddr),
    .m_axi_arlen    (c_arlen),
    .m_axi_arsize   (c_arsize),
    .m_axi_arburst  (c_arburst),
    .m_axi_arlock   (c_arlock),
    .m_axi_arcache  (c_arcache),
    .m_axi_arprot   (c_arprot),
    .m_axi_arqos    (c_arqos),
    .m_axi_arvalid  (c_arvalid),
    .m_axi_arready  (c_arready),
    .m_axi_rid      (c_rid),
    .m_axi_rdata    (c_rdata),
    .m_axi_rresp    (c_rresp),
    .m_axi_rlast    (c_rlast),
    .m_axi_rvalid   (c_rvalid),
    .m_axi_rready   (c_rready)
  );

  //===========================================================================
  // Core AXI4 -> clk_main_a0 (Xilinx AXI clock converter, HDK IP)
  //===========================================================================
  logic [15:0]  a_awid, a_bid, a_arid, a_rid;
  logic [63:0]  a_awaddr, a_araddr;
  logic [7:0]   a_awlen, a_arlen;
  logic [2:0]   a_awsize, a_arsize, a_awprot, a_arprot;
  logic [1:0]   a_awburst, a_arburst, a_bresp, a_rresp;
  logic         a_awlock, a_arlock;
  logic [3:0]   a_awcache, a_arcache, a_awqos, a_arqos;
  logic         a_awvalid, a_awready, a_wvalid, a_wready, a_wlast;
  logic         a_bvalid, a_bready, a_arvalid, a_arready;
  logic         a_rvalid, a_rready, a_rlast;
  logic [511:0] a_wdata, a_rdata;
  logic [63:0]  a_wstrb;

  cl_axi_clock_converter DDR_CDC (
    .s_axi_aclk     (clk_core),
    .s_axi_aresetn  (core_rst_n),
    .s_axi_awid     (c_awid),
    .s_axi_awaddr   (c_awaddr),
    .s_axi_awlen    (c_awlen),
    .s_axi_awsize   (c_awsize),
    .s_axi_awburst  (c_awburst),
    .s_axi_awlock   (c_awlock),
    .s_axi_awcache  (c_awcache),
    .s_axi_awprot   (c_awprot),
    .s_axi_awregion (4'd0),
    .s_axi_awqos    (c_awqos),
    .s_axi_awuser   (19'd0),
    .s_axi_awvalid  (c_awvalid),
    .s_axi_awready  (c_awready),
    .s_axi_wdata    (c_wdata),
    .s_axi_wstrb    (c_wstrb),
    .s_axi_wlast    (c_wlast),
    .s_axi_wvalid   (c_wvalid),
    .s_axi_wready   (c_wready),
    .s_axi_bid      (c_bid),
    .s_axi_bresp    (c_bresp),
    .s_axi_bvalid   (c_bvalid),
    .s_axi_bready   (c_bready),
    .s_axi_arid     (c_arid),
    .s_axi_araddr   (c_araddr),
    .s_axi_arlen    (c_arlen),
    .s_axi_arsize   (c_arsize),
    .s_axi_arburst  (c_arburst),
    .s_axi_arlock   (c_arlock),
    .s_axi_arcache  (c_arcache),
    .s_axi_arprot   (c_arprot),
    .s_axi_arregion (4'd0),
    .s_axi_arqos    (c_arqos),
    .s_axi_aruser   (19'd0),
    .s_axi_arvalid  (c_arvalid),
    .s_axi_arready  (c_arready),
    .s_axi_rid      (c_rid),
    .s_axi_rdata    (c_rdata),
    .s_axi_rresp    (c_rresp),
    .s_axi_rlast    (c_rlast),
    .s_axi_rvalid   (c_rvalid),
    .s_axi_rready   (c_rready),
    .m_axi_aclk     (gen_clk_main_a0),
    .m_axi_aresetn  (cvt_main_rst_n),
    .m_axi_awid     (a_awid),
    .m_axi_awaddr   (a_awaddr),
    .m_axi_awlen    (a_awlen),
    .m_axi_awsize   (a_awsize),
    .m_axi_awburst  (a_awburst),
    .m_axi_awlock   (a_awlock),
    .m_axi_awcache  (a_awcache),
    .m_axi_awprot   (a_awprot),
    .m_axi_awregion (),
    .m_axi_awqos    (a_awqos),
    .m_axi_awuser   (),
    .m_axi_awvalid  (a_awvalid),
    .m_axi_awready  (a_awready),
    .m_axi_wdata    (a_wdata),
    .m_axi_wstrb    (a_wstrb),
    .m_axi_wlast    (a_wlast),
    .m_axi_wvalid   (a_wvalid),
    .m_axi_wready   (a_wready),
    .m_axi_bid      (a_bid),
    .m_axi_bresp    (a_bresp),
    .m_axi_bvalid   (a_bvalid),
    .m_axi_bready   (a_bready),
    .m_axi_arid     (a_arid),
    .m_axi_araddr   (a_araddr),
    .m_axi_arlen    (a_arlen),
    .m_axi_arsize   (a_arsize),
    .m_axi_arburst  (a_arburst),
    .m_axi_arlock   (a_arlock),
    .m_axi_arcache  (a_arcache),
    .m_axi_arprot   (a_arprot),
    .m_axi_arregion (),
    .m_axi_arqos    (a_arqos),
    .m_axi_aruser   (),
    .m_axi_arvalid  (a_arvalid),
    .m_axi_arready  (a_arready),
    .m_axi_rid      (a_rid),
    .m_axi_rdata    (a_rdata),
    .m_axi_rresp    (a_rresp),
    .m_axi_rlast    (a_rlast),
    .m_axi_rvalid   (a_rvalid),
    .m_axi_rready   (a_rready)
  );

  //===========================================================================
  // PCIS (host -> DDR4 / HBM loads) -> register slices (SLR1, SLR2)
  //===========================================================================
  logic [15:0]  p1_awid, p1_bid, p1_arid, p1_rid;
  logic [63:0]  p1_awaddr, p1_araddr;
  logic [7:0]   p1_awlen, p1_arlen;
  logic [2:0]   p1_awsize, p1_arsize;
  logic [1:0]   p1_awburst, p1_arburst, p1_bresp, p1_rresp;
  logic [2:0]   p1_awprot, p1_arprot;
  logic         p1_awlock, p1_arlock;
  logic [3:0]   p1_awcache, p1_arcache, p1_awqos, p1_arqos;
  logic         p1_awvalid, p1_awready, p1_wvalid, p1_wready, p1_wlast;
  logic         p1_bvalid, p1_bready, p1_arvalid, p1_arready;
  logic         p1_rvalid, p1_rready, p1_rlast;
  logic [511:0] p1_wdata, p1_rdata;
  logic [63:0]  p1_wstrb;
  logic [15:0]  p_awid, p_bid, p_arid, p_rid;
  logic [63:0]  p_awaddr, p_araddr;
  logic [7:0]   p_awlen, p_arlen;
  logic [2:0]   p_awsize, p_arsize, p_awprot, p_arprot;
  logic [1:0]   p_awburst, p_arburst, p_bresp, p_rresp;
  logic         p_awlock, p_arlock;
  logic [3:0]   p_awcache, p_arcache, p_awqos, p_arqos;
  logic         p_awvalid, p_awready, p_wvalid, p_wready, p_wlast;
  logic         p_bvalid, p_bready, p_arvalid, p_arready;
  logic         p_rvalid, p_rready, p_rlast;
  logic [511:0] p_wdata, p_rdata;
  logic [63:0]  p_wstrb;

  axi_register_slice PCIS_SLC (
    .aclk           (gen_clk_main_a0),
    .aresetn        (main_rst_n),
    .s_axi_awid     (sh_cl_dma_pcis_awid),
    .s_axi_awaddr   (sh_cl_dma_pcis_awaddr),
    .s_axi_awlen    (sh_cl_dma_pcis_awlen),
    .s_axi_awsize   (sh_cl_dma_pcis_awsize),
    .s_axi_awburst  (sh_cl_dma_pcis_awburst),
    .s_axi_awlock   (sh_cl_dma_pcis_awlock),
    .s_axi_awcache  (sh_cl_dma_pcis_awcache),
    .s_axi_awprot   (sh_cl_dma_pcis_awprot),
    .s_axi_awregion (4'd0),
    .s_axi_awqos    (sh_cl_dma_pcis_awqos),
    .s_axi_awvalid  (sh_cl_dma_pcis_awvalid),
    .s_axi_awready  (cl_sh_dma_pcis_awready),
    .s_axi_wdata    (sh_cl_dma_pcis_wdata),
    .s_axi_wstrb    (sh_cl_dma_pcis_wstrb),
    .s_axi_wlast    (sh_cl_dma_pcis_wlast),
    .s_axi_wvalid   (sh_cl_dma_pcis_wvalid),
    .s_axi_wready   (cl_sh_dma_pcis_wready),
    .s_axi_bid      (cl_sh_dma_pcis_bid),
    .s_axi_bresp    (cl_sh_dma_pcis_bresp),
    .s_axi_bvalid   (cl_sh_dma_pcis_bvalid),
    .s_axi_bready   (sh_cl_dma_pcis_bready),
    .s_axi_arid     (sh_cl_dma_pcis_arid),
    .s_axi_araddr   (sh_cl_dma_pcis_araddr),
    .s_axi_arlen    (sh_cl_dma_pcis_arlen),
    .s_axi_arsize   (sh_cl_dma_pcis_arsize),
    .s_axi_arburst  (sh_cl_dma_pcis_arburst),
    .s_axi_arlock   (sh_cl_dma_pcis_arlock),
    .s_axi_arcache  (sh_cl_dma_pcis_arcache),
    .s_axi_arprot   (sh_cl_dma_pcis_arprot),
    .s_axi_arregion (4'd0),
    .s_axi_arqos    (sh_cl_dma_pcis_arqos),
    .s_axi_arvalid  (sh_cl_dma_pcis_arvalid),
    .s_axi_arready  (cl_sh_dma_pcis_arready),
    .s_axi_rid      (cl_sh_dma_pcis_rid),
    .s_axi_rdata    (cl_sh_dma_pcis_rdata),
    .s_axi_rresp    (cl_sh_dma_pcis_rresp),
    .s_axi_rlast    (cl_sh_dma_pcis_rlast),
    .s_axi_rvalid   (cl_sh_dma_pcis_rvalid),
    .s_axi_rready   (sh_cl_dma_pcis_rready),
    .m_axi_awid     (p1_awid),
    .m_axi_awaddr   (p1_awaddr),
    .m_axi_awlen    (p1_awlen),
    .m_axi_awsize   (p1_awsize),
    .m_axi_awburst  (p1_awburst),
    .m_axi_awlock   (p1_awlock),
    .m_axi_awcache  (p1_awcache),
    .m_axi_awprot   (p1_awprot),
    .m_axi_awregion (),
    .m_axi_awqos    (p1_awqos),
    .m_axi_awvalid  (p1_awvalid),
    .m_axi_awready  (p1_awready),
    .m_axi_wdata    (p1_wdata),
    .m_axi_wstrb    (p1_wstrb),
    .m_axi_wlast    (p1_wlast),
    .m_axi_wvalid   (p1_wvalid),
    .m_axi_wready   (p1_wready),
    .m_axi_bid      (p1_bid),
    .m_axi_bresp    (p1_bresp),
    .m_axi_bvalid   (p1_bvalid),
    .m_axi_bready   (p1_bready),
    .m_axi_arid     (p1_arid),
    .m_axi_araddr   (p1_araddr),
    .m_axi_arlen    (p1_arlen),
    .m_axi_arsize   (p1_arsize),
    .m_axi_arburst  (p1_arburst),
    .m_axi_arlock   (p1_arlock),
    .m_axi_arcache  (p1_arcache),
    .m_axi_arprot   (p1_arprot),
    .m_axi_arregion (),
    .m_axi_arqos    (p1_arqos),
    .m_axi_arvalid  (p1_arvalid),
    .m_axi_arready  (p1_arready),
    .m_axi_rid      (p1_rid),
    .m_axi_rdata    (p1_rdata),
    .m_axi_rresp    (p1_rresp),
    .m_axi_rlast    (p1_rlast),
    .m_axi_rvalid   (p1_rvalid),
    .m_axi_rready   (p1_rready)
  );

  // Second PCIS slice in SLR2 (the SmartConnect, DDR4 and SoC live
  // there; PCIS enters in SLR1).
  axi_register_slice PCIS_SLC2 (
    .aclk           (gen_clk_main_a0),
    .aresetn        (main_rst_n),
    .s_axi_awid     (p1_awid),
    .s_axi_awaddr   (p1_awaddr),
    .s_axi_awlen    (p1_awlen),
    .s_axi_awsize   (p1_awsize),
    .s_axi_awburst  (p1_awburst),
    .s_axi_awlock   (p1_awlock),
    .s_axi_awcache  (p1_awcache),
    .s_axi_awprot   (p1_awprot),
    .s_axi_awregion (4'd0),
    .s_axi_awqos    (p1_awqos),
    .s_axi_awvalid  (p1_awvalid),
    .s_axi_awready  (p1_awready),
    .s_axi_wdata     (p1_wdata),
    .s_axi_wstrb     (p1_wstrb),
    .s_axi_wlast     (p1_wlast),
    .s_axi_wvalid    (p1_wvalid),
    .s_axi_wready    (p1_wready),
    .s_axi_bid      (p1_bid),
    .s_axi_bresp     (p1_bresp),
    .s_axi_bvalid    (p1_bvalid),
    .s_axi_bready    (p1_bready),
    .s_axi_arid     (p1_arid),
    .s_axi_araddr   (p1_araddr),
    .s_axi_arlen    (p1_arlen),
    .s_axi_arsize   (p1_arsize),
    .s_axi_arburst  (p1_arburst),
    .s_axi_arlock   (p1_arlock),
    .s_axi_arcache  (p1_arcache),
    .s_axi_arprot   (p1_arprot),
    .s_axi_arregion (4'd0),
    .s_axi_arqos    (p1_arqos),
    .s_axi_arvalid  (p1_arvalid),
    .s_axi_arready  (p1_arready),
    .s_axi_rid      (p1_rid),
    .s_axi_rdata     (p1_rdata),
    .s_axi_rresp     (p1_rresp),
    .s_axi_rlast     (p1_rlast),
    .s_axi_rvalid    (p1_rvalid),
    .s_axi_rready    (p1_rready),
    .m_axi_awid     (p_awid),
    .m_axi_awaddr    (p_awaddr),
    .m_axi_awlen     (p_awlen),
    .m_axi_awsize    (p_awsize),
    .m_axi_awburst   (p_awburst),
    .m_axi_awlock    (p_awlock),
    .m_axi_awcache   (p_awcache),
    .m_axi_awprot    (p_awprot),
    .m_axi_awregion  (),
    .m_axi_awqos     (p_awqos),
    .m_axi_awvalid  (p_awvalid),
    .m_axi_awready  (p_awready),
    .m_axi_wdata     (p_wdata),
    .m_axi_wstrb     (p_wstrb),
    .m_axi_wlast     (p_wlast),
    .m_axi_wvalid    (p_wvalid),
    .m_axi_wready    (p_wready),
    .m_axi_bid      (p_bid),
    .m_axi_bresp     (p_bresp),
    .m_axi_bvalid    (p_bvalid),
    .m_axi_bready    (p_bready),
    .m_axi_arid     (p_arid),
    .m_axi_araddr    (p_araddr),
    .m_axi_arlen     (p_arlen),
    .m_axi_arsize    (p_arsize),
    .m_axi_arburst   (p_arburst),
    .m_axi_arlock    (p_arlock),
    .m_axi_arcache   (p_arcache),
    .m_axi_arprot    (p_arprot),
    .m_axi_arregion  (),
    .m_axi_arqos     (p_arqos),
    .m_axi_arvalid  (p_arvalid),
    .m_axi_arready  (p_arready),
    .m_axi_rid      (p_rid),
    .m_axi_rdata     (p_rdata),
    .m_axi_rresp     (p_rresp),
    .m_axi_rlast     (p_rlast),
    .m_axi_rvalid    (p_rvalid),
    .m_axi_rready   (p_rready)
  );
  assign cl_sh_dma_pcis_ruser = 64'd0;

  //===========================================================================
  // SmartConnect 2x2 (HDK block design): XDMA = PCIS, ATG = SoC
  //===========================================================================
  logic [63:0]  d_awaddr, d_araddr;
  logic [7:0]   d_awlen, d_arlen;
  logic [2:0]   d_awsize, d_arsize;
  logic [1:0]   d_awburst, d_arburst, d_bresp, d_rresp;
  logic         d_awvalid, d_awready, d_wvalid, d_wready, d_wlast;
  logic         d_bvalid, d_bready, d_arvalid, d_arready;
  logic         d_rvalid, d_rready, d_rlast;
  logic [511:0] d_wdata, d_rdata;
  logic [63:0]  d_wstrb;

  logic [63:0]  e_awaddr, e_araddr;
  logic [7:0]   e_awlen, e_arlen;
  logic [2:0]   e_awsize, e_arsize;
  logic [1:0]   e_awburst, e_arburst, e_bresp, e_rresp;
  logic         e_awvalid, e_awready, e_wvalid, e_wready, e_wlast;
  logic         e_bvalid, e_bready, e_arvalid, e_arready;
  logic         e_rvalid, e_rready, e_rlast;
  logic [511:0] e_wdata, e_rdata;
  logic [63:0]  e_wstrb;

  cl_axi_sc_2x2_wrapper DDR_XBAR (
    .aclk_250      (gen_clk_main_a0),
    .aresetn_250   (main_rst_n),

    .XDMA_awid     (p_awid),
    .XDMA_awaddr   (p_awaddr),
    .XDMA_awlen    (p_awlen),
    .XDMA_awsize   (p_awsize),
    .XDMA_awburst  (p_awburst),
    .XDMA_awlock   (p_awlock),
    .XDMA_awcache  (p_awcache),
    .XDMA_awprot   (p_awprot),
    .XDMA_awqos    (p_awqos),
    .XDMA_awvalid  (p_awvalid),
    .XDMA_awready  (p_awready),
    .XDMA_wdata    (p_wdata),
    .XDMA_wstrb    (p_wstrb),
    .XDMA_wlast    (p_wlast),
    .XDMA_wvalid   (p_wvalid),
    .XDMA_wready   (p_wready),
    .XDMA_bid      (p_bid),
    .XDMA_bresp    (p_bresp),
    .XDMA_bvalid   (p_bvalid),
    .XDMA_bready   (p_bready),
    .XDMA_arid     (p_arid),
    .XDMA_araddr   (p_araddr),
    .XDMA_arlen    (p_arlen),
    .XDMA_arsize   (p_arsize),
    .XDMA_arburst  (p_arburst),
    .XDMA_arlock   (p_arlock),
    .XDMA_arcache  (p_arcache),
    .XDMA_arprot   (p_arprot),
    .XDMA_arqos    (p_arqos),
    .XDMA_arvalid  (p_arvalid),
    .XDMA_arready  (p_arready),
    .XDMA_rid      (p_rid),
    .XDMA_rdata    (p_rdata),
    .XDMA_rresp    (p_rresp),
    .XDMA_rlast    (p_rlast),
    .XDMA_rvalid   (p_rvalid),
    .XDMA_rready   (p_rready),

    .ATG_awid      (a_awid),
    .ATG_awaddr    (a_awaddr),
    .ATG_awlen     (a_awlen),
    .ATG_awsize    (a_awsize),
    .ATG_awburst   (a_awburst),
    .ATG_awlock    (a_awlock),
    .ATG_awcache   (a_awcache),
    .ATG_awprot    (a_awprot),
    .ATG_awqos     (a_awqos),
    .ATG_awvalid   (a_awvalid),
    .ATG_awready   (a_awready),
    .ATG_wdata     (a_wdata),
    .ATG_wstrb     (a_wstrb),
    .ATG_wlast     (a_wlast),
    .ATG_wvalid    (a_wvalid),
    .ATG_wready    (a_wready),
    .ATG_bid       (a_bid),
    .ATG_bresp     (a_bresp),
    .ATG_bvalid    (a_bvalid),
    .ATG_bready    (a_bready),
    .ATG_arid      (a_arid),
    .ATG_araddr    (a_araddr),
    .ATG_arlen     (a_arlen),
    .ATG_arsize    (a_arsize),
    .ATG_arburst   (a_arburst),
    .ATG_arlock    (a_arlock),
    .ATG_arcache   (a_arcache),
    .ATG_arprot    (a_arprot),
    .ATG_arqos     (a_arqos),
    .ATG_arvalid   (a_arvalid),
    .ATG_arready   (a_arready),
    .ATG_rid       (a_rid),
    .ATG_rdata     (a_rdata),
    .ATG_rresp     (a_rresp),
    .ATG_rlast     (a_rlast),
    .ATG_rvalid    (a_rvalid),
    .ATG_rready    (a_rready),

    .DDRA_awaddr   (d_awaddr),
    .DDRA_awlen    (d_awlen),
    .DDRA_awsize   (d_awsize),
    .DDRA_awburst  (d_awburst),
    .DDRA_awlock   (),
    .DDRA_awcache  (),
    .DDRA_awprot   (),
    .DDRA_awqos    (),
    .DDRA_awvalid  (d_awvalid),
    .DDRA_awready  (d_awready),
    .DDRA_wdata    (d_wdata),
    .DDRA_wstrb    (d_wstrb),
    .DDRA_wlast    (d_wlast),
    .DDRA_wvalid   (d_wvalid),
    .DDRA_wready   (d_wready),
    .DDRA_bresp    (d_bresp),
    .DDRA_bvalid   (d_bvalid),
    .DDRA_bready   (d_bready),
    .DDRA_araddr   (d_araddr),
    .DDRA_arlen    (d_arlen),
    .DDRA_arsize   (d_arsize),
    .DDRA_arburst  (d_arburst),
    .DDRA_arlock   (),
    .DDRA_arcache  (),
    .DDRA_arprot   (),
    .DDRA_arqos    (),
    .DDRA_arvalid  (d_arvalid),
    .DDRA_arready  (d_arready),
    .DDRA_rdata    (d_rdata),
    .DDRA_rresp    (d_rresp),
    .DDRA_rlast    (d_rlast),
    .DDRA_rvalid   (d_rvalid),
    .DDRA_rready   (d_rready),

    .DDRB_awaddr   (e_awaddr),
    .DDRB_awlen    (e_awlen),
    .DDRB_awsize   (e_awsize),
    .DDRB_awburst  (e_awburst),
    .DDRB_awlock   (),
    .DDRB_awcache  (),
    .DDRB_awprot   (),
    .DDRB_awqos    (),
    .DDRB_awvalid  (e_awvalid),
    .DDRB_awready  (e_awready),
    .DDRB_wdata    (e_wdata),
    .DDRB_wstrb    (e_wstrb),
    .DDRB_wlast    (e_wlast),
    .DDRB_wvalid   (e_wvalid),
    .DDRB_wready   (e_wready),
    .DDRB_bresp    (e_bresp),
    .DDRB_bvalid   (e_bvalid),
    .DDRB_bready   (e_bready),
    .DDRB_araddr   (e_araddr),
    .DDRB_arlen    (e_arlen),
    .DDRB_arsize   (e_arsize),
    .DDRB_arburst  (e_arburst),
    .DDRB_arlock   (),
    .DDRB_arcache  (),
    .DDRB_arprot   (),
    .DDRB_arqos    (),
    .DDRB_arvalid  (e_arvalid),
    .DDRB_arready  (e_arready),
    .DDRB_rdata    (e_rdata),
    .DDRB_rresp    (e_rresp),
    .DDRB_rlast    (e_rlast),
    .DDRB_rvalid   (e_rvalid),
    .DDRB_rready   (e_rready)
  );

  //===========================================================================
  // HBM (16 GiB, SLR0) behind the SmartConnect DDRB port (AXI
  // 0x10_0000_0000 + y): register slices for the SLR2 -> SLR1 -> SLR0
  // crossings, then cl_sigil_hbm. EN_HBM = 0: a DECERR responder.
  //===========================================================================
  logic [15:0]  h2_awid, h2_bid, h2_arid, h2_rid;
  logic [63:0]  h2_awaddr, h2_araddr;
  logic [7:0]   h2_awlen, h2_arlen;
  logic [2:0]   h2_awsize, h2_arsize;
  logic [1:0]   h2_awburst, h2_arburst, h2_bresp, h2_rresp;
  logic [2:0]   h2_awprot, h2_arprot;
  logic         h2_awlock, h2_arlock;
  logic [3:0]   h2_awcache, h2_arcache, h2_awqos, h2_arqos;
  logic         h2_awvalid, h2_awready, h2_wvalid, h2_wready, h2_wlast;
  logic         h2_bvalid, h2_bready, h2_arvalid, h2_arready;
  logic         h2_rvalid, h2_rready, h2_rlast;
  logic [511:0] h2_wdata, h2_rdata;
  logic [63:0]  h2_wstrb;
  logic [15:0]  h1_awid, h1_bid, h1_arid, h1_rid;
  logic [63:0]  h1_awaddr, h1_araddr;
  logic [7:0]   h1_awlen, h1_arlen;
  logic [2:0]   h1_awsize, h1_arsize;
  logic [1:0]   h1_awburst, h1_arburst, h1_bresp, h1_rresp;
  logic [2:0]   h1_awprot, h1_arprot;
  logic         h1_awlock, h1_arlock;
  logic [3:0]   h1_awcache, h1_arcache, h1_awqos, h1_arqos;
  logic         h1_awvalid, h1_awready, h1_wvalid, h1_wready, h1_wlast;
  logic         h1_bvalid, h1_bready, h1_arvalid, h1_arready;
  logic         h1_rvalid, h1_rready, h1_rlast;
  logic [511:0] h1_wdata, h1_rdata;
  logic [63:0]  h1_wstrb;
  logic [15:0]  h0_awid, h0_bid, h0_arid, h0_rid;
  logic [63:0]  h0_awaddr, h0_araddr;
  logic [7:0]   h0_awlen, h0_arlen;
  logic [2:0]   h0_awsize, h0_arsize;
  logic [1:0]   h0_awburst, h0_arburst, h0_bresp, h0_rresp;
  logic [2:0]   h0_awprot, h0_arprot;
  logic         h0_awlock, h0_arlock;
  logic [3:0]   h0_awcache, h0_arcache, h0_awqos, h0_arqos;
  logic         h0_awvalid, h0_awready, h0_wvalid, h0_wready, h0_wlast;
  logic         h0_bvalid, h0_bready, h0_arvalid, h0_arready;
  logic         h0_rvalid, h0_rready, h0_rlast;
  logic [511:0] h0_wdata, h0_rdata;
  logic [63:0]  h0_wstrb;
  axi_register_slice HBM_SLC2 (
    .aclk           (gen_clk_main_a0),
    .aresetn        (main_rst_n),
    .s_axi_awid     (16'd0),
    .s_axi_awaddr   (e_awaddr),
    .s_axi_awlen    (e_awlen),
    .s_axi_awsize   (e_awsize),
    .s_axi_awburst  (e_awburst),
    .s_axi_awlock   (1'b0),
    .s_axi_awcache  (4'd3),
    .s_axi_awprot   (3'd0),
    .s_axi_awregion (4'd0),
    .s_axi_awqos    (4'd0),
    .s_axi_awvalid  (e_awvalid),
    .s_axi_awready  (e_awready),
    .s_axi_wdata     (e_wdata),
    .s_axi_wstrb     (e_wstrb),
    .s_axi_wlast     (e_wlast),
    .s_axi_wvalid    (e_wvalid),
    .s_axi_wready    (e_wready),
    .s_axi_bid      (),
    .s_axi_bresp     (e_bresp),
    .s_axi_bvalid    (e_bvalid),
    .s_axi_bready    (e_bready),
    .s_axi_arid     (16'd0),
    .s_axi_araddr   (e_araddr),
    .s_axi_arlen    (e_arlen),
    .s_axi_arsize   (e_arsize),
    .s_axi_arburst  (e_arburst),
    .s_axi_arlock   (1'b0),
    .s_axi_arcache  (4'd3),
    .s_axi_arprot   (3'd0),
    .s_axi_arregion (4'd0),
    .s_axi_arqos    (4'd0),
    .s_axi_arvalid  (e_arvalid),
    .s_axi_arready  (e_arready),
    .s_axi_rid      (),
    .s_axi_rdata     (e_rdata),
    .s_axi_rresp     (e_rresp),
    .s_axi_rlast     (e_rlast),
    .s_axi_rvalid    (e_rvalid),
    .s_axi_rready    (e_rready),
    .m_axi_awid     (h2_awid),
    .m_axi_awaddr    (h2_awaddr),
    .m_axi_awlen     (h2_awlen),
    .m_axi_awsize    (h2_awsize),
    .m_axi_awburst   (h2_awburst),
    .m_axi_awlock    (),
    .m_axi_awcache   (),
    .m_axi_awprot    (),
    .m_axi_awregion  (),
    .m_axi_awqos     (),
    .m_axi_awvalid  (h2_awvalid),
    .m_axi_awready  (h2_awready),
    .m_axi_wdata     (h2_wdata),
    .m_axi_wstrb     (h2_wstrb),
    .m_axi_wlast     (h2_wlast),
    .m_axi_wvalid    (h2_wvalid),
    .m_axi_wready    (h2_wready),
    .m_axi_bid      (h2_bid),
    .m_axi_bresp     (h2_bresp),
    .m_axi_bvalid    (h2_bvalid),
    .m_axi_bready    (h2_bready),
    .m_axi_arid     (h2_arid),
    .m_axi_araddr    (h2_araddr),
    .m_axi_arlen     (h2_arlen),
    .m_axi_arsize    (h2_arsize),
    .m_axi_arburst   (h2_arburst),
    .m_axi_arlock    (),
    .m_axi_arcache   (),
    .m_axi_arprot    (),
    .m_axi_arregion  (),
    .m_axi_arqos     (),
    .m_axi_arvalid  (h2_arvalid),
    .m_axi_arready  (h2_arready),
    .m_axi_rid      (h2_rid),
    .m_axi_rdata     (h2_rdata),
    .m_axi_rresp     (h2_rresp),
    .m_axi_rlast     (h2_rlast),
    .m_axi_rvalid    (h2_rvalid),
    .m_axi_rready   (h2_rready)
  );
  axi_register_slice HBM_SLC1 (
    .aclk           (gen_clk_main_a0),
    .aresetn        (main_rst_n),
    .s_axi_awid     (h2_awid),
    .s_axi_awaddr   (h2_awaddr),
    .s_axi_awlen    (h2_awlen),
    .s_axi_awsize   (h2_awsize),
    .s_axi_awburst  (h2_awburst),
    .s_axi_awlock   (1'b0),
    .s_axi_awcache  (4'd3),
    .s_axi_awprot   (3'd0),
    .s_axi_awregion (4'd0),
    .s_axi_awqos    (4'd0),
    .s_axi_awvalid  (h2_awvalid),
    .s_axi_awready  (h2_awready),
    .s_axi_wdata     (h2_wdata),
    .s_axi_wstrb     (h2_wstrb),
    .s_axi_wlast     (h2_wlast),
    .s_axi_wvalid    (h2_wvalid),
    .s_axi_wready    (h2_wready),
    .s_axi_bid      (h2_bid),
    .s_axi_bresp     (h2_bresp),
    .s_axi_bvalid    (h2_bvalid),
    .s_axi_bready    (h2_bready),
    .s_axi_arid     (h2_arid),
    .s_axi_araddr   (h2_araddr),
    .s_axi_arlen    (h2_arlen),
    .s_axi_arsize   (h2_arsize),
    .s_axi_arburst  (h2_arburst),
    .s_axi_arlock   (1'b0),
    .s_axi_arcache  (4'd3),
    .s_axi_arprot   (3'd0),
    .s_axi_arregion (4'd0),
    .s_axi_arqos    (4'd0),
    .s_axi_arvalid  (h2_arvalid),
    .s_axi_arready  (h2_arready),
    .s_axi_rid      (h2_rid),
    .s_axi_rdata     (h2_rdata),
    .s_axi_rresp     (h2_rresp),
    .s_axi_rlast     (h2_rlast),
    .s_axi_rvalid    (h2_rvalid),
    .s_axi_rready    (h2_rready),
    .m_axi_awid     (h1_awid),
    .m_axi_awaddr    (h1_awaddr),
    .m_axi_awlen     (h1_awlen),
    .m_axi_awsize    (h1_awsize),
    .m_axi_awburst   (h1_awburst),
    .m_axi_awlock    (),
    .m_axi_awcache   (),
    .m_axi_awprot    (),
    .m_axi_awregion  (),
    .m_axi_awqos     (),
    .m_axi_awvalid  (h1_awvalid),
    .m_axi_awready  (h1_awready),
    .m_axi_wdata     (h1_wdata),
    .m_axi_wstrb     (h1_wstrb),
    .m_axi_wlast     (h1_wlast),
    .m_axi_wvalid    (h1_wvalid),
    .m_axi_wready    (h1_wready),
    .m_axi_bid      (h1_bid),
    .m_axi_bresp     (h1_bresp),
    .m_axi_bvalid    (h1_bvalid),
    .m_axi_bready    (h1_bready),
    .m_axi_arid     (h1_arid),
    .m_axi_araddr    (h1_araddr),
    .m_axi_arlen     (h1_arlen),
    .m_axi_arsize    (h1_arsize),
    .m_axi_arburst   (h1_arburst),
    .m_axi_arlock    (),
    .m_axi_arcache   (),
    .m_axi_arprot    (),
    .m_axi_arregion  (),
    .m_axi_arqos     (),
    .m_axi_arvalid  (h1_arvalid),
    .m_axi_arready  (h1_arready),
    .m_axi_rid      (h1_rid),
    .m_axi_rdata     (h1_rdata),
    .m_axi_rresp     (h1_rresp),
    .m_axi_rlast     (h1_rlast),
    .m_axi_rvalid    (h1_rvalid),
    .m_axi_rready   (h1_rready)
  );
  axi_register_slice HBM_SLC0 (
    .aclk           (gen_clk_main_a0),
    .aresetn        (main_rst_n),
    .s_axi_awid     (h1_awid),
    .s_axi_awaddr   (h1_awaddr),
    .s_axi_awlen    (h1_awlen),
    .s_axi_awsize   (h1_awsize),
    .s_axi_awburst  (h1_awburst),
    .s_axi_awlock   (1'b0),
    .s_axi_awcache  (4'd3),
    .s_axi_awprot   (3'd0),
    .s_axi_awregion (4'd0),
    .s_axi_awqos    (4'd0),
    .s_axi_awvalid  (h1_awvalid),
    .s_axi_awready  (h1_awready),
    .s_axi_wdata     (h1_wdata),
    .s_axi_wstrb     (h1_wstrb),
    .s_axi_wlast     (h1_wlast),
    .s_axi_wvalid    (h1_wvalid),
    .s_axi_wready    (h1_wready),
    .s_axi_bid      (h1_bid),
    .s_axi_bresp     (h1_bresp),
    .s_axi_bvalid    (h1_bvalid),
    .s_axi_bready    (h1_bready),
    .s_axi_arid     (h1_arid),
    .s_axi_araddr   (h1_araddr),
    .s_axi_arlen    (h1_arlen),
    .s_axi_arsize   (h1_arsize),
    .s_axi_arburst  (h1_arburst),
    .s_axi_arlock   (1'b0),
    .s_axi_arcache  (4'd3),
    .s_axi_arprot   (3'd0),
    .s_axi_arregion (4'd0),
    .s_axi_arqos    (4'd0),
    .s_axi_arvalid  (h1_arvalid),
    .s_axi_arready  (h1_arready),
    .s_axi_rid      (h1_rid),
    .s_axi_rdata     (h1_rdata),
    .s_axi_rresp     (h1_rresp),
    .s_axi_rlast     (h1_rlast),
    .s_axi_rvalid    (h1_rvalid),
    .s_axi_rready    (h1_rready),
    .m_axi_awid     (h0_awid),
    .m_axi_awaddr    (h0_awaddr),
    .m_axi_awlen     (h0_awlen),
    .m_axi_awsize    (h0_awsize),
    .m_axi_awburst   (h0_awburst),
    .m_axi_awlock    (),
    .m_axi_awcache   (),
    .m_axi_awprot    (),
    .m_axi_awregion  (),
    .m_axi_awqos     (),
    .m_axi_awvalid  (h0_awvalid),
    .m_axi_awready  (h0_awready),
    .m_axi_wdata     (h0_wdata),
    .m_axi_wstrb     (h0_wstrb),
    .m_axi_wlast     (h0_wlast),
    .m_axi_wvalid    (h0_wvalid),
    .m_axi_wready    (h0_wready),
    .m_axi_bid      (h0_bid),
    .m_axi_bresp     (h0_bresp),
    .m_axi_bvalid    (h0_bvalid),
    .m_axi_bready    (h0_bready),
    .m_axi_arid     (h0_arid),
    .m_axi_araddr    (h0_araddr),
    .m_axi_arlen     (h0_arlen),
    .m_axi_arsize    (h0_arsize),
    .m_axi_arburst   (h0_arburst),
    .m_axi_arlock    (),
    .m_axi_arcache   (),
    .m_axi_arprot    (),
    .m_axi_arregion  (),
    .m_axi_arqos     (),
    .m_axi_arvalid  (h0_arvalid),
    .m_axi_arready  (h0_arready),
    .m_axi_rid      (h0_rid),
    .m_axi_rdata     (h0_rdata),
    .m_axi_rresp     (h0_rresp),
    .m_axi_rlast     (h0_rlast),
    .m_axi_rvalid    (h0_rvalid),
    .m_axi_rready   (h0_rready)
  );

  logic hbm_axi_rst_n;      // clk_hbm_axi
  xpm_cdc_async_rst CDC_RST_HBM_AXI (
    .src_arst  (gen_rst_hbm_axi_n),
    .dest_clk  (gen_clk_hbm_axi),
    .dest_arst (hbm_axi_rst_n)
  );

  generate
    if (EN_HBM != 0) begin : G_HBM
      cl_sigil_hbm HBM (
        .clk                (gen_clk_main_a0),
        .rst_n              (main_rst_n),
        .clk_hbm_ref        (gen_clk_hbm_ref),
        .clk_hbm_axi        (gen_clk_hbm_axi),
        .hbm_axi_rst_n      (hbm_axi_rst_n),
        .s_axi_awid         (h0_awid),
        .s_axi_awaddr       (h0_awaddr),
        .s_axi_awlen        (h0_awlen),
        .s_axi_awsize       (h0_awsize),
        .s_axi_awburst      (h0_awburst),
        .s_axi_awvalid      (h0_awvalid),
        .s_axi_awready      (h0_awready),
        .s_axi_wdata        (h0_wdata),
        .s_axi_wstrb        (h0_wstrb),
        .s_axi_wlast        (h0_wlast),
        .s_axi_wvalid       (h0_wvalid),
        .s_axi_wready       (h0_wready),
        .s_axi_bid          (h0_bid),
        .s_axi_bresp        (h0_bresp),
        .s_axi_bvalid       (h0_bvalid),
        .s_axi_bready       (h0_bready),
        .s_axi_arid         (h0_arid),
        .s_axi_araddr       (h0_araddr),
        .s_axi_arlen        (h0_arlen),
        .s_axi_arsize       (h0_arsize),
        .s_axi_arburst      (h0_arburst),
        .s_axi_arvalid      (h0_arvalid),
        .s_axi_arready      (h0_arready),
        .s_axi_rid          (h0_rid),
        .s_axi_rdata        (h0_rdata),
        .s_axi_rresp        (h0_rresp),
        .s_axi_rlast        (h0_rlast),
        .s_axi_rvalid       (h0_rvalid),
        .s_axi_rready       (h0_rready),
        .hbm_apb_preset_n_1 (hbm_apb_preset_n_1),
        .hbm_apb_paddr_1    (hbm_apb_paddr_1),
        .hbm_apb_pprot_1    (hbm_apb_pprot_1),
        .hbm_apb_psel_1     (hbm_apb_psel_1),
        .hbm_apb_penable_1  (hbm_apb_penable_1),
        .hbm_apb_pwrite_1   (hbm_apb_pwrite_1),
        .hbm_apb_pwdata_1   (hbm_apb_pwdata_1),
        .hbm_apb_pstrb_1    (hbm_apb_pstrb_1),
        .hbm_apb_pready_1   (hbm_apb_pready_1),
        .hbm_apb_prdata_1   (hbm_apb_prdata_1),
        .hbm_apb_pslverr_1  (hbm_apb_pslverr_1),
        .hbm_apb_preset_n_0 (hbm_apb_preset_n_0),
        .hbm_apb_paddr_0    (hbm_apb_paddr_0),
        .hbm_apb_pprot_0    (hbm_apb_pprot_0),
        .hbm_apb_psel_0     (hbm_apb_psel_0),
        .hbm_apb_penable_0  (hbm_apb_penable_0),
        .hbm_apb_pwrite_0   (hbm_apb_pwrite_0),
        .hbm_apb_pwdata_0   (hbm_apb_pwdata_0),
        .hbm_apb_pstrb_0    (hbm_apb_pstrb_0),
        .hbm_apb_pready_0   (hbm_apb_pready_0),
        .hbm_apb_prdata_0   (hbm_apb_prdata_0),
        .hbm_apb_pslverr_0  (hbm_apb_pslverr_0),
        .hbm_ready_o        (hbm_ready)
      );
    end else begin : G_NO_HBM
      // Nothing above 64 GiB: answer DECERR so a stray host access
      // completes instead of hanging the PCIe request.
      sigil_axi_decerr #(.DATA_W(512)) DDRB_DECERR (
        .clk_i       (gen_clk_main_a0),
        .rst_ni      (main_rst_n),
        .s_awvalid_i (h0_awvalid),
        .s_awready_o (h0_awready),
        .s_wvalid_i  (h0_wvalid),
        .s_wlast_i   (h0_wlast),
        .s_wready_o  (h0_wready),
        .s_bresp_o   (h0_bresp),
        .s_bvalid_o  (h0_bvalid),
        .s_bready_i  (h0_bready),
        .s_arvalid_i (h0_arvalid),
        .s_arlen_i   (h0_arlen),
        .s_arready_o (h0_arready),
        .s_rdata_o   (h0_rdata),
        .s_rresp_o   (h0_rresp),
        .s_rlast_o   (h0_rlast),
        .s_rvalid_o  (h0_rvalid),
        .s_rready_i  (h0_rready)
      );
      assign h0_bid = h0_awid;
      assign h0_rid = h0_arid;
      assign hbm_ready = 1'b0;
      always_comb begin
        hbm_apb_paddr_1   = '0;
        hbm_apb_pprot_1   = '0;
        hbm_apb_psel_1    = '0;
        hbm_apb_penable_1 = '0;
        hbm_apb_pwrite_1  = '0;
        hbm_apb_pwdata_1  = '0;
        hbm_apb_pstrb_1   = '0;
        hbm_apb_pready_1  = '0;
        hbm_apb_prdata_1  = '0;
        hbm_apb_pslverr_1 = '0;
        hbm_apb_paddr_0   = '0;
        hbm_apb_pprot_0   = '0;
        hbm_apb_psel_0    = '0;
        hbm_apb_penable_0 = '0;
        hbm_apb_pwrite_0  = '0;
        hbm_apb_pwdata_0  = '0;
        hbm_apb_pstrb_0   = '0;
        hbm_apb_pready_0  = '0;
        hbm_apb_prdata_0  = '0;
        hbm_apb_pslverr_0 = '0;
      end
    end
  endgenerate

  //===========================================================================
  // Shell DDR4 (sh_ddr): resets from rst_main_n only, stat bus piped
  //===========================================================================
  localparam NUM_CFG_STGS_CL_DDR_ATG = 8;

  logic  [7:0] sh_ddr_stat_addr_q;
  logic        sh_ddr_stat_wr_q, sh_ddr_stat_rd_q;
  logic [31:0] sh_ddr_stat_wdata_q;
  logic        ddr_sh_stat_ack_q;
  logic [31:0] ddr_sh_stat_rdata_q;
  logic  [7:0] ddr_sh_stat_int_q;

  lib_pipe #(.WIDTH(1+1+8+32), .STAGES(NUM_CFG_STGS_CL_DDR_ATG)) PIPE_DDR_STAT0 (
    .clk     (gen_clk_main_a0),
    .rst_n   (rst_main_sync_n),
    .in_bus  ({sh_cl_ddr_stat_wr, sh_cl_ddr_stat_rd, sh_cl_ddr_stat_addr,
               sh_cl_ddr_stat_wdata}),
    .out_bus ({sh_ddr_stat_wr_q, sh_ddr_stat_rd_q, sh_ddr_stat_addr_q,
               sh_ddr_stat_wdata_q})
  );

  lib_pipe #(.WIDTH(1+8+32), .STAGES(NUM_CFG_STGS_CL_DDR_ATG)) PIPE_DDR_STAT_ACK0 (
    .clk     (gen_clk_main_a0),
    .rst_n   (rst_main_sync_n),
    .in_bus  ({ddr_sh_stat_ack_q, ddr_sh_stat_int_q, ddr_sh_stat_rdata_q}),
    .out_bus ({cl_sh_ddr_stat_ack, cl_sh_ddr_stat_int, cl_sh_ddr_stat_rdata})
  );

  logic [15:0] ddr_bid_unused, ddr_rid_unused;

  sh_ddr #(.DDR_PRESENT(EN_DDR)) SH_DDR (
    .clk                   (gen_clk_main_a0),
    .rst_n                 (rst_main_sync_n),
    .stat_clk              (gen_clk_main_a0),
    .stat_rst_n            (rst_main_sync_n),
    .CLK_DIMM_DP           (CLK_DIMM_DP),
    .CLK_DIMM_DN           (CLK_DIMM_DN),
    .M_ACT_N               (M_ACT_N),
    .M_MA                  (M_MA),
    .M_BA                  (M_BA),
    .M_BG                  (M_BG),
    .M_CKE                 (M_CKE),
    .M_ODT                 (M_ODT),
    .M_CS_N                (M_CS_N),
    .M_CLK_DN              (M_CLK_DN),
    .M_CLK_DP              (M_CLK_DP),
    .M_PAR                 (M_PAR),
    .M_DQ                  (M_DQ),
    .M_ECC                 (M_ECC),
    .M_DQS_DP              (M_DQS_DP),
    .M_DQS_DN              (M_DQS_DN),
    .cl_RST_DIMM_N         (RST_DIMM_N),
    .cl_sh_ddr_axi_awid    (16'd0),
    .cl_sh_ddr_axi_awaddr  (d_awaddr),
    .cl_sh_ddr_axi_awlen   (d_awlen),
    .cl_sh_ddr_axi_awsize  (d_awsize),
    .cl_sh_ddr_axi_awvalid (d_awvalid),
    .cl_sh_ddr_axi_awburst (d_awburst),
    .cl_sh_ddr_axi_awuser  (1'd0),
    .cl_sh_ddr_axi_awready (d_awready),
    .cl_sh_ddr_axi_wdata   (d_wdata),
    .cl_sh_ddr_axi_wstrb   (d_wstrb),
    .cl_sh_ddr_axi_wlast   (d_wlast),
    .cl_sh_ddr_axi_wvalid  (d_wvalid),
    .cl_sh_ddr_axi_wready  (d_wready),
    .cl_sh_ddr_axi_bid     (ddr_bid_unused),
    .cl_sh_ddr_axi_bresp   (d_bresp),
    .cl_sh_ddr_axi_bvalid  (d_bvalid),
    .cl_sh_ddr_axi_bready  (d_bready),
    .cl_sh_ddr_axi_arid    (16'd0),
    .cl_sh_ddr_axi_araddr  (d_araddr),
    .cl_sh_ddr_axi_arlen   (d_arlen),
    .cl_sh_ddr_axi_arsize  (d_arsize),
    .cl_sh_ddr_axi_arvalid (d_arvalid),
    .cl_sh_ddr_axi_arburst (d_arburst),
    .cl_sh_ddr_axi_aruser  (1'd0),
    .cl_sh_ddr_axi_arready (d_arready),
    .cl_sh_ddr_axi_rid     (ddr_rid_unused),
    .cl_sh_ddr_axi_rdata   (d_rdata),
    .cl_sh_ddr_axi_rresp   (d_rresp),
    .cl_sh_ddr_axi_rlast   (d_rlast),
    .cl_sh_ddr_axi_rvalid  (d_rvalid),
    .cl_sh_ddr_axi_rready  (d_rready),
    .sh_ddr_stat_bus_addr  (sh_ddr_stat_addr_q),
    .sh_ddr_stat_bus_wdata (sh_ddr_stat_wdata_q),
    .sh_ddr_stat_bus_wr    (sh_ddr_stat_wr_q),
    .sh_ddr_stat_bus_rd    (sh_ddr_stat_rd_q),
    .sh_ddr_stat_bus_ack   (ddr_sh_stat_ack_q),
    .sh_ddr_stat_bus_rdata (ddr_sh_stat_rdata_q),
    .ddr_sh_stat_int       (ddr_sh_stat_int_q),
    .sh_cl_ddr_is_ready    (ddr_ready)
  );

  //===========================================================================
  // Unused Shell interfaces (HDK CL_TEMPLATE tie-offs)
  //===========================================================================
  // PCIM: no host-memory master.
  always_comb begin
    cl_sh_pcim_awid    = '0;
    cl_sh_pcim_awaddr  = '0;
    cl_sh_pcim_awlen   = '0;
    cl_sh_pcim_awsize  = '0;
    cl_sh_pcim_awburst = '0;
    cl_sh_pcim_awcache = '0;
    cl_sh_pcim_awlock  = '0;
    cl_sh_pcim_awprot  = '0;
    cl_sh_pcim_awqos   = '0;
    cl_sh_pcim_awuser  = '0;
    cl_sh_pcim_awvalid = '0;
    cl_sh_pcim_wid     = '0;
    cl_sh_pcim_wdata   = '0;
    cl_sh_pcim_wstrb   = '0;
    cl_sh_pcim_wlast   = '0;
    cl_sh_pcim_wuser   = '0;
    cl_sh_pcim_wvalid  = '0;
    cl_sh_pcim_bready  = '0;
    cl_sh_pcim_arid    = '0;
    cl_sh_pcim_araddr  = '0;
    cl_sh_pcim_arlen   = '0;
    cl_sh_pcim_arsize  = '0;
    cl_sh_pcim_arburst = '0;
    cl_sh_pcim_arcache = '0;
    cl_sh_pcim_arlock  = '0;
    cl_sh_pcim_arprot  = '0;
    cl_sh_pcim_arqos   = '0;
    cl_sh_pcim_aruser  = '0;
    cl_sh_pcim_arvalid = '0;
    cl_sh_pcim_rready  = '0;
  end

  // Interrupts, virtual JTAG, PCIe pass-through pins.
  always_comb begin
    cl_sh_apppf_irq_req = '0;
    tdo = 1'b0;


    PCIE_EP_TXP    = '0;
    PCIE_EP_TXN    = '0;
    PCIE_RP_PERSTN = '0;
    PCIE_RP_TXP    = '0;
    PCIE_RP_TXN    = '0;
  end

endmodule // cl_sigil
