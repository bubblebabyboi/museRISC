// Vector register file (issue #23; element-serial rework).
// 32 registers of VLEN=512 bits stored as 256 words of 64
// bits (word address = {reg[4:0], word[2:0]}; element 0 is
// the lowest bits of word 0 of the first register).
//
// Storage is three identical 1R1W replicas of a 256x64 RAM
// with byte-write enables and a *synchronous* read (address
// sampled on the clock edge when re is high; the output
// register holds while re is low). One replica serves each
// read port (A = vs2/index, B = vs1, C = old vd/store data),
// and every write goes to all three. Each replica maps
// directly to a simple-dual-port BRAM (512x72 SDP) or a
// LUTRAM on FPGA, or a 1R1W byte-masked SRAM macro on ASIC.
//
// Read-during-write to the same word is resolved here by a
// one-cycle write bypass (write-first semantics), so the
// replicas' own collision behavior never matters.
//
// Consumer contract: read data is valid the cycle after re
// and is then held while re stays low, but a held word does
// NOT reflect writes that land after it was sampled. A
// consumer may hold read data across a write only if that
// write cannot touch bytes it still uses (true for the
// vector unit's in-order element pipeline and the MEM
// sequencer's RD/ACC phases; see docs/CORE.md).
//
// v0 is additionally mirrored in a 512-bit shadow so the
// mask bit of any element is available without a read port.
`default_nettype none
module muserisc_vrf_bank (
    input  wire        clk_i,
    input  wire        re_i,
    input  wire [7:0]  raddr_i,
    output logic [63:0] rdata_o,
    input  wire        we_i,
    input  wire [7:0]  waddr_i,
    input  wire [7:0]  wbe_i,
    input  wire [63:0] wdata_i
);
  logic [63:0] mem_q [256];
  always_ff @(posedge clk_i) begin
    if (we_i) begin
      for (int b = 0; b < 8; b++) begin
        if (wbe_i[b]) mem_q[waddr_i][b*8 +: 8] <= wdata_i[b*8 +: 8];
      end
    end
    if (re_i) rdata_o <= mem_q[raddr_i];
  end
endmodule

module muserisc_vregfile (
    input  wire        clk_i,
    // rst is unnecessary: vector registers are uninitialized
    // architecturally (tests write before reading).

    input  wire        re_a_i,
    input  wire [7:0]  raddr_a_i,
    output logic [63:0] rdata_a_o,
    input  wire        re_b_i,
    input  wire [7:0]  raddr_b_i,
    output logic [63:0] rdata_b_o,
    input  wire        re_c_i,
    input  wire [7:0]  raddr_c_i,
    output logic [63:0] rdata_c_o,
    output logic [511:0] v0_o,      // mask register shadow

    input  wire        we_i,
    input  wire [7:0]  waddr_i,
    input  wire [7:0]  wbe_i,       // byte enables
    input  wire [63:0] wdata_i
);

  logic [2:0]  re;
  logic [7:0]  raddr [3];
  logic [63:0] ram_q [3];
  assign re = {re_c_i, re_b_i, re_a_i};
  assign raddr[0] = raddr_a_i;
  assign raddr[1] = raddr_b_i;
  assign raddr[2] = raddr_c_i;

  // Write bypass state per port: the bytes written in the
  // same cycle a port sampled that address.
  logic [2:0]  byp_q;
  logic [7:0]  byp_be_q [3];
  logic [63:0] byp_data_q [3];
  logic [63:0] rdata [3];

  for (genvar p = 0; p < 3; p++) begin : g_port
    muserisc_vrf_bank u_bank (
        .clk_i   (clk_i),
        .re_i    (re[p]),
        .raddr_i (raddr[p]),
        .rdata_o (ram_q[p]),
        .we_i    (we_i),
        .waddr_i (waddr_i),
        .wbe_i   (wbe_i),
        .wdata_i (wdata_i)
    );
    always_ff @(posedge clk_i) begin
      if (re[p]) begin
        byp_q[p] <= we_i && (waddr_i == raddr[p]);
        byp_be_q[p] <= wbe_i;
        byp_data_q[p] <= wdata_i;
      end
    end
    logic [63:0] byp_mask;
    for (genvar b = 0; b < 8; b++) begin : g_byte
      assign byp_mask[b*8 +: 8] = {8{byp_q[p] && byp_be_q[p][b]}};
    end
    assign rdata[p] = (ram_q[p] & ~byp_mask) | (byp_data_q[p] & byp_mask);
  end

  assign rdata_a_o = rdata[0];
  assign rdata_b_o = rdata[1];
  assign rdata_c_o = rdata[2];

  // v0 shadow (register 0 = words 0..7).
  logic [511:0] v0_q;
  always_ff @(posedge clk_i) begin
    if (we_i && (waddr_i[7:3] == 5'd0)) begin
      for (int b = 0; b < 8; b++) begin
        if (wbe_i[b]) v0_q[{waddr_i[2:0], 6'd0} + 9'(b * 8) +: 8] <=
            wdata_i[b*8 +: 8];
      end
    end
  end
  assign v0_o = v0_q;

endmodule
`default_nettype wire
