// museRISC in-house core: IEEE-754 stage functions shared by the
// scalar FPU and the vector FP path. Single source of truth for
// the arithmetic: `included both inside package muserisc_fpu_pkg
// (where fp_eval chains them combinationally for the vector unit)
// and inside module muserisc_fpu (which registers between them).
// The module copy also gives Verilator line coverage of the
// arithmetic, which it does not collect for package functions.
// Types and op codes come from muserisc_fpu_pkg.
  // ---------------------------------------------------------
  // Leading-zero normalisers: log-depth (one zero-detect + mux
  // level per shift-amount bit). lz = shift applied; an
  // all-zero input returns lz = width-1 and v = 0.
  // ---------------------------------------------------------
  function automatic fp_norm64_t norm64(input logic [63:0] v);
    fp_norm64_t r;
    logic [63:0] x;
    x = v;
    r.lz = 6'd0;
    if (x[63:32] == 32'd0) begin x = {x[31:0], 32'd0}; r.lz[5] = 1'b1; end
    if (x[63:48] == 16'd0) begin x = {x[47:0], 16'd0}; r.lz[4] = 1'b1; end
    if (x[63:56] == 8'd0)  begin x = {x[55:0], 8'd0};  r.lz[3] = 1'b1; end
    if (x[63:60] == 4'd0)  begin x = {x[59:0], 4'd0};  r.lz[2] = 1'b1; end
    if (x[63:62] == 2'd0)  begin x = {x[61:0], 2'd0};  r.lz[1] = 1'b1; end
    if (x[63] == 1'b0)     begin x = {x[62:0], 1'b0};  r.lz[0] = 1'b1; end
    r.v = x;
    return r;
  endfunction

  function automatic fp_norm128_t norm128(input logic [127:0] v);
    fp_norm128_t r;
    logic [127:0] x;
    x = v;
    r.lz = 7'd0;
    if (x[127:64] == 64'd0)  begin x = {x[63:0], 64'd0};  r.lz[6] = 1'b1; end
    if (x[127:96] == 32'd0)  begin x = {x[95:0], 32'd0};  r.lz[5] = 1'b1; end
    if (x[127:112] == 16'd0) begin x = {x[111:0], 16'd0}; r.lz[4] = 1'b1; end
    if (x[127:120] == 8'd0)  begin x = {x[119:0], 8'd0};  r.lz[3] = 1'b1; end
    if (x[127:124] == 4'd0)  begin x = {x[123:0], 4'd0};  r.lz[2] = 1'b1; end
    if (x[127:126] == 2'd0)  begin x = {x[125:0], 2'd0};  r.lz[1] = 1'b1; end
    if (x[127] == 1'b0)      begin x = {x[126:0], 1'b0};  r.lz[0] = 1'b1; end
    r.v = x;
    return r;
  endfunction

  // ---------------------------------------------------------
  // Unpack (NaN-box check, classification, subnormal
  // normalisation through norm64).
  // ---------------------------------------------------------
  function automatic logic [63:0] fp_box_check(input logic [63:0] v,
                                               input logic d);
    return (!d && (v[63:32] != 32'hFFFF_FFFF))
               ? 64'hFFFF_FFFF_7FC0_0000 : v;
  endfunction

  function automatic unpacked_t unpack(input logic [63:0] v,
                                       input logic d);
    unpacked_t u;
    logic [63:0] eff;
    logic [10:0] efield;
    logic [51:0] frac;
    logic        emax_f;
    fp_norm64_t  n;
    eff = fp_box_check(v, d);
    u.raw = eff;
    if (d) begin
      u.sign = eff[63]; efield = eff[62:52]; frac = eff[51:0];
    end else begin
      u.sign = eff[31]; efield = {3'b0, eff[30:23]};
      frac = {eff[22:0], 29'b0};
    end
    emax_f = (efield == (d ? 11'h7FF : 11'h0FF));
    u.is_zero = (efield == 11'd0) && (frac == 52'd0);
    u.is_sub  = (efield == 11'd0) && (frac != 52'd0);
    u.is_inf  = emax_f && (frac == 52'd0);
    u.is_nan  = emax_f && (frac != 52'd0);
    u.is_snan = u.is_nan && !frac[51];
    // Subnormal: value = {0,frac} * 2^(emin-52); shift the
    // leading one up to bit 52 and lower the exponent to match.
    n = norm64({1'b0, frac, 11'b0});
    if (efield != 11'd0) begin
      u.sig = {1'b1, frac};
      u.exp = $signed({5'b0, efield}) - (d ? 16'sd1023 : 16'sd127);
    end else if (u.is_zero) begin
      u.sig = 53'd0;
      u.exp = FPU_ZERO_EXP;
    end else begin
      u.sig = n.v[63:11];
      u.exp = (d ? -16'sd1022 : -16'sd126) - $signed({10'b0, n.lz});
    end
    return u;
  endfunction

  // ---------------------------------------------------------
  // Constants
  // ---------------------------------------------------------
  function automatic logic [63:0] fp_canon(input logic d);
    return d ? 64'h7FF8_0000_0000_0000 : 64'hFFFF_FFFF_7FC0_0000;
  endfunction

  function automatic logic [63:0] fp_inf(input logic d, input logic s);
    return d ? {s, 11'h7FF, 52'd0} : {32'hFFFF_FFFF, s, 8'hFF, 23'd0};
  endfunction

  function automatic logic [63:0] fp_zero(input logic d, input logic s);
    return d ? {s, 63'd0} : {32'hFFFF_FFFF, s, 31'd0};
  endfunction

  function automatic logic [63:0] fp_maxfin(input logic d, input logic s);
    return d ? {s, 11'h7FE, 52'hF_FFFF_FFFF_FFFF}
             : {32'hFFFF_FFFF, s, 8'hFE, 23'h7F_FFFF};
  endfunction

  // ---------------------------------------------------------
  // Fast ops: sign injection and raw moves. They need only
  // the NaN-box check, so the FPU completes them in the issue
  // cycle.
  // ---------------------------------------------------------
  function automatic logic fp_is_fast(input logic [4:0] op);
    return (op == FPU_SGNJ) || (op == FPU_MVXF) || (op == FPU_MVFX);
  endfunction

  function automatic logic [63:0] fp_fastop(
      input logic [4:0] op, input logic d, input logic [63:0] a,
      input logic [63:0] b, input logic [1:0] aux);
    logic [63:0] ea, eb, r;
    logic sa, sb, s;
    ea = fp_box_check(a, d);
    eb = fp_box_check(b, d);
    sa = d ? ea[63] : ea[31];
    sb = d ? eb[63] : eb[31];
    s = (aux == 2'd0) ? sb : (aux == 2'd1) ? ~sb : (sa ^ sb);
    if (op == FPU_MVXF)      r = d ? a : {32'hFFFF_FFFF, a[31:0]};
    else if (op == FPU_MVFX) r = d ? a : {{32{a[31]}}, a[31:0]};
    else                     r = d ? {s, ea[62:0]}
                                   : {32'hFFFF_FFFF, s, ea[30:0]};
    return r;
  endfunction

  // ---------------------------------------------------------
  // Special cases and the compare-class ops, from unpacked
  // operands. For FPU_F2F, ua is the operand unpacked in the
  // source format. F2I/I2F never hit (own datapath); fast ops
  // are handled before this function is consulted.
  // ---------------------------------------------------------
  function automatic fp_special_t fp_special(
      input logic [4:0] op, input logic d,
      input unpacked_t ua, input unpacked_t ub, input unpacked_t uc,
      input logic [1:0] aux);
    fp_special_t s;
    logic sb, sp, sc, blt, beq, anan, a0inf;
    logic [9:0] cls;
    s.hit = 1'b1;
    s.result = fp_canon(d);
    s.flags = 5'd0;
    sb = ub.sign ^ (op == FPU_SUB);
    sp = ua.sign ^ ub.sign ^ ((op == FPU_FNMS) || (op == FPU_FNMA));
    sc = uc.sign ^ ((op == FPU_FMS) || (op == FPU_FNMA));
    anan = ua.is_nan || ub.is_nan;
    a0inf = (ua.is_zero && ub.is_inf) || (ua.is_inf && ub.is_zero);
    // ordered comparison of two non-NaN operands
    if (ua.is_zero && ub.is_zero) begin
      blt = 1'b0; beq = 1'b1;
    end else if (ua.sign != ub.sign) begin
      blt = ua.sign; beq = 1'b0;
    end else if (ua.exp != ub.exp) begin
      blt = ua.sign ? (ua.exp > ub.exp) : (ua.exp < ub.exp);
      beq = 1'b0;
    end else begin
      blt = ua.sign ? (ua.sig > ub.sig) : (ua.sig < ub.sig);
      beq = (ua.sig == ub.sig);
    end
    // (whole-vector assignments: Verilator 5.020 rejects a
    // variable-index write to a local of a non-inlined function)
    if (ua.is_inf)       cls = ua.sign ? 10'h001 : 10'h080;
    else if (ua.is_nan)  cls = ua.is_snan ? 10'h100 : 10'h200;
    else if (ua.is_zero) cls = ua.sign ? 10'h008 : 10'h010;
    else if (ua.is_sub)  cls = ua.sign ? 10'h004 : 10'h020;
    else                 cls = ua.sign ? 10'h002 : 10'h040;

    unique case (op)
      FPU_ADD, FPU_SUB: begin
        if (anan)
          s.flags[4] = ua.is_snan | ub.is_snan;
        else if (ua.is_inf && ub.is_inf && (ua.sign != sb))
          s.flags[4] = 1'b1;
        else if (ua.is_inf || ub.is_inf)
          s.result = fp_inf(d, ua.is_inf ? ua.sign : sb);
        else
          s.hit = 1'b0;
      end
      FPU_MUL: begin
        if (anan)
          s.flags[4] = ua.is_snan | ub.is_snan;
        else if (a0inf)
          s.flags[4] = 1'b1;
        else if (ua.is_inf || ub.is_inf)
          s.result = fp_inf(d, ua.sign ^ ub.sign);
        else
          s.hit = 1'b0;
      end
      FPU_DIV: begin
        if (anan) begin
          s.flags[4] = ua.is_snan | ub.is_snan;
        end else if ((ua.is_zero && ub.is_zero) ||
                     (ua.is_inf && ub.is_inf)) begin
          s.flags[4] = 1'b1;
        end else if (ua.is_inf || ub.is_zero) begin
          s.result = fp_inf(d, ua.sign ^ ub.sign);
          s.flags[3] = ub.is_zero && !ua.is_inf;   // DZ
        end else if (ub.is_inf || ua.is_zero) begin
          s.result = fp_zero(d, ua.sign ^ ub.sign);
        end else begin
          s.hit = 1'b0;
        end
      end
      FPU_SQRT: begin
        if (ua.is_nan)
          s.flags[4] = ua.is_snan;
        else if (ua.sign && !ua.is_zero)
          s.flags[4] = 1'b1;
        else if (ua.is_inf)
          s.result = fp_inf(d, 1'b0);
        else if (ua.is_zero)
          s.result = fp_zero(d, ua.sign);
        else
          s.hit = 1'b0;
      end
      FPU_FMA, FPU_FMS, FPU_FNMS, FPU_FNMA: begin
        if (anan || uc.is_nan || a0inf)
          s.flags[4] = ua.is_snan | ub.is_snan | uc.is_snan | a0inf;
        else if ((ua.is_inf || ub.is_inf) && uc.is_inf && (sp != sc))
          s.flags[4] = 1'b1;
        else if (ua.is_inf || ub.is_inf)
          s.result = fp_inf(d, sp);
        else if (uc.is_inf)
          s.result = fp_inf(d, sc);
        else
          s.hit = 1'b0;
      end
      FPU_F2F: begin
        if (ua.is_nan)
          s.flags[4] = ua.is_snan;
        else if (ua.is_inf)
          s.result = fp_inf(d, ua.sign);
        else
          s.hit = 1'b0;
      end
      FPU_MINMAX: begin
        s.flags[4] = ua.is_snan | ub.is_snan;
        if (ua.is_nan && ub.is_nan)    s.result = fp_canon(d);
        else if (ua.is_nan)            s.result = ub.raw;
        else if (ub.is_nan)            s.result = ua.raw;
        else if (ua.is_zero && ub.is_zero)
          s.result = fp_zero(d, (aux == 2'd0) ? (ua.sign | ub.sign)
                                              : (ua.sign & ub.sign));
        else
          s.result = ((aux == 2'd0) == blt) ? ua.raw : ub.raw;
      end
      FPU_CMP: begin
        s.result = 64'd0;
        if (anan)
          s.flags[4] = (aux == 2'd2) ? (ua.is_snan | ub.is_snan) : 1'b1;
        else
          s.result[0] = (aux == 2'd2) ? beq :
                        (aux == 2'd1) ? blt : (blt | beq);
      end
      FPU_CLASS: s.result = {54'd0, cls};
      FPU_F2I, FPU_I2F: s.hit = 1'b0;
      // Undefined op codes (the decoder emits none; fast ops
      // never get here): zero result, no flags.
      default: s.result = 64'd0;
    endcase
    return s;
  endfunction

  // ---------------------------------------------------------
  // Add / multiply / FMA datapath
  // ---------------------------------------------------------
  function automatic fp_op_t fop_unp(input unpacked_t u, input logic neg);
    fp_op_t o;
    o.sign = u.sign ^ neg;
    o.exp = u.exp;
    o.sig = {u.sig, 53'd0};
    return o;
  endfunction


  function automatic fp_pp_t fp_mul_pp(input logic [52:0] a, input logic [52:0] b);
    fp_pp_t r;
    r.hi = 79'(a) * 79'(b[52:27]);
    r.lo = 80'(a) * 80'(b[26:0]);
    return r;
  endfunction

  function automatic logic [105:0] fp_mul_sum(input fp_pp_t pp);
    return 106'(pp.lo) + {pp.hi, 27'd0};
  endfunction

  // Product operand: sig = a.sig*b.sig (MSB at 104 or 105),
  // bit 105 weight 2^(ea+eb+1).
  function automatic fp_op_t fop_prod(input logic [4:0] op, input unpacked_t ua,
                                      input unpacked_t ub, input logic [105:0] p);
    fp_op_t o;
    o.sign = ua.sign ^ ub.sign ^ ((op == FPU_FNMS) || (op == FPU_FNMA));
    o.exp = ua.exp + ub.exp + 16'sd1;
    o.sig = p;
    return o;
  endfunction

  function automatic logic fma_neg_c(input logic [4:0] op);
    return (op == FPU_FMS) || (op == FPU_FNMA);
  endfunction

  function automatic fp_sum_t fop_sum(input fp_op_t x);
    fp_sum_t s;
    s.sign = x.sign;
    s.exp = x.exp;
    s.mag = {2'b0, x.sig, 20'd0};
    return s;
  endfunction

  // Exponent compare, swap, and right shift of the smaller
  // operand with a jam bit. Cancellation is only possible for
  // exponent distances <= 1, where nothing is shifted out, so
  // the 128-bit window keeps every add/FMA result exact up to
  // the jam bit (2 bits of headroom above bit 125).
  function automatic fp_align_t fp_align(input fp_op_t x, input fp_op_t y);
    fp_align_t r;
    logic x_big;
    logic [15:0] dsh;
    logic [127:0] wx, wy, sm, lost;
    wx = {2'b0, x.sig, 20'd0};
    wy = {2'b0, y.sig, 20'd0};
    x_big = (x.exp >= y.exp);
    dsh = x_big ? 16'(x.exp - y.exp) : 16'(y.exp - x.exp);
    r.big = x_big ? wx : wy;
    sm = x_big ? wy : wx;
    r.exp = x_big ? x.exp : y.exp;
    r.sign_big = x_big ? x.sign : y.sign;
    r.sign_small = x_big ? y.sign : x.sign;
    r.eff_sub = x.sign ^ y.sign;
    if (dsh >= 16'd128) begin
      r.sml = {127'd0, (sm != 128'd0)};
    end else begin
      lost = sm & ((128'd1 << dsh[6:0]) - 128'd1);
      r.sml = sm >> dsh[6:0];
      r.sml[0] = r.sml[0] | (lost != 128'd0);
    end
    return r;
  endfunction

  // Signed-magnitude add. An effective subtraction computes
  // big-sml; a borrow (possible only for exponent distance
  // <= 1, so exact) selects sml-big. Exact zero takes +0,
  // or -0 under RDN.
  function automatic fp_sum_t fp_addsub(input fp_align_t a, input logic [2:0] rm);
    fp_sum_t s;
    logic [128:0] df;
    s.exp = a.exp;
    df = {1'b0, a.big} - {1'b0, a.sml};
    if (!a.eff_sub) begin
      s.mag = a.big + a.sml;
      s.sign = a.sign_big;
    end else if (df[128]) begin
      s.mag = a.sml - a.big;
      s.sign = a.sign_small;
    end else begin
      s.mag = df[127:0];
      s.sign = (df == 129'd0) ? (rm == 3'b010) : a.sign_big;
    end
    return s;
  endfunction

  // Leading-zero normalise a sum into round-and-pack form.
  function automatic fp_rnd_t fp_norm(input fp_sum_t s);
    fp_rnd_t r;
    fp_norm128_t n;
    n = norm128(s.mag);
    r.sign = s.sign;
    r.zero = (s.mag == 128'd0);
    r.exp = s.exp + 16'sd2 - $signed({9'd0, n.lz});
    r.sig = n.v[127:64];
    r.sticky = (n.v[63:0] != 64'd0);
    return r;
  endfunction

  // ---------------------------------------------------------
  // Conversions
  // ---------------------------------------------------------
  // Integer -> float: magnitude placed at the window top
  // (bit 127 = 2^63, so bit 125 = 2^61), then fp_norm.
  function automatic fp_sum_t i2f_sum(input logic [63:0] a, input logic [1:0] aux);
    fp_sum_t s;
    logic [63:0] iv, m;
    logic neg;
    unique case (aux)
      2'd0:    iv = {{32{a[31]}}, a[31:0]};
      2'd1:    iv = {32'd0, a[31:0]};
      default: iv = a;
    endcase
    neg = !aux[0] && iv[63];
    m = neg ? (64'd0 - iv) : iv;
    s.sign = neg;
    s.exp = 16'sd61;
    s.mag = {m, 64'd0};
    return s;
  endfunction

  // Float -> float: the source operand (already unpacked in
  // the source format) goes straight to round-and-pack.
  function automatic fp_rnd_t f2f_rnd(input unpacked_t u);
    fp_rnd_t r;
    r.sign = u.sign;
    r.exp = u.exp;
    r.sig = {u.sig, 11'd0};
    r.sticky = 1'b0;
    r.zero = u.is_zero;
    return r;
  endfunction

  // Float -> integer, stage 1: align the significand to a
  // 64.64 fixed point (bit 64 = 2^0) and apply the rounding
  // increment.
  function automatic fp_f2i_t f2i_s1(input unpacked_t u, input logic [2:0] rm);
    fp_f2i_t r;
    logic [127:0] w;
    logic [63:0]  ip;
    logic [6:0]   sh;
    logic g, st, up;
    r.sign = u.sign;
    r.nan = u.is_nan;
    r.big = 1'b0;
    ip = 64'd0; g = 1'b0; st = 1'b0;
    sh = 7'(16'sd63 - u.exp);   // 0..64 when -1 <= exp <= 63
    w = {u.sig, 75'd0} >> sh;
    if (u.exp >= 16'sd64) begin
      r.big = 1'b1;             // also Inf and NaN
    end else if (u.exp >= -16'sd1) begin
      ip = w[127:64];
      g = w[63];
      st = (w[62:0] != 63'd0);
    end else begin
      st = !u.is_zero;          // 0 < |x| < 0.5
    end
    unique case (rm)
      3'b000:  up = g & (st | ip[0]);        // RNE
      3'b010:  up = u.sign & (g | st);       // RDN
      3'b011:  up = !u.sign & (g | st);      // RUP
      3'b100:  up = g;                       // RMM
      default: up = 1'b0;                    // RTZ
    endcase
    r.ip = {1'b0, ip} + {64'd0, up};
    r.inexact = g | st;
    return r;
  endfunction

  // Float -> integer, stage 2: range check, saturation and
  // sign. aux: 0=W 1=WU 2=L 3=LU. NaN saturates like +big.
  function automatic fp_eval_result_t f2i_s2(input fp_f2i_t s, input logic [1:0] aux);
    fp_eval_result_t r;
    logic [64:0] lim;
    logic [63:0] m;
    logic neg;
    unique case (aux)
      2'd0:    lim = s.sign ? 65'h0_8000_0000 : 65'h0_7FFF_FFFF;
      2'd1:    lim = s.sign ? 65'd0 : 65'h0_FFFF_FFFF;
      2'd2:    lim = s.sign ? 65'h0_8000_0000_0000_0000 : 65'h0_7FFF_FFFF_FFFF_FFFF;
      default: lim = s.sign ? 65'd0 : 65'h0_FFFF_FFFF_FFFF_FFFF;
    endcase
    neg = s.sign && !s.nan;
    m = s.sign ? (64'd0 - s.ip[63:0]) : s.ip[63:0];
    r.flags = 5'd0;
    if (s.nan || s.big || (s.ip > lim)) begin
      r.flags[4] = 1'b1;
      unique case (aux)
        2'd0:    r.result = neg ? 64'hFFFF_FFFF_8000_0000 : 64'h0000_0000_7FFF_FFFF;
        2'd2:    r.result = neg ? 64'h8000_0000_0000_0000 : 64'h7FFF_FFFF_FFFF_FFFF;
        default: r.result = neg ? 64'd0 : 64'hFFFF_FFFF_FFFF_FFFF;
      endcase
    end else begin
      r.flags[0] = s.inexact;
      r.result = aux[1] ? m : {{32{m[31]}}, m[31:0]};
    end
    return r;
  endfunction

  // ---------------------------------------------------------
  // Divide / square root: radix-2 restoring digit recurrence,
  // one shared subtractor per step.
  // ---------------------------------------------------------
  function automatic fp_ds_t ds_init(input logic is_sqrt, input unpacked_t ua,
                                     input unpacked_t ub);
    fp_ds_t s;
    logic signed [15:0] e2;
    s = '0;
    s.is_sqrt = is_sqrt;
    e2 = ua.exp - (ua.exp[0] ? 16'sd1 : 16'sd0);
    if (is_sqrt) begin
      // Even exponent; radicand m in [1,4) placed so that the
      // FPU_DS_N_D-bit root has its MSB at bit N-1 and weight
      // 2^(e/2). Binary32 consumes only the top 2*N_S bits.
      s.rad = {(ua.exp[0] ? {ua.sig, 1'b0} : {1'b0, ua.sig}), 58'd0};
      s.exp = {e2[15], e2[15:1]};
      s.sign = ua.sign;
    end else begin
      s.rem = {11'd0, ua.sig};
      s.dvs = ub.sig;
      s.exp = ua.exp - ub.exp;
      s.sign = ua.sign ^ ub.sign;
    end
    return s;
  endfunction

  function automatic fp_ds_t ds_step(input fp_ds_t s);
    fp_ds_t r;
    logic [63:0] a, b, keep;
    logic [64:0] t;
    logic ok;
    r = s;
    a = s.is_sqrt ? {s.rem[61:0], s.rad[111:110]} : s.rem;
    b = s.is_sqrt ? {s.q[61:0], 2'b01} : {11'd0, s.dvs};
    t = {1'b0, a} - {1'b0, b};
    ok = !t[64];
    keep = ok ? t[63:0] : a;
    r.rem = s.is_sqrt ? keep : {keep[62:0], 1'b0};
    r.q = {s.q[62:0], ok};
    r.rad = {s.rad[109:0], 2'b00};
    return r;
  endfunction

  function automatic fp_rnd_t ds_fin(input fp_ds_t s, input logic d);
    fp_rnd_t r;
    logic [63:0] sig;
    sig = d ? (s.q << (64 - FPU_DS_N_D)) : (s.q << (64 - FPU_DS_N_S));
    r.sign = s.sign;
    r.zero = 1'b0;
    r.sticky = (s.rem != 64'd0) || (s.rad != 112'd0);
    if (sig[63]) begin
      r.sig = sig;
      r.exp = s.exp;
    end else begin
      r.sig = {sig[62:0], 1'b0};   // quotient < 1
      r.exp = s.exp - 16'sd1;
    end
    return r;
  endfunction

  // ---------------------------------------------------------
  // Round and pack. rm: 0 RNE, 1 RTZ, 2 RDN, 3 RUP, 4 RMM,
  // 5 ROD (vfncvt.rod); 6/7 never reach here from the core
  // and behave as RTZ.
  // ---------------------------------------------------------
  function automatic fp_eval_result_t fp_round(input fp_rnd_t ri, input logic d,
                                               input logic [2:0] rm);
    fp_eval_result_t r;
    logic [6:0]  p, xb;
    logic signed [15:0] emin, emax, bias, e, efield;
    logic [15:0] shift, total;
    logic [63:0] kept, fracbits, sig_b, inc_b, mask;
    logic guard, sticky, inexact, round_up, rtz;
    p = d ? 7'd53 : 7'd24;
    xb = d ? 7'd10 : 7'd7;
    emax = d ? 16'sd1023 : 16'sd127;
    emin = d ? -16'sd1022 : -16'sd126;
    bias = emax;
    r.flags = 5'd0;
    rtz = (rm == 3'b001) || (rm == 3'b101) || (rm[2:1] == 2'b11);
    if (ri.zero) begin
      r.result = fp_zero(d, ri.sign);
    end else begin
      e = ri.exp;
      // subnormal right-shift amount on top of the 64-p drop
      shift = (e < emin) ? 16'(emin - e) : 16'd0;
      total = (16'd64 - {9'd0, p}) + shift;
      if (total > 16'd64) begin
        kept = 64'd0;
        guard = 1'b0;
        sticky = 1'b1;                     // sig is never zero here
      end else if (total == 16'd64) begin
        // everything drops; the MSB is the guard (half-ulp) bit
        kept = 64'd0;
        guard = ri.sig[63];
        sticky = (ri.sig[62:0] != 63'd0) | ri.sticky;
      end else begin
        kept = ri.sig >> total[5:0];
        guard = ri.sig[total[5:0] - 6'd1];
        mask = (64'd1 << (total[5:0] - 6'd1)) - 64'd1;
        sticky = ri.sticky | ((ri.sig & mask) != 64'd0);
      end
      inexact = guard | sticky;
      unique case (rm)
        3'b000:  round_up = guard & (sticky | kept[0]);   // RNE
        3'b010:  round_up = ri.sign & inexact;            // RDN
        3'b011:  round_up = ~ri.sign & inexact;           // RUP
        3'b100:  round_up = guard;                        // RMM
        3'b101:  round_up = inexact & ~kept[0];           // ROD
        default: round_up = 1'b0;                         // RTZ
      endcase
      // Tininess, Berkeley-style "after rounding" (matches
      // Sail): only values headed subnormal can be tiny. With
      // the significand kept to p+X bits (X=10 for D, 7 for
      // S, jammed), the value is tiny iff its exponent is at
      // least two binades down, or one binade down and adding
      // the rounding increment does not carry it to 2^emin.
      sig_b = ri.sig >> (7'd64 - (p + xb));
      if (ri.sticky || ((ri.sig << (p + xb)) != 64'd0))
        sig_b[0] = 1'b1;
      unique case (rm)
        3'b000, 3'b100: inc_b = 64'd1 << (xb - 7'd1);
        3'b010:  inc_b = ri.sign ? ((64'd1 << xb) - 64'd1) : 64'd0;
        3'b011:  inc_b = ri.sign ? 64'd0 : ((64'd1 << xb) - 64'd1);
        default: inc_b = 64'd0;
      endcase
      if (inexact && (e < emin) &&
          ((e < emin - 16'sd1) ||
           ((sig_b + inc_b) < (64'd1 << (p + xb)))))
        r.flags[1] = 1'b1;                                 // UF
      kept = kept + {63'd0, round_up};
      // rounding promoted into the next binade
      if (kept >= (64'd1 << p)) begin
        kept = kept >> 1;
        e = e + 16'sd1;
      end else if ((shift != 16'd0) && (kept >= (64'd1 << (p - 7'd1)))) begin
        e = emin;   // promoted from subnormal to min normal
      end
      r.flags[0] = inexact;                                // NX
      if (e > emax) begin
        r.flags[2] = 1'b1;                                 // OF
        r.flags[0] = 1'b1;                                 // NX
        // overflow result per rm: max finite when rounding
        // toward zero in effect, else infinity
        r.result = (rtz || ((rm == 3'b010) && !ri.sign) ||
                    ((rm == 3'b011) && ri.sign))
                       ? fp_maxfin(d, ri.sign) : fp_inf(d, ri.sign);
      end else if (kept < (64'd1 << (p - 7'd1))) begin
        // subnormal or zero: exponent field 0, frac = kept
        fracbits = kept;
        r.result = d ? {ri.sign, 11'd0, fracbits[51:0]}
                     : {32'hFFFF_FFFF, ri.sign, 8'd0, fracbits[22:0]};
      end else begin
        efield = e + bias;
        fracbits = kept - (64'd1 << (p - 7'd1));
        r.result = d ? {ri.sign, efield[10:0], fracbits[51:0]}
                     : {32'hFFFF_FFFF, ri.sign, efield[7:0], fracbits[22:0]};
      end
    end
    return r;
  endfunction

