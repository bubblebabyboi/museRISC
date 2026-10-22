// Simulation-only walker / data-port invariant and corner coverage
// for the issue #73 fetch-walk preemption fix (skeptic review,
// patch-correctness lens). Bound into sigil_cpu next to
// sigil_oops_chk (sim/Makefile.oops). Not part of any RTL build.
//
// Invariant (PTWINV): a walker request that is still live on the
// core data port (dq_pend && dq_walk && !dq_drop) belongs to the
// walk that owns the walker right now: the walker is not idle and
// its current PTE address and kind (read / A-D write) are the ones
// that were requested. Any MMU transition that abandons a request
// without arming dq_drop breaks it at once, whether or not a later
// walk happens to consume the response (sigil_oops_chk only sees
// the consumption).
//
// Coverage (PTWCOV, printed at the end): the cycles where the MMU
// preempts a fetch walk (W_VS_READ / W_G_READ, fetch walk, data
// miss), split by what the data port is doing in that cycle, which
// are exactly the cases the drop condition must get right:
//   inflight     fetch request in flight, no response this cycle
//   inflight_drp request in flight that is already dropped
//   rsp_same     the fetch request's response arrives this cycle
//   issue_acc    walk_issue accepted this cycle (same-cycle issue)
//   issue_nacc   walk_issue offered but not accepted (ready low)
//   trap         trap_take in the same cycle
//   idle         nothing on the port for the walker
// plus W_G_READ exits on a GPA width fault (gw) and how many of
// them issued a request in the same cycle (gw_issue).
// The preempt condition is recomputed from MMU internals, so the
// module is the same on patched and unpatched RTL.
`default_nettype none
/* verilator lint_off UNUSEDSIGNAL */
module sigil_ptw_inv (
    input wire        clk_i,
    input wire        rst_ni,
    input wire        dreq_valid,
    input wire        dreq_ready,
    input wire [63:0] dreq_addr,
    input wire [1:0]  dreq_op,
    input wire        drsp_valid,
    input wire        mem_issue,
    input wire        walk_issue,
    input wire        walk_rsp,
    input wire [63:0] walk_addr,
    input wire        walk_we,
    input wire [2:0]  mmu_state,
    input wire        mmu_is_data,
    input wire        miss_d,
    input wire        g_width_fault,
    input wire        dq_pend,
    input wire        dq_walk,
    input wire        dq_drop,
    input wire        trap_take,
    input wire        sfence_fire
);
  localparam logic [2:0] W_IDLE = 3'd0, W_VS_READ = 3'd1, W_G_READ = 3'd3;

  longint      cyc_q;
  logic [63:0] rq_addr_q;
  logic        rq_we_q;
  longint      n_viol, n_pre, n_inflight, n_inflight_drp, n_rsp_same,
               n_issue_acc, n_issue_nacc, n_trap, n_idle, n_gw, n_gw_issue;
  int          max_rep;
  initial begin
    n_viol = 0; n_pre = 0; n_inflight = 0; n_inflight_drp = 0; n_rsp_same = 0;
    n_issue_acc = 0; n_issue_nacc = 0; n_trap = 0; n_idle = 0; n_gw = 0;
    n_gw_issue = 0;
    if (!$value$plusargs("ptwinvmax=%d", max_rep)) max_rep = 20;
  end

  logic pre, live;
  assign pre = ((mmu_state == W_VS_READ) || (mmu_state == W_G_READ)) &&
               !mmu_is_data && miss_d && !sfence_fire;
  assign live = dq_pend && dq_walk && !dq_drop;

  always @(posedge clk_i) begin
    if (!rst_ni) begin
      cyc_q <= 0;
    end else begin
      cyc_q <= cyc_q + 1;
      if (dreq_valid && dreq_ready && !mem_issue) begin
        rq_addr_q <= dreq_addr;
        rq_we_q <= (dreq_op == 2'd1);
      end
      if (live && ((mmu_state == W_IDLE) || (walk_addr != rq_addr_q) ||
                   (walk_we != rq_we_q))) begin
        n_viol <= n_viol + 1;
        if (n_viol < longint'(max_rep)) begin
          $display("PTWINV live-walk-req-abandoned cyc=%0d req=%h we=%0d walker_state=%0d walker_pte=%h walker_we=%0d data=%0d rsp=%0d",
                   cyc_q, rq_addr_q, rq_we_q, mmu_state, walk_addr, walk_we,
                   mmu_is_data, drsp_valid);
        end
      end
      if (pre) begin
        n_pre <= n_pre + 1;
        if (dq_pend && dq_walk && !dq_drop && !drsp_valid) n_inflight <= n_inflight + 1;
        if (dq_pend && dq_walk && dq_drop && !drsp_valid) n_inflight_drp <= n_inflight_drp + 1;
        if (dq_pend && dq_walk && !dq_drop && drsp_valid) n_rsp_same <= n_rsp_same + 1;
        if (walk_issue && dreq_ready) n_issue_acc <= n_issue_acc + 1;
        if (walk_issue && !dreq_ready) n_issue_nacc <= n_issue_nacc + 1;
        if (trap_take) n_trap <= n_trap + 1;
        if (!dq_pend && !walk_issue) n_idle <= n_idle + 1;
      end
      if ((mmu_state == W_G_READ) && g_width_fault && !pre && !trap_take) begin
        n_gw <= n_gw + 1;
        if (walk_issue && dreq_ready) n_gw_issue <= n_gw_issue + 1;
      end
    end
  end

  final begin
    $display("PTWCOV pre=%0d inflight=%0d inflight_drp=%0d rsp_same=%0d issue_acc=%0d issue_nacc=%0d trap=%0d idle=%0d gw=%0d gw_issue=%0d",
             n_pre, n_inflight, n_inflight_drp, n_rsp_same, n_issue_acc,
             n_issue_nacc, n_trap, n_idle, n_gw, n_gw_issue);
    $display("PTWINV violations=%0d", n_viol);
  end
endmodule
/* verilator lint_on UNUSEDSIGNAL */

bind sigil_cpu sigil_ptw_inv u_ptw_inv (
    .clk_i         (clk_i),
    .rst_ni        (rst_ni),
    .dreq_valid    (dreq_valid),
    .dreq_ready    (dreq_ready),
    .dreq_addr     (dreq_addr),
    .dreq_op       (dreq_op),
    .drsp_valid    (drsp_valid),
    .mem_issue     (u_core.mem_issue),
    .walk_issue    (u_core.walk_issue),
    .walk_rsp      (u_core.walk_rsp),
    .walk_addr     (u_core.walk_addr),
    .walk_we       (u_core.walk_we),
    .mmu_state     (u_core.u_mmu.state_q),
    .mmu_is_data   (u_core.u_mmu.req_is_data_q),
    .miss_d        (u_core.u_mmu.miss_d),
    .g_width_fault (u_core.u_mmu.g_width_fault),
    .dq_pend       (u_core.dq_pend_q),
    .dq_walk       (u_core.dq_walk_q),
    .dq_drop       (u_core.dq_drop_q),
    .trap_take     (u_core.trap_take),
    .sfence_fire   (u_core.sfence_fire)
);
`default_nettype wire
