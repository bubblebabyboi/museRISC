// QEMU-virt-compatible test finisher ("sifive,test1" / "sifive,test0",
// docs/LINUX_PLATFORM.md; issue #67) at SoC 0x0010_0000. A write to
// offset 0 whose low 16 bits are a known status raises fin_valid_o for
// one cycle with the written value on fin_data_o:
//   0x5555                 power off (pass)       -- FINISHER_PASS
//   0x7777                 reboot                 -- FINISHER_RESET
//   (code << 16) | 0x3333  power off with failure -- FINISHER_FAIL
// Other values and offsets are ignored and reads return 0, as in QEMU
// (so syscon-poweroff / syscon-reboot read-modify-writes work). What
// happens on an event is up to the platform: the FPGA top latches it
// for the host (OCL FIN_* registers), the simulation harnesses end the
// run. Bus: the core's aligned 64-bit device word (exact byte address
// in addr_i, byte lanes in be_i / wdata_i).
`default_nettype none
module sigil_test_finisher (
    input  wire        clk_i,
    input  wire        rst_ni,
    input  wire        sel_i,      // access to this 4 KiB page
    /* verilator lint_off UNUSEDSIGNAL */
    input  wire [11:0] addr_i,
    input  wire [7:0]  be_i,
    input  wire [63:0] wdata_i,
    /* verilator lint_on UNUSEDSIGNAL */
    output wire [63:0] rdata_o,
    output logic       fin_valid_o,
    output logic [31:0] fin_data_o
);
  localparam logic [15:0] FIN_FAIL  = 16'h3333;
  localparam logic [15:0] FIN_PASS  = 16'h5555;
  localparam logic [15:0] FIN_RESET = 16'h7777;

  logic [31:0] val;
  logic        wr;
  always_comb begin
    for (int i = 0; i < 4; i++) val[8*i +: 8] = be_i[i] ? wdata_i[8*i +: 8] : 8'd0;
  end
  // Offset 0 only (the 32-bit register is the low half of word 0).
  assign wr = sel_i && (addr_i[11:3] == 9'd0) && (be_i[1:0] != 2'b00);
  assign rdata_o = 64'd0;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      fin_valid_o <= 1'b0;
      fin_data_o <= 32'd0;
    end else begin
      fin_valid_o <= wr && ((val[15:0] == FIN_PASS) || (val[15:0] == FIN_FAIL) ||
                            (val[15:0] == FIN_RESET));
      if (wr) fin_data_o <= val;
    end
  end
endmodule
`default_nettype wire
