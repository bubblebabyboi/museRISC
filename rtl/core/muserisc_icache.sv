// L1 instruction cache: blocking, read-only, physically
// indexed/tagged, set-associative.
//
// Core side: req_valid_i/req_ready_o handshake with the PA of an
// aligned 32-bit fetch word; exactly one rsp_valid_o pulse per
// accepted request (earliest the cycle after acceptance) with
// that word. inval_i (FENCE.I, after the D$ has been cleaned)
// clears every valid bit in one cycle; a refill in flight when
// it arrives completes and answers its request but does not
// leave the line valid, so no pre-clean data survives.
//
// Bus side: line refill = one read burst of LINE_BYTES/8 beats;
// uncacheable fetches are single beats.
`default_nettype none
module muserisc_icache import muserisc_cache_pkg::*; #(
    parameter int unsigned SETS = 64,
    parameter int unsigned WAYS = 2,
    parameter int unsigned LINE_BYTES = 64,
    parameter logic [63:0] C0_BASE = 64'h0000_0000_8000_0000,
    parameter logic [63:0] C0_SIZE = 64'h0000_0000_8000_0000,
    parameter logic [63:0] C1_BASE = 64'h0,
    parameter logic [63:0] C1_SIZE = 64'h0
) (
    input  wire        clk_i,
    input  wire        rst_ni,
    input  wire        cache_en_i,
    input  wire        inval_i,
    // Core side
    input  wire        req_valid_i,
    output logic       req_ready_o,
    input  wire [63:0] req_addr_i,
    output logic       rsp_valid_o,
    output logic [31:0] rsp_rdata_o,
    // Bus master (read-only)
    output logic       bus_req_valid_o,
    input  wire        bus_req_ready_i,
    output logic [63:0] bus_req_addr_o,
    output logic [7:0] bus_req_len_o,
    output logic [7:0] bus_req_be_o,
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

  if (SETS < 2 || (1 << IDX_W) != SETS) begin : g_bad_sets
    $error("icache: SETS must be a power of two >= 2");
  end
  if (BEATS < 2 || BEATS > 256 || (1 << BW) != BEATS) begin : g_bad_line
    $error("icache: LINE_BYTES must be a power of two in [16, 2048]");
  end
  if (WAYS < 1 || WAYS > 16) begin : g_bad_ways
    $error("icache: WAYS must be in [1, 16]");
  end

  typedef enum logic [2:0] {
    S_IDLE, S_LOOKUP, S_FILL_REQ, S_FILL, S_REPLAY, S_UNC_REQ, S_UNC_RSP,
    S_UNC_DONE
  } state_e;
  state_e state_q;

  logic [63:0] r_addr_q;
  logic [SETS-1:0] valid_q [WAYS];
  logic [WAY_W-1:0] victim_q, rr_q;
  logic [BW-1:0]    cnt_q;
  logic             fill_kill_q;  // inval_i seen during this refill
  logic [63:0]      unc_rdata_q;  // registered uncached fetch data

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

  logic [IDX_W-1:0] r_idx;
  assign r_idx = f_idx(r_addr_q);

  logic [WAYS-1:0]  tag_en, tag_we, data_en;
  logic [7:0]       data_we [WAYS];
  logic [IDX_W-1:0] tag_addr;
  logic [DA_W-1:0]  data_addr;
  logic [TAG_W-1:0] tag_rdata [WAYS];
  logic [63:0]      data_rdata [WAYS];
  for (genvar w = 0; w < int'(WAYS); w++) begin : g_way
    muserisc_sram_sp #(.WIDTH(TAG_W), .DEPTH(SETS), .LANES(1)) u_tag (
        .clk_i   (clk_i),
        .en_i    (tag_en[w]),
        .we_i    (tag_we[w]),
        .addr_i  (tag_addr),
        .wdata_i (f_tag(r_addr_q)),
        .rdata_o (tag_rdata[w])
    );
    muserisc_sram_sp #(.WIDTH(64), .DEPTH(SETS * BEATS), .LANES(8)) u_data (
        .clk_i   (clk_i),
        .en_i    (data_en[w]),
        .we_i    (data_we[w]),
        .addr_i  (data_addr),
        .wdata_i (bus_rsp_rdata_i),
        .rdata_o (data_rdata[w])
    );
  end

  logic [WAYS-1:0]  hit_vec;
  logic             hit, any_invalid;
  logic [WAY_W-1:0] hit_way, victim;
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

  logic req_cacheable;
  assign req_cacheable = pma_cacheable(req_addr_i, cache_en_i,
                                       C0_BASE, C0_SIZE, C1_BASE, C1_SIZE);
  logic [63:0] hit_word;
  assign hit_word = data_rdata[hit_way];

  logic [63:0] rsp_word;
  assign rsp_valid_o = ((state_q == S_LOOKUP) && hit) ||
                       (state_q == S_UNC_DONE);
  // Registered uncached response: no bus input reaches the core
  // combinationally.
  assign rsp_word = (state_q == S_UNC_DONE) ? unc_rdata_q : hit_word;
  assign rsp_rdata_o = r_addr_q[2] ? rsp_word[63:32] : rsp_word[31:0];

  always_comb begin
    req_ready_o = 1'b0;
    tag_en = '0;
    tag_we = '0;
    data_en = '0;
    for (int w = 0; w < int'(WAYS); w++) data_we[w] = 8'h00;
    tag_addr = r_idx;
    data_addr = {r_idx, f_beat(r_addr_q)};
    bus_req_valid_o = 1'b0;
    bus_req_addr_o = r_addr_q;
    bus_req_len_o = 8'd0;
    bus_req_be_o = r_addr_q[2] ? 8'hF0 : 8'h0F;
    unique case (state_q)
      S_IDLE: begin
        req_ready_o = 1'b1;
        tag_addr = f_idx(req_addr_i);
        data_addr = {f_idx(req_addr_i), f_beat(req_addr_i)};
        if (req_valid_i && req_cacheable) begin
          tag_en = '1;
          data_en = '1;
        end
      end
      S_FILL_REQ: begin
        bus_req_valid_o = 1'b1;
        bus_req_addr_o = {r_addr_q[63:OFF_W], OFF_W'(0)};
        bus_req_len_o = LEN;
        bus_req_be_o = 8'hFF;
      end
      S_FILL: begin
        data_addr = {r_idx, cnt_q};
        if (bus_rsp_valid_i) begin
          data_en[victim_q] = 1'b1;
          data_we[victim_q] = 8'hFF;
          if (cnt_q == BW'(BEATS - 1)) begin
            tag_en[victim_q] = 1'b1;
            tag_we[victim_q] = 1'b1;
          end
        end
      end
      S_REPLAY: begin
        tag_en = '1;
        data_en = '1;
      end
      S_UNC_REQ: bus_req_valid_o = 1'b1;
      default: ;  // S_LOOKUP, S_UNC_RSP, S_UNC_DONE
    endcase
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q <= S_IDLE;
      r_addr_q <= 64'd0;
      for (int w = 0; w < int'(WAYS); w++) valid_q[w] <= '0;
      victim_q <= '0;
      rr_q <= '0;
      cnt_q <= '0;
      fill_kill_q <= 1'b0;
      unc_rdata_q <= 64'd0;
    end else begin
      unique case (state_q)
        S_IDLE: begin
          if (req_valid_i) begin
            r_addr_q <= req_addr_i;
            state_q <= req_cacheable ? S_LOOKUP : S_UNC_REQ;
          end
        end
        S_LOOKUP: begin
          if (hit) begin
            state_q <= S_IDLE;
          end else begin
            victim_q <= victim;
            if (!any_invalid) rr_q <= (rr_q == WAY_W'(WAYS - 1)) ? '0 : rr_q + 1'b1;
            cnt_q <= '0;
            fill_kill_q <= 1'b0;
            state_q <= S_FILL_REQ;
          end
        end
        S_FILL_REQ: begin
          valid_q[victim_q][r_idx] <= 1'b0;
          if (bus_req_ready_i) state_q <= S_FILL;
        end
        S_FILL: begin
          if (bus_rsp_valid_i) begin
            cnt_q <= cnt_q + 1'b1;
            if (cnt_q == BW'(BEATS - 1)) begin
              valid_q[victim_q][r_idx] <= !fill_kill_q && !inval_i;
              state_q <= S_REPLAY;
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
        // Unreachable encodings recover to idle (excluded from
        // line coverage: no legal state reaches it).
        /* verilator coverage_off */
        default: state_q <= S_IDLE;
        /* verilator coverage_on */
      endcase
      // FENCE.I invalidation (overrides the fill update above).
      if (inval_i) begin
        for (int w = 0; w < int'(WAYS); w++) valid_q[w] <= '0;
        if ((state_q == S_FILL_REQ) || (state_q == S_FILL)) fill_kill_q <= 1'b1;
      end
    end
  end

`ifndef SYNTHESIS
  logic chk_live_q;
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) chk_live_q <= 1'b0;
    else chk_live_q <= 1'b1;
  end
  a_fill_last: assert property (@(posedge clk_i) disable iff (!chk_live_q)
      (bus_rsp_valid_i && (state_q == S_FILL)) |->
      (bus_rsp_last_i == (cnt_q == BW'(BEATS - 1))))
    else $error("icache: fill burst last-beat mismatch");
  a_single_rsp: assert property (@(posedge clk_i) disable iff (!chk_live_q)
      (bus_rsp_valid_i && (state_q != S_FILL)) |->
      (bus_rsp_last_i && (state_q == S_UNC_RSP)))
    else $error("icache: unexpected bus response");
`endif
endmodule
`default_nettype wire
