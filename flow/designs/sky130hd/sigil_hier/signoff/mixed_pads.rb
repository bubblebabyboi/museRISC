# sigil: parent via3 on the OpenRAM macros' "mixed" pin squares.
#
# In the stock OpenRAM LEF / GDS (platforms/sky130ram) some met3 vdd pin
# squares overlap a gnd pin square (0.49 um squares offset by 0.06 um; 132 /
# 260 / 516 pairs in the 44x64 / 64x256 / 128x256 macros). A parent power
# via on one of them would join the parent's VDD and VSS through the macro
# metal. Counts, per macro instance placed directly in <cell>, the mixed
# squares and the parent via3 shapes on them.
#
# usage: klayout -b -rd in_gds=<gds> -rd cell=sigil_cpu -rd lefs=<a.lef,...> -r mixed_pads.rb

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


ly = RBA::Layout::new
ly.read($in_gds)
dbu = ly.dbu
top = ly.cell($cell)
geo = {}
$lefs.split(",").each { |f| geo.merge!(read_lef_geo(f)) }
v3 = ly.find_layer(70, 44)
top.each_inst do |inst|
  mc = inst.cell
  next unless geo.key?(mc.name)
  sq = Hash.new { |h, k| h[k] = RBA::Region::new }
  geo[mc.name].each do |pin, l, pts|
    next unless pin && l == "met3" && %w[vdd gnd].include?(pin)
    sq[pin].insert(RBA::Polygon::new(pts.map { |x, y| RBA::Point::new((x / dbu).round, (y / dbu).round) }))
  end
  mixed_v = sq["vdd"].interacting(sq["gnd"]).transformed(inst.trans)
  mixed_g = sq["gnd"].interacting(sq["vdd"]).transformed(inst.trans)
  it = RBA::RecursiveShapeIterator::new(ly, top, v3, mc.bbox.transformed(inst.trans), false)
  it.unselect_cells("sky130_sram_1rw1r_*")
  vias = RBA::Region::new(it)
  puts "#{mc.name} #{inst.trans}: mixed vdd squares #{mixed_v.count}, gnd #{mixed_g.count}; parent via3 over the macro #{vias.count}, on mixed squares #{vias.interacting(mixed_v + mixed_g).count}"
end
