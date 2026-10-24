# sigil: OpenRAM macro GDS metal vs. its LEF (pins + OBS), per routing layer.
#
# The router only sees the LEF. Metal of the macro GDS that is neither a LEF
# pin nor covered by a LEF OBS shape is invisible to it ("missing OBS"): the
# router may route over / through it, which in the GDS is a short or a
# spacing violation. Prints the missing area per layer and, with
# -rd out_lef=<file>, writes a copy of the LEF whose OBS section is
# replaced by the merged GDS metal of each layer minus the LEF pins
# (rectangles), i.e. an obstruction for every drawn shape that is not a pin.
#
# usage: klayout -b -rd gds=<macro.gds> -rd lef=<macro.lef> [-rd out_lef=<file>] -r sram_obs.rb

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


LAY = { "li1" => [67, 20], "met1" => [68, 20], "met2" => [69, 20], "met3" => [70, 20], "met4" => [71, 20] }
ly = RBA::Layout::new
ly.read($gds)
dbu = ly.dbu
top = ly.top_cell
geo = read_lef_geo($lef)[top.name] or raise "#{top.name} not in #{$lef}"
topoly = lambda { |pts| RBA::Polygon::new(pts.map { |x, y| RBA::Point::new((x / dbu).round, (y / dbu).round) }) }
newobs = {}
LAY.each do |lname, (ln, dt)|
  li = ly.find_layer(ln, dt)
  metal = li ? RBA::Region::new(top.begin_shapes_rec(li)).merged : RBA::Region::new
  pins = RBA::Region::new
  obs = RBA::Region::new
  geo.each do |pin, l, pts|
    next unless l == lname
    (pin ? pins : obs).insert(topoly.call(pts))
  end
  pins.merge
  obs.merge
  miss = metal - obs - pins
  printf("%-28s %-5s GDS %12.3f um^2  LEF pins %10.3f  LEF OBS %12.3f  missing (GDS - OBS - pins) %10.4f um^2 in %d polygons\n",
         top.name, lname, metal.area * dbu * dbu, pins.area * dbu * dbu, obs.area * dbu * dbu, miss.area * dbu * dbu, miss.count)
  newobs[lname] = metal - pins
end
if $out_lef
  out = []
  skipping = false
  File.foreach($lef) do |line|
    if line =~ /^\s*OBS\b/
      skipping = true
      out << "  OBS\n"
      LAY.each_key do |lname|
        r = newobs[lname]
        next if r.nil? || r.is_empty?
        out << "    LAYER #{lname} ;\n"
        r.decompose_trapezoids(RBA::Polygon::TD_htrapezoids).each do |p|
          b = p.bbox
          raise "non-rectangular piece #{p}" unless p.area == p.bbox.area
          out << format("      RECT %.3f %.3f %.3f %.3f ;\n", b.left * dbu, b.bottom * dbu, b.right * dbu, b.top * dbu)
        end
      end
      next
    end
    if skipping
      if line =~ /^\s*END\s*$/
        skipping = false
        out << "  END\n"
      end
      next
    end
    out << line
  end
  File.write($out_lef, out.join)
  puts "wrote #{$out_lef}"
end
