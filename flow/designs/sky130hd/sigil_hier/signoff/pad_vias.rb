# sigil: parent via3 / met4 on given macro pin pads.
# -rd pads="<macro>:x,y;<macro>:x,y;..." or -rd pads_file=<file with that> (macro coordinates, um; e.g. the
# vdd texts that macro_supply.rb finds on a macro's gnd network). For every
# instance of those macros placed directly in <cell>: parent (non-macro)
# via3 / met4 shapes within 0.3 um of each point.
# usage: klayout -b -rd in_gds=<gds> -rd cell=sigil_cpu -rd pads=... -r pad_vias.rb
ly = RBA::Layout::new
ly.read($in_gds)
dbu = ly.dbu
top = ly.cell($cell)
pads = Hash.new { |h, k| h[k] = [] }
($pads || File.read($pads_file).strip).split(";").each { |e| m, xy = e.split(":"); x, y = xy.split(",").map(&:to_f); pads[m] << [x, y] }
excl = $exclude || "sky130_sram_1rw1r_*"
hits = 0
n = 0
top.each_inst do |inst|
  next unless pads.key?(inst.cell.name)
  pads[inst.cell.name].each do |x, y|
    p = inst.trans * RBA::Point::new((x / dbu).round, (y / dbu).round)
    box = RBA::Box::new(p, p).enlarged(300, 300)
    [[70, 44, "via3"], [71, 20, "met4"]].each do |ln, dt, nm|
      li = ly.find_layer(ln, dt)
      next unless li
      it = RBA::RecursiveShapeIterator::new(ly, top, li, box, false)
      it.unselect_cells(excl)
      c = RBA::Region::new(it).count
      hits += c
      puts "  #{inst.cell.name} #{inst.trans} pad (#{x},#{y}): #{c} parent #{nm}" if c > 0
    end
    n += 1
  end
end
puts "#{n} pads checked, #{hits} parent via3 / met4 shapes on them"
