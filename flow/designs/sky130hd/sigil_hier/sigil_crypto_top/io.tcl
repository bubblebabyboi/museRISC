# sigil_crypto_top pins: bottom edge, facing the 40 um routing gap
# above the CPU block that leads to the top-level glue column (see
# ../config.mk floorplan). Pins on the 780 um left edge instead put the
# AXI register/read-mux logic at one end of the 2770 um block: +24 %
# global-route wire and 7,873 overflowed gcells (v2 run).
exclude_io_pin_region -region top:* -region left:* -region right:*
