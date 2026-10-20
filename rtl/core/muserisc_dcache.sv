// L1 data cache: blocking, physically indexed/tagged,
// set-associative, write-back + write-allocate.
//
// Core side (one request in flight; see docs/CORE.md):
//   req_valid_i/req_ready_o handshake with {addr, op, wdata, be};
//   exactly one rsp_valid_o pulse per accepted request, at the
//   earliest the cycle after acceptance. LOAD returns the
//   aligned 64-bit word containing addr; STORE writes the lanes
//   in be; CLEAN writes back every dirty line (FENCE.I) and
//   responds when memory is up to date. The page-table walker
//   and the core's AMO/LR/SC read and write phases are plain
//   LOAD/STORE requests, so they are coherent by construction.
//
// Bus side (master): see muserisc_cpu.sv for the protocol. A
// line refill is one read burst of LINE_BYTES/8 beats; a dirty
// victim is a write burst of LINE_BYTES/8 beats; uncacheable
// (I/O) accesses are single beats carrying the exact byte
// address and byte enables, issued in program order.
//
// Arrays (tags, data) are single-port synchronous SRAMs
// (muserisc_sram_sp); valid/dirty bits and the replacement
// pointer are flops. Victim: first invalid way, else a
// round-robin pointer advanced on every miss.
`default_nettype none
module muserisc_dcache import muserisc_cache_pkg::*; #(
    parameter int unsigned SETS = 64,
    parameter int unsigned WAYS = 4,
    parameter int unsigned LINE_BYTES = 64,
    parameter logic [63:0] C0_BASE = 64'h0000_0000_8000_0000,
    parameter logic [63:0] C0_SIZE = 64'h0000_0000_8000_0000,
    parameter logic [63:0] C1_BASE = 64'h0,
    parameter logic [63:0] C1_SIZE = 64'h0
) (
    input  wire        clk_i,
    input  wire        rst_ni,
    input  wire        cache_en_i,     // strap: 0 = every access uncached
    // Core side
    input  wire        req_valid_i,
    output logic       req_ready_o,
    input  wire [63:0] req_addr_i,
    input  wire [1:0]  req_op_i,
    input  wire [63:0] req_wdata_i,
    input  wire [7:0]  req_be_i,
    output logic       rsp_valid_o,
    output logic [63:0] rsp_rdata_o,
    // Bus master
    output logic       bus_req_valid_o,
    input  wire        bus_req_ready_i,
    output logic [63:0] bus_req_addr_o,
    output logic       bus_req_write_o,
    output logic [7:0] bus_req_len_o,
    output logic [63:0] bus_req_wdata_o,
    output logic [7:0] bus_req_be_o,
    output logic       bus_req_last_o,
    input  wire        bus_rsp_valid_i,
    input  wire [63:0] bus_rsp_rdata_i,
    input  wire        bus_rsp_last_i
);
  localparam int unsigned BEATS = LINE_BYTES / 8;
  localparam int unsigned OFF_W = $clog2(LINE_BYTES);
  localparam int unsigned IDX_W = $clog2(SETS);
  localparam int unsigned BW = $clog2(BEATS);
  localparam int unsigned TAG_W = 56 - OFF_W - IDX_W;
  localparam int unsigned WAY_W = (WAYS > 1) ? $clog2(WAYS) : 1;
  localparam int unsigned DA_W = IDX_W + BW;
  localparam logic [7:0] LEN = 8'(BEATS - 1);

  // Geometry limits (elaboration-time).
  if (SETS < 2 || (1 << IDX_W) != SETS) begin : g_bad_sets
    $error("dcache: SETS must be a power of two >= 2");
  end
  if (BEATS < 2 || BEATS > 256 || (1 << BW) != BEATS) begin : g_bad_line
    $error("dcache: LINE_BYTES must be a power of two in [16, 2048]");
  end
  if (WAYS < 1 || WAYS > 16) begin : g_bad_ways
    $error("dcache: WAYS must be in [1, 16]");
  end

  typedef enum logic [3:0] {
    S_IDLE, S_LOOKUP, S_WB_RD, S_WB_BUS, S_WB_ACK, S_FILL_REQ, S_FILL,
    S_REPLAY, S_UNC_REQ, S_UNC_RSP, S_UNC_DONE, S_CLEAN, S_CLEAN_TAG
  } state_e;
  state_e state_q;

  logic [63:0] r_addr_q, r_wdata_q;
  logic [1:0]  r_op_q;
  logic [7:0]  r_be_q;
  logic [SETS-1:0] valid_q [WAYS];
  logic [SETS-1:0] dirty_q [WAYS];
  logic [WAY_W-1:0] victim_q, rr_q;
  logic [TAG_W-1:0] vtag_q;
  logic [BW:0]      cnt_q;
  logic [IDX_W-1:0] sc_set_q;
  logic [WAY_W-1:0] sc_way_q;
  logic [63:0]      linebuf_q [BEATS];
  logic [63:0]      unc_rdata_q;   // registered uncached read data

  // Address fields (PA bits above 55 never reach a cacheable
  // window: the core faults PAs >= 2^56 before the port).
  /* verilator lint_off UNUSEDSIGNAL */
  function automatic logic [IDX_W-1:0] f_idx(input logic [63:0] a);
    return a[OFF_W +: IDX_W];
  endfunction
  function automatic logic [TAG_W-1:0] f_tag(input logic [63:0] a);
    return a[OFF_W + IDX_W +: TAG_W];
  endfunction
  function automatic logic [BW-1:0] f_beat(input logic [63:0] a);
    return a[3 +: BW];
  endfunction
  /* verilator lint_on UNUSEDSIGNAL */

  logic [IDX_W-1:0] r_idx, line_idx;
  assign r_idx = f_idx(r_addr_q);
  assign line_idx = (r_op_q == DOP_CLEAN) ? sc_set_q : r_idx;

  // ---- Arrays ----
  logic [WAYS-1:0]      tag_en, tag_we, data_en;
  logic [7:0]           data_we [WAYS];
  logic [IDX_W-1:0]     tag_addr;
  logic [TAG_W-1:0]     tag_wdata;
  logic [DA_W-1:0]      data_addr;
  logic [63:0]          data_wdata;
  logic [TAG_W-1:0]     tag_rdata [WAYS];
  logic [63:0]          data_rdata [WAYS];
  for (genvar w = 0; w < int'(WAYS); w++) begin : g_way
    muserisc_sram_sp #(.WIDTH(TAG_W), .DEPTH(SETS), .LANES(1)) u_tag (
        .clk_i   (clk_i),
        .en_i    (tag_en[w]),
        .we_i    (tag_we[w]),
        .addr_i  (tag_addr),
        .wdata_i (tag_wdata),
        .rdata_o (tag_rdata[w])
    );
    muserisc_sram_sp #(.WIDTH(64), .DEPTH(SETS * BEATS), .LANES(8)) u_data (
        .clk_i   (clk_i),
        .en_i    (data_en[w]),
        .we_i    (data_we[w]),
        .addr_i  (data_addr),
        .wdata_i (data_wdata),
        .rdata_o (data_rdata[w])
    );
  end

  // ---- Lookup ----
  logic [WAYS-1:0]  hit_vec;
  logic             hit;
  logic [WAY_W-1:0] hit_way, victim;
  logic             any_invalid;
  always_comb begin
    hit_way = '0;
    victim = rr_q;
    any_invalid = 1'b0;
    for (int w = 0; w < int'(WAYS); w++) begin
      hit_vec[w] = valid_q[w][r_idx] && (tag_rdata[w] == f_tag(r_addr_q));
    end
    for (int w = int'(WAYS) - 1; w >= 0; w--) begin
      if (hit_vec[w]) hit_way = WAY_W'(w);
      if (!valid_q[w][r_idx]) begin
        victim = WAY_W'(w);
        any_invalid = 1'b1;
      end
    end
  end
  assign hit = |hit_vec;

  logic sc_last, sc_dirty, req_cacheable;
  assign sc_last = (sc_set_q == IDX_W'(SETS - 1)) &&
                   (sc_way_q == WAY_W'(WAYS - 1));
  assign sc_dirty = valid_q[sc_way_q][sc_set_q] && dirty_q[sc_way_q][sc_set_q];
  assign req_cacheable = pma_cacheable(req_addr_i, cache_en_i,
                                       C0_BASE, C0_SIZE, C1_BASE, C1_SIZE);

  // ---- Datapath / outputs ----
  // Response (kept out of the request-side block below: it never
  // depends on the incoming request).
  // The uncached response is registered (S_UNC_DONE): no bus
  // input reaches the core combinationally.
  assign rsp_valid_o = ((state_q == S_LOOKUP) && hit) ||
                       (state_q == S_UNC_DONE) ||
                       ((state_q == S_CLEAN) && !sc_dirty && sc_last);
  assign rsp_rdata_o = (state_q == S_UNC_DONE) ? unc_rdata_q
                                              : data_rdata[hit_way];
  always_comb begin
    req_ready_o = 1'b0;
    tag_en = '0;
    tag_we = '0;
    data_en = '0;
    for (int w = 0; w < int'(WAYS); w++) data_we[w] = 8'h00;
    tag_addr = r_idx;
    tag_wdata = f_tag(r_addr_q);
    data_addr = {r_idx, f_beat(r_addr_q)};
    data_wdata = r_wdata_q;
    bus_req_valid_o = 1'b0;
    bus_req_addr_o = r_addr_q;
    bus_req_write_o = 1'b0;
    bus_req_len_o = 8'd0;
    bus_req_wdata_o = r_wdata_q;
    bus_req_be_o = r_be_q;
    bus_req_last_o = 1'b1;
    unique case (state_q)
      S_IDLE: begin
        req_ready_o = 1'b1;
        tag_addr = f_idx(req_addr_i);
        data_addr = {f_idx(req_addr_i), f_beat(req_addr_i)};
        if (req_valid_i && req_cacheable && (req_op_i != DOP_CLEAN)) begin
          tag_en = '1;
          data_en = '1;
        end
      end
      S_LOOKUP: begin
        if (hit && (r_op_q == DOP_STORE)) begin
          data_en[hit_way] = 1'b1;
          data_we[hit_way] = r_be_q;
        end
      end
      S_WB_RD: begin
        data_addr = {line_idx, cnt_q[BW-1:0]};
        if (cnt_q != (BW + 1)'(BEATS)) data_en[victim_q] = 1'b1;
      end
      S_WB_BUS: begin
        bus_req_valid_o = 1'b1;
        bus_req_addr_o = {8'd0, vtag_q, line_idx, cnt_q[BW-1:0], 3'b000};
        bus_req_write_o = 1'b1;
        bus_req_len_o = LEN;
        bus_req_wdata_o = linebuf_q[cnt_q[BW-1:0]];
        bus_req_be_o = 8'hFF;
        bus_req_last_o = (cnt_q == (BW + 1)'(BEATS - 1));
      end
      S_FILL_REQ: begin
        bus_req_valid_o = 1'b1;
        bus_req_addr_o = {r_addr_q[63:OFF_W], OFF_W'(0)};
        bus_req_len_o = LEN;
        bus_req_be_o = 8'hFF;
      end
      S_FILL: begin
        data_addr = {r_idx, cnt_q[BW-1:0]};
        data_wdata = bus_rsp_rdata_i;
        if (bus_rsp_valid_i) begin
          data_en[victim_q] = 1'b1;
          data_we[victim_q] = 8'hFF;
          if (cnt_q == (BW + 1)'(BEATS - 1)) begin
            tag_en[victim_q] = 1'b1;
            tag_we[victim_q] = 1'b1;
          end
        end
      end
      S_REPLAY: begin
        tag_en = '1;
        data_en = '1;
      end
      S_UNC_REQ: begin
        bus_req_valid_o = 1'b1;
        bus_req_write_o = (r_op_q == DOP_STORE);
      end
      S_CLEAN: begin
        tag_addr = sc_set_q;
        if (sc_dirty) tag_en[sc_way_q] = 1'b1;
      end
      default: ;  // S_WB_ACK, S_UNC_RSP, S_UNC_DONE, S_CLEAN_TAG
    endcase
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q <= S_IDLE;
      r_addr_q <= 64'd0;
      r_wdata_q <= 64'd0;
      r_op_q <= DOP_LOAD;
      r_be_q <= 8'd0;
      for (int w = 0; w < int'(WAYS); w++) begin
        valid_q[w] <= '0;
        dirty_q[w] <= '0;
      end
      victim_q <= '0;
      rr_q <= '0;
      vtag_q <= '0;
      cnt_q <= '0;
      sc_set_q <= '0;
      sc_way_q <= '0;
      unc_rdata_q <= 64'd0;
    end else begin
      unique case (state_q)
        S_IDLE: begin
          if (req_valid_i) begin
            r_addr_q <= req_addr_i;
            r_op_q <= req_op_i;
            r_wdata_q <= req_wdata_i;
            r_be_q <= req_be_i;
            sc_set_q <= '0;
            sc_way_q <= '0;
            if (req_op_i == DOP_CLEAN) state_q <= S_CLEAN;
            else if (req_cacheable) state_q <= S_LOOKUP;
            else state_q <= S_UNC_REQ;
          end
        end
        S_LOOKUP: begin
          if (hit) begin
            if (r_op_q == DOP_STORE) dirty_q[hit_way][r_idx] <= 1'b1;
            state_q <= S_IDLE;
          end else begin
            victim_q <= victim;
            vtag_q <= tag_rdata[victim];
            if (!any_invalid) rr_q <= (rr_q == WAY_W'(WAYS - 1)) ? '0 : rr_q + 1'b1;
            cnt_q <= '0;
            state_q <= (valid_q[victim][r_idx] && dirty_q[victim][r_idx])
                       ? S_WB_RD : S_FILL_REQ;
          end
        end
        S_WB_RD: begin
          if (cnt_q != '0) linebuf_q[cnt_q[BW-1:0] - 1'b1] <= data_rdata[victim_q];
          if (cnt_q == (BW + 1)'(BEATS)) begin
            cnt_q <= '0;
            state_q <= S_WB_BUS;
          end else begin
            cnt_q <= cnt_q + 1'b1;
          end
        end
        S_WB_BUS: begin
          if (bus_req_ready_i) begin
            if (cnt_q == (BW + 1)'(BEATS - 1)) begin
              cnt_q <= '0;
              state_q <= S_WB_ACK;
            end else begin
              cnt_q <= cnt_q + 1'b1;
            end
          end
        end
        S_WB_ACK: begin
          if (bus_rsp_valid_i) begin
            dirty_q[victim_q][line_idx] <= 1'b0;
            state_q <= (r_op_q == DOP_CLEAN) ? S_CLEAN : S_FILL_REQ;
          end
        end
        S_FILL_REQ: begin
          // The victim line is being replaced: invalid until the
          // last beat lands (its data no longer matches its tag).
          valid_q[victim_q][r_idx] <= 1'b0;
          if (bus_req_ready_i) state_q <= S_FILL;
        end
        S_FILL: begin
          if (bus_rsp_valid_i) begin
            if (cnt_q == (BW + 1)'(BEATS - 1)) begin
              valid_q[victim_q][r_idx] <= 1'b1;
              dirty_q[victim_q][r_idx] <= 1'b0;
              cnt_q <= '0;
              state_q <= S_REPLAY;
            end else begin
              cnt_q <= cnt_q + 1'b1;
            end
          end
        end
        S_REPLAY: state_q <= S_LOOKUP;
        S_UNC_REQ: if (bus_req_ready_i) state_q <= S_UNC_RSP;
        S_UNC_RSP: begin
          if (bus_rsp_valid_i) begin
            unc_rdata_q <= bus_rsp_rdata_i;
            state_q <= S_UNC_DONE;
          end
        end
        S_UNC_DONE: state_q <= S_IDLE;
        S_CLEAN: begin
          if (sc_dirty) begin
            victim_q <= sc_way_q;
            state_q <= S_CLEAN_TAG;
          end else if (sc_last) begin
            state_q <= S_IDLE;
          end else if (sc_way_q == WAY_W'(WAYS - 1)) begin
            sc_way_q <= '0;
            sc_set_q <= sc_set_q + 1'b1;
          end else begin
            sc_way_q <= sc_way_q + 1'b1;
          end
        end
        S_CLEAN_TAG: begin
          vtag_q <= tag_rdata[victim_q];
          cnt_q <= '0;
          state_q <= S_WB_RD;
        end
        // Unreachable encodings recover to idle (excluded from
        // line coverage: no legal state reaches it).
        /* verilator coverage_off */
        default: state_q <= S_IDLE;
        /* verilator coverage_on */
      endcase
    end
  end

  // Protocol checks (simulation): a fill/ack beat's last flag
  // must match the burst length this cache asked for.
`ifndef SYNTHESIS
  // Low until reset: pre-reset state is arbitrary under
  // +verilator+rand+reset+2. A plain always, not always_ff, so the
  // initial block may also write it (IEEE 1800 9.2.2.4: an
  // always_ff variable has no other writer; a declaration
  // initialiser trips Verilator's PROCASSINIT instead).
  logic chk_live_q;
  initial chk_live_q = 1'b0;
  always @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) chk_live_q <= 1'b0;
    else chk_live_q <= 1'b1;
  end
  a_fill_last: assert property (@(posedge clk_i) disable iff (!chk_live_q)
      (bus_rsp_valid_i && (state_q == S_FILL)) |->
      (bus_rsp_last_i == (cnt_q == (BW + 1)'(BEATS - 1))))
    else $error("dcache: fill burst last-beat mismatch");
  a_single_rsp: assert property (@(posedge clk_i) disable iff (!chk_live_q)
      (bus_rsp_valid_i && (state_q != S_FILL)) |->
      (bus_rsp_last_i && ((state_q == S_WB_ACK) || (state_q == S_UNC_RSP))))
    else $error("dcache: unexpected bus response");
`endif
endmodule
`default_nettype wire
