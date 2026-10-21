// Shared tasks for the Sigil CL XSIM tests (issue #54). They drive the
// CL through the HDK Shell BFM exactly the way fpga/host/sigil_host.c
// drives the real FPGA: AWS_CLK_GEN over SDA (clock recipe + reset
// release), OCL registers (docs/FPGA_F2.md "F3" register map), and
// payload loads into DDR through PCIS.
`include "common_base_test.svh"
`include "aws_clk_gen_utils.svh"

// OCL register offsets (rtl/fpga/sigil_ocl_regs.sv).
`define SIGIL_ID          32'h000
`define SIGIL_VERSION     32'h004
`define SIGIL_CTRL        32'h008
`define SIGIL_STATUS      32'h00C
`define SIGIL_BOOT_PC_LO  32'h010
`define SIGIL_BOOT_PC_HI  32'h014
`define SIGIL_CYCLE_LO    32'h018
`define SIGIL_CYCLE_HI    32'h01C
`define SIGIL_TRAP_COUNT  32'h020
`define SIGIL_CLK_KHZ     32'h024
`define SIGIL_SCRATCH     32'h03C
`define SIGIL_TX_DATA     32'h040
`define SIGIL_TX_STATUS   32'h044
`define SIGIL_RX_DATA     32'h048
`define SIGIL_RX_STATUS   32'h04C

// SoC RAM 0x8000_0000 maps to DDR offset 0 (sigil_fpga_ocl DDR_BASE = 0).
`define SIGIL_DDR(soc_addr) (64'(soc_addr) - 64'h8000_0000)

// Firmware images staged by fpga/scripts/sim_cl_sigil.sh; XSIM runs
// in $CL_DIR/verif/sim/xsim/<test>_sv_fast.
`define SIGIL_FW_DIR "../../../fw/"

task automatic sigil_ocl_rd(input logic [31:0] addr, output logic [31:0] data);
  logic [63:0] d;
  tb.peek_ocl(.addr(64'(addr)), .data(d));
  data = d[31:0];
endtask

task automatic sigil_ocl_wr(input logic [31:0] addr, input logic [31:0] data);
  tb.poke_ocl(.addr(64'(addr)), .data(data));
endtask

task automatic sigil_check(input string what, input logic [31:0] got, input logic [31:0] exp);
  if (got !== exp) begin
    error_count++;
    $error("[%t] SIGIL CHECK FAIL %s: got 0x%08x expected 0x%08x", $realtime, what, got, exp);
  end else begin
    $display("[%t] check %s = 0x%08x ok", $realtime, what, got);
  end
endtask

task automatic sigil_cycles(output longint unsigned c);
  logic [31:0] lo, hi;
  sigil_ocl_rd(`SIGIL_CYCLE_LO, lo);  // snapshots the upper half
  sigil_ocl_rd(`SIGIL_CYCLE_HI, hi);
  c = {hi, lo};
endtask

// Shell power-up, AWS_CLK_GEN group B -> recipe B1 (clk_extra_b1 =
// 62.5 MHz, the interim core clock) the way the SDK's
// aws_clkgen_set_recipe() does it (assert resets, program, release
// after MMCM lock), then wait for DDR.
task automatic sigil_power_up();
  logic [31:0] st;
  int n;
  tb.power_up(.clk_recipe_a(ClockRecipe::A1));
  #500ns;
  aws_clkgen_dsrt_rst();
  aws_clkgen_asrt_rst();
  // B1: VCO = 100 MHz x 11.875; b0 = /9.5 = 125 MHz; b1 = /19 = 62.5 MHz
  aws_clkgen_set_mmcm(.mmcm_base(`AWS_CLKGEN_BASE_B), .mult(11), .mult_frac(875),
                      .div(1), .div0(9), .div0_frac(500), .div1(19), .div2(1), .reset(0));
  aws_clkgen_dsrt_rst();
  #1us;
  n = 0;
  do begin
    sigil_ocl_rd(`SIGIL_STATUS, st);
    n++;
    if (!st[6]) #1us;
  end while (!st[6] && n < 1000);
  if (!st[6]) begin
    error_count++;
    $error("[%t] DDR never reported ready (STATUS 0x%08x)", $realtime, st);
  end
  $display("[%t] sigil: clocks programmed (B1), resets released, STATUS 0x%08x", $realtime, st);
endtask

// Measured core clock: cycle-counter delta over simulated time.
task automatic sigil_measure_clock(input int window_ns, output real mhz);
  longint unsigned c0, c1;
  realtime t0, t1;
  sigil_cycles(c0);
  t0 = $realtime;
  #(window_ns * 1ns);
  sigil_cycles(c1);
  t1 = $realtime;
  mhz = real'(c1 - c0) / ((t1 - t0) / 1us);
  $display("[%t] sigil: cycle counter %0d -> %0d over %0.3f us = %0.3f MHz",
           $realtime, c0, c1, (t1 - t0) / 1us, mhz);
endtask

// Copy a binary file into DDR through PCIS, 64 bytes per write, then
// read the first and last line back through PCIS.
task automatic sigil_load_pcis(input string path, input logic [63:0] ddr_addr);
  int fd, c, nbytes;
  byte unsigned img[$];
  logic [511:0] d, rd;
  logic [63:0] strb;
  fd = $fopen(path, "rb");
  if (fd == 0) begin
    error_count++;
    $fatal(1, "cannot open %s", path);
  end
  while ((c = $fgetc(fd)) != -1) img.push_back(byte'(c));
  $fclose(fd);
  nbytes = img.size();
  for (int off = 0; off < nbytes; off += 64) begin
    d = '0;
    strb = '0;
    for (int k = 0; k < 64 && off + k < nbytes; k++) begin
      d[8*k +: 8] = img[off + k];
      strb[k] = 1'b1;
    end
    tb.poke_pcis(.addr(ddr_addr + off), .data(d), .strb(strb));
  end
  for (int pass = 0; pass < 2; pass++) begin
    int off = pass == 0 ? 0 : ((nbytes - 1) / 64) * 64;
    tb.peek_pcis(.addr(ddr_addr + off), .data(rd));
    for (int k = 0; k < 64 && off + k < nbytes; k++)
      if (rd[8*k +: 8] !== img[off + k]) begin
        error_count++;
        $error("[%t] PCIS readback mismatch %s +0x%0x: 0x%02x vs 0x%02x",
               $realtime, path, off + k, rd[8*k +: 8], img[off + k]);
        break;
      end
  end
  $display("[%t] sigil: loaded %0d bytes from %s at DDR 0x%0x (PCIS)", $realtime,
           nbytes, path, ddr_addr);
endtask

// Release the SoC (boot PC = boot ROM) and drain the virtual UART
// over OCL until `pass` appears, feeding `rx` into the RX FIFO. Reports
// cycles to pass and the measured clock over the run.
task automatic sigil_run(input string pass, input string rx, input int max_us,
                         output bit ok);
  logic [31:0] d, st;
  string out = "";
  int rx_i = 0, idle = 0;
  longint unsigned c0, c1;
  realtime t0, t_end;
  ok = 0;
  sigil_ocl_wr(`SIGIL_BOOT_PC_LO, 32'h1000);
  sigil_ocl_wr(`SIGIL_BOOT_PC_HI, 32'h0);
  sigil_ocl_wr(`SIGIL_CTRL, 32'h2);          // cache_en = 1, release reset
  sigil_cycles(c0);
  t0 = $realtime;
  t_end = t0 + max_us * 1us;
  $display("[%t] sigil: SoC released, waiting for \"%s\"", $realtime, pass);
  while ($realtime < t_end) begin
    sigil_ocl_rd(`SIGIL_TX_DATA, d);
    if (d[31]) begin
      idle = 0;
      $write("%c", d[7:0]);
      out = {out, string'(d[7:0])};
      if (out.len() > 4096) out = out.substr(out.len() - 1024, out.len() - 1);
      if (out.len() >= pass.len() &&
          out.substr(out.len() - pass.len(), out.len() - 1) == pass) begin
        ok = 1;
        break;
      end
    end else begin
      idle++;
      if (rx_i < rx.len()) begin
        sigil_ocl_rd(`SIGIL_RX_STATUS, st);
        if (!st[31]) begin
          sigil_ocl_wr(`SIGIL_RX_DATA, 32'(rx[rx_i]));
          rx_i++;
        end
      end
      if (idle % 64 == 0) begin
        sigil_ocl_rd(`SIGIL_STATUS, st);
        if (st[1] || st[2]) begin
          error_count++;
          $error("[%t] sigil: STATUS 0x%08x (mem_err/tx_overflow)", $realtime, st);
          break;
        end
      end
      #2us;
    end
  end
  sigil_cycles(c1);
  $display("");
  if (ok) begin
    $display("[%t] SIGIL PASS \"%s\" after %0d core cycles, %0.1f us simulated, measured %0.3f MHz",
             $realtime, pass, c1 - c0, ($realtime - t0) / 1us,
             real'(c1 - c0) / (($realtime - t0) / 1us));
  end else begin
    error_count++;
    $error("[%t] SIGIL TIMEOUT waiting for \"%s\" (%0d core cycles)", $realtime, pass, c1 - c0);
  end
endtask

function automatic string sigil_read_text(input string path);
  int fd, c;
  string s = "";
  fd = $fopen(path, "rb");
  if (fd == 0) $fatal(1, "cannot open %s", path);
  while ((c = $fgetc(fd)) != -1) s = {s, string'(byte'(c))};
  $fclose(fd);
  return s;
endfunction

task automatic sigil_finish();
  #1us;
  tb.power_down();
  report_pass_fail_status();
  $finish;
endtask

// One baremetal image at SoC 0x8000_0000, boot ROM -> image.
task automatic sigil_boot_image(input string image, input string pass,
                                input string rx, input int max_us);
  bit ok;
  logic [31:0] st;
  sigil_power_up();
  sigil_ocl_rd(`SIGIL_STATUS, st);
  sigil_check("STATUS.soc_in_reset before release", 32'(st[0]), 32'h1);
  sigil_load_pcis({`SIGIL_FW_DIR, image}, `SIGIL_DDR(32'h8000_0000));
  sigil_run(pass, rx, max_us, ok);
  sigil_finish();
endtask
