// Single-port synchronous SRAM model (L1 cache arrays).
//
// One access per cycle: with en_i high the word at addr_i is
// read (rdata_o valid the following cycle, held until the next
// enabled read) or, with any we_i lane set, written under the
// per-lane write mask. A write cycle does not update rdata_o
// (no read-during-write forwarding is assumed by the caches).
// This is the behavior of a standard single-port SRAM macro or
// an FPGA BRAM in NO_CHANGE mode, so a technology flow swaps
// this module for a macro wrapper of the same name/ports; the
// behavioral body below is what Verilator simulates.
`default_nettype none
module muserisc_sram_sp #(
    parameter int unsigned WIDTH = 64,
    parameter int unsigned DEPTH = 64,
    parameter int unsigned LANES = 8,   // write-mask lanes (WIDTH % LANES == 0)
    localparam int unsigned AW = (DEPTH > 1) ? $clog2(DEPTH) : 1
) (
    input  wire              clk_i,
    input  wire              en_i,
    input  wire [LANES-1:0]  we_i,
    input  wire [AW-1:0]     addr_i,
    input  wire [WIDTH-1:0]  wdata_i,
    output logic [WIDTH-1:0] rdata_o
);
  localparam int unsigned LW = WIDTH / LANES;
  logic [WIDTH-1:0] mem_q [DEPTH];

  always_ff @(posedge clk_i) begin
    if (en_i) begin
      if (|we_i) begin
        for (int l = 0; l < int'(LANES); l++) begin
          if (we_i[l]) mem_q[addr_i][l*LW +: LW] <= wdata_i[l*LW +: LW];
        end
      end else begin
        rdata_o <= mem_q[addr_i];
      end
    end
  end
endmodule
`default_nettype wire
