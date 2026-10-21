// XSIM speed probe (issue #54): sochash with the core released, for
// timing `run` slices of simulated time from the xsim prompt.
module test_sigil_speed();
  import tb_type_defines_pkg::*;
  `include "sigil_test_utils.svh"
  initial sigil_boot_image("hash_soc_test.bin", "SOC HASH PASS", "", 20000);
endmodule
