# Flatten device-less cells into their parent cells for KLayout LVS (same
# geometry, fewer cells): the router's via cells (VIA_*) and the
# sky130hd fill, tap and antenna-diode cells (no extracted devices).
# Kept as cells, each becomes a netlist circuit without devices whose
# pins are then purged instance by instance (db::Circuit::do_purge_nets
# searches the VDD / VSS net's ~10^5 subcircuit pins for every instance
# and pin): 5.8 h for the crypto block, days for the CPU block.
# Each parent's instance list is rebuilt once (Instance#flatten per
# instance is quadratic on cells with ~10^6 instances).
# usage: klayout -b -rd in=<gds> -rd out=<gds> [-rd pat=<ruby regexp>] -r flatvia.rb
# (Experiment: the signoff LVS instead flattens these circuits in the
# extracted netlist, sky130hd_sigil.lylvs -rd flatten=..., and checks the
# unmodified GDS; both gave the same result on the crypto block.)
ly = RBA::Layout::new
ly.read($in)
pat = Regexp::new($pat || '\AVIA_|\Asky130_fd_sc_hd__(fill|tapvpwrvgnd|diode)_')
via = {}
ly.each_cell do |c|
  next unless c.name =~ pat
  sh = []
  ly.layer_indexes.each { |li| sh << [li, c.shapes(li)] unless c.shapes(li).is_empty? }
  via[c.cell_index] = sh
end
n = 0
ly.each_cell do |c|
  next if via[c.cell_index]
  keep = []; flat = []
  c.each_inst { |i| (via[i.cell_index] ? flat : keep) << i.cell_inst.dup }
  next if flat.empty?
  c.clear_insts
  keep.each { |ci| c.insert(ci) }
  flat.each do |ci|
    sh = via[ci.cell_index]
    ci.each_cplx_trans do |t|
      sh.each { |li, s| c.shapes(li).insert(s, t) }
      n += 1
    end
  end
end
via.keys.each { |ci| ly.delete_cell(ci) }
ly.write($out)
puts "flatvia: #{via.size} cells matching #{pat.source}, #{n} placements flattened, wrote #{$out}"
