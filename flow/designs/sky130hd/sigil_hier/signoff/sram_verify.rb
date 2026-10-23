# Check the OpenRAM macros in a merged GDS against the platform macro GDS:
# every cell of each macro (subcells renamed <macro>__<cell> by
# sram_gds_uniq.rb) must have the same bbox, shape count per layer and
# child instances. Also compares all other cells with a reference GDS.
# usage: klayout -b -rd merged=<gds> [-rd ref=<gds>] -r sram_verify.rb
P = "/OpenROAD-flow-scripts/flow/platforms/sky130ram"
ms = %w(sky130_sram_1rw1r_44x64_8 sky130_sram_1rw1r_64x256_8 sky130_sram_1rw1r_128x256_8)
def sig(ly, c)
  per = ly.layer_indexes.map { |li| i = ly.get_info(li); n = c.shapes(li).size; n > 0 ? "#{i.layer}/#{i.datatype}:#{n}" : nil }.compact.sort
  ch = []
  c.each_inst { |i| ch << "#{ly.cell(i.cell_index).name}@#{i.trans}x#{i.size}" }
  [c.bbox.to_s, per, ch.sort]
end
mg = RBA::Layout::new; mg.read($merged)
bad = 0
ms.each do |m|
  ly = RBA::Layout::new; ly.read("#{P}/#{m}/#{m}.gds")
  n = 0
  ly.each_cell do |c|
    name = c.name == m ? m : "#{m}__#{c.name}"
    mc = mg.cell(name)
    if !mc
      puts "MISSING #{name}"; bad += 1; next
    end
    a = sig(ly, c)
    b = sig(mg, mc)
    # child names in the merged copy carry the prefix
    a[2] = a[2].map { |s| s.start_with?(m) ? s : "#{m}__#{s}" }
    if a != b
      bad += 1
      puts "DIFF #{name}: #{a[0]} #{a[1].size} | #{b[0]} #{b[1].size}" if bad < 20
    end
    n += 1
  end
  puts "#{m}: #{n} cells compared"
end
puts "openram cells differing from the platform GDS: #{bad}"
if $ref
  rf = RBA::Layout::new; rf.read($ref)
  d = 0; k = 0
  mg.each_cell do |c|
    next if c.name =~ /\Asky130_sram_/
    r = rf.cell(c.name)
    next unless r
    k += 1
    if sig(mg, c) != sig(rf, r)
      d += 1
      puts "REFDIFF #{c.name}" if d < 10
    end
  end
  puts "non-OpenRAM cells compared with #{File.basename($ref)}: #{k}, differing #{d}"
end
