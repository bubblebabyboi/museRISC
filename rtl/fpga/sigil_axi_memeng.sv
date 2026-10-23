// AXI4 memory engine for the F2 platform (issues #62, #65, #66):
// fills, pattern-writes or checks a range of the AXI address space
// with full-width INCR bursts and several bursts in flight, so the
// host can
//   - scrub DDR4 after an AFI load: the Shell DDR4 controller has ECC
//     and answers reads of never-written locations with an
//     uncorrectable-ECC SLVERR -- the spurious STATUS.mem_err of #62,
//     raised by the first D$ refill of an unloaded line (e.g. the
//     stack) -- so all of DDR4 is written once before the SoC runs;
//   - run a full-range memory test of DDR4 and HBM at AXI speed
//     (write an address pattern, read it back and compare).
//
// Modes (mode_i, sampled at start_i):
//   bit 0  pattern: 0 = every 64-bit word = seed_i,
//                   1 = word at AXI byte address A = A ^ seed_i
//   bit 1  0 = write the pattern, 1 = read and compare with it
// Range: base_i / size_i in bytes, both multiples of BURST_BYTES
// (4 KiB at 512 bits; min(4 KiB, 256 beats)); size 0 completes at
// once. Every burst is AXI_ID, so responses are in order. Status:
// busy_o; done_o (set at completion, cleared by the next start);
// fail_o = any mismatch or error response in the last run;
// mism_count_o = mismatching 64-bit words; fail_addr_o = AXI address
// of the first one; resp_err_o = error responses (B, or R beats);
// cycles_o = clk_i cycles the run took. start_i is ignored while
// busy. The caller must not let anything else drive the AXI port
// while busy_o (sigil_fpga_top muxes it with the SoC bridge and only
// starts the engine while the SoC is held and the bridge idle).
`default_nettype none
module sigil_axi_memeng #(
    parameter int unsigned AXI_ID_W   = 16,
    parameter int unsigned AXI_ADDR_W = 64,
    parameter int unsigned AXI_DATA_W = 512,   // 64 .. 512
    parameter logic [AXI_ID_W-1:0] AXI_ID = '0,
    parameter int unsigned MAX_OT = 8          // bursts in flight (<= 255)
) (
    input  wire                    clk_i,
    input  wire                    rst_ni,
    input  wire                    start_i,
    input  wire [1:0]              mode_i,
    /* verilator lint_off UNUSEDSIGNAL */
    input  wire [63:0]             base_i,     // low bits ignored (burst aligned)
    input  wire [63:0]             size_i,
    /* verilator lint_on UNUSEDSIGNAL */
    input  wire [63:0]             seed_i,
    output logic                   busy_o,
    output logic                   done_o,
    output logic                   fail_o,
    output logic [31:0]            mism_count_o,
    output logic [63:0]            fail_addr_o,
    output logic [31:0]            resp_err_o,
    output logic [63:0]            cycles_o,
    // AXI4 master
    output logic [AXI_ID_W-1:0]    m_axi_awid,
    output logic [AXI_ADDR_W-1:0]  m_axi_awaddr,
    output logic [7:0]             m_axi_awlen,
    output logic [2:0]             m_axi_awsize,
    output logic [1:0]             m_axi_awburst,
    output logic                   m_axi_awvalid,
    input  wire                    m_axi_awready,
    output logic [AXI_DATA_W-1:0]  m_axi_wdata,
    output logic [AXI_DATA_W/8-1:0] m_axi_wstrb,
    output logic                   m_axi_wlast,
    output logic                   m_axi_wvalid,
    input  wire                    m_axi_wready,
    /* verilator lint_off UNUSEDSIGNAL */
    input  wire [AXI_ID_W-1:0]     m_axi_bid,
    /* verilator lint_on UNUSEDSIGNAL */
    input  wire [1:0]              m_axi_bresp,
    input  wire                    m_axi_bvalid,
    output logic                   m_axi_bready,
    output logic [AXI_ID_W-1:0]    m_axi_arid,
    output logic [AXI_ADDR_W-1:0]  m_axi_araddr,
    output logic [7:0]             m_axi_arlen,
    output logic [2:0]             m_axi_arsize,
    output logic [1:0]             m_axi_arburst,
    output logic                   m_axi_arvalid,
    input  wire                    m_axi_arready,
    /* verilator lint_off UNUSEDSIGNAL */
    input  wire [AXI_ID_W-1:0]     m_axi_rid,
    /* verilator lint_on UNUSEDSIGNAL */
    input  wire                    m_axi_rlast,
    input  wire [AXI_DATA_W-1:0]   m_axi_rdata,
    input  wire [1:0]              m_axi_rresp,
    input  wire                    m_axi_rvalid,
    output logic                   m_axi_rready
);
  localparam int unsigned DB = AXI_DATA_W / 8;            // bytes per beat
  localparam int unsigned LB = $clog2(DB);
  localparam int unsigned LANES = AXI_DATA_W / 64;
  localparam int unsigned BEATS = (4096 / DB > 256) ? 256 : 4096 / DB;
  localparam int unsigned BURST_BYTES = BEATS * DB;
  localparam int unsigned BB = $clog2(BURST_BYTES);
  localparam logic [7:0] AXLEN = 8'(BEATS - 1);
  localparam int unsigned OTW = $clog2(MAX_OT + 1);

  logic        busy_q, done_q, check_q, addrpat_q;
  logic [63:0] seed_q;
  logic [63:0] aw_addr_q, aw_left_q;     // next burst address / bytes to issue
  logic [63:0] w_addr_q;                 // address of the next W beat
  logic [8:0]  w_beat_q;                 // beats left in the current W burst
  logic [63:0] bursts_q;                 // bursts still to complete (B / last R)
  logic [OTW-1:0] ot_q;                  // bursts issued, not completed
  logic [OTW-1:0] wq_q;                  // write bursts issued (AW), W not done
  logic [63:0] r_addr_q;                 // address of the next R beat
  logic [31:0] mism_q, rerr_q;
  logic [63:0] fail_addr_q, cyc_q;
  logic        fail_seen_q;
  // R pipeline stage (compare one cycle after the beat).
  logic                  rv_q;
  logic [AXI_DATA_W-1:0] rd_q;
  logic [63:0]           ra_q;

  // Expected / written data of the beat at byte address a.
  /* verilator lint_off UNUSEDSIGNAL */
  function automatic logic [AXI_DATA_W-1:0] pat(input logic [63:0] a,
      input logic [63:0] seed, input logic ap);
    logic [AXI_DATA_W-1:0] d;
    for (int k = 0; k < LANES; k++) begin
      d[64*k +: 64] = ap ? ({a[63:LB], LB'(0)} | 64'(8 * k)) ^ seed : seed;
    end
    return d;
  endfunction
  /* verilator lint_on UNUSEDSIGNAL */

  logic aw_fire, w_fire, b_fire, ar_fire, r_fire;
  logic issue_ok;
  assign aw_fire = m_axi_awvalid && m_axi_awready;
  assign w_fire = m_axi_wvalid && m_axi_wready;
  assign b_fire = m_axi_bvalid && m_axi_bready;
  assign ar_fire = m_axi_arvalid && m_axi_arready;
  assign r_fire = m_axi_rvalid && m_axi_rready;
  assign issue_ok = busy_q && (aw_left_q != 64'd0) && (ot_q != OTW'(MAX_OT));

  always_comb begin
    m_axi_awid = AXI_ID;
    m_axi_awaddr = AXI_ADDR_W'(aw_addr_q);
    m_axi_awlen = AXLEN;
    m_axi_awsize = 3'(LB);
    m_axi_awburst = 2'b01;
    m_axi_awvalid = issue_ok && !check_q;
    m_axi_wdata = pat(w_addr_q, seed_q, addrpat_q);
    m_axi_wstrb = '1;
    m_axi_wlast = (w_beat_q == 9'd1);
    m_axi_wvalid = busy_q && !check_q && (wq_q != '0);
    m_axi_bready = busy_q && !check_q;
    m_axi_arid = AXI_ID;
    m_axi_araddr = AXI_ADDR_W'(aw_addr_q);
    m_axi_arlen = AXLEN;
    m_axi_arsize = 3'(LB);
    m_axi_arburst = 2'b01;
    m_axi_arvalid = issue_ok && check_q;
    m_axi_rready = busy_q && check_q;
    busy_o = busy_q;
    done_o = done_q;
    fail_o = fail_seen_q;
    mism_count_o = mism_q;
    fail_addr_o = fail_addr_q;
    resp_err_o = rerr_q;
    cycles_o = cyc_q;
  end

  // Lane compare of the registered R beat.
  logic [LANES-1:0] lane_bad;
  logic [AXI_DATA_W-1:0] rexp;
  logic [$clog2(LANES+1)-1:0] nbad;
  logic [63:0] first_bad;
  always_comb begin
    rexp = pat(ra_q, seed_q, addrpat_q);
    nbad = '0;
    first_bad = 64'd0;
    for (int k = LANES - 1; k >= 0; k--) begin
      lane_bad[k] = rd_q[64*k +: 64] != rexp[64*k +: 64];
      if (lane_bad[k]) begin
        nbad = nbad + 1'b1;
        first_bad = {ra_q[63:LB], LB'(0)} | 64'(8 * k);
      end
    end
  end

  logic burst_done;
  assign burst_done = check_q ? (r_fire && m_axi_rlast) : b_fire;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      busy_q <= 1'b0;
      done_q <= 1'b0;
      check_q <= 1'b0;
      addrpat_q <= 1'b0;
      seed_q <= 64'd0;
      aw_addr_q <= 64'd0;
      aw_left_q <= 64'd0;
      w_addr_q <= 64'd0;
      w_beat_q <= 9'd0;
      bursts_q <= 64'd0;
      ot_q <= '0;
      wq_q <= '0;
      r_addr_q <= 64'd0;
      mism_q <= 32'd0;
      rerr_q <= 32'd0;
      fail_addr_q <= 64'd0;
      fail_seen_q <= 1'b0;
      cyc_q <= 64'd0;
      rv_q <= 1'b0;
      rd_q <= '0;
      ra_q <= 64'd0;
    end else begin
      rv_q <= 1'b0;
      if (!busy_q) begin
        if (start_i) begin
          busy_q <= 1'b1;
          done_q <= 1'b0;
          check_q <= mode_i[1];
          addrpat_q <= mode_i[0];
          seed_q <= seed_i;
          aw_addr_q <= {base_i[63:BB], BB'(0)};
          aw_left_q <= {size_i[63:BB], BB'(0)};
          w_addr_q <= {base_i[63:BB], BB'(0)};
          r_addr_q <= {base_i[63:BB], BB'(0)};
          w_beat_q <= 9'(BEATS);
          bursts_q <= 64'(size_i[63:BB]);
          ot_q <= '0;
          wq_q <= '0;
          mism_q <= 32'd0;
          rerr_q <= 32'd0;
          fail_addr_q <= 64'd0;
          fail_seen_q <= 1'b0;
          cyc_q <= 64'd0;
        end
      end else begin
        cyc_q <= cyc_q + 64'd1;
        // Address channel (AW or AR): one burst per handshake.
        if (aw_fire || ar_fire) begin
          aw_addr_q <= aw_addr_q + 64'(BURST_BYTES);
          aw_left_q <= aw_left_q - 64'(BURST_BYTES);
        end
        // Bursts in flight.
        if ((aw_fire || ar_fire) && !burst_done) ot_q <= ot_q + 1'b1;
        else if (!(aw_fire || ar_fire) && burst_done) ot_q <= ot_q - 1'b1;
        // W bursts owed (AW accepted, W not yet sent).
        if (aw_fire && !(w_fire && m_axi_wlast)) wq_q <= wq_q + 1'b1;
        else if (!aw_fire && w_fire && m_axi_wlast) wq_q <= wq_q - 1'b1;
        if (w_fire) begin
          w_addr_q <= w_addr_q + 64'(DB);
          w_beat_q <= m_axi_wlast ? 9'(BEATS) : w_beat_q - 9'd1;
        end
        if (b_fire && m_axi_bresp != 2'b00) begin
          rerr_q <= rerr_q + 32'd1;
          fail_seen_q <= 1'b1;
        end
        if (r_fire) begin
          rv_q <= 1'b1;
          rd_q <= m_axi_rdata;
          ra_q <= r_addr_q;
          r_addr_q <= r_addr_q + 64'(DB);
          if (m_axi_rresp != 2'b00) begin
            rerr_q <= rerr_q + 32'd1;
            fail_seen_q <= 1'b1;
          end
        end
        if (burst_done) bursts_q <= bursts_q - 64'd1;
        // Done once every burst has completed (and the last R beat
        // has been compared).
        if (bursts_q == 64'd0 && !rv_q) begin
          busy_q <= 1'b0;
          done_q <= 1'b1;
        end
      end
      // Compare stage (may complete after the last R handshake).
      if (rv_q && (lane_bad != '0)) begin
        if (mism_q == 32'd0) fail_addr_q <= first_bad;
        mism_q <= (mism_q > 32'hFFFF_FFF0) ? 32'hFFFF_FFFF : mism_q + 32'(nbad);
        fail_seen_q <= 1'b1;
      end
    end
  end
endmodule
`default_nettype wire
