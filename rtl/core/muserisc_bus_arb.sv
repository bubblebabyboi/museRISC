// Two-master arbiter for the museRISC memory bus (protocol in
// muserisc_cpu.sv). Master 1 (D$) has priority over master 0
// (I$) when both request in the same idle cycle. The bus is
// locked to the granted master from its first request beat
// until the response beat flagged last, so transactions are
// never interleaved (one transaction in flight on the bus).
// A request beat offered to the slave but not yet accepted
// (valid && !ready) keeps its master selected (hold_q), so the
// offered payload stays stable until the handshake (AXI rule)
// even if the other master raises its valid meanwhile.
// req_wdata_o is zero on I$ beats, so it too is stable on
// every offered beat (checked by a_req_stable).
`default_nettype none
module muserisc_bus_arb (
    input  wire        clk_i,
    input  wire        rst_ni,
    // Master 0: instruction cache (reads only)
    input  wire        m0_req_valid_i,
    output logic       m0_req_ready_o,
    input  wire [63:0] m0_req_addr_i,
    input  wire [7:0]  m0_req_len_i,
    input  wire [7:0]  m0_req_be_i,
    output logic       m0_rsp_valid_o,
    // Master 1: data cache
    input  wire        m1_req_valid_i,
    output logic       m1_req_ready_o,
    input  wire [63:0] m1_req_addr_i,
    input  wire        m1_req_write_i,
    input  wire [7:0]  m1_req_len_i,
    input  wire [63:0] m1_req_wdata_i,
    input  wire [7:0]  m1_req_be_i,
    input  wire        m1_req_last_i,
    output logic       m1_rsp_valid_o,
    // Slave port (response data/last are broadcast to masters)
    output logic       req_valid_o,
    input  wire        req_ready_i,
    output logic [63:0] req_addr_o,
    output logic       req_write_o,
    output logic [7:0] req_len_o,
    output logic [63:0] req_wdata_o,
    output logic [7:0] req_be_o,
    output logic       req_last_o,
    output logic       req_inst_o,
    input  wire        rsp_valid_i,
    input  wire        rsp_last_i
);
  logic busy_q, owner_q, sel, hold_q, hold_sel_q;
  assign sel = busy_q ? owner_q : hold_q ? hold_sel_q : m1_req_valid_i;

  always_comb begin
    req_valid_o = sel ? m1_req_valid_i : m0_req_valid_i;
    req_addr_o  = sel ? m1_req_addr_i : m0_req_addr_i;
    req_write_o = sel && m1_req_write_i;
    req_len_o   = sel ? m1_req_len_i : m0_req_len_i;
    // Zero on I$ beats so wdata is stable on every offered beat.
    req_wdata_o = sel ? m1_req_wdata_i : 64'h0;
    req_be_o    = sel ? m1_req_be_i : m0_req_be_i;
    req_last_o  = sel ? m1_req_last_i : 1'b1;
    req_inst_o  = !sel;
    m0_req_ready_o = !sel && req_ready_i;
    m1_req_ready_o = sel && req_ready_i;
    m0_rsp_valid_o = busy_q && !owner_q && rsp_valid_i;
    m1_rsp_valid_o = busy_q && owner_q && rsp_valid_i;
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      hold_q <= 1'b0;
      hold_sel_q <= 1'b0;
    end else begin
      // An offered, unaccepted first beat pins the selection.
      hold_q <= !busy_q && req_valid_o && !req_ready_i;
      hold_sel_q <= sel;
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      busy_q <= 1'b0;
      owner_q <= 1'b0;
    end else if (busy_q && rsp_valid_i && rsp_last_i) begin
      busy_q <= 1'b0;
    end else if (!busy_q && req_valid_o && req_ready_i) begin
      busy_q <= 1'b1;
      owner_q <= sel;
    end
  end

  // Simulation checks (enabled one cycle after reset release).
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
  a_rsp: assert property (@(posedge clk_i) disable iff (!chk_live_q)
      rsp_valid_i |-> busy_q)
    else $error("bus_arb: response with no transaction");
  // Request-channel stability: an offered beat that is not
  // accepted is offered again, unchanged, in the next cycle.
  a_req_stable: assert property (@(posedge clk_i) disable iff (!chk_live_q)
      (req_valid_o && !req_ready_i) |=>
      (req_valid_o && $stable(req_addr_o) && $stable(req_write_o) &&
       $stable(req_len_o) && $stable(req_wdata_o) &&
       $stable(req_be_o) && $stable(req_last_o) && $stable(req_inst_o)))
    else $error("bus_arb: request changed while valid && !ready");
`endif
endmodule
`default_nettype wire
