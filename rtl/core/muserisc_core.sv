// In-house RV64 core (issue #18). Five-stage in-order pipeline
// (IF/ID/EX/MEM/WB) over combinational-read Harvard memory ports
// with M/S/U privilege, precise traps, interrupts, PMP, and an
// Sv39+Svnapot MMU; see docs/CORE.md for the contract and
// staging plan.
//
// Pipeline policy:
// - Full forwarding to EX (EX/MEM and MEM/WB) plus a WB->ID
//   bypass so an instruction reading a register in the cycle its
//   producer is in WB latches the new value.
// - One bubble on load-use (consumer in ID against a load in EX).
// - All control transfers resolve in EX (predict not-taken):
//   taken branches, jumps, xRET, and SFENCE flush IF/ID + ID/EX.
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
`default_nettype none
module muserisc_core import muserisc_pkg::*; (
    input  wire        clk_i,
    input  wire        rst_ni,
    input  wire [63:0] boot_pc_i,     // reset PC (0 for directed TBs)
    // Instruction memory (combinational read)
    output wire [63:0] imem_addr_o,
    input  wire [31:0] imem_rdata_i,
    // Data memory (combinational read, byte-enable write)
    output wire [63:0] dmem_addr_o,
    output logic [63:0] dmem_wdata_o,
    output logic [7:0]  dmem_be_o,
    output wire        dmem_re_o,
    input  wire [63:0] dmem_rdata_i,
    // External scalar data stall: while asserted for a data
    // access in MEM, the whole pipeline holds exactly as for a
    // translation miss and the access completes in the cycle
    // this drops (SoC fabric uses it for AXI/handshaked MMIO;
    // tie to 0 for plain combinational SRAM). Vector LS and
    // walker accesses do not consume it.
    input  wire        dmem_stall_i,
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
  logic        mem_stall;     // data translation miss: hold all regs
  logic        fpu_req, fpu_done;
  logic        ex_mc_busy;    // a multi-cycle EX unit is still working
  logic        ex_hold;       // EX holds (multi-cycle unit / vector WB)
  logic        ex_advance;    // EX contents move to EX/MEM this cycle
  logic        sfence_fire;   // SFENCE.VMA commits this cycle
  // Forward declarations for signals driven in later
  // stages but read in EX/ID gating (slang synthesis
  // requires declaration before use; Verilator did not).
  logic        vec_wb_stall, vls_vrf_we, vec_fflags_we, mem_exc;
  logic signed [3:0] vls_emul_log2;
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
  assign imem_addr_o = mmu_if_pa;
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
  assign fetch_stall = !fetch_pa_illegal && !mmu_if_ok &&
                       !mmu_if_fault;

  // Parcel assembly and decompression.
  logic [15:0] parcel16;
  logic        parcel_long, rvc_illegal, straddle_enter;
  logic [31:0] fetch_instr, rvc_expanded;
  logic        fetch_rvc;
  logic [63:0] fetch_tval;
  assign parcel16 = pc_q[1] ? imem_rdata_i[31:16]
                            : imem_rdata_i[15:0];
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
      fetch_instr = {imem_rdata_i[15:0], straddle_lo_q};
      fetch_rvc = 1'b0;
    end else if (!parcel_long) begin
      fetch_instr = rvc_illegal ? 32'b0 : rvc_expanded;
      fetch_rvc = 1'b1;
    end else begin
      fetch_instr = imem_rdata_i;
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
  logic [4095:0] exmem_vec_data_q;  // vd old / vs3 group for MEM
  logic [511:0]  exmem_vec_mask_q;  // v0 snapshot for MEM
  logic          exmem_vm_q;        // vector mask-enable bit
  logic [4095:0] exmem_vec_idx_q;   // index group (indexed LS)
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
  logic        memwb_vec_we_q;    // vector load writeback in WB
  logic [4:0]  memwb_vec_rd_q;
  logic [3:0]  memwb_vec_wnum_q;
  logic [4095:0] memwb_vec_data_q;

  logic        wb_write;
  // A vector load writes the VRF from WB and completes in
  // MEM the cycle before; a vector op in EX in either cycle
  // would read or write stale state, so EX holds across both
  // (bubbles into EX/MEM, front stages frozen).
  assign vec_wb_stall = (memwb_vec_we_q || vls_vrf_we) &&
                        idex_valid_q && idex_ctrl_q.vec && !idex_exc_q;
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
  assign ex_mc_busy = fpu_req && !fpu_done;
  // EX holds for a busy multi-cycle unit or a vector op waiting
  // on a vector-load VRF write.
  assign ex_hold = vec_wb_stall || ex_mc_busy;
  // EX contents move to EX/MEM this cycle.
  assign ex_advance = !trap_take && !freeze && !mem_stall && !ex_hold;

  muserisc_fpu u_fpu (
      .clk_i     (clk_i),
      .rst_ni    (rst_ni),
      .req_i     (fpu_req),
      .ack_i     (ex_advance),
      .kill_i    (trap_take),
      .done_o    (fpu_done),
      .op_i      (idex_ctrl_q.fpu_op),
      .fmt_d_i   (idex_ctrl_q.fmt_d),
      .rm_i      (fpu_rm),
      .a_i       (idex_ctrl_q.fp_rs1 ? ex_frs1 : ex_rs1),
      .b_i       (ex_frs2),
      .c_i       (ex_frs3),
      .aux_i     (idex_ctrl_q.fpu_aux),
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

  // Vector datapath (stage 8a): register groups are read in
  // EX from the raw instruction fields, executed combinationally,
  // and committed at the EX edge under the same !mem_exc /
  // !mem_stall gating as CSR writes, keeping traps precise.
  logic [1:0]    csr_vec_vs;
  /* verilator lint_off UNUSEDSIGNAL */  // vtype[62:8] read zero
  logic [63:0]   csr_vtype;
  /* verilator lint_on UNUSEDSIGNAL */
  logic [63:0]   csr_vl, csr_vstart, csr_vset_vl;
  logic [4095:0] vec_vs2, vec_vs1, vec_old_vd, vec_result;
  logic [511:0]  vec_v0;
  logic [63:0]   vec_scalar;
  logic          vec_we, vec_illegal, vec_align_bad;
  logic [2:0]    vec_wlmul;
  logic [63:0]   vset_avl, vset_vtype_raw, vec_vlmax;
  logic [1:0]    csr_vxrm;
  logic          vset_en, vec_sat;
  logic [4:0]    vec_fflags;
  // FP vector ops accrue fflags and dirty FS on commit,
  // under the same precise-trap gating as vxsat.
  assign vec_fflags_we = idex_valid_q && idex_ctrl_q.vec &&
      (idex_ctrl_q.bext_op >= VOP_FBIN) &&
      (idex_ctrl_q.bext_op <= VOP_FMVFS) &&
      !idex_exc_q && !vec_illegal && !trap_fire &&
      !mem_exc && !mem_stall && !vec_wb_stall;
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
  // VRF write group size for EX-executed vector ops.
  always_comb begin
    if (idex_ctrl_q.bext_op == VOP_MVR) begin
      vec_wlmul = (idex_instr_q[19:15] == 5'd1) ? 3'd1 :
                  (idex_instr_q[19:15] == 5'd3) ? 3'd2 :
                  (idex_instr_q[19:15] == 5'd7) ? 3'd3 : 3'd0;
    end else if (ex_is_mask_dest ||
                 (idex_ctrl_q.bext_op == VOP_RED) ||
                 (idex_ctrl_q.bext_op == VOP_WRED) ||
                 (idex_ctrl_q.bext_op == VOP_FRED) ||
                 (idex_ctrl_q.bext_op == VOP_FWRED)) begin
      vec_wlmul = 3'd0;
    end else begin
      vec_wlmul = (ex_vd_log2 < 0) ? 3'd0 : ex_vd_log2[2:0];
    end
  end
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
                   !vec_wb_stall;
  // Vector loads complete through the MEM sequencer/WB path;
  // they must not also write the (garbage) EX vec result.
  assign vec_we = idex_valid_q && idex_ctrl_q.vec_rd && !idex_exc_q &&
                  !idex_ctrl_q.mem_read && !idex_ctrl_q.mem_write &&
                  !vec_illegal && !trap_fire && !mem_exc && !mem_stall &&
                  !vec_wb_stall;

  muserisc_vregfile u_vregfile (
      .clk_i     (clk_i),
      .raddr_a_i (idex_instr_q[24:20]),
      .rdata_a_o (vec_vs2),
      .raddr_b_i (idex_instr_q[19:15]),
      .rdata_b_o (vec_vs1),
      .raddr_c_i (idex_rd_q),
      .rdata_c_o (vec_old_vd),
      .v0_o      (vec_v0),
      .we_i      (vec_we || memwb_vec_we_q),
      .waddr_i   (memwb_vec_we_q ? memwb_vec_rd_q : idex_rd_q),
      .wnum_i    (memwb_vec_we_q ? memwb_vec_wnum_q
                                 : (4'd1 << vec_wlmul)),
      .wdata_i   (memwb_vec_we_q ? memwb_vec_data_q : vec_result)
  );

  muserisc_vec u_vec (
      .op_i      (idex_ctrl_q.bext_op),
      .form_i    (idex_ctrl_q.fpu_aux),
      .sew_i     (csr_vtype[5:3]),
      .vl_i      (csr_vl),
      .vstart_i  (csr_vstart),
      .vlmax_i   (vec_vlmax),
      .vxrm_i    (csr_vxrm),
      .frm_i     (csr_frm),
      .fflags_o  (vec_fflags),
      .sat_o     (vec_sat),
      .vta_i     (csr_vtype[6]),
      .vma_i     (csr_vtype[7]),
      .vm_i      (idex_instr_q[25]),
      .mask_i    (vec_v0),
      .vs2_i     (vec_vs2),
      .vs1_i     (vec_vs1),
      .old_vd_i  (vec_old_vd),
      // FP vector .vf forms read the scalar from the FP
      // register file; integer .vx forms use the GPR value.
      .scalar_i  (idex_ctrl_q.fp_rs1 ? ex_frs1 : ex_rs1),
      .imm_i     (idex_imm_q),
      .result_o  (vec_result),
      .scalar_o  (vec_scalar)
  );

  logic [63:0] bext_result;
  muserisc_bext u_bext (
      .op_i      (idex_ctrl_q.bext_op[5:0]),
      .a_i       (ex_rs1),
      .b_i       (idex_ctrl_q.alu_src_imm ? idex_imm_q : ex_rs2),
      .result_o  (bext_result)
  );

  muserisc_muldiv u_muldiv (
      .funct3_i  (idex_ctrl_q.funct3),
      .word_op_i (idex_ctrl_q.word_op),
      .a_i       (ex_rs1),
      .b_i       (ex_rs2),
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
                  !trap_fire && !mem_exc && !mem_stall &&
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
  // SFENCE/HFENCE and xRET serialize: redirect and flush.
  assign ex_serialize = ex_ret ||
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
    else if (idex_ctrl_q.sfence || idex_ctrl_q.hfence)
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

  // ---- Vector load/store sequencer (stages 8b/8c) ----
  // All classes (unit-stride, strided, indexed, whole-
  // register, fault-only-first) iterate one element per
  // completed memory cycle through the existing MMU/PMP
  // path. Masked-off elements are skipped without an
  // access. On a fault the elements before it commit and
  // vstart is set to the faulting index (resumable traps);
  // fault-only-first loads instead trim vl and do not trap
  // unless the first accessed element faults.
  logic        vls_is, vls_has_cur, vls_more, vls_elem_done, vls_done;
  logic        vls_whole, vls_strided, vls_indexed, vls_ff, vls_maskls;
  logic        vls_started_q, vls_any_done_q;
  logic [63:0] vls_idx_q, vls_cur, vls_addr, vls_index;
  logic [63:0] vls_vl_eff, vls_start_eff, vls_vl_merge;
  logic        vls_vm_eff, vls_misalign, vls_ff_trim;
  logic [4095:0] vls_data_q;
  logic [2:0]  vls_eew_code, vls_idx_eew;
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
  assign vls_start_eff = vls_whole ? 64'd0 : csr_vstart;
  assign vls_vm_eff = (vls_whole || vls_maskls) ? 1'b1 : exmem_vm_q;
  logic [63:0] vls_idx_eff;
  assign vls_idx_eff = vls_started_q ? vls_idx_q : vls_start_eff;
  always_comb begin
    vls_cur = vls_vl_eff;
    vls_has_cur = 1'b0;
    vls_more = 1'b0;
    for (int i = 0; i < 512; i++) begin
      if ((64'(unsigned'(i)) >= vls_idx_eff) &&
          (64'(unsigned'(i)) < vls_vl_eff) &&
          (vls_vm_eff || exmem_vec_mask_q[i])) begin
        if (!vls_has_cur) begin
          vls_cur = 64'(unsigned'(i));
          vls_has_cur = 1'b1;
        end else begin
          vls_more = 1'b1;
        end
      end
    end
  end
  always_comb begin
    unique case (vls_idx_eew)
      3'd0: vls_index = {56'd0, exmem_vec_idx_q[vls_cur[8:0]*8 +: 8]};
      3'd1: vls_index = {48'd0, exmem_vec_idx_q[vls_cur[7:0]*16 +: 16]};
      3'd2: vls_index = {32'd0, exmem_vec_idx_q[vls_cur[6:0]*32 +: 32]};
      default: vls_index = exmem_vec_idx_q[vls_cur[5:0]*64 +: 64];
    endcase
  end
  // Segments (nf>0, non-whole classes) iterate fields
  // inside each element; field f of element i lives in
  // memory right after field f-1 and in the register file
  // at bit f*EMUL*VLEN + i*EEW of the destination span.
  logic        vls_seg;
  logic [3:0]  vls_nfields, vls_field_stride;
  logic [2:0]  vls_field_q, vls_field;
  logic [11:0] vls_bitpos;
  assign vls_seg = !vls_whole && (exmem_vec_nf_q != 3'd0);
  assign vls_nfields = vls_seg
      ? ({1'b0, exmem_vec_nf_q} + 4'd1) : 4'd1;
  // Whole-register transfers span nf+1 consecutive
  // registers as a single field.
  assign vls_field_stride = vls_whole
      ? ({1'b0, exmem_vec_nf_q} + 4'd1)
      : (4'd1 << ((vls_emul_log2 < 0) ? 3'd0 : vls_emul_log2[2:0]));
  assign vls_field = vls_started_q ? vls_field_q : 3'd0;
  always_comb begin
    unique case (vls_eew_code)
      3'd0: vls_bitpos = 12'(vls_field * vls_field_stride * 512) +
                         12'(vls_cur[8:0] * 8);
      3'd1: vls_bitpos = 12'(vls_field * vls_field_stride * 512) +
                         12'(vls_cur[7:0] * 16);
      3'd2: vls_bitpos = 12'(vls_field * vls_field_stride * 512) +
                         12'(vls_cur[6:0] * 32);
      default: vls_bitpos = 12'(vls_field * vls_field_stride * 512) +
                            12'(vls_cur[5:0] * 64);
    endcase
  end
  assign vls_addr = (vls_strided
      ? (exmem_addr_q + vls_cur * exmem_vec_stride_q)
      : vls_indexed ? (exmem_addr_q + vls_index)
                    : (exmem_addr_q +
                       vls_cur * {60'd0, vls_nfields} *
                       (64'd1 << vls_eew_code))) +
      ({61'd0, vls_field} << vls_eew_code);
  logic [63:0] mem_va;
  assign mem_va = vls_is ? vls_addr : exmem_addr_q;
  assign vls_misalign = vls_is && vls_has_cur &&
      (((vls_eew_code == 3'd1) && vls_addr[0]) ||
       ((vls_eew_code == 3'd2) && |vls_addr[1:0]) ||
       ((vls_eew_code == 3'd3) && |vls_addr[2:0]));
  assign vls_elem_done = vls_is && vls_has_cur && !vls_misalign &&
                         mmu_d_ok && pmp_allow_data &&
                         !(|mmu_d_pa[63:56]);
  // Fault-only-first: a fault after at least one completed
  // element trims vl to the faulting index, no trap.
  logic vls_fault_raw;
  assign vls_fault_raw = vls_is &&
      (mem_trans_fault || mem_pmp_fault || vls_misalign);
  assign vls_ff_trim = vls_ff && vls_fault_raw && vls_any_done_q &&
                       (!vls_seg || (vls_cur > vls_start_eff));
  assign vls_vl_merge = vls_ff_trim ? vls_cur : vls_vl_eff;
  assign vls_done = vls_is &&
                    (vls_ff_trim || !vls_has_cur ||
                     (vls_elem_done && !vls_more &&
                      (vls_field == (vls_nfields[2:0] - 3'd1))));
  // Captured load data including the element completing now.
  logic [4095:0] vls_cap_base, vls_cap_next, vls_merged;
  assign vls_cap_base = vls_started_q ? vls_data_q : exmem_vec_data_q;
  always_comb begin
    vls_cap_next = vls_cap_base;
    if (vls_elem_done && exmem_ctrl_q.mem_read) begin
      unique case (vls_eew_code)
        3'd0: vls_cap_next[vls_bitpos +: 8] = load_shifted[7:0];
        3'd1: vls_cap_next[vls_bitpos +: 16] = load_shifted[15:0];
        3'd2: vls_cap_next[vls_bitpos +: 32] = load_shifted[31:0];
        default: vls_cap_next[vls_bitpos +: 64] = load_shifted;
      endcase
    end
  end
  // Final (or partial-fault) destination merge at EEW,
  // field by field for segment forms.
  always_comb begin
    logic [63:0] cap_el;
    logic [11:0] mpos;
    int mpos_full;
    vls_merged = exmem_vec_data_q;
    for (int i = 0; i < 512; i++) begin
     for (int f = 0; f < 8; f++) begin
      mpos_full = f * int'(vls_field_stride) * 512 +
                  (i << (vls_eew_code + 3));
      if ((f < vls_nfields) && (mpos_full < 4096) &&
          (64'(unsigned'(i)) >= vls_start_eff) &&
          (i < (512 >> vls_eew_code)) &&
          // Stay inside this field's register group.
          (i < (int'(vls_field_stride) * 512 >>
                (vls_eew_code + 3)))) begin
        mpos = 12'(mpos_full);
        cap_el = 64'd0;
        unique case (vls_eew_code)
          3'd0: cap_el = {56'd0, vls_cap_next[mpos +: 8]};
          3'd1: cap_el = {48'd0, vls_cap_next[mpos +: 16]};
          3'd2: cap_el = {32'd0, vls_cap_next[mpos +: 32]};
          default: cap_el = vls_cap_next[mpos +: 64];
        endcase
        if ((64'(unsigned'(i)) < vls_vl_merge) &&
            (vls_vm_eff || exmem_vec_mask_q[i]) &&
            // On a fault only elements before it have data.
            ((vls_done && !vls_ff_trim) ||
             (64'(unsigned'(i)) < vls_cur))) begin
          unique case (vls_eew_code)
            3'd0: vls_merged[mpos +: 8] = cap_el[7:0];
            3'd1: vls_merged[mpos +: 16] = cap_el[15:0];
            3'd2: vls_merged[mpos +: 32] = cap_el[31:0];
            default: vls_merged[mpos +: 64] = cap_el;
          endcase
        end
        // Elements not written above keep the old vd value
        // (agnostic = undisturbed in this implementation).
      end
     end
    end
  end
  // EMUL for the destination group: (EEW/SEW)*LMUL. The
  // write count is the register span (fields * group size
  // for segments, nf+1 for whole-register transfers).
  logic [3:0] vls_wnum;
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
  assign vls_wnum = vls_whole ? ({1'b0, exmem_vec_nf_q} + 4'd1)
                              : (vls_nfields * vls_field_stride);
  logic vls_fault;
  assign vls_fault = vls_fault_raw && !vls_ff_trim;
  assign vls_vrf_we = exmem_ctrl_q.mem_read && (vls_done || vls_fault);

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      vls_started_q <= 1'b0;
      vls_any_done_q <= 1'b0;
      vls_field_q <= 3'd0;
      vls_idx_q <= 64'd0;
      vls_data_q <= '0;
    end else if (!vls_is || vls_done || vls_fault) begin
      vls_started_q <= 1'b0;
      vls_any_done_q <= 1'b0;
      vls_field_q <= 3'd0;
      if (vls_elem_done) vls_data_q <= vls_cap_next;
    end else if (!vls_started_q) begin
      vls_started_q <= 1'b1;
      vls_any_done_q <= vls_elem_done;
      vls_field_q <= (vls_elem_done &&
                      (3'd0 < (vls_nfields[2:0] - 3'd1))) ? 3'd1 : 3'd0;
      vls_idx_q <= vls_elem_done && (vls_nfields == 4'd1)
                   ? (vls_cur + 64'd1) : vls_start_eff;
      vls_data_q <= vls_cap_next;
    end else if (vls_elem_done) begin
      vls_any_done_q <= 1'b1;
      vls_data_q <= vls_cap_next;
      if (vls_field_q < (vls_nfields[2:0] - 3'd1)) begin
        vls_field_q <= vls_field_q + 3'd1;
      end else begin
        vls_field_q <= 3'd0;
        vls_idx_q <= vls_cur + 64'd1;
      end
    end
  end

  // A translation miss parks the access in MEM (pipeline hold);
  // a translation fault or a PMP denial on the PA excepts it.
  assign data_access = exmem_valid_q && !exmem_exc_q &&
                       (exmem_ctrl_q.mem_read || exmem_ctrl_q.mem_write) &&
                       (!vls_is || vls_has_cur);
  assign mem_stall = (data_access && !mmu_d_ok && !mmu_d_fault) ||
                     (vls_is && !vls_done && !vls_fault) ||
                     (data_access && mmu_d_ok && !vls_is &&
                      dmem_stall_i);
  assign mem_trans_fault = data_access && mmu_d_fault;
  // PMP denial, or a physical address outside the 56-bit map.
  assign mem_pmp_fault = data_access && mmu_d_ok &&
                         (!pmp_allow_data || |mmu_d_pa[63:56]);
  assign mem_uses_port = data_access && mmu_d_ok && !mem_pmp_fault &&
                         !vls_misalign;
  // The walker borrows the port whenever MEM is not using it.
  assign walk_grant = walk_req && !mem_uses_port;
  assign dmem_addr_o = walk_grant ? walk_addr : mmu_d_pa;
  assign dmem_re_o = mem_uses_port && exmem_ctrl_q.mem_read;

  logic        res_valid_q;
  logic [63:0] res_pa_q;
  logic        res_is_d_q;  // reserved access size: 1 = 8B, 0 = 4B
  assign load_shifted = dmem_rdata_i >> {mem_va[2:0], 3'b000};

  // AMO read-modify-write, executed in MEM against the loaded
  // value (combinational memory: read and write are one cycle).
  logic [63:0] eff_store_data;
  logic        sc_success;
  always_comb begin
    logic [31:0] a32, b32, r32;
    logic [63:0] r64;
    a32 = load_shifted[31:0];
    b32 = exmem_store_data_q[31:0];
    unique case (exmem_ctrl_q.amo_op)
      5'b00000: begin  // AMOADD
        r32 = a32 + b32;
        r64 = load_shifted + exmem_store_data_q;
      end
      5'b00100: begin  // AMOXOR
        r32 = a32 ^ b32;
        r64 = load_shifted ^ exmem_store_data_q;
      end
      5'b01000: begin  // AMOOR
        r32 = a32 | b32;
        r64 = load_shifted | exmem_store_data_q;
      end
      5'b01100: begin  // AMOAND
        r32 = a32 & b32;
        r64 = load_shifted & exmem_store_data_q;
      end
      5'b10000: begin  // AMOMIN
        r32 = ($signed(a32) < $signed(b32)) ? a32 : b32;
        r64 = ($signed(load_shifted) < $signed(exmem_store_data_q))
              ? load_shifted : exmem_store_data_q;
      end
      5'b10100: begin  // AMOMAX
        r32 = ($signed(a32) > $signed(b32)) ? a32 : b32;
        r64 = ($signed(load_shifted) > $signed(exmem_store_data_q))
              ? load_shifted : exmem_store_data_q;
      end
      5'b11000: begin  // AMOMINU
        r32 = (a32 < b32) ? a32 : b32;
        r64 = (load_shifted < exmem_store_data_q)
              ? load_shifted : exmem_store_data_q;
      end
      5'b11100: begin  // AMOMAXU
        r32 = (a32 > b32) ? a32 : b32;
        r64 = (load_shifted > exmem_store_data_q)
              ? load_shifted : exmem_store_data_q;
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
      // Vector store element at the sequencer index.
      unique case (vls_eew_code)
        3'd0: eff_store_data =
            {56'd0, exmem_vec_data_q[vls_bitpos +: 8]};
        3'd1: eff_store_data =
            {48'd0, exmem_vec_data_q[vls_bitpos +: 16]};
        3'd2: eff_store_data =
            {32'd0, exmem_vec_data_q[vls_bitpos +: 32]};
        default: eff_store_data = exmem_vec_data_q[vls_bitpos +: 64];
      endcase
    end
  end
  // "Reserve exactly enough to cover the access": an SC
  // succeeds iff its whole access lies within the LR's range.
  assign sc_success = res_valid_q && (res_pa_q == mmu_d_pa) &&
                      (res_is_d_q || (exmem_ctrl_q.funct3 == 3'b010));

  always_comb begin
    dmem_be_o = 8'd0;
    dmem_wdata_o = 64'd0;
    if (walk_grant && walk_we) begin
      // PTE A/D writeback (suppressed on PMP denial; the MMU
      // turns that into an access fault for the requester).
      dmem_be_o = pmp_allow_walk ? 8'hFF : 8'd0;
      dmem_wdata_o = walk_wdata;
    end else if (mem_uses_port && exmem_ctrl_q.mem_write && !trap_fire &&
                 (!exmem_ctrl_q.sc || sc_success)) begin
      unique case (vls_is ? vls_eew_code[1:0]
                          : exmem_ctrl_q.funct3[1:0])
        2'b00: begin
          dmem_be_o = 8'h01 << mem_va[2:0];
          dmem_wdata_o = {8{eff_store_data[7:0]}};
        end
        2'b01: begin
          dmem_be_o = 8'h03 << {mem_va[2:1], 1'b0};
          dmem_wdata_o = {4{eff_store_data[15:0]}};
        end
        2'b10: begin
          dmem_be_o = 8'h0F << {mem_va[2], 2'b00};
          dmem_wdata_o = {2{eff_store_data[31:0]}};
        end
        default: begin
          dmem_be_o = 8'hFF;
          dmem_wdata_o = eff_store_data;
        end
      endcase
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
      .vec_dirty_i   (vec_we || memwb_vec_we_q),
      .vstart_we_i   (vls_fault),
      .vstart_wdata_i(vls_cur),
      .vl_we_i       (vls_ff_trim),
      .vl_wdata_i    (vls_cur),
      .vxrm_o        (csr_vxrm),
      .vxsat_set_i   (vec_sat && idex_valid_q && idex_ctrl_q.vec &&
                      !idex_exc_q && !vec_illegal && !trap_fire &&
                      !mem_exc && !mem_stall && !vec_wb_stall),
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
      .walk_rdata_i     (dmem_rdata_i),
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
      exmem_vec_data_q <= '0;
      exmem_vec_mask_q <= '0;
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
      memwb_vec_we_q <= vls_vrf_we;
      memwb_vec_rd_q <= exmem_rd_q;
      memwb_vec_wnum_q <= vls_wnum;
      memwb_vec_data_q <= vls_merged;
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
      exmem_vec_data_q <= vec_old_vd;
      exmem_vec_mask_q <= vec_v0;
      exmem_vm_q <= idex_instr_q[25];
      exmem_vec_idx_q <= vec_vs2;
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
