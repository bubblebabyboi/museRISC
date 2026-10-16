// RV64M multiply/divide unit, multi-cycle (EX-stage unit).
//
// Same operation encoding and results as the combinational
// muserisc_muldiv: funct3 000 MUL, 001 MULH, 010 MULHSU, 011 MULHU,
// 100 DIV, 101 DIVU, 110 REM, 111 REMU; word_op_i selects the
// 32-bit W rule (low 32-bit operands, sign-extended result; MULW
// is the only word multiply, word funct3 001..011 are don't-care).
// RV64M edge cases: x/0 -> quotient all ones, remainder = dividend;
// most-negative / -1 -> quotient = dividend, remainder 0.
//
// EX handshake: the generic multi-cycle EX unit protocol shared
// with muserisc_fpu (docs/CORE.md "EX-stage multi-cycle units"):
//   req_i  - level: the instruction in EX uses this unit. Operands
//            are sampled in IDLE; later changes are ignored until
//            the operation completes, is acked, or is dropped.
//   done_o - result_o valid this cycle. The core stalls EX while
//            req_i && !done_o. done_o and result_o depend only on
//            unit registers (COMB=0), never on the operand inputs.
//   ack_i  - EX advances this cycle and consumes the result. Done
//            without ack (an older access holds MEM) keeps the
//            unit in its done state, result stable, until acked.
//   kill_i - squash (trap/flush); dropping req_i also squashes.
//
// Datapath (COMB=0). IDLE registers operands (with divide
// magnitudes, signs and the special-case result precomputed), so
// later stages never see the forwarding network.
//
//   op                         states                  done cycle
//   MUL/MULH/MULHSU/MULHU/MULW IDLE MUL1 MUL2(done)          2
//   DIV*/REM*, b == 0 or
//     signed overflow          IDLE PREP(done)               1
//   DIV*/REM* otherwise        IDLE PREP ITERxn FIX(done)  2+n
//
// (cycle 0 = the cycle req_i is first seen in IDLE.)
// Multiplier: 65x65 signed (operands sign- or zero-extended per
// op) split into four 33x33 signed partial products registered in
// MUL1 (each maps onto a 2x2 DSP48 tile on FPGA, or a Booth array
// on ASIC) and summed in MUL2.
// Divider: radix-4 restoring digit recurrence on magnitudes, two
// quotient bits per ITER cycle from three parallel compares
// against d, 2d, 3d. PREP normalizes with leading-zero counts so
// only significant quotient digits are iterated:
//   n = max(0, ceil((clz(|b|) - clz(|a|) + 1) / 2))  (0..32; 0..16 W)
// so |a| < |b| (different MSB position) finishes after PREP+FIX,
// and small quotients finish early. FIX applies signs and the W
// sign extension.
//
// COMB=1 selects the legacy single-cycle behaviour (the
// combinational muserisc_muldiv) behind the same handshake: done_o
// = req_i, no state. Kept as a reference and fallback.
`default_nettype none
module muserisc_muldiv_mc #(
    parameter int unsigned COMB = 0   // 1: legacy single-cycle mode
) (
    input  wire         clk_i,
    input  wire         rst_ni,
    input  wire         req_i,
    input  wire         ack_i,
    input  wire         kill_i,
    input  wire  [2:0]  funct3_i,
    input  wire         word_op_i,
    input  wire  [63:0] a_i,
    input  wire  [63:0] b_i,
    output logic        done_o,
    output logic [63:0] result_o
);

  if (COMB != 0) begin : g_comb
    // Legacy single-cycle unit; clocks/handshake unused.
    /* verilator lint_off UNUSEDSIGNAL */
    logic unused_hs;
    assign unused_hs = clk_i ^ rst_ni ^ ack_i ^ kill_i;
    /* verilator lint_on UNUSEDSIGNAL */
    assign done_o = req_i;
    muserisc_muldiv u_comb (
        .funct3_i  (funct3_i),
        .word_op_i (word_op_i),
        .a_i       (a_i),
        .b_i       (b_i),
        .result_o  (result_o)
    );
  end else begin : g_mc

    typedef enum logic [2:0] {
      // S_IDLE must stay 0: muserisc_core's sim-only in-flight
      // check tests the state for nonzero.
      S_IDLE = 3'd0, S_MUL1, S_MUL2, S_PREP, S_ITER, S_FIX
    } state_e;

    // Leading-zero count, log-depth tree: 4-bit leaves, then four
    // levels of (left-valid ? left : right) merges. 64 for zero.
    function automatic logic [6:0] clz64(input logic [63:0] x);
      logic [15:0]      v4;
      logic [15:0][1:0] c4;
      logic [7:0]       v8;
      logic [7:0][2:0]  c8;
      logic [3:0]       v16;
      logic [3:0][3:0]  c16;
      logic [1:0]       v32;
      logic [1:0][4:0]  c32;
      for (int i = 0; i < 16; i++) begin
        // nibble i covers bits [63-4i -: 4], most significant first
        logic [3:0] nb;
        nb = x[63-4*i -: 4];
        v4[i] = |nb;
        c4[i] = nb[3] ? 2'd0 : nb[2] ? 2'd1 : nb[1] ? 2'd2 : 2'd3;
      end
      for (int i = 0; i < 8; i++) begin
        v8[i] = v4[2*i] | v4[2*i+1];
        c8[i] = v4[2*i] ? {1'b0, c4[2*i]} : {1'b1, c4[2*i+1]};
      end
      for (int i = 0; i < 4; i++) begin
        v16[i] = v8[2*i] | v8[2*i+1];
        c16[i] = v8[2*i] ? {1'b0, c8[2*i]} : {1'b1, c8[2*i+1]};
      end
      for (int i = 0; i < 2; i++) begin
        v32[i] = v16[2*i] | v16[2*i+1];
        c32[i] = v16[2*i] ? {1'b0, c16[2*i]} : {1'b1, c16[2*i+1]};
      end
      if (v32[0])      clz64 = {2'b00, c32[0]};
      else if (v32[1]) clz64 = {2'b01, c32[1]};
      else             clz64 = 7'd64;
    endfunction

    state_e      state_q, state_d;
    logic [1:0]  f3_q;               // funct3[1:0] (op class known by state)
    logic        word_q;
    logic        neg_q_q, neg_r_q;   // divide: negate quotient / remainder
    logic        special_q;          // divide: b == 0 or signed overflow
    // Shared operand/working registers (mul and div never overlap):
    //   x_q  : MUL1 a (65-bit signed) | MUL2 pLH | PREP |a| | ITER quotient
    //   y_q  : MUL1 b (65-bit signed) | MUL2 pHL | divisor |b|
    //   w0_q : MUL2 pLL | div special result (PREP) | partial remainder
    //   w1_q : MUL2 pHH | 3 * divisor
    logic [65:0] x_q, y_q, w1_q;
    logic [63:0] w0_q;
    logic [4:0]  cnt_q;              // ITER steps left - 1

    // ---------------- IDLE: operand capture ----------------------
    logic        is_mul, is_rem, sgn;
    logic [63:0] a_val, b_val, au, bu, a_mag, b_mag, spec;
    logic        div0, ovf, a_sx, b_sx;
    assign is_mul = !funct3_i[2];
    assign is_rem = funct3_i[1];
    assign sgn    = !funct3_i[0];          // DIV/REM signed
    assign a_val  = word_op_i ? {{32{a_i[31]}}, a_i[31:0]} : a_i;
    assign b_val  = word_op_i ? {{32{b_i[31]}}, b_i[31:0]} : b_i;
    assign au     = word_op_i ? {32'd0, a_i[31:0]} : a_i;
    assign bu     = word_op_i ? {32'd0, b_i[31:0]} : b_i;
    assign a_mag  = (sgn && a_val[63]) ? (~a_val + 64'd1) : au;
    assign b_mag  = (sgn && b_val[63]) ? (~b_val + 64'd1) : bu;
    assign div0   = (bu == 64'd0);
    assign ovf    = sgn && (a_val == (word_op_i ? 64'hFFFF_FFFF_8000_0000
                                                : 64'h8000_0000_0000_0000)) &&
                    (b_val == 64'hFFFF_FFFF_FFFF_FFFF);
    // Special results are already W-correct: a_val is sign-extended
    // for word ops and all-ones is its own sign extension.
    assign spec   = div0 ? (is_rem ? a_val : 64'hFFFF_FFFF_FFFF_FFFF)
                         : (is_rem ? 64'd0 : a_val);
    // Multiplier operand extension to 65 bits: MULH both signed,
    // MULHSU a signed, MULHU/MUL/MULW unsigned (low half is
    // sign-agnostic).
    assign a_sx   = (funct3_i[1:0] == 2'b01 || funct3_i[1:0] == 2'b10) && a_i[63];
    assign b_sx   = (funct3_i[1:0] == 2'b01) && b_i[63];

    // ---------------- MUL1: partial products --------------------
    // a = a_hi * 2^32 + a_lo, a_hi signed 33-bit, a_lo unsigned
    // 32-bit (zero-extended to a signed 33-bit factor below).
    logic signed [32:0] a_hi, b_hi;
    logic        [31:0] a_lo, b_lo;
    logic [65:0]        p_ll, p_lh, p_hl, p_hh;
    assign a_lo = x_q[31:0];
    assign b_lo = y_q[31:0];
    assign a_hi = x_q[64:32];
    assign b_hi = y_q[64:32];
    // 33x33 signed -> 66-bit products (operands widen in the
    // assignment context, so each product is exact).
    /* verilator lint_off WIDTHEXPAND */
    assign p_ll = a_lo * b_lo;
    assign p_lh = $signed({1'b0, a_lo}) * b_hi;
    assign p_hl = a_hi * $signed({1'b0, b_lo});
    assign p_hh = a_hi * b_hi;
    /* verilator lint_on WIDTHEXPAND */

    // ---------------- MUL2: sum and select ----------------------
    logic [127:0] prod;
    logic [63:0]  mul_res;
    assign prod = {64'd0, w0_q} +
                  {{30{x_q[65]}}, x_q, 32'd0} +
                  {{30{y_q[65]}}, y_q, 32'd0} +
                  {w1_q[63:0], 64'd0};
    always_comb begin
      if (word_q)                    mul_res = {{32{prod[31]}}, prod[31:0]};
      else if (f3_q[1:0] == 2'b00)   mul_res = prod[63:0];
      else                           mul_res = prod[127:64];
    end

    // ---------------- PREP: normalize ----------------------------
    // Quotient bits needed: d = clz|b| - clz|a| + 1 (<= 0: none);
    // iterate n = ceil(d/2) radix-4 steps from rem = |a| >> 2n,
    // quotient shift register = |a| << (64 - 2n).
    logic [6:0]   clz_a, clz_b;
    logic [7:0]   dq;
    logic [5:0]   n_steps;
    logic [5:0]   sh2;                                      // shift / 2
    logic [127:0] norm;
    assign clz_a   = clz64(x_q[63:0]);
    assign clz_b   = clz64(y_q[63:0]);
    assign dq      = {1'b0, clz_b} - {1'b0, clz_a} + 8'd2;   // d + 1
    assign n_steps = dq[7] ? 6'd0 : dq[6:1];                 // ceil(d/2), d<=0 -> 0
    assign sh2     = 6'd32 - n_steps;
    assign norm    = {64'd0, x_q[63:0]} << {sh2, 1'b0};

    // ---------------- ITER: radix-4 step ------------------------
    logic [65:0] r4;
    logic [66:0] s1, s2, s3;
    logic [63:0] rem_nx;
    logic [1:0]  qd;
    assign r4 = {w0_q, x_q[63:62]};
    assign s1 = {1'b0, r4} - {3'b0, y_q[63:0]};
    assign s2 = {1'b0, r4} - {2'b0, y_q[63:0], 1'b0};
    assign s3 = {1'b0, r4} - {1'b0, w1_q};
    always_comb begin
      if (!s3[66])      begin qd = 2'd3; rem_nx = s3[63:0]; end
      else if (!s2[66]) begin qd = 2'd2; rem_nx = s2[63:0]; end
      else if (!s1[66]) begin qd = 2'd1; rem_nx = s1[63:0]; end
      else              begin qd = 2'd0; rem_nx = r4[63:0]; end
    end

    // ---------------- FIX: signs, select, W extension ------------
    logic [63:0] quo_s, rem_s, div_sel, div_res;
    assign quo_s   = neg_q_q ? (~x_q[63:0] + 64'd1) : x_q[63:0];
    assign rem_s   = neg_r_q ? (~w0_q + 64'd1) : w0_q;
    assign div_sel = f3_q[1] ? rem_s : quo_s;
    assign div_res = word_q ? {{32{div_sel[31]}}, div_sel[31:0]} : div_sel;

    // ---------------- completion --------------------------------
    always_comb begin
      done_o   = 1'b0;
      result_o = div_res;
      unique case (state_q)
        S_MUL2: begin done_o = 1'b1; result_o = mul_res; end
        S_PREP: if (special_q) begin done_o = 1'b1; result_o = w0_q; end
        S_FIX:  done_o = 1'b1;
        default: ;
      endcase
    end

    always_comb begin
      state_d = state_q;
      if (kill_i || ((state_q != S_IDLE) && !req_i)) begin
        state_d = S_IDLE;
      end else if (done_o) begin
        // Hold the done state (registers frozen) until acked.
        if (ack_i) state_d = S_IDLE;
      end else begin
        unique case (state_q)
          S_IDLE:  if (req_i) state_d = is_mul ? S_MUL1 : S_PREP;
          S_MUL1:  state_d = S_MUL2;
          S_PREP:  state_d = (n_steps == 6'd0) ? S_FIX : S_ITER;
          S_ITER:  if (cnt_q == 5'd0) state_d = S_FIX;
          // S_MUL2/S_FIX always complete (done_o above).
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

    // Datapath registers: no reset, each is written before the
    // state that reads it. Nothing is written in a done state, so
    // result_o is stable while waiting for ack.
    always_ff @(posedge clk_i) begin
      unique case (state_q)
        S_IDLE: if (req_i) begin
          f3_q      <= funct3_i[1:0];
          word_q    <= word_op_i;
          neg_q_q   <= sgn && (a_val[63] != b_val[63]);
          neg_r_q   <= sgn && a_val[63];
          special_q <= div0 || ovf;
          w0_q      <= spec;
          if (is_mul) begin
            x_q <= {a_sx, a_sx, a_i};
            y_q <= {b_sx, b_sx, b_i};
          end else begin
            x_q <= {2'b00, a_mag};
            y_q <= {2'b00, b_mag};
          end
        end
        S_MUL1: begin
          w0_q <= p_ll[63:0];
          x_q  <= p_lh;
          y_q  <= p_hl;
          w1_q <= p_hh;
        end
        S_PREP: if (!special_q) begin
          w0_q  <= norm[127:64];
          x_q   <= {2'b00, norm[63:0]};
          w1_q  <= {2'b00, y_q[63:0]} + {1'b0, y_q[63:0], 1'b0};
          cnt_q <= 5'(n_steps - 6'd1);
        end
        S_ITER: begin
          w0_q  <= rem_nx;
          x_q   <= {2'b00, x_q[61:0], qd};
          cnt_q <= cnt_q - 5'd1;
        end
        default: ;
      endcase
    end

    // p_ll's top bits are zero (32x32 unsigned); pHH above bit 63
    // and the upper sign copies only matter beyond 128 bits; dq[0]
    // is rounded away; s1..s3[65:64] are zero whenever selected
    // (the new partial remainder is below the divisor).
    /* verilator lint_off UNUSEDSIGNAL */
    logic unused_mc;
    assign unused_mc = ^{p_ll[65:64], w1_q[65:64], dq[0],
                         s1[65:64], s2[65:64], s3[65:64]};
    /* verilator lint_on UNUSEDSIGNAL */

`ifndef SYNTHESIS
    // Simulation cross-check: every completion must equal the
    // combinational reference on the operands sampled at issue.
    logic [2:0]  chk_f3;
    logic        chk_w;
    logic [63:0] chk_a, chk_b, chk_ref;
    muserisc_muldiv u_ref (
        .funct3_i  (chk_f3),
        .word_op_i (chk_w),
        .a_i       (chk_a),
        .b_i       (chk_b),
        .result_o  (chk_ref)
    );
    always_ff @(posedge clk_i) begin
      if ((state_q == S_IDLE) && req_i) begin
        chk_f3 <= funct3_i; chk_w <= word_op_i; chk_a <= a_i; chk_b <= b_i;
      end
      // Word funct3 001..011 (no MULHW) are don't-care encodings.
      if (done_o && !kill_i && !(chk_w && !chk_f3[2] && (chk_f3[1:0] != 2'b00)) &&
          (chk_ref != result_o))
        $error("muserisc_muldiv_mc: f3=%0d w=%0d a=%h b=%h: got %h, ref %h",
               chk_f3, chk_w, chk_a, chk_b, result_o, chk_ref);
    end
`endif
  end

endmodule
`default_nettype wire
