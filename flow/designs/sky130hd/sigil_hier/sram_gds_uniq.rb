# Copy of an OpenRAM macro GDS whose subcells carry the macro name as a
# prefix (<macro>__<cell>); the macro (top) cell keeps its name.
#
# Why: the three sky130 OpenRAM GDS files (platforms/sky130ram) share 134
# subcell names, 62 of them with different contents (bank, bitcell_array,
# port_address, data_dff, pinv_*, contact_*, ...). ORFS's GDS merge
# (util/def2stream.py) reads all inputs into one layout, where KLayout
# adds the contents of same-named cells together (cell conflict
# resolution AddToCell), so every macro in the merged GDS ends up with
# the union of the three variants' subcells: the 44x64 macro's cell
# grows from 445 x 237 um to 971 x 916 um and overlaps its neighbours.
# Reading these copies instead keeps each macro intact.
#
# usage: klayout -zz -rd in=<macro>.gds -rd out=<copy>.gds -r sram_gds_uniq.rb
ly = RBA::Layout::new
ly.read($in)
tops = ly.top_cells
raise "sram_gds_uniq: #{$in} has #{tops.size} top cells" unless tops.size == 1
top = tops[0]
n = 0
ly.each_cell do |c|
  next if c.cell_index == top.cell_index
  c.name = "#{top.name}__#{c.name}"
  n += 1
end
ly.write($out)
puts "sram_gds_uniq: #{top.name}: #{n} subcells renamed -> #{$out}"
