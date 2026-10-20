// museRISC in-house core: helpers for muserisc_bext
// (issue #27). Op encodings plus bit-manipulation and AES
// helper functions (originally extracted from muserisc_bext.sv;
// the AES S-box is now a composite-field GF((2^4)^2) circuit).
`default_nettype none
package muserisc_bext_pkg;

  // Operation encoding (decoder assigns these).
  localparam logic [5:0] BOP_ADD_UW   = 6'd0;
  localparam logic [5:0] BOP_SH1ADD   = 6'd1;
  localparam logic [5:0] BOP_SH2ADD   = 6'd2;
  localparam logic [5:0] BOP_SH3ADD   = 6'd3;
  localparam logic [5:0] BOP_SH1ADDUW = 6'd4;
  localparam logic [5:0] BOP_SH2ADDUW = 6'd5;
  localparam logic [5:0] BOP_SH3ADDUW = 6'd6;
  localparam logic [5:0] BOP_SLLI_UW  = 6'd7;
  localparam logic [5:0] BOP_ANDN     = 6'd8;
  localparam logic [5:0] BOP_ORN      = 6'd9;
  localparam logic [5:0] BOP_XNOR     = 6'd10;
  localparam logic [5:0] BOP_CLZ      = 6'd11;
  localparam logic [5:0] BOP_CLZW     = 6'd12;
  localparam logic [5:0] BOP_CTZ      = 6'd13;
  localparam logic [5:0] BOP_CTZW     = 6'd14;
  localparam logic [5:0] BOP_CPOP     = 6'd15;
  localparam logic [5:0] BOP_CPOPW    = 6'd16;
  localparam logic [5:0] BOP_MAX      = 6'd17;
  localparam logic [5:0] BOP_MAXU     = 6'd18;
  localparam logic [5:0] BOP_MIN      = 6'd19;
  localparam logic [5:0] BOP_MINU     = 6'd20;
  localparam logic [5:0] BOP_SEXT_B   = 6'd21;
  localparam logic [5:0] BOP_SEXT_H   = 6'd22;
  localparam logic [5:0] BOP_ROL      = 6'd23;
  localparam logic [5:0] BOP_ROLW     = 6'd24;
  localparam logic [5:0] BOP_ROR      = 6'd25;   // incl. RORI
  localparam logic [5:0] BOP_RORW     = 6'd26;   // incl. RORIW
  localparam logic [5:0] BOP_ORC_B    = 6'd27;
  localparam logic [5:0] BOP_REV8     = 6'd28;
  localparam logic [5:0] BOP_CLMUL    = 6'd29;
  localparam logic [5:0] BOP_CLMULH   = 6'd30;
  localparam logic [5:0] BOP_CLMULR   = 6'd31;
  localparam logic [5:0] BOP_BCLR     = 6'd32;   // incl. I forms
  localparam logic [5:0] BOP_BEXT     = 6'd33;
  localparam logic [5:0] BOP_BINV     = 6'd34;
  localparam logic [5:0] BOP_BSET     = 6'd35;
  localparam logic [5:0] BOP_CZEQZ    = 6'd36;
  localparam logic [5:0] BOP_CZNEZ    = 6'd37;
  localparam logic [5:0] BOP_PACK     = 6'd38;
  localparam logic [5:0] BOP_PACKH    = 6'd39;
  localparam logic [5:0] BOP_PACKW    = 6'd40;
  localparam logic [5:0] BOP_BREV8    = 6'd41;
  localparam logic [5:0] BOP_XPERM4   = 6'd42;
  localparam logic [5:0] BOP_XPERM8   = 6'd43;
  localparam logic [5:0] BOP_AES_ES   = 6'd44;
  localparam logic [5:0] BOP_AES_ESM  = 6'd45;
  localparam logic [5:0] BOP_AES_DS   = 6'd46;
  localparam logic [5:0] BOP_AES_DSM  = 6'd47;
  localparam logic [5:0] BOP_AES_IM   = 6'd48;
  localparam logic [5:0] BOP_AES_KS1I = 6'd49;   // b_i[3:0] = rcon index
  localparam logic [5:0] BOP_AES_KS2  = 6'd50;
  localparam logic [5:0] BOP_SHA256SIG0 = 6'd51;
  localparam logic [5:0] BOP_SHA256SIG1 = 6'd52;
  localparam logic [5:0] BOP_SHA256SUM0 = 6'd53;
  localparam logic [5:0] BOP_SHA256SUM1 = 6'd54;
  localparam logic [5:0] BOP_SHA512SIG0 = 6'd55;
  localparam logic [5:0] BOP_SHA512SIG1 = 6'd56;
  localparam logic [5:0] BOP_SHA512SUM0 = 6'd57;
  localparam logic [5:0] BOP_SHA512SUM1 = 6'd58;

  // ---- helpers ------------------------------------------------
  function automatic logic [6:0] clz64(input logic [63:0] v);
    logic [6:0] n;
    n = 7'd64;
    for (int i = 63; i >= 0; i--) begin
      if (v[i] && (n == 7'd64)) n = 7'(63 - i);
    end
    return n;
  endfunction

  function automatic logic [6:0] ctz64(input logic [63:0] v);
    logic [6:0] n;
    n = 7'd64;
    for (int i = 0; i < 64; i++) begin
      if (v[i] && (n == 7'd64)) n = 7'(i);
    end
    return n;
  endfunction

  function automatic logic [127:0] clmul128(input logic [63:0] x,
                                            input logic [63:0] y);
    logic [127:0] r;
    r = 128'b0;
    for (int i = 0; i < 64; i++) begin
      if (y[i]) r = r ^ (128'(x) << i);
    end
    return r;
  endfunction

  function automatic logic [63:0] ror64(input logic [63:0] v,
                                        input logic [5:0] sh);
    if (sh == 6'd0) return v;
    return (v >> sh) | (v << (6'd0 - sh));
  endfunction

  function automatic logic [31:0] ror32(input logic [31:0] v,
                                        input logic [4:0] sh);
    if (sh == 5'd0) return v;
    return (v >> sh) | (v << (5'd0 - sh));
  endfunction

  // ---- AES GF(2^8) arithmetic --------------------------------
  // General GF(2^8) multiply (AES polynomial 0x11B). Only ever
  // called with a constant second operand (MixColumns), which
  // folds to a shallow xtime/XOR network at elaboration.
  function automatic logic [7:0] gf_mul(input logic [7:0] x,
                                        input logic [7:0] y);
    logic [7:0] r;
    logic [7:0] a, b;
    r = 8'b0; a = x; b = y;
    for (int i = 0; i < 8; i++) begin
      if (b[0]) r = r ^ a;
      a = {a[6:0], 1'b0} ^ (a[7] ? 8'h1B : 8'h00);
      b = b >> 1;
    end
    return r;
  endfunction

  // ---- AES S-box: composite field GF((2^4)^2) ------------------
  // The GF(2^8) inverse at the heart of SubBytes/InvSubBytes is
  // computed in an isomorphic tower field (Satoh/Canright style)
  // instead of as x^254, which was 8 chained variable GF(2^8)
  // multiplies in a while loop: very deep, and not
  // synthesizable by Yosys.
  //   GF(16)      = GF(2)[w]/(w^4 + w + 1), polynomial basis
  //   GF(16^2)    = GF(16)[z]/(z^2 + z + LAM), element h*z + l
  //                 packed {h[3:0], l[3:0]}
  //   (h z + l)^-1 = (h d) z + (h + l) d,
  //                 d = (h^2 LAM + h l + l^2)^-1 in GF(16)
  // The isomorphism maps z-tower generator 0x14 to AES element
  // 0x1E; LAM and the root were chosen (exhaustive search over
  // all 8 LAM x 8 conjugate roots) to minimise the total weight
  // of the four 8x8 GF(2) matrices below (unique minimum: 110,
  // next 112). scripts/gen_aes_tower.py reproduces every
  // constant here (incl. the GF(16) inverse table); run it with
  // --check to compare against this file. Forward and inverse
  // S-boxes share one tower inverter: the input matrix folds in
  // the AES->tower map (and, for decryption, the inverse
  // affine transform), the output matrix folds in the tower->
  // AES map (and, for encryption, the forward affine
  // transform). The constants are checked exhaustively (all
  // 256 inputs, both directions) against the FIPS-197 tables
  // in tb/cpp/bext_tb.cpp.
  localparam logic [3:0] AES_TOWER_LAM = 4'hA;
  // 8x8 GF(2) matrices, packed {row7, ..., row0}; row o bit i is
  // the coefficient of input bit i in output bit o.
  localparam logic [63:0] AES_M_IN_FWD = {   // AES -> tower
      8'b10100000, 8'b01110010, 8'b10101100, 8'b11011100,
      8'b11001010, 8'b11000010, 8'b00101100, 8'b00100001};
  localparam logic [63:0] AES_M_IN_INV = {   // inv-affine, -> tower
      8'b11000110, 8'b10111110, 8'b01110001, 8'b10000110,
      8'b00010111, 8'b00110010, 8'b00100011, 8'b00110000};
  localparam logic [7:0]  AES_C_IN_INV = 8'h33;  // tower(0x05)
  localparam logic [63:0] AES_M_OUT_FWD = {  // tower ->, affine
      8'b00011110, 8'b10010000, 8'b10110110, 8'b10110111,
      8'b01010001, 8'b00001011, 8'b00000101, 8'b10110001};
  localparam logic [63:0] AES_M_OUT_INV = {  // tower -> AES
      8'b00100010, 8'b01010110, 8'b10100010, 8'b11000100,
      8'b00001100, 8'b10101100, 8'b01110000, 8'b10100011};

  // Constant 8x8 GF(2) matrix times vector: one balanced XOR
  // tree (reduction) per output bit.
  function automatic logic [7:0] gf2_mat8(input logic [63:0] m,
                                          input logic [7:0] x);
    logic [7:0] y;
    for (int o = 0; o < 8; o++) y[o] = ^(m[o*8 +: 8] & x);
    return y;
  endfunction

  function automatic logic [3:0] gf16_mul(input logic [3:0] a,
                                          input logic [3:0] b);
    logic [6:0] p;
    p = 7'b0;
    for (int i = 0; i < 4; i++) begin
      if (b[i]) p = p ^ (7'(a) << i);
    end
    // reduce w^6..w^4 with w^4 = w + 1
    // (w^5 = w^2 + w, w^6 = w^3 + w^2).
    return p[3:0] ^ {p[6], p[5] ^ p[6], p[4] ^ p[5], p[4]};
  endfunction

  // Squaring is linear in GF(16): (a3 a2 a1 a0)^2.
  function automatic logic [3:0] gf16_sq(input logic [3:0] a);
    return {a[3], a[3] ^ a[1], a[2], a[2] ^ a[0]};
  endfunction

  // GF(16) inverse (0 -> 0): a 4-input function, so a 16-entry
  // table is both the shallowest and the smallest form.
  function automatic logic [3:0] gf16_inv(input logic [3:0] a);
    unique case (a)
      4'h0: return 4'h0;  4'h1: return 4'h1;
      4'h2: return 4'h9;  4'h3: return 4'hE;
      4'h4: return 4'hD;  4'h5: return 4'hB;
      4'h6: return 4'h7;  4'h7: return 4'h6;
      4'h8: return 4'hF;  4'h9: return 4'h2;
      4'hA: return 4'hC;  4'hB: return 4'h5;
      4'hC: return 4'hA;  4'hD: return 4'h4;
      4'hE: return 4'h3;  default: return 4'h8;
    endcase
  endfunction

  // Inverse in GF(16^2) (0 -> 0, as AES requires).
  function automatic logic [7:0] gf256t_inv(input logic [7:0] x);
    logic [3:0] h, l, d;
    h = x[7:4];
    l = x[3:0];
    d = gf16_inv(gf16_mul(gf16_sq(h), AES_TOWER_LAM) ^
                 gf16_mul(h, l) ^ gf16_sq(l));
    return {gf16_mul(h, d), gf16_mul(h ^ l, d)};
  endfunction

  // Shared forward / inverse AES S-box (inv = 1: InvSubBytes).
  function automatic logic [7:0] aes_sbox_fi(input logic [7:0] x,
                                             input logic inv);
    logic [7:0] t, v;
    t = inv ? (gf2_mat8(AES_M_IN_INV, x) ^ AES_C_IN_INV)
            : gf2_mat8(AES_M_IN_FWD, x);
    v = gf256t_inv(t);
    return inv ? gf2_mat8(AES_M_OUT_INV, v)
               : (gf2_mat8(AES_M_OUT_FWD, v) ^ 8'h63);
  endfunction

  // MixColumns on one 32-bit column (little-endian bytes).
  function automatic logic [31:0] mixcol(input logic [31:0] w);
    logic [7:0] b0, b1, b2, b3;
    b0 = w[7:0]; b1 = w[15:8]; b2 = w[23:16]; b3 = w[31:24];
    return {
      gf_mul(b0, 8'h03) ^ b1 ^ b2 ^ gf_mul(b3, 8'h02),
      b0 ^ b1 ^ gf_mul(b2, 8'h02) ^ gf_mul(b3, 8'h03),
      b0 ^ gf_mul(b1, 8'h02) ^ gf_mul(b2, 8'h03) ^ b3,
      gf_mul(b0, 8'h02) ^ gf_mul(b1, 8'h03) ^ b2 ^ b3};
  endfunction

  function automatic logic [31:0] imixcol(input logic [31:0] w);
    logic [7:0] b0, b1, b2, b3;
    b0 = w[7:0]; b1 = w[15:8]; b2 = w[23:16]; b3 = w[31:24];
    return {
      gf_mul(b0, 8'h0B) ^ gf_mul(b1, 8'h0D) ^ gf_mul(b2, 8'h09) ^
          gf_mul(b3, 8'h0E),
      gf_mul(b0, 8'h0D) ^ gf_mul(b1, 8'h09) ^ gf_mul(b2, 8'h0E) ^
          gf_mul(b3, 8'h0B),
      gf_mul(b0, 8'h09) ^ gf_mul(b1, 8'h0E) ^ gf_mul(b2, 8'h0B) ^
          gf_mul(b3, 8'h0D),
      gf_mul(b0, 8'h0E) ^ gf_mul(b1, 8'h0B) ^ gf_mul(b2, 8'h0D) ^
          gf_mul(b3, 8'h09)};
  endfunction

  // One aes64 round half: rs1 (a) and rs2 (b) together hold
  // the 128-bit state (a = columns 0-1, b = columns 2-3,
  // column-major little-endian). Select the (Inv)ShiftRows
  // bytes of the low 64-bit half (swapping the operands gives
  // the high half); muserisc_bext then applies (Inv)SubBytes
  // through its eight shared S-box lanes. Byte selection
  // follows the K spec (cross-checked against CVA6 aes.sv).
  function automatic logic [63:0] aes_shift_rows(
      input logic [63:0] a, input logic [63:0] b, input logic inv);
    logic [7:0] s [16];
    logic [7:0] o [8];
    for (int i = 0; i < 8; i++) begin
      s[i]   = a[i*8 +: 8];
      s[i+8] = b[i*8 +: 8];
    end
    if (!inv) begin
      o[0] = s[0];  o[1] = s[5];  o[2] = s[10]; o[3] = s[15];
      o[4] = s[4];  o[5] = s[9];  o[6] = s[14]; o[7] = s[3];
    end else begin
      o[0] = s[0];  o[1] = s[13]; o[2] = s[10]; o[3] = s[7];
      o[4] = s[4];  o[5] = s[1];  o[6] = s[14]; o[7] = s[11];
    end
    return {o[7], o[6], o[5], o[4], o[3], o[2], o[1], o[0]};
  endfunction

  function automatic logic [7:0] aes_rcon(input logic [3:0] i);
    unique case (i)
      4'h0:    return 8'h01;
      4'h1:    return 8'h02;
      4'h2:    return 8'h04;
      4'h3:    return 8'h08;
      4'h4:    return 8'h10;
      4'h5:    return 8'h20;
      4'h6:    return 8'h40;
      4'h7:    return 8'h80;
      4'h8:    return 8'h1B;
      4'h9:    return 8'h36;
      default: return 8'h00;   // 0xA unused by AES-128/192/256
    endcase
  endfunction

endpackage
`default_nettype wire
