# sigil: metal-only connectivity around each macro instance (macro content +
# parent routing), to find nets that join two different macro pins.
#
# For every instance of the LEF macros placed directly in <cell>, the full
# GDS content (macro and parent, met1..met5 and via..via4; -rd li=1 adds li1
# and mcon) inside the macro's bounding box (+2 um) is flattened into a
# scratch layout and its nets are extracted (KLayout LayoutToNetlist, no
# devices). The macro's pin texts (OpenRAM: on x/16 in the macro's top cell)
# name the nets. A net carrying two different macro pin names joins those
# pins through metal: inside an OpenRAM macro that never happens (the
# pins are separate nets), so it is a short made by the parent's routing.
# Reported per instance: the shorted pin-name groups and, for each, the
# parent shapes (non-macro) that are part of that net.
#
# usage: klayout -b -rd in_gds=<gds> -rd cell=sigil_cpu -rd macros=<m1,m2,...> [-rd li=1] -r macro_short.rb
#        klayout -b -rd in_gds=<macro.gds> -rd cell=<macro> -rd standalone=1 -r macro_short.rb  (control)

COND = [[68, 20, "met1"], [68, 44, "via"], [69, 20, "met2"], [69, 44, "via2"], [70, 20, "met3"],
        [70, 44, "via3"], [71, 20, "met4"], [71, 44, "via4"], [72, 20, "met5"]]
COND.unshift([67, 20, "li1"], [67, 44, "mcon"]) if $li == "1"
CHAIN = COND.map { |c| c[2] }
TXT = { 67 => "li1", 68 => "met1", 69 => "met2", 70 => "met3", 71 => "met4", 72 => "met5" }

ly = RBA::Layout::new
ly.read($in_gds)
dbu = ly.dbu
top = ly.cell($cell) or raise "no cell #{$cell}"
macros = ($macros || "").split(",")
excl = $exclude || "sky130_sram_1rw1r_*"
grand = 0
# -rd standalone=1: <cell> is a macro GDS's own top cell (control run, no parent)
targets = []
if $standalone == "1"
  targets << [top, RBA::Trans::new]
else
  top.each_inst { |inst| targets << [inst.cell, inst.trans] if macros.include?(inst.cell.name) }
end
targets.each do |mc, tr|
  box = mc.bbox.transformed(tr).enlarged(2000, 2000)
  sl = RBA::Layout::new
  sl.dbu = dbu
  sc = sl.create_cell("clip")
  lidx = {}
  par = {}
  COND.each do |ln, dt, nm|
    src = ly.find_layer(ln, dt)
    lidx[nm] = sl.layer(ln, dt)
    next unless src
    it = RBA::RecursiveShapeIterator::new(ly, top, src, box, false)
    reg = RBA::Region::new(it)
    sc.shapes(lidx[nm]).insert(reg)
    pit = RBA::RecursiveShapeIterator::new(ly, top, src, box, false)
    pit.unselect_cells(excl)
    par[nm] = RBA::Region::new(pit)
  end
  # macro pin texts -> label layers (x/5)
  ntext = 0
  TXT.each do |ln, nm|
    t16 = ly.find_layer(ln, 16)
    next unless t16
    tl = sl.layer(ln, 5)
    mc.shapes(t16).each do |s|
      next unless s.is_text?
      sc.shapes(tl).insert(s.text.transformed(tr))
      ntext += 1
    end
  end
  l2n = RBA::LayoutToNetlist::new(RBA::RecursiveShapeIterator::new(sl, sc, []))
  ml = {}
  CHAIN.each { |nm| ml[nm] = l2n.make_layer(lidx[nm], nm) }
  CHAIN.each_cons(2) { |a, b| l2n.connect(ml[a], ml[b]) }
  CHAIN.each { |nm| l2n.connect(ml[nm]) }
  TXT.each do |ln, nm|
    next unless ml[nm]
    tl = l2n.make_text_layer(sl.layer(ln, 5), "#{nm}_txt")
    l2n.connect(ml[nm], tl)
  end
  l2n.extract_netlist
  c = l2n.netlist.circuit_by_name("clip")
  shorts = []
  nnets = 0
  c.each_net do |n|
    nnets += 1
    names = (n.name || "").split(",").uniq
    shorts << [n, names] if names.size > 1
  end
  # how many vdd / gnd pin texts each net holds (supply networks: one net each, unless joined)
  sup = Hash.new { |h, k| h[k] = Hash.new(0) }
  TXT.each do |ln, nm|
    next unless ml[nm]
    sc.shapes(sl.layer(ln, 5)).each do |s|
      next unless s.is_text? && %w[vdd gnd].include?(s.text_string)
      net = l2n.probe_net(ml[nm], RBA::DPoint::new(s.text.x * dbu, s.text.y * dbu))
      sup[net ? net.cluster_id : -1][s.text_string] += 1 if net
    end
  end
  sup.select { |_, h| h["vdd"] > 0 && h["gnd"] > 0 }.each { |id, h| puts "  supply net #{id}: #{h['vdd']} vdd + #{h['gnd']} gnd pin texts" }
  tv = sup.values.sum { |h| h["vdd"] }; tg = sup.values.sum { |h| h["gnd"] }
  puts "  vdd texts #{tv} in #{sup.count { |_, h| h['vdd'] > 0 }} nets, gnd texts #{tg} in #{sup.count { |_, h| h['gnd'] > 0 }} nets"
  grand += shorts.size
  puts "#{mc.name} at #{tr.disp.to_s} (#{(tr.disp.x * dbu).round(2)},#{(tr.disp.y * dbu).round(2)}): #{ntext} pin texts, #{nnets} nets, #{shorts.size} nets joining different macro pins"
  shorts.first(40).each do |n, names|
    shown = names.size > 8 ? names.first(8).join(",") + ",... (#{names.size} names)" : names.join(",")
    pp = []
    CHAIN.each do |nm|
      next unless par[nm] && !par[nm].is_empty?
      sh = l2n.shapes_of_net(n, ml[nm], true)
      hit = par[nm].interacting(sh)
      hit.each { |p| pp << "#{nm} #{p.bbox.transformed(RBA::CplxTrans::new(dbu))}" }
    end
    puts "  short: #{shown}; parent shapes in the net: #{pp.size}"
    pp.first(4).each { |s| puts "     #{s}" }
  end
end
puts "TOTAL nets joining different macro pins: #{grand}"
