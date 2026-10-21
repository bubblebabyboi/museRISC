# Sigil CL (issue #54): no extra timing constraints. The core clock is
# AWS_CLK_GEN clk_extra_b1, constrained by the HDK flow from
# --clock_recipe_b; clk_main_a0 <-> clk_extra_b1 crossings are only in
# the Xilinx AXI clock converters (DDR_CDC, OCL_CDC) and XPM CDC cells,
# whose own constraints apply.
