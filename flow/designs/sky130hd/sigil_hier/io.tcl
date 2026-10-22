# sigil_soc_top pins: left and right die edges above the CPU block
# (y > 2600), next to the glue channel/columns (see config.mk).
exclude_io_pin_region -region bottom:* -region top:* -region left:0-2600 -region right:0-2600
