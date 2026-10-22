// F2 platform test through the whole CL (issues #62, #63, #65-#67):
//  1. DDR4 + HBM ready, VERSION 4, RAM window 80 GiB, HBM present.
//  2. Memory engine over OCL: address pattern written and checked
//     across the 4 GiB mark and across the DDR4 / HBM boundary (AXI
//     64 GiB) through DDR_CDC -> SmartConnect -> sh_ddr / HBM slices;
//     a word changed through PCIS must show up as exactly one mismatch.
//  3. sw/fpga-tests/f2_platform_test.bin from the boot ROM: RTC (set
//     over OCL), window edges of DDR4 and HBM from the core, Linux-
//     style UART bursts (every byte checked), an out-of-window read
//     (mailbox bit 0), then the test finisher (power off). The host
//     side checks FIN_STATUS / FIN_VALUE, the bridge error capture
//     (out-of-window read of PA 0x14_8000_0000) and reads the lines
//     the core wrote into DDR4 and HBM back through PCIS.
// Runs at recipe B5 like the other long firmware tests (Makefile.tests).
module test_sigil_platform();
  import tb_type_defines_pkg::*;
  `include "sigil_test_utils.svh"

  localparam logic [63:0] SEED = 64'h0123_4567_89AB_CDEF;

  task automatic eng_run(input int mode, input logic [63:0] base, input logic [63:0] size,
                         input logic [63:0] seed, output logic [31:0] ctrl);
    sigil_ocl_wr(32'h0A4, base[31:0]);
    sigil_ocl_wr(32'h0A8, base[63:32]);
    sigil_ocl_wr(32'h0AC, size[31:0]);
    sigil_ocl_wr(32'h0B0, size[63:32]);
    sigil_ocl_wr(32'h0B4, seed[31:0]);
    sigil_ocl_wr(32'h0B8, seed[63:32]);
    sigil_ocl_wr(32'h0A0, (32'(mode) << 4) | 32'h1);
    do sigil_ocl_rd(32'h0A0, ctrl); while (ctrl[1:0] != 2'b10);
    begin
      logic [31:0] cyc, mism;
      sigil_ocl_rd(32'h0C8, cyc);
      sigil_ocl_rd(32'h0BC, mism);
      $display("[%t] engine mode %0d AXI 0x%0x+0x%0x: %0d core cycles, %0d mismatches, MEM_CTRL 0x%0x",
               $realtime, mode, base, size, cyc, mism, ctrl);
    end
  endtask

  function automatic logic [63:0] pat(input logic [63:0] a, input int k);
    return (a + 64'(8 * k)) ^ 64'hA5C3F00D12345678 ^ (64'(k) << 56);
  endfunction

  initial begin
    logic [31:0] d, ctrl;
    logic [511:0] line;
    string out = "";
    bit fin = 0;
    int bursts = 0;
    realtime t_end;
    sigil_power_up();
    sigil_ocl_rd(`SIGIL_STATUS, d);
    sigil_check("STATUS DDR4 + HBM ready, held", d & 32'hC1, 32'hC1);
    sigil_ocl_rd(`SIGIL_VERSION, d); sigil_check("VERSION", d, 32'h0004_0001);
    sigil_ocl_rd(32'h054, d);        sigil_check("RAM_SIZE_MB", d, 32'd81920);
    sigil_ocl_rd(32'h058, d);        sigil_check("CAPS (HBM, recipe H0)", d, 32'h11);

    // 2. Memory engine.
    eng_run(1, 64'h0_FFFF_C000, 64'h8000, SEED, ctrl);
    eng_run(3, 64'h0_FFFF_C000, 64'h8000, SEED, ctrl);
    sigil_check("engine 4 GiB check", ctrl & 32'h7, 32'h2);
    eng_run(1, 64'hF_FFFF_C000, 64'h8000, SEED, ctrl);
    eng_run(3, 64'hF_FFFF_C000, 64'h8000, SEED, ctrl);
    sigil_check("engine DDR4/HBM boundary check", ctrl & 32'h7, 32'h2);
    tb.peek_pcis(.addr(64'h10_0000_0040), .data(line));
    sigil_check("HBM word via PCIS = engine pattern", line[31:0],
                32'(64'h10_0000_0040 ^ SEED));
    line[63:0] = ~line[63:0];
    tb.poke_pcis(.addr(64'h10_0000_0040), .data(line), .strb({64{1'b1}}));
    eng_run(3, 64'hF_FFFF_C000, 64'h8000, SEED, ctrl);
    sigil_check("engine injected mismatch", ctrl & 32'h7, 32'h6);
    sigil_ocl_rd(32'h0BC, d);        sigil_check("MEM_MISM", d, 32'd1);
    sigil_ocl_rd(32'h0C0, d);        sigil_check("MEM_FADDR_LO", d, 32'h0000_0040);
    sigil_ocl_rd(32'h0C4, d);        sigil_check("MEM_FADDR_HI", d, 32'h10);

    // 3. Platform firmware: RTC, mailbox (out-of-window read), release.
    sigil_load_pcis({`SIGIL_FW_DIR, "f2_platform_test.bin"}, `SIGIL_DDR(32'h8000_0000));
    line = '0;
    line[63:0] = 64'h1;
    tb.poke_pcis(.addr(`SIGIL_DDR(32'h8008_0000)), .data(line), .strb({64{1'b1}}));
    sigil_ocl_wr(32'h080, 32'hDA11_DD30);   // RTC = 0x1870A71D_DA11DD30 ns (2025)
    sigil_ocl_wr(32'h084, 32'h1870_A71D);
    sigil_ocl_wr(`SIGIL_CTRL, 32'h0000_000B); // clear the error capture (held)
    sigil_ocl_wr(`SIGIL_BOOT_PC_LO, 32'h1000);
    sigil_ocl_wr(`SIGIL_CTRL, 32'h2);
    $display("[%t] sigil: f2_platform_test released", $realtime);
    t_end = $realtime + 20ms;
    while ($realtime < t_end) begin
      sigil_ocl_rd(32'h050, d);              // UART_TX_DATA3
      if (d[25:24] != 0) begin
        for (int b = 0; b < d[25:24]; b++) begin
          $write("%c", d[8*b +: 8]);
          out = {out, string'(d[8*b +: 8])};
        end
      end else begin
        sigil_ocl_rd(`SIGIL_STATUS, d);
        if (d[11] && !d[5]) begin
          fin = 1;
          break;
        end
        #2us;
      end
    end
    $display("");
    if (!fin) begin
      error_count++;
      $error("[%t] no finisher event", $realtime);
    end
    sigil_ocl_rd(32'h074, d);        sigil_check("FIN_VALUE (power off)", d, 32'h5555);
    for (int n = 0; n < 64; n++) begin
      string want = "B";
      want = {want, string'(8'(48 + n / 10)), string'(8'(48 + n % 10)), ":"};
      for (int j = 0; j < 56; j++) want = {want, string'(8'(97 + (n * 7 + j) % 26))};
      for (int i = 0; i + want.len() <= out.len(); i++)
        if (out.substr(i, i + want.len() - 1) == want) begin
          bursts++;
          break;
        end
    end
    sigil_check("UART burst lines byte-exact", bursts, 64);
    begin
      int ok = 0;
      for (int i = 0; i + 16 <= out.len(); i++)
        if (out.substr(i, i + 15) == "F2 PLATFORM PASS") ok = 1;
      sigil_check("F2 PLATFORM PASS seen", ok, 1);
    end
    sigil_ocl_rd(32'h068, d);        sigil_check("ERR_INFO (oob read, DECERR)", d, 32'hAC00_0000);
    sigil_ocl_rd(32'h060, d);        sigil_check("ERR_ADDR_LO", d, 32'h8000_0000);
    sigil_ocl_rd(32'h064, d);        sigil_check("ERR_ADDR_HI", d, 32'h14);
    // Lines the core wrote, read back through PCIS (DDR4 end, HBM start / end).
    begin
      logic [63:0] pa[3] = '{64'h10_7FFF_FFC0, 64'h10_8000_0000, 64'h14_7FFF_FFC0};
      for (int i = 0; i < 3; i++) begin
        tb.peek_pcis(.addr(pa[i] - 64'h8000_0000), .data(line));
        for (int k = 0; k < 8; k++)
          if (line[64*k +: 64] !== pat(pa[i], k)) begin
            error_count++;
            $error("[%t] PCIS read of the core's line at PA 0x%0x word %0d: %h", $realtime,
                   pa[i], k, line[64*k +: 64]);
          end
      end
      $display("[%t] core-written DDR4/HBM lines read back through PCIS", $realtime);
    end
    sigil_finish();
  end
endmodule
