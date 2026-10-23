// Sv39 + Svnapot MMU for the in-house core (issue #18 stage 3b).
//
// One unified 32-entry fully-associative TLB with two
// combinational lookup ports (fetch and data) and a single
// page-table walker that borrows the core's data-memory port.
// Data misses preempt fetch walks (the MEM instruction is older
// and stalls the whole pipeline); fetch walks yield the port
// to MEM accesses cycle by cycle via walk_grant_i. A walk that
// ends without consuming its PTE read (walk_abandon_o) leaves
// that read's response to the core to drop.
//
// Policies:
// - With V=0, translation is on iff satp.MODE == Sv39 and the
//   effective privilege is S or U; otherwise VA passes as PA.
// - With V=1, VS-stage (vsatp in satp_i) yields a GPA and
//   G-stage Sv39x4 (hgatp_i) yields the supervisor PA. Either
//   stage can be Bare. VS page-table accesses are implicit
//   loads/stores through G-stage. G-stage permission checks
//   are made as U-mode; HS MXR (hs_mxr_i), not VS MXR, makes
//   G-stage execute-only pages readable.
// - Two-stage TLB fills are exact 4 KiB combined VA->SPA
//   entries (separate VS and G permission bits). This is
//   architecturally transparent; superpages simply refill
//   once per 4 KiB page while both stages are enabled.
// - Hardware A/D update (Svadu semantics): the walker writes
//   the leaf PTE back with A (and D for stores) set. A TLB hit
//   with A=0 — impossible after a fill — or a store hit with
//   D=0 re-enters the walker to perform the update. The read
//   and the write-back are atomic: from the leaf read to its
//   write-back the walker keeps the data port (walk_lock_o), so
//   no store can reach that PTE in between and be overwritten.
// - SFENCE.VMA flushes the whole TLB (operands ignored; a full
//   flush is always a legal implementation of any SFENCE).
// - Faults are reported as page faults or access faults
//   (PTE-access PMP denial); the core picks the cause code
//   from the access type. The physical-address PMP check on
//   the translated address itself stays in the core.
`default_nettype none
module sigil_mmu #(
    // FPGA timing structures (#53, sigil_cache_pkg::FPGA_TIMING):
    // one-hot port lookups; registered data translation (the dl_*
    // lookup port below); fetch page register (g_ireg).
    parameter bit FPGA_TIMING = 1'b0
) (
    input  wire        clk_i,
    input  wire        rst_ni,
    input  wire [63:0] satp_i,         // fetch satp/vsatp for current V
    input  wire [63:0] d_satp_i,       // data satp/vsatp (HLV may differ)
    input  wire [63:0] hgatp_i,
    input  wire        sum_i,          // effective VS/HS SUM for data
    input  wire        mxr_i,          // effective VS/HS MXR for stage 1
    input  wire        hs_mxr_i,       // HS MXR for G-stage loads
    input  wire        flush_i,        // SFENCE commits: clear TLB + walk
    input  wire        abort_i,        // trap taken: kill walk + fault state
    // Fetch lookup (priv = current privilege, access = execute)
    input  wire [63:0] if_va_i,
    input  wire [1:0]  if_priv_i,
    input  wire        if_virt_i,
    output logic [63:0] if_pa_o,
    output logic       if_ok_o,        // PA usable this cycle
    output logic       if_fault_o,     // definitive fault this cycle
    output logic       if_fault_page_o, // 1 page/guest, 0 access
    output logic       if_fault_guest_o,
    output logic [63:0] if_fault_gpa_o,
    // Data lookup
    input  wire [63:0] d_va_i,
    input  wire        d_write_i,
    input  wire        d_exec_i,       // HLVX: translate as execute
    input  wire [1:0]  d_priv_i,
    input  wire        d_virt_i,
    input  wire        d_valid_i,
    output logic [63:0] d_pa_o,
    output logic       d_ok_o,
    output logic       d_fault_o,
    output logic       d_fault_page_o,
    output logic       d_fault_guest_o,
    output logic [63:0] d_fault_gpa_o,
    // Registered data translation (FPGA_TIMING only, #53). The d_*
    // inputs above stay MEM's access (walk requests, A/D class) and
    // d_valid_i its data_access, but the d_* outputs become a
    // register: the lookup of the dl_* port (EX's access, or MEM's
    // own while it waits for a translation or sequences a vector
    // load/store) captured when dl_ld_i, usable when dl_vld_i was
    // set with it and no TLB or walk-fault update has landed since.
    // dl_mem_i: the access is MEM's own (not EX's).
    // A data walk then starts from that register (miss) instead of
    // the combinational lookup, and a walk end costs a replay cycle.
    /* verilator lint_off UNUSEDSIGNAL */
    input  wire [63:0] dl_va_i,
    input  wire        dl_write_i,
    input  wire        dl_exec_i,
    input  wire [1:0]  dl_priv_i,
    input  wire        dl_virt_i,
    input  wire [63:0] dl_satp_i,
    input  wire        dl_sum_i,
    input  wire        dl_mxr_i,
    input  wire        dl_mem_i,
    input  wire        dl_ld_i,
    input  wire        dl_vld_i,
    /* verilator lint_on UNUSEDSIGNAL */
    // Walker memory port (muxed onto the core data port)
    output logic       walk_req_o,     // wants the port this cycle
    output logic       walk_abandon_o, // walk ends without its PTE read
    output logic       walk_lock_o,    // A/D read-modify-write: keep the port
    output logic [63:0] walk_addr_o,
    output logic       walk_we_o,      // A/D writeback (8-byte store)
    output logic [63:0] walk_wdata_o,
    output logic [1:0]  walk_acc_o,    // PMP access class: 0 read, 1 write
    input  wire        walk_grant_i,   // port granted: consume rdata
    input  wire [63:0] walk_rdata_i,
    input  wire        walk_pmp_allow_i
);
  // ------------------------------------------------------------
  // TLB (32 entries, fully associative, round-robin fill)
  // ------------------------------------------------------------
  typedef struct packed {
    logic        valid;
    logic        guest;   // entry belongs to V=1 translation
    logic        vs_bare; // guest entry with no VS-stage checks
    logic [15:0] asid;    // satp/vsatp ASID
    logic [15:0] vmid;    // hgatp VMID (guest entries)
    logic [26:0] vpn;     // VA[38:12]
    logic [1:0]  vpn_ext; // GPA[40:39] for vs_bare entries
    logic [43:0] ppn;     // supervisor PA[55:12]
    logic [1:0]  level;   // leaf level: 0 = 4K, 1 = 2M, 2 = 1G
    logic        napot;   // 64K contiguous (level 0 only)
    logic        r, w, x, u, g, a, d;  // VS/stage-1 permissions
    logic        gr, gw, gx;           // G-stage permissions
  } tlb_entry_t;

  tlb_entry_t tlb_q [0:31];
  logic [4:0]  fill_ptr_q;

  logic        satp_sv39, d_satp_sv39, hgatp_sv39x4;
  logic [15:0] satp_asid, d_satp_asid, hgatp_vmid;
  assign satp_sv39 = (satp_i[63:60] == 4'd8);
  assign satp_asid = satp_i[59:44];
  assign d_satp_sv39 = (d_satp_i[63:60] == 4'd8);
  assign d_satp_asid = d_satp_i[59:44];
  assign hgatp_sv39x4 = (hgatp_i[63:60] == 4'd8);
  assign hgatp_vmid = hgatp_i[59:44];

  /* verilator lint_off UNUSEDSIGNAL */  // low VA bits pass through PA muxes
  // (Expression form, no early returns: Verilator attributes no
  // coverage to return statements in inlined functions.)
  function automatic logic entry_match(
      input tlb_entry_t e, input logic [63:0] va, input logic [15:0] asid,
      input logic guest, input logic [15:0] vmid, input logic g_on,
      input logic vs_on);
    logic [26:0] vpn;
    logic asid_ok, vmid_ok;
    vpn = va[38:12];
    asid_ok = !vs_on || e.vs_bare || e.g || (e.asid == asid);
    vmid_ok = !guest || !g_on || (e.vmid == vmid);
    entry_match = e.valid && (e.guest == guest) &&
        (e.vs_bare == (guest && !vs_on)) && asid_ok && vmid_ok &&
        (!e.vs_bare || (va[40:39] == e.vpn_ext)) &&
        ((e.level == 2'd2) ? (vpn[26:18] == e.vpn[26:18]) :
         (e.level == 2'd1) ? (vpn[26:9] == e.vpn[26:9]) :
         e.napot           ? (vpn[26:4] == e.vpn[26:4]) :
                             (vpn == e.vpn));
  endfunction

  function automatic logic [63:0] entry_pa(
      input tlb_entry_t e, input logic [63:0] va);
    entry_pa = (e.level == 2'd2) ? {8'd0, e.ppn[43:18], va[29:0]} :
               (e.level == 2'd1) ? {8'd0, e.ppn[43:9], va[20:0]} :
               e.napot           ? {8'd0, e.ppn[43:4], va[15:0]} :
                                   {8'd0, e.ppn, va[11:0]};
  endfunction

  // Permission of an access against one leaf/TLB entry.
  // acc: 0 read, 1 write, 2 execute.
  function automatic logic perm_ok(
      input tlb_entry_t e, input logic [1:0] priv,
      input logic [1:0] acc, input logic sum, input logic mxr);
    logic u_ok, rwx_ok;
    if (e.vs_bare) return 1'b1;
    if (priv == 2'b00)      u_ok = e.u;                 // U needs U=1
    else if (acc == 2'd2)   u_ok = !e.u;                // S fetch: U=0
    else                    u_ok = !e.u || sum;         // S data
    if (acc == 2'd2)        rwx_ok = e.x;
    else if (acc == 2'd1)   rwx_ok = e.w;
    else                    rwx_ok = e.r || (mxr && e.x);
    return u_ok && rwx_ok;
  endfunction

  // G-stage permission from the cached G bits. The G leaf's
  // U=1 requirement was checked when the entry was filled;
  // HS MXR makes an execute-only G page load-readable.
  function automatic logic g_perm_ok(
      input tlb_entry_t e, input logic [1:0] acc, input logic hs_mxr);
    if (!e.guest) return 1'b1;
    if (acc == 2'd2)      return e.gx;
    else if (acc == 2'd1) return e.gw;
    else                  return e.gr || (hs_mxr && e.gx);
  endfunction
  /* verilator lint_on UNUSEDSIGNAL */

  /* verilator lint_off UNUSEDSIGNAL */  // only the VPN slices are inputs
  function automatic logic canonical(input logic [63:0] va);
    return (va[63:39] == {25{va[38]}});
  endfunction

  // Find a matching entry; returns its index (valid bit = bit 5).
  function automatic logic [5:0] find_entry(
      input logic [63:0] va, input logic [15:0] asid,
      input logic guest, input logic [15:0] vmid, input logic g_on,
      input logic vs_on);
    find_entry = 6'd0;
    for (int i = 0; i < 32; i++) begin
      if (entry_match(tlb_q[i], va, asid, guest, vmid, g_on, vs_on)) begin
        find_entry = {1'b1, 5'(i)};
      end
    end
  endfunction

  // A port lookup: hit, the selected entry, and that entry's
  // verdicts for the access (perm_ok; g_perm_ok with A, and D for a
  // store). Index form, main's find_entry: the reference the
  // FPGA_TIMING one-hot form is checked against in simulation.
  typedef struct packed {
    logic       hit;
    logic       perm;
    logic       gok;
    tlb_entry_t e;
  } lookup_t;

  function automatic lookup_t lookup_idx(
      input logic [63:0] va, input logic [15:0] asid,
      input logic guest, input logic [15:0] vmid, input logic g_on,
      input logic vs_on, input logic [1:0] priv, input logic [1:0] acc,
      input logic write, input logic sum, input logic mxr);
    logic [5:0] f;
    lookup_t    r;
    f = find_entry(va, asid, guest, vmid, g_on, vs_on);
    r.hit = f[5];
    r.e = tlb_q[f[4:0]];
    r.perm = perm_ok(r.e, priv, acc, sum, mxr);
    r.gok = g_perm_ok(r.e, acc, hs_mxr_i) && r.e.a && (!write || r.e.d);
    return r;
  endfunction

  // One-hot form of lookup_idx (FPGA_TIMING, #53), same result on a
  // hit: the match bits, the highest matching index kept by a mask
  // (no match above it: find_entry's rule), and an AND-OR select of
  // the entry and of per-entry verdicts computed beside the match,
  // instead of a priority encoder feeding a 32:1 entry mux and the
  // verdicts. Written as vector reductions: an accumulating loop
  // synthesizes back into a chain.
  function automatic lookup_t lookup_1h(
      input logic [63:0] va, input logic [15:0] asid,
      input logic guest, input logic [15:0] vmid, input logic g_on,
      input logic vs_on, input logic [1:0] priv, input logic [1:0] acc,
      input logic write, input logic sum, input logic mxr);
    logic [31:0] m, sel, perm_v, gok_v, col;
    logic [$bits(tlb_entry_t)-1:0] e;
    lookup_t     r;
    for (int i = 0; i < 32; i++) begin
      m[i] = entry_match(tlb_q[i], va, asid, guest, vmid, g_on, vs_on);
      perm_v[i] = perm_ok(tlb_q[i], priv, acc, sum, mxr);
      gok_v[i] = g_perm_ok(tlb_q[i], acc, hs_mxr_i) && tlb_q[i].a &&
                 (!write || tlb_q[i].d);
    end
    for (int i = 0; i < 32; i++) sel[i] = m[i] && ((m >> (i + 1)) == 32'd0);
    for (int b = 0; b < $bits(tlb_entry_t); b++) begin
      for (int i = 0; i < 32; i++) col[i] = tlb_q[i][b];
      e[b] = |(sel & col);
    end
    r.hit = |m;
    r.perm = |(sel & perm_v);
    r.gok = |(sel & gok_v);
    r.e = e;
    return r;
  endfunction

  /* verilator lint_on UNUSEDSIGNAL */

  // ------------------------------------------------------------
  // Lookups
  // ------------------------------------------------------------
  // Recorded walk fault (held until the core consumes it; killed
  // by abort/flush, and only ever matched against the faulting VA).
  logic        wf_valid_q, wf_is_data_q, wf_page_q, wf_guest_q;
  logic [63:0] wf_va_q, wf_gpa_q;

  logic        if_vs_trans, d_vs_trans, if_g_trans, d_g_trans;
  logic        if_trans, d_trans;
  assign if_vs_trans = satp_sv39 && (if_priv_i != 2'b11);
  assign d_vs_trans  = d_satp_sv39 && (d_priv_i != 2'b11);
  assign if_g_trans = if_virt_i && hgatp_sv39x4;
  assign d_g_trans  = d_virt_i && hgatp_sv39x4;
  assign if_trans = if_vs_trans || if_g_trans;
  assign d_trans  = d_vs_trans || d_g_trans;

  // A port's verdict for one access (FPGA_TIMING; fault gated by
  // valid): main's fetch and data port logic as a function of a
  // lookup, the port (data) choosing which recorded walk fault
  // applies.
  typedef struct packed {
    logic [63:0] pa;
    logic        ok, fault, page, guest;
    logic [63:0] gpa;
  } dres_t;

  /* verilator lint_off UNUSEDSIGNAL */  // only the PA fields of .e are read
  function automatic dres_t port_result(
      input logic [63:0] va, input logic valid, input logic data,
      input logic trans, input logic vs_trans, input logic g_trans,
      input lookup_t lk);
    dres_t r;
    r.pa = va;
    r.ok = 1'b0;
    r.fault = 1'b0;
    r.page = 1'b1;
    r.guest = 1'b0;
    r.gpa = 64'd0;
    if (!trans) begin
      r.ok = 1'b1;
    end else if (vs_trans && !canonical(va)) begin
      r.fault = valid;
    end else if (!vs_trans && g_trans && |va[63:41]) begin
      r.fault = valid;
      r.guest = 1'b1;
      r.gpa = va;
    end else if (wf_valid_q && (wf_is_data_q == data) && (wf_va_q == va)) begin
      // A recorded walk fault supersedes a stale TLB hit that
      // triggered the re-walk (e.g. a G-stage permission denial).
      r.fault = valid;
      r.page = wf_page_q;
      r.guest = wf_guest_q;
      r.gpa = wf_gpa_q;
    end else if (lk.hit) begin
      r.pa = entry_pa(lk.e, va);
      if (!lk.perm) begin
        r.fault = valid;
      end else if (lk.gok) begin
        r.ok = 1'b1;  // G denial or A=0 falls through to a re-walk
      end
    end
    return r;
  endfunction
  /* verilator lint_on UNUSEDSIGNAL */

  logic miss_f, miss_d;
  logic [1:0]  d_acc;
  logic [63:0] d_root_pte;
  assign d_acc = d_exec_i ? 2'd2 : d_write_i ? 2'd1 : 2'd0;
  assign d_root_pte = {8'd0, d_satp_i[43:0], 12'd0} +
                      {52'd0, d_va_i[38:30], 3'd0};

  // ------------------------------------------------------------
  // Page-table walker
  // ------------------------------------------------------------
  typedef enum logic [2:0] {
    W_IDLE, W_VS_READ, W_VS_UPD, W_G_READ, W_G_UPD
  } walk_state_e;
  walk_state_e state_q;
  logic        req_is_data_q, req_virt_q, req_vs_q, req_g_q;
  logic [63:0] req_va_q;
  logic [1:0]  req_acc_q, req_priv_q, level_q;
  logic [15:0] req_asid_q, req_vmid_q;
  logic [63:0] pte_addr_q, pte_q;
  logic [63:0] vs_pte_gpa_q, final_gpa_q;
  logic        vs_r_q, vs_w_q, vs_x_q, vs_u_q, vs_g_q, vs_d_q;
  // G-stage subwalker. Purpose: 0 final access, 1 VS PTE read,
  // 2 VS PTE A/D write. g_acc is the implicit access class for
  // purposes 1/2 and the original class for purpose 0.
  logic [1:0]  g_level_q, g_acc_q, g_purpose_q;
  logic [63:0] g_gpa_q, g_pte_q, g_spa_q;
  logic        g_r_q, g_w_q, g_x_q, g_d_q;

  assign walk_req_o = (state_q != W_IDLE);
  assign walk_addr_o = pte_addr_q;
  assign walk_we_o = (state_q == W_VS_UPD) || (state_q == W_G_UPD);
  assign walk_acc_o = walk_we_o ? 2'd1 : 2'd0;

  // Combinational leaf evaluation of the PTE on the port.
  // (PTE RSW bits [9:8] are software's; the walker ignores them.)
  /* verilator lint_off UNUSEDSIGNAL */
  logic        pte_leaf, pte_fault, pte_needs_upd;
  tlb_entry_t  fill_entry;
  always_comb begin
    logic [63:0] pte;
    pte = walk_rdata_i;
    pte_leaf = pte[1] || pte[3];                       // R or X
    pte_fault = 1'b0;
    if (!pte[0] || (!pte[1] && pte[2])) pte_fault = 1'b1;   // !V, W w/o R
    if (pte[62:54] != 9'd0) pte_fault = 1'b1;               // PBMT/reserved
    if (!pte_leaf && (pte[7] || pte[6] || pte[4])) begin
      pte_fault = 1'b1;                                     // non-leaf D/A/U
    end
    if (!pte_leaf && (level_q == 2'd0)) pte_fault = 1'b1;
    if (pte[63] && !(pte_leaf && (level_q == 2'd0) &&
                     (pte[13:10] == 4'b1000))) begin
      pte_fault = 1'b1;                                     // bad NAPOT use of N
    end
    if (pte_leaf && (level_q == 2'd2) && (pte[27:10] != 18'd0)) begin
      pte_fault = 1'b1;                                     // misaligned 1G
    end
    if (pte_leaf && (level_q == 2'd1) && (pte[18:10] != 9'd0)) begin
      pte_fault = 1'b1;                                     // misaligned 2M
    end
    // Candidate TLB entry (also used for the permission check).
    fill_entry = '0;
    fill_entry.valid = 1'b1;
    fill_entry.guest = req_virt_q;
    fill_entry.asid = req_asid_q;
    fill_entry.vmid = req_vmid_q;
    fill_entry.vpn = req_va_q[38:12];
    fill_entry.ppn = pte[53:10];
    fill_entry.level = level_q;
    fill_entry.napot = pte[63];
    fill_entry.r = pte[1];
    fill_entry.w = pte[2];
    fill_entry.x = pte[3];
    fill_entry.u = pte[4];
    fill_entry.g = pte[5];
    fill_entry.a = 1'b1;  // walker guarantees A/D before filling
    fill_entry.d = pte[7] || (req_acc_q == 2'd1);
    fill_entry.gr = 1'b1;  // replaced by real G bits on G fills
    fill_entry.gw = 1'b1;
    fill_entry.gx = 1'b1;
    if (pte_leaf && !pte_fault &&
        !perm_ok(fill_entry, req_priv_q, req_acc_q, sum_i, mxr_i)) begin
      pte_fault = 1'b1;
    end
    pte_needs_upd = !pte[6] || ((req_acc_q == 2'd1) && !pte[7]);
  end
  assign walk_wdata_o = (state_q == W_G_UPD)
      ? (g_pte_q | (64'd1 << 6) |
         ((g_acc_q == 2'd1) ? (64'd1 << 7) : 64'd0))
      : (pte_q | (64'd1 << 6) |
         ((req_acc_q == 2'd1) ? (64'd1 << 7) : 64'd0));

  // G-stage leaf evaluation of the PTE on the port: Sv39 rules
  // with privilege forced to U (so U=1 is required) and HS MXR
  // for loads. The G bit is ignored, as required.
  logic        g_pte_leaf, g_pte_fault, g_needs_upd, g_width_fault;
  logic [63:0] g_leaf_spa;
  always_comb begin
    logic [63:0] pte;
    pte = walk_rdata_i;
    g_width_fault = |g_gpa_q[63:41];
    g_pte_leaf = pte[1] || pte[3];
    g_pte_fault = 1'b0;
    if (!pte[0] || (!pte[1] && pte[2])) g_pte_fault = 1'b1;
    if (pte[62:54] != 9'd0) g_pte_fault = 1'b1;
    if (!g_pte_leaf && (pte[7] || pte[6] || pte[4])) g_pte_fault = 1'b1;
    if (!g_pte_leaf && (g_level_q == 2'd0)) g_pte_fault = 1'b1;
    if (pte[63] && !(g_pte_leaf && (g_level_q == 2'd0) &&
                     (pte[13:10] == 4'b1000))) g_pte_fault = 1'b1;
    if (g_pte_leaf && (g_level_q == 2'd2) &&
        (pte[27:10] != 18'd0)) g_pte_fault = 1'b1;
    if (g_pte_leaf && (g_level_q == 2'd1) &&
        (pte[18:10] != 9'd0)) g_pte_fault = 1'b1;
    if (g_pte_leaf && !g_pte_fault) begin
      if (!pte[4]) begin
        g_pte_fault = 1'b1;  // G-stage checks as U-mode
      end else if (g_acc_q == 2'd2) begin
        if (!pte[3]) g_pte_fault = 1'b1;
      end else if (g_acc_q == 2'd1) begin
        if (!pte[2]) g_pte_fault = 1'b1;
      end else if (!pte[1] && !(hs_mxr_i && pte[3])) begin
        g_pte_fault = 1'b1;
      end
    end
    g_needs_upd = !pte[6] || ((g_acc_q == 2'd1) && !pte[7]);
    if (g_level_q == 2'd2) begin
      g_leaf_spa = {8'd0, pte[53:28], g_gpa_q[29:0]};
    end else if (g_level_q == 2'd1) begin
      g_leaf_spa = {8'd0, pte[53:19], g_gpa_q[20:0]};
    end else if (pte[63]) begin
      g_leaf_spa = {8'd0, pte[53:14], g_gpa_q[15:0]};
    end else begin
      g_leaf_spa = {8'd0, pte[53:10], g_gpa_q[11:0]};
    end
  end

  // Walk abandonment. An older data miss preempts a fetch walk in
  // W_VS_READ/W_G_READ, and a G-stage step on a GPA wider than 41
  // bits ends the walk at once; neither consumes its PTE read.
  // That read may already be on the port (preemption), or be
  // issued in this very cycle (a data miss in MEM leaves the port
  // to the walker), and its response would otherwise be taken as
  // the next walk's PTE (issue #73: the preempting data walk took
  // the fetch walk's root entry). walk_abandon_o makes the core
  // drop that response.
  logic walk_preempt;
  assign walk_preempt = ((state_q == W_VS_READ) || (state_q == W_G_READ)) &&
                        !req_is_data_q && miss_d;
  assign walk_abandon_o = walk_preempt ||
                          ((state_q == W_G_READ) && g_width_fault);

  // A/D update atomicity. A leaf PTE that needs A/D was read in
  // the walker's last port access; MEM going before the write-back
  // could store to that PTE (an older store, under a fetch walk)
  // and then be overwritten by the stale pte_q|A. walk_lock_o
  // gives the walker the port from that read to the write-back:
  // in W_VS_UPD / W_G_UPD, and for a VS leaf under two-stage
  // translation also across the G-stage walk of the PTE's own GPA
  // (g_purpose_q == 2) that comes before W_VS_UPD. The port is
  // free when the lock starts (the leaf read just completed), so
  // nothing gets in between.
  assign walk_lock_o = (state_q == W_VS_UPD) || (state_q == W_G_UPD) ||
                       ((state_q == W_G_READ) && (g_purpose_q == 2'd2));

`ifndef SYNTHESIS
  // Simulation checks are armed by the first reset edge (pre-reset
  // state is arbitrary under +verilator+rand+reset+2).
  logic chk_live_q;
  initial chk_live_q = 1'b0;
  always @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) chk_live_q <= 1'b0;
    else chk_live_q <= 1'b1;
  end
`endif

  // Fetch port. Main: the if_* outputs are the combinational lookup
  // of the fetch VA. FPGA_TIMING (#53) step 7: IF translates from
  // it_q, the last OK translated fetch page and the context it was
  // looked up in (privilege, V, satp/vsatp mode and ASID, hgatp mode
  // and VMID: the TLB's own match key), so fetch_stall, the I$
  // request and fetch PMP start from a page compare. A fetch outside
  // it waits a cycle while the full lookup is registered in ir_q
  // (tagged with its VA and context): an OK result loads it_q, a
  // fault is delivered from ir_q, and a miss starts the walk from
  // ir_q. ir_q is not used in the cycle after a walk end, flush or
  // abort (ichg_q), so a just-filled entry never starts a second
  // walk; it_q is dropped by SFENCE and traps. A TLB fill keeps it_q:
  // a cached OK translation stays usable until SFENCE.
  if (FPGA_TIMING) begin : g_ireg
    logic         ichg_d, ichg_q, it_valid_q, it_hit, ir_live;
    logic [42:0]  ctx, it_ctx_q, ir_ctx_q;
    logic [63:12] it_va_q, it_pa_q;
    logic [63:0]  ir_va_q;
    dres_t        if_res, ir_q;
    /* verilator lint_off UNUSEDSIGNAL */  // only the PA fields of .e are read
    lookup_t      if_lk;
    /* verilator lint_on UNUSEDSIGNAL */
    assign if_lk = lookup_1h(if_va_i, satp_asid, if_virt_i, hgatp_vmid,
                             if_g_trans, if_vs_trans, if_priv_i, 2'd2, 1'b0,
                             sum_i, mxr_i);
    assign ctx = {if_priv_i, if_virt_i, satp_i[63:60], satp_asid,
                  hgatp_i[63:60], hgatp_vmid};
    assign if_res = port_result(if_va_i, 1'b1, 1'b0, if_trans, if_vs_trans,
                                if_g_trans, if_lk);
    assign ichg_d = flush_i || abort_i ||
                    ((state_q != W_IDLE) && walk_grant_i) ||
                    ((state_q == W_G_READ) && g_width_fault);
    always_ff @(posedge clk_i or negedge rst_ni) begin
      if (!rst_ni) begin
        ichg_q <= 1'b0;
        it_valid_q <= 1'b0;
        it_va_q <= '0;
        it_pa_q <= '0;
        it_ctx_q <= '0;
        ir_q <= '0;
        ir_va_q <= 64'd0;
        ir_ctx_q <= '0;
      end else begin
        ichg_q <= ichg_d;
        ir_q <= if_res;
        ir_va_q <= if_va_i;
        ir_ctx_q <= ctx;
        if (flush_i || abort_i) begin
          it_valid_q <= 1'b0;
        end else if (if_trans && if_res.ok) begin
          it_valid_q <= 1'b1;
          it_va_q <= if_va_i[63:12];
          it_pa_q <= if_res.pa[63:12];
          it_ctx_q <= ctx;
        end
      end
    end
    assign it_hit = it_valid_q && (it_va_q == if_va_i[63:12]) &&
                    (it_ctx_q == ctx);
    assign ir_live = !ichg_q && (ir_va_q == if_va_i) && (ir_ctx_q == ctx);
    assign if_pa_o = if_trans ? {it_pa_q, if_va_i[11:0]} : if_va_i;
    assign if_ok_o = !if_trans || it_hit;
    assign if_fault_o = if_trans && !it_hit && ir_live && ir_q.fault;
    assign if_fault_page_o = ir_q.page;
    // The guest flag only with the fault, as main: the core takes the
    // GPA (mtval2/htval) for any fetch fault that has it set.
    assign if_fault_guest_o = if_fault_o && ir_q.guest;
    assign if_fault_gpa_o = ir_q.gpa;
    assign miss_f = if_trans && !it_hit && ir_live && !ir_q.ok && !ir_q.fault;
`ifndef SYNTHESIS
    // Every cycle: a one-hot hit is an index hit with the same entry
    // and verdicts (the D port's check is in g_dreg). Every cycle IF
    // uses it_q, the full lookup of the fetch VA is a miss or the same
    // page (no SFENCE since), unless it_q was loaded before the last
    // TLB write: a re-walk may have re-read a PTE changed without
    // SFENCE, and either translation is then legal.
    lookup_t if_ref;
    logic    it_old_q;
    assign if_ref = lookup_idx(if_va_i, satp_asid, if_virt_i, hgatp_vmid,
                               if_g_trans, if_vs_trans, if_priv_i, 2'd2, 1'b0,
                               sum_i, mxr_i);
    always_ff @(posedge clk_i) begin
      if (ichg_d) it_old_q <= 1'b1;
      else if (if_trans && if_res.ok) it_old_q <= 1'b0;
      if ((if_lk.hit != if_ref.hit) || (if_lk.hit && (if_lk != if_ref)))
        $error("sigil_mmu: one-hot TLB lookup differs from find_entry");
      if (chk_live_q && if_trans && it_hit && !it_old_q &&
          (if_res.fault || (if_res.ok && (if_res.pa[63:12] != it_pa_q))))
        $error("sigil_mmu: fetch page register differs from the I-port lookup");
    end
`endif
  end else begin : g_ireg_off
    always_comb begin
      logic [5:0] f;
      tlb_entry_t e;
      if_pa_o = if_va_i;
      if_ok_o = 1'b0;
      if_fault_o = 1'b0;
      if_fault_page_o = 1'b1;
      if_fault_guest_o = 1'b0;
      if_fault_gpa_o = 64'd0;
      f = find_entry(if_va_i, satp_asid, if_virt_i, hgatp_vmid,
                     if_g_trans, if_vs_trans);
      e = tlb_q[f[4:0]];
      if (!if_trans) begin
        if_ok_o = 1'b1;
      end else if (if_vs_trans && !canonical(if_va_i)) begin
        if_fault_o = 1'b1;
      end else if (!if_vs_trans && if_g_trans && |if_va_i[63:41]) begin
        if_fault_o = 1'b1;
        if_fault_guest_o = 1'b1;
        if_fault_gpa_o = if_va_i;
      end else if (wf_valid_q && !wf_is_data_q && (wf_va_q == if_va_i)) begin
        // A recorded walk fault supersedes a stale TLB hit that
        // triggered the re-walk (e.g. a G-stage permission denial).
        if_fault_o = 1'b1;
        if_fault_page_o = wf_page_q;
        if_fault_guest_o = wf_guest_q;
        if_fault_gpa_o = wf_gpa_q;
      end else if (f[5]) begin
        if_pa_o = entry_pa(e, if_va_i);
        if (!perm_ok(e, if_priv_i, 2'd2, sum_i, mxr_i)) begin
          if_fault_o = 1'b1;
        end else if (g_perm_ok(e, 2'd2, hs_mxr_i) && e.a) begin
          if_ok_o = 1'b1;  // G denial or A=0 falls through to a re-walk
        end
      end
    end
    assign miss_f = if_trans && !if_ok_o && !if_fault_o;
  end

  // Data port. Main: the d_* outputs are the combinational lookup of
  // MEM's access. FPGA_TIMING (#53): they are mt_q, the lookup of the
  // dl_* port registered on dl_ld_i, so MEM's PMP check, request and
  // exception logic start from flops. mt_q is live while dl_vld_i was
  // set with it and no update that can change a data lookup (TLB
  // write, flush, abort, data walk fault: chg_q) has landed since its
  // capture; otherwise the core replays MEM's access on the port. A
  // data walk starts from a live miss in mt_q, so a just-filled entry
  // or a just-recorded fault never starts a second walk. A capture of
  // EX's access that matches the recorded walk fault is not valid:
  // main applies the record to MEM's access only while MEM presents
  // its VA, so MEM replays its own lookup then (+1 cycle).
  if (FPGA_TIMING) begin : g_dreg
    logic  dl_vs_trans, dl_g_trans, dl_wf, chg_d, chg_q, mt_valid_q, mt_live;
    dres_t dl_res, mt_q;
    /* verilator lint_off UNUSEDSIGNAL */  // only the PA fields of .e are read
    lookup_t d_lk;
    /* verilator lint_on UNUSEDSIGNAL */
    assign dl_vs_trans = (dl_satp_i[63:60] == 4'd8) && (dl_priv_i != 2'b11);
    assign dl_g_trans = dl_virt_i && hgatp_sv39x4;
    assign d_lk = lookup_1h(dl_va_i, dl_satp_i[59:44], dl_virt_i, hgatp_vmid,
                            dl_g_trans, dl_vs_trans, dl_priv_i,
                            dl_exec_i ? 2'd2 : dl_write_i ? 2'd1 : 2'd0,
                            dl_write_i, dl_sum_i, dl_mxr_i);
    assign dl_res = port_result(dl_va_i, 1'b1, 1'b1, dl_vs_trans || dl_g_trans,
                                dl_vs_trans, dl_g_trans, d_lk);
    assign dl_wf = wf_valid_q && wf_is_data_q && (wf_va_q == dl_va_i);
    // Every TLB write is on a walker grant; a data walk fault is on a
    // grant or a G-stage GPA width fault.
    assign chg_d = flush_i || abort_i ||
                   ((state_q != W_IDLE) && walk_grant_i) ||
                   ((state_q == W_G_READ) && req_is_data_q && g_width_fault);
    always_ff @(posedge clk_i or negedge rst_ni) begin
      if (!rst_ni) begin
        mt_q <= '0;
        mt_valid_q <= 1'b0;
        chg_q <= 1'b0;
      end else begin
        chg_q <= chg_d;
        if (dl_ld_i) begin
          mt_q <= dl_res;
          mt_valid_q <= dl_vld_i && (dl_mem_i || !dl_wf);
        end
      end
    end
    assign mt_live = mt_valid_q && !chg_q;
    assign d_pa_o = mt_q.pa;
    assign d_ok_o = mt_live && mt_q.ok;
    assign d_fault_o = d_valid_i && mt_live && mt_q.fault;
    assign d_fault_page_o = mt_q.page;
    assign d_fault_guest_o = mt_q.guest;
    assign d_fault_gpa_o = mt_q.gpa;
    assign miss_d = d_valid_i && mt_live && !mt_q.ok && !mt_q.fault;
`ifndef SYNTHESIS
    // Every cycle: the one-hot D lookup equals find_entry, and
    // whenever MEM uses mt_q it equals the lookup of MEM's own access
    // in MEM's context (d_*), so the port's EX lookup saw MEM's
    // translation context. Only a capture of MEM's own access that
    // matched the recorded walk fault is exempt, once the record no
    // longer applies to MEM's VA (it may drop, e.g. at a fetch walk
    // start, before MEM uses the capture); EX's such capture is not
    // valid.
    lookup_t dl_ref, s_lk;
    dres_t   s_res;
    logic    mt_wf_q, mt_mem_q, wf_mem;
    assign dl_ref = lookup_idx(dl_va_i, dl_satp_i[59:44], dl_virt_i,
                               hgatp_vmid, dl_g_trans, dl_vs_trans, dl_priv_i,
                               dl_exec_i ? 2'd2 : dl_write_i ? 2'd1 : 2'd0,
                               dl_write_i, dl_sum_i, dl_mxr_i);
    assign s_lk = lookup_idx(d_va_i, d_satp_asid, d_virt_i, hgatp_vmid,
                             d_g_trans, d_vs_trans, d_priv_i, d_acc,
                             d_write_i, sum_i, mxr_i);
    assign s_res = port_result(d_va_i, 1'b1, 1'b1, d_trans, d_vs_trans,
                               d_g_trans, s_lk);
    assign wf_mem = wf_valid_q && wf_is_data_q && (wf_va_q == d_va_i);
    always_ff @(posedge clk_i) begin
      if (dl_ld_i) begin
        mt_wf_q <= dl_wf;
        mt_mem_q <= dl_mem_i;
      end
      if ((d_lk.hit != dl_ref.hit) || (d_lk.hit && (d_lk != dl_ref)))
        $error("sigil_mmu: one-hot TLB lookup differs from find_entry");
      if (chk_live_q && d_valid_i && mt_live &&
          !(mt_wf_q && mt_mem_q && !wf_mem) &&
          ((mt_q.ok != s_res.ok) || (mt_q.fault != s_res.fault) ||
           (mt_q.ok && (mt_q.pa != s_res.pa)) ||
           (mt_q.fault && ({mt_q.page, mt_q.guest, mt_q.gpa} !=
                           {s_res.page, s_res.guest, s_res.gpa}))))
        $error("sigil_mmu: registered data translation differs from MEM's lookup");
    end
`endif
  end else begin : g_dreg_off
    always_comb begin
      logic [5:0] f;
      tlb_entry_t e;
      d_pa_o = d_va_i;
      d_ok_o = 1'b0;
      d_fault_o = 1'b0;
      d_fault_page_o = 1'b1;
      d_fault_guest_o = 1'b0;
      d_fault_gpa_o = 64'd0;
      f = find_entry(d_va_i, d_satp_asid, d_virt_i, hgatp_vmid,
                     d_g_trans, d_vs_trans);
      e = tlb_q[f[4:0]];
      if (!d_trans) begin
        d_ok_o = 1'b1;
      end else if (d_vs_trans && !canonical(d_va_i)) begin
        d_fault_o = d_valid_i;
      end else if (!d_vs_trans && d_g_trans && |d_va_i[63:41]) begin
        d_fault_o = d_valid_i;
        d_fault_guest_o = 1'b1;
        d_fault_gpa_o = d_va_i;
      end else if (wf_valid_q && wf_is_data_q && (wf_va_q == d_va_i)) begin
        d_fault_o = d_valid_i;
        d_fault_page_o = wf_page_q;
        d_fault_guest_o = wf_guest_q;
        d_fault_gpa_o = wf_gpa_q;
      end else if (f[5]) begin
        d_pa_o = entry_pa(e, d_va_i);
        if (!perm_ok(e, d_priv_i,
                     d_exec_i ? 2'd2 : d_write_i ? 2'd1 : 2'd0,
                     sum_i, mxr_i)) begin
          d_fault_o = d_valid_i;
        end else if (g_perm_ok(e,
                               d_exec_i ? 2'd2 : d_write_i ? 2'd1 : 2'd0,
                               hs_mxr_i) &&
                     e.a && (!d_write_i || e.d)) begin
          d_ok_o = 1'b1;
        end
      end
    end
    assign miss_d = d_valid_i && d_trans && !d_ok_o && !d_fault_o;
  end

  // Fill target: reuse an existing (A/D-stale) entry for this VA
  // so a re-walk never leaves a duplicate for lookups to find.
  logic [5:0] exist_f;
  logic [4:0] fill_idx;
  assign exist_f = find_entry(req_va_q, req_asid_q, req_virt_q,
                              req_vmid_q, req_g_q, req_vs_q);
  assign fill_idx = exist_f[5] ? exist_f[4:0] : fill_ptr_q;

  /* verilator lint_off UNUSEDSIGNAL */  // only the VPN slice is read
  function automatic logic [63:0] pte_addr(
      input logic [43:0] base_ppn, input logic [63:0] va,
      input logic [1:0] level);
    logic [8:0] vpn_i;
    if (level == 2'd2)      vpn_i = va[38:30];
    else if (level == 2'd1) vpn_i = va[29:21];
    else                    vpn_i = va[20:12];
    return {8'd0, base_ppn, 12'd0} + {52'd0, vpn_i, 3'd0};
  endfunction

  // Sv39x4: the root index is GPA[40:30] (11 bits, 16 KiB root).
  function automatic logic [63:0] g_pte_addr(
      input logic [43:0] base_ppn, input logic [63:0] gpa,
      input logic [1:0] level);
    if (level == 2'd2) begin
      return {8'd0, base_ppn, 12'd0} + {50'd0, gpa[40:30], 3'd0};
    end else if (level == 2'd1) begin
      return {8'd0, base_ppn, 12'd0} + {52'd0, gpa[29:21], 3'd0};
    end else begin
      return {8'd0, base_ppn, 12'd0} + {52'd0, gpa[20:12], 3'd0};
    end
  endfunction

  // Combined 4 KiB fill for a completed G translation. For a
  // VS+G fill the VS leaf fields were latched when its PTE was
  // read; for G-only (vsatp Bare) there are no VS checks.
  function automatic tlb_entry_t combined_entry(
      input logic [63:0] spa, input logic gr, input logic gw,
      input logic gx, input logic gd);
    combined_entry = '0;
    combined_entry.valid = 1'b1;
    combined_entry.guest = 1'b1;
    combined_entry.vs_bare = !req_vs_q;
    combined_entry.asid = req_asid_q;
    combined_entry.vmid = req_vmid_q;
    combined_entry.vpn = req_va_q[38:12];
    combined_entry.vpn_ext = req_va_q[40:39];
    combined_entry.ppn = spa[55:12];
    combined_entry.level = 2'd0;
    combined_entry.r = vs_r_q;
    combined_entry.w = vs_w_q;
    combined_entry.x = vs_x_q;
    combined_entry.u = vs_u_q;
    combined_entry.g = vs_g_q;
    combined_entry.a = 1'b1;
    combined_entry.d = req_vs_q ? (vs_d_q && gd) : gd;
    combined_entry.gr = gr;
    combined_entry.gw = gw;
    combined_entry.gx = gx;
  endfunction
  /* verilator lint_on UNUSEDSIGNAL */

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q <= W_IDLE;
      fill_ptr_q <= 5'd0;
      wf_valid_q <= 1'b0;
      req_is_data_q <= 1'b0;
      req_virt_q <= 1'b0;
      req_vs_q <= 1'b0;
      req_g_q <= 1'b0;
      req_va_q <= 64'd0;
      req_acc_q <= 2'd0;
      req_priv_q <= 2'd0;
      req_asid_q <= 16'd0;
      req_vmid_q <= 16'd0;
      level_q <= 2'd0;
      pte_addr_q <= 64'd0;
      pte_q <= 64'd0;
      vs_pte_gpa_q <= 64'd0;
      final_gpa_q <= 64'd0;
      vs_r_q <= 1'b0;
      vs_w_q <= 1'b0;
      vs_x_q <= 1'b0;
      vs_u_q <= 1'b0;
      vs_g_q <= 1'b0;
      vs_d_q <= 1'b0;
      g_level_q <= 2'd0;
      g_acc_q <= 2'd0;
      g_purpose_q <= 2'd0;
      g_gpa_q <= 64'd0;
      g_pte_q <= 64'd0;
      g_spa_q <= 64'd0;
      g_r_q <= 1'b0;
      g_w_q <= 1'b0;
      g_x_q <= 1'b0;
      g_d_q <= 1'b0;
      wf_is_data_q <= 1'b0;
      wf_page_q <= 1'b1;
      wf_guest_q <= 1'b0;
      wf_va_q <= 64'd0;
      wf_gpa_q <= 64'd0;
      for (int i = 0; i < 32; i++) tlb_q[i] <= '0;
    end else if (flush_i || abort_i) begin
      state_q <= W_IDLE;
      wf_valid_q <= 1'b0;
      if (flush_i) begin
        for (int i = 0; i < 32; i++) tlb_q[i].valid <= 1'b0;
      end
    end else begin
      // A recorded fault lives only while its port still presents
      // the faulting VA; anything else would negative-cache it.
      if (wf_valid_q &&
          ((wf_is_data_q && (d_va_i != wf_va_q)) ||
           (!wf_is_data_q && (if_va_i != wf_va_q)))) begin
        wf_valid_q <= 1'b0;
      end
      unique case (state_q)
        W_IDLE: begin
          if (miss_d) begin
            req_is_data_q <= 1'b1;
            req_virt_q <= d_virt_i;
            req_vs_q <= d_vs_trans;
            req_g_q <= d_g_trans;
            req_va_q <= d_va_i;
            req_acc_q <= d_acc;
            req_priv_q <= d_priv_i;
            req_asid_q <= d_satp_asid;
            req_vmid_q <= hgatp_vmid;
            level_q <= 2'd2;
            wf_valid_q <= 1'b0;
            if (d_vs_trans) begin
              vs_pte_gpa_q <= d_root_pte;
              if (d_g_trans) begin
                state_q <= W_G_READ;
                g_gpa_q <= d_root_pte;
                g_acc_q <= 2'd0;
                g_purpose_q <= 2'd1;
                g_level_q <= 2'd2;
                pte_addr_q <= g_pte_addr(hgatp_i[43:0], d_root_pte, 2'd2);
              end else begin
                state_q <= W_VS_READ;
                pte_addr_q <= d_root_pte;
              end
            end else begin
              state_q <= W_G_READ;
              g_gpa_q <= d_va_i;
              g_acc_q <= d_acc;
              g_purpose_q <= 2'd0;
              g_level_q <= 2'd2;
              pte_addr_q <= g_pte_addr(hgatp_i[43:0], d_va_i, 2'd2);
            end
          end else if (miss_f) begin
            req_is_data_q <= 1'b0;
            req_virt_q <= if_virt_i;
            req_vs_q <= if_vs_trans;
            req_g_q <= if_g_trans;
            req_va_q <= if_va_i;
            req_acc_q <= 2'd2;
            req_priv_q <= if_priv_i;
            req_asid_q <= satp_asid;
            req_vmid_q <= hgatp_vmid;
            level_q <= 2'd2;
            wf_valid_q <= 1'b0;
            if (if_vs_trans) begin
              vs_pte_gpa_q <= pte_addr(satp_i[43:0], if_va_i, 2'd2);
              if (if_g_trans) begin
                state_q <= W_G_READ;
                g_gpa_q <= pte_addr(satp_i[43:0], if_va_i, 2'd2);
                g_acc_q <= 2'd0;
                g_purpose_q <= 2'd1;
                g_level_q <= 2'd2;
                pte_addr_q <= g_pte_addr(hgatp_i[43:0],
                    pte_addr(satp_i[43:0], if_va_i, 2'd2), 2'd2);
              end else begin
                state_q <= W_VS_READ;
                pte_addr_q <= pte_addr(satp_i[43:0], if_va_i, 2'd2);
              end
            end else begin
              state_q <= W_G_READ;
              g_gpa_q <= if_va_i;
              g_acc_q <= 2'd2;
              g_purpose_q <= 2'd0;
              g_level_q <= 2'd2;
              pte_addr_q <= g_pte_addr(hgatp_i[43:0], if_va_i, 2'd2);
            end
          end
        end
        W_G_READ: begin
          if (walk_preempt) begin
            // An older data miss preempts a fetch walk.
            req_is_data_q <= 1'b1;
            req_virt_q <= d_virt_i;
            req_vs_q <= d_vs_trans;
            req_g_q <= d_g_trans;
            req_va_q <= d_va_i;
            req_acc_q <= d_acc;
            req_priv_q <= d_priv_i;
            req_asid_q <= d_satp_asid;
            req_vmid_q <= hgatp_vmid;
            level_q <= 2'd2;
            if (d_vs_trans) begin
              vs_pte_gpa_q <= d_root_pte;
              if (d_g_trans) begin
                g_gpa_q <= d_root_pte;
                g_acc_q <= 2'd0;
                g_purpose_q <= 2'd1;
                g_level_q <= 2'd2;
                pte_addr_q <= g_pte_addr(hgatp_i[43:0], d_root_pte, 2'd2);
              end else begin
                state_q <= W_VS_READ;
                pte_addr_q <= d_root_pte;
              end
            end else begin
              g_gpa_q <= d_va_i;
              g_acc_q <= d_acc;
              g_purpose_q <= 2'd0;
              g_level_q <= 2'd2;
              pte_addr_q <= g_pte_addr(hgatp_i[43:0], d_va_i, 2'd2);
            end
          end else if (g_width_fault) begin
            state_q <= W_IDLE;
            wf_valid_q <= 1'b1;
            wf_is_data_q <= req_is_data_q;
            wf_page_q <= 1'b1;
            wf_guest_q <= 1'b1;
            wf_va_q <= req_va_q;
            wf_gpa_q <= g_gpa_q;
          end else if (walk_grant_i) begin
            if (!walk_pmp_allow_i) begin
              state_q <= W_IDLE;
              wf_valid_q <= 1'b1;
              wf_is_data_q <= req_is_data_q;
              wf_page_q <= 1'b0;
              wf_guest_q <= 1'b0;
              wf_va_q <= req_va_q;
              wf_gpa_q <= 64'd0;
            end else if (g_pte_fault) begin
              state_q <= W_IDLE;
              wf_valid_q <= 1'b1;
              wf_is_data_q <= req_is_data_q;
              wf_page_q <= 1'b1;
              wf_guest_q <= 1'b1;
              wf_va_q <= req_va_q;
              wf_gpa_q <= g_gpa_q;
            end else if (!g_pte_leaf) begin
              g_level_q <= g_level_q - 2'd1;
              pte_addr_q <= g_pte_addr(walk_rdata_i[53:10], g_gpa_q,
                                       g_level_q - 2'd1);
            end else begin
              g_spa_q <= g_leaf_spa;
              g_r_q <= walk_rdata_i[1];
              g_w_q <= walk_rdata_i[2];
              g_x_q <= walk_rdata_i[3];
              g_d_q <= walk_rdata_i[7] || (g_acc_q == 2'd1);
              if (g_needs_upd) begin
                state_q <= W_G_UPD;
                g_pte_q <= walk_rdata_i;
              end else if (g_purpose_q == 2'd1) begin
                state_q <= W_VS_READ;
                pte_addr_q <= g_leaf_spa;
              end else if (g_purpose_q == 2'd2) begin
                state_q <= W_VS_UPD;
                pte_addr_q <= g_leaf_spa;
              end else begin
                state_q <= W_IDLE;
                tlb_q[fill_idx] <= combined_entry(g_leaf_spa,
                    walk_rdata_i[1], walk_rdata_i[2], walk_rdata_i[3],
                    walk_rdata_i[7] || (g_acc_q == 2'd1));
                if (!exist_f[5]) fill_ptr_q <= fill_ptr_q + 5'd1;
              end
            end
          end
        end
        W_G_UPD: begin
          if (walk_grant_i) begin
            if (!walk_pmp_allow_i) begin
              state_q <= W_IDLE;
              wf_valid_q <= 1'b1;
              wf_is_data_q <= req_is_data_q;
              wf_page_q <= 1'b0;
              wf_guest_q <= 1'b0;
              wf_va_q <= req_va_q;
              wf_gpa_q <= 64'd0;
            end else if (g_purpose_q == 2'd1) begin
              state_q <= W_VS_READ;
              pte_addr_q <= g_spa_q;
            end else if (g_purpose_q == 2'd2) begin
              state_q <= W_VS_UPD;
              pte_addr_q <= g_spa_q;
            end else begin
              state_q <= W_IDLE;
              tlb_q[fill_idx] <= combined_entry(g_spa_q, g_r_q, g_w_q,
                                                g_x_q, g_d_q);
              if (!exist_f[5]) fill_ptr_q <= fill_ptr_q + 5'd1;
            end
          end
        end
        W_VS_READ: begin
          // An older data miss preempts a fetch walk.
          if (walk_preempt) begin
            req_is_data_q <= 1'b1;
            req_virt_q <= d_virt_i;
            req_vs_q <= d_vs_trans;
            req_g_q <= d_g_trans;
            req_va_q <= d_va_i;
            req_acc_q <= d_acc;
            req_priv_q <= d_priv_i;
            req_asid_q <= d_satp_asid;
            req_vmid_q <= hgatp_vmid;
            level_q <= 2'd2;
            if (d_vs_trans) begin
              vs_pte_gpa_q <= d_root_pte;
              if (d_g_trans) begin
                state_q <= W_G_READ;
                g_gpa_q <= d_root_pte;
                g_acc_q <= 2'd0;
                g_purpose_q <= 2'd1;
                g_level_q <= 2'd2;
                pte_addr_q <= g_pte_addr(hgatp_i[43:0], d_root_pte, 2'd2);
              end else begin
                pte_addr_q <= d_root_pte;
              end
            end else begin
              state_q <= W_G_READ;
              g_gpa_q <= d_va_i;
              g_acc_q <= d_acc;
              g_purpose_q <= 2'd0;
              g_level_q <= 2'd2;
              pte_addr_q <= g_pte_addr(hgatp_i[43:0], d_va_i, 2'd2);
            end
          end else if (walk_grant_i) begin
            if (!walk_pmp_allow_i) begin
              state_q <= W_IDLE;      // implicit-access PMP denial
              wf_valid_q <= 1'b1;
              wf_is_data_q <= req_is_data_q;
              wf_page_q <= 1'b0;
              wf_guest_q <= 1'b0;
              wf_va_q <= req_va_q;
              wf_gpa_q <= 64'd0;
            end else if (pte_fault) begin
              state_q <= W_IDLE;
              wf_valid_q <= 1'b1;
              wf_is_data_q <= req_is_data_q;
              wf_page_q <= 1'b1;
              wf_guest_q <= 1'b0;
              wf_va_q <= req_va_q;
              wf_gpa_q <= 64'd0;
            end else if (!pte_leaf) begin
              level_q <= level_q - 2'd1;
              vs_pte_gpa_q <= pte_addr(walk_rdata_i[53:10], req_va_q,
                                       level_q - 2'd1);
              if (req_g_q) begin
                state_q <= W_G_READ;
                g_gpa_q <= pte_addr(walk_rdata_i[53:10], req_va_q,
                                    level_q - 2'd1);
                g_acc_q <= 2'd0;
                g_purpose_q <= 2'd1;
                g_level_q <= 2'd2;
                pte_addr_q <= g_pte_addr(hgatp_i[43:0],
                    pte_addr(walk_rdata_i[53:10], req_va_q,
                             level_q - 2'd1), 2'd2);
              end else begin
                pte_addr_q <= pte_addr(walk_rdata_i[53:10], req_va_q,
                                       level_q - 2'd1);
              end
            end else begin
              // VS leaf: latch it for the final G translation.
              vs_r_q <= walk_rdata_i[1];
              vs_w_q <= walk_rdata_i[2];
              vs_x_q <= walk_rdata_i[3];
              vs_u_q <= walk_rdata_i[4];
              vs_g_q <= walk_rdata_i[5];
              vs_d_q <= walk_rdata_i[7] || (req_acc_q == 2'd1);
              final_gpa_q <= entry_pa(fill_entry, req_va_q);
              if (pte_needs_upd) begin
                pte_q <= walk_rdata_i;
                if (req_g_q) begin
                  state_q <= W_G_READ;
                  g_gpa_q <= vs_pte_gpa_q;
                  g_acc_q <= 2'd1;
                  g_purpose_q <= 2'd2;
                  g_level_q <= 2'd2;
                  pte_addr_q <= g_pte_addr(hgatp_i[43:0],
                                           vs_pte_gpa_q, 2'd2);
                end else begin
                  state_q <= W_VS_UPD;
                end
              end else if (req_g_q) begin
                state_q <= W_G_READ;
                g_gpa_q <= entry_pa(fill_entry, req_va_q);
                g_acc_q <= req_acc_q;
                g_purpose_q <= 2'd0;
                g_level_q <= 2'd2;
                pte_addr_q <= g_pte_addr(hgatp_i[43:0],
                    entry_pa(fill_entry, req_va_q), 2'd2);
              end else begin
                state_q <= W_IDLE;
                tlb_q[fill_idx] <= fill_entry;
                if (!exist_f[5]) fill_ptr_q <= fill_ptr_q + 5'd1;
              end
            end
          end
        end
        W_VS_UPD: begin
          if (walk_grant_i) begin
            if (!walk_pmp_allow_i) begin
              state_q <= W_IDLE;
              wf_valid_q <= 1'b1;
              wf_is_data_q <= req_is_data_q;
              wf_page_q <= 1'b0;
              wf_guest_q <= 1'b0;
              wf_va_q <= req_va_q;
              wf_gpa_q <= 64'd0;
            end else if (req_g_q) begin
              // VS A/D is written; now translate the final GPA.
              state_q <= W_G_READ;
              g_gpa_q <= final_gpa_q;
              g_acc_q <= req_acc_q;
              g_purpose_q <= 2'd0;
              g_level_q <= 2'd2;
              pte_addr_q <= g_pte_addr(hgatp_i[43:0], final_gpa_q, 2'd2);
            end else begin
              state_q <= W_IDLE;
              // Rebuild the fill entry from the stored PTE.
              tlb_q[fill_idx].valid <= 1'b1;
              tlb_q[fill_idx].guest <= req_virt_q;
              tlb_q[fill_idx].vs_bare <= 1'b0;
              tlb_q[fill_idx].asid <= req_asid_q;
              tlb_q[fill_idx].vmid <= req_vmid_q;
              tlb_q[fill_idx].vpn <= req_va_q[38:12];
              tlb_q[fill_idx].ppn <= pte_q[53:10];
              tlb_q[fill_idx].level <= level_q;
              tlb_q[fill_idx].napot <= pte_q[63];
              tlb_q[fill_idx].r <= pte_q[1];
              tlb_q[fill_idx].w <= pte_q[2];
              tlb_q[fill_idx].x <= pte_q[3];
              tlb_q[fill_idx].u <= pte_q[4];
              tlb_q[fill_idx].g <= pte_q[5];
              tlb_q[fill_idx].a <= 1'b1;
              tlb_q[fill_idx].d <= pte_q[7] || (req_acc_q == 2'd1);
              tlb_q[fill_idx].gr <= 1'b1;
              tlb_q[fill_idx].gw <= 1'b1;
              tlb_q[fill_idx].gx <= 1'b1;
              if (!exist_f[5]) fill_ptr_q <= fill_ptr_q + 5'd1;
            end
          end
        end
        default: state_q <= W_IDLE;  // unused encodings recover
      endcase
    end
  end
endmodule
`default_nettype wire
