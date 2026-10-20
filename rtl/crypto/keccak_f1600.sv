// Sigil Keccak-f1600 permutation (FIPS 202). 24 rounds, 1 round/cycle.
// State lane (x,y) is state[64*(5*y+x) +: 64], little-endian lanes as in
// the Keccak reference. Sponge (rate/padding) is handled by the driver.
`default_nettype none
module keccak_f1600 (
    input  wire          clk,
    input  wire          rst_n,
    input  wire          start,
    input  wire [1599:0] state_in,
    output logic [1599:0] state_out,
    output logic         busy,
    output logic         done
);
  logic [1599:0] st;
  logic [4:0]    round;

  function automatic logic [63:0] rotl(input logic [63:0] x,
                                       input logic [5:0] n);
    rotl = (n == 6'd0) ? x : ((x << n) | (x >> (64 - n)));
  endfunction

  function automatic logic [5:0] rho(input logic [2:0] x,
                                     input logic [2:0] y);
    case ({y, x})
      6'b000_000: rho = 6'd0;
      6'b000_001: rho = 6'd1;
      6'b000_010: rho = 6'd62;
      6'b000_011: rho = 6'd28;
      6'b000_100: rho = 6'd27;
      6'b001_000: rho = 6'd36;
      6'b001_001: rho = 6'd44;
      6'b001_010: rho = 6'd6;
      6'b001_011: rho = 6'd55;
      6'b001_100: rho = 6'd20;
      6'b010_000: rho = 6'd3;
      6'b010_001: rho = 6'd10;
      6'b010_010: rho = 6'd43;
      6'b010_011: rho = 6'd25;
      6'b010_100: rho = 6'd39;
      6'b011_000: rho = 6'd41;
      6'b011_001: rho = 6'd45;
      6'b011_010: rho = 6'd15;
      6'b011_011: rho = 6'd21;
      6'b011_100: rho = 6'd8;
      6'b100_000: rho = 6'd18;
      6'b100_001: rho = 6'd2;
      6'b100_010: rho = 6'd61;
      6'b100_011: rho = 6'd56;
      default:    rho = 6'd14;
    endcase
  endfunction

  function automatic logic [63:0] rc(input logic [4:0] i);
    case (i)
      5'd0: rc = 64'h0000000000000001;
      5'd1: rc = 64'h0000000000008082;
      5'd2: rc = 64'h800000000000808a;
      5'd3: rc = 64'h8000000080008000;
      5'd4: rc = 64'h000000000000808b;
      5'd5: rc = 64'h0000000080000001;
      5'd6: rc = 64'h8000000080008081;
      5'd7: rc = 64'h8000000000008009;
      5'd8: rc = 64'h000000000000008a;
      5'd9: rc = 64'h0000000000000088;
      5'd10: rc = 64'h0000000080008009;
      5'd11: rc = 64'h000000008000000a;
      5'd12: rc = 64'h000000008000808b;
      5'd13: rc = 64'h800000000000008b;
      5'd14: rc = 64'h8000000000008089;
      5'd15: rc = 64'h8000000000008003;
      5'd16: rc = 64'h8000000000008002;
      5'd17: rc = 64'h8000000000000080;
      5'd18: rc = 64'h000000000000800a;
      5'd19: rc = 64'h800000008000000a;
      5'd20: rc = 64'h8000000080008081;
      5'd21: rc = 64'h8000000000008080;
      5'd22: rc = 64'h0000000080000001;
      default: rc = 64'h8000000080008008;
    endcase
  endfunction

  // One Keccak round, combinational over `st` and `round`.
  logic [63:0] a_lane [25];
  logic [63:0] b_lane [25];
  logic [63:0] cc [5];
  logic [63:0] dd [5];
  logic [1599:0] nxt;
  always_comb begin
    for (int y = 0; y < 5; y++) begin
      for (int x = 0; x < 5; x++) begin
        a_lane[5 * y + x] = st[64 * (5 * y + x) +: 64];
      end
    end
    for (int x = 0; x < 5; x++) begin
      cc[x] = a_lane[x] ^ a_lane[5 + x] ^ a_lane[10 + x] ^
              a_lane[15 + x] ^ a_lane[20 + x];
    end
    for (int x = 0; x < 5; x++) begin
      dd[x] = cc[(x + 4) % 5] ^ rotl(cc[(x + 1) % 5], 6'd1);
    end
    for (int y = 0; y < 5; y++) begin
      for (int x = 0; x < 5; x++) begin
        a_lane[5 * y + x] = a_lane[5 * y + x] ^ dd[x];
        b_lane[5 * ((2 * x + 3 * y) % 5) + y] =
            rotl(a_lane[5 * y + x], rho(x[2:0], y[2:0]));
      end
    end
    for (int y = 0; y < 5; y++) begin
      for (int x = 0; x < 5; x++) begin
        a_lane[5 * y + x] = b_lane[5 * y + x] ^
            ((~b_lane[5 * y + ((x + 1) % 5)]) &
             b_lane[5 * y + ((x + 2) % 5)]);
      end
    end
    a_lane[0] = a_lane[0] ^ rc(round);
    for (int y = 0; y < 5; y++) begin
      for (int x = 0; x < 5; x++) begin
        nxt[64 * (5 * y + x) +: 64] = a_lane[5 * y + x];
      end
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      busy <= 1'b0; done <= 1'b0; state_out <= '0;
      st <= '0; round <= '0;
    end else if (start && !busy) begin
      busy <= 1'b1; done <= 1'b0; st <= state_in; round <= '0;
    end else if (busy) begin
      st <= nxt;
      if (round == 5'd23) begin
        busy <= 1'b0; done <= 1'b1; state_out <= nxt;
      end
      round <= round + 5'd1;
    end else begin
      done <= 1'b0;
    end
  end
endmodule
`default_nettype wire
