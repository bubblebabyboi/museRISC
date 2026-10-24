# sigil: routing obstructions for the OpenRAM macro metal that the macros'
# LEF does not declare, for a re-route of the block that places them.
#
# The OpenRAM LEFs shipped with ORFS (platforms/sky130ram) obstruct only
# part of the macros' metal (sram_obs.rb: per macro 1.0-5.1k um^2 of met1,
# 0.6-2.6k of met2, 0.9-5.9k of met3 and all 0.4-1.9k of met4 are neither
# a LEF pin nor a LEF OBS shape). The router cannot see that metal; the
# CPU block's routing touches it (macro_short.rb). For every instance of
# the LEF macros placed directly in <cell> this writes, in the cell's
# coordinates (DBU = GDS database units), the rectangles of
#   macro GDS metal - LEF OBS - LEF pins      (met1..met4)
# as an OpenROAD Tcl list:  set sigil_sram_obs { {met1 x1 y1 x2 y2} ... }
# (drt_reroute_obs.tcl turns them into block obstructions).
#
# usage: klayout -b -rd in_gds=<block gds> -rd cell=sigil_cpu -rd lefs=<a.lef,...> -rd out_tcl=<file> -r sram_missing_obs.rb

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



LAY = { "met1" => [68, 20], "met2" => [69, 20], "met3" => [70, 20], "met4" => [71, 20] }
ly = RBA::Layout::new
ly.read($in_gds)
dbu = ly.dbu
top = ly.cell($cell) or raise "no cell #{$cell}"
geo = {}
$lefs.split(",").each { |f| geo.merge!(read_lef_geo(f)) }
topoly = lambda { |pts| RBA::Polygon::new(pts.map { |x, y| RBA::Point::new((x / dbu).round, (y / dbu).round) }) }
# per master: missing region per layer (master coordinates)
miss = {}
File.open($out_tcl, "w") do |f|
  f.puts "# #{File.basename(__FILE__)}: #{$in_gds} cell #{$cell}"
  f.puts "set sigil_sram_obs {"
  n = 0
  top.each_inst do |inst|
    mc = inst.cell
    next unless geo.key?(mc.name)
    miss[mc.name] ||= LAY.map do |lname, (ln, dt)|
      li = ly.find_layer(ln, dt)
      metal = li ? RBA::Region::new(mc.begin_shapes_rec(li)).merged : RBA::Region::new
      lef = RBA::Region::new
      sigpins = RBA::Region::new
      geo[mc.name].each do |pin, l, pts|
        next unless l == lname
        lef.insert(topoly.call(pts))
        sigpins.insert(topoly.call(pts)) if pin && !%w[vdd gnd].include?(pin)
      end
      r = metal - lef
      # missing metal touching a signal pin on the same layer is that pin's
      # own wire (e.g. the clk0 / clk1 stubs): not an obstruction, the router
      # reaches the pin through it (DRT reported its access as shorts with
      # the obstruction). Pieces touching vdd / gnd pins stay obstructions
      # (they are the macros' supply rails).
      own = r.interacting(sigpins)
      r -= own
      puts "#{mc.name} #{lname}: #{own.count} missing pieces (#{(own.area * dbu * dbu).round(3)} um^2) touch a signal pin: not obstructed" if own.count > 0
      rects = []
      r.decompose_trapezoids(RBA::Polygon::TD_htrapezoids).each do |p|
        raise "#{mc.name} #{lname}: non-rectangular piece #{p}" unless p.area == p.bbox.area
        rects << p.bbox
      end
      puts "#{mc.name} #{lname}: #{(r.area * dbu * dbu).round(3)} um^2 missing, #{rects.size} rectangles"
      [lname, rects]
    end
    tr = inst.trans
    miss[mc.name].each do |lname, rects|
      rects.each do |b|
        bb = b.transformed(tr)
        f.puts "{#{lname} #{bb.left} #{bb.bottom} #{bb.right} #{bb.top}}"
        n += 1
      end
    end
    puts "#{mc.name} at #{tr}: done"
  end
  f.puts "}"
  puts "wrote #{n} rectangles to #{$out_tcl}"
end
