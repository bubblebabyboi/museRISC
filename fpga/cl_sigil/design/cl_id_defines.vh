// PCIe IDs of the Sigil CL (issue #54), copied into the AFI manifest
// by aws_build_dcp_from_cl.py. Amazon vendor ID 0x1D0F requires a
// device ID in 0xF000-0xF0FF (HDK cl_id_defines.vh rules).
`ifndef CL_ID_DEFINES
`define CL_ID_DEFINES
  // 31:16 PCIe Device ID, 15:0 PCIe Vendor ID
  `define CL_SH_ID0 32'hF054_1D0F
  // 31:16 PCIe Subsystem ID, 15:0 Subsystem Vendor ID
  `define CL_SH_ID1 32'h5160_1D0F
`endif
