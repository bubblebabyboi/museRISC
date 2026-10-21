// Shared definitions for the L1 caches and the core memory
// interface (see docs/CORE.md "Memory interface").
`default_nettype none
package sigil_cache_pkg;
  // Registered SRAM read outputs (W7.1, docs/SOC_AREA.md). With
  // SRAM_OREG set, every SRAM read (L1 data/tag ways in
  // sigil_sram_sp, VRF ports in sigil_vregfile) takes one more cycle:
  // the read data is captured in a rising-edge register straight
  // after the array, so no path launches from a macro output (the
  // sky130 OpenRAM macros drive dout from the falling edge) into
  // logic. The consumers (caches, vector unit, vector load/store
  // sequencer) add the matching wait cycle. On for the sky130 macro
  // build (SIGIL_SRAM_SKY130); SIGIL_SRAM_OREG turns it on for any
  // other build (simulation of the sky130 latency on behavioural
  // arrays). Off otherwise: it costs a cycle per I$ fetch, D$ hit and
  // VRF read, which nangate45 / FPGA do not need.
`ifdef SIGIL_SRAM_SKY130
  localparam bit SRAM_OREG = 1'b1;
`elsif SIGIL_SRAM_OREG
  localparam bit SRAM_OREG = 1'b1;
`else
  localparam bit SRAM_OREG = 1'b0;
`endif
  // Registered VRF read outputs only (vector register file ports in
  // sigil_vregfile, the vector unit's R stage and the vector LS
  // sequencer's VLS_RW cycle). Implied by SRAM_OREG; SIGIL_VRF_OREG
  // turns it on alone for the FPGA build (#53), where the VRF BRAM read
  // feeding the vector datapath is the worst path but the caches do not
  // need the extra cycle (+0.37% on the vector TB vs +35-47% with the
  // cache registers too).
`ifdef SIGIL_VRF_OREG
  localparam bit VRF_OREG = 1'b1;
`else
  localparam bit VRF_OREG = SRAM_OREG;
`endif
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
