// 4 KiB boot ROM at SoC offset 0 (mapped at 0x1000 by the
// fabric). Contents are sw/linux/boot_stub.S assembled with
// -Ttext=0x1000 (16 bytes: a0=0, a1=DTB 0x8300_0000, jump
// to OpenSBI at 0x8000_0000); the rest reads as zero.
// Regenerate the words if boot_stub.S changes:
//   make -C sim soc, then read build/linux/boot_stub.bin
//   as little-endian 32-bit words.
`default_nettype none
module sigil_bootrom (
    /* verilator lint_off UNUSEDSIGNAL */
    input  wire [11:0] addr_i,
    /* verilator lint_on UNUSEDSIGNAL */
    output wire [31:0] data_o,
    output wire [63:0] data64_o
);
  function automatic logic [31:0] rom_word(input logic [9:0] idx);
    unique case (idx)
      10'd0:   return 32'h059b_4501;
      10'd1:   return 32'h05e2_0830;
      10'd2:   return 32'h0010_029b;
      10'd3:   return 32'h8282_02fe;
      default: return 32'd0;
    endcase
  endfunction

  assign data_o = rom_word(addr_i[11:2]);
  assign data64_o = {rom_word({addr_i[11:3], 1'b1}),
                     rom_word({addr_i[11:3], 1'b0})};
endmodule
`default_nettype wire
