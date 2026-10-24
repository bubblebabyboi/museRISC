# sigil: at each pin of a hard-block instance, do the parent's drawn wire and
# the block's drawn wire touch (drawing purpose x/20 only, as on the mask)?
# Run on a GDS before pin_metal.rb to count the block pins that were joined
# only through the pin-purpose rectangle (x/16). Without a parent wire on the
# pin layer, parent vias on the pin are checked instead.
#
# usage: klayout -b -rd in_gds=<gds> -rd top=<cell> -rd blocks=<cell,cell> -r pin_gap.rb

ly = RBA::Layout::new
ly.read($in_gds)
top = ly.cell($top) or raise "no cell #{$top}"
blocks = $blocks.split(",")
res = Hash.new(0)
# parent shapes (top cell incl. its via cells and std cells, blocks excluded) touching a box
parent = lambda do |li, box|
  it = RBA::RecursiveShapeIterator::new(ly, top, li, box, false)
  it.unselect_cells(blocks.join(" ")) if blocks.size == 1
  blocks.each { |b| it.unselect_cells(b) } if blocks.size > 1
  RBA::Region::new(it)
end
top.each_inst do |inst|
  bc = inst.cell
  next unless blocks.include?(bc.name)
  tr = inst.trans
  (67..72).each do |ln|
    lp = ly.find_layer(ln, 16)
    ld = ly.find_layer(ln, 20)
    next unless lp && ld
    bc.shapes(lp).each do |s|
      next if s.is_text?
      pin = s.polygon.transformed(tr)
      bb = pin.bbox.enlarged(10, 10)
      par = parent.call(ld, bb).interacting(RBA::Region::new(pin))
      blk = RBA::Region::new(bc.begin_shapes_rec_touching(ld, s.bbox.enlarged(10, 10))).transformed(tr)
      blk = blk.interacting(RBA::Region::new(pin))
      key = "#{bc.name} L#{ln}"
      res["#{key} pins"] += 1
      if par.is_empty?
        # no parent wire on the pin layer: a parent via (below: (L-1)/44, above: L/44) on the pin?
        vias = RBA::Region::new
        [ln - 1, ln].each do |vl|
          vi = ly.find_layer(vl, 44)
          vias += parent.call(vi, bb) if vi
        end
        vias = vias.interacting(RBA::Region::new(pin))
        if vias.is_empty?
          res["#{key} no parent wire or via (unconnected at this level)"] += 1
        elsif vias.interacting(blk).is_empty?
          res["#{key} parent via only, not on block wire (open without the pin shape)"] += 1
        else
          res["#{key} parent via on block wire"] += 1
        end
      elsif blk.is_empty?
        res["#{key} no block wire"] += 1
      elsif par.interacting(blk).is_empty?
        res["#{key} parent and block wire do not touch (open without the pin shape)"] += 1
      else
        res["#{key} touching"] += 1
      end
    end
  end
end
res.sort.each { |k, v| puts "#{k}: #{v}" }
