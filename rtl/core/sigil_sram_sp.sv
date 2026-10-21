// Single-port synchronous SRAM model (L1 cache arrays).
//
// One access per cycle: with en_i high the word at addr_i is
// read or, with any we_i lane set, written under the per-lane
// write mask. Read data is valid LAT = 1 + SRAM_OREG cycles after
// the read (sigil_cache_pkg::SRAM_OREG) and is then held until the
// next read's data replaces it; reads may issue every cycle
// (pipelined). A write cycle does not update rdata_o (no
// read-during-write forwarding is assumed by the caches). With
// LAT = 1 this is a standard single-port SRAM macro or an FPGA
// BRAM in NO_CHANGE mode; LAT = 2 adds an output register (FPGA:
// the BRAM output register). By default the simulation uses the
// behavioural body below.
//
// ASIC flows: SIGIL_SRAM_FAKERAM45 (nangate45) and
// SIGIL_SRAM_SKY130 (sky130hd), set by the ORFS configs, map the
// two L1 geometries to macros; any other geometry stays behavioural.
//   512x64, 8 lanes (data way): fakeram45_512x64 (stock, 1RW, bit
//     mask) / sky130_sram_1rw1r_128x256_8 used as 256x128 with a
//     half select (port 0 RW; port 1 unused).
//   64x44, 1 lane (tag way): fakeram45_64x44 (generated 1RW view,
//     flow/designs/nangate45/sigil_soc/sram) /
//     sky130_sram_1rw1r_44x64_8 (port 0 RW; port 1 unused).
// The macros do not hold read data (fakeram: X after a non-read
// edge; OpenRAM: X after every rising edge, valid from the falling
// edge). LAT = 1: a capture register restores the
// hold-until-next-read contract, rdata_o = rd_q ? macro : hold_q.
// LAT = 2 (always on sky130): the macro output is captured in the
// cycle after the read and rdata_o is that register, so the only
// logic after the macro is the capture (and half-select) mux and
// nothing launches from the falling-edge macro output.
`default_nettype none
module sigil_sram_sp import sigil_cache_pkg::SRAM_OREG; #(
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
`ifdef SIGIL_SRAM_FAKERAM45
  localparam bit IS_DATA = (WIDTH == 64) && (DEPTH == 512) && (LANES == 8);
  localparam bit IS_TAG  = (WIDTH == 44) && (DEPTH == 64) && (LANES == 1);
`elsif SIGIL_SRAM_SKY130
  localparam bit IS_DATA = (WIDTH == 64) && (DEPTH == 512) && (LANES == 8);
  localparam bit IS_TAG  = (WIDTH == 44) && (DEPTH == 64) && (LANES == 1);
`else
  localparam bit IS_DATA = 1'b0;
  localparam bit IS_TAG  = 1'b0;
`endif

  if (IS_DATA || IS_TAG) begin : g_macro
    logic             rd;
    logic [WIDTH-1:0] mac_rd, hold_q;
    logic             rd_q;
    assign rd = en_i && !(|we_i);
    always_ff @(posedge clk_i) begin
      rd_q <= rd;
      if (rd_q) hold_q <= mac_rd;
    end
    // SRAM_OREG: hold_q is the output register (valid the cycle
    // after the capture); otherwise the macro output is forwarded in
    // the capture cycle.
    assign rdata_o = (rd_q && !SRAM_OREG) ? mac_rd : hold_q;
`ifdef SIGIL_SRAM_FAKERAM45
    // fakeram45 takes a per-bit write mask.
    logic [WIDTH-1:0] wmask;
    for (genvar l = 0; l < int'(LANES); l++) begin : g_wm
      assign wmask[l*LW +: LW] = {LW{we_i[l]}};
    end
    if (IS_DATA) begin : g_data
      fakeram45_512x64 u_ram (
          .clk       (clk_i),
          .ce_in     (en_i),
          .we_in     (|we_i),
          .addr_in   (addr_i[8:0]),
          .wd_in     (wdata_i),
          .w_mask_in (wmask),
          .rd_out    (mac_rd)
      );
    end else begin : g_tag
      fakeram45_64x44 u_ram (
          .clk       (clk_i),
          .ce_in     (en_i),
          .we_in     (|we_i),
          .addr_in   (addr_i[5:0]),
          .wd_in     (wdata_i),
          .w_mask_in (wmask),
          .rd_out    (mac_rd)
      );
    end
`elsif SIGIL_SRAM_SKY130
    if (IS_DATA) begin : g_data
      // 512x64 stored as 256x128: addr[0] picks the 64-bit half
      // (byte-mask lanes 8..15 = upper half). The read half select
      // is registered with the read.
      logic         half_q;
      logic [127:0] dout0;
      /* verilator lint_off UNUSEDSIGNAL */
      logic [127:0] unused_dout1;
      /* verilator lint_on UNUSEDSIGNAL */
      always_ff @(posedge clk_i) begin
        if (rd) half_q <= addr_i[0];
      end
      assign mac_rd = half_q ? dout0[127:64] : dout0[63:0];
      sky130_sram_1rw1r_128x256_8 u_ram (
          .clk0   (clk_i),
          .csb0   (~en_i),
          .web0   (~(|we_i)),
          .wmask0 (addr_i[0] ? {we_i[7:0], 8'h00} : {8'h00, we_i[7:0]}),
          .addr0  (addr_i[8:1]),
          .din0   ({wdata_i, wdata_i}),
          .dout0  (dout0),
          .clk1   (clk_i),
          .csb1   (1'b1),
          .addr1  (8'h00),
          .dout1  (unused_dout1)
      );
    end else begin : g_tag
      /* verilator lint_off UNUSEDSIGNAL */
      logic [43:0] unused_dout1;
      /* verilator lint_on UNUSEDSIGNAL */
      sky130_sram_1rw1r_44x64_8 u_ram (
          .clk0   (clk_i),
          .csb0   (~en_i),
          .web0   (~we_i[0]),
          .wmask0 (6'h3f),
          .addr0  (addr_i[5:0]),
          .din0   (wdata_i),
          .dout0  (mac_rd),
          .clk1   (clk_i),
          .csb1   (1'b1),
          .addr1  (6'h00),
          .dout1  (unused_dout1)
      );
    end
`endif
  end else begin : g_behav
    logic [WIDTH-1:0] mem_q [DEPTH];
    logic [WIDTH-1:0] rd_q;
    always_ff @(posedge clk_i) begin
      if (en_i) begin
        if (|we_i) begin
          for (int l = 0; l < int'(LANES); l++) begin
            if (we_i[l]) mem_q[addr_i][l*LW +: LW] <= wdata_i[l*LW +: LW];
          end
        end else begin
          rd_q <= mem_q[addr_i];
        end
      end
    end
    if (SRAM_OREG) begin : g_oreg
      logic rv_q;
      always_ff @(posedge clk_i) begin
        rv_q <= en_i && !(|we_i);
        if (rv_q) rdata_o <= rd_q;
      end
    end else begin : g_noreg
      assign rdata_o = rd_q;
    end
  end
endmodule
`default_nettype wire
