# Std-cell and via cells of a merged GDS vs the platform library: the
# merged cell's shapes must be k identical copies of the library cell's
# (k = number of merge inputs that define the cell): same set of
# distinct shapes per layer, and total = k x library total.
# usage: klayout -b -rd in=<merged gds> -rd lib=<sky130_fd_sc_hd.gds> -r gds_dupcheck.rb
def shapes_of(ly, c)
  h = {}
  ly.layer_indexes.each do |li|
    i = ly.get_info(li)
    c.shapes(li).each { |s| k = "#{i.layer}/#{i.datatype} #{s.to_s.sub(/ props=.*/, "")}"; h[k] = (h[k] || 0) + 1 }
  end
  h
end
ly = RBA::Layout::new; ly.read($in)
lib = RBA::Layout::new; lib.read($lib)
mult = Hash.new(0); bad = 0; n = 0; vias = 0
ly.each_cell do |c|
  if c.name =~ /\AVIA_/
    vias += 1
    h = shapes_of(ly, c)
    k = h.values.uniq
    if k.size == 1 then mult["via x#{k[0]}"] += 1 else bad += 1; puts "VIA uneven #{c.name} #{k.inspect}" end
    next
  end
  next unless c.name =~ /\Asky130_fd_sc_hd__/
  lc = lib.cell(c.name) or next
  n += 1
  a = shapes_of(ly, c); b = shapes_of(lib, lc)
  ta = a.values.sum; tb = b.values.sum
  k = ta / tb
  if a.keys.sort == b.keys.sort && ta == k * tb && a.all? { |key, v| v == k * b[key] }
    mult["std x#{k}"] += 1
  else
    bad += 1
    puts "DIFF #{c.name}: #{ta} vs library #{tb}" if bad < 20
  end
end
puts "std cells compared #{n}, via cells #{vias}; exact k-fold copies: #{mult.sort.map { |k, v| "#{k}: #{v}" }.join(", ")}; other: #{bad}"
