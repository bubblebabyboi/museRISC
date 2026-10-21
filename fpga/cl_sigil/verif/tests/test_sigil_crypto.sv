// Boot ROM -> socrtl crypto image (crypto_soc_test).
module test_sigil_crypto();
  import tb_type_defines_pkg::*;
  `include "sigil_test_utils.svh"
  initial sigil_boot_image("crypto_soc_test.bin", "SOC CRYPTO PASS", "", 800000);
endmodule
