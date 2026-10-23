# Bounding boxes of a GDS: top cell, its instances, and the OpenRAM
# instances inside them (top coordinates, um).
# usage: klayout -b -rd in=<gds> -r gds_bbox.rb
ly = RBA::Layout::new
ly.read($in)
top = ly.top_cell
puts "top #{top.name} bbox #{top.dbbox}"
top.each_inst do |i|
  c = ly.cell(i.cell_index)
  next if c.name =~ /\Asky130_fd_sc_hd__|\AVIA_/
  puts "inst #{c.name} trans #{i.dcplx_trans} bbox #{i.dbbox}"
  c.each_inst do |j|
    cj = ly.cell(j.cell_index)
    next unless cj.name =~ /sram/
    puts "   sub #{cj.name} trans #{(i.dcplx_trans * j.dcplx_trans)} bbox #{j.dbbox.transformed(i.dcplx_trans)} cellbbox #{cj.dbbox}"
  end
end
ly.top_cells.each { |t| puts "top_cells: #{t.name}" }
