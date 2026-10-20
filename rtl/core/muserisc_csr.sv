// Privileged state for the in-house core (issue #18 stage 3):
// M/S/U CSRs, precise trap entry/return, interrupt selection with
// delegation, cycle/instret counters, and 16 PMP entries.
//
// Contract with the pipeline (docs/CORE.md):
// - CSR reads are combinational in EX; writes commit on the
//   EX->MEM edge (wr_en_i), so a following instruction in EX reads
//   the new value next cycle. xRET side effects apply on the same
//   edge; trap entry applies on the WB edge (trap_take_i).
// - Current privilege changes only through trap entry / xRET,
//   both of which flush the pipeline, so priv_o always names the
//   privilege of every instruction currently in flight.
// - satp is stored here; translation itself lives in the MMU.
`default_nettype none
module muserisc_csr (
    input  wire        clk_i,
    input  wire        rst_ni,
    // CSR read/write port (EX)
    input  wire [11:0] addr_i,
    output logic [63:0] rdata_o,
    // Old value for CSRRS/CSRRC read-modify-write. Equals rdata_o
    // except for mip, where SEIP/STIP are the software-writable
    // bits only: the external pins must not be latched into them
    // (priv spec, mip: RMW uses the software SEIP bit).
    output logic [63:0] rmw_rdata_o,
    output logic       illegal_o,     // access faults as illegal-instr
    input  wire        wr_en_i,       // commit wdata_i at the next edge
    input  wire [63:0] wdata_i,
    // Privileged-instruction legality helpers (EX)
    output logic       sys_illegal_o, // mret/sret/wfi/sfence not allowed now
    input  wire [2:0]  sys_op_i,      // 0 none 1 mret 2 sret 3 wfi 4 sfence
                                      // 5 hfence.vvma 6 hfence.gvma 7 hlv
    input  wire        ret_en_i,      // xRET takes effect at the next edge
    // Trap entry (WB)
    input  wire        trap_take_i,
    input  wire [63:0] trap_cause_i,  // full xcause value (bit63 = interrupt)
    input  wire [63:0] trap_pc_i,
    input  wire [63:0] trap_tval_i,
    input  wire [63:0] trap_gpa_i,   // faulting GPA for htval/mtval2
    input  wire        trap_gva_i,   // HLV fault: tval holds a guest VA
    input  wire [63:0] trap_tinst_i, // transformed instr (0 = none)
    output logic [63:0] trap_target_o,
    output logic [1:0] trap_priv_o,   // privilege the trap is taken to
    // Interrupt injection (sampled in ID)
    output logic       irq_valid_o,
    output logic [63:0] irq_cause_o,  // full xcause value (interrupt bit set)
    // External interrupt pins
    input  wire        irq_m_timer_i,
    input  wire        irq_m_soft_i,
    input  wire        irq_m_ext_i,
    input  wire        irq_s_timer_i,
    input  wire        irq_s_ext_i,
    // State outputs
    output logic [1:0] priv_o,       // nominal privilege (U/S/M)
    output logic       virt_o,       // virtualization mode V
    output logic       dvirt_o,      // effective V for data (MPRV/MPV)
    output logic       virt_inst_o,  // current CSR op wants cause 22
    output logic       sum_o,        // effective data SUM (VS if V=1)
    output logic       mxr_o,        // effective data MXR (VS if V=1)
    output logic       hs_mxr_o,     // HS MXR (overrides G-stage X)
    output logic [63:0] satp_o,      // effective data satp/vsatp
    output logic [63:0] fsatp_o,     // fetch satp for the current V
    output logic [63:0] vsatp_o,     // raw vsatp (HLV data context)
    output logic       spvp_o,       // hstatus.SPVP (HLV privilege)
    output logic       vs_sum_o,     // vsstatus.SUM (HLV)
    output logic       vs_mxr_o,     // vsstatus.MXR (HLV stage 1)
    output logic [63:0] hgatp_o,
    output logic [63:0] mstatus_o,
    output logic [63:0] xret_pc_o,    // mepc or sepc per sys_op_i
    input  wire        retire_i,      // an instruction retired in WB
    output logic [2:0] frm_o,
    output logic [1:0] fs_o,
    input  wire        fflags_we_i,   // OR flags from the FPU
    input  wire [4:0]  fflags_i,
    input  wire        fp_dirty_i,    // an FP reg write commits
    // Vector state (stage 8)
    output logic [1:0] vec_vs_o,      // effective mstatus.VS
    output logic [63:0] vtype_o,
    output logic [63:0] vl_o,
    output logic [63:0] vstart_o,
    output logic [63:0] vset_vl_o,    // vl result of a vset in EX
    input  wire        vset_en_i,     // a vset instruction commits
    input  wire [63:0] vset_avl_i,
    input  wire [63:0] vset_vtype_i,  // raw requested vtype value
    input  wire        vset_keep_vl_i, // rd==x0 && rs1==x0 form
    input  wire        vset_vlmax_i,  // rs1==x0 && rd!=x0 form
    input  wire        vec_dirty_i,   // a vector reg write commits
    input  wire        vstart_we_i,   // faulting vector LS sets vstart
    input  wire [63:0] vstart_wdata_i,
    input  wire        vl_we_i,       // fault-only-first trims vl
    input  wire [63:0] vl_wdata_i,
    output logic [1:0] vxrm_o,        // fixed-point rounding mode
    input  wire        vxsat_set_i,   // a fixed-point op saturated
    // PMP checks (physical addresses, combinational)
    input  wire [63:0] pmp_addr_a_i,
    input  wire [1:0]  pmp_acc_a_i,   // 0 read 1 write 2 exec
    input  wire [1:0]  pmp_priv_a_i,
    output logic       pmp_allow_a_o,
    input  wire [63:0] pmp_addr_b_i,
    input  wire [1:0]  pmp_acc_b_i,
    input  wire [1:0]  pmp_priv_b_i,
    output logic       pmp_allow_b_o,
    input  wire [63:0] pmp_addr_c_i,
    input  wire [1:0]  pmp_acc_c_i,
    input  wire [1:0]  pmp_priv_c_i,
    output logic       pmp_allow_c_o
);
  localparam logic [1:0] PRIV_U = 2'b00, PRIV_S = 2'b01, PRIV_M = 2'b11;

  // ------------------------------------------------------------
  // Architectural state
  // ------------------------------------------------------------
  logic [1:0]  priv_q;
  // mstatus fields actually stored
  logic mstatus_mie_q, mstatus_sie_q, mstatus_mpie_q, mstatus_spie_q;
  logic mstatus_spp_q;
  logic [1:0] mstatus_mpp_q;
  logic mstatus_mprv_q, mstatus_sum_q, mstatus_mxr_q;
  logic mstatus_tvm_q, mstatus_tw_q, mstatus_tsr_q;
  logic [63:0] medeleg_q, mideleg_q, mie_q, mtvec_q, mcounteren_q;
  logic [4:0]  fflags_q;
  logic [2:0]  frm_q;
  logic [1:0]  mstatus_fs_q, mstatus_vs_q;
  // Vector architectural state (single set, not HS/VS banked).
  logic        vtype_vill_q, vtype_vma_q, vtype_vta_q;
  logic [2:0]  vtype_vsew_q, vtype_vlmul_q;
  logic [63:0] vl_q, vstart_q;
  logic        vxsat_q;
  logic [1:0]  vxrm_q;
  logic [63:0] mscratch_q, mepc_q, mcause_q, mtval_q;
  logic        mip_ssip_q, mip_seip_q, mip_stip_q;
  logic [63:0] menvcfg_q, mcountinhibit_q;
  logic [63:0] stvec_q, scounteren_q, sscratch_q, sepc_q, scause_q;
  logic [63:0] stval_q, senvcfg_q, satp_q;
  logic [63:0] mcycle_q, minstret_q, mtime_q;
  // Hypervisor (ext:h) state. priv_q stays nominal (U/S/M);
  // virt_q distinguishes VU/VS (V=1) from U/HS (V=0).
  logic        virt_q;
  logic        mstatus_mpv_q, mstatus_gva_q;
  logic        h_gva_q, h_spv_q, h_spvp_q, h_hu_q;
  logic        h_vtvm_q, h_vtw_q, h_vtsr_q;
  logic [63:0] hedeleg_q, hideleg_q, hvip_q, htimedelta_q;
  logic [63:0] hcounteren_q, henvcfg_q, htval_q, htinst_q, hgatp_q;
  logic [63:0] mtval2_q, mtinst_q;
  logic        vs_sie_q, vs_spie_q, vs_spp_q, vs_sum_q, vs_mxr_q;
  logic [1:0]  vs_fs_q, vs_vs_q;
  logic [63:0] vstvec_q, vsscratch_q, vsepc_q, vscause_q;
  logic [63:0] vstval_q, vsatp_q;
  logic [7:0]  pmpcfg_q [0:15];
  logic [63:0] pmpaddr_q [0:15];

  assign priv_o = priv_q;
  assign virt_o = virt_q;
  // Loads/stores in M-mode with MPRV=1, MPP!=M and MPV=1 execute
  // with VS/VU translation context even though fetch stays in M.
  assign dvirt_o = virt_q || ((priv_q == PRIV_M) && mstatus_mprv_q &&
                               (mstatus_mpp_q != PRIV_M) && mstatus_mpv_q);
  assign satp_o = dvirt_o ? vsatp_q : satp_q;
  assign fsatp_o = virt_q ? vsatp_q : satp_q;
  assign vsatp_o = vsatp_q;
  assign spvp_o = h_spvp_q;
  assign vs_sum_o = vs_sum_q;
  assign vs_mxr_o = vs_mxr_q;
  assign hgatp_o = hgatp_q;
  assign sum_o = dvirt_o ? vs_sum_q : mstatus_sum_q;
  assign mxr_o = dvirt_o ? vs_mxr_q : mstatus_mxr_q;
  assign hs_mxr_o = mstatus_mxr_q;

  // hstatus / vsstatus compositions.
  logic [63:0] hstatus_val, vsstatus_val;
  always_comb begin
    hstatus_val = 64'd0;
    hstatus_val[6] = h_gva_q;
    hstatus_val[7] = h_spv_q;
    hstatus_val[8] = h_spvp_q;
    hstatus_val[9] = h_hu_q;
    hstatus_val[20] = h_vtvm_q;
    hstatus_val[21] = h_vtw_q;
    hstatus_val[22] = h_vtsr_q;
    hstatus_val[33:32] = 2'd2;  // VSXL = 64 (read-only)
    vsstatus_val = 64'd0;
    vsstatus_val[1] = vs_sie_q;
    vsstatus_val[5] = vs_spie_q;
    vsstatus_val[8] = vs_spp_q;
    vsstatus_val[10:9] = vs_vs_q;
    vsstatus_val[14:13] = vs_fs_q;
    vsstatus_val[18] = vs_sum_q;
    vsstatus_val[19] = vs_mxr_q;
    vsstatus_val[33:32] = 2'd2;  // UXL = 64
    vsstatus_val[63] = (vs_fs_q == 2'b11) || (vs_vs_q == 2'b11);
  end

  // mstatus assembly (unlisted fields read zero).
  always_comb begin
    mstatus_o = 64'd0;
    mstatus_o[1]     = mstatus_sie_q;
    mstatus_o[3]     = mstatus_mie_q;
    mstatus_o[5]     = mstatus_spie_q;
    mstatus_o[7]     = mstatus_mpie_q;
    mstatus_o[8]     = mstatus_spp_q;
    mstatus_o[12:11] = mstatus_mpp_q;
    mstatus_o[17]    = mstatus_mprv_q;
    mstatus_o[18]    = mstatus_sum_q;
    mstatus_o[19]    = mstatus_mxr_q;
    mstatus_o[20]    = mstatus_tvm_q;
    mstatus_o[21]    = mstatus_tw_q;
    mstatus_o[22]    = mstatus_tsr_q;
    mstatus_o[38]    = mstatus_gva_q;
    mstatus_o[39]    = mstatus_mpv_q;
    mstatus_o[10:9]  = mstatus_vs_q;
    mstatus_o[14:13] = mstatus_fs_q;
    mstatus_o[63]    = (mstatus_fs_q == 2'b11) ||
                       (mstatus_vs_q == 2'b11);  // SD
    mstatus_o[35:34] = 2'b10;  // SXL = 64-bit
    mstatus_o[33:32] = 2'b10;  // UXL = 64-bit
  end

  localparam logic [63:0] SSTATUS_MASK =
      (64'd1 << 1) | (64'd1 << 5) | (64'd1 << 8) |
      (64'd3 << 9) | (64'd3 << 13) | (64'd1 << 18) | (64'd1 << 19) |
      (64'd3 << 32) | (64'd1 << 63);

  assign frm_o = frm_q;
  // In VM, FP is off if either status FS field is Off.
  assign fs_o = virt_q ? ((mstatus_fs_q == 2'd0 || vs_fs_q == 2'd0)
                              ? 2'd0 : vs_fs_q)
                       : mstatus_fs_q;
  assign vec_vs_o = virt_q ? ((mstatus_vs_q == 2'd0 || vs_vs_q == 2'd0)
                                  ? 2'd0 : vs_vs_q)
                           : mstatus_vs_q;
  assign vtype_o = {vtype_vill_q, 55'd0, vtype_vma_q, vtype_vta_q,
                    vtype_vsew_q, vtype_vlmul_q};
  assign vl_o = vl_q;
  assign vstart_o = vstart_q;
  assign vxrm_o = vxrm_q;

  // vsetvl* next-state computation (combinational; committed
  // in EX like other CSR writes). VLEN=512, ELEN=64.
  logic        vset_vill;
  logic [63:0] vset_vlmax;
  always_comb begin
    logic [12:0] group_bits;
    // VLMAX = LMUL*VLEN/SEW. Both factors are powers of two,
    // so the quotient is a right shift by log2(SEW) = vsew+3
    // (a division here synthesizes to a 64-bit divider).
    unique case (vset_vtype_i[2:0])
      3'd0: group_bits = 13'd512;
      3'd1: group_bits = 13'd1024;
      3'd2: group_bits = 13'd2048;
      3'd3: group_bits = 13'd4096;
      3'd5: group_bits = 13'd64;
      3'd6: group_bits = 13'd128;
      3'd7: group_bits = 13'd256;
      default: group_bits = 13'd0;
    endcase
    vset_vlmax = {51'd0, group_bits >> ({1'b0, vset_vtype_i[5:3]} + 4'd3)};
    // vill: reserved fields or SEW > ELEN. Fractional LMUL
    // with SEW/LMUL > ELEN (VLMAX < 8) is also supported.
    vset_vill = (vset_vtype_i[5:3] > 3'd3) ||
                (vset_vtype_i[2:0] == 3'd4) ||
                (vset_vtype_i[63:8] != 56'd0) || (vset_vlmax == 64'd0);
    if (vset_vill) begin
      vset_vl_o = 64'd0;
    end else if (vset_keep_vl_i) begin
      vset_vl_o = (vl_q < vset_vlmax) ? vl_q : vset_vlmax;
    end else if (vset_vlmax_i) begin
      vset_vl_o = vset_vlmax;
    end else begin
      vset_vl_o = (vset_avl_i < vset_vlmax) ? vset_avl_i : vset_vlmax;
    end
  end

  // mip assembly: pin-driven fields plus software SSIP/SEIP.
  logic [63:0] mip_val;
  always_comb begin
    mip_val = 64'd0;
    mip_val[1]  = mip_ssip_q;
    mip_val[2]  = hvip_q[2];    // VSSIP (alias of hip)
    mip_val[3]  = irq_m_soft_i;
    mip_val[5]  = irq_s_timer_i | mip_stip_q;
    mip_val[6]  = hvip_q[6];    // VSTIP
    mip_val[7]  = irq_m_timer_i;
    mip_val[9]  = irq_s_ext_i | mip_seip_q;
    mip_val[10] = hvip_q[10];   // VSEIP (GEILEN = 0)
    mip_val[11] = irq_m_ext_i;
  end

  // vsip/vsie are hideleg-gated aliases of hip/hie, translated
  // from VS interrupt codes (2/6/10) to S codes (1/5/9).
  logic [63:0] vsip_val, vsie_val;
  always_comb begin
    vsip_val = 64'd0;
    vsip_val[1] = hideleg_q[2] & hvip_q[2];
    vsip_val[5] = hideleg_q[6] & hvip_q[6];
    vsip_val[9] = hideleg_q[10] & hvip_q[10];
    vsie_val = 64'd0;
    vsie_val[1] = hideleg_q[2] & mie_q[2];
    vsie_val[5] = hideleg_q[6] & mie_q[6];
    vsie_val[9] = hideleg_q[10] & mie_q[10];
  end

  // ------------------------------------------------------------
  // Read mux + legality
  // ------------------------------------------------------------
  logic        csr_exists;
  logic [63:0] csr_rdata;
  // Composed pmpcfg views (RV64: cfg0 holds entries 0-7, cfg2 8-15).
  logic [63:0] pmpcfg0_val, pmpcfg2_val;
  always_comb begin
    for (int i = 0; i < 8; i++) begin
      pmpcfg0_val[i*8 +: 8] = pmpcfg_q[i];
      pmpcfg2_val[i*8 +: 8] = pmpcfg_q[i+8];
    end
  end

  always_comb begin
    csr_exists = 1'b1;
    csr_rdata = 64'd0;
    unique case (addr_i)
      12'h001: csr_rdata = {59'd0, fflags_q};                     // fflags
      12'h002: csr_rdata = {61'd0, frm_q};                        // frm
      12'h003: csr_rdata = {56'd0, frm_q, fflags_q};              // fcsr
      12'h008: csr_rdata = vstart_q;                              // vstart
      12'h009: csr_rdata = {63'd0, vxsat_q};                      // vxsat
      12'h00A: csr_rdata = {62'd0, vxrm_q};                       // vxrm
      12'h00F: csr_rdata = {61'd0, vxrm_q, vxsat_q};              // vcsr
      12'h100: csr_rdata = virt_q ? vsstatus_val :
                           (mstatus_o & SSTATUS_MASK);          // sstatus
      12'h104: csr_rdata = virt_q ? vsie_val :
                           (mie_q & mideleg_q & 64'hAAA);       // sie
      12'h105: csr_rdata = virt_q ? vstvec_q : stvec_q;           // stvec
      12'h106: csr_rdata = scounteren_q;                          // scounteren
      12'h10A: csr_rdata = senvcfg_q;                             // senvcfg
      12'h140: csr_rdata = virt_q ? vsscratch_q : sscratch_q;     // sscratch
      12'h141: csr_rdata = virt_q ? vsepc_q : sepc_q;             // sepc
      12'h142: csr_rdata = virt_q ? vscause_q : scause_q;         // scause
      12'h143: csr_rdata = virt_q ? vstval_q : stval_q;           // stval
      12'h144: csr_rdata = virt_q ? vsip_val :
                           (mip_val & mideleg_q & 64'hAAA);     // sip
      12'h180: csr_rdata = virt_q ? vsatp_q : satp_q;             // satp
      12'h200: csr_rdata = vsstatus_val;                          // vsstatus
      12'h204: csr_rdata = vsie_val;                              // vsie
      12'h205: csr_rdata = vstvec_q;                              // vstvec
      12'h240: csr_rdata = vsscratch_q;                           // vsscratch
      12'h241: csr_rdata = vsepc_q;                               // vsepc
      12'h242: csr_rdata = vscause_q;                             // vscause
      12'h243: csr_rdata = vstval_q;                              // vstval
      12'h244: csr_rdata = vsip_val;                              // vsip
      12'h280: csr_rdata = vsatp_q;                               // vsatp
      12'h600: csr_rdata = hstatus_val;                           // hstatus
      12'h602: csr_rdata = hedeleg_q;                             // hedeleg
      12'h603: csr_rdata = hideleg_q;                             // hideleg
      12'h604: csr_rdata = mie_q & 64'h444;                       // hie
      12'h605: csr_rdata = htimedelta_q;                          // htimedelta
      12'h606: csr_rdata = hcounteren_q;                          // hcounteren
      12'h607: csr_rdata = 64'd0;                                 // hgeie
      12'h60A: csr_rdata = henvcfg_q;                             // henvcfg
      12'h643: csr_rdata = htval_q;                               // htval
      12'h644: csr_rdata = hvip_q & 64'h444;                      // hip
      12'h645: csr_rdata = hvip_q;                                // hvip
      12'h64A: csr_rdata = htinst_q;                              // htinst
      12'h680: csr_rdata = hgatp_q;                               // hgatp
      12'hE12: csr_rdata = 64'd0;                                 // hgeip
      12'h300: csr_rdata = mstatus_o;                             // mstatus
      12'h301: csr_rdata = 64'h8000_0000_0034_11AF;               // misa: RV64 IMABC FDHV SU
      12'h302: csr_rdata = medeleg_q;                             // medeleg
      12'h303: csr_rdata = mideleg_q | 64'h444;  // VS ints always delegated                             // mideleg
      12'h304: csr_rdata = mie_q;                                 // mie
      12'h305: csr_rdata = mtvec_q;                               // mtvec
      12'h306: csr_rdata = mcounteren_q;                          // mcounteren
      12'h30A: csr_rdata = menvcfg_q;                             // menvcfg
      12'h320: csr_rdata = mcountinhibit_q;                       // mcountinhibit
      12'h340: csr_rdata = mscratch_q;                            // mscratch
      12'h341: csr_rdata = mepc_q;                                // mepc
      12'h342: csr_rdata = mcause_q;                              // mcause
      12'h343: csr_rdata = mtval_q;                               // mtval
      12'h344: csr_rdata = mip_val;                               // mip
      12'h34A: csr_rdata = mtinst_q;                              // mtinst
      12'h34B: csr_rdata = mtval2_q;                              // mtval2
      12'h3A0: csr_rdata = pmpcfg0_val;                           // pmpcfg0
      12'h3A2: csr_rdata = pmpcfg2_val;                           // pmpcfg2
      12'hB00: csr_rdata = mcycle_q;                              // mcycle
      12'hB02: csr_rdata = minstret_q;                            // minstret
      12'hC00: csr_rdata = mcycle_q;                              // cycle
      12'hC01: csr_rdata = virt_q ? (mtime_q + htimedelta_q) : mtime_q;  // time
      12'hC02: csr_rdata = minstret_q;                            // instret
      12'hC20: csr_rdata = vl_q;                                  // vl
      12'hC21: csr_rdata = vtype_o;                               // vtype
      12'hC22: csr_rdata = 64'd64;                                // vlenb
      12'hF11: csr_rdata = 64'd0;                                 // mvendorid
      12'hF12: csr_rdata = 64'h4D55_5345;                         // marchid "MUSE"
      12'hF13: csr_rdata = 64'h0003_0000;                         // mimpid
      12'hF14: csr_rdata = 64'd0;                                 // mhartid
      12'hF15: csr_rdata = 64'd0;                                 // mconfigptr
      default: begin
        if ((addr_i >= 12'h3B0) && (addr_i <= 12'h3BF)) begin
          csr_rdata = pmpaddr_q[addr_i[3:0]];
        end else if ((addr_i >= 12'hB03) && (addr_i <= 12'hB1F)) begin
          csr_rdata = 64'd0;                                      // mhpmcounter3-31
        end else if ((addr_i >= 12'h323) && (addr_i <= 12'h33F)) begin
          csr_rdata = 64'd0;                                      // mhpmevent3-31
        end else if (((addr_i >= 12'h7A0) && (addr_i <= 12'h7A5)) ||
                     (addr_i == 12'h7A8) || (addr_i == 12'h7AA) ||
                     (addr_i == 12'h5A8)) begin
          // Sdtrig trigger CSRs, zero triggers implemented:
          // tselect/tdata*/tinfo/tcontrol/context all read 0
          // (tinfo.type = none), writes are ignored.
          csr_rdata = 64'd0;
        end else begin
          csr_exists = 1'b0;
        end
      end
    endcase
  end

  logic csr_priv_ok, csr_write_attempt;
  // Effective rank for CSR addr[9:8]: M=3, HS=2, VS=1, U/VU=0.
  logic [1:0] priv_rank;
  assign priv_rank = (priv_q == PRIV_M) ? 2'd3 :
                     (priv_q == PRIV_S) ? (virt_q ? 2'd1 : 2'd2) : 2'd0;
  assign csr_priv_ok = (priv_rank >= addr_i[9:8]);
  // The core only asserts wr_en_i for actual writes; read-only
  // CSRs (addr[11:10]==2'b11) fault on any write attempt.
  assign csr_write_attempt = wr_en_i;
  // Counter access control: mcounteren gates S and U reads of
  // the unprivileged counters (0xC00-0xC1F), scounteren gates U.
  logic counter_blocked, counter_virt;
  always_comb begin
    counter_blocked = 1'b0;
    counter_virt = 1'b0;
    if ((addr_i[11:5] == 7'h60) && (priv_q != PRIV_M)) begin
      if (!mcounteren_q[{1'b0, addr_i[4:0]}]) begin
        counter_blocked = 1'b1;
      end else if (virt_q && (!hcounteren_q[{1'b0, addr_i[4:0]}] ||
                   ((priv_q == PRIV_U) &&
                    !scounteren_q[{1'b0, addr_i[4:0]}]))) begin
        counter_blocked = 1'b1;
        counter_virt = 1'b1;
      end else if ((priv_q == PRIV_U) &&
                   !scounteren_q[{1'b0, addr_i[4:0]}]) begin
        counter_blocked = 1'b1;
      end
    end
  end
  // Implemented H/VS/supervisor CSRs, for virtual-instruction
  // classification of accesses from VS/VU.
  logic is_h_csr, is_vs_csr, is_s_csr, csr_virt_inst;
  always_comb begin
    is_h_csr = (addr_i == 12'h600) || (addr_i == 12'h602) ||
               (addr_i == 12'h603) || (addr_i == 12'h604) ||
               (addr_i == 12'h605) || (addr_i == 12'h606) ||
               (addr_i == 12'h607) || (addr_i == 12'h60A) ||
               (addr_i == 12'h643) || (addr_i == 12'h644) ||
               (addr_i == 12'h645) || (addr_i == 12'h64A) ||
               (addr_i == 12'h680) || (addr_i == 12'hE12);
    is_vs_csr = (addr_i == 12'h200) || (addr_i == 12'h204) ||
                (addr_i == 12'h205) || (addr_i == 12'h240) ||
                (addr_i == 12'h241) || (addr_i == 12'h242) ||
                (addr_i == 12'h243) || (addr_i == 12'h244) ||
                (addr_i == 12'h280);
    is_s_csr = (addr_i == 12'h100) || (addr_i == 12'h104) ||
               (addr_i == 12'h105) || (addr_i == 12'h106) ||
               (addr_i == 12'h10A) || (addr_i == 12'h140) ||
               (addr_i == 12'h141) || (addr_i == 12'h142) ||
               (addr_i == 12'h143) || (addr_i == 12'h144) ||
               (addr_i == 12'h180);
    csr_virt_inst = virt_q && csr_exists &&
                    (is_h_csr || is_vs_csr ||
                     ((priv_q == PRIV_U) && is_s_csr) ||
                     ((addr_i == 12'h180) && (priv_q == PRIV_S) &&
                      h_vtvm_q) || counter_virt);
  end
  // TVM: satp/hgatp access from HS-mode is illegal while TVM=1.
  assign illegal_o = !csr_exists || !csr_priv_ok || counter_blocked ||
                     (((addr_i == 12'h001) || (addr_i == 12'h002) ||
                       (addr_i == 12'h003)) && (fs_o == 2'b00)) ||
                     (((addr_i == 12'h008) || (addr_i == 12'h009) ||
                       (addr_i == 12'h00A) || (addr_i == 12'h00F) ||
                       (addr_i == 12'hC20) || (addr_i == 12'hC21) ||
                       (addr_i == 12'hC22)) && (vec_vs_o == 2'b00)) ||
                     ((addr_i == 12'h180) && (priv_q == PRIV_S) &&
                      !virt_q && mstatus_tvm_q) ||
                     ((addr_i == 12'h680) && (priv_q == PRIV_S) &&
                      !virt_q && mstatus_tvm_q) ||
                     ((addr_i == 12'h180) && (priv_q == PRIV_S) &&
                      virt_q && h_vtvm_q) ||
                     (csr_write_attempt && (addr_i[11:10] == 2'b11));
  assign rdata_o = csr_rdata;
  assign rmw_rdata_o = (addr_i == 12'h344)
      ? {csr_rdata[63:10], mip_seip_q, csr_rdata[8:6], mip_stip_q,
         csr_rdata[4:0]}
      : csr_rdata;

  // xRET/WFI/SFENCE legality by mode; sys_virt_inst marks the
  // denials that are virtual-instruction (cause 22) in a VM.
  logic sys_virt_inst;
  always_comb begin
    sys_illegal_o = 1'b0;
    sys_virt_inst = 1'b0;
    unique case (sys_op_i)
      3'd1: sys_illegal_o = (priv_q != PRIV_M);                   // MRET
      3'd2: begin                                                 // SRET
        if (priv_q == PRIV_U) begin
          sys_illegal_o = 1'b1;
          sys_virt_inst = virt_q;
        end else if (virt_q && h_vtsr_q) begin
          sys_illegal_o = 1'b1;
          sys_virt_inst = 1'b1;
        end else if (!virt_q && (priv_q == PRIV_S) && mstatus_tsr_q) begin
          sys_illegal_o = 1'b1;
        end
      end
      3'd3: begin                                                 // WFI
        if ((priv_q != PRIV_M) && mstatus_tw_q) begin
          sys_illegal_o = 1'b1;
        end else if (virt_q && ((priv_q == PRIV_U) ||
                                ((priv_q == PRIV_S) && h_vtw_q))) begin
          sys_illegal_o = 1'b1;
          sys_virt_inst = 1'b1;
        end
      end
      3'd4: begin                                                 // SFENCE
        if (priv_q == PRIV_U) begin
          sys_illegal_o = 1'b1;
          sys_virt_inst = virt_q;
        end else if (virt_q && h_vtvm_q) begin
          sys_illegal_o = 1'b1;
          sys_virt_inst = 1'b1;
        end else if (!virt_q && (priv_q == PRIV_S) && mstatus_tvm_q) begin
          sys_illegal_o = 1'b1;
        end
      end
      3'd5: begin                                       // HFENCE.VVMA
        if (virt_q) begin
          sys_illegal_o = 1'b1;
          sys_virt_inst = 1'b1;
        end else if (priv_q == PRIV_U) begin
          sys_illegal_o = 1'b1;
        end
      end
      3'd6: begin                                       // HFENCE.GVMA
        if (virt_q) begin
          sys_illegal_o = 1'b1;
          sys_virt_inst = 1'b1;
        end else if (priv_q == PRIV_U) begin
          sys_illegal_o = 1'b1;
        end else if ((priv_q == PRIV_S) && mstatus_tvm_q) begin
          sys_illegal_o = 1'b1;
        end
      end
      3'd7: begin                                       // HLV/HLVX/HSV
        if (virt_q) begin
          sys_illegal_o = 1'b1;
          sys_virt_inst = 1'b1;
        end else if ((priv_q == PRIV_U) && !h_hu_q) begin
          sys_illegal_o = 1'b1;
        end
      end
      default: ;
    endcase
  end
  assign virt_inst_o = csr_virt_inst | sys_virt_inst;

  assign xret_pc_o = (sys_op_i == 3'd2)
      ? (virt_q ? vsepc_q : sepc_q) : mepc_q;

  // ------------------------------------------------------------
  // Interrupt selection
  // ------------------------------------------------------------
  // VS-level interrupts are always delegated past M (their
  // mideleg bits read as one), so selection uses the effective
  // delegation value. Pending sets are split by destination:
  // HS gets delegated HS interrupts plus VS interrupts whose
  // hideleg bit is clear; VS gets only hideleg-delegated VS
  // interrupts, and only while executing in the guest.
  logic [63:0] pend_m, pend_hs, pend_vs, eff_mideleg;
  logic [63:0] sel_cause_m, sel_cause_hs, sel_cause_vs;
  assign eff_mideleg = mideleg_q | 64'h444;
  assign pend_m  = mip_val & mie_q & ~eff_mideleg;
  assign pend_hs = mip_val & mie_q & eff_mideleg & ~hideleg_q;
  assign pend_vs = mip_val & mie_q & hideleg_q;

  /* verilator lint_off UNUSEDSIGNAL */  // pend uses the low 12 bits
  function automatic logic [63:0] pick_irq(input logic [63:0] pend);
    if (pend[11])      pick_irq = 64'd11;
    else if (pend[3])  pick_irq = 64'd3;
    else if (pend[7])  pick_irq = 64'd7;
    else if (pend[9])  pick_irq = 64'd9;
    else if (pend[1])  pick_irq = 64'd1;
    else if (pend[5])  pick_irq = 64'd5;
    else               pick_irq = 64'd0;
  endfunction
  // HS destination priority: SEI, SSI, STI, VSEI, VSSI, VSTI.
  function automatic logic [63:0] pick_irq_hs(input logic [63:0] pend);
    if (pend[9])       pick_irq_hs = 64'd9;
    else if (pend[1])  pick_irq_hs = 64'd1;
    else if (pend[5])  pick_irq_hs = 64'd5;
    else if (pend[10]) pick_irq_hs = 64'd10;
    else if (pend[2])  pick_irq_hs = 64'd2;
    else if (pend[6])  pick_irq_hs = 64'd6;
    else               pick_irq_hs = 64'd0;
  endfunction
  // VS destination priority follows the translated S order.
  function automatic logic [63:0] pick_irq_vs(input logic [63:0] pend);
    if (pend[10])      pick_irq_vs = 64'd10;
    else if (pend[2])  pick_irq_vs = 64'd2;
    else if (pend[6])  pick_irq_vs = 64'd6;
    else               pick_irq_vs = 64'd0;
  endfunction
  /* verilator lint_on UNUSEDSIGNAL */

  assign sel_cause_m  = pick_irq(pend_m);
  assign sel_cause_hs = pick_irq_hs(pend_hs);
  assign sel_cause_vs = pick_irq_vs(pend_vs);

  logic take_m, take_hs, take_vs;
  assign take_m = (pend_m != 64'd0) &&
                  ((priv_q < PRIV_M) || mstatus_mie_q);
  // VS/VU are less privileged than HS, so HS interrupts trap
  // out of a guest regardless of both SIE bits.
  assign take_hs = !take_m && (pend_hs != 64'd0) &&
                   (virt_q || (priv_q == PRIV_U) ||
                    ((priv_q == PRIV_S) && mstatus_sie_q));
  assign take_vs = !take_m && !take_hs && virt_q &&
                   (pend_vs != 64'd0) &&
                   ((priv_q == PRIV_U) || vs_sie_q);
  assign irq_valid_o = take_m || take_hs || take_vs;
  assign irq_cause_o = {1'b1, 63'd0} |
      (take_m ? sel_cause_m : take_hs ? sel_cause_hs : sel_cause_vs);

  // ------------------------------------------------------------
  // Trap target (delegated traps go to S when taken from S/U)
  // ------------------------------------------------------------
  logic        trap_is_irq;
  logic [5:0]  trap_code;
  logic        trap_to_s;   // taken in HS (nominal S, V=0)
  logic        trap_to_vs;  // taken in VS (nominal S, V stays 1)
  logic [5:0]  trap_code_vs;
  assign trap_is_irq = trap_cause_i[63];
  assign trap_code = trap_cause_i[5:0];
  // VS interrupt codes are translated to S codes for the guest.
  assign trap_code_vs = (trap_code == 6'd10) ? 6'd9 :
                        (trap_code == 6'd6)  ? 6'd5 :
                        (trap_code == 6'd2)  ? 6'd1 : trap_code;
  always_comb begin
    logic deleg_hs;
    if (priv_q == PRIV_M) begin
      deleg_hs = 1'b0;
    end else if (trap_is_irq) begin
      deleg_hs = mideleg_q[trap_code] || (trap_code == 6'd2) ||
                 (trap_code == 6'd6) || (trap_code == 6'd10);
    end else begin
      deleg_hs = medeleg_q[trap_code];
    end
    trap_to_vs = deleg_hs && virt_q &&
                 (trap_is_irq ? hideleg_q[trap_code]
                              : hedeleg_q[trap_code]);
    trap_to_s = deleg_hs && !trap_to_vs;
  end
  assign trap_priv_o = (trap_to_s || trap_to_vs) ? PRIV_S : PRIV_M;
  always_comb begin
    if (trap_to_vs) begin
      trap_target_o = {vstvec_q[63:2], 2'b00} +
          ((vstvec_q[1:0] == 2'b01) && trap_is_irq
               ? {56'd0, trap_code_vs, 2'b00} : 64'd0);
    end else if (trap_to_s) begin
      trap_target_o = {stvec_q[63:2], 2'b00} +
          ((stvec_q[1:0] == 2'b01) && trap_is_irq
               ? {56'd0, trap_code, 2'b00} : 64'd0);
    end else begin
      trap_target_o = {mtvec_q[63:2], 2'b00} +
          ((mtvec_q[1:0] == 2'b01) && trap_is_irq
               ? {56'd0, trap_code, 2'b00} : 64'd0);
    end
  end

  // ------------------------------------------------------------
  // PMP (16 entries, grain 4 bytes)
  // ------------------------------------------------------------
  // PMP compares in the pmpaddr domain (PA[55:2], 54 bits); the
  // unused input bits (byte offsets, cfg permission bits consumed
  // by the caller) are inherent to the interface.
  /* verilator lint_off UNUSEDSIGNAL */
  function automatic logic pmp_match(
      input logic [63:0] addr,
      input logic [7:0]  cfg,
      input logic [63:0] pmpaddr,
      input logic [63:0] prev_pmpaddr);
    logic [53:0] a54, enc, prev, napot_mask;
    a54 = addr[55:2];
    enc = pmpaddr[53:0];
    prev = prev_pmpaddr[53:0];
    napot_mask = enc ^ (enc + 54'd1);  // trailing-ones span, incl. the 0 above
    unique case (cfg[4:3])
      2'b00:   pmp_match = 1'b0;                                    // OFF
      2'b01:   pmp_match = (a54 >= prev) && (a54 < enc);            // TOR
      2'b10:   pmp_match = (a54 == enc);                            // NA4
      default: pmp_match = ((a54 ^ enc) & ~napot_mask) == 54'd0;    // NAPOT
    endcase
  endfunction
  /* verilator lint_on UNUSEDSIGNAL */

  function automatic logic pmp_check(
      input logic [63:0] addr,
      input logic [1:0]  acc,
      input logic [1:0]  priv);
    logic allow;
    allow = (priv == PRIV_M);
    for (int i = 15; i >= 0; i--) begin
      if (pmp_match(addr, pmpcfg_q[i], pmpaddr_q[i],
                    (i == 0) ? 64'd0 : pmpaddr_q[i-1])) begin
        if ((priv == PRIV_M) && !pmpcfg_q[i][7]) begin
          allow = 1'b1;
        end else if (acc == 2'd0) begin
          allow = pmpcfg_q[i][0];
        end else if (acc == 2'd1) begin
          allow = pmpcfg_q[i][1];
        end else if (acc == 2'd3) begin
          allow = pmpcfg_q[i][0] && pmpcfg_q[i][2];  // HLVX: R+X
        end else begin
          allow = pmpcfg_q[i][2];
        end
      end
    end
    return allow;
  endfunction

  assign pmp_allow_a_o = pmp_check(pmp_addr_a_i, pmp_acc_a_i, pmp_priv_a_i);
  assign pmp_allow_b_o = pmp_check(pmp_addr_b_i, pmp_acc_b_i, pmp_priv_b_i);
  assign pmp_allow_c_o = pmp_check(pmp_addr_c_i, pmp_acc_c_i, pmp_priv_c_i);

  // PMP write locking: an entry is locked by its own L bit, and
  // pmpaddr[i] is also locked when entry i+1 is a locked TOR entry
  // (pmpaddr[i] forms its lower bound).
  function automatic logic pmp_locked(input int idx);
    pmp_locked = pmpcfg_q[idx][7] ||
        ((idx < 15) && pmpcfg_q[idx+1][7] &&
         (pmpcfg_q[idx+1][4:3] == 2'b01));
  endfunction

  // ------------------------------------------------------------
  // Sequential updates: CSR writes, xRET, trap entry, counters
  // ------------------------------------------------------------
  logic [1:0] ret_priv;
  assign ret_priv = (sys_op_i == 3'd2)
      ? {1'b0, virt_q ? vs_spp_q : mstatus_spp_q} : mstatus_mpp_q;
  logic ret_virt;
  assign ret_virt = (sys_op_i == 3'd1)
      ? ((mstatus_mpp_q == PRIV_M) ? 1'b0 : mstatus_mpv_q)
      : (virt_q ? 1'b1 : h_spv_q);

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      priv_q <= PRIV_M;
      mstatus_mie_q <= 1'b0;
      mstatus_sie_q <= 1'b0;
      mstatus_mpie_q <= 1'b0;
      mstatus_spie_q <= 1'b0;
      mstatus_spp_q <= 1'b0;
      mstatus_mpp_q <= 2'b00;
      mstatus_mprv_q <= 1'b0;
      mstatus_sum_q <= 1'b0;
      mstatus_mxr_q <= 1'b0;
      mstatus_tvm_q <= 1'b0;
      mstatus_tw_q <= 1'b0;
      mstatus_tsr_q <= 1'b0;
      medeleg_q <= 64'd0;
      mideleg_q <= 64'd0;
      mie_q <= 64'd0;
      mtvec_q <= 64'd0;
      mcounteren_q <= 64'd0;
      fflags_q <= 5'd0;
      frm_q <= 3'd0;
      mstatus_fs_q <= 2'd0;
      mstatus_vs_q <= 2'd0;
      vtype_vill_q <= 1'b1;
      vtype_vma_q <= 1'b0;
      vtype_vta_q <= 1'b0;
      vtype_vsew_q <= 3'd0;
      vtype_vlmul_q <= 3'd0;
      vl_q <= 64'd0;
      vstart_q <= 64'd0;
      vxsat_q <= 1'b0;
      vxrm_q <= 2'd0;
      mscratch_q <= 64'd0;
      mepc_q <= 64'd0;
      mcause_q <= 64'd0;
      mtval_q <= 64'd0;
      mip_ssip_q <= 1'b0;
      mip_seip_q <= 1'b0;
      mip_stip_q <= 1'b0;
      menvcfg_q <= 64'd0;
      mcountinhibit_q <= 64'd0;
      stvec_q <= 64'd0;
      scounteren_q <= 64'd0;
      sscratch_q <= 64'd0;
      sepc_q <= 64'd0;
      scause_q <= 64'd0;
      stval_q <= 64'd0;
      senvcfg_q <= 64'd0;
      satp_q <= 64'd0;
      mcycle_q <= 64'd0;
      minstret_q <= 64'd0;
      mtime_q <= 64'd0;
      virt_q <= 1'b0;
      mstatus_mpv_q <= 1'b0;
      mstatus_gva_q <= 1'b0;
      h_gva_q <= 1'b0;
      h_spv_q <= 1'b0;
      h_spvp_q <= 1'b0;
      h_hu_q <= 1'b0;
      h_vtvm_q <= 1'b0;
      h_vtw_q <= 1'b0;
      h_vtsr_q <= 1'b0;
      hedeleg_q <= 64'd0;
      hideleg_q <= 64'd0;
      hvip_q <= 64'd0;
      htimedelta_q <= 64'd0;
      hcounteren_q <= 64'd0;
      henvcfg_q <= 64'd0;
      htval_q <= 64'd0;
      htinst_q <= 64'd0;
      hgatp_q <= 64'd0;
      mtval2_q <= 64'd0;
      mtinst_q <= 64'd0;
      vs_sie_q <= 1'b0;
      vs_spie_q <= 1'b0;
      vs_spp_q <= 1'b0;
      vs_sum_q <= 1'b0;
      vs_mxr_q <= 1'b0;
      vs_fs_q <= 2'd0;
      vs_vs_q <= 2'd0;
      vstvec_q <= 64'd0;
      vsscratch_q <= 64'd0;
      vsepc_q <= 64'd0;
      vscause_q <= 64'd0;
      vstval_q <= 64'd0;
      vsatp_q <= 64'd0;
      for (int i = 0; i < 16; i++) begin
        pmpcfg_q[i] <= 8'd0;
        pmpaddr_q[i] <= 64'd0;
      end
    end else begin
      // Free-running counters. CY/IR inhibit mcycle/minstret
      // only: `time` is a real-time counter and must advance
      // even while CY is inhibited (OpenSBI PMU stop-all relies
      // on this distinction; Linux takes its clocksource here).
      mtime_q <= mtime_q + 64'd1;
      if (!mcountinhibit_q[0]) mcycle_q <= mcycle_q + 64'd1;
      if (retire_i && !mcountinhibit_q[2]) begin
        minstret_q <= minstret_q + 64'd1;
      end
      // FPU side effects (explicit CSR writes in the chain
      // below win on the same edge by statement order).
      if (fflags_we_i) fflags_q <= fflags_q | fflags_i;
      if (fp_dirty_i) begin
        mstatus_fs_q <= 2'b11;
        if (virt_q) vs_fs_q <= 2'b11;  // both FS fields go Dirty
      end
      if (vec_dirty_i) begin
        mstatus_vs_q <= 2'b11;
        if (virt_q) vs_vs_q <= 2'b11;  // both VS fields go Dirty
      end
      if (vxsat_set_i) vxsat_q <= 1'b1;
      if (vl_we_i) vl_q <= vl_wdata_i;
      if (vstart_we_i) vstart_q <= vstart_wdata_i;
      // vsetvl* commit (EX). Setting vill zeroes vl and the
      // remaining vtype fields; vstart always clears.
      if (vset_en_i) begin
        vtype_vill_q <= vset_vill;
        vtype_vma_q <= !vset_vill && vset_vtype_i[7];
        vtype_vta_q <= !vset_vill && vset_vtype_i[6];
        vtype_vsew_q <= vset_vill ? 3'd0 : vset_vtype_i[5:3];
        vtype_vlmul_q <= vset_vill ? 3'd0 : vset_vtype_i[2:0];
        vl_q <= vset_vl_o;
        vstart_q <= 64'd0;
        mstatus_vs_q <= 2'b11;
        if (virt_q) vs_vs_q <= 2'b11;
      end

      if (trap_take_i) begin
        priv_q <= trap_priv_o;
        if (trap_to_vs) begin
          vsepc_q <= trap_pc_i;
          vscause_q <= trap_is_irq
              ? {1'b1, 57'd0, trap_code_vs} : trap_cause_i;
          vstval_q <= trap_tval_i;
          vs_spie_q <= vs_sie_q;
          vs_sie_q <= 1'b0;
          vs_spp_q <= priv_q[0];
          // V remains 1.
        end else if (trap_to_s) begin
          sepc_q <= trap_pc_i;
          scause_q <= trap_cause_i;
          stval_q <= trap_tval_i;
          htval_q <= trap_gpa_i >> 2;
          htinst_q <= trap_tinst_i;
          mstatus_spie_q <= mstatus_sie_q;
          mstatus_sie_q <= 1'b0;
          mstatus_spp_q <= priv_q[0];
          h_spv_q <= virt_q;
          h_gva_q <= (virt_q || trap_gva_i) && !trap_is_irq &&
                     ((trap_code <= 6'd1) || (trap_code == 6'd3) ||
                      ((trap_code >= 6'd4) && (trap_code <= 6'd7)) ||
                      (trap_code == 6'd12) || (trap_code == 6'd13) ||
                      (trap_code == 6'd15) || (trap_code == 6'd20) ||
                      (trap_code == 6'd21) || (trap_code == 6'd23));
          if (virt_q) h_spvp_q <= priv_q[0];
          virt_q <= 1'b0;
        end else begin
          mepc_q <= trap_pc_i;
          mcause_q <= trap_cause_i;
          mtval_q <= trap_tval_i;
          mtval2_q <= trap_gpa_i >> 2;
          mtinst_q <= trap_tinst_i;
          mstatus_mpie_q <= mstatus_mie_q;
          mstatus_mie_q <= 1'b0;
          mstatus_mpp_q <= priv_q;
          mstatus_mpv_q <= virt_q;
          mstatus_gva_q <= (virt_q || trap_gva_i) && !trap_is_irq &&
                     ((trap_code <= 6'd1) || (trap_code == 6'd3) ||
                      ((trap_code >= 6'd4) && (trap_code <= 6'd7)) ||
                      (trap_code == 6'd12) || (trap_code == 6'd13) ||
                      (trap_code == 6'd15) || (trap_code == 6'd20) ||
                      (trap_code == 6'd21) || (trap_code == 6'd23));
          virt_q <= 1'b0;
        end
        // MPRV is NOT cleared by trap entry (only by an xRET
        // returning to a non-M mode, below).
      end else if (ret_en_i) begin
        // xRET (sys_op 1 = MRET, 2 = SRET)
        priv_q <= ret_priv;
        virt_q <= ret_virt;
        if (sys_op_i == 3'd1) begin
          mstatus_mie_q <= mstatus_mpie_q;
          mstatus_mpie_q <= 1'b1;
          mstatus_mpp_q <= 2'b00;
          mstatus_mpv_q <= 1'b0;
          if (ret_priv != PRIV_M) mstatus_mprv_q <= 1'b0;
        end else if (virt_q) begin
          vs_sie_q <= vs_spie_q;
          vs_spie_q <= 1'b1;
          vs_spp_q <= 1'b0;
        end else begin
          mstatus_sie_q <= mstatus_spie_q;
          mstatus_spie_q <= 1'b1;
          mstatus_spp_q <= 1'b0;
          h_spv_q <= 1'b0;
        end
      end else if (wr_en_i && !illegal_o) begin
        unique case (addr_i)
          12'h001: fflags_q <= wdata_i[4:0];
          12'h002: frm_q <= wdata_i[2:0];
          12'h003: begin
            fflags_q <= wdata_i[4:0];
            frm_q <= wdata_i[7:5];
          end
          12'h008: vstart_q <= wdata_i;
          12'h009: vxsat_q <= wdata_i[0];
          12'h00A: vxrm_q <= wdata_i[1:0];
          12'h00F: begin
            vxsat_q <= wdata_i[0];
            vxrm_q <= wdata_i[2:1];
          end
          12'h100: begin  // sstatus (vsstatus while V=1)
            if (virt_q) begin
              vs_sie_q <= wdata_i[1];
              vs_spie_q <= wdata_i[5];
              vs_spp_q <= wdata_i[8];
              vs_sum_q <= wdata_i[18];
              vs_mxr_q <= wdata_i[19];
              vs_fs_q <= wdata_i[14:13];
              vs_vs_q <= wdata_i[10:9];
            end else begin
              mstatus_sie_q <= wdata_i[1];
              mstatus_spie_q <= wdata_i[5];
              mstatus_spp_q <= wdata_i[8];
              mstatus_sum_q <= wdata_i[18];
              mstatus_mxr_q <= wdata_i[19];
              mstatus_fs_q <= wdata_i[14:13];
              mstatus_vs_q <= wdata_i[10:9];
            end
          end
          12'h104: begin  // sie (vsie while V=1)
            if (virt_q) begin
              if (hideleg_q[2]) mie_q[2] <= wdata_i[1];
              if (hideleg_q[6]) mie_q[6] <= wdata_i[5];
              if (hideleg_q[10]) mie_q[10] <= wdata_i[9];
            end else begin
              mie_q <= (mie_q & ~mideleg_q) | (wdata_i & mideleg_q);
            end
          end
          12'h105: if (virt_q) begin
            vstvec_q <= {wdata_i[63:2], (wdata_i[1:0] < 2'd2) ? wdata_i[1:0] : 2'd0};
          end else begin
            stvec_q <= {wdata_i[63:2], (wdata_i[1:0] < 2'd2) ? wdata_i[1:0] : 2'd0};
          end
          12'h106: scounteren_q <= wdata_i & 64'h7;  // CY|TM|IR exist
          12'h10A: senvcfg_q <= wdata_i;
          12'h140: if (virt_q) vsscratch_q <= wdata_i;
                   else sscratch_q <= wdata_i;
          12'h141: if (virt_q) vsepc_q <= {wdata_i[63:1], 1'b0};
                   else sepc_q <= {wdata_i[63:1], 1'b0};
          12'h142: if (virt_q) vscause_q <= wdata_i;
                   else scause_q <= wdata_i;
          12'h143: if (virt_q) vstval_q <= wdata_i;
                   else stval_q <= wdata_i;
          12'h144: if (virt_q) begin
            if (hideleg_q[2]) hvip_q[2] <= wdata_i[1];
          end else begin
            mip_ssip_q <= wdata_i[1];
          end
          12'h180: begin  // satp MODE is WARL: only Bare/Sv39 stick
            if ((wdata_i[63:60] == 4'd0) || (wdata_i[63:60] == 4'd8)) begin
              if (virt_q) vsatp_q <= wdata_i;
              else satp_q <= wdata_i;
            end
          end
          12'h200: begin  // vsstatus
            vs_sie_q <= wdata_i[1];
            vs_spie_q <= wdata_i[5];
            vs_spp_q <= wdata_i[8];
            vs_sum_q <= wdata_i[18];
            vs_mxr_q <= wdata_i[19];
            vs_fs_q <= wdata_i[14:13];
            vs_vs_q <= wdata_i[10:9];
          end
          12'h204: begin  // vsie
            if (hideleg_q[2]) mie_q[2] <= wdata_i[1];
            if (hideleg_q[6]) mie_q[6] <= wdata_i[5];
            if (hideleg_q[10]) mie_q[10] <= wdata_i[9];
          end
          12'h205: vstvec_q <= {wdata_i[63:2], (wdata_i[1:0] < 2'd2) ? wdata_i[1:0] : 2'd0};
          12'h240: vsscratch_q <= wdata_i;
          12'h241: vsepc_q <= {wdata_i[63:1], 1'b0};
          12'h242: vscause_q <= wdata_i;
          12'h243: vstval_q <= wdata_i;
          12'h244: if (hideleg_q[2]) hvip_q[2] <= wdata_i[1];
          12'h280: begin  // vsatp
            if ((wdata_i[63:60] == 4'd0) || (wdata_i[63:60] == 4'd8)) begin
              vsatp_q <= wdata_i;
            end
          end
          12'h600: begin  // hstatus (VSBE/VGEIN/VSXL read-only here)
            h_gva_q <= wdata_i[6];
            h_spv_q <= wdata_i[7];
            h_spvp_q <= wdata_i[8];
            h_hu_q <= wdata_i[9];
            h_vtvm_q <= wdata_i[20];
            h_vtw_q <= wdata_i[21];
            h_vtsr_q <= wdata_i[22];
          end
          12'h602: hedeleg_q <= wdata_i & 64'hC_B1FE;
          12'h603: hideleg_q <= wdata_i & 64'h444;
          12'h604: begin  // hie aliases in mie
            mie_q[2] <= wdata_i[2];
            mie_q[6] <= wdata_i[6];
            mie_q[10] <= wdata_i[10];
          end
          12'h605: htimedelta_q <= wdata_i;
          12'h606: hcounteren_q <= wdata_i & 64'h7;
          12'h607: ;  // hgeie: GEILEN = 0, ignore
          12'h60A: henvcfg_q <= wdata_i;
          12'h643: htval_q <= wdata_i;
          12'h644: hvip_q[2] <= wdata_i[2];  // hip.VSSIP alias
          12'h645: hvip_q <= wdata_i & 64'h444;
          12'h64A: htinst_q <= wdata_i;
          12'h680: begin  // hgatp MODE WARL: Bare/Sv39x4
            if ((wdata_i[63:60] == 4'd0) || (wdata_i[63:60] == 4'd8)) begin
              hgatp_q <= wdata_i;
            end
          end
          12'h300: begin  // mstatus
            mstatus_sie_q <= wdata_i[1];
            mstatus_mie_q <= wdata_i[3];
            mstatus_spie_q <= wdata_i[5];
            mstatus_mpie_q <= wdata_i[7];
            mstatus_spp_q <= wdata_i[8];
            mstatus_mpp_q <= (wdata_i[12:11] == 2'b10) ? 2'b00 : wdata_i[12:11];
            mstatus_mprv_q <= wdata_i[17];
            mstatus_sum_q <= wdata_i[18];
            mstatus_mxr_q <= wdata_i[19];
            mstatus_tvm_q <= wdata_i[20];
            mstatus_tw_q <= wdata_i[21];
            mstatus_tsr_q <= wdata_i[22];
            mstatus_fs_q <= wdata_i[14:13];
            mstatus_vs_q <= wdata_i[10:9];
            mstatus_gva_q <= wdata_i[38];
            mstatus_mpv_q <= wdata_i[39];
          end
          12'h302: medeleg_q <= wdata_i & 64'hF0_B75D;
          12'h303: mideleg_q <= wdata_i & 64'h222;
          12'h304: mie_q <= wdata_i & 64'hEEE;
          12'h305: mtvec_q <= {wdata_i[63:2], (wdata_i[1:0] < 2'd2) ? wdata_i[1:0] : 2'd0};
          12'h306: mcounteren_q <= wdata_i & 64'h7;  // CY|TM|IR exist
          12'h30A: menvcfg_q <= wdata_i;
          12'h320: mcountinhibit_q <= wdata_i & 64'h5;  // CY|IR exist
          12'h340: mscratch_q <= wdata_i;
          12'h341: mepc_q <= {wdata_i[63:1], 1'b0};
          12'h342: mcause_q <= wdata_i;
          12'h343: mtval_q <= wdata_i;
          12'h344: begin
            mip_ssip_q <= wdata_i[1];
            hvip_q[2] <= wdata_i[2];
            mip_stip_q <= wdata_i[5];
            hvip_q[6] <= wdata_i[6];
            mip_seip_q <= wdata_i[9];
            hvip_q[10] <= wdata_i[10];
          end
          12'h34A: mtinst_q <= wdata_i;
          12'h34B: mtval2_q <= wdata_i;
          12'h3A0: begin
            for (int i = 0; i < 8; i++) begin
              if (!pmpcfg_q[i][7]) begin
                // Bits 6:5 are reserved (read zero); W without R
                // is reserved: clear W and X (WARL, matching
                // Sail's PMP_ClearPermissions).
                pmpcfg_q[i] <= wdata_i[i*8 +: 8] &
                               ((wdata_i[i*8+1] && (wdata_i[i*8] == 1'b0)) ? 8'h99 : 8'h9F);
              end
            end
          end
          12'h3A2: begin
            for (int i = 0; i < 8; i++) begin
              if (!pmpcfg_q[i+8][7]) begin
                pmpcfg_q[i+8] <= wdata_i[i*8 +: 8] &
                                 ((wdata_i[i*8+1] && (wdata_i[i*8] == 1'b0)) ? 8'h99 : 8'h9F);
              end
            end
          end
          12'hB00: mcycle_q <= wdata_i;
          12'hB02: minstret_q <= wdata_i;
          default: begin
            if ((addr_i >= 12'h3B0) && (addr_i <= 12'h3BF)) begin
              if (!pmp_locked(int'(addr_i[3:0]))) begin
                pmpaddr_q[addr_i[3:0]] <= {10'd0, wdata_i[53:0]};
              end
            end
            // mhpmcounter/mhpmevent and read-only CSRs: ignored or
            // already faulted via illegal_o.
          end
        endcase
      end
    end
  end
endmodule
`default_nettype wire
