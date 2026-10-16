// Shared definitions for the L1 caches and the core memory
// interface (see docs/CORE.md "Memory interface").
`default_nettype none
package muserisc_cache_pkg;
  /* verilator lint_off UNUSEDPARAM */
  // Core data-port operations (dreq_op).
  localparam logic [1:0] DOP_LOAD  = 2'd0;  // read the aligned 64-bit word
  localparam logic [1:0] DOP_STORE = 2'd1;  // byte-masked write
  localparam logic [1:0] DOP_CLEAN = 2'd2;  // write back every dirty line (FENCE.I)
  /* verilator lint_on UNUSEDPARAM */

  // Physical-memory attribute: cacheable iff the cache is
  // enabled and the PA lies in one of two [base, base+size)
  // windows (size 0 disables a window). Everything else is
  // I/O: accessed uncached, one bus beat per access, in order.
  function automatic logic pma_cacheable(
      input logic [63:0] pa, input logic en,
      input logic [63:0] b0, input logic [63:0] s0,
      input logic [63:0] b1, input logic [63:0] s1);
    pma_cacheable = en &&
        (((s0 != 64'd0) && (pa >= b0) && ((pa - b0) < s0)) ||
         ((s1 != 64'd0) && (pa >= b1) && ((pa - b1) < s1)));
  endfunction
endpackage
`default_nettype wire
