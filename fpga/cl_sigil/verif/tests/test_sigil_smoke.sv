// Boot ROM -> FPGA smoke firmware (D$-thrashing memory test over the
// AXI/DDR path) + a 170-byte line through the virtual-UART RX path.
module test_sigil_smoke();
  import tb_type_defines_pkg::*;
  `include "sigil_test_utils.svh"
  initial sigil_boot_image("fpga_smoke_test.bin", "FPGA SMOKE PASS",
                           sigil_read_text({`SIGIL_FW_DIR, "fpga_smoke_uart_in.txt"}), 400000);
endmodule
