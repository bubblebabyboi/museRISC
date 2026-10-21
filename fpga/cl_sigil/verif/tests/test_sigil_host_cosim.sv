// HW/SW co-simulation of the host runtime (issue #54): fpga/host/
// sigil_host.c runs unchanged against the simulated CL through
// fpga/host/cosim/sigil_host_cosim.c, which maps the aws-fpga SDK
// calls onto the DPI tasks below (Shell BFM OCL / PCIS / SDA).
// Arguments: sigil_host_cosim.args in this directory.
module test_sigil_host_cosim();
  import tb_type_defines_pkg::*;
  `include "sigil_test_utils.svh"

  import "DPI-C" context task sigil_host_cosim_main(output int rc);
  export "DPI-C" task sv_sigil_ocl_rd;
  export "DPI-C" task sv_sigil_ocl_wr;
  export "DPI-C" task sv_sigil_pcis_rd64;
  export "DPI-C" task sv_sigil_pcis_wr_line;
  export "DPI-C" task sv_sigil_sleep_ns;
  export "DPI-C" task sv_sigil_clkgen;
  export "DPI-C" function sv_sigil_time_ps;

  task sv_sigil_ocl_rd(input int unsigned addr, output int unsigned data);
    logic [31:0] d;
    sigil_ocl_rd(addr, d);
    data = d;
  endtask
  task sv_sigil_ocl_wr(input int unsigned addr, input int unsigned data);
    sigil_ocl_wr(addr, data);
  endtask
  task sv_sigil_pcis_rd64(input longint unsigned addr, output longint unsigned data);
    logic [511:0] r;
    tb.peek_pcis(.addr({addr[63:6], 6'd0}), .data(r));
    data = r[64*addr[5:3] +: 64];
  endtask
  task sv_sigil_pcis_wr_line(input longint unsigned addr, input bit [511:0] data,
                             input bit [63:0] strb);
    tb.poke_pcis(.addr(addr), .data(data), .strb(strb));
  endtask
  task sv_sigil_sleep_ns(input int ns);
    #(ns * 1ns);
  endtask
  // recipe_b < 0: only release the AWS_CLK_GEN resets (aws_clkgen_deassert_resets);
  // else program group B like aws_clkgen_set_recipe().
  task sv_sigil_clkgen(input int recipe_b);
    if (recipe_b >= 0) begin
      aws_clkgen_asrt_rst();
      case (recipe_b)
        1: aws_clkgen_set_mmcm(`AWS_CLKGEN_BASE_B, 11, 875, 1, 9, 500, 19, 1, 0);
        3: aws_clkgen_set_mmcm(`AWS_CLKGEN_BASE_B, 11, 875, 1, 4, 750, 19, 1, 0);
        4: aws_clkgen_set_mmcm(`AWS_CLKGEN_BASE_B, 12, 0, 1, 4, 0, 16, 1, 0);
        5: aws_clkgen_set_mmcm(`AWS_CLKGEN_BASE_B, 12, 0, 1, 3, 0, 12, 1, 0);
        default: $display("cosim: recipe B%0d not modelled, MMCM left as is", recipe_b);
      endcase
    end
    aws_clkgen_dsrt_rst();
  endtask
  function longint sv_sigil_time_ps();
    return longint'($realtime / 1ps);
  endfunction

  initial begin
    int rc;
    // "AFI load": Shell power-up and DDR init; clocks and everything
    // after them are the host runtime's job.
    tb.power_up(.clk_recipe_a(ClockRecipe::A1));
    #500ns;
    tb.poke_stat(.addr(8'h0c), .intf("ddr"), .data(32'h0000_0000));
    tb.poke_stat(.addr(8'h0c), .intf("ddr"), .data(32'h0000_0001));
    tb.poke_stat(.addr(8'h0c), .intf("ddr"), .data(32'h0000_0000));
    sigil_host_cosim_main(rc);
    $display("[%t] cosim: sigil_host returned %0d", $realtime, rc);
    if (rc != 0) error_count++;
    sigil_finish();
  end
endmodule
