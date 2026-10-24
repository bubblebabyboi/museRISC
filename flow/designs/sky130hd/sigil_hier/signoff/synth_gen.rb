# synthetic LVS test of the pin-abstract black-box handling (two sky130hd
# inverters: inv1 drives pin a, inv2 pins b and c of an abstract macro;
# inv2's VPWR reaches VDD only through the macro's two vdd pads; vdd pad 1
# on VDD, pad 2 open). -rd dir=<out dir> -rd bad=0|1 (1: a/c labels swapped)
# -rd stdgds=<sky130_fd_sc_hd.gds> -rd stdcdl=<sky130hd.cdl>; then lvs_abstract.rb -rd lefs=synth.lef on synth.gds before LVS
ly = RBA::Layout::new
ly.read($stdgds)
li = ly.layer(67, 20); lit = ly.layer(67, 5); m1 = ly.layer(68, 20); m1t = ly.layer(68, 5)
b = lambda { |x1, y1, x2, y2| RBA::Box::new((x1 * 1000).round, (y1 * 1000).round, (x2 * 1000).round, (y2 * 1000).round) }
t = lambda { |s, x, y| RBA::Text::new(s, (x * 1000).round, (y * 1000).round) }
mac = ly.create_cell("sky130_sram_1rw1r_test")
# OpenRAM-style macro: pins on x/20 + x/16 with their texts on x/16; the two
# vdd pads joined by an internal met1 strap; some internal li
lip = ly.layer(67, 16); m1p = ly.layer(68, 16)
na, nc = ($bad == "1") ? ["c", "a"] : ["a", "c"]
[[0, na], [1, "b"], [2, nc]].each do |x, n|
  mac.shapes(li).insert(b.call(x, 0, x + 0.5, 0.5)); mac.shapes(lip).insert(b.call(x, 0, x + 0.5, 0.5))
  mac.shapes(lip).insert(t.call(n, x + 0.25, 0.25))
end
[0, 2].each do |x|
  mac.shapes(m1).insert(b.call(x, 3, x + 0.5, 3.5)); mac.shapes(m1p).insert(b.call(x, 3, x + 0.5, 3.5))
  mac.shapes(m1p).insert(t.call("vdd", x + 0.25, 3.25))
end
mac.shapes(m1).insert(b.call(0, 4, 2.5, 4.3)); mac.shapes(m1).insert(b.call(0, 3.4, 0.3, 4.3)); mac.shapes(m1).insert(b.call(2.2, 3.4, 2.5, 4.3))
sub = ly.create_cell("sky130_sram_1rw1r_test__internal")
sub.shapes(li).insert(b.call(0, 0, 0.2, 0.2))
mac.insert(RBA::CellInstArray::new(sub.cell_index, RBA::Trans::new(500, 1500)))
top = ly.create_cell("TOP")
inv = ly.cell("sky130_fd_sc_hd__inv_1")
top.insert(RBA::CellInstArray::new(inv.cell_index, RBA::Trans::new(10000, 10000)))
top.insert(RBA::CellInstArray::new(inv.cell_index, RBA::Trans::new(20000, 10000)))
top.insert(RBA::CellInstArray::new(mac.cell_index, RBA::Trans::new(12000, 3000)))
s = top.shapes(li)
# inv1 Y -> macro pin at x 12..12.5
s.insert(b.call(10.82, 10.9, 12.4, 11.1)); s.insert(b.call(12.1, 3.2, 12.4, 11.1))
# inv2 Y -> macro pin at x 14..14.5
s.insert(b.call(20.82, 10.9, 23.2, 11.1)); s.insert(b.call(23.0, 1.5, 23.2, 11.1))
s.insert(b.call(13.1, 1.5, 23.2, 1.7)); s.insert(b.call(14.1, 1.5, 14.4, 3.2)); s.insert(b.call(13.1, 1.5, 13.4, 3.2))
top.shapes(lit).insert(t.call("IN1", 10.45, 11.2)); top.shapes(lit).insert(t.call("IN2", 20.45, 11.2))
s = top.shapes(m1)
s.insert(b.call(10, 9.8, 21.38, 10.2))
# inv2's VPWR gets VDD only through the macro's vdd pin (pad 2 <-> pad 1 inside the macro)
s.insert(b.call(14, 6.0, 22.3, 6.3)); s.insert(b.call(22.0, 6.0, 22.3, 12.9)); s.insert(b.call(20, 12.5, 22.3, 12.9))
s.insert(b.call(8, 6.0, 8.3, 12.9)); s.insert(b.call(8, 12.5, 10, 12.9)); s.insert(b.call(8, 6.0, 12.5, 6.3))
top.shapes(m1t).insert(t.call("VDD", 10.5, 12.72)); top.shapes(m1t).insert(t.call("VSS", 10.5, 10.0))
keep = [top.cell_index]
ly.top_cells.each { |c| ly.delete_cell_rec(c.cell_index) unless keep.include?(c.cell_index) }
ly.write("#{$dir}/synth.gds")
File.write("#{$dir}/synth.cdl", <<~CDL + File.read($stdcdl))
  .SUBCKT sky130_sram_1rw1r_test a b c vdd
  .ENDS sky130_sram_1rw1r_test
  .SUBCKT TOP IN1 IN2 VDD VSS
  X1 IN1 VSS VSS NW1 VDD n1 sky130_fd_sc_hd__inv_1
  X2 IN2 VSS VSS NW2 VDD n2 sky130_fd_sc_hd__inv_1
  XM n1 n2 n2 VDD sky130_sram_1rw1r_test
  .ENDS TOP
CDL
File.write("#{$dir}/synth.lef", <<~LEF)
  MACRO sky130_sram_1rw1r_test
    ORIGIN 0 0 ;
    SIZE 3 BY 5 ;
    PIN #{na}
      PORT
        LAYER li1 ;
          RECT 0 0 0.5 0.5 ;
      END
    END #{na}
    PIN b
      PORT
        LAYER li1 ;
          RECT 1 0 1.5 0.5 ;
      END
    END b
    PIN #{nc}
      PORT
        LAYER li1 ;
          RECT 2 0 2.5 0.5 ;
      END
    END #{nc}
    PIN vdd
      PORT
        LAYER met1 ;
          RECT 0 3 0.5 3.5 ;
        LAYER met1 ;
          RECT 2 3 2.5 3.5 ;
      END
    END vdd
    OBS
      LAYER met1 ;
        RECT 0 4 2.5 4.3 ;
    END
  END sky130_sram_1rw1r_test
LEF
puts "wrote synth.gds / synth.cdl / synth.lef (bad=#{$bad})"
