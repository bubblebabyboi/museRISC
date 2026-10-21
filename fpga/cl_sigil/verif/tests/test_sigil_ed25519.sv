// Boot ROM -> socrtl crypto image (ed25519_soc_test).
module test_sigil_ed25519();
  import tb_type_defines_pkg::*;
  `include "sigil_test_utils.svh"
  initial sigil_boot_image("ed25519_soc_test.bin", "SOC CRYPTO PASS", "", 800000);
endmodule
