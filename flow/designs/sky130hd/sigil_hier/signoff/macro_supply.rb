# sigil: are the vdd and gnd networks of a stock OpenRAM macro joined?
#
# Connectivity of a macro GDS without device channels: metal, vias, li,
# licon to source / drain diffusion (diff minus poly), poly and taps; n-taps
# to their n-well, p-taps to one global substrate net. Source and drain of
# a transistor are separate nodes, so a net here is a DC path through
# conductors only. Labels: the macro's pin texts (x/16). Reports the nets
# that carry vdd and / or gnd pin texts, split into the texts on "mixed"
# squares (a vdd and a gnd LEF square overlapping, -rd lef=) and the others.
# If the net with the non-mixed vdd pads is also the net with the non-mixed
# gnd pads, the macro's supplies are shorted in its own layout.
#
# usage: klayout -b -rd gds=<macro.gds> -rd lef=<macro.lef> -r macro_supply.rb

ly = RBA::Layout::new
ly.read($gds)
dbu = ly.dbu
top = ly.top_cell
l2n = RBA::LayoutToNetlist::new(RBA::RecursiveShapeIterator::new(ly, top, []))
l2n.threads = 8
mk = lambda { |l, d, n| li = ly.find_layer(l, d); li ? l2n.make_polygon_layer(li, n) : l2n.make_polygon_layer(ly.layer(l, d), n) }
nwell = mk.call(64, 20, "nwell")
diff = mk.call(65, 20, "diff")
tap = mk.call(65, 44, "tap")
psdm = mk.call(94, 20, "psdm")
nsdm = mk.call(93, 44, "nsdm")
poly = mk.call(66, 20, "poly")
licon = mk.call(66, 44, "licon")
li = mk.call(67, 20, "li")
mcon = mk.call(67, 44, "mcon")
m1 = mk.call(68, 20, "m1"); via = mk.call(68, 44, "via")
m2 = mk.call(69, 20, "m2"); via2 = mk.call(69, 44, "via2")
m3 = mk.call(70, 20, "m3"); via3 = mk.call(70, 44, "via3")
m4 = mk.call(71, 20, "m4")
sd = diff - poly
l2n.register(sd, "sd")
ntap = (tap & nwell) & nsdm
ptap = (tap - nwell) & psdm
l2n.register(ntap, "ntap")
l2n.register(ptap, "ptap")
[[licon, sd], [licon, poly], [licon, ntap], [licon, ptap], [licon, li], [li, mcon], [mcon, m1],
 [m1, via], [via, m2], [m2, via2], [via2, m3], [m3, via3], [via3, m4], [ntap, nwell]].each { |a, b| l2n.connect(a, b) }
[sd, poly, ntap, ptap, li, m1, m2, m3, m4, nwell].each { |a| l2n.connect(a) }
l2n.connect_global(ptap, "SUBSTRATE")
txt = {}
[[67, li], [68, m1], [69, m2], [70, m3], [71, m4]].each do |ln, ml|
  t = ly.find_layer(ln, 16)
  next unless t
  tl = l2n.make_text_layer(t, "t#{ln}")
  l2n.connect(ml, tl)
  txt[ln] = [t, ml]
end
l2n.extract_netlist

# mixed squares from the LEF (vdd / gnd met3 squares overlapping one of the other pin)
sq = Hash.new { |h, k| h[k] = RBA::Region::new }
pin = layer = nil
File.foreach($lef) do |line|
  t = line.split
  next if t.empty?
  case t[0]
  when "PIN" then pin = t[1]
  when "OBS" then pin = nil
  when "LAYER" then layer = t[1]
  when "RECT"
    next unless pin && layer == "met3" && %w[vdd gnd].include?(pin)
    a, b, c, d = t[1, 4].map { |v| (v.to_f / dbu).round }
    sq[pin].insert(RBA::Box::new([a, c].min, [b, d].min, [a, c].max, [b, d].max))
  end
end
mixed = sq["vdd"].interacting(sq["gnd"]) + sq["gnd"].interacting(sq["vdd"])
stat = Hash.new { |h, k| h[k] = Hash.new(0) }
pos = {}
txt.each do |ln, (t, ml)|
  top.shapes(t).each do |s|
    next unless s.is_text? && %w[vdd gnd].include?(s.text_string)
    p = s.text.position
    net = l2n.probe_net(ml, RBA::DPoint::new(p.x * dbu, p.y * dbu))
    next unless net
    kind = mixed.interacting(RBA::Region::new(RBA::Box::new(p, p).enlarged(1, 1))).is_empty? ? "" : "mixed "
    stat[net.cluster_id]["#{kind}#{s.text_string}"] += 1
    (pos[net.cluster_id] ||= []) << [kind + s.text_string, p.x * dbu, p.y * dbu]
  end
end
# texts of one supply sitting on the network that carries most texts of the other
main = {}
%w[vdd gnd].each { |n| main[n] = stat.max_by { |_, h| h[n] }&.first }
%w[vdd gnd].each do |n|
  o = n == "vdd" ? "gnd" : "vdd"
  next unless main[o]
  (pos[main[o]] || []).select { |k, _, _| k == n }.each { |k, x, y| puts "  #{n} text at (#{x.round(3)}, #{y.round(3)}) is on the #{o} network" }
end
puts "#{top.name}: #{mixed.count} mixed squares"
stat.sort_by { |_, h| -h.values.sum }.first(12).each { |id, h| puts "  net #{id}: #{h.sort.map { |k, v| "#{k} #{v}" }.join(', ')}" }
puts "  (#{stat.size} nets carry vdd / gnd texts)"
