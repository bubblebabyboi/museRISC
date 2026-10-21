// Boot ROM -> OpenSBI fw_jump (0x8000_0000) + DTB (0x8300_0000) ->
// S-mode payload s_hello (0x8020_0000), the OpenSBI layout the host
// runtime uses for Linux.
module test_sigil_hello();
  import tb_type_defines_pkg::*;
  `include "sigil_test_utils.svh"
  initial begin
    bit ok;
    sigil_power_up();
    sigil_load_pcis({`SIGIL_FW_DIR, "fw_jump.bin"}, `SIGIL_DDR(32'h8000_0000));
    sigil_load_pcis({`SIGIL_FW_DIR, "sigil.dtb"},   `SIGIL_DDR(32'h8300_0000));
    sigil_load_pcis({`SIGIL_FW_DIR, "s_hello.bin"}, `SIGIL_DDR(32'h8020_0000));
    sigil_run("HELLO FROM S-MODE", "", 400000, ok);
    sigil_finish();
  end
endmodule
