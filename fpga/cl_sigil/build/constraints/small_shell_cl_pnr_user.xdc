# Sigil CL (issue #54) placement for the F2 Small Shell.
# Keep the SoC, its DDR-side clock converter and the DDR4 controller in
# SLR2 (clock regions X0Y8:X7Y11, wholly CL; the HDK cl_mem_perf
# example places SH_DDR there too) so no core path crosses an SLR.
create_pblock pblock_CL_SLR2
resize_pblock pblock_CL_SLR2 -add {CLOCKREGION_X0Y8:CLOCKREGION_X7Y11}
set_property parent pblock_CL [get_pblocks pblock_CL_SLR2]
add_cells_to_pblock pblock_CL_SLR2 [get_cells [list \
  WRAPPER/CL/SH_DDR \
  WRAPPER/CL/PIPE_DDR_STAT* \
  WRAPPER/CL/SIGIL \
  WRAPPER/CL/DDR_CDC ]]
