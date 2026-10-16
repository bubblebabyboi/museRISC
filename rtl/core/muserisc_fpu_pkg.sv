// museRISC in-house core: IEEE-754 binary32/binary64 arithmetic
// definitions shared by the scalar multi-cycle FPU
// (muserisc_fpu) and the combinational vector FP path
// (muserisc_vec via fp_eval/fp_estimate).
//
// Every operation is expressed as a short chain of stage
// functions over packed structs:
//
//   unpack -> [fp_special | fast op | datapath stages] -> fp_round
//
//   datapath stages:
//     add/sub : fp_align -> fp_addsub -> fp_norm
//     mul     : fp_mul_pp -> fp_mul_sum -> fop_sum -> fp_norm
//     fma     : fp_mul_pp -> fp_mul_sum -> fp_align -> fp_addsub -> fp_norm
//     div/sqrt: ds_init -> ds_step x N -> ds_fin   (radix-2 steps)
//     i2f     : i2f_sum -> fp_norm
//     f2f     : f2f_rnd
//     f2i     : f2i_s1 -> f2i_s2
//
// muserisc_fpu registers between these stages (one stage per
// cycle, FPU_DS_BITS div/sqrt steps per cycle); fp_eval chains
// the very same functions combinationally for the vector unit,
// so scalar and vector results are bit-identical by
// construction (and muserisc_fpu cross-checks against fp_eval
// in simulation). No data-dependent loops: normalisation uses
// log-depth leading-zero shifters (norm64/norm128), and the
// only loop (fp_eval's div/sqrt chain) has a constant bound.
//
// NaN results are the canonical quiet NaN, as RISC-V requires.
// Binary32 operands are read from the low 32 bits with the
// NaN-box check applied (improperly boxed = canonical NaN);
// binary32 results are NaN-boxed. Underflow tininess is
// detected after rounding (Berkeley/Sail rule).
`default_nettype none
package muserisc_fpu_pkg;
  // Stage functions take whole operand structs and each uses a
  // subset of the fields.
  /* verilator lint_off UNUSEDSIGNAL */

  // Op encoding (op_i) for muserisc_fpu / fp_eval.
  localparam logic [4:0] FPU_ADD   = 5'd0;
  localparam logic [4:0] FPU_SUB   = 5'd1;
  localparam logic [4:0] FPU_MUL   = 5'd2;
  localparam logic [4:0] FPU_DIV   = 5'd3;
  localparam logic [4:0] FPU_SQRT  = 5'd4;
  localparam logic [4:0] FPU_SGNJ  = 5'd5;   // aux: 0=sgnj 1=sgnjn 2=sgnjx
  localparam logic [4:0] FPU_MINMAX= 5'd6;   // aux: 0=min 1=max
  localparam logic [4:0] FPU_CMP   = 5'd7;   // aux: 0=le 1=lt 2=eq
  localparam logic [4:0] FPU_CLASS = 5'd8;
  localparam logic [4:0] FPU_F2I   = 5'd9;   // aux: 0=W 1=WU 2=L 3=LU
  localparam logic [4:0] FPU_I2F   = 5'd10;  // aux: 0=W 1=WU 2=L 3=LU
  localparam logic [4:0] FPU_F2F   = 5'd11;  // fp->fp (fmt_d_i = dest)
  localparam logic [4:0] FPU_FMA   = 5'd12;  // a*b+c
  localparam logic [4:0] FPU_FMS   = 5'd13;  // a*b-c
  localparam logic [4:0] FPU_FNMS  = 5'd14;  // -(a*b)+c
  localparam logic [4:0] FPU_FNMA  = 5'd15;  // -(a*b)-c
  localparam logic [4:0] FPU_MVXF  = 5'd16;  // int bits -> fp reg
  localparam logic [4:0] FPU_MVFX  = 5'd17;  // fp raw bits -> int reg

  // Divide / square-root digit recurrence: FPU_DS_BITS radix-2
  // steps per cycle (2 = radix-4 throughput). The step count
  // covers p+2 quotient/root bits (p, guard, and one more for
  // the quotient's possible leading zero), rounded up to a
  // whole number of cycles.
  // Overridable for exploration/verification builds
  // (+define+MUSERISC_FPU_DS_BITS=1 in `make -C sim fpu-ds1`).
`ifndef MUSERISC_FPU_DS_BITS
`define MUSERISC_FPU_DS_BITS 2
`endif
  localparam int FPU_DS_BITS = `MUSERISC_FPU_DS_BITS;
  localparam int FPU_DS_N_D  = ((55 + FPU_DS_BITS - 1) / FPU_DS_BITS) * FPU_DS_BITS;
  localparam int FPU_DS_N_S  = ((26 + FPU_DS_BITS - 1) / FPU_DS_BITS) * FPU_DS_BITS;

  // Exponent given to a zero operand: far below any real
  // exponent, so zero always ranks as the smaller magnitude.
  localparam logic signed [15:0] FPU_ZERO_EXP = -16'sd3000;

  // ---------------------------------------------------------
  // Types
  // ---------------------------------------------------------
  // Unpacked operand. The significand is left-aligned for both
  // formats: hidden bit at sig[52], value = sig * 2^(exp-52).
  // Subnormals are normalised (sig[52]=1, exp below emin).
  typedef struct packed {
    logic               sign;
    logic signed [15:0] exp;
    logic [52:0]        sig;
    logic               is_zero, is_inf, is_nan, is_snan, is_sub;
    logic [63:0]        raw;    // effective bits (post box check)
  } unpacked_t;

  typedef struct packed {
    logic [63:0] result;  // fp result (boxed) or int result
    logic [4:0]  flags;   // NV DZ OF UF NX
  } fp_eval_result_t;

  // Special-case outcome (NaN/Inf/invalid/exact-zero shortcuts
  // and the non-arithmetic ops): hit = result is final.
  typedef struct packed {
    logic        hit;
    logic [63:0] result;
    logic [4:0]  flags;
  } fp_special_t;

  // Addend/product operand in the 106-bit frame: sig bit 105
  // has weight 2^exp.
  typedef struct packed {
    logic               sign;
    logic signed [15:0] exp;
    logic [105:0]       sig;
  } fp_op_t;

  // Aligned operand pair in a 128-bit window: bit 125 has
  // weight 2^exp; the smaller operand is shifted right with
  // everything shifted out jammed into bit 0.
  typedef struct packed {
    logic [127:0]       big;
    logic [127:0]       sml;
    logic signed [15:0] exp;
    logic               sign_big, sign_small, eff_sub;
  } fp_align_t;

  // Signed-magnitude sum in the 128-bit window (bit 125 =
  // 2^exp); for a zero magnitude, sign is the IEEE zero sign.
  typedef struct packed {
    logic               sign;
    logic signed [15:0] exp;
    logic [127:0]       mag;
  } fp_sum_t;

  // Round-and-pack input: sig normalised with sig[63] weight
  // 2^exp, sticky = OR of everything below sig[0].
  typedef struct packed {
    logic               sign;
    logic signed [15:0] exp;
    logic [63:0]        sig;
    logic               sticky;
    logic               zero;
  } fp_rnd_t;

  // Divide / square-root recurrence state. Divide: rem holds
  // 2x the partial remainder, q the quotient bits so far (first
  // bit weight 2^0). Square root: rem/q are the integer
  // remainder/root of the radicand bits consumed so far; rad
  // holds the unconsumed radicand bits (top first).
  typedef struct packed {
    logic [63:0]        rem;
    logic [63:0]        q;
    logic [111:0]       rad;
    logic [52:0]        dvs;
    logic               is_sqrt;
    logic               sign;
    logic signed [15:0] exp;
  } fp_ds_t;

  // Float -> integer, after the shift/round stage.
  typedef struct packed {
    logic [64:0] ip;      // rounded integer magnitude
    logic        inexact;
    logic        big;     // |x| >= 2^64 or infinite
    logic        sign;
    logic        nan;
  } fp_f2i_t;

  typedef struct packed {
    logic [5:0]  lz;
    logic [63:0] v;
  } fp_norm64_t;

  typedef struct packed {
    logic [6:0]   lz;
    logic [127:0] v;
  } fp_norm128_t;

  // 53x53 multiply split into two 53x27/53x26 partial
  // products (one pipeline cut) and their sum.
  typedef struct packed {
    logic [78:0] hi;   // a * b[52:27]
    logic [79:0] lo;   // a * b[26:0]
  } fp_pp_t;

  `include "muserisc_fpu_ops.svh"

  // 7-bit estimate tables for vfrec7/vfrsqrt7 (the RVV
  // spec tables; values extracted exhaustively from the
  // Sail reference with an exponent/fraction sweep probe
  // and checked over ~10.8k operand/result pairs).
  function automatic logic [6:0] rec7_tab(input logic [6:0] i);
    unique case (i)
      7'd0: rec7_tab = 7'h7f; 7'd1: rec7_tab = 7'h7d; 7'd2: rec7_tab = 7'h7b; 7'd3: rec7_tab = 7'h79; 7'd4: rec7_tab = 7'h77; 7'd5: rec7_tab = 7'h75; 7'd6: rec7_tab = 7'h74; 7'd7: rec7_tab = 7'h72;
      7'd8: rec7_tab = 7'h70; 7'd9: rec7_tab = 7'h6e; 7'd10: rec7_tab = 7'h6d; 7'd11: rec7_tab = 7'h6b; 7'd12: rec7_tab = 7'h69; 7'd13: rec7_tab = 7'h68; 7'd14: rec7_tab = 7'h66; 7'd15: rec7_tab = 7'h64;
      7'd16: rec7_tab = 7'h63; 7'd17: rec7_tab = 7'h61; 7'd18: rec7_tab = 7'h60; 7'd19: rec7_tab = 7'h5e; 7'd20: rec7_tab = 7'h5d; 7'd21: rec7_tab = 7'h5b; 7'd22: rec7_tab = 7'h5a; 7'd23: rec7_tab = 7'h58;
      7'd24: rec7_tab = 7'h57; 7'd25: rec7_tab = 7'h55; 7'd26: rec7_tab = 7'h54; 7'd27: rec7_tab = 7'h53; 7'd28: rec7_tab = 7'h51; 7'd29: rec7_tab = 7'h50; 7'd30: rec7_tab = 7'h4f; 7'd31: rec7_tab = 7'h4d;
      7'd32: rec7_tab = 7'h4c; 7'd33: rec7_tab = 7'h4b; 7'd34: rec7_tab = 7'h4a; 7'd35: rec7_tab = 7'h48; 7'd36: rec7_tab = 7'h47; 7'd37: rec7_tab = 7'h46; 7'd38: rec7_tab = 7'h45; 7'd39: rec7_tab = 7'h44;
      7'd40: rec7_tab = 7'h42; 7'd41: rec7_tab = 7'h41; 7'd42: rec7_tab = 7'h40; 7'd43: rec7_tab = 7'h3f; 7'd44: rec7_tab = 7'h3e; 7'd45: rec7_tab = 7'h3d; 7'd46: rec7_tab = 7'h3c; 7'd47: rec7_tab = 7'h3b;
      7'd48: rec7_tab = 7'h3a; 7'd49: rec7_tab = 7'h39; 7'd50: rec7_tab = 7'h38; 7'd51: rec7_tab = 7'h37; 7'd52: rec7_tab = 7'h36; 7'd53: rec7_tab = 7'h35; 7'd54: rec7_tab = 7'h34; 7'd55: rec7_tab = 7'h33;
      7'd56: rec7_tab = 7'h32; 7'd57: rec7_tab = 7'h31; 7'd58: rec7_tab = 7'h30; 7'd59: rec7_tab = 7'h2f; 7'd60: rec7_tab = 7'h2e; 7'd61: rec7_tab = 7'h2d; 7'd62: rec7_tab = 7'h2c; 7'd63: rec7_tab = 7'h2b;
      7'd64: rec7_tab = 7'h2a; 7'd65: rec7_tab = 7'h29; 7'd66: rec7_tab = 7'h28; 7'd67: rec7_tab = 7'h28; 7'd68: rec7_tab = 7'h27; 7'd69: rec7_tab = 7'h26; 7'd70: rec7_tab = 7'h25; 7'd71: rec7_tab = 7'h24;
      7'd72: rec7_tab = 7'h23; 7'd73: rec7_tab = 7'h23; 7'd74: rec7_tab = 7'h22; 7'd75: rec7_tab = 7'h21; 7'd76: rec7_tab = 7'h20; 7'd77: rec7_tab = 7'h1f; 7'd78: rec7_tab = 7'h1f; 7'd79: rec7_tab = 7'h1e;
      7'd80: rec7_tab = 7'h1d; 7'd81: rec7_tab = 7'h1c; 7'd82: rec7_tab = 7'h1c; 7'd83: rec7_tab = 7'h1b; 7'd84: rec7_tab = 7'h1a; 7'd85: rec7_tab = 7'h19; 7'd86: rec7_tab = 7'h19; 7'd87: rec7_tab = 7'h18;
      7'd88: rec7_tab = 7'h17; 7'd89: rec7_tab = 7'h17; 7'd90: rec7_tab = 7'h16; 7'd91: rec7_tab = 7'h15; 7'd92: rec7_tab = 7'h15; 7'd93: rec7_tab = 7'h14; 7'd94: rec7_tab = 7'h13; 7'd95: rec7_tab = 7'h13;
      7'd96: rec7_tab = 7'h12; 7'd97: rec7_tab = 7'h11; 7'd98: rec7_tab = 7'h11; 7'd99: rec7_tab = 7'h10; 7'd100: rec7_tab = 7'h0f; 7'd101: rec7_tab = 7'h0f; 7'd102: rec7_tab = 7'h0e; 7'd103: rec7_tab = 7'h0e;
      7'd104: rec7_tab = 7'h0d; 7'd105: rec7_tab = 7'h0c; 7'd106: rec7_tab = 7'h0c; 7'd107: rec7_tab = 7'h0b; 7'd108: rec7_tab = 7'h0b; 7'd109: rec7_tab = 7'h0a; 7'd110: rec7_tab = 7'h09; 7'd111: rec7_tab = 7'h09;
      7'd112: rec7_tab = 7'h08; 7'd113: rec7_tab = 7'h08; 7'd114: rec7_tab = 7'h07; 7'd115: rec7_tab = 7'h07; 7'd116: rec7_tab = 7'h06; 7'd117: rec7_tab = 7'h05; 7'd118: rec7_tab = 7'h05; 7'd119: rec7_tab = 7'h04;
      7'd120: rec7_tab = 7'h04; 7'd121: rec7_tab = 7'h03; 7'd122: rec7_tab = 7'h03; 7'd123: rec7_tab = 7'h02; 7'd124: rec7_tab = 7'h02; 7'd125: rec7_tab = 7'h01; 7'd126: rec7_tab = 7'h01; 7'd127: rec7_tab = 7'h00;
    endcase
  endfunction

  function automatic logic [6:0] rsqrt7_tab(
      input logic e_odd, input logic [6:0] i);
    unique case ({e_odd, i})
      8'd0: rsqrt7_tab = 7'h7f; 8'd1: rsqrt7_tab = 7'h7f; 8'd2: rsqrt7_tab = 7'h7d; 8'd3: rsqrt7_tab = 7'h7d;
      8'd4: rsqrt7_tab = 7'h7b; 8'd5: rsqrt7_tab = 7'h7b; 8'd6: rsqrt7_tab = 7'h79; 8'd7: rsqrt7_tab = 7'h79;
      8'd8: rsqrt7_tab = 7'h77; 8'd9: rsqrt7_tab = 7'h77; 8'd10: rsqrt7_tab = 7'h76; 8'd11: rsqrt7_tab = 7'h76;
      8'd12: rsqrt7_tab = 7'h74; 8'd13: rsqrt7_tab = 7'h74; 8'd14: rsqrt7_tab = 7'h72; 8'd15: rsqrt7_tab = 7'h72;
      8'd16: rsqrt7_tab = 7'h71; 8'd17: rsqrt7_tab = 7'h71; 8'd18: rsqrt7_tab = 7'h6f; 8'd19: rsqrt7_tab = 7'h6f;
      8'd20: rsqrt7_tab = 7'h6d; 8'd21: rsqrt7_tab = 7'h6d; 8'd22: rsqrt7_tab = 7'h6c; 8'd23: rsqrt7_tab = 7'h6c;
      8'd24: rsqrt7_tab = 7'h6a; 8'd25: rsqrt7_tab = 7'h6a; 8'd26: rsqrt7_tab = 7'h69; 8'd27: rsqrt7_tab = 7'h69;
      8'd28: rsqrt7_tab = 7'h67; 8'd29: rsqrt7_tab = 7'h67; 8'd30: rsqrt7_tab = 7'h66; 8'd31: rsqrt7_tab = 7'h66;
      8'd32: rsqrt7_tab = 7'h64; 8'd33: rsqrt7_tab = 7'h64; 8'd34: rsqrt7_tab = 7'h63; 8'd35: rsqrt7_tab = 7'h63;
      8'd36: rsqrt7_tab = 7'h61; 8'd37: rsqrt7_tab = 7'h61; 8'd38: rsqrt7_tab = 7'h60; 8'd39: rsqrt7_tab = 7'h60;
      8'd40: rsqrt7_tab = 7'h5f; 8'd41: rsqrt7_tab = 7'h5f; 8'd42: rsqrt7_tab = 7'h5d; 8'd43: rsqrt7_tab = 7'h5d;
      8'd44: rsqrt7_tab = 7'h5c; 8'd45: rsqrt7_tab = 7'h5c; 8'd46: rsqrt7_tab = 7'h5b; 8'd47: rsqrt7_tab = 7'h5b;
      8'd48: rsqrt7_tab = 7'h5a; 8'd49: rsqrt7_tab = 7'h5a; 8'd50: rsqrt7_tab = 7'h58; 8'd51: rsqrt7_tab = 7'h58;
      8'd52: rsqrt7_tab = 7'h57; 8'd53: rsqrt7_tab = 7'h57; 8'd54: rsqrt7_tab = 7'h56; 8'd55: rsqrt7_tab = 7'h56;
      8'd56: rsqrt7_tab = 7'h55; 8'd57: rsqrt7_tab = 7'h55; 8'd58: rsqrt7_tab = 7'h54; 8'd59: rsqrt7_tab = 7'h54;
      8'd60: rsqrt7_tab = 7'h53; 8'd61: rsqrt7_tab = 7'h53; 8'd62: rsqrt7_tab = 7'h52; 8'd63: rsqrt7_tab = 7'h52;
      8'd64: rsqrt7_tab = 7'h50; 8'd65: rsqrt7_tab = 7'h50; 8'd66: rsqrt7_tab = 7'h4f; 8'd67: rsqrt7_tab = 7'h4f;
      8'd68: rsqrt7_tab = 7'h4e; 8'd69: rsqrt7_tab = 7'h4e; 8'd70: rsqrt7_tab = 7'h4d; 8'd71: rsqrt7_tab = 7'h4d;
      8'd72: rsqrt7_tab = 7'h4c; 8'd73: rsqrt7_tab = 7'h4c; 8'd74: rsqrt7_tab = 7'h4b; 8'd75: rsqrt7_tab = 7'h4b;
      8'd76: rsqrt7_tab = 7'h4a; 8'd77: rsqrt7_tab = 7'h4a; 8'd78: rsqrt7_tab = 7'h49; 8'd79: rsqrt7_tab = 7'h49;
      8'd80: rsqrt7_tab = 7'h48; 8'd81: rsqrt7_tab = 7'h48; 8'd82: rsqrt7_tab = 7'h47; 8'd83: rsqrt7_tab = 7'h47;
      8'd84: rsqrt7_tab = 7'h46; 8'd85: rsqrt7_tab = 7'h46; 8'd86: rsqrt7_tab = 7'h46; 8'd87: rsqrt7_tab = 7'h46;
      8'd88: rsqrt7_tab = 7'h45; 8'd89: rsqrt7_tab = 7'h45; 8'd90: rsqrt7_tab = 7'h44; 8'd91: rsqrt7_tab = 7'h44;
      8'd92: rsqrt7_tab = 7'h43; 8'd93: rsqrt7_tab = 7'h43; 8'd94: rsqrt7_tab = 7'h42; 8'd95: rsqrt7_tab = 7'h42;
      8'd96: rsqrt7_tab = 7'h41; 8'd97: rsqrt7_tab = 7'h41; 8'd98: rsqrt7_tab = 7'h40; 8'd99: rsqrt7_tab = 7'h40;
      8'd100: rsqrt7_tab = 7'h3f; 8'd101: rsqrt7_tab = 7'h3f; 8'd102: rsqrt7_tab = 7'h3f; 8'd103: rsqrt7_tab = 7'h3f;
      8'd104: rsqrt7_tab = 7'h3e; 8'd105: rsqrt7_tab = 7'h3e; 8'd106: rsqrt7_tab = 7'h3d; 8'd107: rsqrt7_tab = 7'h3d;
      8'd108: rsqrt7_tab = 7'h3c; 8'd109: rsqrt7_tab = 7'h3c; 8'd110: rsqrt7_tab = 7'h3b; 8'd111: rsqrt7_tab = 7'h3b;
      8'd112: rsqrt7_tab = 7'h3b; 8'd113: rsqrt7_tab = 7'h3b; 8'd114: rsqrt7_tab = 7'h3a; 8'd115: rsqrt7_tab = 7'h3a;
      8'd116: rsqrt7_tab = 7'h39; 8'd117: rsqrt7_tab = 7'h39; 8'd118: rsqrt7_tab = 7'h38; 8'd119: rsqrt7_tab = 7'h38;
      8'd120: rsqrt7_tab = 7'h38; 8'd121: rsqrt7_tab = 7'h38; 8'd122: rsqrt7_tab = 7'h37; 8'd123: rsqrt7_tab = 7'h37;
      8'd124: rsqrt7_tab = 7'h36; 8'd125: rsqrt7_tab = 7'h36; 8'd126: rsqrt7_tab = 7'h35; 8'd127: rsqrt7_tab = 7'h35;
      8'd128: rsqrt7_tab = 7'h34; 8'd129: rsqrt7_tab = 7'h34; 8'd130: rsqrt7_tab = 7'h33; 8'd131: rsqrt7_tab = 7'h33;
      8'd132: rsqrt7_tab = 7'h32; 8'd133: rsqrt7_tab = 7'h32; 8'd134: rsqrt7_tab = 7'h30; 8'd135: rsqrt7_tab = 7'h30;
      8'd136: rsqrt7_tab = 7'h2f; 8'd137: rsqrt7_tab = 7'h2f; 8'd138: rsqrt7_tab = 7'h2e; 8'd139: rsqrt7_tab = 7'h2e;
      8'd140: rsqrt7_tab = 7'h2c; 8'd141: rsqrt7_tab = 7'h2c; 8'd142: rsqrt7_tab = 7'h2b; 8'd143: rsqrt7_tab = 7'h2b;
      8'd144: rsqrt7_tab = 7'h2a; 8'd145: rsqrt7_tab = 7'h2a; 8'd146: rsqrt7_tab = 7'h29; 8'd147: rsqrt7_tab = 7'h29;
      8'd148: rsqrt7_tab = 7'h28; 8'd149: rsqrt7_tab = 7'h28; 8'd150: rsqrt7_tab = 7'h27; 8'd151: rsqrt7_tab = 7'h27;
      8'd152: rsqrt7_tab = 7'h26; 8'd153: rsqrt7_tab = 7'h26; 8'd154: rsqrt7_tab = 7'h24; 8'd155: rsqrt7_tab = 7'h24;
      8'd156: rsqrt7_tab = 7'h23; 8'd157: rsqrt7_tab = 7'h23; 8'd158: rsqrt7_tab = 7'h22; 8'd159: rsqrt7_tab = 7'h22;
      8'd160: rsqrt7_tab = 7'h21; 8'd161: rsqrt7_tab = 7'h21; 8'd162: rsqrt7_tab = 7'h20; 8'd163: rsqrt7_tab = 7'h20;
      8'd164: rsqrt7_tab = 7'h1f; 8'd165: rsqrt7_tab = 7'h1f; 8'd166: rsqrt7_tab = 7'h1e; 8'd167: rsqrt7_tab = 7'h1e;
      8'd168: rsqrt7_tab = 7'h1e; 8'd169: rsqrt7_tab = 7'h1e; 8'd170: rsqrt7_tab = 7'h1d; 8'd171: rsqrt7_tab = 7'h1d;
      8'd172: rsqrt7_tab = 7'h1c; 8'd173: rsqrt7_tab = 7'h1c; 8'd174: rsqrt7_tab = 7'h1b; 8'd175: rsqrt7_tab = 7'h1b;
      8'd176: rsqrt7_tab = 7'h1a; 8'd177: rsqrt7_tab = 7'h1a; 8'd178: rsqrt7_tab = 7'h19; 8'd179: rsqrt7_tab = 7'h19;
      8'd180: rsqrt7_tab = 7'h18; 8'd181: rsqrt7_tab = 7'h18; 8'd182: rsqrt7_tab = 7'h17; 8'd183: rsqrt7_tab = 7'h17;
      8'd184: rsqrt7_tab = 7'h17; 8'd185: rsqrt7_tab = 7'h17; 8'd186: rsqrt7_tab = 7'h16; 8'd187: rsqrt7_tab = 7'h16;
      8'd188: rsqrt7_tab = 7'h15; 8'd189: rsqrt7_tab = 7'h15; 8'd190: rsqrt7_tab = 7'h14; 8'd191: rsqrt7_tab = 7'h14;
      8'd192: rsqrt7_tab = 7'h13; 8'd193: rsqrt7_tab = 7'h13; 8'd194: rsqrt7_tab = 7'h13; 8'd195: rsqrt7_tab = 7'h13;
      8'd196: rsqrt7_tab = 7'h12; 8'd197: rsqrt7_tab = 7'h12; 8'd198: rsqrt7_tab = 7'h11; 8'd199: rsqrt7_tab = 7'h11;
      8'd200: rsqrt7_tab = 7'h10; 8'd201: rsqrt7_tab = 7'h10; 8'd202: rsqrt7_tab = 7'h10; 8'd203: rsqrt7_tab = 7'h10;
      8'd204: rsqrt7_tab = 7'h0f; 8'd205: rsqrt7_tab = 7'h0f; 8'd206: rsqrt7_tab = 7'h0e; 8'd207: rsqrt7_tab = 7'h0e;
      8'd208: rsqrt7_tab = 7'h0e; 8'd209: rsqrt7_tab = 7'h0e; 8'd210: rsqrt7_tab = 7'h0d; 8'd211: rsqrt7_tab = 7'h0d;
      8'd212: rsqrt7_tab = 7'h0c; 8'd213: rsqrt7_tab = 7'h0c; 8'd214: rsqrt7_tab = 7'h0c; 8'd215: rsqrt7_tab = 7'h0c;
      8'd216: rsqrt7_tab = 7'h0b; 8'd217: rsqrt7_tab = 7'h0b; 8'd218: rsqrt7_tab = 7'h0a; 8'd219: rsqrt7_tab = 7'h0a;
      8'd220: rsqrt7_tab = 7'h0a; 8'd221: rsqrt7_tab = 7'h0a; 8'd222: rsqrt7_tab = 7'h09; 8'd223: rsqrt7_tab = 7'h09;
      8'd224: rsqrt7_tab = 7'h09; 8'd225: rsqrt7_tab = 7'h09; 8'd226: rsqrt7_tab = 7'h08; 8'd227: rsqrt7_tab = 7'h08;
      8'd228: rsqrt7_tab = 7'h07; 8'd229: rsqrt7_tab = 7'h07; 8'd230: rsqrt7_tab = 7'h07; 8'd231: rsqrt7_tab = 7'h07;
      8'd232: rsqrt7_tab = 7'h06; 8'd233: rsqrt7_tab = 7'h06; 8'd234: rsqrt7_tab = 7'h06; 8'd235: rsqrt7_tab = 7'h06;
      8'd236: rsqrt7_tab = 7'h05; 8'd237: rsqrt7_tab = 7'h05; 8'd238: rsqrt7_tab = 7'h04; 8'd239: rsqrt7_tab = 7'h04;
      8'd240: rsqrt7_tab = 7'h04; 8'd241: rsqrt7_tab = 7'h04; 8'd242: rsqrt7_tab = 7'h03; 8'd243: rsqrt7_tab = 7'h03;
      8'd244: rsqrt7_tab = 7'h03; 8'd245: rsqrt7_tab = 7'h03; 8'd246: rsqrt7_tab = 7'h02; 8'd247: rsqrt7_tab = 7'h02;
      8'd248: rsqrt7_tab = 7'h02; 8'd249: rsqrt7_tab = 7'h02; 8'd250: rsqrt7_tab = 7'h01; 8'd251: rsqrt7_tab = 7'h01;
      8'd252: rsqrt7_tab = 7'h01; 8'd253: rsqrt7_tab = 7'h01; 8'd254: rsqrt7_tab = 7'h00; 8'd255: rsqrt7_tab = 7'h00;
    endcase
  endfunction


  // vfrec7 (rsqrt=0) / vfrsqrt7 (rsqrt=1) element estimate.
  // The operand is normalized through unpack(); the result
  // is assembled from the table fraction with no rounding
  // (and no UF/NX except reciprocal overflow, per Sail).
  function automatic fp_eval_result_t fp_estimate(
      input logic rsqrt, input logic d, input logic [2:0] rm,
      input logic [63:0] v);
    /* verilator no_inline_task */
    unpacked_t u;
    fp_eval_result_t r;
    logic signed [15:0] eo, emax, emin;
    logic [6:0] idx, f7;
    logic [63:0] canon, infv, zerov, maxv;
    logic [62:0] field;
    logic [7:0] sig8;
    begin
      u = unpack(v, d);
      emax = d ? 16'sd1023 : 16'sd127;
      emin = d ? -16'sd1022 : -16'sd126;
      canon = d ? 64'h7FF8_0000_0000_0000
                : 64'hFFFF_FFFF_7FC0_0000;
      infv = d ? {u.sign, 11'h7FF, 52'b0}
               : {32'hFFFF_FFFF, u.sign, 8'hFF, 23'b0};
      zerov = d ? {u.sign, 63'b0}
                : {32'hFFFF_FFFF, u.sign, 31'b0};
      maxv = d ? {u.sign, 11'h7FE, 52'hF_FFFF_FFFF_FFFF}
               : {32'hFFFF_FFFF, u.sign, 8'hFE, 23'h7F_FFFF};
      idx = u.sig[51:45];  // significand is left-aligned in both formats
      r.flags = 5'b0;
      r.result = canon;
      if (u.is_nan) begin
        r.flags[4] = u.is_snan;  // NV
      end else if (rsqrt && u.sign && !u.is_zero) begin
        r.flags[4] = 1'b1;       // NV: rsqrt of negative
      end else if (u.is_inf) begin
        r.result = zerov;
      end else if (u.is_zero) begin
        r.result = infv;
        r.flags[3] = 1'b1;       // DZ
      end else begin
        if (rsqrt) begin
          f7 = rsqrt7_tab(u.exp[0], idx);
          eo = -(u.exp >>> 1) - 16'sd1;
        end else begin
          f7 = rec7_tab(idx);
          eo = -u.exp - 16'sd1;
        end
        sig8 = {1'b1, f7};
        if (eo > emax) begin
          // Reciprocal overflow follows the standard
          // rounding-mode overflow rule (inf vs max finite).
          r.result = ((rm == 3'b001) ||
                      ((rm == 3'b010) && !u.sign) ||
                      ((rm == 3'b011) && u.sign)) ? maxv : infv;
          r.flags[2] = 1'b1;     // OF
          r.flags[0] = 1'b1;     // NX
        end else if (eo >= emin) begin
          r.result = d ? {(rsqrt ? 1'b0 : u.sign),
                          11'(eo + 16'sd1023), f7, 45'b0}
                       : {32'hFFFF_FFFF, (rsqrt ? 1'b0 : u.sign),
                          8'(eo + 16'sd127), f7, 16'b0};
        end else begin
          // Subnormal result (reciprocal of large values):
          // 8 significand bits shifted right by emin - eo.
          field = {55'b0, sig8} <<
                  ((d ? 6'd45 : 6'd16) - 6'(emin - eo));
          r.result = d ? {(rsqrt ? 1'b0 : u.sign), field}
                       : {32'hFFFF_FFFF, (rsqrt ? 1'b0 : u.sign),
                          field[30:0]};
        end
      end
      return r;
    end
  endfunction

  // ---------------------------------------------------------
  // Whole evaluation, combinational: the same stage functions
  // muserisc_fpu sequences, chained without registers. Used per
  // element by the vector unit and as the simulation
  // cross-check reference inside muserisc_fpu.
  // ---------------------------------------------------------
  function automatic fp_eval_result_t fp_eval(
      input logic [4:0]  op,
      input logic        fmt_d,
      input logic [2:0]  rm,
      input logic [63:0] a,
      input logic [63:0] b,
      input logic [63:0] c,
      input logic [1:0]  aux);
    // Keep as one C++ function: inlining the full chain at
    // every vector call site explodes the Verilated model.
    /* verilator no_inline_task */
    fp_eval_result_t r;
    unpacked_t ua, ub, uc;
    fp_special_t sp;
    fp_rnd_t rn;
    fp_ds_t ds;
    ua = unpack(a, (op == FPU_F2F) ? !fmt_d : fmt_d);
    ub = unpack(b, fmt_d);
    uc = unpack(c, fmt_d);
    sp = fp_special(op, fmt_d, ua, ub, uc, aux);
    rn = '0;
    if (fp_is_fast(op)) begin
      r.result = fp_fastop(op, fmt_d, a, b, aux);
      r.flags = 5'd0;
    end else if (op == FPU_F2I) begin
      r = f2i_s2(f2i_s1(ua, rm), aux);
    end else if (sp.hit) begin
      r.result = sp.result;
      r.flags = sp.flags;
    end else begin
      unique case (op)
        FPU_ADD, FPU_SUB:
          rn = fp_norm(fp_addsub(fp_align(fop_unp(ua, 1'b0),
                                          fop_unp(ub, op == FPU_SUB)), rm));
        FPU_MUL:
          rn = fp_norm(fop_sum(fop_prod(op, ua, ub,
                                        fp_mul_sum(fp_mul_pp(ua.sig, ub.sig)))));
        FPU_DIV, FPU_SQRT: begin
          ds = ds_init(op == FPU_SQRT, ua, ub);
          for (int i = 0; i < FPU_DS_N_D; i++) begin
            if (fmt_d || (i < FPU_DS_N_S)) ds = ds_step(ds);
          end
          rn = ds_fin(ds, fmt_d);
        end
        FPU_I2F:
          rn = fp_norm(i2f_sum(a, aux));
        FPU_F2F:
          rn = f2f_rnd(ua);
        default:  // FMA family
          rn = fp_norm(fp_addsub(fp_align(
                   fop_prod(op, ua, ub, fp_mul_sum(fp_mul_pp(ua.sig, ub.sig))),
                   fop_unp(uc, fma_neg_c(op))), rm));
      endcase
      r = fp_round(rn, fmt_d, rm);
    end
    return r;
  endfunction

  /* verilator lint_on UNUSEDSIGNAL */
endpackage
`default_nettype wire
