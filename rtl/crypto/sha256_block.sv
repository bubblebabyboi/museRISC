// Sigil SHA-256 single-block core (FIPS 180-4).
// One 512-bit block per start pulse; message padding is done by the
// driver. Iterative: 1 round/cycle, 64 cycles per block. Synthesizable.
`default_nettype none
module sha256_block (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         start,
    input  wire [511:0] block_in,
    output logic [255:0] digest_out,
    output logic        busy,
    output logic        done
);
  logic [31:0] h [8];
  logic [31:0] w [64];
  logic [31:0] a, b, c, d, e, f, g, hh;
  logic [6:0]  round;

  function automatic logic [31:0] rotr(input logic [31:0] x,
                                       input logic [4:0] n);
    rotr = (x >> n) | (x << (32 - n));
  endfunction
  function automatic logic [31:0] ch(input logic [31:0] x,
                                     input logic [31:0] y,
                                     input logic [31:0] z);
    ch = (x & y) ^ (~x & z);
  endfunction
  function automatic logic [31:0] maj(input logic [31:0] x,
                                      input logic [31:0] y,
                                      input logic [31:0] z);
    maj = (x & y) ^ (x & z) ^ (y & z);
  endfunction
  function automatic logic [31:0] bsig0(input logic [31:0] x);
    bsig0 = rotr(x, 2) ^ rotr(x, 13) ^ rotr(x, 22);
  endfunction
  function automatic logic [31:0] bsig1(input logic [31:0] x);
    bsig1 = rotr(x, 6) ^ rotr(x, 11) ^ rotr(x, 25);
  endfunction
  function automatic logic [31:0] ssig0(input logic [31:0] x);
    ssig0 = rotr(x, 7) ^ rotr(x, 18) ^ (x >> 3);
  endfunction
  function automatic logic [31:0] ssig1(input logic [31:0] x);
    ssig1 = rotr(x, 17) ^ rotr(x, 19) ^ (x >> 10);
  endfunction
  function automatic logic [31:0] kconst(input logic [5:0] i);
    case (i)
      6'd0: kconst = 32'h428a2f98; 6'd1: kconst = 32'h71374491;
      6'd2: kconst = 32'hb5c0fbcf; 6'd3: kconst = 32'he9b5dba5;
      6'd4: kconst = 32'h3956c25b; 6'd5: kconst = 32'h59f111f1;
      6'd6: kconst = 32'h923f82a4; 6'd7: kconst = 32'hab1c5ed5;
      6'd8: kconst = 32'hd807aa98; 6'd9: kconst = 32'h12835b01;
      6'd10: kconst = 32'h243185be; 6'd11: kconst = 32'h550c7dc3;
      6'd12: kconst = 32'h72be5d74; 6'd13: kconst = 32'h80deb1fe;
      6'd14: kconst = 32'h9bdc06a7; 6'd15: kconst = 32'hc19bf174;
      6'd16: kconst = 32'he49b69c1; 6'd17: kconst = 32'hefbe4786;
      6'd18: kconst = 32'h0fc19dc6; 6'd19: kconst = 32'h240ca1cc;
      6'd20: kconst = 32'h2de92c6f; 6'd21: kconst = 32'h4a7484aa;
      6'd22: kconst = 32'h5cb0a9dc; 6'd23: kconst = 32'h76f988da;
      6'd24: kconst = 32'h983e5152; 6'd25: kconst = 32'ha831c66d;
      6'd26: kconst = 32'hb00327c8; 6'd27: kconst = 32'hbf597fc7;
      6'd28: kconst = 32'hc6e00bf3; 6'd29: kconst = 32'hd5a79147;
      6'd30: kconst = 32'h06ca6351; 6'd31: kconst = 32'h14292967;
      6'd32: kconst = 32'h27b70a85; 6'd33: kconst = 32'h2e1b2138;
      6'd34: kconst = 32'h4d2c6dfc; 6'd35: kconst = 32'h53380d13;
      6'd36: kconst = 32'h650a7354; 6'd37: kconst = 32'h766a0abb;
      6'd38: kconst = 32'h81c2c92e; 6'd39: kconst = 32'h92722c85;
      6'd40: kconst = 32'ha2bfe8a1; 6'd41: kconst = 32'ha81a664b;
      6'd42: kconst = 32'hc24b8b70; 6'd43: kconst = 32'hc76c51a3;
      6'd44: kconst = 32'hd192e819; 6'd45: kconst = 32'hd6990624;
      6'd46: kconst = 32'hf40e3585; 6'd47: kconst = 32'h106aa070;
      6'd48: kconst = 32'h19a4c116; 6'd49: kconst = 32'h1e376c08;
      6'd50: kconst = 32'h2748774c; 6'd51: kconst = 32'h34b0bcb5;
      6'd52: kconst = 32'h391c0cb3; 6'd53: kconst = 32'h4ed8aa4a;
      6'd54: kconst = 32'h5b9cca4f; 6'd55: kconst = 32'h682e6ff3;
      6'd56: kconst = 32'h748f82ee; 6'd57: kconst = 32'h78a5636f;
      6'd58: kconst = 32'h84c87814; 6'd59: kconst = 32'h8cc70208;
      6'd60: kconst = 32'h90befffa; 6'd61: kconst = 32'ha4506ceb;
      6'd62: kconst = 32'hbef9a3f7; default: kconst = 32'hc67178f2;
    endcase
  endfunction

  logic [5:0]  ridx;
  logic [31:0] w_exp, w_cur, t1, t2;
  assign ridx = round[5:0];
  assign w_exp = ssig1(w[(ridx - 6'd2) & 6'd63]) +
                 w[(ridx - 6'd7) & 6'd63] +
                 ssig0(w[(ridx - 6'd15) & 6'd63]) +
                 w[(ridx - 6'd16) & 6'd63];
  assign w_cur = (round < 7'd16) ? w[ridx] : w_exp;
  assign t1 = hh + bsig1(e) + ch(e, f, g) + kconst(ridx) + w_cur;
  assign t2 = bsig0(a) + maj(a, b, c);

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      busy <= 1'b0; done <= 1'b0; digest_out <= '0; round <= '0;
    end else if (start && !busy) begin
      busy <= 1'b1; done <= 1'b0; round <= '0;
      h[0] <= 32'h6a09e667; h[1] <= 32'hbb67ae85;
      h[2] <= 32'h3c6ef372; h[3] <= 32'ha54ff53a;
      h[4] <= 32'h510e527f; h[5] <= 32'h9b05688c;
      h[6] <= 32'h1f83d9ab; h[7] <= 32'h5be0cd19;
      a <= 32'h6a09e667; b <= 32'hbb67ae85; c <= 32'h3c6ef372;
      d <= 32'ha54ff53a; e <= 32'h510e527f; f <= 32'h9b05688c;
      g <= 32'h1f83d9ab; hh <= 32'h5be0cd19;
      for (int i = 0; i < 16; i++) begin
        w[i] <= block_in[511 - 32 * i -: 32];
      end
    end else if (busy) begin
      if (round >= 7'd16) begin
        w[ridx] <= w_exp;  // store for use by later rounds
      end
      hh <= g; g <= f; f <= e; e <= d + t1;
      d <= c; c <= b; b <= a; a <= t1 + t2;
      if (round == 7'd63) begin
        busy <= 1'b0; done <= 1'b1;
        digest_out <= {h[0] + (t1 + t2), h[1] + a, h[2] + b,
                       h[3] + c, h[4] + (d + t1), h[5] + e,
                       h[6] + f, h[7] + g};
      end
      round <= round + 7'd1;
    end else begin
      done <= 1'b0;
    end
  end
endmodule
`default_nettype wire
