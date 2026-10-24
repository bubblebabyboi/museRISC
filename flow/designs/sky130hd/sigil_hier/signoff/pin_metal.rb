# sigil: draw the DEF pin rectangles of ORFS-written cells as metal.
#
# ORFS's GDS merge (util/def2stream.py with platforms/sky130hd/sky130hd.lyt)
# writes the PINS of a DEF only on the pin purpose (li1/met1..met5 x/16:
# <special-pins-datatype-string>16), not on the drawing purpose (x/20) that
# is the mask layer and the layer DRC and LVS connect through. Where the
# router's wire covers the pin rectangle that does not matter, but at the
# hard-block boundaries of sigil_hier it does: a block pin is a 0.14 x 0.485
# um met2 rectangle (LEF / DEF), the block's own route reaches into it from
# the inside and the top-level route from the outside, and between the two
# wire ends there is only the x/16 rectangle (e.g. crypto clk: top wire
# ends 0.04 um into the pin, block wire starts 0.34 um into it). Both
# routers took the whole pin rectangle as metal (LEF PIN / DEF PINS), so
# this script makes the GDS say what the routed DEFs say: for each named
# cell, its own (non-recursive) x/16 shapes are added on x/20. Std-cell and
# OpenRAM GDS cells are not touched (their pins are drawn metal already).
#
# usage: klayout -b -rd in_gds=<gds> -rd out_gds=<gds> [-rd cells=a,b] -r pin_metal.rb
#   cells: default the top cell; the hierarchical SoC uses
#          sigil_soc_top,sigil_cpu,sigil_crypto_top
# Prints per cell and layer: pin shapes, and how many of them were not
# fully covered by drawn metal before (and the uncovered area).

LAYERS = { 67 => "li1", 68 => "met1", 69 => "met2", 70 => "met3", 71 => "met4", 72 => "met5" }

ly = RBA::Layout::new
ly.read($in_gds)
names = ($cells && $cells != "") ? $cells.split(",") : [ly.top_cell.name]
total_added = 0
names.each do |cn|
  cell = ly.cell(cn) or raise "no cell #{cn} in #{$in_gds}"
  LAYERS.each do |ln, lname|
    lp = ly.find_layer(ln, 16)
    next unless lp
    ld = ly.layer(ln, 20)
    pins = []
    cell.shapes(lp).each { |s| pins << s.polygon if s.is_box? || s.is_polygon? || s.is_path? }
    next if pins.empty?
    uncovered = 0
    uarea = 0
    pins.each do |pg|
      pr = RBA::Region::new(pg)
      dr = RBA::Region::new(cell.begin_shapes_rec_touching(ld, pg.bbox))
      rest = pr - dr
      unless rest.is_empty?
        uncovered += 1
        uarea += rest.area
      end
    end
    pins.each { |pg| cell.shapes(ld).insert(pg) }
    total_added += pins.size
    printf("%-18s %-5s pin shapes %6d  not fully covered by %s.drawing before: %6d (%.4f um^2 uncovered)\n",
           cn, lname, pins.size, lname, uncovered, uarea * ly.dbu * ly.dbu)
  end
end
ly.write($out_gds)
puts "added #{total_added} shapes; wrote #{$out_gds}"
