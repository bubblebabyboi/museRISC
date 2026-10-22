// Simulation-only performance event counters (issue #56).
//
// Textually included at the end of sigil_cpu inside `ifndef SYNTHESIS.
// Every synthesis flow (ORFS/slang, Yosys, sv2v, Vivado) defines
// SYNTHESIS, so none of them ever reads this file: it cannot change a
// netlist. It is passive: it only reads core, cache and bus signals
// through hierarchical references and drives nothing in the design.
// Method and counter definitions: docs/PERFORMANCE.md.
//
// Measured region. Software writes a marker to mhpmevent31 (CSR
// 0x33F). On this core mhpmevent3..31 are legal WARL CSRs whose writes
// are ignored, so the marker has no architectural effect and costs one
// ordinary CSR instruction (CSR writes do not flush this pipeline);
// on hardware it is simply a no-op. The marker value is
//   [63:16] = 0x5045 ("PE")  [15:8] = region id  [7:0] = 1 begin / 2 end
// (sw/sdk/include/sigil.h: sigil_perf_begin() / sigil_perf_end()).
// The window is [cycle of the begin marker's CSR write, cycle of the
// end marker's CSR write): by construction `cycles` and `instret` equal
// the mcycle / minstret deltas between the two markers, which the
// record also reports (mcycle_delta, minstret_delta) as a cross-check.
// One region is open at a time; a begin while open restarts it.
//
// Output: one line per end marker,
//   SIGIL_PERF v1 region=<id> seq=<n> <key>=<value> ...
// appended to the file named by the plusarg +sigil_perf=<file>, or
// written to stderr without it.
//
// Accounting. Every cycle in the window is charged to exactly one
// stk_* category (they sum to `cycles`; checked at each dump):
//   stk_retire           an instruction retires in WB
//   stk_trap             WB holds a trapping instruction, or the slot
//                        was emptied by a trap flush
//   stk_dc_lat .. stk_vls  the whole pipeline is frozen by MEM
//                        (mem_stall), by sub-cause: D$ hit latency,
//                        D$ miss (write-back/refill), uncached device
//                        access (stk_io), FENCE.I D$ clean, data TLB
//                        walk, vector load/store sequencing
//   otherwise WB holds a bubble, charged to the cause that created it
//   (a shadow tag travels with every empty slot down the pipeline):
//   stk_fetch_lat        IF waited for an I$ hit (request/response
//                        latency and the fetch issue gap)
//   stk_fetch_miss       IF waited for an I$ refill
//   stk_fetch_unc        IF waited for an uncached fetch (boot ROM)
//   stk_fetch_itlb       IF waited for the page-table walker
//   stk_fetch_straddle   a 32-bit instruction straddled a fetch word
//   stk_branch/jal/jalr  a wrong-path instruction squashed by a taken
//                        branch / jal / jalr (a slot that was already
//                        empty keeps its own cause)
//   stk_serial           squashed by xRET/FENCE.I/SFENCE, or fetch
//                        blocked by a FENCE.I in MEM
//   stk_loaduse          load-use interlock bubble
//   stk_muldiv/fpu/vec   EX held by the M unit / FPU / vector unit
//   stk_other            reset or frozen (trap_halt_i) cycles
/* verilator coverage_off */
  typedef enum int {
    // Per-cycle accounting (exactly one per cycle; sums to PE_CYCLES).
    PE_STK_RETIRE, PE_STK_FETCH_LAT, PE_STK_FETCH_MISS, PE_STK_FETCH_UNC,
    PE_STK_FETCH_ITLB, PE_STK_FETCH_STRADDLE, PE_STK_BRANCH, PE_STK_JAL,
    PE_STK_JALR, PE_STK_SERIAL, PE_STK_LOADUSE, PE_STK_MULDIV, PE_STK_FPU,
    PE_STK_VEC, PE_STK_DC_LAT, PE_STK_DC_MISS, PE_STK_IO, PE_STK_DC_CLEAN,
    PE_STK_DTLB, PE_STK_VLS, PE_STK_TRAP, PE_STK_OTHER,
    // Totals.
    PE_CYCLES, PE_INSTRET,
    // Retired instructions by class (PE_RET_ALU + class code).
    PE_RET_ALU, PE_RET_LOAD, PE_RET_STORE, PE_RET_AMO, PE_RET_BRANCH,
    PE_RET_JAL, PE_RET_JALR, PE_RET_MUL, PE_RET_DIV, PE_RET_FP, PE_RET_VEC,
    PE_RET_VLS, PE_RET_VSET, PE_RET_CSR, PE_RET_FENCE, PE_RET_SYSTEM,
    PE_RET_RVC,  // compressed (16-bit) instructions, any class
    // Redirect / flush events (counted when the flush takes effect).
    PE_BR_TAKEN, PE_JAL_REDIR, PE_JALR_REDIR, PE_XRET_FLUSH, PE_FENCEI_FLUSH,
    PE_SFENCE_FLUSH, PE_SQUASH_ID, PE_SQUASH_IF, PE_TRAP_EXC, PE_TRAP_IRQ,
    // Raw stall / busy cycles (overlapping, not exclusive).
    PE_LOADUSE_CYC, PE_MULDIV_BUSY, PE_FPU_BUSY, PE_VEC_BUSY, PE_VEC_EX_STALL,
    PE_VLS_CYC, PE_FETCH_STALL_CYC, PE_ITLB_CYC, PE_DTLB_CYC, PE_MEM_STALL_CYC,
    // L1 instruction cache (core fetch port).
    PE_IC_ACCESS, PE_IC_MISS, PE_IC_UNC, PE_IC_MISS_CYC,
    // L1 data cache (core data port, MEM and page-table walker).
    PE_DC_LOAD, PE_DC_STORE, PE_DC_CLEAN, PE_DC_MISS, PE_DC_UNC,
    PE_DC_MISS_CYC, PE_DC_UNC_CYC,
    // Memory bus (sigil_cpu master port): transactions by kind, then
    // occupied cycles, request backpressure and response wait cycles.
    PE_BUS_IFILL, PE_BUS_IUNC, PE_BUS_DFILL, PE_BUS_DWB, PE_BUS_DUNC,
    PE_BUS_BUSY_CYC, PE_BUS_REQ_WAIT, PE_BUS_RSP_WAIT,
    PE_COUNT
  } perf_ev_e;
  localparam int PerfN = int'(PE_COUNT);
  localparam int PerfStkN = int'(PE_STK_OTHER) + 1;

  // Marker decode (EX-stage CSR write; csr_we is high for exactly one
  // cycle per committing CSR write).
  logic        perf_mark, perf_begin, perf_end;
  logic [7:0]  perf_mark_region;
  assign perf_mark = u_core.csr_we && (u_core.csr_addr == 12'h33F) &&
                     (u_core.csr_wdata[63:16] == 48'h0000_0000_5045);
  assign perf_mark_region = u_core.csr_wdata[15:8];
  assign perf_begin = perf_mark && (u_core.csr_wdata[7:0] == 8'd1);
  assign perf_end = perf_mark && (u_core.csr_wdata[7:0] == 8'd2);

  logic        perf_on_q, perf_active;
  logic [7:0]  perf_region_q;
  logic [31:0] perf_seq_q;
  logic [63:0] perf_mc_b_q, perf_mi_b_q;
  logic [63:0] perf_cnt_q [PerfN];
  logic [PerfN-1:0] perf_inc;
  assign perf_active = (perf_on_q || perf_begin) && !perf_end;

  // Outstanding-request classification for the L1s (set by the
  // lookup-miss tap / an uncached accept, cleared by the response).
  logic perf_ic_miss_q, perf_ic_unc_q, perf_dc_miss_q, perf_dc_unc_q;
  logic perf_ic_acc, perf_dc_acc, perf_ic_cacheable, perf_dc_cacheable;
  assign perf_ic_acc = ireq_valid && ireq_ready;
  assign perf_dc_acc = dreq_valid && dreq_ready;
  assign perf_ic_cacheable = pma_cacheable(ireq_addr, cache_en_i,
                                           C0_BASE, C0_SIZE, C1_BASE, C1_SIZE);
  assign perf_dc_cacheable = pma_cacheable(dreq_addr, cache_en_i,
                                           C0_BASE, C0_SIZE, C1_BASE, C1_SIZE);

  // Pipeline update condition (the core's pipeline registers move).
  logic perf_upd;
  assign perf_upd = !u_core.trap_take && !u_core.freeze && !u_core.mem_stall;

  // Instruction class of the ID instruction (retired-class counters).
  /* verilator lint_off UNUSEDSIGNAL */
  function automatic logic [3:0] perf_class(input sigil_pkg::ctrl_t c,
                                            input logic [6:0] opcode);
    if (c.vec && c.vset) return 4'd12;                          // VSET
    if (c.vec && (c.mem_read || c.mem_write)) return 4'd11;     // VLS
    if (c.vec) return 4'd10;                                    // VEC
    if (c.amo || c.lr || c.sc) return 4'd3;                     // AMO
    if (c.mem_read) return 4'd1;                                // LOAD
    if (c.mem_write) return 4'd2;                               // STORE
    if (c.branch) return 4'd4;                                  // BRANCH
    if (c.jal) return 4'd5;                                     // JAL
    if (c.jalr) return 4'd6;                                    // JALR
    if (c.muldiv) return c.funct3[2] ? 4'd8 : 4'd7;             // DIV / MUL
    if (c.fp_op) return 4'd9;                                   // FP
    if (c.csr) return 4'd13;                                    // CSR
    if (c.mret || c.sret || c.wfi || c.sfence || c.hfence) return 4'd15;  // SYSTEM
    if (opcode == 7'b0001111) return 4'd14;                     // FENCE / FENCE.I
    return 4'd0;                                                // ALU
  endfunction
  /* verilator lint_on UNUSEDSIGNAL */

  // Bubble causes (perf_ev_e PE_STK_* indices; all < 32).
  logic [4:0] perf_ftag, perf_rtag, perf_xtag, perf_stk;
  always_comb begin
    if (!u_core.mmu_if_ok)                           perf_ftag = 5'(PE_STK_FETCH_ITLB);
    else if (u_core.fencei_block)                    perf_ftag = 5'(PE_STK_SERIAL);
    else if (perf_ic_miss_q || u_icache.perf_miss)   perf_ftag = 5'(PE_STK_FETCH_MISS);
    else if (perf_ic_unc_q)                          perf_ftag = 5'(PE_STK_FETCH_UNC);
    else                                             perf_ftag = 5'(PE_STK_FETCH_LAT);
    if (u_core.idex_ctrl_q.branch)                   perf_rtag = 5'(PE_STK_BRANCH);
    else if (u_core.idex_ctrl_q.jal)                 perf_rtag = 5'(PE_STK_JAL);
    else if (u_core.idex_ctrl_q.jalr)                perf_rtag = 5'(PE_STK_JALR);
    else                                             perf_rtag = 5'(PE_STK_SERIAL);
    if (u_core.vec_ex_stall)                         perf_xtag = 5'(PE_STK_VEC);
    else if (u_core.muldiv_req && !u_core.muldiv_done) perf_xtag = 5'(PE_STK_MULDIV);
    else                                             perf_xtag = 5'(PE_STK_FPU);
  end

  // Shadow of the pipeline's slot contents: a bubble cause for empty
  // slots, the class and RVC flag for instructions. Updated with
  // exactly the core's IF/ID, ID/EX, EX/MEM, MEM/WB enables.
  logic [4:0] perf_t_ifid_q, perf_t_idex_q, perf_t_exmem_q, perf_t_memwb_q;
  logic [3:0] perf_c_idex_q, perf_c_exmem_q, perf_c_memwb_q;
  logic       perf_r_idex_q, perf_r_exmem_q, perf_r_memwb_q;
  logic       perf_if_has_instr;
  assign perf_if_has_instr = !u_core.fetch_stall && !u_core.straddle_enter;
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      perf_t_ifid_q <= 5'(PE_STK_OTHER);
      perf_t_idex_q <= 5'(PE_STK_OTHER);
      perf_t_exmem_q <= 5'(PE_STK_OTHER);
      perf_t_memwb_q <= 5'(PE_STK_OTHER);
      perf_c_idex_q <= 4'd0;
      perf_c_exmem_q <= 4'd0;
      perf_c_memwb_q <= 4'd0;
      perf_r_idex_q <= 1'b0;
      perf_r_exmem_q <= 1'b0;
      perf_r_memwb_q <= 1'b0;
    end else if (u_core.trap_take) begin
      perf_t_ifid_q <= 5'(PE_STK_TRAP);
      perf_t_idex_q <= 5'(PE_STK_TRAP);
      perf_t_exmem_q <= 5'(PE_STK_TRAP);
      perf_t_memwb_q <= 5'(PE_STK_TRAP);
    end else if (perf_upd) begin
      perf_t_memwb_q <= perf_t_exmem_q;
      perf_c_memwb_q <= perf_c_exmem_q;
      perf_r_memwb_q <= perf_r_exmem_q;
      perf_t_exmem_q <= u_core.ex_hold ? perf_xtag : perf_t_idex_q;
      perf_c_exmem_q <= perf_c_idex_q;
      perf_r_exmem_q <= perf_r_idex_q;
      if (!u_core.ex_hold) begin
        if (u_core.stall) begin
          perf_t_idex_q <= 5'(PE_STK_LOADUSE);
        end else if (u_core.flush) begin
          perf_t_idex_q <= u_core.ifid_valid_q ? perf_rtag : perf_t_ifid_q;
        end else if (u_core.irq_inject) begin
          perf_t_idex_q <= 5'(PE_STK_TRAP);
        end else begin
          perf_t_idex_q <= perf_t_ifid_q;
          perf_c_idex_q <= perf_class(u_core.id_ctrl, u_core.ifid_instr_q[6:0]);
          perf_r_idex_q <= u_core.ifid_rvc_q;
        end
      end
      if (u_core.flush) begin
        perf_t_ifid_q <= perf_if_has_instr ? perf_rtag :
                         u_core.fetch_stall ? perf_ftag : 5'(PE_STK_FETCH_STRADDLE);
      end else if (!u_core.stall && !u_core.fetch_stall && !u_core.ex_hold) begin
        perf_t_ifid_q <= u_core.straddle_enter ? 5'(PE_STK_FETCH_STRADDLE)
                                               : 5'(PE_STK_OTHER);
      end else if (u_core.fetch_stall && !u_core.stall && !u_core.ex_hold) begin
        perf_t_ifid_q <= perf_ftag;
      end
    end
  end

  // This cycle's accounting slot.
  always_comb begin
    if (u_core.trap_fire) begin
      perf_stk = 5'(PE_STK_TRAP);
    end else if (u_core.mem_stall) begin
      if (u_core.data_access && !u_core.mmu_d_ok && !u_core.mmu_d_fault)
        perf_stk = 5'(PE_STK_DTLB);
      else if (u_core.vls_is)
        perf_stk = 5'(PE_STK_VLS);
      else if (u_core.mem_fencei)
        perf_stk = 5'(PE_STK_DC_CLEAN);
      else if (perf_dc_unc_q)
        perf_stk = 5'(PE_STK_IO);
      else if (perf_dc_miss_q || u_dcache.perf_miss)
        perf_stk = 5'(PE_STK_DC_MISS);
      else
        perf_stk = 5'(PE_STK_DC_LAT);
    end else if (u_core.freeze) begin
      perf_stk = 5'(PE_STK_OTHER);
    end else if (u_core.memwb_valid_q) begin
      perf_stk = 5'(PE_STK_RETIRE);
    end else begin
      perf_stk = perf_t_memwb_q;
    end
  end

  logic perf_retire, perf_flush_upd, perf_bus_first;
  assign perf_retire = u_core.memwb_valid_q && !u_core.memwb_exc_q &&
                       !u_core.mem_stall;
  assign perf_flush_upd = u_core.flush && perf_upd;
  assign perf_bus_first = !u_arb.busy_q && bus_req_valid_o && bus_req_ready_i;
  always_comb begin
    perf_inc = '0;
    perf_inc[int'(perf_stk)] = 1'b1;
    perf_inc[PE_CYCLES] = 1'b1;
    perf_inc[PE_INSTRET] = perf_retire;
    if (perf_retire) begin
      perf_inc[int'(PE_RET_ALU) + int'(perf_c_memwb_q)] = 1'b1;
      perf_inc[PE_RET_RVC] = perf_r_memwb_q;
    end
    perf_inc[PE_BR_TAKEN] = perf_flush_upd && u_core.idex_ctrl_q.branch;
    perf_inc[PE_JAL_REDIR] = perf_flush_upd && u_core.idex_ctrl_q.jal;
    perf_inc[PE_JALR_REDIR] = perf_flush_upd && u_core.idex_ctrl_q.jalr;
    perf_inc[PE_XRET_FLUSH] = perf_flush_upd && u_core.ex_ret;
    perf_inc[PE_FENCEI_FLUSH] = perf_flush_upd && u_core.ex_fencei;
    perf_inc[PE_SFENCE_FLUSH] = perf_flush_upd &&
        (u_core.idex_ctrl_q.sfence || u_core.idex_ctrl_q.hfence);
    perf_inc[PE_SQUASH_ID] = perf_flush_upd && u_core.ifid_valid_q;
    perf_inc[PE_SQUASH_IF] = perf_flush_upd && perf_if_has_instr;
    perf_inc[PE_TRAP_EXC] = u_core.trap_take && !u_core.memwb_cause_q[63];
    perf_inc[PE_TRAP_IRQ] = u_core.trap_take && u_core.memwb_cause_q[63];
    perf_inc[PE_LOADUSE_CYC] = perf_upd && u_core.stall && !u_core.ex_hold;
    perf_inc[PE_MULDIV_BUSY] = u_core.muldiv_req && !u_core.muldiv_done;
    perf_inc[PE_FPU_BUSY] = u_core.fpu_req && !u_core.fpu_done;
    perf_inc[PE_VEC_BUSY] = u_core.vec_busy;
    perf_inc[PE_VEC_EX_STALL] = u_core.vec_ex_stall;
    perf_inc[PE_VLS_CYC] = u_core.vls_is;
    perf_inc[PE_FETCH_STALL_CYC] = u_core.fetch_stall;
    perf_inc[PE_ITLB_CYC] = !u_core.mmu_if_ok && !u_core.mmu_if_fault;
    perf_inc[PE_DTLB_CYC] = u_core.data_access && !u_core.mmu_d_ok &&
                            !u_core.mmu_d_fault;
    perf_inc[PE_MEM_STALL_CYC] = u_core.mem_stall;
    perf_inc[PE_IC_ACCESS] = perf_ic_acc;
    perf_inc[PE_IC_MISS] = u_icache.perf_miss;
    perf_inc[PE_IC_UNC] = perf_ic_acc && !perf_ic_cacheable;
    perf_inc[PE_IC_MISS_CYC] = perf_ic_miss_q || u_icache.perf_miss;
    perf_inc[PE_DC_LOAD] = perf_dc_acc && (dreq_op == DOP_LOAD);
    perf_inc[PE_DC_STORE] = perf_dc_acc && (dreq_op == DOP_STORE);
    perf_inc[PE_DC_CLEAN] = perf_dc_acc && (dreq_op == DOP_CLEAN);
    perf_inc[PE_DC_MISS] = u_dcache.perf_miss;
    perf_inc[PE_DC_UNC] = perf_dc_acc && (dreq_op != DOP_CLEAN) &&
                          !perf_dc_cacheable;
    perf_inc[PE_DC_MISS_CYC] = perf_dc_miss_q || u_dcache.perf_miss;
    perf_inc[PE_DC_UNC_CYC] = perf_dc_unc_q;
    perf_inc[PE_BUS_IFILL] = perf_bus_first && bus_req_inst_o && (bus_req_len_o != 8'd0);
    perf_inc[PE_BUS_IUNC] = perf_bus_first && bus_req_inst_o && (bus_req_len_o == 8'd0);
    perf_inc[PE_BUS_DFILL] = perf_bus_first && !bus_req_inst_o && !bus_req_write_o &&
                             (bus_req_len_o != 8'd0);
    perf_inc[PE_BUS_DWB] = perf_bus_first && !bus_req_inst_o && bus_req_write_o &&
                           (bus_req_len_o != 8'd0);
    perf_inc[PE_BUS_DUNC] = perf_bus_first && !bus_req_inst_o && (bus_req_len_o == 8'd0);
    perf_inc[PE_BUS_BUSY_CYC] = u_arb.busy_q || bus_req_valid_o;
    perf_inc[PE_BUS_REQ_WAIT] = bus_req_valid_o && !bus_req_ready_i;
    perf_inc[PE_BUS_RSP_WAIT] = u_arb.busy_q && !bus_req_valid_o && !bus_rsp_valid_i;
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      perf_ic_miss_q <= 1'b0;
      perf_ic_unc_q <= 1'b0;
      perf_dc_miss_q <= 1'b0;
      perf_dc_unc_q <= 1'b0;
      perf_on_q <= 1'b0;
      perf_region_q <= 8'd0;
      perf_seq_q <= 32'd0;
      perf_mc_b_q <= 64'd0;
      perf_mi_b_q <= 64'd0;
    end else begin
      if (irsp_valid) begin
        perf_ic_miss_q <= 1'b0;
        perf_ic_unc_q <= 1'b0;
      end else begin
        if (u_icache.perf_miss) perf_ic_miss_q <= 1'b1;
        if (perf_ic_acc && !perf_ic_cacheable) perf_ic_unc_q <= 1'b1;
      end
      if (drsp_valid) begin
        perf_dc_miss_q <= 1'b0;
        perf_dc_unc_q <= 1'b0;
      end else begin
        if (u_dcache.perf_miss) perf_dc_miss_q <= 1'b1;
        if (perf_dc_acc && (dreq_op != DOP_CLEAN) && !perf_dc_cacheable)
          perf_dc_unc_q <= 1'b1;
      end
      if (perf_begin) begin
        perf_on_q <= 1'b1;
        perf_region_q <= perf_mark_region;
        perf_mc_b_q <= u_core.u_csr.mcycle_q;
        perf_mi_b_q <= u_core.u_csr.minstret_q;
      end else if (perf_end) begin
        perf_on_q <= 1'b0;
        if (perf_on_q) perf_seq_q <= perf_seq_q + 32'd1;
      end
    end
  end
  // One process per counter (Verilator 5.020 has no non-blocking
  // writes to unpacked-array elements inside a loop).
  for (genvar g = 0; g < PerfN; g++) begin : g_perf_cnt
    always_ff @(posedge clk_i or negedge rst_ni) begin
      if (!rst_ni)           perf_cnt_q[g] <= 64'd0;
      else if (perf_begin)   perf_cnt_q[g] <= 64'(perf_inc[g]);
      else if (perf_active)  perf_cnt_q[g] <= perf_cnt_q[g] + 64'(perf_inc[g]);
    end
  end

  // Record output (+sigil_perf=<file>, else stderr).
  int    perf_fd;
  string perf_path;
  initial begin
    perf_fd = 32'h8000_0002;  // STDERR
    if ($value$plusargs("sigil_perf=%s", perf_path)) begin
      perf_fd = $fopen(perf_path, "a");
      if (perf_fd == 0) $fatal(1, "sigil_perf: cannot open %s", perf_path);
    end
  end
  // (perf_end is low in reset: no instruction is in EX.)
  always @(posedge clk_i) begin
    if (perf_end) begin
      if (!perf_on_q) begin
        $fwrite(perf_fd, "SIGIL_PERF warning: end marker (region %0d) without begin\n",
                perf_mark_region);
      end else begin
        logic [63:0] stk_sum, mc_d, mi_d;
        perf_ev_e ev;
        string nm;
        stk_sum = 64'd0;
        for (int i = 0; i < PerfStkN; i++) stk_sum += perf_cnt_q[i];
        mc_d = u_core.u_csr.mcycle_q - perf_mc_b_q;
        mi_d = u_core.u_csr.minstret_q - perf_mi_b_q;
        $fwrite(perf_fd, "SIGIL_PERF v1 region=%0d seq=%0d", perf_region_q, perf_seq_q);
        if (perf_mark_region != perf_region_q)
          $fwrite(perf_fd, " end_region=%0d", perf_mark_region);
        for (int i = 0; i < PerfN; i++) begin
          ev = perf_ev_e'(i);
          nm = ev.name();
          nm = nm.substr(3, nm.len() - 1);  // drop "PE_"
          nm = nm.tolower();
          $fwrite(perf_fd, " %s=%0d", nm, perf_cnt_q[i]);
        end
        $fwrite(perf_fd, " mcycle_begin=%0d mcycle_delta=%0d minstret_delta=%0d",
                perf_mc_b_q, mc_d, mi_d);
        $fwrite(perf_fd, " cfg_sram_oreg=%0d cfg_vrf_oreg=%0d cfg_ic=%0dx%0dx%0d",
                SRAM_OREG, VRF_OREG, IC_SETS, IC_WAYS, LINE_BYTES);
        $fwrite(perf_fd, " cfg_dc=%0dx%0dx%0d cfg_cache_en=%0d stk_sum=%0d\n",
                DC_SETS, DC_WAYS, LINE_BYTES, cache_en_i, stk_sum);
        $fflush(perf_fd);
        // Internal consistency (a failure is a counter bug).
        if (stk_sum != perf_cnt_q[PE_CYCLES])
          $error("sigil_perf: accounting slots %0d != cycles %0d", stk_sum,
                 perf_cnt_q[PE_CYCLES]);
        if (perf_cnt_q[PE_STK_RETIRE] != perf_cnt_q[PE_INSTRET])
          $error("sigil_perf: retire slots %0d != instret %0d",
                 perf_cnt_q[PE_STK_RETIRE], perf_cnt_q[PE_INSTRET]);
      end
    end
  end
/* verilator coverage_on */
