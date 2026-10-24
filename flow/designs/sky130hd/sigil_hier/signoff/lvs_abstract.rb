# sigil: LVS-only copy of a GDS with macros replaced by their LEF pin abstracts.
#
# The OpenRAM macros are black boxes in LVS (their schematic is a pin-only
# stub, the macro's .lvs.sp top .SUBCKT line). This writes a copy of the
# layout in which each macro named in the given LEF files keeps only its
# LEF pins: every PIN PORT RECT / POLYGON as drawn metal (li1 / met1..met5
# -> 67..72 / 20) with a label of the pin name at its centre (x/5, the
# label layer the LVS deck reads); all other content of the cell and its
# subcells are removed. The LEF pins are what the router connected to.
# A pin with several shapes (the ~1000 met3 vdd / gnd pads of a macro,
# joined inside the macro by its own metal) is kept as one net by private
# join layers that only the sigil LVS deck reads (-rd abstract=...): a
# copy of each piece on (L+140) / k (L = its layer 67..72 -> 207..212) and one bar
# over the cell on 213 / k, k = 1, 2, ... per multi-shape pin; the deck
# connects metal L <-> (L+140) / k <-> 213 / k. (KLayout's connect_implicit /
# connect_explicit in a non-top cell are "must-connect" nets: they require
# the parent to join every piece.)
# Shorts between parent routing and macro metal other than the pins are not
# visible in an LVS of this copy; macro_overlap.rb checks for them.
#
# usage: klayout -b -rd in_gds=<gds> -rd out_gds=<gds> -rd lefs=<a.lef,b.lef> -r lvs_abstract.rb

LEFLAYER = { "li1" => 67, "met1" => 68, "met2" => 69, "met3" => 70, "met4" => 71, "met5" => 72 }
MAXJOIN = 4

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

ly = RBA::Layout::new
ly.read($in_gds)
dbu = ly.dbu
$lefs.split(",").each do |lef|
  read_lef_pins(lef).each do |cn, pins|
    cell = ly.cell(cn)
    unless cell
      puts "#{cn} (#{File.basename(lef)}): not in layout"
      next
    end
    bbox = cell.bbox
    nsub = 0
    cell.each_child_cell { nsub += 1 }
    cell.prune_subcells
    cell.clear_shapes
    skipped = 0
    byname = Hash.new { |h, k| h[k] = [] }
    # LEF pin shapes that overlap / touch a shape of another pin on the same
    # layer (the stock OpenRAM macros' "mixed" vdd / gnd columns: a vdd and a
    # gnd 0.49 um square offset by 0.06 um) are left out unless -rd
    # keep_mixed=1: drawn as metal they would join the two pins in the
    # abstract. The parent must not connect to them (mixed_pads.rb counts
    # its vias on them); the macro's own metal there is the upstream macro's.
    polys = pins.map { |name, lname, pts| [name, lname, LEFLAYER[lname] && RBA::Polygon::new(pts.map { |x, y| RBA::Point::new((x / dbu).round, (y / dbu).round) })] }
    mixed = {}
    if $keep_mixed != "1"
      polys.group_by { |_, l, _| l }.each do |l, ps|
        ps = ps.select { |_, _, pg| pg }
        byn = ps.group_by(&:first)
        byn.each do |n, own|
          others = RBA::Region::new
          ps.each { |n2, _, pg| others.insert(pg) if n2 != n }
          own.each { |_, _, pg| mixed[pg.object_id] = true unless others.interacting(RBA::Region::new(pg)).is_empty? } if byn.size > 1
        end
      end
    end
    nmixed = 0
    polys.each do |name, lname, pg|
      ln = LEFLAYER[lname]
      unless ln
        skipped += 1
        next
      end
      if mixed[pg.object_id]
        nmixed += 1
        next
      end
      cell.shapes(ly.layer(ln, 20)).insert(pg)
      c = pg.bbox.center
      cell.shapes(ly.layer(ln, 5)).insert(RBA::Text::new(name, c.x, c.y))
      byname[name] << [ln, pg]
    end
    multi = byname.select { |_, v| v.size > 1 }.sort_by { |n, v| [-v.size, n] }
    raise "#{cn}: #{multi.size} multi-shape pins > #{MAXJOIN}" if multi.size > MAXJOIN
    multi.each_with_index do |(name, ps), i|
      k = i + 1
      ps.each { |ln, pg| cell.shapes(ly.layer(ln + 140, k)).insert(pg) }
      cell.shapes(ly.layer(213, k)).insert(bbox)
      puts "  #{cn}: join #{k} = #{name}: #{ps.size} shapes on layer(s) #{ps.map(&:first).uniq.sort.join('/')}"
    end
    puts "#{cn}: #{nsub} child cells pruned; abstract from #{File.basename(lef)}: #{byname.size} pins, " \
         "#{pins.size - skipped - nmixed} shapes (#{skipped} on non-metal layers, #{nmixed} overlapping another pin's shape left out), #{multi.size} multi-shape pins"
  end
end
ly.cleanup
ly.write($out_gds)
puts "wrote #{$out_gds}"
