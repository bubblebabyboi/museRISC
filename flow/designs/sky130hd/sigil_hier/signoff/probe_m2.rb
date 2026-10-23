# List the m2 (69/20) shapes touching a box (um) of a GDS, with their cell,
# instance path and polygon in top-cell coordinates (used on the m2.1 marker
# sites of the merged-GDS DRC).
# usage: klayout -b -rd in=<gds> -rd box=x1,y1,x2,y2 -r probe_m2.rb
ly = RBA::Layout::new
ly.read($in)
top = ly.top_cell
x1, y1, x2, y2 = $box.split(",").map { |v| v.to_f }
box = RBA::DBox::new(x1, y1, x2, y2)
li = ly.layer(69, 20)
it = top.begin_shapes_rec_touching(li, box)
while !it.at_end?
  path = it.path.map { |e| ly.cell(e.cell_inst.cell_index).name }.join("/")
  puts "#{ly.cell(it.cell_index).name} [#{path}] #{it.shape.polygon.transformed(it.trans).to_dtype(ly.dbu)}"
  it.next
end
