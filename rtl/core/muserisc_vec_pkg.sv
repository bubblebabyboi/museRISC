// museRISC in-house core: element helpers for muserisc_vec
// (issue #27; rounding/saturation restructured for logic
// depth in the element-serial rework, same results).
`default_nettype none
package muserisc_vec_pkg;

  // Element extraction at width code w (width = 8<<w, w<=3).
  function automatic logic [63:0] get_el(
      input logic [4095:0] grp, input int idx, input logic [2:0] w);
    logic [11:0] base;
    base = 12'(idx << (w + 3));
    unique case (w)
      3'd0: get_el = {56'd0, grp[base +: 8]};
      3'd1: get_el = {48'd0, grp[base +: 16]};
      3'd2: get_el = {32'd0, grp[base +: 32]};
      default: get_el = grp[base +: 64];
    endcase
  endfunction

  function automatic logic [63:0] sext_el(
      input logic [63:0] v, input logic [2:0] w);
    unique case (w)
      3'd0: sext_el = {{56{v[7]}}, v[7:0]};
      3'd1: sext_el = {{48{v[15]}}, v[15:0]};
      3'd2: sext_el = {{32{v[31]}}, v[31:0]};
      default: sext_el = v;
    endcase
  endfunction

  function automatic logic [4095:0] put_el(
      input logic [4095:0] grp, input int idx, input logic [2:0] w,
      input logic [63:0] v);
    put_el = grp;
    unique case (w)
      3'd0: put_el[idx*8 +: 8] = v[7:0];
      3'd1: put_el[idx*16 +: 16] = v[15:0];
      3'd2: put_el[idx*32 +: 32] = v[31:0];
      default: put_el[idx*64 +: 64] = v;
    endcase
  endfunction

  // Rounding shift-right of a 128-bit value by s (fixed-point
  // vxrm rules): 00 rnu, 01 rne, 10 rdn (truncate), 11 rod.
  // The rounding increment is formed from bit s-1 and an
  // OR-reduction of the discarded bits (no wide compare), so
  // the only carry chain is the final increment.
  /* verilator lint_off UNUSEDSIGNAL */  // s is < 128
  function automatic logic [127:0] rnd_shift(
      input logic [127:0] v, input int s, input logic arith,
      input logic [1:0] rm);
    logic [127:0] q, below, below1;
    logic [6:0] sh;
    logic bd1, rest_nz, disc_nz, inc;
    sh = s[6:0];
    q = arith ? 128'(signed'(v) >>> sh) : (v >> sh);
    below = ~({128{1'b1}} << sh);   // discarded bits [s-1:0]
    below1 = below >> 1;            // bits [s-2:0]
    disc_nz = |(v & below);
    rest_nz = |(v & below1);
    bd1 = |(v & below & ~below1);   // bit s-1 (0 when s = 0)
    inc = 1'b0;
    unique case (rm)
      2'b00: inc = bd1;
      2'b01: inc = bd1 && (rest_nz || q[0]);
      2'b11: q[0] = q[0] | disc_nz;
      default: ;
    endcase
    rnd_shift = q + {127'd0, inc};
  endfunction
  /* verilator lint_on UNUSEDSIGNAL */

  // Saturating clamp to a signed width-2^w range: overflow
  // iff bits [127:SEW-1] are not a sign extension.
  function automatic logic [63:0] sat_s(
      input logic signed [127:0] v, input logic [2:0] w,
      output logic sat);
    logic [127:0] top_m;
    logic [63:0] hi, lo;
    unique case (w)
      3'd0: begin
        top_m = ~128'h7f; hi = 64'h7f; lo = 64'hffff_ffff_ffff_ff80;
      end
      3'd1: begin
        top_m = ~128'h7fff; hi = 64'h7fff; lo = 64'hffff_ffff_ffff_8000;
      end
      3'd2: begin
        top_m = ~128'h7fff_ffff; hi = 64'h7fff_ffff;
        lo = 64'hffff_ffff_8000_0000;
      end
      default: begin
        top_m = ~128'h7fff_ffff_ffff_ffff; hi = 64'h7fff_ffff_ffff_ffff;
        lo = 64'h8000_0000_0000_0000;
      end
    endcase
    sat = ((v & top_m) != 128'd0) && ((v & top_m) != top_m);
    sat_s = !sat ? v[63:0] : (v[127] ? lo : hi);
  endfunction

  // Saturating clamp to an unsigned width-2^w range.
  function automatic logic [63:0] sat_u(
      input logic [127:0] v, input logic [2:0] w,
      output logic sat);
    logic [127:0] top_m;
    logic [63:0] hi;
    unique case (w)
      3'd0: begin top_m = ~128'hff; hi = 64'hff; end
      3'd1: begin top_m = ~128'hffff; hi = 64'hffff; end
      3'd2: begin top_m = ~128'hffff_ffff; hi = 64'hffff_ffff; end
      default: begin
        top_m = ~128'hffff_ffff_ffff_ffff; hi = 64'hffff_ffff_ffff_ffff;
      end
    endcase
    sat = (v & top_m) != 128'd0;
    sat_u = sat ? hi : v[63:0];
  endfunction

endpackage
`default_nettype wire
