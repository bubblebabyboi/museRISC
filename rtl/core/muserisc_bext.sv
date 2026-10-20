// museRISC in-house core: B-extension (Zba/Zbb/Zbc/Zbs),
// Zicond, and scalar-crypto (Zbkb/Zbkx/Zkne/Zknd/Zknh)
// execution unit. Combinational; selected by ctrl.bext with
// the operation in ctrl.bext_op. The AES S-box is a shallow
// composite-field GF((2^4)^2) circuit (muserisc_bext_pkg);
// eight S-box lanes, each shared between SubBytes and
// InvSubBytes, serve aes64es/esm/ds/dsm and aes64ks1i.

module muserisc_bext import muserisc_bext_pkg::*; (
    input  logic [5:0]  op_i,
    input  logic [63:0] a_i,       // rs1 (forwarded)
    input  logic [63:0] b_i,       // rs2 or shamt-bearing imm
    output logic [63:0] result_o
);

  // Op encodings + bit-manip/AES helpers: muserisc_bext_pkg.

  logic [127:0] clp;

  // ---- AES S-box lanes ------------------------------------------
  // aes64es/esm/ds/dsm substitute the eight (Inv)ShiftRows-
  // selected bytes; aes64ks1i substitutes the four bytes of
  // RotWord(rs1[63:32]) (no rotation for rcon index 0xA, the
  // AES-256 schedule) on lanes 0-3. Lanes 4-7 then see the
  // ShiftRows bytes but their outputs are unused.
  logic        sb_inv;
  logic [31:0] ks_w;
  logic [63:0] sb_in, sb_out;

  always_comb begin
    sb_inv = (op_i == BOP_AES_DS) || (op_i == BOP_AES_DSM);
    ks_w = a_i[63:32];
    if (b_i[3:0] != 4'hA) ks_w = {ks_w[7:0], ks_w[31:8]};
    sb_in = aes_shift_rows(a_i, b_i, sb_inv);
    if (op_i == BOP_AES_KS1I) sb_in[31:0] = ks_w;
    for (int i = 0; i < 8; i++) begin
      sb_out[i*8 +: 8] = aes_sbox_fi(sb_in[i*8 +: 8], sb_inv);
    end
  end

  always_comb begin
    logic [63:0] r;
    logic [31:0] w32;
    logic [6:0]  cnt;
    logic [63:0] a32z;   // zero-extended rs1[31:0] (local: the
                         // upper half is a constant tie-off)
    a32z = {32'b0, a_i[31:0]};
    clp = clmul128(a_i, b_i);
    r = 64'b0;
    w32 = 32'b0;
    cnt = 7'b0;

    unique case (op_i)
      BOP_ADD_UW:   r = a32z + b_i;
      BOP_SH1ADD:   r = (a_i << 1) + b_i;
      BOP_SH2ADD:   r = (a_i << 2) + b_i;
      BOP_SH3ADD:   r = (a_i << 3) + b_i;
      BOP_SH1ADDUW: r = (a32z << 1) + b_i;
      BOP_SH2ADDUW: r = (a32z << 2) + b_i;
      BOP_SH3ADDUW: r = (a32z << 3) + b_i;
      BOP_SLLI_UW:  r = a32z << b_i[5:0];
      BOP_ANDN:     r = a_i & ~b_i;
      BOP_ORN:      r = a_i | ~b_i;
      BOP_XNOR:     r = ~(a_i ^ b_i);
      BOP_CLZ:      r = {57'b0, clz64(a_i)};
      BOP_CLZW:     r = {57'b0, clz64(a32z) - 7'd32};
      BOP_CTZ:      r = {57'b0, ctz64(a_i)};
      BOP_CTZW:     r = a_i[31:0] == 32'b0 ? 64'd32
                        : {57'b0, ctz64({32'b0, a_i[31:0]})};
      BOP_CPOP: begin
        cnt = 7'b0;
        for (int i = 0; i < 64; i++) cnt += {6'b0, a_i[i]};
        r = {57'b0, cnt};
      end
      BOP_CPOPW: begin
        cnt = 7'b0;
        for (int i = 0; i < 32; i++) cnt += {6'b0, a_i[i]};
        r = {57'b0, cnt};
      end
      BOP_MAX:  r = ($signed(a_i) >= $signed(b_i)) ? a_i : b_i;
      BOP_MAXU: r = (a_i >= b_i) ? a_i : b_i;
      BOP_MIN:  r = ($signed(a_i) <= $signed(b_i)) ? a_i : b_i;
      BOP_MINU: r = (a_i <= b_i) ? a_i : b_i;
      BOP_SEXT_B: r = {{56{a_i[7]}}, a_i[7:0]};
      BOP_SEXT_H: r = {{48{a_i[15]}}, a_i[15:0]};
      BOP_ROL:  r = ror64(a_i, 6'd0 - b_i[5:0]);
      BOP_ROLW: begin
        w32 = ror32(a_i[31:0], 5'd0 - b_i[4:0]);
        if (b_i[4:0] == 5'd0) w32 = a_i[31:0];
        r = {{32{w32[31]}}, w32};
      end
      BOP_ROR:  r = ror64(a_i, b_i[5:0]);
      BOP_RORW: begin
        w32 = ror32(a_i[31:0], b_i[4:0]);
        r = {{32{w32[31]}}, w32};
      end
      BOP_ORC_B: begin
        for (int i = 0; i < 8; i++) begin
          r[i*8 +: 8] = (a_i[i*8 +: 8] != 8'b0) ? 8'hFF : 8'h00;
        end
      end
      BOP_REV8: begin
        for (int i = 0; i < 8; i++) begin
          r[i*8 +: 8] = a_i[(7-i)*8 +: 8];
        end
      end
      BOP_CLMUL:  r = clp[63:0];
      BOP_CLMULH: r = clp[127:64];
      BOP_CLMULR: r = clp[126:63];
      BOP_BCLR: r = a_i & ~(64'b1 << b_i[5:0]);
      BOP_BEXT: r = {63'b0, a_i[b_i[5:0]]};
      BOP_BINV: r = a_i ^ (64'b1 << b_i[5:0]);
      BOP_BSET: r = a_i | (64'b1 << b_i[5:0]);
      BOP_CZEQZ: r = (b_i == 64'b0) ? 64'b0 : a_i;
      BOP_CZNEZ: r = (b_i != 64'b0) ? 64'b0 : a_i;
      BOP_PACK:  r = {b_i[31:0], a_i[31:0]};
      BOP_PACKH: r = {48'b0, b_i[7:0], a_i[7:0]};
      BOP_PACKW: begin
        w32 = {b_i[15:0], a_i[15:0]};
        r = {{32{w32[31]}}, w32};
      end
      BOP_BREV8: begin
        for (int i = 0; i < 8; i++) begin
          for (int j = 0; j < 8; j++) begin
            r[i*8+j] = a_i[i*8 + (7-j)];
          end
        end
      end
      BOP_XPERM4: begin
        for (int i = 0; i < 16; i++) begin
          r[i*4 +: 4] = a_i[b_i[i*4 +: 4]*4 +: 4];
        end
      end
      BOP_XPERM8: begin
        for (int i = 0; i < 8; i++) begin
          r[i*8 +: 8] = (b_i[i*8 +: 8] < 8'd8) ?
              a_i[b_i[i*8 +: 8]*8 +: 8] : 8'b0;
        end
      end
      BOP_AES_ES, BOP_AES_DS: r = sb_out;
      BOP_AES_ESM: r = {mixcol(sb_out[63:32]), mixcol(sb_out[31:0])};
      BOP_AES_DSM: r = {imixcol(sb_out[63:32]), imixcol(sb_out[31:0])};
      BOP_AES_IM: begin
        r = {imixcol(a_i[63:32]), imixcol(a_i[31:0])};
      end
      BOP_AES_KS1I: begin
        // SubWord(RotWord(w1)) ^ Rcon (byte 0), duplicated;
        // indices above 0xA are illegal at decode.
        w32 = sb_out[31:0] ^ {24'b0, aes_rcon(b_i[3:0])};
        r = {w32, w32};
      end
      BOP_AES_KS2: begin
        w32 = a_i[63:32] ^ b_i[31:0];
        r = {w32 ^ b_i[63:32], w32};
      end
      BOP_SHA256SIG0: begin
        w32 = a_i[31:0];
        r = {{32{1'b0}}, ror32(w32, 5'd7) ^ ror32(w32, 5'd18) ^
             (w32 >> 3)} & 64'hFFFF_FFFF;
        // (sign-extension fixed below)
        r = {{32{r[31]}}, r[31:0]};
      end
      BOP_SHA256SIG1: begin
        w32 = a_i[31:0];
        r = {{32{1'b0}}, ror32(w32, 5'd17) ^ ror32(w32, 5'd19) ^
             (w32 >> 10)};
        r = {{32{r[31]}}, r[31:0]};
      end
      BOP_SHA256SUM0: begin
        w32 = a_i[31:0];
        r = {{32{1'b0}}, ror32(w32, 5'd2) ^ ror32(w32, 5'd13) ^
             ror32(w32, 5'd22)};
        r = {{32{r[31]}}, r[31:0]};
      end
      BOP_SHA256SUM1: begin
        w32 = a_i[31:0];
        r = {{32{1'b0}}, ror32(w32, 5'd6) ^ ror32(w32, 5'd11) ^
             ror32(w32, 5'd25)};
        r = {{32{r[31]}}, r[31:0]};
      end
      BOP_SHA512SIG0:
        r = ror64(a_i, 6'd1) ^ ror64(a_i, 6'd8) ^ (a_i >> 7);
      BOP_SHA512SIG1:
        r = ror64(a_i, 6'd19) ^ ror64(a_i, 6'd61) ^ (a_i >> 6);
      BOP_SHA512SUM0:
        r = ror64(a_i, 6'd28) ^ ror64(a_i, 6'd34) ^ ror64(a_i, 6'd39);
      BOP_SHA512SUM1:
        r = ror64(a_i, 6'd14) ^ ror64(a_i, 6'd18) ^ ror64(a_i, 6'd41);
      default: r = 64'b0;
    endcase
    result_o = r;
  end

endmodule
