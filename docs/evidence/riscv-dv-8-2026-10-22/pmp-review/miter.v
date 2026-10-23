// ok = 1 iff forms FA and FB agree; the wide check only for aligned
// 8-byte accesses (addr[2] = 0), as the core issues them.
module miter #(parameter integer FA = 1, parameter integer FB = 3, parameter integer WA = 2, parameter integer WB = 2) (
    input  [63:0] addr, input [1:0] acc, input [1:0] priv, input wide_i,
    input  [127:0] cfg_flat, input [863:0] paddr_flat, output ok);
  wire a, b;
  pmp_forms #(.FORM(FA), .WIDE(WA)) ua (.addr(addr), .acc(acc), .priv(priv), .wide_i(wide_i), .cfg_flat(cfg_flat), .paddr_flat(paddr_flat), .allow(a));
  pmp_forms #(.FORM(FB), .WIDE(WB)) ub (.addr(addr), .acc(acc), .priv(priv), .wide_i(wide_i), .cfg_flat(cfg_flat), .paddr_flat(paddr_flat), .allow(b));
  assign ok = (wide_i && addr[2]) ? 1'b1 : (a == b);
endmodule
