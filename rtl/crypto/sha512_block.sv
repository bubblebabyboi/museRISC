// museRISC SHA-512 block core (FIPS 180-4). One 1024-bit block per
// start pulse; padding by driver (or muse_hash_stream). Iterative
// 1 round/cycle x80. `cont`=0 starts from the FIPS IV; `cont`=1
// chains from the previous block's result (multi-block messages).
// The chaining value after reset is undefined: the first block of
// every message must use cont=0.
// K/H constants generated from prime cube/square roots (FIPS 180-4).
`default_nettype none
module sha512_block (
    input  wire          clk,
    input  wire          rst_n,
    input  wire          start,
    input  wire          cont,
    input  wire [1023:0] block_in,
    output logic [511:0] digest_out,
    output logic         busy,
    output logic         done
);
  logic [63:0] h [8];
  logic [63:0] w [80];
  logic [63:0] a, b, c, d, e, f, g, hh;
  logic [6:0]  round;

  function automatic logic [63:0] rotr(input logic [63:0] x,
                                       input logic [5:0] n);
    rotr = (x >> n) | (x << (64 - n));
  endfunction
  function automatic logic [63:0] ch(input logic [63:0] x,
                                     input logic [63:0] y,
                                     input logic [63:0] z);
    ch = (x & y) ^ (~x & z);
  endfunction
  function automatic logic [63:0] maj(input logic [63:0] x,
                                      input logic [63:0] y,
                                      input logic [63:0] z);
    maj = (x & y) ^ (x & z) ^ (y & z);
  endfunction
  function automatic logic [63:0] bsig0(input logic [63:0] x);
    bsig0 = rotr(x, 28) ^ rotr(x, 34) ^ rotr(x, 39);
  endfunction
  function automatic logic [63:0] bsig1(input logic [63:0] x);
    bsig1 = rotr(x, 14) ^ rotr(x, 18) ^ rotr(x, 41);
  endfunction
  function automatic logic [63:0] ssig0(input logic [63:0] x);
    ssig0 = rotr(x, 1) ^ rotr(x, 8) ^ (x >> 7);
  endfunction
  function automatic logic [63:0] ssig1(input logic [63:0] x);
    ssig1 = rotr(x, 19) ^ rotr(x, 61) ^ (x >> 6);
  endfunction
  function automatic logic [63:0] kconst(input logic [6:0] i);
    case (i)
      7'd0: kconst = 64'h428a2f98d728ae22;
      7'd1: kconst = 64'h7137449123ef65cd;
      7'd2: kconst = 64'hb5c0fbcfec4d3b2f;
      7'd3: kconst = 64'he9b5dba58189dbbc;
      7'd4: kconst = 64'h3956c25bf348b538;
      7'd5: kconst = 64'h59f111f1b605d019;
      7'd6: kconst = 64'h923f82a4af194f9b;
      7'd7: kconst = 64'hab1c5ed5da6d8118;
      7'd8: kconst = 64'hd807aa98a3030242;
      7'd9: kconst = 64'h12835b0145706fbe;
      7'd10: kconst = 64'h243185be4ee4b28c;
      7'd11: kconst = 64'h550c7dc3d5ffb4e2;
      7'd12: kconst = 64'h72be5d74f27b896f;
      7'd13: kconst = 64'h80deb1fe3b1696b1;
      7'd14: kconst = 64'h9bdc06a725c71235;
      7'd15: kconst = 64'hc19bf174cf692694;
      7'd16: kconst = 64'he49b69c19ef14ad2;
      7'd17: kconst = 64'hefbe4786384f25e3;
      7'd18: kconst = 64'h0fc19dc68b8cd5b5;
      7'd19: kconst = 64'h240ca1cc77ac9c65;
      7'd20: kconst = 64'h2de92c6f592b0275;
      7'd21: kconst = 64'h4a7484aa6ea6e483;
      7'd22: kconst = 64'h5cb0a9dcbd41fbd4;
      7'd23: kconst = 64'h76f988da831153b5;
      7'd24: kconst = 64'h983e5152ee66dfab;
      7'd25: kconst = 64'ha831c66d2db43210;
      7'd26: kconst = 64'hb00327c898fb213f;
      7'd27: kconst = 64'hbf597fc7beef0ee4;
      7'd28: kconst = 64'hc6e00bf33da88fc2;
      7'd29: kconst = 64'hd5a79147930aa725;
      7'd30: kconst = 64'h06ca6351e003826f;
      7'd31: kconst = 64'h142929670a0e6e70;
      7'd32: kconst = 64'h27b70a8546d22ffc;
      7'd33: kconst = 64'h2e1b21385c26c926;
      7'd34: kconst = 64'h4d2c6dfc5ac42aed;
      7'd35: kconst = 64'h53380d139d95b3df;
      7'd36: kconst = 64'h650a73548baf63de;
      7'd37: kconst = 64'h766a0abb3c77b2a8;
      7'd38: kconst = 64'h81c2c92e47edaee6;
      7'd39: kconst = 64'h92722c851482353b;
      7'd40: kconst = 64'ha2bfe8a14cf10364;
      7'd41: kconst = 64'ha81a664bbc423001;
      7'd42: kconst = 64'hc24b8b70d0f89791;
      7'd43: kconst = 64'hc76c51a30654be30;
      7'd44: kconst = 64'hd192e819d6ef5218;
      7'd45: kconst = 64'hd69906245565a910;
      7'd46: kconst = 64'hf40e35855771202a;
      7'd47: kconst = 64'h106aa07032bbd1b8;
      7'd48: kconst = 64'h19a4c116b8d2d0c8;
      7'd49: kconst = 64'h1e376c085141ab53;
      7'd50: kconst = 64'h2748774cdf8eeb99;
      7'd51: kconst = 64'h34b0bcb5e19b48a8;
      7'd52: kconst = 64'h391c0cb3c5c95a63;
      7'd53: kconst = 64'h4ed8aa4ae3418acb;
      7'd54: kconst = 64'h5b9cca4f7763e373;
      7'd55: kconst = 64'h682e6ff3d6b2b8a3;
      7'd56: kconst = 64'h748f82ee5defb2fc;
      7'd57: kconst = 64'h78a5636f43172f60;
      7'd58: kconst = 64'h84c87814a1f0ab72;
      7'd59: kconst = 64'h8cc702081a6439ec;
      7'd60: kconst = 64'h90befffa23631e28;
      7'd61: kconst = 64'ha4506cebde82bde9;
      7'd62: kconst = 64'hbef9a3f7b2c67915;
      7'd63: kconst = 64'hc67178f2e372532b;
      7'd64: kconst = 64'hca273eceea26619c;
      7'd65: kconst = 64'hd186b8c721c0c207;
      7'd66: kconst = 64'heada7dd6cde0eb1e;
      7'd67: kconst = 64'hf57d4f7fee6ed178;
      7'd68: kconst = 64'h06f067aa72176fba;
      7'd69: kconst = 64'h0a637dc5a2c898a6;
      7'd70: kconst = 64'h113f9804bef90dae;
      7'd71: kconst = 64'h1b710b35131c471b;
      7'd72: kconst = 64'h28db77f523047d84;
      7'd73: kconst = 64'h32caab7b40c72493;
      7'd74: kconst = 64'h3c9ebe0a15c9bebc;
      7'd75: kconst = 64'h431d67c49c100d4c;
      7'd76: kconst = 64'h4cc5d4becb3e42b6;
      7'd77: kconst = 64'h597f299cfc657e2a;
      7'd78: kconst = 64'h5fcb6fab3ad6faec;
      default: kconst = 64'h6c44198c4a475817;
    endcase
  endfunction

  logic [63:0] w_exp, w_cur, t1, t2;
  assign w_exp = ssig1(w[round - 7'd2]) + w[round - 7'd7] +
                 ssig0(w[round - 7'd15]) + w[round - 7'd16];
  assign w_cur = (round < 7'd16) ? w[round] : w_exp;
  assign t1 = hh + bsig1(e) + ch(e, f, g) + kconst(round) + w_cur;
  assign t2 = bsig0(a) + maj(a, b, c);

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      busy <= 1'b0; done <= 1'b0; digest_out <= '0; round <= '0;
    end else if (start && !busy) begin
      busy <= 1'b1; done <= 1'b0; round <= '0;
      if (!cont) begin
        h[0] <= 64'h6a09e667f3bcc908;
        h[1] <= 64'hbb67ae8584caa73b;
        h[2] <= 64'h3c6ef372fe94f82b;
        h[3] <= 64'ha54ff53a5f1d36f1;
        h[4] <= 64'h510e527fade682d1;
        h[5] <= 64'h9b05688c2b3e6c1f;
        h[6] <= 64'h1f83d9abfb41bd6b;
        h[7] <= 64'h5be0cd19137e2179;
        a <= 64'h6a09e667f3bcc908;
        b <= 64'hbb67ae8584caa73b;
        c <= 64'h3c6ef372fe94f82b;
        d <= 64'ha54ff53a5f1d36f1;
        e <= 64'h510e527fade682d1;
        f <= 64'h9b05688c2b3e6c1f;
        g <= 64'h1f83d9abfb41bd6b;
        hh <= 64'h5be0cd19137e2179;
      end else begin
        a <= h[0]; b <= h[1]; c <= h[2]; d <= h[3];
        e <= h[4]; f <= h[5]; g <= h[6]; hh <= h[7];
      end
      for (int i = 0; i < 16; i++) begin
        w[i] <= block_in[1023 - 64 * i -: 64];
      end
    end else if (busy) begin
      if (round >= 7'd16) w[round] <= w_exp;
      hh <= g; g <= f; f <= e; e <= d + t1;
      d <= c; c <= b; b <= a; a <= t1 + t2;
      if (round == 7'd79) begin
        busy <= 1'b0; done <= 1'b1;
        digest_out <= {h[0] + (t1 + t2), h[1] + a, h[2] + b,
                       h[3] + c, h[4] + (d + t1), h[5] + e,
                       h[6] + f, h[7] + g};
        h[0] <= h[0] + (t1 + t2); h[1] <= h[1] + a;
        h[2] <= h[2] + b;         h[3] <= h[3] + c;
        h[4] <= h[4] + (d + t1);  h[5] <= h[5] + e;
        h[6] <= h[6] + f;         h[7] <= h[7] + g;
      end
      round <= round + 7'd1;
    end else begin
      done <= 1'b0;
    end
  end
endmodule
`default_nettype wire
