// 32x64 register file, two combinational read ports, one clocked
// write port. x0 reads as zero and ignores writes.
`default_nettype none
module sigil_regfile (
    input  wire        clk_i,
    input  wire        we_i,
    input  wire [4:0]  waddr_i,
    input  wire [63:0] wdata_i,
    input  wire [4:0]  raddr_a_i,
    output wire [63:0] rdata_a_o,
    input  wire [4:0]  raddr_b_i,
    output wire [63:0] rdata_b_o
);
  logic [63:0] regs_q [0:31];

  always_ff @(posedge clk_i) begin
    if (we_i && (waddr_i != 5'd0)) begin
      regs_q[waddr_i] <= wdata_i;
    end
  end

  assign rdata_a_o = (raddr_a_i == 5'd0) ? 64'd0 : regs_q[raddr_a_i];
  assign rdata_b_o = (raddr_b_i == 5'd0) ? 64'd0 : regs_q[raddr_b_i];
endmodule
`default_nettype wire
