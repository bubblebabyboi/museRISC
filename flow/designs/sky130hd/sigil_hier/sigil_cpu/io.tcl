# sigil_cpu pins face the top-level glue (fabric, devices) above the
# block (see ../config.mk floorplan): all on the block's top edge.
exclude_io_pin_region -region bottom:* -region left:* -region right:*
