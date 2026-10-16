// In-house RV64 core (issue #18). Five-stage in-order pipeline
// (IF/ID/EX/MEM/WB) with M/S/U privilege, precise traps,
// interrupts, PMP, and an Sv39+Svnapot MMU, over two
// latency-tolerant request/response memory ports (instruction
// fetch and data) that the L1 caches serve (muserisc_cpu.sv);
// see docs/CORE.md for the contract and staging plan.
//
// Pipeline policy:
// - Full forwarding to EX (EX/MEM and MEM/WB) plus a WB->ID
//   bypass so an instruction reading a register in the cycle its
//   producer is in WB latches the new value.
// - One bubble on load-use (consumer in ID against a load in EX).
// - All control transfers resolve in EX (predict not-taken):
//   taken branches, jumps, xRET, SFENCE and FENCE.I flush
//   IF/ID + ID/EX.
// - CSR writes commit on the EX->MEM edge; CSR reads in EX see
//   all older writes. Privilege changes only via trap entry
//   (WB) and xRET (EX), both of which flush, so priv_o always
//   names the privilege of every instruction in flight.
// - Exceptions travel with their instruction to WB; the
//   trapping instruction and everything younger perform no
//   register, memory, or CSR write. At WB the trap is taken
//   (redirect to the handler) unless trap_halt_i requests the
//   stage-1/2 freeze-and-report behavior for directed TBs.
// - Interrupts are injected in ID as an exception on the next
//   unexecuted instruction, making epc precise by construction.
// - Virtual memory: fetch translates combinationally (TLB hit)
//   or stalls IF while the walker runs; a data miss stalls the
//   whole pipeline with the access parked in MEM. PMP is always
//   checked on physical addresses (port C covers PTE accesses).
// - Memory ports (L1 stage): each port has at most one request
//   in flight and every accepted request gets exactly one
//   response, at the earliest the next cycle. IF holds the PC
//   until its fetch word arrives (a flush or trap marks an
//   outstanding fetch stale and its response is dropped). MEM
//   holds the whole pipeline (mem_stall) until its access
//   responds; a MEM access is only issued when no older
//   instruction is trapping, so it is never abandoned. The
//   page-table walker shares the data port (MEM first); AMOs
//   are a read then a write with the port held in between.
`default_nettype none
module muserisc_core import muserisc_pkg::*, muserisc_cache_pkg::*; (
    input  wire        clk_i,
    input  wire        rst_ni,
    input  wire [63:0] boot_pc_i,     // reset PC (0 for directed TBs)
    // Instruction fetch port: PA of an aligned 32-bit word.
    output logic       ireq_valid_o,
    input  wire        ireq_ready_i,
    output wire [63:0] ireq_addr_o,
    input  wire        irsp_valid_i,
    input  wire [31:0] irsp_rdata_i,
    output wire        icache_inval_o,  // FENCE.I: invalidate I$
    // Data port (op: muserisc_cache_pkg DOP_LOAD/STORE/CLEAN).
    // LOAD returns the aligned 64-bit word; be names the
    // accessed lanes for loads and stores alike.
    output logic       dreq_valid_o,
    input  wire        dreq_ready_i,
    output logic [63:0] dreq_addr_o,
    output logic [1:0] dreq_op_o,
    output logic [63:0] dreq_wdata_o,
    output logic [7:0] dreq_be_o,
    input  wire        drsp_valid_i,
    input  wire [63:0] drsp_rdata_i,
    // Trap observability: pulses the cycle a trap is taken.
    output wire        trap_o,
    output wire [63:0] trap_cause_o,
    output wire [63:0] trap_pc_o,
    // 1 = freeze on first trap (directed-TB mode), 0 = take trap.
    input  wire        trap_halt_i,
    // Interrupt lines (CLINT/PLIC equivalents in a future SoC).
    input  wire        irq_m_timer_i,
    input  wire        irq_m_soft_i,
    input  wire        irq_m_ext_i,
    input  wire        irq_s_timer_i,
    input  wire        irq_s_ext_i
);

  // ------------------------------------------------------------
  // CSR / privileged state (declared first: ID/EX read it)
  // ------------------------------------------------------------
  logic [1:0]  priv;
  // The core consumes mstatus.MPRV/MPP today; satp feeds the MMU.
  /* verilator lint_off UNUSEDSIGNAL */
  logic [63:0] csr_mstatus, csr_satp, csr_hgatp;
  logic [63:0] csr_fsatp, csr_vsatp;
  logic        virt, dvirt, csr_virt_inst, csr_sum, csr_mxr, csr_hs_mxr;
  logic        csr_spvp, csr_vs_sum, csr_vs_mxr;
  /* verilator lint_on UNUSEDSIGNAL */
  logic [1:0]  eff_priv_data;  // MPRV-adjusted privilege for data
  assign eff_priv_data = (priv == 2'b11 && csr_mstatus[17])
                             ? csr_mstatus[12:11] : priv;

  logic [11:0] csr_addr;
  logic [63:0] csr_rdata, csr_wdata, csr_src;
  logic        csr_illegal, csr_we;
  logic        sys_illegal;
  logic [2:0]  sys_op;
  logic [63:0] xret_pc;
  logic        irq_valid;
  logic [63:0] irq_cause;
  logic        trap_fire, trap_take;
  logic [63:0] trap_target;
  logic [1:0]  trap_priv_unused;
  logic        pmp_allow_fetch, pmp_allow_data, pmp_allow_walk;

  // MMU (instantiated after MEM; signals declared here for IF)
  logic [63:0] mmu_if_pa, mmu_d_pa;
  logic        mmu_if_ok, mmu_if_fault, mmu_if_fault_page;
  logic        mmu_d_ok, mmu_d_fault, mmu_d_fault_page;
  logic        mmu_if_fault_guest, mmu_d_fault_guest;
  logic [63:0] mmu_if_fault_gpa, mmu_d_fault_gpa;
  logic        walk_req, walk_we, walk_grant;
  logic [63:0] walk_addr, walk_wdata;
  logic [1:0]  walk_acc;
  logic        mem_stall;     // MEM waiting (translation or port): hold all regs
  logic        mem_port_done; // MEM's data-port access completes this cycle
  logic        fpu_req, fpu_done;
  logic        muldiv_req, muldiv_done;
  // M unit mode: multi-cycle (default) or, with
  // +define+MUSERISC_MULDIV_COMB, the legacy single-cycle unit
  // behind the same handshake (done in the issue cycle).
`ifdef MUSERISC_MULDIV_COMB
  localparam int unsigned MuldivComb = 1;
`else
  localparam int unsigned MuldivComb = 0;
`endif
  logic        ex_mc_busy;    // a multi-cycle EX unit is still working
  logic        ex_hold;       // EX holds (multi-cycle unit / vector WB)
  logic        ex_advance;    // EX contents move to EX/MEM this cycle
  logic        sfence_fire;   // SFENCE.VMA commits this cycle
  // Forward declarations for signals driven in later
  // stages but read in EX/ID gating (slang synthesis
  // requires declaration before use; Verilator did not).
  logic        vec_ex_stall, vec_fflags_we, mem_exc;
  logic [63:0] load_shifted;

  // ------------------------------------------------------------
  // IF stage
  // ------------------------------------------------------------
  logic [63:0] pc_q, pc_d;
  logic        stall;
  logic        flush;
  logic [63:0] redirect_pc;
  logic        freeze;
  logic        fetch_fault, fetch_stall;
  logic [63:0] fetch_cause;

  // Fetch realignment for 16-bit parcels (stage 5 C):
  // the MMU translates one aligned 32-bit fetch word at a
  // time. A 32-bit instruction starting in the upper half
  // latches its low parcel (straddle_q) and completes from
  // the next aligned word next cycle; that second fetch is
  // translated (and may fault) independently, with tval
  // naming the second half's address.
  logic        straddle_q;
  logic [15:0] straddle_lo_q;
  logic [63:0] fetch_va;
  assign fetch_va = straddle_q ? (pc_q + 64'd2)
                               : {pc_q[63:2], 2'b00};
  assign ireq_addr_o = mmu_if_pa;
  // Physical addresses are 56 bits: an untranslated (M-mode /
  // Bare) address at or above 2^56 access-faults. Translated
  // PAs from the MMU are 56-bit by construction. Gated on
  // mmu_if_ok: while a walk is in flight if_pa_o still carries
  // the raw VA, which may be a high canonical address.
  logic fetch_pa_illegal;
  assign fetch_pa_illegal = mmu_if_ok && |mmu_if_pa[63:56];
  // IALIGN=16 (C extension): only translation and PMP faults
  // remain at fetch.
  assign fetch_fault = mmu_if_fault || fetch_pa_illegal ||
                       (mmu_if_ok && !pmp_allow_fetch);
  assign fetch_cause = mmu_if_fault ?
      (mmu_if_fault_guest ? 64'd20 :
       mmu_if_fault_page ? 64'd12 : 64'd1) : 64'd1;
  // Fetch-port state. ifw_q buffers the word for the current
  // fetch_va when it arrives while IF cannot consume it; it is
  // dropped whenever IF consumes or is redirected. ifq_drop_q
  // marks the outstanding request stale (redirected past it).
  logic        ifw_valid_q, ifq_pend_q, ifq_drop_q;
  logic [31:0] ifw_q;
  logic        fetch_word_ok, fencei_block;
  logic [31:0] fetch_word;
  assign fetch_word_ok = ifw_valid_q ||
                         (irsp_valid_i && ifq_pend_q && !ifq_drop_q);
  assign fetch_word = ifw_valid_q ? ifw_q : irsp_rdata_i;
  // A translation miss, or a translated (non-faulting) fetch
  // whose word has not arrived yet.
  assign fetch_stall = !fetch_fault && !(mmu_if_ok && fetch_word_ok);
  assign ireq_valid_o = mmu_if_ok && !fetch_fault && !ifw_valid_q &&
                        !ifq_pend_q && !fencei_block;

  // Parcel assembly and decompression.
  logic [15:0] parcel16;
  logic        parcel_long, rvc_illegal, straddle_enter;
  logic [31:0] fetch_instr, rvc_expanded;
  logic        fetch_rvc;
  logic [63:0] fetch_tval;
  assign parcel16 = pc_q[1] ? fetch_word[31:16]
                            : fetch_word[15:0];
  assign parcel_long = (parcel16[1:0] == 2'b11);
  assign straddle_enter = !straddle_q && parcel_long && pc_q[1] &&
                          !fetch_fault && !fetch_stall;
  muserisc_rvc u_rvc (
      .in_i      (parcel16),
      .out_o     (rvc_expanded),
      .illegal_o (rvc_illegal)
  );
  always_comb begin
    if (straddle_q) begin
      fetch_instr = {fetch_word[15:0], straddle_lo_q};
      fetch_rvc = 1'b0;
    end else if (!parcel_long) begin
      fetch_instr = rvc_illegal ? 32'b0 : rvc_expanded;
      fetch_rvc = 1'b1;
    end else begin
      fetch_instr = fetch_word;
      fetch_rvc = 1'b0;
    end
  end
  assign fetch_tval = straddle_q ? (pc_q + 64'd2) : pc_q;

  // IF/ID register
  logic        ifid_valid_q;
  logic [63:0] ifid_pc_q;
  logic [31:0] ifid_instr_q;
  logic        ifid_exc_q;      // fetch fault (access or page)
  logic [63:0] ifid_cause_q;
  logic        ifid_rvc_q;      // instruction was a 16-bit parcel
  logic [15:0] ifid_parcel_q;   // raw parcel (illegal tval)
  logic [63:0] ifid_tval_q;     // fetch-fault address
  logic [63:0] ifid_gpa_q;      // faulting GPA (guest faults)

  // ------------------------------------------------------------
  // ID stage
  // ------------------------------------------------------------
  muserisc_pkg::ctrl_t id_ctrl;
  logic [63:0] id_imm;
  logic [4:0]  id_rs1, id_rs2, id_rd;
  logic [63:0] rf_rs1, rf_rs2;
  logic [63:0] id_rs1_val, id_rs2_val;
  logic        id_exc;
  logic [63:0] id_cause, id_tval, id_gpa;
  logic        irq_inject;

  muserisc_decoder u_decoder (
      .instr_i (ifid_instr_q),
      .ctrl_o  (id_ctrl),
      .imm_o   (id_imm),
      .rs1_o   (id_rs1),
      .rs2_o   (id_rs2),
      .rd_o    (id_rd)
  );

  always_comb begin
    id_gpa = 64'd0;
    if (ifid_exc_q) begin
      id_exc = ifid_valid_q;
      id_cause = ifid_cause_q;          // 1 access / 12 page / 20 guest
      id_tval = ifid_tval_q;
      id_gpa = ifid_gpa_q;
    end else if (id_ctrl.ecall) begin
      id_exc = ifid_valid_q;
      id_cause = (priv == 2'b11) ? 64'd11 :
                 (priv == 2'b01) ? (virt ? 64'd10 : 64'd9) : 64'd8;
      id_tval = 64'd0;
    end else if (id_ctrl.ebreak) begin
      id_exc = ifid_valid_q;
      id_cause = CAUSE_BREAKPOINT;
      id_tval = ifid_pc_q;
    end else if (!id_ctrl.valid) begin
      id_exc = ifid_valid_q;
      id_cause = CAUSE_ILLEGAL_INSTR;
      id_tval = ifid_rvc_q ? {48'd0, ifid_parcel_q}
                           : {32'd0, ifid_instr_q};
    end else begin
      id_exc = 1'b0;
      id_cause = 64'd0;
      id_tval = 64'd0;
    end
  end

  assign irq_inject = irq_valid && ifid_valid_q && !stall && !flush &&
                      !freeze && !mem_stall && !ex_hold;

  // Which sources the ID instruction reads (load-use interlock).
  logic [6:0] id_opcode;
  logic       id_uses_rs1, id_uses_rs2;
  assign id_opcode = ifid_instr_q[6:0];
  assign id_uses_rs1 = (id_opcode != 7'b0110111) &&
                       (id_opcode != 7'b0010111) &&
                       (id_opcode != 7'b1101111);
  assign id_uses_rs2 = (id_opcode == 7'b0110011) ||
                       (id_opcode == 7'b0111011) ||
                       (id_opcode == 7'b0100011) ||
                       (id_opcode == 7'b1100011) ||
                       (id_opcode == 7'b0101111) ||  // AMO/SC source
                       (id_ctrl.hlv && id_ctrl.mem_write) ||  // HSV data
                       (id_ctrl.vec &&
                        (id_ctrl.bext_op == VLS_STRIDED)) ||  // stride
                       (id_ctrl.vset && (id_ctrl.fpu_aux == 2'd2));  // vsetvl vtype
                       // (LR's rs2 field is x0; the rd!=0 guard covers it)

  // ID/EX register
  logic        idex_valid_q;
  logic [63:0] idex_pc_q;
  muserisc_pkg::ctrl_t idex_ctrl_q;
  logic [63:0] idex_imm_q;
  logic [31:0] idex_instr_q;  // for illegal-instruction tval in EX
  logic [63:0] idex_rs1_q, idex_rs2_q;
  logic [63:0] idex_frs1_q, idex_frs2_q, idex_frs3_q;
  logic [4:0]  idex_rs1_addr_q, idex_rs2_addr_q, idex_rd_q;
  logic [4:0]  idex_rs3_addr_q;
  logic        idex_exc_q;
  logic [63:0] idex_cause_q, idex_tval_q, idex_gpa_q;
  logic        idex_rvc_q;

  // FP sources of the ID instruction (from the decoder ctrl).
  logic [4:0] id_rs3;
  assign id_rs3 = ifid_instr_q[31:27];
  assign stall = idex_valid_q && idex_ctrl_q.mem_read &&
                 !idex_exc_q && ifid_valid_q && !ifid_exc_q &&
                 ((!idex_ctrl_q.fp_rd && (idex_rd_q != 5'd0) &&
                   ((id_uses_rs1 && (idex_rd_q == id_rs1)) ||
                    (id_uses_rs2 && (idex_rd_q == id_rs2)))) ||
                  (idex_ctrl_q.fp_rd &&
                   ((id_ctrl.fp_rs1 && (idex_rd_q == id_rs1)) ||
                    (id_ctrl.fp_rs2 && (idex_rd_q == id_rs2)) ||
                    (id_ctrl.fp_op && id_ctrl.fpu_op >= 5'd12 &&
                     id_ctrl.fpu_op <= 5'd15 &&
                     (idex_rd_q == id_rs3)))));

  // ------------------------------------------------------------
  // EX stage
  // ------------------------------------------------------------
  logic [63:0] ex_rs1, ex_rs2;
  logic [63:0] alu_a, alu_b, alu_result, muldiv_result;
  logic [63:0] ex_result;
  logic        branch_taken;
  logic        ex_misalign, ex_illegal;
  logic        ex_exc, ex_gva;
  logic [63:0] ex_cause, ex_tval, ex_gpa;
  logic        ex_ret, ex_serialize;

  // EX/MEM register
  logic        exmem_valid_q;
  logic [63:0] exmem_pc_q;
  /* verilator lint_off UNUSEDSIGNAL */
  muserisc_pkg::ctrl_t exmem_ctrl_q;
  /* verilator lint_on UNUSEDSIGNAL */
  logic [63:0] exmem_result_q;
  logic [63:0] exmem_addr_q;
  logic [63:0] exmem_store_data_q;
  logic          exmem_vm_q;        // vector mask-enable bit
  logic [4:0]    exmem_vs2_q;       // index group register (indexed LS)
  logic [63:0]   exmem_vec_stride_q; // stride scalar (strided LS)
  logic [2:0]    exmem_vec_nf_q;    // nf field (whole-register LS)
  logic [4:0]  exmem_rd_q;
  logic        exmem_exc_q, exmem_gva_q;
  logic [63:0] exmem_cause_q, exmem_tval_q, exmem_gpa_q;

  // MEM/WB register
  logic        memwb_valid_q;
  logic [63:0] memwb_pc_q;
  logic [63:0] memwb_result_q;
  logic [4:0]  memwb_rd_q;
  logic        memwb_reg_write_q;
  logic        memwb_fp_write_q;
  logic        memwb_exc_q, memwb_gva_q;
  logic [63:0] memwb_cause_q, memwb_tval_q, memwb_gpa_q;

  logic        wb_write;
  // A vector arithmetic op holds EX (front stages frozen,
  // bubbles into EX/MEM) from the cycle it reaches EX until
  // the element-serial vector unit reports done; see the
  // vector datapath section below (vec_ex_stall is
  // forward-declared at the top of the module).
  assign wb_write = memwb_valid_q && memwb_reg_write_q && !memwb_exc_q;
  logic        wb_fp_write;
  assign wb_fp_write = memwb_valid_q && memwb_fp_write_q &&
                       !memwb_exc_q;
  assign trap_fire = memwb_valid_q && memwb_exc_q;
  assign trap_take = trap_fire && !trap_halt_i;
  assign freeze = trap_fire && trap_halt_i;
  assign trap_o = trap_fire;
  assign trap_cause_o = memwb_cause_q;
  assign trap_pc_o = memwb_pc_q;

  muserisc_regfile u_regfile (
      .clk_i     (clk_i),
      .we_i      (wb_write && !freeze),
      .waddr_i   (memwb_rd_q),
      .wdata_i   (memwb_result_q),
      .raddr_a_i (id_rs1),
      .rdata_a_o (rf_rs1),
      .raddr_b_i (id_rs2),
      .rdata_b_o (rf_rs2)
  );

  logic [63:0] frf_rs1, frf_rs2, frf_rs3;
  logic [63:0] id_frs1_val, id_frs2_val, id_frs3_val;
  muserisc_fpregfile u_fpregfile (
      .clk_i     (clk_i),
      .we_i      (wb_fp_write && !freeze),
      .waddr_i   (memwb_rd_q),
      .wdata_i   (memwb_result_q),
      .raddr1_i  (id_rs1),
      .raddr2_i  (id_rs2),
      .raddr3_i  (id_rs3),
      .rdata1_o  (frf_rs1),
      .rdata2_o  (frf_rs2),
      .rdata3_o  (frf_rs3)
  );
  assign id_frs1_val = (wb_fp_write && (memwb_rd_q == id_rs1))
                       ? memwb_result_q : frf_rs1;
  assign id_frs2_val = (wb_fp_write && (memwb_rd_q == id_rs2))
                       ? memwb_result_q : frf_rs2;
  assign id_frs3_val = (wb_fp_write && (memwb_rd_q == id_rs3))
                       ? memwb_result_q : frf_rs3;

  logic [63:0] ex_frs1, ex_frs2, ex_frs3;
  always_comb begin
    if (exmem_valid_q && exmem_ctrl_q.fp_rd &&
        !exmem_ctrl_q.mem_read && !exmem_exc_q &&
        (exmem_rd_q == idex_rs1_addr_q))
      ex_frs1 = exmem_result_q;
    else if (wb_fp_write && (memwb_rd_q == idex_rs1_addr_q))
      ex_frs1 = memwb_result_q;
    else
      ex_frs1 = idex_frs1_q;
    if (exmem_valid_q && exmem_ctrl_q.fp_rd &&
        !exmem_ctrl_q.mem_read && !exmem_exc_q &&
        (exmem_rd_q == idex_rs2_addr_q))
      ex_frs2 = exmem_result_q;
    else if (wb_fp_write && (memwb_rd_q == idex_rs2_addr_q))
      ex_frs2 = memwb_result_q;
    else
      ex_frs2 = idex_frs2_q;
    if (exmem_valid_q && exmem_ctrl_q.fp_rd &&
        !exmem_ctrl_q.mem_read && !exmem_exc_q &&
        (exmem_rd_q == idex_rs3_addr_q))
      ex_frs3 = exmem_result_q;
    else if (wb_fp_write && (memwb_rd_q == idex_rs3_addr_q))
      ex_frs3 = memwb_result_q;
    else
      ex_frs3 = idex_frs3_q;
  end

  assign id_rs1_val = (wb_write && (memwb_rd_q != 5'd0) &&
                       (memwb_rd_q == id_rs1)) ? memwb_result_q : rf_rs1;
  assign id_rs2_val = (wb_write && (memwb_rd_q != 5'd0) &&
                       (memwb_rd_q == id_rs2)) ? memwb_result_q : rf_rs2;

  always_comb begin
    if (exmem_valid_q && exmem_ctrl_q.reg_write && !exmem_ctrl_q.mem_read &&
        !exmem_exc_q && (exmem_rd_q != 5'd0) &&
        (exmem_rd_q == idex_rs1_addr_q)) begin
      ex_rs1 = exmem_result_q;
    end else if (wb_write && (memwb_rd_q != 5'd0) &&
                 (memwb_rd_q == idex_rs1_addr_q)) begin
      ex_rs1 = memwb_result_q;
    end else begin
      ex_rs1 = idex_rs1_q;
    end
    if (exmem_valid_q && exmem_ctrl_q.reg_write && !exmem_ctrl_q.mem_read &&
        !exmem_exc_q && (exmem_rd_q != 5'd0) &&
        (exmem_rd_q == idex_rs2_addr_q)) begin
      ex_rs2 = exmem_result_q;
    end else if (wb_write && (memwb_rd_q != 5'd0) &&
                 (memwb_rd_q == idex_rs2_addr_q)) begin
      ex_rs2 = memwb_result_q;
    end else begin
      ex_rs2 = idex_rs2_q;
    end
  end

  assign alu_a = idex_ctrl_q.alu_a_pc ? idex_pc_q : ex_rs1;
  assign alu_b = idex_ctrl_q.alu_src_imm ? idex_imm_q : ex_rs2;

  muserisc_alu u_alu (
      .op_i      (idex_ctrl_q.alu_op),
      .word_op_i (idex_ctrl_q.word_op),
      .a_i       (alu_a),
      .b_i       (alu_b),
      .result_o  (alu_result)
  );

  logic [2:0]  csr_frm;
  logic [1:0]  csr_fs;
  logic [63:0] fpu_result;
  logic [4:0]  fpu_flags;
  logic [2:0]  fpu_rm;
  assign fpu_rm = (idex_ctrl_q.funct3 == 3'b111) ? csr_frm
                                                 : idex_ctrl_q.funct3;
  // ---- EX-stage multi-cycle units (generic handshake) ----
  // A unit with req && !done holds EX (ex_mc_busy): IF/ID/EX
  // keep their contents, a bubble enters EX/MEM, and older
  // instructions in MEM/WB drain normally. The result is
  // consumed (ack) on the cycle EX advances; a trap squashes
  // the unit (kill). See docs/CORE.md "EX-stage multi-cycle
  // units". A new unit adds its req && !done term to
  // ex_mc_busy and uses the same ack/kill.
  assign fpu_req = idex_valid_q && idex_ctrl_q.fp_op && !idex_exc_q &&
                   !ex_illegal;
  // M unit (muserisc_muldiv_mc): MUL* 3 EX cycles, DIV*/REM*
  // 2 (x/0, overflow) or 3..35 (operand-dependent).
  assign muldiv_req = idex_valid_q && idex_ctrl_q.muldiv && !idex_exc_q &&
                      !ex_illegal;
  assign ex_mc_busy = (fpu_req && !fpu_done) ||
                      (muldiv_req && !muldiv_done);
  // EX holds for a busy multi-cycle unit or the vector unit.
  // The vector unit keeps its own start/ack handshake. It and
  // a scalar FP op only ever serve the instruction in EX
  // (vector and FP-scalar decodes are disjoint), so the FPU is
  // free for the vector unit's FP sub-steps while it is busy
  // (asserted in simulation after vec_commit).
  assign ex_hold = vec_ex_stall || ex_mc_busy;
  // EX contents move to EX/MEM this cycle.
  assign ex_advance = !trap_take && !freeze && !mem_stall && !ex_hold;

  // The vector unit runs its FP element sub-steps on this FPU
  // (vfpu_*): while the unit is busy the FPU serves only it
  // (no scalar FP op can be in EX then), and the vector unit
  // takes each result the cycle it completes.
  logic        vfpu_req, vfpu_fmt_d;
  logic [4:0]  vfpu_op;
  logic [2:0]  vfpu_rm;
  logic [63:0] vfpu_a, vfpu_b, vfpu_c;
  logic [1:0]  vfpu_aux;
  logic        vec_busy;
  muserisc_fpu u_fpu (
      .clk_i     (clk_i),
      .rst_ni    (rst_ni),
      .req_i     (vec_busy ? vfpu_req : fpu_req),
      .ack_i     (vec_busy || ex_advance),
      .kill_i    (trap_take),
      .done_o    (fpu_done),
      .op_i      (vec_busy ? vfpu_op : idex_ctrl_q.fpu_op),
      .fmt_d_i   (vec_busy ? vfpu_fmt_d : idex_ctrl_q.fmt_d),
      .rm_i      (vec_busy ? vfpu_rm : fpu_rm),
      .a_i       (vec_busy ? vfpu_a :
                  (idex_ctrl_q.fp_rs1 ? ex_frs1 : ex_rs1)),
      .b_i       (vec_busy ? vfpu_b : ex_frs2),
      .c_i       (vec_busy ? vfpu_c : ex_frs3),
      .aux_i     (vec_busy ? vfpu_aux : idex_ctrl_q.fpu_aux),
      .result_o  (fpu_result),
      .flags_o   (fpu_flags)
  );
  // FP instructions need FS != Off; dynamic rounding mode must
  // name a real mode (static bad rms are illegal at decode).
  logic fp_illegal;
  assign fp_illegal = (idex_ctrl_q.fp && (csr_fs == 2'b00)) ||
                      (idex_ctrl_q.fp_rm &&
                       (idex_ctrl_q.funct3 == 3'b111) &&
                       (csr_frm > 3'd4));
  logic csr_fflags_we, fp_dirty_ex, fp_dirty_mem, fp_dirty;
  // !mem_exc on every EX-committed side effect: an older
  // instruction already carrying an exception in MEM must take
  // its trap before this instruction writes architectural state
  // (OpenSBI's mtvec restore right after a trapping CSR probe
  // otherwise beats the in-flight trap to the vector).
  // fpu_done: flags commit once, on the cycle the FP op leaves EX.
  assign csr_fflags_we = idex_valid_q && idex_ctrl_q.fp_op &&
                         !idex_exc_q && !ex_illegal && !trap_fire &&
                         !mem_exc && !mem_stall && fpu_done;
  assign fp_dirty_ex = (csr_fflags_we && idex_ctrl_q.fp_rd) ||
                       vec_fflags_we;
  assign fp_dirty_mem = exmem_valid_q && exmem_ctrl_q.fp_rd &&
                        exmem_ctrl_q.mem_read && !exmem_exc_q &&
                        !mem_exc && !mem_stall;
  assign fp_dirty = fp_dirty_ex || fp_dirty_mem;

  // Vector datapath: arithmetic/permutation/mask ops run in
  // the element-serial vector unit (muserisc_vec) while the
  // instruction holds EX. The unit starts only once every
  // older instruction is known not to trap (the same !mem_exc
  // / !mem_stall / !trap_fire gating as CSR writes) and no
  // vector load/store is in MEM, so its element-by-element
  // VRF writes are precise; front stages freeze and EX/MEM
  // takes bubbles until done, then the op leaves EX and its
  // CSR side effects (vxsat, fflags, vstart := 0, VS dirty)
  // commit in that cycle. Interrupts wait for the op to end
  // (they are injected in ID, which is frozen meanwhile).
  logic [1:0]    csr_vec_vs;
  /* verilator lint_off UNUSEDSIGNAL */  // vtype[62:8] read zero
  logic [63:0]   csr_vtype;
  /* verilator lint_on UNUSEDSIGNAL */
  logic [63:0]   csr_vl, csr_vstart, csr_vset_vl;
  logic [63:0]   vec_scalar;
  logic          vec_illegal, vec_align_bad;
  logic [2:0]    vec_wlmul;
  logic [63:0]   vset_avl, vset_vtype_raw, vec_vlmax;
  logic [1:0]    csr_vxrm;
  logic          vset_en, vec_sat;
  logic [4:0]    vec_fflags;
  logic          vec_unit_op, vec_done, vec_start, vec_commit;
  logic          vls_is;  // MEM holds a vector load/store
  // EX holds an instruction the vector unit executes.
  assign vec_unit_op = idex_valid_q && idex_ctrl_q.vec &&
                       !idex_ctrl_q.vset &&
                       !idex_ctrl_q.mem_read && !idex_ctrl_q.mem_write &&
                       !idex_exc_q && !vec_illegal;
  assign vec_start = vec_unit_op && !vec_busy && !trap_fire &&
                     !mem_exc && !mem_stall && !vls_is;
  // A CSR access or vset in EX is held for as long as a
  // vector load/store occupies MEM (the whole pipeline is
  // frozen by mem_stall until its last cycle anyway; this
  // adds that last cycle), so it observes the vstart/vl
  // updates that commit on the load/store's final edge.
  assign vec_ex_stall = (vec_unit_op && !vec_done) ||
                        (idex_valid_q && !idex_exc_q && vls_is &&
                         (idex_ctrl_q.csr || idex_ctrl_q.vset));
  assign vec_commit = vec_unit_op && vec_done && !trap_fire &&
                      !mem_exc && !mem_stall;
`ifndef SYNTHESIS
  // The FPU, the M unit and the vector unit are never in
  // flight together: each serves only the instruction in EX
  // (fp_op, muldiv and vec decodes are disjoint) and returns to
  // idle when that instruction leaves EX or is killed.
  logic vec_busy_q;
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) vec_busy_q <= 1'b0;
    else         vec_busy_q <= vec_busy;
  end
  // Checks are armed by the first reset edge: before reset the
  // state is arbitrary (e.g. under +verilator+rand+reset+2).
  logic chk_armed;
  initial chk_armed = 1'b0;
  always @(posedge clk_i or negedge rst_ni) if (!rst_ni) chk_armed <= 1'b1;
  always_ff @(posedge clk_i) if (chk_armed) begin
    if (vec_busy && fpu_req)
      $error("muserisc_core: FPU request while the vector unit is busy");
    if (fpu_req && vec_unit_op)
      $error("muserisc_core: FP and vector op in EX together");
    if (vec_busy && muldiv_req)
      $error("muserisc_core: M-unit request while the vector unit is busy");
    if (muldiv_req && (vec_unit_op || fpu_req))
      $error("muserisc_core: M-unit op in EX together with an FP/vector op");
    // Unit state (hierarchical, simulation only): a non-idle
    // unit means an operation is in flight or its result held.
    // The vector unit drives the FPU only while busy.
    if ((u_fpu.state_q != u_fpu.S_IDLE) && muldiv_req)
      $error("muserisc_core: FPU in flight with the M unit");
    if (vfpu_req && !vec_busy)
      $error("muserisc_core: vector FPU request while the unit is idle");
    // The FPU is shared: a vector op starts only on an idle FPU,
    // the vector unit always takes its results (never HOLD), and
    // hands the FPU back idle when it finishes.
    if (vec_start && (u_fpu.state_q != u_fpu.S_IDLE))
      $error("muserisc_core: vector op starts with the FPU busy");
    if (vec_busy && (u_fpu.state_q == u_fpu.S_HOLD))
      $error("muserisc_core: FPU parked in HOLD while the vector unit is busy");
    if (vec_busy_q && !vec_busy && (u_fpu.state_q != u_fpu.S_IDLE))
      $error("muserisc_core: vector unit finished with the FPU not idle");
  end
  // The multi-cycle M unit's state exists only with COMB = 0 (the
  // legacy single-cycle mode has none). S_IDLE is encoding 0 (the
  // enum item itself is not referenced: Verilator 5.020 fails on a
  // hierarchical enum-item reference inside a generate block).
  if (MuldivComb == 0) begin : g_md_inflight_chk
    always_ff @(posedge clk_i) begin
      if (chk_armed && (|u_muldiv.g_mc.state_q) &&
          (fpu_req || vec_busy || (u_fpu.state_q != u_fpu.S_IDLE)))
        $error("muserisc_core: M unit in flight with the FPU/vector unit");
    end
  end
`endif
  // FP vector ops accrue fflags and dirty FS on commit.
  assign vec_fflags_we = vec_commit &&
      (idex_ctrl_q.bext_op >= VOP_FBIN) &&
      (idex_ctrl_q.bext_op <= VOP_FMVFS);
  // VLMAX for the execution unit (same formula as the CSR
  // vset logic): group bits / SEW.
  always_comb begin
    logic [63:0] group_bits;
    unique case (csr_vtype[2:0])
      3'd1: group_bits = 64'd1024;
      3'd2: group_bits = 64'd2048;
      3'd3: group_bits = 64'd4096;
      3'd5: group_bits = 64'd64;
      3'd6: group_bits = 64'd128;
      3'd7: group_bits = 64'd256;
      default: group_bits = 64'd512;
    endcase
    vec_vlmax = group_bits >> (csr_vtype[5:3] + 3'd3);
  end
  // Per-class group geometry for legality and write width.
  // vmv.s.x / vmv.x.s / vcpop / vfirst touch one register or
  // a scalar, so group rules do not apply; vmv<nr>r.v copies
  // whole registers independent of vtype (legal even with
  // vill set) and is handled by its own alignment rule.
  logic ex_is_wide, ex_is_narrow, ex_is_mask_dest;
  logic signed [3:0] ex_lmul_log2, ex_vd_log2, ex_vs2_log2, ex_vs1_log2;
  assign ex_is_wide =
      ((idex_ctrl_q.bext_op >= VOP_WADD) &&
       (idex_ctrl_q.bext_op <= VOP_WMACCUS)) ||
      (idex_ctrl_q.bext_op == VOP_FBINW) ||
      (idex_ctrl_q.bext_op == VOP_FMACCW) ||
      ((idex_ctrl_q.bext_op == VOP_FCVT) &&
       (idex_imm_q[4:0] >= 5'd8) && (idex_imm_q[4:0] < 5'd16));
  assign ex_is_narrow =
      ((idex_ctrl_q.bext_op >= VOP_NSRL) &&
       (idex_ctrl_q.bext_op <= VOP_NCLIPU)) ||
      ((idex_ctrl_q.bext_op == VOP_FCVT) &&
       (idex_imm_q[4:0] >= 5'd16));
  assign ex_is_mask_dest = (idex_ctrl_q.bext_op == VOP_MADC) ||
      (idex_ctrl_q.bext_op == VOP_MSBC) ||
      ((idex_ctrl_q.bext_op >= VOP_CMPEQ) &&
       (idex_ctrl_q.bext_op <= VOP_CMPGT)) ||
      (idex_ctrl_q.bext_op == VOP_MLOG) ||
      (idex_ctrl_q.bext_op == VOP_MSBIT) ||
      (idex_ctrl_q.bext_op == VOP_FCMP);
  always_comb begin
    logic signed [3:0] mvr_log2;
    unique case (csr_vtype[2:0])
      3'd5: ex_lmul_log2 = -4'sd3;
      3'd6: ex_lmul_log2 = -4'sd2;
      3'd7: ex_lmul_log2 = -4'sd1;
      default: ex_lmul_log2 = 4'(signed'({1'b0, csr_vtype[2:0]}));
    endcase
    mvr_log2 = (idex_instr_q[19:15] == 5'd1) ? 4'sd1 :
               (idex_instr_q[19:15] == 5'd3) ? 4'sd2 :
               (idex_instr_q[19:15] == 5'd7) ? 4'sd3 : 4'sd0;
    if (idex_ctrl_q.bext_op == VOP_MVR) begin
      ex_vd_log2 = mvr_log2;
      ex_vs2_log2 = mvr_log2;
    end else if (ex_is_wide) begin
      ex_vd_log2 = ex_lmul_log2 + 4'sd1;
      ex_vs2_log2 = ((idex_ctrl_q.bext_op == VOP_WADDW) ||
                     (idex_ctrl_q.bext_op == VOP_WADDUW) ||
                     (idex_ctrl_q.bext_op == VOP_WSUBW) ||
                     (idex_ctrl_q.bext_op == VOP_WSUBUW) ||
                     ((idex_ctrl_q.bext_op == VOP_FBINW) &&
                      idex_imm_q[7]))
                    ? (ex_lmul_log2 + 4'sd1) : ex_lmul_log2;
    end else if (ex_is_narrow) begin
      ex_vd_log2 = ex_lmul_log2;
      ex_vs2_log2 = ex_lmul_log2 + 4'sd1;
    end else if (ex_is_mask_dest ||
                 (idex_ctrl_q.bext_op == VOP_RED) ||
                 (idex_ctrl_q.bext_op == VOP_WRED) ||
                 (idex_ctrl_q.bext_op == VOP_FRED) ||
                 (idex_ctrl_q.bext_op == VOP_FWRED)) begin
      ex_vd_log2 = -4'sd3;  // single register: no constraint
      // Mask-register sources (logicals, vmsbf family) are
      // single registers; data sources use the full group.
      ex_vs2_log2 = ((idex_ctrl_q.bext_op == VOP_MLOG) ||
                     (idex_ctrl_q.bext_op == VOP_MSBIT))
                    ? -4'sd3 : ex_lmul_log2;
    end else if (idex_ctrl_q.bext_op == VOP_EXT) begin
      ex_vd_log2 = ex_lmul_log2;
      // imm[2:1]: 01=/8, 10=/4, 11=/2
      ex_vs2_log2 = ex_lmul_log2 -
                    (4'sd4 - 4'(signed'({2'b00, idex_imm_q[2:1]})));
    end else begin
      ex_vd_log2 = ex_lmul_log2;
      ex_vs2_log2 = ex_lmul_log2;
    end
    ex_vs1_log2 = (idex_ctrl_q.bext_op == VOP_GATHEREI16)
        ? (ex_lmul_log2 + 4'sd1 -
           4'(signed'({1'b0, csr_vtype[5:3]})))
        : ex_lmul_log2;
  end
  function automatic logic align_bad(
      input logic [4:0] regno, input logic signed [3:0] log2n);
    logic [4:0] mask;
    mask = (log2n == 4'sd1) ? 5'b00001 :
           (log2n == 4'sd2) ? 5'b00011 :
           (log2n >= 4'sd3) ? 5'b00111 : 5'b00000;
    align_bad = |(regno & mask);
  endfunction
  assign vec_align_bad =
      (idex_ctrl_q.bext_op != VOP_MVSX) &&
      (idex_ctrl_q.bext_op != VOP_MVXS) &&
      (idex_ctrl_q.bext_op != VOP_FMVFS) &&
      (idex_ctrl_q.bext_op != VOP_CPOP) &&
      (idex_ctrl_q.bext_op != VOP_FIRST) &&
      !(idex_ctrl_q.mem_read || idex_ctrl_q.mem_write) &&
      (align_bad(idex_rd_q, ex_vd_log2) ||
       // vs2/vs1 group fields (vs1 only in VV form; the vs2
       // slot holds a stride/index group for LS, excluded)
       align_bad(idex_instr_q[24:20], ex_vs2_log2) ||
       ((idex_ctrl_q.fpu_aux == VFORM_VV) &&
        (idex_ctrl_q.bext_op != VOP_RED) &&
        (idex_ctrl_q.bext_op != VOP_WRED) &&
        (idex_ctrl_q.bext_op != VOP_FRED) &&
        (idex_ctrl_q.bext_op != VOP_FWRED) &&
        (idex_ctrl_q.bext_op != VOP_EXT) &&
        (idex_ctrl_q.bext_op != VOP_MSBIT) &&
        (idex_ctrl_q.bext_op != VOP_MLOG) &&
        (idex_ctrl_q.bext_op != VOP_COMPRESS) &&
        (idex_ctrl_q.bext_op != VOP_IOTA) &&
        // FCVT/FUNARY carry a sub-op in the vs1 field, not
        // a register group.
        (idex_ctrl_q.bext_op != VOP_FCVT) &&
        (idex_ctrl_q.bext_op != VOP_FUNARY) &&
        (idex_ctrl_q.bext_op != VOP_ID) &&
        (idex_ctrl_q.bext_op != VOP_MVR) &&
        align_bad(idex_instr_q[19:15], ex_vs1_log2)) ||
       // Masked destination may not overlap the v0 register,
       // except mask-register destinations (compares and
       // friends), which may write v0 under its own mask.
       (idex_ctrl_q.vec_rd && !idex_instr_q[25] &&
        !ex_is_mask_dest &&
        // Reductions write a single element and may target
        // v0 under a mask.
        (idex_ctrl_q.bext_op != VOP_RED) &&
        (idex_ctrl_q.bext_op != VOP_WRED) &&
        (idex_ctrl_q.bext_op != VOP_FRED) &&
        (idex_ctrl_q.bext_op != VOP_FWRED) &&
        (idex_ctrl_q.bext_op != VOP_ADC) &&
        (idex_ctrl_q.bext_op != VOP_SBC) &&
        (idex_ctrl_q.bext_op != VOP_MERGE) &&
        (idex_ctrl_q.bext_op != VOP_MADC) &&
        (idex_ctrl_q.bext_op != VOP_MSBC) &&
        (idex_rd_q < (5'd1 << ((ex_vd_log2 < 0) ? 3'd0
                                                : ex_vd_log2[2:0])))));
  // Widening needs SEW < ELEN and LMUL < 8; narrowing needs
  // 2*LMUL <= 8; extends need SEW >= 8*ratio.
  logic ex_vec_bad;
  assign ex_vec_bad =
      (ex_is_wide && ((csr_vtype[5:3] == 3'd3) ||
                      (ex_lmul_log2 == 4'sd3))) ||
      // Widening reductions: 2*SEW dest, any LMUL.
      (((idex_ctrl_q.bext_op == VOP_WRED) ||
        (idex_ctrl_q.bext_op == VOP_FWRED)) &&
       (csr_vtype[5:3] == 3'd3)) ||
      (ex_is_narrow && ((csr_vtype[5:3] == 3'd3) ||
                        (ex_lmul_log2 == 4'sd3))) ||
      ((idex_ctrl_q.bext_op == VOP_EXT) &&
       (4'(signed'({1'b0, csr_vtype[5:3]})) <
        (4'sd4 - 4'(signed'({2'b00, idex_imm_q[2:1]})))));
  // FP vector legality (stage 9): FS must be enabled, SEW
  // must name a supported FP width (32/64; no Zfh), and
  // rounding forms need a legal dynamic frm. FPU op codes
  // ride in imm[4:0]: ADD/SUB/MUL/DIV are 0..3.
  logic ex_fp_vec, ex_fp_rounds, ex_fp_bad;
  assign ex_fp_vec =
      ((idex_ctrl_q.bext_op >= VOP_FBIN) &&
       (idex_ctrl_q.bext_op <= VOP_FMVFS)) ||
      (idex_ctrl_q.vec && idex_ctrl_q.fp_rs1 &&
       !idex_ctrl_q.mem_read && !idex_ctrl_q.mem_write);
  assign ex_fp_rounds =
      (((idex_ctrl_q.bext_op == VOP_FBIN) ||
        (idex_ctrl_q.bext_op == VOP_FBINW)) &&
       (idex_imm_q[4:0] <= 5'd3)) ||
      (idex_ctrl_q.bext_op == VOP_FMACC) ||
      (idex_ctrl_q.bext_op == VOP_FMACCW) ||
      ((idex_ctrl_q.bext_op == VOP_FUNARY) &&
       (idex_imm_q[1:0] != 2'd1)) ||
      (((idex_ctrl_q.bext_op == VOP_FRED) ||
        (idex_ctrl_q.bext_op == VOP_FWRED)) &&
       (idex_imm_q[1:0] < 2'd2)) ||
      ((idex_ctrl_q.bext_op == VOP_FCVT) &&
       (idex_imm_q[2:0] < 3'd6));
  assign ex_fp_bad = ex_fp_vec &&
      ((csr_fs == 2'b00) || (csr_vtype[5:3] < 3'd2) ||
       (ex_fp_rounds && (csr_frm > 3'd4)));
  // vmv<nr>r.v register count (log2) for the vector unit.
  assign vec_wlmul = (idex_instr_q[19:15] == 5'd1) ? 3'd1 :
                     (idex_instr_q[19:15] == 5'd3) ? 3'd2 :
                     (idex_instr_q[19:15] == 5'd7) ? 3'd3 : 3'd0;
  // Vector LS legality in EX, by class (bext_op = VLS_*):
  // data EMUL in [1/8, 8] with group alignment; masked loads
  // may not overwrite v0. For indexed forms funct3 is the
  // index EEW and the data EEW is SEW; whole-register forms
  // align to the register count and must be unmasked.
  logic [2:0] ex_eew_code;
  logic signed [3:0] ex_emul_log2, ex_idx_emul_log2;
  logic ex_vls_bad;
  assign ex_eew_code = (idex_ctrl_q.funct3 == 3'b000) ? 3'd0 :
                       (idex_ctrl_q.funct3 == 3'b101) ? 3'd1 :
                       (idex_ctrl_q.funct3 == 3'b110) ? 3'd2 : 3'd3;
  always_comb begin
    ex_emul_log2 = (idex_ctrl_q.bext_op == VLS_INDEXED)
        ? ex_lmul_log2
        : (4'(signed'({1'b0, ex_eew_code})) -
           4'(signed'({1'b0, csr_vtype[5:3]})) + ex_lmul_log2);
    ex_idx_emul_log2 = 4'(signed'({1'b0, ex_eew_code})) -
                       4'(signed'({1'b0, csr_vtype[5:3]})) +
                       ex_lmul_log2;
  end
  always_comb begin
    logic signed [3:0] whole_log2;
    whole_log2 = (idex_instr_q[31:29] == 3'd1) ? 4'sd1 :
                 (idex_instr_q[31:29] == 3'd3) ? 4'sd2 :
                 (idex_instr_q[31:29] == 3'd7) ? 4'sd3 : 4'sd0;
    if (idex_ctrl_q.bext_op == VLS_MASK) begin
      ex_vls_bad = !idex_instr_q[25];  // vlm/vsm are unmasked-only
    end else if (idex_ctrl_q.bext_op == VLS_WHOLE) begin
      ex_vls_bad = !idex_instr_q[25] ||
                   align_bad(idex_rd_q, whole_log2);
    end else begin
      ex_vls_bad = (ex_emul_log2 > 4'sd3) ||
          (ex_emul_log2 < -4'sd3) ||
          // Segment span NFIELDS*EMUL must not exceed 8 regs.
          ((idex_instr_q[31:29] != 3'd0) &&
           (({1'b0, idex_instr_q[31:29]} + 4'd1) <<
            ((ex_emul_log2 < 0) ? 3'd0 : ex_emul_log2[2:0])) > 5'd8) ||
          align_bad(idex_rd_q, ex_emul_log2) ||
          ((idex_ctrl_q.bext_op == VLS_INDEXED) &&
           ((ex_idx_emul_log2 > 4'sd3) ||
            (ex_idx_emul_log2 < -4'sd3) ||
            align_bad(idex_instr_q[24:20], ex_idx_emul_log2))) ||
          (idex_ctrl_q.mem_read && !idex_instr_q[25] &&
           (idex_rd_q < (5'd1 << ((ex_emul_log2 < 0) ? 3'd0
                                                     : ex_emul_log2[2:0]))));
    end
  end
  assign vec_illegal = idex_ctrl_q.vec &&
      ((csr_vec_vs == 2'b00) ||
       // vmv<nr>r.v and whole-register transfers are legal
       // even with vill set.
       (!idex_ctrl_q.vset && csr_vtype[63] &&
        (idex_ctrl_q.bext_op != VOP_MVR) &&
        (idex_ctrl_q.bext_op != VLS_WHOLE)) ||
       (!idex_ctrl_q.vset && vec_align_bad) ||
       (!idex_ctrl_q.vset && ex_vec_bad) ||
       (!idex_ctrl_q.vset && ex_fp_bad) ||
       ((idex_ctrl_q.mem_read || idex_ctrl_q.mem_write) && ex_vls_bad));
  assign vset_avl = (idex_ctrl_q.fpu_aux == 2'd1)
      ? {59'd0, idex_instr_q[19:15]} : ex_rs1;
  assign vset_vtype_raw = (idex_ctrl_q.fpu_aux == 2'd0)
      ? {53'd0, idex_instr_q[30:20]} :
      (idex_ctrl_q.fpu_aux == 2'd1)
      ? {54'd0, idex_instr_q[29:20]} : ex_rs2;
  assign vset_en = idex_valid_q && idex_ctrl_q.vset && !idex_exc_q &&
                   !vec_illegal && !trap_fire && !mem_exc && !mem_stall &&
                   !vec_ex_stall;

  // Banked VRF: three synchronous-read word ports and one
  // byte-masked write port, owned by the MEM vector LS
  // sequencer while a vector load/store is in MEM and by the
  // vector unit otherwise (the unit never runs then).
  logic          vrf_re_a, vrf_re_b, vrf_re_c, vrf_we;
  logic [7:0]    vrf_ra_a, vrf_ra_b, vrf_ra_c, vrf_wa, vrf_wbe;
  logic [63:0]   vrf_rd_a, vrf_rd_b, vrf_rd_c, vrf_wd;
  logic [511:0]  vec_v0;
  logic          vu_re_a, vu_re_b, vu_re_c, vu_we;
  logic [7:0]    vu_ra_a, vu_ra_b, vu_ra_c, vu_wa, vu_wbe;
  logic [63:0]   vu_wd;
  logic          vls_re_a, vls_re_c, vls_vrf_we;
  logic [7:0]    vls_ra_a, vls_ra_c, vls_vrf_wa, vls_vrf_wbe;
  logic [63:0]   vls_vrf_wd;
  assign vrf_re_a = vls_is ? vls_re_a : vu_re_a;
  assign vrf_ra_a = vls_is ? vls_ra_a : vu_ra_a;
  assign vrf_re_b = vls_is ? 1'b0 : vu_re_b;
  assign vrf_ra_b = vu_ra_b;
  assign vrf_re_c = vls_is ? vls_re_c : vu_re_c;
  assign vrf_ra_c = vls_is ? vls_ra_c : vu_ra_c;
  assign vrf_we = vls_is ? vls_vrf_we : vu_we;
  assign vrf_wa = vls_is ? vls_vrf_wa : vu_wa;
  assign vrf_wbe = vls_is ? vls_vrf_wbe : vu_wbe;
  assign vrf_wd = vls_is ? vls_vrf_wd : vu_wd;

  muserisc_vregfile u_vregfile (
      .clk_i     (clk_i),
      .re_a_i    (vrf_re_a),
      .raddr_a_i (vrf_ra_a),
      .rdata_a_o (vrf_rd_a),
      .re_b_i    (vrf_re_b),
      .raddr_b_i (vrf_ra_b),
      .rdata_b_o (vrf_rd_b),
      .re_c_i    (vrf_re_c),
      .raddr_c_i (vrf_ra_c),
      .rdata_c_o (vrf_rd_c),
      .v0_o      (vec_v0),
      .we_i      (vrf_we),
      .waddr_i   (vrf_wa),
      .wbe_i     (vrf_wbe),
      .wdata_i   (vrf_wd)
  );

  muserisc_vec u_vec (
      .clk_i     (clk_i),
      .rst_ni    (rst_ni),
      .kill_i    (trap_take),
      .start_i   (vec_start),
      .ack_i     (!freeze && !mem_stall),
      .op_i      (idex_ctrl_q.bext_op),
      .form_i    (idex_ctrl_q.fpu_aux),
      .sew_i     (csr_vtype[5:3]),
      .vl_i      (csr_vl),
      .vstart_i  (csr_vstart),
      .vlmax_i   (vec_vlmax),
      .vta_i     (csr_vtype[6]),
      .vma_i     (csr_vtype[7]),
      .vm_i      (idex_instr_q[25]),
      .vs2_i     (idex_instr_q[24:20]),
      .vs1_i     (idex_instr_q[19:15]),
      .vd_i      (idex_rd_q),
      .nreg_i    (4'd1 << vec_wlmul),
      // FP vector .vf forms read the scalar from the FP
      // register file; integer .vx forms use the GPR value.
      .scalar_i  (idex_ctrl_q.fp_rs1 ? ex_frs1 : ex_rs1),
      .imm_i     (idex_imm_q),
      .vxrm_i    (csr_vxrm),
      .frm_i     (csr_frm),
      .re_a_o    (vu_re_a),
      .raddr_a_o (vu_ra_a),
      .rdata_a_i (vrf_rd_a),
      .re_b_o    (vu_re_b),
      .raddr_b_o (vu_ra_b),
      .rdata_b_i (vrf_rd_b),
      .re_c_o    (vu_re_c),
      .raddr_c_o (vu_ra_c),
      .rdata_c_i (vrf_rd_c),
      .v0_i      (vec_v0),
      .we_o      (vu_we),
      .waddr_o   (vu_wa),
      .wbe_o     (vu_wbe),
      .wdata_o   (vu_wd),
      .busy_o    (vec_busy),
      .done_o    (vec_done),
      .scalar_o  (vec_scalar),
      .sat_o     (vec_sat),
      .fflags_o  (vec_fflags),
      .fpu_req_o    (vfpu_req),
      .fpu_op_o     (vfpu_op),
      .fpu_fmt_d_o  (vfpu_fmt_d),
      .fpu_rm_o     (vfpu_rm),
      .fpu_a_o      (vfpu_a),
      .fpu_b_o      (vfpu_b),
      .fpu_c_o      (vfpu_c),
      .fpu_aux_o    (vfpu_aux),
      .fpu_done_i   (fpu_done),
      .fpu_result_i (fpu_result),
      .fpu_flags_i  (fpu_flags)
  );

  logic [63:0] bext_result;
  muserisc_bext u_bext (
      .op_i      (idex_ctrl_q.bext_op[5:0]),
      .a_i       (ex_rs1),
      .b_i       (idex_ctrl_q.alu_src_imm ? idex_imm_q : ex_rs2),
      .result_o  (bext_result)
  );

  // Multi-cycle M unit on the generic EX handshake (see
  // ex_mc_busy above); operands are sampled when it accepts.
  muserisc_muldiv_mc #(.COMB(MuldivComb)) u_muldiv (
      .clk_i     (clk_i),
      .rst_ni    (rst_ni),
      .req_i     (muldiv_req),
      .ack_i     (ex_advance),
      .kill_i    (trap_take),
      .funct3_i  (idex_ctrl_q.funct3),
      .word_op_i (idex_ctrl_q.word_op),
      .a_i       (ex_rs1),
      .b_i       (ex_rs2),
      .done_o    (muldiv_done),
      .result_o  (muldiv_result)
  );

  // CSR execution in EX.
  assign csr_addr = idex_imm_q[11:0];
  assign csr_src = idex_ctrl_q.csr_imm ? {59'd0, idex_rs1_addr_q} : ex_rs1;
  always_comb begin
    unique case (idex_ctrl_q.funct3[1:0])
      2'b01:   csr_wdata = csr_src;                       // CSRRW(I)
      2'b10:   csr_wdata = csr_rdata | csr_src;           // CSRRS(I)
      default: csr_wdata = csr_rdata & ~csr_src;          // CSRRC(I)
    endcase
  end
  // !mem_stall: a CSR write must not commit while an older
  // instruction is parked in MEM (it could still page-fault).
  assign csr_we = idex_valid_q && idex_ctrl_q.csr && !idex_exc_q &&
                  !trap_fire && !mem_exc && !mem_stall && !vec_ex_stall &&
                  ((idex_ctrl_q.funct3[1:0] == 2'b01) ||
                   (idex_rs1_addr_q != 5'd0));
  assign sfence_fire = idex_valid_q &&
                       (idex_ctrl_q.sfence || idex_ctrl_q.hfence) &&
                       !idex_exc_q && !sys_illegal && !mem_stall;
  assign sys_op = idex_ctrl_q.mret   ? 3'd1 :
                  idex_ctrl_q.sret   ? 3'd2 :
                  idex_ctrl_q.wfi    ? 3'd3 :
                  idex_ctrl_q.sfence ? 3'd4 :
                  idex_ctrl_q.hfence ? (idex_ctrl_q.hfence_gvma ? 3'd6 : 3'd5) :
                  idex_ctrl_q.hlv    ? 3'd7 : 3'd0;
  assign ex_ret = idex_valid_q && (idex_ctrl_q.mret || idex_ctrl_q.sret) &&
                  !idex_exc_q && !sys_illegal;
  // FENCE.I (MISC-MEM funct3=001; decodes as a NOP) serializes
  // like SFENCE: younger instructions are refetched after it
  // has cleaned the D$ and invalidated the I$ in MEM.
  logic ex_fencei;
  assign ex_fencei = idex_valid_q && !idex_exc_q && !idex_rvc_q &&
                     (idex_instr_q[6:0] == 7'b0001111) &&
                     (idex_instr_q[14:12] == 3'b001);
  // SFENCE/HFENCE, FENCE.I and xRET serialize: redirect and flush.
  assign ex_serialize = ex_ret || ex_fencei ||
                        (idex_valid_q &&
                         (idex_ctrl_q.sfence || idex_ctrl_q.hfence) &&
                         !idex_exc_q && !sys_illegal);
  assign ex_illegal = (idex_ctrl_q.csr ? csr_illegal :
                      ((idex_ctrl_q.mret || idex_ctrl_q.sret ||
                        idex_ctrl_q.wfi || idex_ctrl_q.sfence ||
                        idex_ctrl_q.hfence || idex_ctrl_q.hlv) && sys_illegal)) ||
                      fp_illegal || vec_illegal;

  always_comb begin
    if (idex_ctrl_q.jal || idex_ctrl_q.jalr) ex_result = idex_pc_q + (idex_rvc_q ? 64'd2 : 64'd4);
    else if (idex_ctrl_q.vset)               ex_result = csr_vset_vl;
    else if (idex_ctrl_q.vec)                ex_result = vec_scalar;
    else if (idex_ctrl_q.csr)                ex_result = csr_rdata;
    else if (idex_ctrl_q.muldiv)             ex_result = muldiv_result;
    else if (idex_ctrl_q.fp_op)              ex_result = fpu_result;
    else if (idex_ctrl_q.bext)               ex_result = bext_result;
    else                                     ex_result = alu_result;
  end

  always_comb begin
    unique case (idex_ctrl_q.funct3)
      3'b000:  branch_taken = (ex_rs1 == ex_rs2);
      3'b001:  branch_taken = (ex_rs1 != ex_rs2);
      3'b100:  branch_taken = ($signed(ex_rs1) < $signed(ex_rs2));
      3'b101:  branch_taken = ($signed(ex_rs1) >= $signed(ex_rs2));
      3'b110:  branch_taken = (ex_rs1 < ex_rs2);
      3'b111:  branch_taken = (ex_rs1 >= ex_rs2);
      default: branch_taken = 1'b0;
    endcase
  end

  // With IALIGN=16 a control target is misaligned only if
  // bit 0 is set, which no encodable target can be (branch
  // and JAL immediates are even, JALR clears bit 0); the
  // check is retained in that form for completeness.
  logic jump_misalign;
  assign jump_misalign = idex_valid_q && !idex_exc_q && !ex_illegal &&
      (idex_ctrl_q.jal || idex_ctrl_q.jalr ||
       (idex_ctrl_q.branch && branch_taken)) && redirect_pc[0];

  assign flush = idex_valid_q && !idex_exc_q && !ex_illegal &&
                 !jump_misalign &&
                 (idex_ctrl_q.jal || idex_ctrl_q.jalr ||
                  (idex_ctrl_q.branch && branch_taken) || ex_serialize);
  always_comb begin
    if (ex_ret)                  redirect_pc = xret_pc;
    else if (idex_ctrl_q.sfence || idex_ctrl_q.hfence || ex_fencei)
                                 redirect_pc = idex_pc_q + (idex_rvc_q ? 64'd2 : 64'd4);
    else if (idex_ctrl_q.jalr)   redirect_pc = (ex_rs1 + idex_imm_q) & ~64'd1;
    else                         redirect_pc = idex_pc_q + idex_imm_q;
  end

  always_comb begin
    ex_misalign = 1'b0;
    // Vector LS alignment is checked per element in MEM
    // (masked-off and vl=0 forms access nothing).
    if ((idex_ctrl_q.mem_read || idex_ctrl_q.mem_write) &&
        !idex_ctrl_q.vec) begin
      unique case (idex_ctrl_q.funct3[1:0])
        2'b01:   ex_misalign = alu_result[0];
        2'b10:   ex_misalign = |alu_result[1:0];
        2'b11:   ex_misalign = |alu_result[2:0];
        default: ex_misalign = 1'b0;
      endcase
    end
  end

  always_comb begin
    ex_gpa = idex_gpa_q;
    ex_gva = 1'b0;
    if (idex_exc_q) begin
      ex_exc = idex_valid_q;
      ex_cause = idex_cause_q;
      ex_tval = idex_tval_q;
    end else if (ex_illegal) begin
      ex_gpa = 64'd0;
      ex_exc = idex_valid_q;
      ex_cause = csr_virt_inst ? 64'd22 : CAUSE_ILLEGAL_INSTR;
      ex_tval = {32'd0, idex_instr_q};
    end else if (jump_misalign) begin
      ex_exc = 1'b1;
      ex_cause = 64'd0;  // instruction address misaligned
      ex_tval = redirect_pc;
    end else if (ex_misalign) begin
      ex_exc = idex_valid_q;
      ex_gva = idex_valid_q && idex_ctrl_q.hlv;
      ex_cause = idex_ctrl_q.mem_write ? CAUSE_STORE_MISALIGN
                                       : CAUSE_LOAD_MISALIGN;
      ex_tval = alu_result;
    end else begin
      ex_exc = 1'b0;
      ex_cause = 64'd0;
      ex_tval = 64'd0;
    end
  end

  // ------------------------------------------------------------
  // MEM stage
  // ------------------------------------------------------------
  logic [63:0] load_data;
  logic [63:0] mem_result;
  logic        data_access, mem_uses_port;
  logic        mem_pmp_fault, mem_trans_fault;
  logic        mem_gva;
  logic [63:0] mem_cause, mem_tval, mem_gpa;
  // Effective data-translation context in MEM. HLV/HSV run
  // as VS/VU (hstatus.SPVP) under vsatp + hgatp regardless of
  // the executing mode; MPRV does not affect them.
  logic [1:0]  eff_priv_mem;
  logic        eff_virt_mem;
  logic [63:0] d_satp_mux;
  logic        mmu_sum, mmu_mxr;
  assign eff_priv_mem = exmem_ctrl_q.hlv
      ? (csr_spvp ? 2'b01 : 2'b00) : eff_priv_data;
  assign eff_virt_mem = exmem_ctrl_q.hlv ? 1'b1 : dvirt;
  assign d_satp_mux = exmem_ctrl_q.hlv ? csr_vsatp : csr_satp;
  assign mmu_sum = exmem_ctrl_q.hlv ? csr_vs_sum : csr_sum;
  assign mmu_mxr = exmem_ctrl_q.hlv
      ? (csr_vs_mxr || csr_hs_mxr) : csr_mxr;

  // ---- Vector load/store sequencer (MEM) ----
  // All classes (unit-stride, strided, indexed, segment,
  // whole-register, mask, fault-only-first) step one element
  // (one field of a segment) at a time through the existing
  // MMU/PMP/data-port path, with no register-group snapshots:
  // index and store-data elements are read from the VRF word
  // ports in an RD cycle, the access happens in an ACC cycle
  // (held across translation misses), and each completed
  // load element is written straight back to the VRF with
  // byte enables. Segment loads buffer the fields of one
  // element and write them out after the last field, so a
  // fault never leaves a partial segment. Element addresses
  // advance by accumulation (no address multiplier); the
  // loop always starts at element 0 and skips elements below
  // vstart (and masked-off elements) at one cycle each,
  // without an access. On a fault the elements before it
  // are committed and vstart is set to the faulting index
  // (resumable traps); fault-only-first loads instead trim
  // vl and do not trap unless element 0 itself faults
  // (RVV 1.0 7.7). Whole-register transfers iterate bytes;
  // their vstart (in encoded-EEW elements) is scaled to
  // bytes on entry and back to elements on a fault.
  localparam logic [1:0] VLS_RD = 2'd0, VLS_ACC = 2'd1, VLS_WO = 2'd2;
  logic        vls_done, vls_elem_done;
  logic        vls_whole, vls_strided, vls_indexed, vls_ff, vls_maskls;
  logic        vls_started_q;
  logic [1:0]  vls_ph_q, vls_ph;
  logic [9:0]  vls_i_q, vls_i, vls_vl10, vls_start10;
  logic [2:0]  vls_f_q, vls_f;
  logic [63:0] vls_ea_q, vls_ea;
  logic [63:0] vls_cur, vls_addr, vls_index, vls_sdata, vls_step;
  logic [63:0] vls_vl_eff, vls_start_eff;
  logic        vls_vm_eff, vls_misalign, vls_ff_trim;
  logic        vls_in_range, vls_act, vls_last_field;
  logic [2:0]  vls_eew_code, vls_idx_eew;
  logic [63:0] vls_seg_q [8];
  assign vls_is = exmem_valid_q && !exmem_exc_q && exmem_ctrl_q.vec &&
                  (exmem_ctrl_q.mem_read || exmem_ctrl_q.mem_write);
  assign vls_whole = exmem_ctrl_q.bext_op == VLS_WHOLE;
  assign vls_strided = exmem_ctrl_q.bext_op == VLS_STRIDED;
  assign vls_indexed = exmem_ctrl_q.bext_op == VLS_INDEXED;
  assign vls_ff = exmem_ctrl_q.bext_op == VLS_FF;
  assign vls_maskls = exmem_ctrl_q.bext_op == VLS_MASK;
  assign vls_idx_eew = (exmem_ctrl_q.funct3 == 3'b000) ? 3'd0 :
                       (exmem_ctrl_q.funct3 == 3'b101) ? 3'd1 :
                       (exmem_ctrl_q.funct3 == 3'b110) ? 3'd2 : 3'd3;
  // Data EEW: bytes for whole-register, SEW for indexed.
  assign vls_eew_code = vls_whole ? 3'd0 :
                        vls_indexed ? csr_vtype[5:3] : vls_idx_eew;
  assign vls_vl_eff = vls_whole
      ? {54'd0, ({1'b0, exmem_vec_nf_q} + 4'd1), 6'd0}
      : vls_maskls ? ((csr_vl + 64'd7) >> 3) : csr_vl;
  // Whole-register transfers iterate bytes; vstart counts
  // elements of the encoded EEW, so it is scaled to bytes.
  assign vls_start_eff = !vls_whole ? csr_vstart :
      (csr_vstart >= 64'd512) ? 64'd512 : (csr_vstart << vls_idx_eew);
  assign vls_vm_eff = (vls_whole || vls_maskls) ? 1'b1 : exmem_vm_q;
  assign vls_vl10 = (vls_vl_eff > 64'd512) ? 10'd512 : vls_vl_eff[9:0];
  assign vls_start10 = (vls_start_eff > 64'd512) ? 10'd512
                                                 : vls_start_eff[9:0];
  // Effective sequencer state (initial values before the
  // first cycle of an instruction).
  assign vls_ph = vls_started_q ? vls_ph_q : VLS_RD;
  assign vls_i = vls_started_q ? vls_i_q : 10'd0;
  assign vls_f = vls_started_q ? vls_f_q : 3'd0;
  assign vls_ea = vls_started_q ? vls_ea_q : exmem_addr_q;
  assign vls_cur = {54'd0, vls_i};
  assign vls_in_range = vls_i < vls_vl10;
  assign vls_act = vls_in_range && (vls_i >= vls_start10) &&
                   (vls_vm_eff || vec_v0[vls_i[8:0]]);
  // Segments (nf>0, non-whole classes) iterate fields inside
  // each element; field f of element i lives in memory right
  // after field f-1 and in the register file at register
  // vd + f*EMUL, element i at EEW.
  logic        vls_seg;
  logic [3:0]  vls_nfields, vls_field_stride;
  logic signed [3:0] vls_emul_log2;
  assign vls_seg = !vls_whole && (exmem_vec_nf_q != 3'd0);
  assign vls_nfields = vls_seg
      ? ({1'b0, exmem_vec_nf_q} + 4'd1) : 4'd1;
  // EMUL for the destination group: (EEW/SEW)*LMUL.
  always_comb begin
    logic signed [3:0] lmul_log2;
    unique case (csr_vtype[2:0])
      3'd5: lmul_log2 = -4'sd3;
      3'd6: lmul_log2 = -4'sd2;
      3'd7: lmul_log2 = -4'sd1;
      default: lmul_log2 = 4'(signed'({1'b0, csr_vtype[2:0]}));
    endcase
    vls_emul_log2 = vls_maskls ? 4'sd0
        : (4'(signed'({1'b0, vls_eew_code})) -
           4'(signed'({1'b0, csr_vtype[5:3]})) + lmul_log2);
  end
  assign vls_field_stride =
      4'd1 << ((vls_emul_log2 < 0) ? 3'd0 : vls_emul_log2[2:0]);
  assign vls_last_field = ({1'b0, vls_f} == (vls_nfields - 4'd1));
  // VRF word addressing (element idx at width code w in the
  // group at register r; groups wrap mod 32 registers).
  /* verilator lint_off UNUSEDSIGNAL */
  function automatic logic [7:0] vls_el_addr(
      input logic [4:0] r, input logic [9:0] idx, input logic [2:0] w);
    logic [12:0] bo;
    bo = 13'(idx) << w;
    vls_el_addr = {r, 3'b000} + bo[10:3];
  endfunction
  function automatic logic [2:0] vls_el_off(
      input logic [9:0] idx, input logic [2:0] w);
    logic [12:0] bo;
    bo = 13'(idx) << w;
    vls_el_off = bo[2:0];
  endfunction
  /* verilator lint_on UNUSEDSIGNAL */
  function automatic logic [63:0] vls_ones(input logic [2:0] w);
    unique case (w)
      3'd0: vls_ones = 64'h0000_0000_0000_00ff;
      3'd1: vls_ones = 64'h0000_0000_0000_ffff;
      3'd2: vls_ones = 64'h0000_0000_ffff_ffff;
      default: vls_ones = 64'hffff_ffff_ffff_ffff;
    endcase
  endfunction
  logic [4:0] vls_freg;
  assign vls_freg = exmem_rd_q + 5'({1'b0, vls_f} * vls_field_stride);
  assign vls_re_a = vls_is && (vls_ph == VLS_RD) && vls_act && vls_indexed;
  assign vls_ra_a = vls_el_addr(exmem_vs2_q, vls_i, vls_idx_eew);
  assign vls_re_c = vls_is && (vls_ph == VLS_RD) && vls_act &&
                    exmem_ctrl_q.mem_write;
  assign vls_ra_c = vls_el_addr(vls_freg, vls_i, vls_eew_code);
  assign vls_index = (vrf_rd_a >> {vls_el_off(vls_i, vls_idx_eew), 3'b000}) &
                     vls_ones(vls_idx_eew);
  assign vls_sdata = (vrf_rd_c >> {vls_el_off(vls_i, vls_eew_code), 3'b000}) &
                     vls_ones(vls_eew_code);
  assign vls_step = vls_strided ? exmem_vec_stride_q
                                : ({60'd0, vls_nfields} << vls_eew_code);
  assign vls_addr = (vls_indexed ? (exmem_addr_q + vls_index) : vls_ea) +
                    ({61'd0, vls_f} << vls_eew_code);
  logic [63:0] mem_va;
  logic        vls_acc;
  assign vls_acc = vls_is && (vls_ph == VLS_ACC);
  assign mem_va = vls_is ? vls_addr : exmem_addr_q;
  assign vls_misalign = vls_acc &&
      (((vls_eew_code == 3'd1) && vls_addr[0]) ||
       ((vls_eew_code == 3'd2) && |vls_addr[1:0]) ||
       ((vls_eew_code == 3'd3) && |vls_addr[2:0]));
  assign vls_elem_done = vls_acc && !vls_misalign &&
                         mmu_d_ok && pmp_allow_data &&
                         !(|mmu_d_pa[63:56]) && mem_port_done;
  // Fault-only-first: a fault after at least one completed
  // element trims vl to the faulting index, no trap.
  logic vls_fault_raw;
  assign vls_fault_raw = vls_is &&
      (mem_trans_fault || mem_pmp_fault || vls_misalign);
  // RVV 1.0 7.7: only a fault on element 0 traps; a fault on
  // any later element (even if element 0 was masked off or
  // below vstart) trims vl to that index.
  assign vls_ff_trim = vls_ff && vls_fault_raw && (vls_cur != 64'd0);
  assign vls_done = vls_is &&
                    (vls_ff_trim || ((vls_ph == VLS_RD) && !vls_in_range));
  logic vls_fault;
  assign vls_fault = vls_fault_raw && !vls_ff_trim;
  // Load data write-back: one element per completed access,
  // or the buffered fields of a segment in the write-out
  // phase. Never while an older instruction traps.
  logic [63:0] vls_ld_el;
  assign vls_ld_el = load_shifted & vls_ones(vls_eew_code);
  always_comb begin
    logic [63:0] wd;
    vls_vrf_we = 1'b0;
    wd = vls_ld_el;
    if (vls_is && exmem_ctrl_q.mem_read && !trap_fire) begin
      if (vls_ph == VLS_WO) begin
        vls_vrf_we = 1'b1;
        wd = vls_seg_q[vls_f];
      end else if (vls_elem_done && !vls_seg) begin
        vls_vrf_we = 1'b1;
      end
    end
    vls_vrf_wa = vls_el_addr(vls_freg, vls_i, vls_eew_code);
    vls_vrf_wbe = ((vls_eew_code == 3'd0) ? 8'h01 :
                   (vls_eew_code == 3'd1) ? 8'h03 :
                   (vls_eew_code == 3'd2) ? 8'h0f : 8'hff)
                  << vls_el_off(vls_i, vls_eew_code);
    vls_vrf_wd = wd << {vls_el_off(vls_i, vls_eew_code), 3'b000};
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      vls_started_q <= 1'b0;
      vls_ph_q <= VLS_RD;
      vls_f_q <= 3'd0;
      vls_i_q <= 10'd0;
      vls_ea_q <= 64'd0;
    end else if (!vls_is || vls_done || vls_fault || trap_fire) begin
      vls_started_q <= 1'b0;
      vls_ph_q <= VLS_RD;
      vls_f_q <= 3'd0;
    end else begin
      vls_started_q <= 1'b1;
      vls_ph_q <= vls_ph;
      vls_f_q <= vls_f;
      vls_i_q <= vls_i;
      vls_ea_q <= vls_ea;
      unique case (vls_ph)
        VLS_RD: begin
          if (vls_act) begin
            vls_ph_q <= VLS_ACC;
          end else begin
            vls_i_q <= vls_i + 10'd1;          // skip element
            vls_ea_q <= vls_ea + vls_step;
          end
        end
        VLS_ACC: begin
          if (vls_elem_done) begin
            if (!vls_last_field) begin
              vls_f_q <= vls_f + 3'd1;
              vls_ph_q <= VLS_RD;
            end else if (vls_seg && exmem_ctrl_q.mem_read) begin
              vls_f_q <= 3'd0;
              vls_ph_q <= VLS_WO;
            end else begin
              vls_f_q <= 3'd0;
              vls_ph_q <= VLS_RD;
              vls_i_q <= vls_i + 10'd1;
              vls_ea_q <= vls_ea + vls_step;
            end
          end
        end
        default: begin  // VLS_WO
          if (!vls_last_field) begin
            vls_f_q <= vls_f + 3'd1;
          end else begin
            vls_f_q <= 3'd0;
            vls_ph_q <= VLS_RD;
            vls_i_q <= vls_i + 10'd1;
            vls_ea_q <= vls_ea + vls_step;
          end
        end
      endcase
    end
  end
  // Segment field buffer (no reset needed: written before read).
  always_ff @(posedge clk_i) begin
    if (vls_elem_done && vls_seg && exmem_ctrl_q.mem_read) begin
      vls_seg_q[vls_f] <= vls_ld_el;
    end
  end

  // A translation miss parks the access in MEM (pipeline hold);
  // a translation fault or a PMP denial on the PA excepts it.
  assign data_access = exmem_valid_q && !exmem_exc_q &&
                       (exmem_ctrl_q.mem_read || exmem_ctrl_q.mem_write) &&
                       (!vls_is || vls_acc);
  assign mem_trans_fault = data_access && mmu_d_fault;
  // PMP denial, or a physical address outside the 56-bit map.
  assign mem_pmp_fault = data_access && mmu_d_ok &&
                         (!pmp_allow_data || |mmu_d_pa[63:56]);
  assign mem_uses_port = data_access && mmu_d_ok && !mem_pmp_fault &&
                         !vls_misalign;

  // ---- Data-port controller ----
  // One request in flight, owned by MEM or by the page-table
  // walker (dq_walk_q). MEM has priority; the walker only gets
  // the port while MEM does not need it. A MEM access issues
  // only when no older instruction is trapping (trap_fire) so it
  // always completes; a walker request abandoned by an MMU
  // flush/abort is marked stale (dq_drop_q) and its response is
  // swallowed. AMOs are a LOAD (value saved in amo_rdata_q) then
  // a STORE of the combined value; the port stays MEM's between
  // the two. A failing SC performs no access. FENCE.I issues a
  // CLEAN (D$ write-back) and invalidates the I$ on its response.
  logic        dq_pend_q, dq_walk_q, dq_drop_q;
  logic        amo_wr_q;        // AMO read phase done; write next
  logic [63:0] amo_rdata_q;
  logic        exmem_fencei_q;
  logic        mem_fencei, mem_needs_port, mem_issue, mem_rsp;
  logic        mem_write_phase, walk_issue, walk_skip, walk_rsp;
  logic        sc_success;
  assign mem_fencei = exmem_valid_q && !exmem_exc_q && exmem_fencei_q;
  assign mem_needs_port = (mem_uses_port &&
                           !(exmem_ctrl_q.sc && !sc_success)) ||
                          mem_fencei;
  assign mem_write_phase = exmem_ctrl_q.mem_write &&
                           (!exmem_ctrl_q.amo || amo_wr_q);
  assign mem_issue = mem_needs_port && !dq_pend_q && !trap_fire && !freeze;
  assign mem_rsp = drsp_valid_i && dq_pend_q && !dq_walk_q;
  // The final (or only) phase of MEM's access responds.
  assign mem_port_done = mem_rsp && (!exmem_ctrl_q.amo || amo_wr_q);
  // Walker: PMP-denied PTE accesses complete at once with no
  // memory access (the MMU turns them into access faults).
  assign walk_issue = walk_req && pmp_allow_walk && !dq_pend_q &&
                      !mem_needs_port && !trap_fire && !freeze;
  assign walk_skip = walk_req && !pmp_allow_walk && !dq_pend_q &&
                     !mem_needs_port && !trap_fire && !freeze;
  assign walk_rsp = drsp_valid_i && dq_pend_q && dq_walk_q && !dq_drop_q;
  assign walk_grant = walk_skip || walk_rsp;
  assign dreq_valid_o = mem_issue || walk_issue;
  assign fencei_block = mem_fencei;
  assign icache_inval_o = mem_fencei && mem_rsp;

  // MEM stalls on a translation miss, on its own port access
  // until the final response, and while a vector LS sequences.
  assign mem_stall = (data_access && !mmu_d_ok && !mmu_d_fault) ||
                     (mem_needs_port && !vls_is && !mem_port_done) ||
                     (vls_is && !vls_done && !vls_fault);

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      dq_pend_q <= 1'b0;
      dq_walk_q <= 1'b0;
      dq_drop_q <= 1'b0;
      amo_wr_q <= 1'b0;
      amo_rdata_q <= 64'd0;
    end else begin
      if (drsp_valid_i) begin
        dq_pend_q <= 1'b0;
        dq_drop_q <= 1'b0;
      end
      if (dreq_valid_o && dreq_ready_i) begin
        dq_pend_q <= 1'b1;
        dq_walk_q <= !mem_issue;
        dq_drop_q <= 1'b0;
      end
      // MMU flush/abort kills the walk that owns the port.
      if ((sfence_fire || trap_take) &&
          ((dq_pend_q && dq_walk_q && !drsp_valid_i) ||
           (walk_issue && dreq_ready_i))) begin
        dq_drop_q <= 1'b1;
      end
      if (mem_rsp && exmem_ctrl_q.amo && !amo_wr_q) begin
        amo_wr_q <= 1'b1;
        amo_rdata_q <= drsp_rdata_i;
      end else if (mem_port_done) begin
        amo_wr_q <= 1'b0;
      end
    end
  end

  // A MEM access in flight is never abandoned: nothing older can
  // trap while it waits (WB is frozen behind mem_stall).
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
  a_mem_kept: assert property (@(posedge clk_i) disable iff (!chk_live_q)
      (dq_pend_q && !dq_walk_q) |-> (!trap_take && mem_needs_port))
    else $error("core: MEM data access abandoned in flight");
  a_drsp: assert property (@(posedge clk_i) disable iff (!chk_live_q)
      drsp_valid_i |-> dq_pend_q)
    else $error("core: data response with no request");
  a_irsp: assert property (@(posedge clk_i) disable iff (!chk_live_q)
      irsp_valid_i |-> ifq_pend_q)
    else $error("core: fetch response with no request");
`endif

  logic [63:0] mem_rdata;  // (load_shifted is forward-declared)
  logic        res_valid_q;
  logic [63:0] res_pa_q;
  logic        res_is_d_q;  // reserved access size: 1 = 8B, 0 = 4B
  assign mem_rdata = amo_wr_q ? amo_rdata_q : drsp_rdata_i;
  assign load_shifted = mem_rdata >> {mem_va[2:0], 3'b000};

  // AMO read-modify-write in MEM: the write phase combines the
  // value saved from the read phase with rs2.
  logic [63:0] eff_store_data, amo_old;
  assign amo_old = amo_rdata_q >> {mem_va[2:0], 3'b000};
  always_comb begin
    logic [31:0] a32, b32, r32;
    logic [63:0] r64;
    a32 = amo_old[31:0];
    b32 = exmem_store_data_q[31:0];
    unique case (exmem_ctrl_q.amo_op)
      5'b00000: begin  // AMOADD
        r32 = a32 + b32;
        r64 = amo_old + exmem_store_data_q;
      end
      5'b00100: begin  // AMOXOR
        r32 = a32 ^ b32;
        r64 = amo_old ^ exmem_store_data_q;
      end
      5'b01000: begin  // AMOOR
        r32 = a32 | b32;
        r64 = amo_old | exmem_store_data_q;
      end
      5'b01100: begin  // AMOAND
        r32 = a32 & b32;
        r64 = amo_old & exmem_store_data_q;
      end
      5'b10000: begin  // AMOMIN
        r32 = ($signed(a32) < $signed(b32)) ? a32 : b32;
        r64 = ($signed(amo_old) < $signed(exmem_store_data_q))
              ? amo_old : exmem_store_data_q;
      end
      5'b10100: begin  // AMOMAX
        r32 = ($signed(a32) > $signed(b32)) ? a32 : b32;
        r64 = ($signed(amo_old) > $signed(exmem_store_data_q))
              ? amo_old : exmem_store_data_q;
      end
      5'b11000: begin  // AMOMINU
        r32 = (a32 < b32) ? a32 : b32;
        r64 = (amo_old < exmem_store_data_q)
              ? amo_old : exmem_store_data_q;
      end
      5'b11100: begin  // AMOMAXU
        r32 = (a32 > b32) ? a32 : b32;
        r64 = (amo_old > exmem_store_data_q)
              ? amo_old : exmem_store_data_q;
      end
      default: begin  // AMOSWAP
        r32 = b32;
        r64 = exmem_store_data_q;
      end
    endcase
    eff_store_data = exmem_ctrl_q.amo
        ? ((exmem_ctrl_q.funct3 == 3'b010) ? {32'd0, r32} : r64)
        : exmem_store_data_q;
    if (vls_is) begin
      // Vector store element read from the VRF in RD.
      eff_store_data = vls_sdata;
    end
  end
  // "Reserve exactly enough to cover the access": an SC
  // succeeds iff its whole access lies within the LR's range.
  assign sc_success = res_valid_q && (res_pa_q == mmu_d_pa) &&
                      (res_is_d_q || (exmem_ctrl_q.funct3 == 3'b010));

  // Data-port request payload. be names the accessed lanes for
  // loads too (an uncached I/O load sees its exact width).
  always_comb begin
    logic [7:0]  be;
    logic [63:0] wdata;
    unique case (vls_is ? vls_eew_code[1:0] : exmem_ctrl_q.funct3[1:0])
      2'b00: begin
        be = 8'h01 << mem_va[2:0];
        wdata = {8{eff_store_data[7:0]}};
      end
      2'b01: begin
        be = 8'h03 << {mem_va[2:1], 1'b0};
        wdata = {4{eff_store_data[15:0]}};
      end
      2'b10: begin
        be = 8'h0F << {mem_va[2], 2'b00};
        wdata = {2{eff_store_data[31:0]}};
      end
      default: begin
        be = 8'hFF;
        wdata = eff_store_data;
      end
    endcase
    if (!mem_issue) begin
      // PTE read, or A/D writeback of the leaf PTE.
      dreq_addr_o = walk_addr;
      dreq_op_o = walk_we ? DOP_STORE : DOP_LOAD;
      dreq_be_o = 8'hFF;
      dreq_wdata_o = walk_wdata;
    end else if (mem_fencei) begin
      dreq_addr_o = 64'd0;
      dreq_op_o = DOP_CLEAN;
      dreq_be_o = 8'h00;
      dreq_wdata_o = 64'd0;
    end else begin
      dreq_addr_o = mmu_d_pa;
      dreq_op_o = mem_write_phase ? DOP_STORE : DOP_LOAD;
      dreq_be_o = be;
      dreq_wdata_o = wdata;
    end
  end

  always_comb begin
    unique case (exmem_ctrl_q.funct3)
      3'b000:  load_data = {{56{load_shifted[7]}}, load_shifted[7:0]};
      3'b001:  load_data = {{48{load_shifted[15]}}, load_shifted[15:0]};
      3'b010:  load_data = {{32{load_shifted[31]}}, load_shifted[31:0]};
      3'b011:  load_data = load_shifted;
      3'b100:  load_data = {56'd0, load_shifted[7:0]};
      3'b101:  load_data = {48'd0, load_shifted[15:0]};
      3'b110:  load_data = {32'd0, load_shifted[31:0]};
      default: load_data = 64'd0;
    endcase
  end

  assign mem_result = exmem_ctrl_q.sc ? (sc_success ? 64'd0 : 64'd1)
                    : exmem_ctrl_q.mem_read ?
                        ((exmem_ctrl_q.fp_rd && !exmem_ctrl_q.fmt_d) ?
                            {32'hFFFF_FFFF, load_shifted[31:0]} :
                            load_data)
                    : exmem_result_q;

  // LR/SC reservation (physical address + access size). Set
  // by a completing LR; cleared by any SC attempt, by a
  // store/AMO overlapping the reserved bytes, and on traps.
  logic        mem_completes;
  logic [63:0] store_end, res_end;
  assign mem_completes = data_access && !mem_stall && !mem_exc && !freeze;
  assign store_end = mmu_d_pa + (64'd1 << exmem_ctrl_q.funct3[1:0]);
  assign res_end = res_pa_q + (res_is_d_q ? 64'd8 : 64'd4);
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      res_valid_q <= 1'b0;
      res_pa_q <= 64'd0;
      res_is_d_q <= 1'b0;
    end else if (trap_take) begin
      res_valid_q <= 1'b0;
    end else if (mem_completes) begin
      if (exmem_ctrl_q.lr) begin
        res_valid_q <= 1'b1;
        res_pa_q <= mmu_d_pa;
        res_is_d_q <= (exmem_ctrl_q.funct3 == 3'b011);
      end else if (exmem_ctrl_q.sc) begin
        res_valid_q <= 1'b0;
      end else if (exmem_ctrl_q.mem_write && res_valid_q &&
                   (mmu_d_pa < res_end) && (res_pa_q < store_end)) begin
        res_valid_q <= 1'b0;
      end
    end
  end
  always_comb begin
    if (exmem_exc_q) begin
      mem_exc = exmem_valid_q;
      mem_gva = exmem_gva_q;
      mem_cause = exmem_cause_q;
      mem_tval = exmem_tval_q;
      mem_gpa = exmem_gpa_q;
    end else if (vls_misalign && !vls_ff_trim) begin
      mem_exc = 1'b1;
      mem_gva = 1'b0;
      mem_cause = exmem_ctrl_q.mem_write ? 64'd6 : 64'd4;
      mem_tval = mem_va;
      mem_gpa = 64'd0;
    end else if (mem_trans_fault && !vls_ff_trim) begin
      mem_exc = 1'b1;
      mem_gva = exmem_ctrl_q.hlv;
      mem_cause = exmem_ctrl_q.mem_write
          ? (mmu_d_fault_guest ? 64'd23 :
             mmu_d_fault_page ? 64'd15 : 64'd7)
          : (mmu_d_fault_guest ? 64'd21 :
             mmu_d_fault_page ? 64'd13 : 64'd5);
      mem_tval = mem_va;  // faulting VA (element addr for VLS)
      mem_gpa = mmu_d_fault_gpa;
    end else if (mem_pmp_fault && !vls_ff_trim) begin
      mem_exc = 1'b1;
      mem_gva = exmem_ctrl_q.hlv;
      mem_cause = exmem_ctrl_q.mem_write ? 64'd7 : 64'd5;
      mem_tval = mem_va;
      mem_gpa = 64'd0;
    end else begin
      mem_exc = 1'b0;
      mem_gva = 1'b0;
      mem_cause = 64'd0;
      mem_tval = 64'd0;
      mem_gpa = 64'd0;
    end
  end

  // ------------------------------------------------------------
  // CSR / privileged unit
  // ------------------------------------------------------------
  muserisc_csr u_csr (
      .clk_i         (clk_i),
      .rst_ni        (rst_ni),
      .addr_i        (csr_addr),
      .rdata_o       (csr_rdata),
      .illegal_o     (csr_illegal),
      .wr_en_i       (csr_we),  // module itself suppresses illegal writes
      .frm_o         (csr_frm),
      .fs_o          (csr_fs),
      .fflags_we_i   (csr_fflags_we || vec_fflags_we),
      .fflags_i      (vec_fflags_we ? vec_fflags : fpu_flags),
      .fp_dirty_i    (fp_dirty),
      .vec_vs_o      (csr_vec_vs),
      .vtype_o       (csr_vtype),
      .vl_o          (csr_vl),
      .vstart_o      (csr_vstart),
      .vset_vl_o     (csr_vset_vl),
      .vset_en_i     (vset_en),
      .vset_avl_i    (vset_avl),
      .vset_vtype_i  (vset_vtype_raw),
      .vset_keep_vl_i(idex_ctrl_q.vset &&
                      (idex_ctrl_q.fpu_aux != 2'd1) &&
                      (idex_rd_q == 5'd0) &&
                      (idex_rs1_addr_q == 5'd0)),
      .vset_vlmax_i  (idex_ctrl_q.vset &&
                      (idex_ctrl_q.fpu_aux != 2'd1) &&
                      (idex_rd_q != 5'd0) &&
                      (idex_rs1_addr_q == 5'd0)),
      .vec_dirty_i   ((vec_commit && (idex_ctrl_q.vec_rd ||
                                     (csr_vstart != 64'd0))) ||
                      (vls_is && exmem_ctrl_q.mem_read && !trap_fire &&
                       (vls_done || vls_fault))),
      // Every vector instruction resets vstart when it
      // completes; a faulting vector load/store sets it to
      // the faulting element index.
      .vstart_we_i   (vec_commit ||
                      (vls_is && !trap_fire && (vls_done || vls_fault))),
      .vstart_wdata_i(!vls_fault ? 64'd0 :
                      vls_whole ? (vls_cur >> vls_idx_eew) : vls_cur),
      .vl_we_i       (vls_ff_trim && !trap_fire),
      .vl_wdata_i    (vls_cur),
      .vxrm_o        (csr_vxrm),
      .vxsat_set_i   (vec_sat && vec_commit),
      .wdata_i       (csr_wdata),
      .sys_illegal_o (sys_illegal),
      .sys_op_i      (sys_op),
      .ret_en_i      (ex_ret && !trap_fire && !mem_exc && !mem_stall),
      .trap_take_i   (trap_take),
      .trap_cause_i  (memwb_cause_q),
      .trap_pc_i     (memwb_pc_q),
      .trap_tval_i   (memwb_tval_q),
      .trap_gpa_i    (memwb_gpa_q),
      .trap_gva_i    (memwb_gva_q),
      .trap_tinst_i  (64'd0),  // zero is a legal htinst/mtinst value
      .trap_target_o (trap_target),
      .trap_priv_o   (trap_priv_unused),
      .irq_valid_o   (irq_valid),
      .irq_cause_o   (irq_cause),
      .irq_m_timer_i (irq_m_timer_i),
      .irq_m_soft_i  (irq_m_soft_i),
      .irq_m_ext_i   (irq_m_ext_i),
      .irq_s_timer_i (irq_s_timer_i),
      .irq_s_ext_i   (irq_s_ext_i),
      .priv_o        (priv),
      .virt_o        (virt),
      .dvirt_o       (dvirt),
      .virt_inst_o   (csr_virt_inst),
      .sum_o         (csr_sum),
      .mxr_o         (csr_mxr),
      .hs_mxr_o      (csr_hs_mxr),
      .satp_o        (csr_satp),
      .fsatp_o       (csr_fsatp),
      .vsatp_o       (csr_vsatp),
      .spvp_o        (csr_spvp),
      .vs_sum_o      (csr_vs_sum),
      .vs_mxr_o      (csr_vs_mxr),
      .hgatp_o       (csr_hgatp),
      .mstatus_o     (csr_mstatus),
      .xret_pc_o     (xret_pc),
      .retire_i      (memwb_valid_q && !memwb_exc_q && !mem_stall),
      .pmp_addr_a_i  (mmu_if_pa),
      .pmp_acc_a_i   (2'd2),
      .pmp_priv_a_i  (priv),
      .pmp_allow_a_o (pmp_allow_fetch),
      .pmp_addr_b_i  (mmu_d_pa),
      .pmp_acc_b_i   (exmem_ctrl_q.hlvx ? 2'd3 :
                      exmem_ctrl_q.mem_write ? 2'd1 : 2'd0),
      .pmp_priv_b_i  (eff_priv_mem),
      .pmp_allow_b_o (pmp_allow_data),
      .pmp_addr_c_i  (walk_addr),
      .pmp_acc_c_i   (walk_acc),
      .pmp_priv_c_i  (2'b01),  // implicit PTE accesses check as S
      .pmp_allow_c_o (pmp_allow_walk)
  );

  // ------------------------------------------------------------
  // MMU (Sv39 + Svnapot TLB and walker)
  // ------------------------------------------------------------
  muserisc_mmu u_mmu (
      .clk_i            (clk_i),
      .rst_ni           (rst_ni),
      .satp_i           (csr_fsatp),
      .d_satp_i         (d_satp_mux),
      .hgatp_i          (csr_hgatp),
      .sum_i            (mmu_sum),
      .mxr_i            (mmu_mxr),
      .hs_mxr_i         (csr_hs_mxr),
      .flush_i          (sfence_fire),
      .abort_i          (trap_take),
      .if_va_i          (fetch_va),
      .if_priv_i        (priv),
      .if_virt_i        (virt),
      .if_pa_o          (mmu_if_pa),
      .if_ok_o          (mmu_if_ok),
      .if_fault_o       (mmu_if_fault),
      .if_fault_page_o  (mmu_if_fault_page),
      .if_fault_guest_o (mmu_if_fault_guest),
      .if_fault_gpa_o   (mmu_if_fault_gpa),
      .d_va_i           (mem_va),
      .d_write_i        (exmem_ctrl_q.mem_write),
      .d_exec_i         (exmem_ctrl_q.hlvx),
      .d_priv_i         (eff_priv_mem),
      .d_virt_i         (eff_virt_mem),
      .d_valid_i        (data_access),
      .d_pa_o           (mmu_d_pa),
      .d_ok_o           (mmu_d_ok),
      .d_fault_o        (mmu_d_fault),
      .d_fault_page_o   (mmu_d_fault_page),
      .d_fault_guest_o  (mmu_d_fault_guest),
      .d_fault_gpa_o    (mmu_d_fault_gpa),
      .walk_req_o       (walk_req),
      .walk_addr_o      (walk_addr),
      .walk_we_o        (walk_we),
      .walk_wdata_o     (walk_wdata),
      .walk_acc_o       (walk_acc),
      .walk_grant_i     (walk_grant),
      .walk_rdata_i     (drsp_rdata_i),
      .walk_pmp_allow_i (pmp_allow_walk)
  );

  // ------------------------------------------------------------
  // PC and pipeline registers
  // ------------------------------------------------------------
  always_comb begin
    if (flush)                             pc_d = redirect_pc;
    else if (stall || freeze || fetch_stall || straddle_enter ||
             ex_hold)
                                           pc_d = pc_q;
    else if (fetch_fault)                  pc_d = pc_q + 64'd4;
    else                                   pc_d = pc_q +
                                                 (fetch_rvc ? 64'd2
                                                            : 64'd4);
  end

  // FENCE.I marker travelling with EX/MEM (qualified by
  // exmem_valid_q; same update condition as the EX/MEM register).
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      exmem_fencei_q <= 1'b0;
    end else if (!trap_take && !freeze && !mem_stall) begin
      exmem_fencei_q <= ex_fencei;
    end
  end

  // Fetch-port bookkeeping (see fetch_word_ok above). IF
  // consumes its word on the same condition that loads IF/ID
  // (or enters a straddle) below; a flush or trap redirects.
  // if_consume uses the generic ex_hold (vector unit and every
  // multi-cycle EX unit), so a fetch word that arrives while EX
  // is held stays buffered instead of being consumed.
  logic if_redirect, if_consume, ifq_issue;
  assign if_redirect = trap_take || (flush && !freeze && !mem_stall);
  assign if_consume = !trap_take && !freeze && !mem_stall && !flush &&
                      !stall && !fetch_stall && !ex_hold;
  assign ifq_issue = ireq_valid_o && ireq_ready_i;
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      ifw_valid_q <= 1'b0;
      ifw_q <= 32'd0;
      ifq_pend_q <= 1'b0;
      ifq_drop_q <= 1'b0;
    end else begin
      if (irsp_valid_i) ifq_pend_q <= 1'b0;
      if (ifq_issue) begin
        ifq_pend_q <= 1'b1;
        ifq_drop_q <= 1'b0;
      end
      if (if_redirect) begin
        ifw_valid_q <= 1'b0;
        if ((ifq_pend_q && !irsp_valid_i) || ifq_issue) ifq_drop_q <= 1'b1;
      end else if (if_consume) begin
        // (A fetch fault can be consumed while a request is
        // still out; its word then belongs to the old PC.)
        ifw_valid_q <= 1'b0;
        if (ifq_pend_q && !irsp_valid_i) ifq_drop_q <= 1'b1;
      end else if (irsp_valid_i && ifq_pend_q && !ifq_drop_q) begin
        ifw_valid_q <= 1'b1;
        ifw_q <= irsp_rdata_i;
      end
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      pc_q <= boot_pc_i;
      ifid_valid_q <= 1'b0;
      idex_valid_q <= 1'b0;
      exmem_valid_q <= 1'b0;
      memwb_valid_q <= 1'b0;
      ifid_pc_q <= 64'd0;
      ifid_instr_q <= 32'd0;
      ifid_exc_q <= 1'b0;
      ifid_cause_q <= 64'd0;
      ifid_rvc_q <= 1'b0;
      ifid_parcel_q <= 16'd0;
      ifid_tval_q <= 64'd0;
      ifid_gpa_q <= 64'd0;
      straddle_q <= 1'b0;
      straddle_lo_q <= 16'd0;
      idex_rvc_q <= 1'b0;
      idex_pc_q <= 64'd0;
      idex_ctrl_q <= '0;
      idex_imm_q <= 64'd0;
      idex_instr_q <= 32'd0;
      idex_rs1_q <= 64'd0;
      idex_rs2_q <= 64'd0;
      idex_rs1_addr_q <= 5'd0;
      idex_rs2_addr_q <= 5'd0;
      idex_rd_q <= 5'd0;
      idex_exc_q <= 1'b0;
      idex_cause_q <= 64'd0;
      idex_tval_q <= 64'd0;
      idex_gpa_q <= 64'd0;
      exmem_pc_q <= 64'd0;
      exmem_ctrl_q <= '0;
      exmem_result_q <= 64'd0;
      exmem_addr_q <= 64'd0;
      exmem_store_data_q <= 64'd0;
      exmem_rd_q <= 5'd0;
      exmem_exc_q <= 1'b0;
      exmem_gva_q <= 1'b0;
      exmem_cause_q <= 64'd0;
      exmem_tval_q <= 64'd0;
      exmem_gpa_q <= 64'd0;
      memwb_pc_q <= 64'd0;
      memwb_result_q <= 64'd0;
      memwb_rd_q <= 5'd0;
      memwb_reg_write_q <= 1'b0;
      memwb_exc_q <= 1'b0;
      memwb_gva_q <= 1'b0;
      memwb_cause_q <= 64'd0;
      memwb_tval_q <= 64'd0;
      memwb_gpa_q <= 64'd0;
    end else if (trap_take) begin
      // Precise trap entry: redirect and empty the pipeline,
      // including any half-fetched straddled instruction.
      pc_q <= trap_target;
      straddle_q <= 1'b0;
      ifid_valid_q <= 1'b0;
      idex_valid_q <= 1'b0;
      exmem_valid_q <= 1'b0;
      memwb_valid_q <= 1'b0;
      ifid_exc_q <= 1'b0;
    end else if (!freeze && !mem_stall) begin
      // (mem_stall holds every pipeline register; the parked
      // MEM access retries once its translation resolves.)
      pc_q <= pc_d;

      memwb_valid_q <= exmem_valid_q;
      memwb_pc_q <= exmem_pc_q;
      memwb_result_q <= mem_result;
      memwb_rd_q <= exmem_rd_q;
      memwb_reg_write_q <= exmem_ctrl_q.reg_write;
      memwb_fp_write_q <= exmem_ctrl_q.fp_rd;
      memwb_exc_q <= mem_exc;
      memwb_gva_q <= mem_gva;
      memwb_cause_q <= mem_cause;
      memwb_tval_q <= mem_tval;
      memwb_gpa_q <= mem_gpa;

      exmem_valid_q <= idex_valid_q && !ex_hold;
      exmem_pc_q <= idex_pc_q;
      exmem_ctrl_q <= idex_ctrl_q;
      exmem_result_q <= ex_result;
      exmem_addr_q <= alu_result;
      exmem_store_data_q <= idex_ctrl_q.fp_rs2 ? ex_frs2 : ex_rs2;
      exmem_vm_q <= idex_instr_q[25];
      exmem_vs2_q <= idex_instr_q[24:20];
      exmem_vec_stride_q <= ex_rs2;
      exmem_vec_nf_q <= idex_instr_q[31:29];
      exmem_rd_q <= idex_rd_q;
      exmem_exc_q <= ex_exc;
      exmem_gva_q <= ex_gva;
      exmem_cause_q <= ex_cause;
      exmem_tval_q <= ex_tval;
      exmem_gpa_q <= ex_gpa;

      if (ex_hold) begin
        // Hold the EX instruction (a vector op re-executes next
        // cycle against the updated VRF; a multi-cycle unit keeps
        // working). Refresh its source operands with this
        // cycle's forwarded values: the producers keep draining
        // through MEM/WB and would fall out of forwarding range.
        idex_rs1_q <= ex_rs1;
        idex_rs2_q <= ex_rs2;
        idex_frs1_q <= ex_frs1;
        idex_frs2_q <= ex_frs2;
        idex_frs3_q <= ex_frs3;
      end else if (stall || flush) begin
        idex_valid_q <= 1'b0;
      end else if (irq_inject) begin
        // The fetched instruction has not executed; epc will
        // point at it so it re-executes after the handler.
        idex_valid_q <= 1'b1;
        idex_pc_q <= ifid_pc_q;
        idex_ctrl_q <= '0;
        idex_imm_q <= 64'd0;
        idex_instr_q <= 32'd0;
        idex_rvc_q <= 1'b0;
        idex_rs1_q <= 64'd0;
        idex_rs2_q <= 64'd0;
        idex_rs1_addr_q <= 5'd0;
        idex_rs2_addr_q <= 5'd0;
        idex_rd_q <= 5'd0;
        idex_exc_q <= 1'b1;
        idex_cause_q <= irq_cause;
        idex_tval_q <= 64'd0;
        idex_gpa_q <= 64'd0;
      end else begin
        idex_valid_q <= ifid_valid_q;
        idex_pc_q <= ifid_pc_q;
        idex_ctrl_q <= ifid_exc_q ? '0 : id_ctrl;
        idex_imm_q <= id_imm;
        idex_instr_q <= ifid_rvc_q ? {16'b0, ifid_parcel_q}
                                   : ifid_instr_q;
        idex_rvc_q <= ifid_rvc_q;
        idex_rs1_q <= id_rs1_val;
        idex_rs2_q <= id_rs2_val;
        idex_frs1_q <= id_frs1_val;
        idex_frs2_q <= id_frs2_val;
        idex_frs3_q <= id_frs3_val;
        idex_rs3_addr_q <= id_rs3;
        idex_rs1_addr_q <= id_rs1;
        idex_rs2_addr_q <= id_rs2;
        idex_rd_q <= id_rd;
        idex_exc_q <= id_exc;
        idex_cause_q <= id_cause;
        idex_tval_q <= id_tval;
        idex_gpa_q <= id_gpa;
      end

      if (flush) begin
        ifid_valid_q <= 1'b0;
        ifid_exc_q <= 1'b0;
        straddle_q <= 1'b0;
      end else if (!stall && !fetch_stall && !ex_hold) begin
        if (straddle_enter) begin
          // Hold the low parcel; complete it next cycle.
          ifid_valid_q <= 1'b0;
          ifid_exc_q <= 1'b0;
          straddle_q <= 1'b1;
          straddle_lo_q <= parcel16;
        end else begin
          ifid_valid_q <= 1'b1;
          ifid_pc_q <= pc_q;
          ifid_instr_q <= fetch_fault ? 32'd0 : fetch_instr;
          ifid_exc_q <= fetch_fault;
          ifid_cause_q <= fetch_cause;
          ifid_rvc_q <= fetch_rvc && !fetch_fault;
          ifid_parcel_q <= parcel16;
          ifid_tval_q <= fetch_tval;
          ifid_gpa_q <= mmu_if_fault_guest ? mmu_if_fault_gpa : 64'd0;
          straddle_q <= 1'b0;
        end
      end else if (fetch_stall && !stall && !ex_hold) begin
        // Walker is resolving this PC: bubble ID until it lands.
        ifid_valid_q <= 1'b0;
        ifid_exc_q <= 1'b0;
      end
    end
  end
endmodule
`default_nettype wire
