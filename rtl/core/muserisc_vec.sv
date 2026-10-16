// Element-serial vector execution unit (issue #23; timing
// rework for #32). VLEN=512, ELEN=64, one element per cycle
// through a 64-bit datapath, reading and writing the banked
// synchronous-read VRF (muserisc_vregfile) one 64-bit word
// per port per cycle. See docs/CORE.md "Vector unit" for the
// microarchitecture and per-op cycle counts.
//
// Pipeline (all three stages advance together; S2 may hold
// for multi-cycle elements and then back-pressures S1/S0):
//   S0  slot sequencer: element index over [vstart, vl)
//       (plus a seed slot and a final-write slot for
//       reductions); issues the three VRF word reads (A =
//       vs2 element / mask word, B = vs1 element / mask word,
//       C = old vd element / mask word) and samples v0[i].
//   S1  operand extract: picks the element out of each read
//       word (byte shift + width mask). vrgather.vv /
//       vrgatherei16 take a second S1 cycle that turns the
//       vs1 element into a vs2 read address.
//   S2  execute + write-back: single-cycle integer ALU,
//       fixed-point (vxrm/vxsat), compare/mask-bit and
//       reduction accumulators, or a multi-cycle sub-unit:
//       radix-2^16 iterative multiplier (1-4 steps by SEW),
//       radix-2 restoring divider (SEW steps), or the FP
//       element sub-step(s) (widening FP ops take 2-3:
//       source conversions, then the operation), each one
//       operation on the core's multi-cycle scalar FPU
//       through the fpu_* ports, or a two-cycle
//       vfrec7/vfrsqrt7 estimate here; every sub-step
//       result is registered before use. The element
//       result is written with byte enables.
// Mask-destination ops accumulate 64 result bits in a word
// register (seeded from the old vd word) and write it once
// per 64 elements. Prestart, tail and inactive elements are
// never written: agnostic policies behave as undisturbed (a
// spec-legal choice matching the Sail reference config).
//
// Handshake with the core: start_i (one cycle, all operand
// inputs valid) latches the instruction; busy_o is high
// until done_o, which stays high (with scalar_o / sat_o /
// fflags_o stable) until ack_i. kill_i abandons the op.
`default_nettype none
module muserisc_vec
  import muserisc_pkg::*, muserisc_vec_pkg::*, muserisc_fpu_pkg::*;
(
    input  wire          clk_i,
    input  wire          rst_ni,
    input  wire          kill_i,
    input  wire          start_i,
    input  wire          ack_i,
    input  wire [6:0]    op_i,       // VOP_*
    input  wire [1:0]    form_i,     // VFORM_* (VV/VX/VI)
    input  wire [2:0]    sew_i,      // vtype.vsew (SEW = 8<<sew)
    input  wire [63:0]   vl_i,
    input  wire [63:0]   vstart_i,
    input  wire [63:0]   vlmax_i,    // elements in a full group
    input  wire          vta_i,
    input  wire          vma_i,
    input  wire          vm_i,       // 1 = unmasked
    input  wire [4:0]    vs2_i,      // register fields
    input  wire [4:0]    vs1_i,
    input  wire [4:0]    vd_i,
    input  wire [3:0]    nreg_i,     // vmv<nr>r.v register count
    input  wire [63:0]   scalar_i,   // rs1 / frs1 value (VX/VF)
    input  wire [63:0]   imm_i,      // imm5 / sub-operation
    input  wire [1:0]    vxrm_i,
    input  wire [2:0]    frm_i,

    // VRF ports (synchronous read: data valid the cycle
    // after re; held while re is low).
    output logic         re_a_o,
    output logic [7:0]   raddr_a_o,
    input  wire  [63:0]  rdata_a_i,
    output logic         re_b_o,
    output logic [7:0]   raddr_b_o,
    input  wire  [63:0]  rdata_b_i,
    output logic         re_c_o,
    output logic [7:0]   raddr_c_o,
    input  wire  [63:0]  rdata_c_i,
    input  wire  [511:0] v0_i,
    output logic         we_o,
    output logic [7:0]   waddr_o,
    output logic [7:0]   wbe_o,
    output logic [63:0]  wdata_o,

    output logic         busy_o,
    output logic         done_o,
    output logic [63:0]  scalar_o,   // vmv.x.s / vcpop / vfirst / vfmv.f.s
    output logic         sat_o,      // an active element saturated
    output logic [4:0]   fflags_o,   // accrued FP flags

    // Shared scalar FPU (muserisc_fpu EX handshake). The core
    // routes these to its FPU while the unit is busy (the FPU
    // is otherwise idle then: it only serves the instruction in
    // EX). req stays high until done; the result is taken (ack)
    // the cycle done is seen.
    output logic         fpu_req_o,
    output logic [4:0]   fpu_op_o,
    output logic         fpu_fmt_d_o,
    output logic [2:0]   fpu_rm_o,
    output logic [63:0]  fpu_a_o,
    output logic [63:0]  fpu_b_o,
    output logic [63:0]  fpu_c_o,
    output logic [1:0]   fpu_aux_o,
    input  wire          fpu_done_i,
    input  wire  [63:0]  fpu_result_i,
    input  wire  [4:0]   fpu_flags_i
);

  // Agnostic policies behave as undisturbed in this
  // implementation, so vta_i/vma_i do not change any result.
  wire unused_agnostic = vta_i ^ vma_i;

  // ------------------------------------------------------------
  // Helpers
  // ------------------------------------------------------------
  function automatic logic [63:0] ones_w(input logic [2:0] w);
    unique case (w)
      3'd0: ones_w = 64'h0000_0000_0000_00ff;
      3'd1: ones_w = 64'h0000_0000_0000_ffff;
      3'd2: ones_w = 64'h0000_0000_ffff_ffff;
      default: ones_w = 64'hffff_ffff_ffff_ffff;
    endcase
  endfunction
  /* verilator lint_off UNUSEDSIGNAL */
  // VRF word address of element idx (width code w) in the
  // group starting at register r; groups wrap mod 32 regs.
  function automatic logic [7:0] el_addr(
      input logic [4:0] r, input logic [9:0] idx, input logic [2:0] w);
    logic [12:0] bo;
    bo = 13'(idx) << w;
    el_addr = {r, 3'b000} + bo[10:3];
  endfunction
  // Byte offset of element idx inside its word.
  function automatic logic [2:0] el_off(
      input logic [9:0] idx, input logic [2:0] w);
    logic [12:0] bo;
    bo = 13'(idx) << w;
    el_off = bo[2:0];
  endfunction
  // Word address holding mask bit idx of register r.
  function automatic logic [7:0] bit_addr(
      input logic [4:0] r, input logic [9:0] idx);
    bit_addr = {r, 3'b000} + {5'd0, idx[8:6]};
  endfunction
  /* verilator lint_on UNUSEDSIGNAL */
  function automatic logic [63:0] ext_el(
      input logic [63:0] word, input logic [9:0] idx, input logic [2:0] w);
    ext_el = (word >> {el_off(idx, w), 3'b000}) & ones_w(w);
  endfunction
  function automatic logic [7:0] be_w(input logic [2:0] w);
    unique case (w)
      3'd0: be_w = 8'h01;
      3'd1: be_w = 8'h03;
      3'd2: be_w = 8'h0f;
      default: be_w = 8'hff;
    endcase
  endfunction

  // Op classification (shared by start-time and run-time).
  function automatic logic f_wide(input logic [6:0] op, input logic [4:0] imm);
    f_wide = ((op >= VOP_WADD) && (op <= VOP_WMACCUS)) ||
             (op == VOP_WRED) || (op == VOP_FBINW) || (op == VOP_FMACCW) ||
             ((op == VOP_FCVT) && (imm[4:0] >= 5'd8) && (imm[4:0] < 5'd16));
  endfunction
  function automatic logic f_narrow(input logic [6:0] op, input logic [4:0] imm);
    f_narrow = ((op >= VOP_NSRL) && (op <= VOP_NCLIPU)) ||
               ((op == VOP_FCVT) && (imm[4:0] >= 5'd16));
  endfunction
  function automatic logic f_red(input logic [6:0] op);
    f_red = (op == VOP_RED) || (op == VOP_WRED) ||
            (op == VOP_FRED) || (op == VOP_FWRED);
  endfunction

  // ------------------------------------------------------------
  // Instruction state (latched at start)
  // ------------------------------------------------------------
  logic        run_q;
  logic [6:0]  op_q;
  logic [1:0]  form_q;
  logic [2:0]  sew_q, dw_q, aw_q;
  logic        vm_q;
  logic [4:0]  vs2_q, vs1_q, vd_q;
  logic [63:0] scalar_q, imm_q;
  logic [1:0]  vxrm_q;
  logic [2:0]  frm_q;
  logic [9:0]  vl10_q, vlmax10_q, beg_q, end_q;
  logic [9:0]  off10_q, lim_q;     // slide offset / slidedown limit
  logic        off_ok_q;           // slideup offset < 512 / slidedown ok
  logic [9:0]  gidx10_q;           // vrgather .vx/.vi index
  logic        gidx_ok_q;

  // Start-time decode of the incoming instruction.
  logic [2:0]  dw_i, aw_i;
  logic [9:0]  vl10_i, vstart10_i, beg_i, end_i;
  logic        wide_i, narrow_i;
  logic [63:0] off64_i, gidx64_i;
  assign wide_i = f_wide(op_i, imm_i[4:0]);
  assign narrow_i = f_narrow(op_i, imm_i[4:0]);
  assign dw_i = wide_i ? ((sew_i >= 3'd3) ? 3'd3 : (sew_i + 3'd1)) : sew_i;
  always_comb begin
    if (narrow_i || (op_i == VOP_WADDW) || (op_i == VOP_WADDUW) ||
        (op_i == VOP_WSUBW) || (op_i == VOP_WSUBUW) ||
        ((op_i == VOP_FBINW) && imm_i[7])) begin
      aw_i = (sew_i >= 3'd3) ? 3'd3 : (sew_i + 3'd1);
    end else if (op_i == VOP_EXT) begin
      // imm[2:1]: 01=/8, 10=/4, 11=/2 (legality in the core).
      aw_i = sew_i - (3'd4 - {1'b0, imm_i[2:1]});
    end else begin
      aw_i = sew_i;
    end
  end
  assign vl10_i = (vl_i > 64'd512) ? 10'd512 : vl_i[9:0];
  // vmv<nr>r.v prestart byte offset (vstart in SEW elements).
  logic [12:0] mvr_boff_i;
  assign mvr_boff_i = 13'(vstart10_i) << sew_i;
  assign vstart10_i = (vstart_i > 64'd512) ? 10'd512 : vstart_i[9:0];
  always_comb begin
    if (op_i == VOP_MVR) begin
      // Whole-register move: EEW = SEW, elements [vstart, evl)
      // copied a word at a time; prestart bytes of the first
      // word are masked off (mvr_be0_q).
      end_i = {3'b000, nreg_i, 3'b000};          // words to copy
      beg_i = (mvr_boff_i >= {3'b000, nreg_i, 6'd0}) ? end_i
                                              : {3'b000, mvr_boff_i[9:3]};
    end else if ((op_i == VOP_MVXS) || (op_i == VOP_FMVFS)) begin
      beg_i = 10'd0;                     // element 0 regardless of vl
      end_i = 10'd1;
    end else if (op_i == VOP_MVSX) begin
      beg_i = 10'd0;
      end_i = ((vstart_i == 64'd0) && (vl_i != 64'd0)) ? 10'd1 : 10'd0;
    end else begin
      end_i = vl10_i;
      beg_i = (vstart10_i > vl10_i) ? vl10_i : vstart10_i;
    end
  end
  assign off64_i = (form_i == VFORM_VX) ? scalar_i : {59'd0, imm_i[4:0]};
  assign gidx64_i = off64_i;

  // ------------------------------------------------------------
  // Run-time classification (from latched op)
  // ------------------------------------------------------------
  logic is_mvr, is_mask_dest, is_mask_src, is_red, is_gvv, is_mul, is_div;
  logic is_fp, unmasked_op, is_scalar_op;
  assign is_mvr = (op_q == VOP_MVR);
  assign is_mask_dest = (op_q == VOP_MADC) || (op_q == VOP_MSBC) ||
      ((op_q >= VOP_CMPEQ) && (op_q <= VOP_CMPGT)) ||
      (op_q == VOP_MLOG) || (op_q == VOP_MSBIT) || (op_q == VOP_FCMP);
  // Ops whose vs2 operand is a mask register (bit i).
  assign is_mask_src = (op_q == VOP_MLOG) || (op_q == VOP_MSBIT) ||
      (op_q == VOP_IOTA) || (op_q == VOP_CPOP) || (op_q == VOP_FIRST);
  assign is_red = f_red(op_q);
  assign is_gvv = ((op_q == VOP_GATHER) && (form_q == VFORM_VV)) ||
                  (op_q == VOP_GATHEREI16);
  assign is_mul = ((op_q >= VOP_MUL) && (op_q <= VOP_NMSUB)) ||
                  (op_q == VOP_SMUL) ||
                  ((op_q >= VOP_WMUL) && (op_q <= VOP_WMACCUS));
  assign is_div = (op_q >= VOP_DIV) && (op_q <= VOP_REMU);
  assign is_fp = (op_q >= VOP_FBIN) && (op_q <= VOP_FWRED);
  assign unmasked_op = (op_q == VOP_ADC) || (op_q == VOP_SBC) ||
                       (op_q == VOP_MERGE);
  assign is_scalar_op = (op_q == VOP_MVXS) || (op_q == VOP_FMVFS) ||
                        (op_q == VOP_CPOP) || (op_q == VOP_FIRST);

  // ------------------------------------------------------------
  // Pipeline registers
  // ------------------------------------------------------------
  localparam logic [1:0] PH_SEED = 2'd0, PH_ELEM = 2'd1, PH_FIN = 2'd2,
                         PH_END = 2'd3;
  localparam logic [1:0] K_SEED = 2'd0, K_ELEM = 2'd1, K_FIN = 2'd2;

  logic [1:0] s0_ph_q;
  logic [9:0] i0_q;

  logic       s1_v_q, s1_ph_q;
  logic [1:0] s1_kind_q;
  logic [9:0] s1_i_q, s1_ai_q;
  logic       s1_m_q, s1_first_q, s1_last_q;
  logic       s1_skip_q;

  logic        s2_v_q;
  logic [1:0]  s2_kind_q;
  logic [9:0]  s2_i_q;
  logic [63:0] s2_a_q, s2_b_q, s2_old_q, s2_cw_q;
  logic        s2_abit_q, s2_bbit_q, s2_m_q, s2_first_q, s2_last_q;
  logic        s2_skip_q;
  logic [6:0]  s2_step_q;

  // Multi-cycle datapath registers.
  logic [63:0]  mx_q, my_q;         // multiplier / divider magnitudes
  logic         mneg_q, rneg_q;     // product/quotient and remainder signs
  logic [127:0] macc_q;             // product accumulator / signed product
  logic [63:0]  mres_q;             // post-processed multiply result
  logic         msat_q;             // vsmul saturated
  logic [63:0]  drem_q;             // divider partial remainder
  logic [63:0]  dquo_q;             // dividend in / quotient out
  logic [63:0]  fa_q, fb_q;         // FP converted operands
  logic [4:0]   fl_q;               // FP flags of earlier sub-steps

  // Op-level accumulators.
  logic [63:0] acc_q;      // reduction accumulator / mask word
  logic [9:0]  cnt_q;      // viota / vcpop count, vcompress pointer
  logic        cnt_ok_q;   // vcompress pointer still inside the group
  logic        seen_q;     // vmsbf/vmsif/vmsof
  logic        sat_q;
  logic [4:0]  ff_q;
  logic [63:0] sres_q;     // scalar result

  // ------------------------------------------------------------
  // S2: execute
  // ------------------------------------------------------------
  logic        s2_done;    // element (slot) completes this cycle
  logic        s2_we, s2_wfull;
  logic [7:0]  s2_wfbe, w_fbe_q, mvr_be0_q;  // full-word byte mask
  logic [7:0]  s2_waddr;
  logic [2:0]  s2_ww, s2_woff;
  logic [63:0] s2_wdata;
  // S3 write-back register: the S2 result (raw element or whole
  // word) is placed into its word with byte enables one cycle
  // later, keeping the formatting shifter off the execute path.
  logic        w_v_q, w_full_q;
  logic [7:0]  w_addr_q;
  logic [2:0]  w_w_q, w_off_q;
  logic [63:0] w_d_q;

  logic s2_free, s1_ready, s1_adv, s1_free, s0_issue;
  assign s2_free = !s2_v_q || s2_done;
  assign s1_ready = !(is_gvv && (s1_kind_q == K_ELEM) && !s1_ph_q);
  assign s1_adv = s1_v_q && s1_ready && s2_free;
  assign s1_free = !s1_v_q || s1_adv;
  assign s0_issue = run_q && (s0_ph_q != PH_END) && s1_free;

  // ---- Element operands in S2 ----
  logic [63:0] a, b, a_s, b_s, old_el, ones_s, ones_v;
  logic [5:0]  shamt, shamt_w;
  int unsigned shamt_bits;
  assign a = s2_a_q;
  assign b = s2_b_q;
  assign old_el = s2_old_q;
  assign a_s = sext_el(a, aw_q);
  assign b_s = sext_el(b, sew_q);
  assign ones_s = ones_w(sew_q);
  assign ones_v = ones_w(dw_q);
  assign shamt_bits = 3 + int'(sew_q);  // log2(SEW)
  // The VI shift amount is the zero-extended 5-bit immediate.
  assign shamt = ((form_q == VFORM_VI) ? {1'b0, b[4:0]} : b[5:0]) &
                 6'((7'd1 << shamt_bits) - 7'd1);
  assign shamt_w = ((form_q == VFORM_VI) ? {1'b0, b[4:0]} : b[5:0]) &
                   6'((7'd1 << (shamt_bits + 1)) - 7'd1);

  // ---- Single-cycle integer / fixed-point element result ----
  logic [63:0] r_int;
  logic        sat_int;
  /* verilator lint_off UNUSEDSIGNAL */
  always_comb begin
    logic signed [127:0] w128;
    logic [127:0] wv;
    r_int = a;
    sat_int = 1'b0;
    w128 = '0;
    wv = '0;
    unique case (op_q)
      VOP_ADD: r_int = a + b;
      VOP_SUB: r_int = a - b;
      VOP_RSUB: r_int = b - a;
      VOP_AND: r_int = a & b;
      VOP_OR: r_int = a | b;
      VOP_XOR: r_int = a ^ b;
      VOP_SLL: r_int = a << shamt;
      VOP_SRL: r_int = (a & ones_v) >> shamt;
      VOP_SRA: r_int = 64'(signed'(a_s) >>> shamt);
      VOP_MV: r_int = b;
      VOP_MVSX: r_int = scalar_q;
      VOP_MIN: r_int = (signed'(a_s) < signed'(b_s)) ? a : b;
      VOP_MINU: r_int = ((a & ones_v) < (b & ones_v)) ? a : b;
      VOP_MAX: r_int = (signed'(a_s) > signed'(b_s)) ? a : b;
      VOP_MAXU: r_int = ((a & ones_v) > (b & ones_v)) ? a : b;
      VOP_ADC: r_int = a + b + {63'd0, s2_m_q};
      VOP_SBC: r_int = a - b - {63'd0, s2_m_q};
      VOP_MERGE: r_int = s2_m_q ? b : a;
      VOP_SADD: r_int = sat_s(signed'({{64{a_s[63]}}, a_s}) +
                              signed'({{64{b_s[63]}}, b_s}), sew_q, sat_int);
      VOP_SADDU: r_int = sat_u({64'd0, a & ones_v} + {64'd0, b & ones_v},
                               sew_q, sat_int);
      VOP_SSUB: r_int = sat_s(signed'({{64{a_s[63]}}, a_s}) -
                              signed'({{64{b_s[63]}}, b_s}), sew_q, sat_int);
      VOP_SSUBU: begin
        wv = {64'd0, a & ones_v} - {64'd0, b & ones_v};
        sat_int = wv[127];
        r_int = sat_int ? 64'd0 : wv[63:0];
      end
      VOP_AADD: begin
        w128 = signed'({{64{a_s[63]}}, a_s}) + signed'({{64{b_s[63]}}, b_s});
        wv = rnd_shift(128'(w128), 1, 1'b1, vxrm_q);
        r_int = wv[63:0];
      end
      VOP_AADDU: begin
        wv = rnd_shift({64'd0, a & ones_v} + {64'd0, b & ones_v}, 1, 1'b0,
                       vxrm_q);
        r_int = wv[63:0];
      end
      VOP_ASUB: begin
        w128 = signed'({{64{a_s[63]}}, a_s}) - signed'({{64{b_s[63]}}, b_s});
        wv = rnd_shift(128'(w128), 1, 1'b1, vxrm_q);
        r_int = wv[63:0];
      end
      VOP_ASUBU: begin
        wv = rnd_shift({64'd0, a & ones_v} - {64'd0, b & ones_v}, 1, 1'b0,
                       vxrm_q);
        r_int = wv[63:0];
      end
      VOP_SSRL: begin
        wv = rnd_shift({64'd0, a & ones_v}, int'(shamt), 1'b0, vxrm_q);
        r_int = wv[63:0];
      end
      VOP_SSRA: begin
        wv = rnd_shift(128'(signed'(a_s)), int'(shamt), 1'b1, vxrm_q);
        r_int = wv[63:0];
      end
      VOP_WADD, VOP_WADDW: r_int = a_s + b_s;
      VOP_WSUB, VOP_WSUBW: r_int = a_s - b_s;
      // Widening unsigned forms zero-extend both sources.
      VOP_WADDU, VOP_WADDUW: r_int = a + (b & ones_s);
      VOP_WSUBU, VOP_WSUBUW: r_int = a - (b & ones_s);
      VOP_NSRL: r_int = a >> shamt_w;
      VOP_NSRA: r_int = 64'(signed'(a_s) >>> shamt_w);
      VOP_NCLIP: r_int = sat_s(signed'(rnd_shift(128'(signed'(a_s)),
                                                 int'(shamt_w), 1'b1, vxrm_q)),
                               sew_q, sat_int);
      VOP_NCLIPU: r_int = sat_u(rnd_shift({64'd0, a}, int'(shamt_w), 1'b0,
                                          vxrm_q), sew_q, sat_int);
      VOP_EXT: r_int = imm_q[0] ? a_s : a;
      VOP_ID: r_int = 64'(s2_i_q);
      VOP_IOTA: r_int = 64'(cnt_q);
      // Permutations: a is the source element S0 selected.
      VOP_GATHER, VOP_GATHEREI16, VOP_SLIDEDOWN:
        r_int = s2_skip_q ? 64'd0 : a;
      VOP_SLIDE1UP, VOP_SLIDE1DOWN: r_int = s2_skip_q ? scalar_q : a;
      default: r_int = a;  // vslideup, vcompress
    endcase
  end
  /* verilator lint_on UNUSEDSIGNAL */

  // ---- Mask-destination bit ----
  logic mbit;
  logic src_act;     // in range (by construction) and mask-enabled
  logic [64:0] carry_w;
  assign src_act = vm_q || s2_m_q;
  always_comb begin
    carry_w = '0;
    unique case (op_q)
      VOP_CMPEQ: mbit = (a & ones_v) == (b & ones_v);
      VOP_CMPNE: mbit = (a & ones_v) != (b & ones_v);
      VOP_CMPLTU: mbit = (a & ones_v) < (b & ones_v);
      VOP_CMPLT: mbit = signed'(a_s) < signed'(b_s);
      VOP_CMPLEU: mbit = (a & ones_v) <= (b & ones_v);
      VOP_CMPLE: mbit = signed'(a_s) <= signed'(b_s);
      VOP_CMPGTU: mbit = (a & ones_v) > (b & ones_v);
      VOP_CMPGT: mbit = signed'(a_s) > signed'(b_s);
      VOP_MADC: begin
        carry_w = {1'b0, a & ones_v} + {1'b0, b & ones_v} +
                  {64'd0, (vm_q ? 1'b0 : s2_m_q)};
        mbit = carry_w[7'd8 << sew_q];
      end
      VOP_MSBC: begin
        carry_w = {1'b0, a & ones_v} - {1'b0, b & ones_v} -
                  {64'd0, (vm_q ? 1'b0 : s2_m_q)};
        mbit = carry_w[64];
      end
      VOP_MLOG: begin
        unique case (imm_q[2:0])
          3'd0: mbit = s2_abit_q & ~s2_bbit_q;     // vmandn
          3'd1: mbit = s2_abit_q & s2_bbit_q;      // vmand
          3'd2: mbit = s2_abit_q | s2_bbit_q;      // vmor
          3'd3: mbit = s2_abit_q ^ s2_bbit_q;      // vmxor
          3'd4: mbit = s2_abit_q | ~s2_bbit_q;     // vmorn
          3'd5: mbit = ~(s2_abit_q & s2_bbit_q);   // vmnand
          3'd6: mbit = ~(s2_abit_q | s2_bbit_q);   // vmnor
          default: mbit = ~(s2_abit_q ^ s2_bbit_q);// vmxnor
        endcase
      end
      default: begin  // VOP_MSBIT (VOP_FCMP comes from the FP step)
        unique case (imm_q[1:0])
          2'd1: mbit = !seen_q && !(src_act && s2_abit_q); // vmsbf
          2'd2: mbit = src_act && s2_abit_q && !seen_q;    // vmsof
          default: mbit = !seen_q;                         // vmsif
        endcase
      end
    endcase
  end

  // ---- Multiplier operand selection (prep step) ----
  logic [63:0] mul_x, mul_y;
  logic        mul_sx, mul_sy;
  always_comb begin
    mul_x = a;
    mul_y = b;
    mul_sx = 1'b0;
    mul_sy = 1'b0;
    unique case (op_q)
      VOP_MADD, VOP_NMSUB: begin mul_x = b; mul_y = old_el; end
      VOP_MULH, VOP_SMUL, VOP_WMUL, VOP_WMACC: begin
        mul_sx = 1'b1; mul_sy = 1'b1;
      end
      VOP_MULHSU, VOP_WMULSU, VOP_WMACCUS: mul_sx = 1'b1;
      VOP_WMACCSU: mul_sy = 1'b1;
      default: ;
    endcase
  end
  logic [63:0] mxv, myv;
  logic        mxn, myn;
  assign mxv = mul_sx ? sext_el(mul_x & ones_s, sew_q) : (mul_x & ones_s);
  assign myv = mul_sy ? sext_el(mul_y & ones_s, sew_q) : (mul_y & ones_s);
  assign mxn = mul_sx && mxv[63];
  assign myn = mul_sy && myv[63];
  // Steps: 0 prep, 1..nch accumulate (top chunk first),
  // nch+1 sign, nch+2 post (round/saturate/accumulate),
  // nch+3 write.
  logic [6:0] mul_nch;
  assign mul_nch = (sew_q <= 3'd1) ? 7'd1 : (sew_q == 3'd2) ? 7'd2 : 7'd4;
  logic [1:0]  mul_ci;
  logic [15:0] mul_chunk;
  logic [79:0] mul_pp;
  assign mul_ci = 2'(mul_nch - s2_step_q);
  assign mul_chunk = my_q[{mul_ci, 4'b0000} +: 16];
  assign mul_pp = 80'(mx_q) * 80'(mul_chunk);
  // Post-processing of the signed 128-bit product.
  logic [63:0] r_mul;
  logic        sat_mul;
  always_comb begin
    logic signed [127:0] p;
    p = signed'(macc_q);
    sat_mul = 1'b0;
    unique case (op_q)
      VOP_MULH, VOP_MULHU, VOP_MULHSU: r_mul = 64'(p >>> (7'd8 << sew_q));
      VOP_MACC, VOP_WMACC, VOP_WMACCU, VOP_WMACCSU, VOP_WMACCUS:
        r_mul = old_el + p[63:0];
      VOP_NMSAC: r_mul = old_el - p[63:0];
      VOP_MADD: r_mul = p[63:0] + a;
      VOP_NMSUB: r_mul = a - p[63:0];
      VOP_SMUL: r_mul = sat_s(signed'(rnd_shift(128'(p), (8 << sew_q) - 1,
                                                1'b1, vxrm_q)),
                              sew_q, sat_mul);
      default: r_mul = p[63:0];  // vmul, vwmul*
    endcase
  end

  // ---- Divider ----
  logic [6:0]  div_n;        // SEW bits = iterations
  logic        div_signed;
  logic [63:0] dvd_v, dvs_v;
  assign div_n = 7'd8 << sew_q;
  assign div_signed = (op_q == VOP_DIV) || (op_q == VOP_REM);
  assign dvd_v = div_signed ? sext_el(a & ones_s, sew_q) : (a & ones_s);
  assign dvs_v = div_signed ? sext_el(b & ones_s, sew_q) : (b & ones_s);
  logic        dvd_n, dvs_n;  // operand signs (signed forms only)
  assign dvd_n = div_signed && dvd_v[63];
  assign dvs_n = div_signed && dvs_v[63];
  logic [64:0] div_t;
  logic        div_ge;
  assign div_t = {drem_q[63:0], dquo_q[63]};
  assign div_ge = div_t >= {1'b0, my_q};
  logic [63:0] r_div;
  always_comb begin
    if ((b & ones_s) == 64'd0) begin
      r_div = ((op_q == VOP_DIV) || (op_q == VOP_DIVU)) ? ones_v : a;
    end else if ((op_q == VOP_DIV) || (op_q == VOP_DIVU)) begin
      r_div = mneg_q ? (64'd0 - dquo_q) : dquo_q;
    end else begin
      r_div = rneg_q ? (64'd0 - drem_q[63:0]) : drem_q[63:0];
    end
  end

  // ---- FP element sub-steps (shared multi-cycle FPU) ----
  // Each FP sub-step is one operation on the core's scalar FPU
  // (fpu_* ports), or for vfrec7/vfrsqrt7 a two-cycle estimate
  // here (unpack, then table and pack). Vector elements are raw
  // SEW-bit values; SEW=32 operands are presented NaN-boxed
  // (the scalar convention).
  logic [6:0]  fp_nst;       // sub-steps for this element
  logic        fp_last;
  logic [4:0]  fp_op;
  logic        fp_dbl, fp_est, fp_rsqrt;
  logic [2:0]  fp_rm;
  logic [63:0] fp_a, fp_b, fp_c;
  logic [1:0]  fp_aux;
  fp_eval_result_t fp_res;   // registered sub-step result (fr_q)
  logic [63:0] nb_a, nb_b, nb_old;
  assign nb_a = (sew_q == 3'd2) ? {32'hffff_ffff, a[31:0]} : a;
  assign nb_b = ((form_q == VFORM_VV) && (sew_q == 3'd2))
                ? {32'hffff_ffff, b[31:0]} : b;
  assign nb_old = (sew_q == 3'd2) ? {32'hffff_ffff, old_el[31:0]} : old_el;
  always_comb begin
    fp_nst = 7'd1;
    if (op_q == VOP_FMACCW) fp_nst = 7'd3;
    else if (op_q == VOP_FBINW) fp_nst = imm_q[7] ? 7'd2 : 7'd3;
    else if (op_q == VOP_FWRED) fp_nst = 7'd2;
  end
  // FBINW with imm[7] (.w forms) skips the vs2 conversion: its
  // steps are numbered from 1.
  logic [6:0] fp_step;
  assign fp_step = ((op_q == VOP_FBINW) && imm_q[7]) ? (s2_step_q + 7'd1)
                                                     : s2_step_q;
  assign fp_last = (s2_step_q == (fp_nst - 7'd1));
  always_comb begin
    logic [63:0] x;
    x = 64'd0;
    fp_op = FPU_F2F;
    fp_dbl = 1'b1;
    fp_rm = frm_q;
    fp_a = 64'd0;
    fp_b = 64'd0;
    fp_c = 64'd0;
    fp_aux = 2'd0;
    fp_est = 1'b0;
    fp_rsqrt = 1'b0;
    unique case (op_q)
      VOP_FBIN: begin
        fp_op = imm_q[4:0];
        fp_dbl = (sew_q == 3'd3);
        fp_a = imm_q[7] ? nb_b : nb_a;   // vfrsub / vfrdiv swap
        fp_b = imm_q[7] ? nb_a : nb_b;
        fp_aux = imm_q[6:5];
      end
      VOP_FBINW: begin
        // SEW=32 sources widen to double (exactly, except
        // sNaN signaling); .w forms read vs2 as doubles.
        if (fp_step == 7'd0) begin
          fp_a = {32'hffff_ffff, a[31:0]};
        end else if (fp_step == 7'd1) begin
          fp_a = (form_q == VFORM_VV) ? {32'hffff_ffff, b[31:0]} : b;
        end else begin
          fp_op = imm_q[4:0];
          fp_a = imm_q[7] ? a : fa_q;
          fp_b = fb_q;
          fp_aux = imm_q[6:5];
        end
      end
      VOP_FMACC, VOP_FMACCW: begin
        // macc: vd = vs2*vs1 + vd; madd (imm[7]): vd = vs1*vd + vs2.
        // Vector funct6[1:0] (imm[6:5]): 00 macc (+p+c), 01 nmacc
        // (-p-c), 10 msac (+p-c), 11 nmsac (-p+c).
        if ((op_q == VOP_FMACCW) && (s2_step_q == 7'd0)) begin
          fp_a = nb_a;
        end else if ((op_q == VOP_FMACCW) && (s2_step_q == 7'd1)) begin
          fp_a = nb_b;
        end else begin
          fp_op = (imm_q[6] ^ imm_q[5]) ? (imm_q[5] ? FPU_FNMA : FPU_FMS)
                                        : (imm_q[5] ? FPU_FNMS : FPU_FMA);
          fp_dbl = (op_q == VOP_FMACCW) || (sew_q == 3'd3);
          fp_aux = imm_q[6:5];
          x = (op_q == VOP_FMACCW) ? fa_q : nb_a;
          fp_b = (op_q == VOP_FMACCW) ? fb_q : nb_b;
          fp_c = (op_q == VOP_FMACCW) ? old_el : nb_old;
          fp_a = imm_q[7] ? fp_c : x;
          if (imm_q[7]) fp_c = x;
        end
      end
      VOP_FCMP: begin
        // imm[2:0]: 0 eq, 1 ne, 2 lt, 3 le, 4 gt, 5 ge. gt/ge
        // swap operands; ne inverts eq. Scalar CMP aux: 0 le,
        // 1 lt, 2 eq (quiet for eq, signaling otherwise).
        fp_op = FPU_CMP;
        fp_dbl = (sew_q == 3'd3);
        fp_a = (imm_q[2:0] >= 3'd4) ? nb_b : nb_a;
        fp_b = (imm_q[2:0] >= 3'd4) ? nb_a : nb_b;
        fp_aux = ((imm_q[2:0] == 3'd3) || (imm_q[2:0] == 3'd5)) ? 2'd0 :
                 ((imm_q[2:0] == 3'd2) || (imm_q[2:0] == 3'd4)) ? 2'd1 : 2'd2;
      end
      VOP_FUNARY: begin
        // imm[1:0]: 0 sqrt, 1 class, 2 rsqrt7, 3 rec7.
        fp_op = (imm_q[1:0] == 2'd0) ? FPU_SQRT : FPU_CLASS;
        fp_dbl = (sew_q == 3'd3);
        fp_a = nb_a;
        fp_est = imm_q[1:0] >= 2'd2;
        fp_rsqrt = imm_q[1:0] == 2'd2;
      end
      VOP_FCVT: begin
        // Sub-op imm[4:0] (the vs1 field): 0..7 plain, 8..15
        // widening, 16..23 narrowing; low bits 0 xu.f, 1 x.f,
        // 2 f.xu, 3 f.x, 4 f.f, 5 rod, 6/7 rtz x(u).f.
        unique case (imm_q[2:0])
          3'd0, 3'd1, 3'd6, 3'd7: begin  // float -> int
            fp_op = FPU_F2I;
            fp_dbl = (aw_q == 3'd3);
            fp_rm = (imm_q[2:0] >= 3'd6) ? 3'b001 : frm_q;
            fp_a = (aw_q == 3'd2) ? {32'hffff_ffff, a[31:0]} : a;
            fp_aux = {(dw_q == 3'd3),
                      (imm_q[2:0] == 3'd0) || (imm_q[2:0] == 3'd6)};
          end
          3'd2, 3'd3: begin  // int -> float
            fp_op = FPU_I2F;
            fp_dbl = (dw_q == 3'd3);
            fp_a = a;
            fp_aux = {(aw_q == 3'd3), (imm_q[2:0] == 3'd2)};
          end
          default: begin  // float -> float (narrow/widen)
            fp_op = FPU_F2F;
            fp_dbl = (dw_q == 3'd3);
            fp_rm = (imm_q[2:0] == 3'd5) ? 3'b101 : frm_q;
            fp_a = (aw_q == 3'd2) ? {32'hffff_ffff, a[31:0]} : a;
          end
        endcase
      end
      VOP_FRED, VOP_FWRED: begin
        // Fold into acc (seeded by vs1[0]); imm[1:0]: 0 usum,
        // 1 osum, 2 min, 3 max. Both sums fold sequentially.
        if ((op_q == VOP_FWRED) && (s2_step_q == 7'd0)) begin
          fp_a = {32'hffff_ffff, a[31:0]};
        end else begin
          fp_op = (imm_q[1:0] < 2'd2) ? FPU_ADD : FPU_MINMAX;
          fp_dbl = (op_q == VOP_FWRED) || (sew_q == 3'd3);
          fp_a = acc_q;
          fp_b = (op_q == VOP_FWRED) ? fa_q : nb_a;
          fp_aux = {1'b0, imm_q[0]};
        end
      end
      default: ;
    endcase
  end
  // Sub-step sequencing. An active FP element (fp_need) waits
  // (fp_wait) until its sub-step result is registered in fr_q
  // (fr_v_q); that result is consumed the next cycle, either by
  // an intermediate step (fa_q/fb_q, step + 1) or by the element
  // completion (fp_ok). Operands come from S2 registers only and
  // stay stable while the FPU works (it samples them at issue).
  logic            fp_need, fp_wait, fp_ok;
  logic            fr_v_q, est_v_q;
  fp_eval_result_t fr_q;
  unpacked_t       eu_q;      // estimate operand, unpacked
  assign fp_need = s2_v_q && (s2_kind_q == K_ELEM) && is_fp && src_act;
  assign fp_wait = fp_need && !fr_v_q;
  assign fp_ok = fr_v_q && fp_last;
  assign fp_res = fr_q;
  assign fpu_req_o = fp_wait && !fp_est;
  assign fpu_op_o = fp_op;
  assign fpu_fmt_d_o = fp_dbl;
  assign fpu_rm_o = fp_rm;
  assign fpu_a_o = fp_a;
  assign fpu_b_o = fp_b;
  assign fpu_c_o = fp_c;
  assign fpu_aux_o = fp_aux;
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      fr_v_q <= 1'b0;
      est_v_q <= 1'b0;
    end else if (kill_i) begin
      fr_v_q <= 1'b0;
      est_v_q <= 1'b0;
    end else begin
      // A registered result is always consumed the next cycle.
      fr_v_q <= (fpu_req_o && fpu_done_i) || est_v_q;
      est_v_q <= fp_wait && fp_est && !est_v_q;
    end
  end
  always_ff @(posedge clk_i) begin
    if (fpu_req_o && fpu_done_i) begin
      fr_q.result <= fpu_result_i;
      fr_q.flags <= fpu_flags_i;
    end else if (est_v_q) begin
      fr_q <= fp_est_fin(fp_rsqrt, fp_dbl, fp_rm, eu_q);
    end
    if (fp_wait && fp_est && !est_v_q) eu_q <= unpack(fp_a, fp_dbl);
  end
`ifndef SYNTHESIS
  // Simulation cross-check: every FP sub-step result equals the
  // combinational reference (fp_eval / fp_estimate) on the
  // operands it was issued with. Armed by the first reset edge:
  // before reset the state is arbitrary (e.g. under
  // +verilator+rand+reset+2) and must not be checked.
  logic chk_armed;
  initial chk_armed = 1'b0;
  always @(posedge clk_i or negedge rst_ni) if (!rst_ni) chk_armed <= 1'b1;
  always_ff @(posedge clk_i) begin
    fp_eval_result_t chk;
    if (chk_armed && !kill_i && fpu_req_o && fpu_done_i) begin
      chk = fp_eval(fp_op, fp_dbl, fp_rm, fp_a, fp_b, fp_c, fp_aux);
      if ((chk.result != fpu_result_i) || (chk.flags != fpu_flags_i))
        $error("muserisc_vec: FPU op %0d d=%0d rm=%0d a=%h b=%h c=%h aux=%0d: got %h/%h, fp_eval %h/%h",
               fp_op, fp_dbl, fp_rm, fp_a, fp_b, fp_c, fp_aux,
               fpu_result_i, fpu_flags_i, chk.result, chk.flags);
    end
    if (chk_armed && !kill_i && est_v_q) begin
      chk = fp_estimate(fp_rsqrt, fp_dbl, fp_rm, fp_a);
      if (chk != fp_est_fin(fp_rsqrt, fp_dbl, fp_rm, eu_q))
        $error("muserisc_vec: estimate rsqrt=%0d d=%0d a=%h mismatch",
               fp_rsqrt, fp_dbl, fp_a);
    end
  end
`endif

  // ---- S2 control / write-back ----
  logic active;       // element-wise op: element written
  logic [9:0] wi;     // destination element index
  logic [63:0] r_el;
  logic [63:0] mword; // mask word incl. this element's bit
  logic        bit_wr;// this element updates its mask bit
  logic        bit_v;
  always_comb begin
    s2_done = 1'b0;
    s2_we = 1'b0;
    s2_waddr = 8'd0;
    s2_wfull = 1'b0;
    s2_wfbe = 8'hff;
    s2_ww = dw_q;
    s2_woff = 3'd0;
    s2_wdata = 64'd0;
    active = 1'b0;
    wi = s2_i_q;
    r_el = r_int;
    bit_wr = 1'b0;
    bit_v = mbit;
    mword = (s2_first_q || (s2_i_q[5:0] == 6'd0)) ? s2_cw_q : acc_q;
    if (s2_v_q) begin
      unique case (s2_kind_q)
        K_SEED: s2_done = 1'b1;
        K_FIN: begin
          s2_done = 1'b1;
          if (vl10_q != 10'd0) begin
            s2_we = 1'b1;
            s2_waddr = {vd_q, 3'b000};
            s2_ww = (op_q == VOP_FWRED) ? 3'd3 : dw_q;
            s2_wdata = acc_q;
          end
        end
        default: begin  // K_ELEM
          if (is_mvr) begin
            s2_done = 1'b1;
            s2_we = 1'b1;
            s2_waddr = {vd_q, 3'b000} + 8'(s2_i_q);
            s2_wfull = 1'b1;
            s2_wfbe = s2_first_q ? mvr_be0_q : 8'hff;
            s2_wdata = a;
          end else if (is_scalar_op || is_red) begin
            // Scalar results and reduction folds write nothing
            // per element (multi-step FP folds hold S2).
            s2_done = !((op_q == VOP_FRED) || (op_q == VOP_FWRED)) ||
                      !src_act || fp_ok;
          end else if (is_mask_dest) begin
            if (op_q == VOP_FCMP) begin
              bit_v = fp_res.result[0] ^ (imm_q[2:0] == 3'd1);
              bit_wr = src_act;
            end else if ((op_q == VOP_MADC) || (op_q == VOP_MSBC) ||
                         (op_q == VOP_MLOG)) begin
              bit_wr = 1'b1;  // no element masking
            end else begin
              bit_wr = src_act;  // compares and vmsbf family
            end
            if (bit_wr) mword[s2_i_q[5:0]] = bit_v;
            // An active vmf* element waits for its FPU compare.
            s2_done = (op_q != VOP_FCMP) || !src_act || fp_ok;
            if (s2_done && (s2_last_q || (s2_i_q[5:0] == 6'd63))) begin
              s2_we = 1'b1;
              s2_waddr = bit_addr(vd_q, s2_i_q);
              s2_wfull = 1'b1;
              s2_wdata = mword;
            end
          end else begin
            // Element-wise classes.
            active = (unmasked_op || vm_q || s2_m_q) &&
                     !((op_q == VOP_SLIDEUP) && s2_skip_q);
            if (op_q == VOP_COMPRESS) begin
              active = s2_bbit_q && cnt_ok_q;
              wi = cnt_q;
            end
            if (is_mul && active) begin
              s2_done = (s2_step_q == (mul_nch + 7'd3));
              r_el = mres_q;
            end else if (is_div && active) begin
              s2_done = (s2_step_q == (div_n + 7'd1));
              r_el = r_div;
            end else if (is_fp && active) begin
              s2_done = fp_ok;
              r_el = fp_res.result;
            end else begin
              s2_done = 1'b1;
            end
            if (active && s2_done) begin
              s2_we = 1'b1;
              s2_waddr = el_addr(vd_q, wi, dw_q);
              s2_woff = el_off(wi, dw_q);
              s2_wdata = r_el;
            end
          end
        end
      endcase
    end
  end

  // ------------------------------------------------------------
  // S0 slot generation and VRF read addressing
  // ------------------------------------------------------------
  logic [1:0]  s0_kind;
  logic [9:0]  s0_ai;
  logic        s0_scal, s0_skip, s0_last;
  always_comb begin
    s0_kind = (s0_ph_q == PH_SEED) ? K_SEED :
              (s0_ph_q == PH_FIN) ? K_FIN : K_ELEM;
    s0_last = (i0_q == (end_q - 10'd1));
    s0_ai = i0_q;
    s0_scal = 1'b0;
    s0_skip = 1'b0;
    unique case (op_q)
      VOP_SLIDEUP: begin
        // Elements below the offset keep the old vd.
        s0_skip = !off_ok_q || (i0_q < off10_q);
        s0_ai = i0_q - off10_q;
      end
      VOP_SLIDEDOWN: begin
        s0_skip = !off_ok_q || (i0_q >= lim_q);  // reads zero
        s0_ai = i0_q + off10_q;
      end
      VOP_SLIDE1UP: begin
        s0_scal = (i0_q == 10'd0);
        s0_ai = i0_q - 10'd1;
      end
      VOP_SLIDE1DOWN: begin
        s0_scal = ((i0_q + 10'd1) >= vl10_q);
        s0_ai = i0_q + 10'd1;
      end
      VOP_GATHER: begin
        s0_skip = !gidx_ok_q;   // .vx/.vi; .vv resolves in S1
        s0_ai = gidx10_q;
      end
      default: ;
    endcase
    s0_skip = s0_skip || s0_scal;
  end

  // S1 gather resolution (second S1 cycle issues the vs2 read).
  logic [63:0] g_idx;
  logic        g_ok;
  assign g_idx = (op_q == VOP_GATHEREI16)
                 ? ext_el(rdata_b_i, s1_i_q, 3'd1)
                 : ext_el(rdata_b_i, s1_i_q, sew_q);
  assign g_ok = g_idx < {54'd0, vlmax10_q};
  logic s1_gissue;
  assign s1_gissue = s1_v_q && is_gvv && (s1_kind_q == K_ELEM) && !s1_ph_q;

  always_comb begin
    re_a_o = 1'b0;
    re_b_o = 1'b0;
    re_c_o = 1'b0;
    raddr_a_o = 8'd0;
    raddr_b_o = 8'd0;
    raddr_c_o = 8'd0;
    if (s1_gissue) begin
      re_a_o = 1'b1;
      raddr_a_o = el_addr(vs2_q, g_idx[9:0], sew_q);
    end else if (s0_issue) begin
      if (s0_kind == K_SEED) begin
        re_b_o = 1'b1;
        raddr_b_o = {vs1_q, 3'b000};
      end else if (s0_kind == K_ELEM) begin
        re_a_o = !is_gvv;
        re_b_o = 1'b1;
        re_c_o = 1'b1;
        if (is_mvr) raddr_a_o = {vs2_q, 3'b000} + 8'(i0_q);
        else if (is_mask_src) raddr_a_o = bit_addr(vs2_q, i0_q);
        else raddr_a_o = el_addr(vs2_q, s0_ai, aw_q);
        if ((op_q == VOP_COMPRESS) || (op_q == VOP_MLOG))
          raddr_b_o = bit_addr(vs1_q, i0_q);
        else if (op_q == VOP_GATHEREI16)
          raddr_b_o = el_addr(vs1_q, i0_q, 3'd1);
        else
          raddr_b_o = el_addr(vs1_q, i0_q, sew_q);
        raddr_c_o = is_mask_dest ? bit_addr(vd_q, i0_q)
                                 : el_addr(vd_q, i0_q, dw_q);
      end
    end
  end

  // S1 operand extraction.
  logic [63:0] x_a, x_b, x_old, x_seed;
  logic [2:0]  seed_w;
  assign seed_w = (op_q == VOP_FWRED) ? 3'd3 :
                  ((op_q == VOP_RED) || (op_q == VOP_FRED)) ? sew_q : dw_q;
  assign x_a = is_mvr ? rdata_a_i : ext_el(rdata_a_i, s1_ai_q, aw_q);
  assign x_b = (form_q == VFORM_VV) ? ext_el(rdata_b_i, s1_i_q, sew_q) :
               (form_q == VFORM_VX) ? scalar_q : imm_q;
  assign x_old = ext_el(rdata_c_i, s1_i_q, dw_q);
  assign x_seed = ext_el(rdata_b_i, 10'd0, seed_w);

  // ------------------------------------------------------------
  // Sequential state
  // ------------------------------------------------------------
  assign busy_o = run_q;
  assign done_o = run_q && (s0_ph_q == PH_END) && !s1_v_q && !s2_v_q &&
                  !w_v_q;
  assign we_o = w_v_q;
  assign waddr_o = w_addr_q;
  assign wbe_o = w_full_q ? w_fbe_q : (be_w(w_w_q) << w_off_q);
  assign wdata_o = w_full_q ? w_d_q
                            : ((w_d_q & ones_w(w_w_q)) << {w_off_q, 3'b000});
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      w_v_q <= 1'b0;
    end else begin
      w_v_q <= s2_we && !kill_i;
    end
  end
  always_ff @(posedge clk_i) begin
    if (s2_we) begin
      w_addr_q <= s2_waddr;
      w_full_q <= s2_wfull;
      w_fbe_q <= s2_wfbe;
      w_w_q <= s2_ww;
      w_off_q <= s2_woff;
      w_d_q <= s2_wdata;
    end
  end
  assign scalar_o = sres_q;
  assign sat_o = sat_q;
  assign fflags_o = ff_q;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      run_q <= 1'b0;
      s0_ph_q <= PH_END;
      s1_v_q <= 1'b0;
      s2_v_q <= 1'b0;
    end else if (kill_i) begin
      run_q <= 1'b0;
      s0_ph_q <= PH_END;
      s1_v_q <= 1'b0;
      s2_v_q <= 1'b0;
    end else if (!run_q) begin
      if (start_i) begin
        run_q <= 1'b1;
        if (f_red(op_i)) s0_ph_q <= PH_SEED;
        else s0_ph_q <= (beg_i < end_i) ? PH_ELEM : PH_END;
      end
    end else begin
      if (done_o && ack_i) run_q <= 1'b0;
      if (s0_issue) begin
        unique case (s0_ph_q)
          PH_SEED: s0_ph_q <= (beg_q < end_q) ? PH_ELEM : PH_FIN;
          PH_ELEM: if (s0_last) s0_ph_q <= is_red ? PH_FIN : PH_END;
          default: s0_ph_q <= PH_END;
        endcase
      end
      if (s0_issue) s1_v_q <= 1'b1;
      else if (s1_adv) s1_v_q <= 1'b0;
      if (s1_adv) s2_v_q <= 1'b1;
      else if (s2_done) s2_v_q <= 1'b0;
    end
  end

  always_ff @(posedge clk_i) begin
    if (start_i && !run_q) begin
      op_q <= op_i;
      form_q <= form_i;
      sew_q <= sew_i;
      dw_q <= dw_i;
      aw_q <= aw_i;
      vm_q <= vm_i;
      vs2_q <= vs2_i;
      vs1_q <= vs1_i;
      vd_q <= vd_i;
      scalar_q <= scalar_i;
      imm_q <= imm_i;
      vxrm_q <= vxrm_i;
      frm_q <= frm_i;
      vl10_q <= vl10_i;
      vlmax10_q <= (vlmax_i > 64'd512) ? 10'd512 : vlmax_i[9:0];
      beg_q <= beg_i;
      mvr_be0_q <= 8'hff << mvr_boff_i[2:0];
      end_q <= end_i;
      i0_q <= beg_i;
      // Slides: vslideup needs offset < 512 to place anything;
      // vslidedown reads vs2[i+off] while i+off < VLMAX.
      if (op_i == VOP_SLIDEDOWN) begin
        off_ok_q <= off64_i < vlmax_i;
        lim_q <= vlmax_i[9:0] - off64_i[9:0];
      end else begin
        off_ok_q <= off64_i < 64'd512;
        lim_q <= 10'd0;
      end
      off10_q <= off64_i[9:0];
      gidx10_q <= gidx64_i[9:0];
      gidx_ok_q <= gidx64_i < vlmax_i;
      // Op-level accumulators.
      cnt_q <= (op_i == VOP_COMPRESS) ? vstart10_i : 10'd0;
      cnt_ok_q <= vstart_i < (64'd512 >> sew_i);
      seen_q <= 1'b0;
      sat_q <= 1'b0;
      ff_q <= 5'd0;
      // vfirst with no set active bit returns -1.
      sres_q <= (op_i == VOP_FIRST) ? 64'hffff_ffff_ffff_ffff : 64'd0;
    end else if (run_q) begin
      if (s0_issue && (s0_ph_q == PH_ELEM)) i0_q <= i0_q + 10'd1;

      // ---- S0 -> S1 ----
      if (s0_issue) begin
        s1_kind_q <= s0_kind;
        s1_i_q <= i0_q;
        s1_ai_q <= s0_ai;
        s1_m_q <= v0_i[i0_q[8:0]];
        s1_first_q <= (i0_q == beg_q);
        s1_last_q <= s0_last;
        s1_skip_q <= s0_skip;
        s1_ph_q <= 1'b0;
      end else if (s1_gissue) begin
        s1_ph_q <= 1'b1;
        s1_skip_q <= !g_ok;
        s1_ai_q <= g_idx[9:0];
      end

      // ---- S1 -> S2 ----
      if (s1_adv) begin
        s2_kind_q <= s1_kind_q;
        s2_i_q <= s1_i_q;
        s2_a_q <= (s1_kind_q == K_SEED) ? x_seed : x_a;
        s2_b_q <= x_b;
        s2_old_q <= x_old;
        s2_cw_q <= rdata_c_i;
        s2_abit_q <= rdata_a_i[s1_i_q[5:0]];
        s2_bbit_q <= rdata_b_i[s1_i_q[5:0]];
        s2_m_q <= s1_m_q;
        s2_first_q <= s1_first_q;
        s2_last_q <= s1_last_q;
        s2_skip_q <= s1_skip_q;
        s2_step_q <= 7'd0;
      end else if (s2_v_q && !s2_done && !fp_wait) begin
        s2_step_q <= s2_step_q + 7'd1;
      end

      // ---- S2 multi-cycle datapaths ----
      if (s2_v_q && (s2_kind_q == K_ELEM)) begin
        if (is_mul) begin
          if (s2_step_q == 7'd0) begin
            mx_q <= mxn ? (64'd0 - mxv) : mxv;
            my_q <= myn ? (64'd0 - myv) : myv;
            mneg_q <= mxn ^ myn;
            macc_q <= '0;
          end else if (s2_step_q <= mul_nch) begin
            macc_q <= (macc_q << 16) + {48'd0, mul_pp};
          end else if (s2_step_q == (mul_nch + 7'd1)) begin
            macc_q <= mneg_q ? (128'd0 - macc_q) : macc_q;
          end else if (s2_step_q == (mul_nch + 7'd2)) begin
            mres_q <= r_mul;
            msat_q <= sat_mul;
          end
        end
        if (is_div) begin
          if (s2_step_q == 7'd0) begin
            mneg_q <= dvd_n ^ dvs_n;
            rneg_q <= dvd_n;
            my_q <= dvs_n ? (64'd0 - dvs_v) : dvs_v;
            dquo_q <= (dvd_n ? (64'd0 - dvd_v) : dvd_v) << (7'd64 - div_n);
            drem_q <= '0;
          end else if (s2_step_q <= div_n) begin
            drem_q <= 64'(div_ge ? (div_t - {1'b0, my_q}) : div_t);
            dquo_q <= {dquo_q[62:0], div_ge};
          end
        end
        if (is_fp && fr_v_q && !fp_last) begin
          // Intermediate conversion results.
          if (((op_q == VOP_FBINW) && (fp_step == 7'd0)) ||
              ((op_q == VOP_FMACCW) && (s2_step_q == 7'd0)) ||
              (op_q == VOP_FWRED)) begin
            fa_q <= fp_res.result;
          end else begin
            fb_q <= fp_res.result;
          end
          fl_q <= ((s2_step_q == 7'd0) ? 5'd0 : fl_q) | fp_res.flags;
        end
      end

      // ---- Op-level accumulators (on element completion) ----
      if (s2_v_q && s2_done) begin
        if (s2_kind_q == K_SEED) begin
          if (op_q == VOP_FRED) begin
            acc_q <= (sew_q == 3'd2) ? {32'hffff_ffff, a[31:0]} : a;
          end else begin
            acc_q <= a;
          end
        end else if (s2_kind_q == K_ELEM) begin
          if (is_mask_dest) begin
            acc_q <= mword;
            if ((op_q == VOP_MSBIT) && src_act && s2_abit_q) seen_q <= 1'b1;
            if ((op_q == VOP_FCMP) && src_act) ff_q <= ff_q | fp_res.flags;
          end
          if (is_red && src_act) begin
            unique case (op_q)
              VOP_WRED: acc_q <= acc_q + (imm_q[0] ? a_s : a);
              VOP_FRED, VOP_FWRED: begin
                acc_q <= fp_res.result;
                ff_q <= ff_q | fp_res.flags |
                        ((op_q == VOP_FWRED) ? fl_q : 5'd0);
              end
              default: begin  // VOP_RED, imm[2:0] selects
                unique case (imm_q[2:0])
                  3'd0: acc_q <= (acc_q + a) & ones_v;
                  3'd1: acc_q <= acc_q & a;
                  3'd2: acc_q <= acc_q | a;
                  3'd3: acc_q <= acc_q ^ a;
                  3'd4: if (!((acc_q & ones_v) < a)) acc_q <= a;
                  3'd5: if (!(signed'(sext_el(acc_q, sew_q)) <
                              signed'(sext_el(a, sew_q)))) acc_q <= a;
                  3'd6: if (!((acc_q & ones_v) > a)) acc_q <= a;
                  default: if (!(signed'(sext_el(acc_q, sew_q)) >
                                 signed'(sext_el(a, sew_q)))) acc_q <= a;
                endcase
              end
            endcase
          end
          if (active) begin
            if ((is_mul && msat_q) || (!is_mul && !is_div && !is_fp && sat_int))
              sat_q <= 1'b1;
            if (is_fp) ff_q <= ff_q | fp_res.flags | ((fp_nst > 7'd1) ? fl_q : 5'd0);
          end
          if ((op_q == VOP_IOTA) && src_act && s2_abit_q) cnt_q <= cnt_q + 10'd1;
          if ((op_q == VOP_COMPRESS) && s2_bbit_q) begin
            if (cnt_q == ((10'd512 >> sew_q) - 10'd1)) cnt_ok_q <= 1'b0;
            cnt_q <= cnt_q + 10'd1;
          end
          if ((op_q == VOP_CPOP) && src_act && s2_abit_q) begin
            sres_q <= sres_q + 64'd1;
          end
          if ((op_q == VOP_FIRST) && src_act && s2_abit_q &&
              (sres_q == 64'hffff_ffff_ffff_ffff)) begin
            sres_q <= 64'(s2_i_q);
          end
          if (op_q == VOP_MVXS) sres_q <= sext_el(a, sew_q);
          if (op_q == VOP_FMVFS) begin
            sres_q <= (sew_q == 3'd2) ? {32'hffff_ffff, a[31:0]} : a;
          end
        end
      end
    end
  end

  // Unused-by-design bits (lint).
  logic unused;
  assign unused = ^{s2_cw_q[0],
                    mul_pp[79:76]};

endmodule
`default_nettype wire
