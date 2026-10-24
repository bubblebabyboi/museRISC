# sigil: parent metal vs. macro-internal metal (the part of the macro that the
# LVS pin abstracts of lvs_abstract.rb leave out).
#
# For every instance of the LEF macros placed directly in <cell>: the parent's shapes
# (everything under <cell> except the macro subtrees, i.e. std cells, routing,
# PDN, fill) inside the macro's bounding box, per conductor layer, against
# the macro's own drawn shapes (full GDS content):
#   overlap      area of parent AND macro metal (positive-area contact)
#   off-pin      the part of that overlap outside the macro's LEF pin shapes
#   bad touches  parent polygons that touch or overlap macro metal but no LEF
#                pin of the layer (a contact to macro metal that is not a pin)
# A parent wire landing on a pin overlaps the macro's metal inside the pin
# shape only; anything off-pin or a bad touch would be a contact LVS of the
# abstract copy cannot see.
#
# usage: klayout -b -rd in_gds=<gds> -rd cell=sigil_cpu -rd lefs=<a.lef,...> [-rd exclude=sky130_sram_1rw1r_*] -r macro_overlap.rb
#   exclude: glob of the macro cells and their (prefixed) subcells

# minimal LEF reader: MACRO -> [[pin, layer, [[x, y], ...]], ...] (um)
def read_lef_pins(path)
  macros = {}
  macro = pin = layer = nil
  in_port = false
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
    when "OBS" then pin = nil; in_port = false
    when "END"
      if t[1] == pin then pin = nil; in_port = false
      elsif t[1].nil? then in_port = false
      elsif t[1] == macro then macro = nil
      end
    when "LAYER" then layer = t[1]
    when "RECT", "POLYGON"
      next unless macro && pin && in_port
      v = t[1..-1].reject { |x| x == ";" || x =~ /^MASK/ }.map(&:to_f)
      pts = v.each_slice(2).to_a
      pts = [[pts[0][0], pts[0][1]], [pts[1][0], pts[0][1]], [pts[1][0], pts[1][1]], [pts[0][0], pts[1][1]]] if t[0] == "RECT"
      macros[macro] << [pin, layer, pts]
    end
  end
  macros
end

LAYERS = [[67, 20, "li1"], [67, 44, "mcon"], [68, 20, "met1"], [68, 44, "via"], [69, 20, "met2"],
          [69, 44, "via2"], [70, 20, "met3"], [70, 44, "via3"], [71, 20, "met4"], [71, 44, "via4"], [72, 20, "met5"]]
LEFL = { "li1" => 67, "met1" => 68, "met2" => 69, "met3" => 70, "met4" => 71, "met5" => 72 }

ly = RBA::Layout::new
ly.read($in_gds)
dbu = ly.dbu
top = ly.cell($cell) or raise "no cell #{$cell}"
pins = {}
$lefs.split(",").each { |f| pins.merge!(read_lef_pins(f)) }

# the macro instances directly under top (with their transformation)
insts = []
top.each_inst { |i| insts << [i.cell, i.trans] if pins.key?(i.cell.name) }
excl = $exclude || "sky130_sram_1rw1r_*"
puts "#{insts.size} macro instances under #{$cell}"

tot = Hash.new(0)
insts.each do |mc, tr|
  box = mc.bbox.transformed(tr)
  LAYERS.each do |ln, dt, lname|
    li = ly.find_layer(ln, dt)
    next unless li
    pit = RBA::RecursiveShapeIterator::new(ly, top, li, box, false)
    pit.unselect_cells(excl)
    par = RBA::Region::new(pit)
    next if par.is_empty?
    mac = RBA::Region::new(mc.begin_shapes_rec(li)).transformed(tr)
    pr = RBA::Region::new
    if dt == 20
      pins[mc.name].each do |pn, lname2, pts|
        next unless LEFL[lname2] == ln
        pr.insert(RBA::Polygon::new(pts.map { |x, y| RBA::Point::new((x / dbu).round, (y / dbu).round) }).transformed(tr))
      end
    end
    ov = par & mac
    off = ov - pr
    touching = par.interacting(mac)
    bad = pr.is_empty? ? touching : touching.not_interacting(pr)
    oa = ov.area * dbu * dbu
    fa = off.area * dbu * dbu
    tot["#{lname} overlap"] += oa
    tot["#{lname} off-pin"] += fa
    tot["#{lname} bad"] += bad.count
    if fa > 0 || bad.count > 0
      printf("%-30s %s %-5s parent %8d  overlap %10.4f  off-pin %10.4f um^2  bad touches %d\n",
             mc.name, tr.disp.to_s, lname, par.count, oa, fa, bad.count)
      bad.each.first(5).each { |p| puts "    bad: #{p.bbox.transformed(RBA::CplxTrans::new(dbu))}" }
    end
  end
end
puts "TOTAL (all instances):"
LAYERS.each { |_, _, n| printf("  %-5s overlap %10.4f um^2  off-pin %10.4f um^2  bad touches %d\n", n, tot["#{n} overlap"], tot["#{n} off-pin"], tot["#{n} bad"]) }
