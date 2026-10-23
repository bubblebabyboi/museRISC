// Sigil memory bus ("mbus", protocol in rtl/core/sigil_cpu.sv) to
// AXI4 master bridge (issue #52, FPGA F1). Serves the SoC's
// external RAM port (sigil_soc_top mem_*) from an AXI4 slave such
// as the AWS F2 Shell DDR4 interface.
//
// Transaction mapping (one mbus transaction at a time, so all AXI
// transactions are in order on a single ID, AXI_ID):
//   mbus read, len = 0   -> AR, ARLEN 0, ARSIZE 3 (8 bytes) at the
//                           8-byte-aligned address; the response
//                           beat is the addressed 64-bit lane.
//   mbus read, len = L   -> AR INCR burst, ARSIZE = log2(DATA_W/8),
//                           ARLEN = (L+1)/RATIO - 1; every wide R
//                           beat is returned as RATIO 64-bit mbus
//                           beats, lowest lane first.
//   mbus write, len = 0  -> AW (ARLEN 0, size 3) + one W beat with
//                           req_be on the addressed lane, then B
//                           -> one ack beat.
//   mbus write, len = L  -> AW INCR burst as for reads; the L+1
//                           request beats (each with its own beat
//                           address) are packed RATIO per W beat,
//                           WLAST on the last; B -> one ack beat.
// RATIO = AXI_DATA_W/64. Bursts are the L1 line refills/write-
// backs (64-byte lines, line-aligned, 8 beats), so for
// AXI_DATA_W up to 512 they are a whole number of wide beats from
// a DATA_W-aligned address: 64 -> 8 beats, 128 -> 4, 256 -> 2,
// 512 -> 1 (the F2 Shell DDR4 width). Simulation checks flag any
// burst that is not.
//
// Address map: requests in the RAM window [MEM_BASE, MEM_BASE +
// MEM_SIZE) go to AXI address AXI_BASE + (addr - MEM_BASE), truncated
// to AXI_ADDR_W (no aliasing). With the defaults the SoC RAM window
// 0x8000_0000 + 128 MiB lands at AXI offset 0 (simulation builds); the
// F2 build sets MEM_SIZE = 80 GiB: DDR4 at AXI 0x0 and HBM at AXI
// 0x10_0000_0000 (docs/LINUX_PLATFORM.md). A request outside the
// window is not sent to AXI: a read returns zero beats, a write is
// dropped, and both are acknowledged normally and recorded as an
// error (the mbus has no error response).
//
// Errors (issue #62): AXI error responses (xRESP != OKAY), responses
// with an unexpected ID and out-of-window requests set the sticky
// err_o and count in err_count_o; the first one since the last
// err_clr_i pulse (or reset) is captured: err_addr_o = SoC address of
// the transaction, err_info_o = {valid, write, out_of_window,
// id_mismatch, xRESP[1:0], 2'b0, req_len[7:0], response ID[15:0]}.
// The data/ack is still returned.
//
// Handshakes: every AXI output is a flop (no combinational path
// from the AXI slave to the mbus or back). RREADY/BREADY are high
// whenever a response can be taken (RREADY drops only while a
// wide beat is being unpacked); req_ready is high in idle and,
// during a write burst, whenever the W holding register is free
// (64-bit AXI: one beat every two cycles; DDR latency dominates).
// AW and W are offered independently (AXI forbids a slave from
// waiting for W before AW and vice versa is allowed, so no
// deadlock).
//
// quiesce_i: stop accepting new mbus requests (the transaction in
// progress completes); idle_o is high when none is in progress.
// The FPGA top uses this to put the SoC in reset only between
// transactions, so the AXI side never sees a torn burst.
`default_nettype none
module sigil_mbus_axi4 #(
    parameter int unsigned AXI_ID_W   = 16,
    parameter int unsigned AXI_ADDR_W = 64,
    parameter int unsigned AXI_DATA_W = 64,   // 64, 128, 256 or 512
    parameter logic [AXI_ID_W-1:0] AXI_ID = '0,
    parameter logic [63:0] MEM_BASE = 64'h0000_0000_8000_0000,
    parameter logic [63:0] MEM_SIZE = 64'h0000_0000_0800_0000,
    parameter logic [63:0] AXI_BASE = 64'h0
) (
    input  wire                    clk_i,
    input  wire                    rst_ni,
    input  wire                    quiesce_i,
    output logic                   idle_o,
    // Error status (sticky until err_clr_i).
    input  wire                    err_clr_i,
    output logic                   err_o,
    output logic [63:0]            err_addr_o,
    output logic [31:0]            err_info_o,
    output logic [31:0]            err_count_o,
    // mbus slave (from sigil_soc_top mem_*)
    input  wire                    req_valid_i,
    output logic                   req_ready_o,
    input  wire [63:0]             req_addr_i,
    input  wire                    req_write_i,
    input  wire [7:0]              req_len_i,
    input  wire [63:0]             req_wdata_i,
    input  wire [7:0]              req_be_i,
    input  wire                    req_last_i,
    input  wire                    req_inst_i,
    output logic                   rsp_valid_o,
    output logic [63:0]            rsp_rdata_o,
    output logic                   rsp_last_o,
    // AXI4 master: write address
    output logic [AXI_ID_W-1:0]    m_axi_awid,
    output logic [AXI_ADDR_W-1:0]  m_axi_awaddr,
    output logic [7:0]             m_axi_awlen,
    output logic [2:0]             m_axi_awsize,
    output logic [1:0]             m_axi_awburst,
    output logic                   m_axi_awlock,
    output logic [3:0]             m_axi_awcache,
    output logic [2:0]             m_axi_awprot,
    output logic [3:0]             m_axi_awqos,
    output logic                   m_axi_awvalid,
    input  wire                    m_axi_awready,
    // write data
    output logic [AXI_DATA_W-1:0]  m_axi_wdata,
    output logic [AXI_DATA_W/8-1:0] m_axi_wstrb,
    output logic                   m_axi_wlast,
    output logic                   m_axi_wvalid,
    input  wire                    m_axi_wready,
    // write response
    input  wire [AXI_ID_W-1:0]     m_axi_bid,
    input  wire [1:0]              m_axi_bresp,
    input  wire                    m_axi_bvalid,
    output logic                   m_axi_bready,
    // read address
    output logic [AXI_ID_W-1:0]    m_axi_arid,
    output logic [AXI_ADDR_W-1:0]  m_axi_araddr,
    output logic [7:0]             m_axi_arlen,
    output logic [2:0]             m_axi_arsize,
    output logic [1:0]             m_axi_arburst,
    output logic                   m_axi_arlock,
    output logic [3:0]             m_axi_arcache,
    output logic [2:0]             m_axi_arprot,
    output logic [3:0]             m_axi_arqos,
    output logic                   m_axi_arvalid,
    input  wire                    m_axi_arready,
    // read data
    input  wire [AXI_ID_W-1:0]     m_axi_rid,
    input  wire [AXI_DATA_W-1:0]   m_axi_rdata,
    input  wire [1:0]              m_axi_rresp,
    input  wire                    m_axi_rlast,
    input  wire                    m_axi_rvalid,
    output logic                   m_axi_rready
);
  localparam int unsigned RATIO = AXI_DATA_W / 64;
  localparam int unsigned RSH = $clog2(RATIO);          // log2(RATIO)
  localparam int unsigned LB = $clog2(AXI_DATA_W / 8);  // byte-offset bits
  localparam int unsigned LANE_W = (RATIO > 1) ? RSH : 1;
  localparam logic [2:0] SIZE_WIDE = 3'(LB);
  localparam logic [2:0] SIZE_NARROW = 3'd3;
  localparam int unsigned DW = AXI_DATA_W;
  localparam int unsigned SW = AXI_DATA_W / 8;

  // S_ORD / S_OWR: an out-of-window read / write served locally.
  typedef enum logic [2:0] {S_IDLE, S_RD, S_WR, S_WB, S_ORD, S_OWR} state_e;
  state_e st_q;

  // Request decode.
  logic        req_fire, req_burst, req_inwin;
  logic [63:0] req_off;
  logic [AXI_ADDR_W-1:0] req_axaddr;
  logic [7:0]  req_axlen;
  logic [2:0]  req_axsize;
  logic [8:0]  req_beats;
  logic [LANE_W-1:0] req_lane;

  assign req_fire = req_valid_i && req_ready_o;
  assign req_burst = (req_len_i != 8'd0);
  assign req_inwin = (req_addr_i >= MEM_BASE) && ((req_addr_i - MEM_BASE) < MEM_SIZE);
  assign req_off = AXI_BASE + (req_addr_i - MEM_BASE);
  assign req_beats = {1'b0, req_len_i} + 9'd1;
  always_comb begin
    if (req_burst) begin
      req_axaddr = AXI_ADDR_W'({req_off[63:LB], LB'(0)});
      req_axlen = 8'((req_beats >> RSH) - 9'd1);
      req_axsize = SIZE_WIDE;
    end else begin
      req_axaddr = AXI_ADDR_W'({req_off[63:3], 3'd0});
      req_axlen = 8'd0;
      req_axsize = SIZE_NARROW;
    end
  end
  // 64-bit lane of the beat address within a wide AXI beat.
  if (RATIO > 1) begin : g_lane
    assign req_lane = req_addr_i[LB-1:3];
  end else begin : g_lane1
    assign req_lane = 1'b0;
  end

  // AXI address channels (registered).
  logic                  arvalid_q, awvalid_q;
  logic [AXI_ADDR_W-1:0] axaddr_q;
  logic [7:0]            axlen_q;
  logic [2:0]            axsize_q;
  logic                  inst_q;
  // W holding register + gather of 64-bit beats into a wide beat.
  logic          wvalid_q, wlast_q;
  logic [DW-1:0] wdata_q, gdata_q, gdata_n;
  logic [SW-1:0] wstrb_q, gstrb_q, gstrb_n;
  logic          wr_burst_q, w_complete;
  logic          bgot_q;
  // Read unpacking.
  logic              rd_burst_q;
  logic [LANE_W-1:0] rd_lane_q;
  logic [DW-1:0]     rbuf_q;
  logic [RSH:0]      rcnt_q;    // 64-bit pieces left in rbuf_q
  logic              rlast_q;   // rbuf_q holds the RLAST beat
  logic              ack_q;
  logic              err_q;
  // Out-of-window read beats still to return.
  logic [8:0]        ocnt_q;
  // Transaction being served (for the error capture).
  logic [63:0]       txn_addr_q;
  logic [7:0]        txn_len_q;
  logic [63:0]       cap_addr_q;
  logic [31:0]       cap_info_q, err_cnt_q;
  // Error event this cycle (at most one source per cycle: B, R and
  // a new request are mutually exclusive in time for one transaction).
  logic              ev;
  logic [63:0]       ev_addr;
  logic [31:0]       ev_info;

  logic r_fire, b_fire;
  assign r_fire = m_axi_rvalid && m_axi_rready;
  assign b_fire = m_axi_bvalid && m_axi_bready;

  always_comb begin
    req_ready_o = ((st_q == S_IDLE) && !quiesce_i) ||
                  ((st_q == S_WR) && !wvalid_q) || (st_q == S_OWR);
    idle_o = (st_q == S_IDLE) && !ack_q;
    err_o = err_q;
    err_addr_o = cap_addr_q;
    err_info_o = cap_info_q;
    err_count_o = err_cnt_q;
    rsp_valid_o = (rcnt_q != '0) || ack_q || (st_q == S_ORD);
    rsp_rdata_o = (st_q == S_ORD) ? 64'd0 : rbuf_q[63:0];
    rsp_last_o = ack_q || ((rcnt_q == (RSH + 1)'(1)) && rlast_q) ||
                 ((st_q == S_ORD) && (ocnt_q == 9'd1));
    // Gather the accepted write beat into its 64-bit lane.
    gdata_n = gdata_q;
    gstrb_n = gstrb_q;
    gdata_n[64*req_lane +: 64] = req_wdata_i;
    gstrb_n[8*req_lane +: 8] = req_be_i;
    // A wide W beat is complete on a single-beat write, on the
    // top lane, or on the last beat of the burst.
    w_complete = !(st_q == S_WR ? wr_burst_q : req_burst) ||
                 (req_lane == LANE_W'(RATIO - 1)) || req_last_i;
  end

  // Error events: an out-of-window request, or a B / R beat with an
  // error response or a foreign ID.
  logic b_bad, r_bad;
  assign b_bad = b_fire && (m_axi_bresp != 2'b00 || m_axi_bid != AXI_ID);
  assign r_bad = r_fire && (m_axi_rresp != 2'b00 || m_axi_rid != AXI_ID);
  always_comb begin
    ev = 1'b0;
    ev_addr = txn_addr_q;
    ev_info = 32'd0;
    if (req_fire && st_q == S_IDLE && !req_inwin) begin
      ev = 1'b1;
      ev_addr = req_addr_i;
      ev_info = {1'b1, req_write_i, 1'b1, 1'b0, 2'b11, 2'b00, req_len_i, 16'd0};
    end else if (b_bad) begin
      ev = 1'b1;
      ev_info = {1'b1, 1'b1, 1'b0, m_axi_bid != AXI_ID, m_axi_bresp, 2'b00,
                 txn_len_q, 16'(m_axi_bid)};
    end else if (r_bad) begin
      ev = 1'b1;
      ev_info = {1'b1, 1'b0, 1'b0, m_axi_rid != AXI_ID, m_axi_rresp, 2'b00,
                 txn_len_q, 16'(m_axi_rid)};
    end
  end

  // AXI outputs.
  always_comb begin
    m_axi_awid = AXI_ID;
    m_axi_awaddr = axaddr_q;
    m_axi_awlen = axlen_q;
    m_axi_awsize = axsize_q;
    m_axi_awburst = 2'b01;      // INCR
    m_axi_awlock = 1'b0;
    m_axi_awcache = 4'b0011;    // normal, non-cacheable, bufferable
    m_axi_awprot = 3'b000;      // unprivileged, secure, data
    m_axi_awqos = 4'd0;
    m_axi_awvalid = awvalid_q;
    m_axi_wdata = wdata_q;
    m_axi_wstrb = wstrb_q;
    m_axi_wlast = wlast_q;
    m_axi_wvalid = wvalid_q;
    m_axi_bready = (st_q == S_WR) || (st_q == S_WB);
    m_axi_arid = AXI_ID;
    m_axi_araddr = axaddr_q;
    m_axi_arlen = axlen_q;
    m_axi_arsize = axsize_q;
    m_axi_arburst = 2'b01;
    m_axi_arlock = 1'b0;
    m_axi_arcache = 4'b0011;
    m_axi_arprot = {inst_q, 2'b00};
    m_axi_arqos = 4'd0;
    m_axi_arvalid = arvalid_q;
    m_axi_rready = (st_q == S_RD) &&
                   ((rcnt_q == '0) || (rcnt_q == (RSH + 1)'(1)));
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      st_q <= S_IDLE;
      arvalid_q <= 1'b0;
      awvalid_q <= 1'b0;
      axaddr_q <= '0;
      axlen_q <= 8'd0;
      axsize_q <= 3'd0;
      inst_q <= 1'b0;
      wvalid_q <= 1'b0;
      wlast_q <= 1'b0;
      wdata_q <= '0;
      wstrb_q <= '0;
      gdata_q <= '0;
      gstrb_q <= '0;
      wr_burst_q <= 1'b0;
      bgot_q <= 1'b0;
      rd_burst_q <= 1'b0;
      rd_lane_q <= '0;
      rbuf_q <= '0;
      rcnt_q <= '0;
      rlast_q <= 1'b0;
      ack_q <= 1'b0;
      err_q <= 1'b0;
      ocnt_q <= 9'd0;
      txn_addr_q <= 64'd0;
      txn_len_q <= 8'd0;
      cap_addr_q <= 64'd0;
      cap_info_q <= 32'd0;
      err_cnt_q <= 32'd0;
    end else begin
      ack_q <= 1'b0;
      // Error status: a clear, then this cycle's event (an event in
      // the clearing cycle is kept).
      if (err_clr_i) begin
        err_q <= 1'b0;
        cap_info_q <= 32'd0;
        err_cnt_q <= 32'd0;
      end
      if (ev) begin
        err_q <= 1'b1;
        if (!err_q || err_clr_i) begin
          cap_addr_q <= ev_addr;
          cap_info_q <= ev_info;
        end
        if (err_clr_i) err_cnt_q <= 32'd1;
        else if (err_cnt_q != 32'hFFFF_FFFF) err_cnt_q <= err_cnt_q + 32'd1;
      end
      if (m_axi_arvalid && m_axi_arready) arvalid_q <= 1'b0;
      if (m_axi_awvalid && m_axi_awready) awvalid_q <= 1'b0;
      if (m_axi_wvalid && m_axi_wready) wvalid_q <= 1'b0;

      // Request beats (IDLE: first beat of any request; WR: the
      // remaining beats of a write burst).
      if (req_fire && st_q == S_IDLE) begin
        txn_addr_q <= req_addr_i;
        txn_len_q <= req_len_i;
      end
      if (req_fire && (st_q == S_OWR || (st_q == S_IDLE && !req_inwin))) begin
        // Out of the RAM window: no AXI transaction.
        if (req_write_i) begin
          if (req_last_i) begin
            ack_q <= 1'b1;
            st_q <= S_IDLE;
          end else begin
            st_q <= S_OWR;
          end
        end else begin
          ocnt_q <= {1'b0, req_len_i} + 9'd1;
          st_q <= S_ORD;
        end
      end else if (req_fire) begin
        if (st_q == S_IDLE) begin
          axaddr_q <= req_axaddr;
          axlen_q <= req_axlen;
          axsize_q <= req_axsize;
          inst_q <= req_inst_i;
        end
        if (!req_write_i) begin
          arvalid_q <= 1'b1;
          rd_burst_q <= req_burst;
          rd_lane_q <= req_lane;
          st_q <= S_RD;
        end else begin
          if (st_q == S_IDLE) begin
            awvalid_q <= 1'b1;
            wr_burst_q <= req_burst;
          end
          if (w_complete) begin
            wvalid_q <= 1'b1;
            wdata_q <= gdata_n;
            wstrb_q <= gstrb_n;
            wlast_q <= req_last_i;
            gdata_q <= '0;
            gstrb_q <= '0;
          end else begin
            gdata_q <= gdata_n;
            gstrb_q <= gstrb_n;
          end
          st_q <= req_last_i ? S_WB : S_WR;
        end
      end

      // Write response: one ack beat once B is in (B can only
      // follow the AW handshake and the WLAST beat).
      if (b_fire) bgot_q <= 1'b1;
      // Out-of-window read: zero beats, one per cycle.
      if (st_q == S_ORD) begin
        ocnt_q <= ocnt_q - 9'd1;
        if (ocnt_q == 9'd1) st_q <= S_IDLE;
      end
      if (st_q == S_WB && bgot_q) begin
        bgot_q <= 1'b0;
        ack_q <= 1'b1;
        st_q <= S_IDLE;
      end

      // Read data: load a beat when the unpack buffer is empty or
      // on its last piece; otherwise shift out the next piece.
      if (r_fire) begin
        rlast_q <= m_axi_rlast;
        if (rd_burst_q) begin
          rbuf_q <= m_axi_rdata;
          rcnt_q <= (RSH + 1)'(RATIO);
        end else begin
          rbuf_q <= m_axi_rdata >> {rd_lane_q, 6'd0};
          rcnt_q <= (RSH + 1)'(1);
        end
      end else if (rcnt_q != '0) begin
        rcnt_q <= rcnt_q - 1'b1;
        rbuf_q <= rbuf_q >> 64;
        if (rcnt_q == (RSH + 1)'(1) && rlast_q) st_q <= S_IDLE;
      end
    end
  end

`ifndef SYNTHESIS
  // Simulation-only protocol checks on the mbus side (the AXI
  // side is checked by the testbench slave model).
  logic chk_live_q;
  logic [8:0] wbeat_q;
  initial chk_live_q = 1'b0;
  always @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      chk_live_q <= 1'b0;
      wbeat_q <= 9'd0;
    end else begin
      chk_live_q <= 1'b1;
      if (req_fire && req_write_i) begin
        wbeat_q <= req_last_i ? 9'd0 : wbeat_q + 9'd1;
      end
    end
  end
  logic [8:0] wlen_q;
  always @(posedge clk_i) begin
    if (req_fire && st_q == S_IDLE) wlen_q <= {1'b0, req_len_i};
  end
  // Bursts must be a whole number of wide beats from a wide-aligned
  // address (true for line bursts of >= DATA_W/8 bytes).
  a_burst_shape: assert property (@(posedge clk_i) disable iff (!chk_live_q)
      (req_fire && st_q == S_IDLE && req_burst) |->
        (((req_beats & 9'(RATIO - 1)) == 9'd0) &&
         (req_off[LB-1:0] == '0)))
    else $error("mbus_axi4: burst not a whole number of %0d-bit beats", AXI_DATA_W);
  // A write burst's request beats walk the line in order and end
  // with req_last on beat len.
  a_wlast: assert property (@(posedge clk_i) disable iff (!chk_live_q)
      (req_fire && req_write_i) |->
        (req_last_i == ((st_q == S_IDLE ? 9'd0 : wbeat_q) ==
                        (st_q == S_IDLE ? {1'b0, req_len_i} : wlen_q))))
    else $error("mbus_axi4: req_last on the wrong write beat");
  // (Vivado 2025.2 xelab segfaults on the LB'() cast inside the
  // property, so the beat's lane is computed outside it.)
  logic [8:0] wbeat_lane;
  assign wbeat_lane = 9'(req_addr_i[LB-1:0]) >> 3;
  a_wbeat_addr: assert property (@(posedge clk_i) disable iff (!chk_live_q)
      (req_fire && req_write_i && st_q == S_WR) |->
        (wbeat_lane == (wbeat_q & 9'(RATIO - 1))))
    else $error("mbus_axi4: write burst beat address out of order");
`endif
endmodule
`default_nettype wire
