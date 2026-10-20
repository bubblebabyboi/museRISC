// Sigil in-house core: FP register file (32 x 64-bit).
// Three asynchronous read ports (rs1/rs2/rs3 for FMA), one
// synchronous write port. Unlike the integer file there is no
// hardwired-zero register; f0 is an ordinary register.

module sigil_fpregfile (
    input  logic        clk_i,
    input  logic        we_i,
    input  logic [4:0]  waddr_i,
    input  logic [63:0] wdata_i,
    input  logic [4:0]  raddr1_i,
    input  logic [4:0]  raddr2_i,
    input  logic [4:0]  raddr3_i,
    output logic [63:0] rdata1_o,
    output logic [63:0] rdata2_o,
    output logic [63:0] rdata3_o
);

  logic [63:0] mem_q [32];

  always_ff @(posedge clk_i) begin
    if (we_i) mem_q[waddr_i] <= wdata_i;
  end

  assign rdata1_o = mem_q[raddr1_i];
  assign rdata2_o = mem_q[raddr2_i];
  assign rdata3_o = mem_q[raddr3_i];

endmodule
