// museRISC in-house core: multi-cycle IEEE-754 binary32/binary64
// FPU (F+D) for the EX stage.
//
// One operation at a time, sequenced by a small FSM; every
// arithmetic step is a function from muserisc_fpu_pkg with a
// register after it, so the longest path is one stage function
// (a 53x27 partial product, a 128-bit shift or add, a log-depth
// normaliser, two radix-2 div/sqrt steps, or round-and-pack).
// The vector unit chains the same functions combinationally
// through fp_eval, so scalar and vector results cannot drift.
//
// Why multi-cycle rather than pipelined: the in-order core
// holds an FP instruction in EX until it completes (no
// out-of-order completion or scoreboard), so a pipelined FPU
// would never have a second op in flight; an FSM over shared
// stage registers gives the same throughput with less area.
//
// Stage sequence (cycle 0 = the cycle the op is in EX with
// req_i high and the FPU idle; latency = cycles in EX):
//
//   fsgnj*/fmv.*                IDLE(done)                    1
//   compare/min/max/class,
//   special operands (NaN/Inf,
//   0*Inf, x/0, sqrt(-x) ...)    IDLE  EX1(done)               2
//   fcvt.int.fp                 IDLE  EX1  F2I2(done)          3
//   fcvt.fp.int                 IDLE  NORM ROUND(done)         3
//   fcvt.s.d / fcvt.d.s         IDLE  EX1  ROUND(done)         3
//   fadd/fsub                   IDLE  EX1(align) ADD NORM ROUND 5
//   fmul                        IDLE  EX1(pp) MUL2 NORM ROUND  5
//   fmadd family                IDLE  EX1(pp) MUL2 ALIGN ADD
//                               NORM ROUND                     7
//   fdiv/fsqrt                  IDLE  EX1(init) ITER x n DSFIN
//                               ROUND        n = 13 (S), 28 (D)  17 / 32
//
// IDLE unpacks the (forwarded) operands into registers, so
// later stages never see the forwarding network.
//
// EX handshake (generic multi-cycle EX unit protocol, see
// docs/CORE.md "EX-stage multi-cycle units"):
//   req_i  - level: the instruction in EX uses this unit and is
//            not already excepting. Operands are sampled when
//            the unit is idle; later changes are ignored.
//   done_o - result_o/flags_o valid this cycle (may be in the
//            issue cycle for fast ops). The core stalls EX while
//            req_i && !done_o.
//   ack_i  - EX advances this cycle and consumes the result.
//            done without ack (e.g. an older access holds MEM)
//            parks the result in HOLD until acked.
//   kill_i - squash (trap/flush); dropping req_i also squashes.
`default_nettype none
module muserisc_fpu import muserisc_fpu_pkg::*; (
    input  wire         clk_i,
    input  wire         rst_ni,
    input  wire         req_i,
    input  wire         ack_i,
    input  wire         kill_i,
    input  wire  [4:0]  op_i,
    input  wire         fmt_d_i,
    input  wire  [2:0]  rm_i,        // resolved rounding mode
    input  wire  [63:0] a_i,         // rs1 (fp value or int bits)
    input  wire  [63:0] b_i,         // rs2
    input  wire  [63:0] c_i,         // rs3 (FMA addend)
    input  wire  [1:0]  aux_i,       // sgnj/min-max/cmp select, cvt int size
    output logic        done_o,
    output logic [63:0] result_o,    // fp result (boxed) or int result
    output logic [4:0]  flags_o      // NV DZ OF UF NX
);

  // Stage functions: module-local copies compiled from the same
  // source text as the package's (muserisc_fpu_ops.svh), so the
  // FPU and fp_eval cannot drift, and Verilator collects line
  // coverage of the arithmetic here.
  /* verilator lint_off UNUSEDSIGNAL */
  `include "muserisc_fpu_ops.svh"
  /* verilator lint_on UNUSEDSIGNAL */

  typedef enum logic [3:0] {
    S_IDLE, S_EX1, S_MUL2, S_ALIGN, S_ADD, S_NORM,
    S_ITER, S_DSFIN, S_F2I2, S_ROUND, S_HOLD
  } state_e;

  state_e      state_q, state_d;
  logic [4:0]  op_q;
  logic        d_q;
  logic [2:0]  rm_q;
  logic [1:0]  aux_q;
  unpacked_t   ua_q, ub_q, uc_q;
  fp_pp_t      pp_q;
  fp_align_t   al_q;
  fp_sum_t     sum_q;
  fp_rnd_t     rnd_q;
  fp_ds_t      ds_q, ds_next;
  fp_f2i_t     f2i_q;
  logic        ds_last;
  logic [63:0] res_q;
  logic [4:0]  flg_q;

  fp_special_t     sp;
  fp_eval_result_t rnd_out, f2i_out;
  fp_op_t          prod_op;

  assign sp      = fp_special(op_q, d_q, ua_q, ub_q, uc_q, aux_q);
  assign rnd_out = fp_round(rnd_q, d_q, rm_q);
  assign f2i_out = f2i_s2(f2i_q, aux_q);
  // FMA: the product parked in sum_q (as fop_sum) re-enters as
  // the first align operand.
  assign prod_op = '{sign: sum_q.sign, exp: sum_q.exp,
                     sig: sum_q.mag[125:20]};
  localparam int DsCycD = FPU_DS_N_D / FPU_DS_BITS;  // cycles in ITER
  localparam int DsCycS = FPU_DS_N_S / FPU_DS_BITS;
  // ITER cycle counter, sized for the longest (binary64) count.
  localparam int CntW = (DsCycD > 1) ? $clog2(DsCycD) : 1;
  logic [CntW-1:0] cnt_q;
  assign ds_last = (cnt_q == (d_q ? CntW'(DsCycD - 1) : CntW'(DsCycS - 1)));
  // Elaboration-time guards: the counter holds every step count
  // and the step count covers the p+2 recurrence bits.
  if ((DsCycD - 1) >= (1 << CntW) || DsCycS > DsCycD ||
      FPU_DS_N_D < 55 || FPU_DS_N_S < 26 || FPU_DS_BITS < 1) begin : gen_bad_ds_cfg
    $error("muserisc_fpu: bad div/sqrt iteration configuration");
  end

  always_comb begin
    ds_next = ds_q;
    for (int k = 0; k < FPU_DS_BITS; k++) ds_next = ds_step(ds_next);
  end

  // Completion and result select.
  always_comb begin
    done_o = 1'b0;
    result_o = res_q;
    flags_o = flg_q;
    unique case (state_q)
      S_IDLE: if (req_i && fp_is_fast(op_i)) begin
        done_o = 1'b1;
        result_o = fp_fastop(op_i, fmt_d_i, a_i, b_i, aux_i);
        flags_o = 5'd0;
      end
      S_EX1: if (sp.hit) begin
        done_o = 1'b1;
        result_o = sp.result;
        flags_o = sp.flags;
      end
      S_F2I2: begin
        done_o = 1'b1;
        result_o = f2i_out.result;
        flags_o = f2i_out.flags;
      end
      S_ROUND: begin
        done_o = 1'b1;
        result_o = rnd_out.result;
        flags_o = rnd_out.flags;
      end
      S_HOLD: done_o = 1'b1;
      default: ;
    endcase
  end

  always_comb begin
    state_d = state_q;
    if (kill_i || ((state_q != S_IDLE) && !req_i)) begin
      state_d = S_IDLE;
    end else if (done_o) begin
      state_d = ack_i ? S_IDLE : S_HOLD;
    end else begin
      unique case (state_q)
        S_IDLE: if (req_i) state_d = (op_i == FPU_I2F) ? S_NORM : S_EX1;
        S_EX1: begin
          unique case (op_q)
            FPU_ADD, FPU_SUB:   state_d = S_ADD;
            FPU_DIV, FPU_SQRT:  state_d = S_ITER;
            FPU_F2I:            state_d = S_F2I2;
            FPU_F2F:            state_d = S_ROUND;
            default:            state_d = S_MUL2;   // MUL, FMA family
          endcase
        end
        S_MUL2:  state_d = (op_q == FPU_MUL) ? S_NORM : S_ALIGN;
        S_ALIGN: state_d = S_ADD;
        S_ADD:   state_d = S_NORM;
        S_NORM:  state_d = S_ROUND;
        S_ITER:  if (ds_last) state_d = S_DSFIN;
        S_DSFIN: state_d = S_ROUND;
        // S_F2I2/S_ROUND/S_HOLD always complete (done_o above)
        /* verilator coverage_off */
        default: state_d = S_IDLE;
        /* verilator coverage_on */
      endcase
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) state_q <= S_IDLE;
    else         state_q <= state_d;
  end

  // Stage registers (no reset needed: each is written before
  // the state that reads it).
  always_ff @(posedge clk_i) begin
    unique case (state_q)
      S_IDLE: if (req_i) begin
        op_q  <= op_i;
        d_q   <= fmt_d_i;
        rm_q  <= rm_i;
        aux_q <= aux_i;
        ua_q  <= unpack(a_i, (op_i == FPU_F2F) ? !fmt_d_i : fmt_d_i);
        ub_q  <= unpack(b_i, fmt_d_i);
        uc_q  <= unpack(c_i, fmt_d_i);
        sum_q <= i2f_sum(a_i, aux_i);
      end
      S_EX1: begin
        al_q  <= fp_align(fop_unp(ua_q, 1'b0), fop_unp(ub_q, op_q == FPU_SUB));
        pp_q  <= fp_mul_pp(ua_q.sig, ub_q.sig);
        ds_q  <= ds_init(op_q == FPU_SQRT, ua_q, ub_q);
        cnt_q <= '0;
        f2i_q <= f2i_s1(ua_q, rm_q);
        rnd_q <= f2f_rnd(ua_q);
      end
      S_MUL2:  sum_q <= fop_sum(fop_prod(op_q, ua_q, ub_q, fp_mul_sum(pp_q)));
      S_ALIGN: al_q <= fp_align(prod_op, fop_unp(uc_q, fma_neg_c(op_q)));
      S_ADD:   sum_q <= fp_addsub(al_q, rm_q);
      S_NORM:  rnd_q <= fp_norm(sum_q);
      S_ITER: begin
        ds_q  <= ds_next;
        cnt_q <= cnt_q + 1'b1;
      end
      S_DSFIN: rnd_q <= ds_fin(ds_q, d_q);
      default: ;
    endcase
    if (done_o && !ack_i) begin
      res_q <= result_o;
      flg_q <= flags_o;
    end
  end

`ifndef SYNTHESIS
  // Simulation cross-check: every multi-cycle completion must
  // equal the combinational fp_eval chain (the vector path's
  // definition) on the operands sampled at issue.
  logic [4:0]  chk_op;
  logic        chk_d;
  logic [2:0]  chk_rm;
  logic [1:0]  chk_aux;
  logic [63:0] chk_a, chk_b, chk_c;
  fp_eval_result_t chk_ref;
  assign chk_ref = fp_eval(chk_op, chk_d, chk_rm, chk_a, chk_b, chk_c, chk_aux);
  // Armed by the first reset edge: before reset the state is
  // arbitrary (e.g. under +verilator+rand+reset+2).
  logic chk_armed;
  initial chk_armed = 1'b0;
  always @(posedge clk_i or negedge rst_ni) if (!rst_ni) chk_armed <= 1'b1;
  always_ff @(posedge clk_i) begin
    if ((state_q == S_IDLE) && req_i) begin
      chk_op <= op_i; chk_d <= fmt_d_i; chk_rm <= rm_i; chk_aux <= aux_i;
      chk_a <= a_i; chk_b <= b_i; chk_c <= c_i;
    end
    if (chk_armed && done_o && (state_q != S_IDLE) &&
        (state_q != S_HOLD) && !kill_i &&
        ((chk_ref.result != result_o) || (chk_ref.flags != flags_o)))
      $error("muserisc_fpu: op %0d d=%0d rm=%0d a=%h b=%h c=%h: got %h/%h, fp_eval %h/%h",
             chk_op, chk_d, chk_rm, chk_a, chk_b, chk_c, result_o, flags_o,
             chk_ref.result, chk_ref.flags);
  end
`endif

endmodule
`default_nettype wire
