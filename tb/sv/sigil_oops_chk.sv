// Simulation-only memory-consistency checker for the issue #73
// oops hunt, bound into sigil_cpu (see sim/Makefile.oops). Not
// part of any RTL build.
//
// 1. Stale walker response: the address/kind of the page-table
//    walker request in flight on the core data port is recorded at
//    the handshake; when a response is handed to the walker
//    (walk_rsp) the walker's current PTE address must still be the
//    one that was requested. A mismatch means the walker consumed a
//    response that belongs to another (preempted) walk.
// 2. D-port shadow memory (tb/cpp/oops_chk_dpi.cpp): every
//    cacheable LOAD response must equal the architectural value
//    built from every earlier D-port store (stores, AMO/SC write
//    phases, walker A/D updates). A word is learned from its first
//    load if no store has been seen.
// 3. I-port vs FENCE.I: a cacheable fetch response that differs
//    from the shadow is flagged when the last store to that word
//    precedes the last FENCE.I completed before the fetch was
//    issued (the I$ must not return pre-FENCE.I data).
`default_nettype none
/* verilator lint_off UNUSEDSIGNAL */
module sigil_oops_chk (
    input wire        clk_i,
    input wire        rst_ni,
    // core data port
    input wire        dreq_valid,
    input wire        dreq_ready,
    input wire [63:0] dreq_addr,
    input wire [1:0]  dreq_op,
    input wire [63:0] dreq_wdata,
    input wire [7:0]  dreq_be,
    input wire        drsp_valid,
    input wire [63:0] drsp_rdata,
    input wire        d_cacheable,
    // core fetch port
    input wire        ireq_valid,
    input wire        ireq_ready,
    input wire [63:0] ireq_addr,
    input wire        irsp_valid,
    input wire [31:0] irsp_rdata,
    input wire        i_cacheable,
    input wire        ic_inval,
    // walker
    input wire        mem_issue,
    input wire        walk_rsp,
    input wire [63:0] walk_addr,
    input wire        walk_we,
    input wire        mmu_is_data,
    input wire [63:0] mmu_va,
    input wire [1:0]  mmu_level,
    input wire [1:0]  priv,
    input wire [63:0] fetch_va,
    input wire [63:0] mem_va,
    // trace only (+oopstrace)
    input wire [2:0]  mmu_state,
    input wire        miss_d,
    input wire        miss_f,
    input wire        walk_req,
    input wire        data_access,
    input wire        d_ok,
    input wire        if_ok,
    input wire        dq_pend,
    input wire        dq_walk,
    input wire        dq_drop
);
  import "DPI-C" function void oops_d_load(input longint cyc, input longint pa,
                                           input longint data, input int walk);
  import "DPI-C" function void oops_d_store(input longint cyc, input longint pa,
                                            input longint data, input int be,
                                            input int walk);
  import "DPI-C" function void oops_fencei(input longint cyc);
  import "DPI-C" function void oops_i_fetch(input longint cyc, input longint pa,
                                            input int data, input longint epoch);
  import "DPI-C" function longint oops_epoch();
  import "DPI-C" function void oops_stale_walk(input longint cyc, input longint req_pa,
                                               input int req_we, input longint walker_pa,
                                               input int walker_we, input longint data,
                                               input int is_data, input longint va,
                                               input int level, input int priv,
                                               input longint fva, input longint dva);
  import "DPI-C" function void oops_summary();

  longint     cyc_q;
  logic [63:0] d_addr_q, d_wdata_q;
  logic [1:0]  d_op_q;
  logic [7:0]  d_be_q;
  logic        d_cach_q, d_walk_q;
  logic [63:0] i_addr_q;
  logic        i_cach_q;
  longint      i_epoch_q;

  bit trace_on;
  int unsigned traceu_left;  // +oopstraceu=N: first N user-mode (priv 0) trace lines
  initial begin
    trace_on = $test$plusargs("oopstrace");
    if (!$value$plusargs("oopstraceu=%d", traceu_left)) traceu_left = 0;
  end
  always @(posedge clk_i) begin
    if (rst_ni && traceu_left != 0 && priv == 2'd0 &&
        (walk_req || dreq_valid || drsp_valid || miss_d || miss_f || dq_pend)) begin
      traceu_left <= traceu_left - 1;
    end
    if (rst_ni && (trace_on || (traceu_left != 0 && priv == 2'd0)) &&
        (walk_req || dreq_valid || drsp_valid || miss_d || miss_f || dq_pend)) begin
      $display("OT %0d mmu st=%0d data=%0d va=%h pte=%h lvl=%0d | missd=%0d missf=%0d wreq=%0d | dreq=%0d%0d a=%h op=%0d | rsp=%0d %h | pend=%0d walk=%0d drop=%0d wrsp=%0d | dacc=%0d dok=%0d mem_va=%h | ifok=%0d fva=%h",
               cyc_q, mmu_state, mmu_is_data, mmu_va, walk_addr, mmu_level, miss_d, miss_f,
               walk_req, dreq_valid, dreq_ready, dreq_addr, dreq_op, drsp_valid, drsp_rdata,
               dq_pend, dq_walk, dq_drop, walk_rsp, data_access, d_ok, mem_va, if_ok, fetch_va);
    end
    if (!rst_ni) begin
      cyc_q <= 0;
    end else begin
      cyc_q <= cyc_q + 1;
      if (dreq_valid && dreq_ready) begin
        d_addr_q <= dreq_addr;
        d_wdata_q <= dreq_wdata;
        d_op_q <= dreq_op;
        d_be_q <= dreq_be;
        d_cach_q <= d_cacheable;
        d_walk_q <= !mem_issue;
      end
      if (drsp_valid && d_cach_q) begin
        if (d_op_q == 2'd0) oops_d_load(cyc_q, d_addr_q, drsp_rdata, int'(d_walk_q));
        else if (d_op_q == 2'd1) oops_d_store(cyc_q, d_addr_q, d_wdata_q, int'(d_be_q),
                                              int'(d_walk_q));
      end
      if (walk_rsp && ((d_addr_q != walk_addr) || ((d_op_q == 2'd1) != walk_we))) begin
        oops_stale_walk(cyc_q, d_addr_q, int'(d_op_q == 2'd1), walk_addr, int'(walk_we),
                        drsp_rdata, int'(mmu_is_data), mmu_va, int'(mmu_level),
                        int'(priv), fetch_va, mem_va);
      end
      if (ic_inval) oops_fencei(cyc_q);
      if (ireq_valid && ireq_ready) begin
        i_addr_q <= ireq_addr;
        i_cach_q <= i_cacheable;
        // An inval in the issue cycle takes effect before the lookup.
        i_epoch_q <= oops_epoch() + (ic_inval ? 64'd1 : 64'd0);
      end
      if (irsp_valid && i_cach_q) oops_i_fetch(cyc_q, i_addr_q, int'(irsp_rdata), i_epoch_q);
    end
  end
  final oops_summary();
endmodule
/* verilator lint_on UNUSEDSIGNAL */

bind sigil_cpu sigil_oops_chk u_oops_chk (
    .clk_i       (clk_i),
    .rst_ni      (rst_ni),
    .dreq_valid  (dreq_valid),
    .dreq_ready  (dreq_ready),
    .dreq_addr   (dreq_addr),
    .dreq_op     (dreq_op),
    .dreq_wdata  (dreq_wdata),
    .dreq_be     (dreq_be),
    .drsp_valid  (drsp_valid),
    .drsp_rdata  (drsp_rdata),
    .d_cacheable (u_dcache.req_cacheable),
    .ireq_valid  (ireq_valid),
    .ireq_ready  (ireq_ready),
    .ireq_addr   (ireq_addr),
    .irsp_valid  (irsp_valid),
    .irsp_rdata  (irsp_rdata),
    .i_cacheable (u_icache.req_cacheable),
    .ic_inval    (ic_inval),
    .mem_issue   (u_core.mem_issue),
    .walk_rsp    (u_core.walk_rsp),
    .walk_addr   (u_core.walk_addr),
    .walk_we     (u_core.walk_we),
    .mmu_is_data (u_core.u_mmu.req_is_data_q),
    .mmu_va      (u_core.u_mmu.req_va_q),
    .mmu_level   (u_core.u_mmu.level_q),
    .priv        (u_core.priv),
    .fetch_va    (u_core.fetch_va),
    .mem_va      (u_core.mem_va),
    .mmu_state   (u_core.u_mmu.state_q),
    .miss_d      (u_core.u_mmu.miss_d),
    .miss_f      (u_core.u_mmu.miss_f),
    .walk_req    (u_core.walk_req),
    .data_access (u_core.data_access),
    .d_ok        (u_core.mmu_d_ok),
    .if_ok       (u_core.mmu_if_ok),
    .dq_pend     (u_core.dq_pend_q),
    .dq_walk     (u_core.dq_walk_q),
    .dq_drop     (u_core.dq_drop_q)
);
`default_nettype wire
