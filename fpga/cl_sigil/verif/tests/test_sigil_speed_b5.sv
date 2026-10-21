// XSIM speed probe (issue #54), B5 core clock + slowed unused groups:
// timing `run` slices of simulated time from the xsim prompt.
module test_sigil_speed_b5();
  import tb_type_defines_pkg::*;
  `include "sigil_test_utils.svh"
  initial sigil_boot_image("hash_soc_test.bin", "SOC HASH PASS", "", 20000);
endmodule
