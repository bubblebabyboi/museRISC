// Boot ROM -> sochash firmware over the CL (issue #54).
module test_sigil_hash();
  import tb_type_defines_pkg::*;
  `include "sigil_test_utils.svh"
  initial sigil_boot_image("hash_soc_test.bin", "SOC HASH PASS", "", 20000);
endmodule
