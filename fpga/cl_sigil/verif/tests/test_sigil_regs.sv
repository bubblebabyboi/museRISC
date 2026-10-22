// OCL register block, clock recipe + measured core clock, PCIS <-> DDR
// and the virtual UART RX FIFO with the SoC held (issue #54).
module test_sigil_regs();
  import tb_type_defines_pkg::*;
  `include "sigil_test_utils.svh"
  initial begin
    logic [31:0] d, lo, hi;
    logic [511:0] w, r;
    longint unsigned c0, c1;
    real mhz;
    sigil_power_up();
    sigil_ocl_rd(`SIGIL_ID, d);       sigil_check("ID", d, 32'h5349_474C);
    sigil_ocl_rd(`SIGIL_VERSION, d);  sigil_check("VERSION", d, 32'h0004_0001);
    sigil_ocl_rd(`SIGIL_CLK_KHZ, d);  sigil_check("CLK_KHZ", d, 32'd62500);
    sigil_ocl_rd(`SIGIL_CTRL, d);     sigil_check("CTRL reset value", d, 32'h3);
    sigil_ocl_rd(`SIGIL_STATUS, d);   sigil_check("STATUS (in reset, DDR + HBM ready)", d, 32'hC1);
    sigil_ocl_rd(32'h054, d);         sigil_check("RAM_SIZE_MB (DDR4 + HBM)", d, 32'd81920);
    sigil_ocl_rd(32'h058, d);         sigil_check("CAPS (HBM present)", d, 32'h1);
    sigil_ocl_rd(`SIGIL_BOOT_PC_LO, d); sigil_check("BOOT_PC_LO reset", d, 32'h1000);
    sigil_ocl_rd(`SIGIL_BOOT_PC_HI, d); sigil_check("BOOT_PC_HI reset", d, 32'h0);
    sigil_ocl_wr(`SIGIL_SCRATCH, 32'hA5C3_0F96);
    sigil_ocl_rd(`SIGIL_SCRATCH, d);  sigil_check("SCRATCH", d, 32'hA5C3_0F96);
    sigil_ocl_wr(`SIGIL_BOOT_PC_LO, 32'h8000_0000);
    sigil_ocl_rd(`SIGIL_BOOT_PC_LO, d); sigil_check("BOOT_PC_LO rw", d, 32'h8000_0000);
    sigil_ocl_wr(`SIGIL_BOOT_PC_LO, 32'h1000);
    sigil_ocl_rd(32'h0F0, d);         sigil_check("unmapped", d, 32'hBAAD_DEC0);
    sigil_ocl_rd(`SIGIL_TX_DATA, d);  sigil_check("TX_DATA empty", d, 32'h0);
    sigil_ocl_rd(`SIGIL_TRAP_COUNT, d); sigil_check("TRAP_COUNT", d, 32'h0);
    // Cycle counter: monotonic, snapshot hi/lo, and the measured clock.
    sigil_cycles(c0);
    sigil_cycles(c1);
    if (!(c1 > c0)) begin
      error_count++;
      $error("cycle counter not increasing: %0d then %0d", c0, c1);
    end
    sigil_measure_clock(20000, mhz);
    if (mhz < 61.5 || mhz > 63.5) begin
      error_count++;
      $error("measured core clock %0.3f MHz, expected 62.5 (recipe B1)", mhz);
    end
    // RX FIFO while the SoC is held: bytes are kept.
    for (int i = 0; i < 5; i++) sigil_ocl_wr(`SIGIL_RX_DATA, 32'h41 + i);
    sigil_ocl_rd(`SIGIL_RX_STATUS, d); sigil_check("RX_STATUS count", d, 32'd5);
    // PCIS write / read back across both windows (AppPF BAR4 offsets):
    // DDR4 0x0 .. 0xF_FFFF_FFFF, HBM 0x10_0000_0000 .. 0x13_FFFF_FFFF.
    begin
      logic [63:0] pa[8];
      pa = '{64'h0, 64'h07FF_FFC0, 64'hFFFF_FFC0, 64'h1_0000_0000,
             64'h8_0000_0000, 64'hF_FFFF_FFC0, 64'h10_0000_0000,
             64'h13_FFFF_FFC0};
      for (int i = 0; i < 8; i++) begin
        for (int k = 0; k < 16; k++) w[32*k +: 32] = {pa[i][35:20], 16'(k)} ^ 32'hC0DE_0000;
        tb.poke_pcis(.addr(pa[i]), .data(w), .strb({64{1'b1}}));
      end
      for (int i = 0; i < 8; i++) begin
        for (int k = 0; k < 16; k++) w[32*k +: 32] = {pa[i][35:20], 16'(k)} ^ 32'hC0DE_0000;
        tb.peek_pcis(.addr(pa[i]), .data(r));
        if (r !== w) begin
          error_count++;
          $error("PCIS readback at 0x%0x: %h", pa[i], r);
        end else $display("[%t] PCIS readback at 0x%0x ok", $realtime, pa[i]);
      end
    end
    $display("[%t] PCIS DDR4 / HBM readback checks done", $realtime);
    sigil_finish();
  end
endmodule
