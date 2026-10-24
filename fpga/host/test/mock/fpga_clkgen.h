// Mock of the aws-fpga SDK fpga_clkgen.h (v2.3.5 signatures), only what
// sigil_host.c uses; implemented by ../sigil_host_mock.c.
#ifndef SIGIL_MOCK_FPGA_CLKGEN_H_
#define SIGIL_MOCK_FPGA_CLKGEN_H_
#include <stdint.h>
int aws_clkgen_set_recipe(int slot_id, uint32_t clk_a_recipe, uint32_t clk_b_recipe,
                          uint32_t clk_c_recipe, uint32_t clk_hbm_recipe, uint32_t reset);
int aws_clkgen_deassert_resets(int slot_id);
#endif
