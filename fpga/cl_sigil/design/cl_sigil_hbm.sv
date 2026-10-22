// HBM for the Sigil CL (issue #66): one 512-bit AXI4 slave port on
// clk_main_a0 that reaches all 16 GiB of the F2 HBM.
//
//   s_axi (AXI4, 512 b, clk_main_a0; address bits [33:0] used: the
//          SmartConnect DDRB segment starts at 0x10_0000_0000, so the
//          low 34 bits are the HBM offset)
//     -> cl_axi_sc_1x1 (HDK block design: AXI4 -> AXI3, 512 -> 256 b,
//        clk_main_a0 -> clk_hbm_axi; bursts split to AXI3 length)
//     -> cl_axi3_256b_reg_slice (clk_hbm_axi)
//     -> cl_mem_hbm_wrapper (HDK cl_mem_perf example: the cl_hbm IP,
//        16 GiB / two stacks / 32 pseudo channels, switch enabled =
//        global addressing, so AXI port 0 reaches every pseudo channel;
//        the IP's "Customer Address Map" option stays disabled, AWS
//        ERRATA: address aliasing in 16 GB mode) on port 0, the other
//        31 ports tied off.
//
// clk_hbm_axi is AWS_CLK_GEN's HBM group (recipe H2 = 450 MHz, as the
// HDK cl_mem_perf example); clk_hbm_ref (100 MHz) clocks the HBM APB
// and the Shell's HBM monitor ports (hbm_apb_*). hbm_ready_o (clk_main_a0)
// is high once both stacks report APB init complete. The HBM IP has
// ECC disabled (cl_hbm.xci), so uninitialised HBM reads cleanly.
//
// SIGIL_HBM_BFM (XSIM only: the HDK simulates the HBM IP with VCS or
// Questa only): a behavioural sparse AXI4 memory on s_axi instead,
// ready 1 us after reset, so the CL tests still exercise the SoC /
// PCIS -> SmartConnect -> SLR register slices -> HBM routing.
module cl_sigil_hbm (
  input  logic          clk,             // clk_main_a0
  input  logic          rst_n,           // synchronized to clk
  input  logic          clk_hbm_ref,     // 100 MHz
  input  logic          clk_hbm_axi,     // 450 MHz (AWS_CLK_GEN H2)
  input  logic          hbm_axi_rst_n,   // synchronized to clk_hbm_axi
  // AXI4 slave (from the SmartConnect DDRB port via register slices)
  input  logic [15:0]   s_axi_awid,
  input  logic [63:0]   s_axi_awaddr,
  input  logic [7:0]    s_axi_awlen,
  input  logic [2:0]    s_axi_awsize,
  input  logic [1:0]    s_axi_awburst,
  input  logic          s_axi_awvalid,
  output logic          s_axi_awready,
  input  logic [511:0]  s_axi_wdata,
  input  logic [63:0]   s_axi_wstrb,
  input  logic          s_axi_wlast,
  input  logic          s_axi_wvalid,
  output logic          s_axi_wready,
  output logic [15:0]   s_axi_bid,
  output logic [1:0]    s_axi_bresp,
  output logic          s_axi_bvalid,
  input  logic          s_axi_bready,
  input  logic [15:0]   s_axi_arid,
  input  logic [63:0]   s_axi_araddr,
  input  logic [7:0]    s_axi_arlen,
  input  logic [2:0]    s_axi_arsize,
  input  logic [1:0]    s_axi_arburst,
  input  logic          s_axi_arvalid,
  output logic          s_axi_arready,
  output logic [15:0]   s_axi_rid,
  output logic [511:0]  s_axi_rdata,
  output logic [1:0]    s_axi_rresp,
  output logic          s_axi_rlast,
  output logic          s_axi_rvalid,
  input  logic          s_axi_rready,
  // Shell HBM monitor (APB, clk_hbm_ref)
  input  logic          hbm_apb_preset_n_1,
  output logic [21:0]   hbm_apb_paddr_1,
  output logic  [2:0]   hbm_apb_pprot_1,
  output logic          hbm_apb_psel_1,
  output logic          hbm_apb_penable_1,
  output logic          hbm_apb_pwrite_1,
  output logic [31:0]   hbm_apb_pwdata_1,
  output logic  [3:0]   hbm_apb_pstrb_1,
  output logic          hbm_apb_pready_1,
  output logic [31:0]   hbm_apb_prdata_1,
  output logic          hbm_apb_pslverr_1,
  input  logic          hbm_apb_preset_n_0,
  output logic [21:0]   hbm_apb_paddr_0,
  output logic  [2:0]   hbm_apb_pprot_0,
  output logic          hbm_apb_psel_0,
  output logic          hbm_apb_penable_0,
  output logic          hbm_apb_pwrite_0,
  output logic [31:0]   hbm_apb_pwdata_0,
  output logic  [3:0]   hbm_apb_pstrb_0,
  output logic          hbm_apb_pready_0,
  output logic [31:0]   hbm_apb_prdata_0,
  output logic          hbm_apb_pslverr_0,
  output logic          hbm_ready_o      // clk domain
);

`ifndef SIGIL_HBM_BFM
  //---------------------------------------------------------------------------
  // AXI4 512 b @ clk -> AXI3 256 b @ clk_hbm_axi
  //---------------------------------------------------------------------------
  logic [63:0]  a3_araddr, a3_awaddr;
  logic [1:0]   a3_arburst, a3_awburst, a3_bresp, a3_rresp;
  logic [3:0]   a3_arlen, a3_awlen;
  logic [2:0]   a3_arsize, a3_awsize;
  logic         a3_arvalid, a3_arready, a3_awvalid, a3_awready;
  logic         a3_bvalid, a3_bready, a3_rvalid, a3_rready, a3_rlast;
  logic [255:0] a3_wdata, a3_rdata;
  logic [31:0]  a3_wstrb;
  logic         a3_wlast, a3_wvalid, a3_wready;

  cl_axi_sc_1x1_wrapper AXI_CONVERTER_AXI4_AXI3 (
    .aclk_250     (clk),
    .aresetn_250  (rst_n),
    .aclk_450     (clk_hbm_axi),
    .AXI4_araddr  (s_axi_araddr),
    .AXI4_arburst (s_axi_arburst),
    .AXI4_arcache (4'd3),
    .AXI4_arid    (s_axi_arid),
    .AXI4_arlen   (s_axi_arlen),
    .AXI4_arlock  (1'b0),
    .AXI4_arprot  (3'd0),
    .AXI4_arqos   (4'd0),
    .AXI4_arready (s_axi_arready),
    .AXI4_arsize  (s_axi_arsize),
    .AXI4_arvalid (s_axi_arvalid),
    .AXI4_awaddr  (s_axi_awaddr),
    .AXI4_awburst (s_axi_awburst),
    .AXI4_awcache (4'd3),
    .AXI4_awid    (s_axi_awid),
    .AXI4_awlen   (s_axi_awlen),
    .AXI4_awlock  (1'b0),
    .AXI4_awprot  (3'd0),
    .AXI4_awqos   (4'd0),
    .AXI4_awready (s_axi_awready),
    .AXI4_awsize  (s_axi_awsize),
    .AXI4_awvalid (s_axi_awvalid),
    .AXI4_bid     (s_axi_bid),
    .AXI4_bready  (s_axi_bready),
    .AXI4_bresp   (s_axi_bresp),
    .AXI4_bvalid  (s_axi_bvalid),
    .AXI4_rdata   (s_axi_rdata),
    .AXI4_rid     (s_axi_rid),
    .AXI4_rlast   (s_axi_rlast),
    .AXI4_rready  (s_axi_rready),
    .AXI4_rresp   (s_axi_rresp),
    .AXI4_rvalid  (s_axi_rvalid),
    .AXI4_wdata   (s_axi_wdata),
    .AXI4_wlast   (s_axi_wlast),
    .AXI4_wready  (s_axi_wready),
    .AXI4_wstrb   (s_axi_wstrb),
    .AXI4_wvalid  (s_axi_wvalid),
    .AXI3_araddr  (a3_araddr),
    .AXI3_arburst (a3_arburst),
    .AXI3_arcache (),
    .AXI3_arlen   (a3_arlen),
    .AXI3_arlock  (),
    .AXI3_arprot  (),
    .AXI3_arqos   (),
    .AXI3_arready (a3_arready),
    .AXI3_arsize  (a3_arsize),
    .AXI3_arvalid (a3_arvalid),
    .AXI3_awaddr  (a3_awaddr),
    .AXI3_awburst (a3_awburst),
    .AXI3_awcache (),
    .AXI3_awlen   (a3_awlen),
    .AXI3_awlock  (),
    .AXI3_awprot  (),
    .AXI3_awqos   (),
    .AXI3_awready (a3_awready),
    .AXI3_awsize  (a3_awsize),
    .AXI3_awvalid (a3_awvalid),
    .AXI3_bready  (a3_bready),
    .AXI3_bresp   (a3_bresp),
    .AXI3_bvalid  (a3_bvalid),
    .AXI3_rdata   (a3_rdata),
    .AXI3_rlast   (a3_rlast),
    .AXI3_rready  (a3_rready),
    .AXI3_rresp   (a3_rresp),
    .AXI3_rvalid  (a3_rvalid),
    .AXI3_wdata   (a3_wdata),
    .AXI3_wlast   (a3_wlast),
    .AXI3_wready  (a3_wready),
    .AXI3_wstrb   (a3_wstrb),
    .AXI3_wvalid  (a3_wvalid)
  );

  // AXI3 register slice in the HBM clock domain.
  logic [5:0]   q_awid, q_arid, q_bid, q_rid, q_wid;
  logic [33:0]  q_awaddr, q_araddr;
  logic [3:0]   q_awlen, q_arlen;
  logic [2:0]   q_awsize, q_arsize;
  logic [1:0]   q_awburst, q_arburst, q_bresp, q_rresp;
  logic         q_awvalid, q_awready, q_wvalid, q_wready, q_wlast;
  logic         q_bvalid, q_bready, q_arvalid, q_arready;
  logic         q_rvalid, q_rready, q_rlast;
  logic [255:0] q_wdata, q_rdata;
  logic [31:0]  q_wstrb;
  logic [5:0]   a3_bid_unused, a3_rid_unused;

  cl_axi3_256b_reg_slice AXI3_REG_SLC_HBM (
    .aclk          (clk_hbm_axi),
    .aresetn       (hbm_axi_rst_n),
    .s_axi_awid    (6'd0),
    .s_axi_awaddr  (a3_awaddr[33:0]),
    .s_axi_awlen   (a3_awlen),
    .s_axi_awsize  (a3_awsize),
    .s_axi_awburst (a3_awburst),
    .s_axi_awlock  (2'd0),
    .s_axi_awcache (4'd3),
    .s_axi_awprot  (3'd0),
    .s_axi_awqos   (4'd0),
    .s_axi_awvalid (a3_awvalid),
    .s_axi_awready (a3_awready),
    .s_axi_wid     (6'd0),
    .s_axi_wdata   (a3_wdata),
    .s_axi_wstrb   (a3_wstrb),
    .s_axi_wlast   (a3_wlast),
    .s_axi_wvalid  (a3_wvalid),
    .s_axi_wready  (a3_wready),
    .s_axi_bid     (a3_bid_unused),
    .s_axi_bresp   (a3_bresp),
    .s_axi_bvalid  (a3_bvalid),
    .s_axi_bready  (a3_bready),
    .s_axi_arid    (6'd0),
    .s_axi_araddr  (a3_araddr[33:0]),
    .s_axi_arlen   (a3_arlen),
    .s_axi_arsize  (a3_arsize),
    .s_axi_arburst (a3_arburst),
    .s_axi_arlock  (2'd0),
    .s_axi_arcache (4'd3),
    .s_axi_arprot  (3'd0),
    .s_axi_arqos   (4'd0),
    .s_axi_arvalid (a3_arvalid),
    .s_axi_arready (a3_arready),
    .s_axi_rid     (a3_rid_unused),
    .s_axi_rdata   (a3_rdata),
    .s_axi_rresp   (a3_rresp),
    .s_axi_rlast   (a3_rlast),
    .s_axi_rvalid  (a3_rvalid),
    .s_axi_rready  (a3_rready),
    .m_axi_awid    (q_awid),
    .m_axi_awaddr  (q_awaddr),
    .m_axi_awlen   (q_awlen),
    .m_axi_awsize  (q_awsize),
    .m_axi_awburst (q_awburst),
    .m_axi_awlock  (),
    .m_axi_awcache (),
    .m_axi_awprot  (),
    .m_axi_awqos   (),
    .m_axi_awvalid (q_awvalid),
    .m_axi_awready (q_awready),
    .m_axi_wid     (q_wid),
    .m_axi_wdata   (q_wdata),
    .m_axi_wstrb   (q_wstrb),
    .m_axi_wlast   (q_wlast),
    .m_axi_wvalid  (q_wvalid),
    .m_axi_wready  (q_wready),
    .m_axi_bid     (q_bid),
    .m_axi_bresp   (q_bresp),
    .m_axi_bvalid  (q_bvalid),
    .m_axi_bready  (q_bready),
    .m_axi_arid    (q_arid),
    .m_axi_araddr  (q_araddr),
    .m_axi_arlen   (q_arlen),
    .m_axi_arsize  (q_arsize),
    .m_axi_arburst (q_arburst),
    .m_axi_arlock  (),
    .m_axi_arcache (),
    .m_axi_arprot  (),
    .m_axi_arqos   (),
    .m_axi_arvalid (q_arvalid),
    .m_axi_arready (q_arready),
    .m_axi_rid     (q_rid),
    .m_axi_rdata   (q_rdata),
    .m_axi_rresp   (q_rresp),
    .m_axi_rlast   (q_rlast),
    .m_axi_rvalid  (q_rvalid),
    .m_axi_rready  (q_rready)
  );

  //---------------------------------------------------------------------------
  // HBM IP (HDK cl_mem_hbm_wrapper, one AXI3 port)
  //---------------------------------------------------------------------------
  logic [33:0]  h_araddr  [0:0];
  logic [1:0]   h_arburst [0:0];
  logic [5:0]   h_arid    [0:0];
  logic [3:0]   h_arlen   [0:0];
  logic [2:0]   h_arsize  [0:0];
  logic         h_arvalid [0:0];
  logic [33:0]  h_awaddr  [0:0];
  logic [1:0]   h_awburst [0:0];
  logic [5:0]   h_awid    [0:0];
  logic [3:0]   h_awlen   [0:0];
  logic [2:0]   h_awsize  [0:0];
  logic         h_awvalid [0:0];
  logic         h_rready  [0:0];
  logic         h_bready  [0:0];
  logic [255:0] h_wdata   [0:0];
  logic         h_wlast   [0:0];
  logic [31:0]  h_wstrb   [0:0];
  logic         h_wvalid  [0:0];
  logic         h_arready [0:0];
  logic         h_awready [0:0];
  logic [255:0] h_rdata   [0:0];
  logic [5:0]   h_rid     [0:0];
  logic         h_rlast   [0:0];
  logic [1:0]   h_rresp   [0:0];
  logic         h_rvalid  [0:0];
  logic         h_wready  [0:0];
  logic [5:0]   h_bid     [0:0];
  logic [1:0]   h_bresp   [0:0];
  logic         h_bvalid  [0:0];

  always_comb begin
    h_araddr[0]  = q_araddr;
    h_arburst[0] = q_arburst;
    h_arid[0]    = q_arid;
    h_arlen[0]   = q_arlen;
    h_arsize[0]  = q_arsize;
    h_arvalid[0] = q_arvalid;
    h_awaddr[0]  = q_awaddr;
    h_awburst[0] = q_awburst;
    h_awid[0]    = q_awid;
    h_awlen[0]   = q_awlen;
    h_awsize[0]  = q_awsize;
    h_awvalid[0] = q_awvalid;
    h_rready[0]  = q_rready;
    h_bready[0]  = q_bready;
    h_wdata[0]   = q_wdata;
    h_wlast[0]   = q_wlast;
    h_wstrb[0]   = q_wstrb;
    h_wvalid[0]  = q_wvalid;
    q_arready    = h_arready[0];
    q_awready    = h_awready[0];
    q_rdata      = h_rdata[0];
    q_rid        = h_rid[0];
    q_rlast      = h_rlast[0];
    q_rresp      = h_rresp[0];
    q_rvalid     = h_rvalid[0];
    q_wready     = h_wready[0];
    q_bid        = h_bid[0];
    q_bresp      = h_bresp[0];
    q_bvalid     = h_bvalid[0];
  end

  cfg_bus_t hbm_stat_bus();
  assign hbm_stat_bus.addr  = '0;
  assign hbm_stat_bus.wdata = '0;
  assign hbm_stat_bus.wr    = 1'b0;
  assign hbm_stat_bus.rd    = 1'b0;
  assign hbm_stat_bus.user  = '0;

  cl_mem_hbm_wrapper #(
    .NUM_OF_AXI_PORTS (1),
    .AXI4_INTERFACE   (0),
    .AXLEN_WIDTH      (4)
  ) HBM_WRAPPER_I (
    .apb_clk              (clk_hbm_ref),
    .i_clk_250m           (clk),
    .i_rst_250m_n         (rst_n),
    .i_clk_450m           (clk_hbm_axi),
    .i_rst_450m_n         (hbm_axi_rst_n),
    .i_axi_araddr         (h_araddr),
    .i_axi_arburst        (h_arburst),
    .i_axi_arid           (h_arid),
    .i_axi_arlen          (h_arlen),
    .i_axi_arsize         (h_arsize),
    .i_axi_arvalid        (h_arvalid),
    .i_axi_awaddr         (h_awaddr),
    .i_axi_awburst        (h_awburst),
    .i_axi_awid           (h_awid),
    .i_axi_awlen          (h_awlen),
    .i_axi_awsize         (h_awsize),
    .i_axi_awvalid        (h_awvalid),
    .i_axi_rready         (h_rready),
    .i_axi_bready         (h_bready),
    .i_axi_wdata          (h_wdata),
    .i_axi_wlast          (h_wlast),
    .i_axi_wstrb          (h_wstrb),
    .i_axi_wvalid         (h_wvalid),
    .o_axi_arready        (h_arready),
    .o_axi_awready        (h_awready),
    .o_axi_rdata          (h_rdata),
    .o_axi_rid            (h_rid),
    .o_axi_rlast          (h_rlast),
    .o_axi_rresp          (h_rresp),
    .o_axi_rvalid         (h_rvalid),
    .o_axi_wready         (h_wready),
    .o_axi_bid            (h_bid),
    .o_axi_bresp          (h_bresp),
    .o_axi_bvalid         (h_bvalid),
    .i_hbm_apb_preset_n_1 (hbm_apb_preset_n_1),
    .o_hbm_apb_paddr_1    (hbm_apb_paddr_1),
    .o_hbm_apb_pprot_1    (hbm_apb_pprot_1),
    .o_hbm_apb_psel_1     (hbm_apb_psel_1),
    .o_hbm_apb_penable_1  (hbm_apb_penable_1),
    .o_hbm_apb_pwrite_1   (hbm_apb_pwrite_1),
    .o_hbm_apb_pwdata_1   (hbm_apb_pwdata_1),
    .o_hbm_apb_pstrb_1    (hbm_apb_pstrb_1),
    .o_hbm_apb_pready_1   (hbm_apb_pready_1),
    .o_hbm_apb_prdata_1   (hbm_apb_prdata_1),
    .o_hbm_apb_pslverr_1  (hbm_apb_pslverr_1),
    .i_hbm_apb_preset_n_0 (hbm_apb_preset_n_0),
    .o_hbm_apb_paddr_0    (hbm_apb_paddr_0),
    .o_hbm_apb_pprot_0    (hbm_apb_pprot_0),
    .o_hbm_apb_psel_0     (hbm_apb_psel_0),
    .o_hbm_apb_penable_0  (hbm_apb_penable_0),
    .o_hbm_apb_pwrite_0   (hbm_apb_pwrite_0),
    .o_hbm_apb_pwdata_0   (hbm_apb_pwdata_0),
    .o_hbm_apb_pstrb_0    (hbm_apb_pstrb_0),
    .o_hbm_apb_pready_0   (hbm_apb_pready_0),
    .o_hbm_apb_prdata_0   (hbm_apb_prdata_0),
    .o_hbm_apb_pslverr_0  (hbm_apb_pslverr_0),
    .hbm_stat_bus         (hbm_stat_bus),
    .o_cl_sh_hbm_stat_int (),
    .o_hbm_ready          (hbm_ready_o)
  );

`else  // SIGIL_HBM_BFM
  //---------------------------------------------------------------------------
  // XSIM stand-in: sparse 64-byte-line memory, one transaction of each
  // kind at a time, OKAY responses, IDs echoed.
  //---------------------------------------------------------------------------
  logic [511:0] mem [longint unsigned];
  logic [33:0]  aw_a, ar_a;
  logic [15:0]  aw_id, ar_id;
  logic [7:0]   ar_left;
  logic         aw_busy, ar_busy, b_pend;
  int           rdy_cnt;

  assign s_axi_awready = !aw_busy && !b_pend;
  assign s_axi_wready  = aw_busy;
  assign s_axi_arready = !ar_busy;
  assign s_axi_bresp   = 2'b00;
  assign s_axi_rresp   = 2'b00;
  assign s_axi_bid     = aw_id;
  assign s_axi_rid     = ar_id;
  assign s_axi_rlast   = (ar_left == 8'd0);
  assign s_axi_rvalid  = ar_busy;
  assign s_axi_bvalid  = b_pend;
  always_comb begin
    s_axi_rdata = mem.exists(ar_a[33:6]) ? mem[ar_a[33:6]] : '0;
  end

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      aw_busy <= 1'b0; ar_busy <= 1'b0; b_pend <= 1'b0;
      ar_left <= 8'd0; rdy_cnt <= 0; hbm_ready_o <= 1'b0;
    end else begin
      if (rdy_cnt < 250) rdy_cnt <= rdy_cnt + 1;
      else hbm_ready_o <= 1'b1;
      if (s_axi_awvalid && s_axi_awready) begin
        aw_busy <= 1'b1;
        aw_a <= s_axi_awaddr[33:0];
        aw_id <= s_axi_awid;
      end
      if (s_axi_wvalid && s_axi_wready) begin
        logic [511:0] line;
        line = mem.exists(aw_a[33:6]) ? mem[aw_a[33:6]] : '0;
        for (int b = 0; b < 64; b++)
          if (s_axi_wstrb[b]) line[8*b +: 8] = s_axi_wdata[8*b +: 8];
        mem[aw_a[33:6]] = line;
        aw_a <= aw_a + 34'd64;
        if (s_axi_wlast) begin
          aw_busy <= 1'b0;
          b_pend <= 1'b1;
        end
      end
      if (s_axi_bvalid && s_axi_bready) b_pend <= 1'b0;
      if (s_axi_arvalid && s_axi_arready) begin
        ar_busy <= 1'b1;
        ar_a <= s_axi_araddr[33:0];
        ar_id <= s_axi_arid;
        ar_left <= s_axi_arlen;
      end else if (s_axi_rvalid && s_axi_rready) begin
        if (ar_left == 8'd0) ar_busy <= 1'b0;
        else begin
          ar_left <= ar_left - 8'd1;
          ar_a <= ar_a + 34'd64;
        end
      end
    end
  end

  always_comb begin
    hbm_apb_paddr_1 = '0; hbm_apb_pprot_1 = '0; hbm_apb_psel_1 = '0;
    hbm_apb_penable_1 = '0; hbm_apb_pwrite_1 = '0; hbm_apb_pwdata_1 = '0;
    hbm_apb_pstrb_1 = '0; hbm_apb_pready_1 = '0; hbm_apb_prdata_1 = '0;
    hbm_apb_pslverr_1 = '0;
    hbm_apb_paddr_0 = '0; hbm_apb_pprot_0 = '0; hbm_apb_psel_0 = '0;
    hbm_apb_penable_0 = '0; hbm_apb_pwrite_0 = '0; hbm_apb_pwdata_0 = '0;
    hbm_apb_pstrb_0 = '0; hbm_apb_pready_0 = '0; hbm_apb_prdata_0 = '0;
    hbm_apb_pslverr_0 = '0;
  end
`endif
endmodule
