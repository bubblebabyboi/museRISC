# sigil_crypto_top pins face the top-level glue channel between the
# CPU block and this block (see ../config.mk floorplan): all on the
# block's bottom edge.
exclude_io_pin_region -region top:* -region left:* -region right:*
