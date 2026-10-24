# sigil: spacing between a block's routing and the OpenRAM macros' own metal.
#
# The KLayout DRC of the merged GDS is run with the OpenRAM macro cells
# left out (their stock content gives millions of markers against the
# logic rules), so it does not see the parent routing next to macro metal.
# This checks that interface directly: for every instance of the LEF macros
# placed directly in <cell>, per layer met1..met4, the parent's shapes
# (everything under <cell> except the macro subtrees) against the macro's
# metal polygons that do not touch a LEF pin of that layer (pin-net metal,
# which the parent connects to, is left out): edge pairs closer than the
# minimum spacing (met1.2 / met2.2 0.14 um, met3.2 / met4.2 0.3 um) and
# parent polygons touching such metal.
#
# usage: klayout -b -rd in_gds=<gds> -rd cell=sigil_cpu -rd lefs=<a.lef,...> [-rd exclude=sky130_sram_1rw1r_*] -r macro_space.rb

# minimal LEF reader: MACRO -> [[pin or nil (OBS), layer, [[x, y], ...]], ...] (um)
def read_lef_geo(path)
  macros = {}
  macro = pin = layer = nil
  in_port = false
  in_obs = false
  stmt = ""
  File.foreach(path) do |raw|
    line = raw.sub(/#.*/, "").strip
    next if line.empty?
    stmt = stmt.empty? ? line : "#{stmt} #{line}"
    next unless stmt.end_with?(";") || stmt =~ /^(MACRO|PIN|PORT|END|OBS)\b/
    t = stmt.split
    stmt = ""
    case t[0]
    when "MACRO" then macro = t[1]; macros[macro] = []; pin = nil
    when "ORIGIN"
      raise "#{path} #{macro}: ORIGIN #{t[1]} #{t[2]} not supported" if macro && (t[1].to_f != 0 || t[2].to_f != 0)
    when "PIN" then pin = t[1]
    when "PORT" then in_port = true if pin
    when "OBS" then pin = nil; in_port = false; in_obs = true
    when "END"
      if t[1] == pin then pin = nil; in_port = false
      elsif t[1].nil? then in_port = false; in_obs = false
      elsif t[1] == macro then macro = nil
      end
    when "LAYER" then layer = t[1]
    when "RECT", "POLYGON"
      next unless macro && ((pin && in_port) || in_obs)
      v = t[1..-1].reject { |x| x == ";" || x =~ /^MASK/ }.map(&:to_f)
      pts = v.each_slice(2).to_a
      pts = [[pts[0][0], pts[0][1]], [pts[1][0], pts[0][1]], [pts[1][0], pts[1][1]], [pts[0][0], pts[1][1]]] if t[0] == "RECT"
      macros[macro] << [in_obs ? nil : pin, layer, pts]
    end
  end
  macros
end



RULES = [[68, "met1", 0.14], [69, "met2", 0.14], [70, "met3", 0.3], [71, "met4", 0.3]]
ly = RBA::Layout::new
ly.read($in_gds)
dbu = ly.dbu
top = ly.cell($cell) or raise "no cell #{$cell}"
geo = {}
$lefs.split(",").each { |f| geo.merge!(read_lef_geo(f)) }
excl = $exclude || "sky130_sram_1rw1r_*"
tot = Hash.new(0)
top.each_inst do |inst|
  mc = inst.cell
  next unless geo.key?(mc.name)
  tr = inst.trans
  box = mc.bbox.transformed(tr).enlarged(1000, 1000)
  RULES.each do |ln, lname, d|
    li = ly.find_layer(ln, 20)
    next unless li
    pit = RBA::RecursiveShapeIterator::new(ly, top, li, box, false)
    pit.unselect_cells(excl)
    par = RBA::Region::new(pit)
    next if par.is_empty?
    mac = RBA::Region::new(mc.begin_shapes_rec(li)).merged.transformed(tr)
    pins = RBA::Region::new
    geo[mc.name].each do |pin, l, pts|
      next unless pin && l == lname
      pins.insert(RBA::Polygon::new(pts.map { |x, y| RBA::Point::new((x / dbu).round, (y / dbu).round) }).transformed(tr))
    end
    other = mac.not_interacting(pins)
    sep = par.separation_check(other, (d / dbu).round)
    touch = par.interacting(other)
    tot["#{lname} spacing"] += sep.count
    tot["#{lname} touch"] += touch.count
    if sep.count > 0 || touch.count > 0
      printf("%-30s %-18s %-5s spacing < %.2f: %5d   touching non-pin macro metal: %5d\n", mc.name, tr.to_s, lname, d, sep.count, touch.count)
      sep.each.first(3).each { |e| puts "    #{e.bbox.transformed(RBA::CplxTrans::new(dbu))}" }
    end
  end
end
puts "TOTAL:"
RULES.each { |_, n, d| printf("  %-5s spacing < %.2f um: %d   touching: %d\n", n, d, tot["#{n} spacing"], tot["#{n} touch"]) }
