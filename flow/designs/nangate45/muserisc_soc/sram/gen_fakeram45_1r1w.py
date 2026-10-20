#!/usr/bin/env python3
"""Generate a 1R1W (one read port, one write port) fakeram45 macro.

ORFS ships only single-port (1RW) fakeram45 views for Nangate45
(flow/platforms/nangate45/{lef,lib}/fakeram45_*), and no 256x64
size. The vector register file needs a simple-dual-port 256x64 RAM
with byte write enables (muserisc_vrf_bank), so this script writes
LEF/Liberty/behavioural-Verilog views of a 1R1W macro in the same
style as the bsg_fakeram-generated fakeram45 views: signal pins on
metal3 along the left edge (0.28 um pitch), alternating VSS/VDD
metal4 stripes, everything else obstructed.

Like all fakeram45 views these are estimates, not a real SRAM.
Footprint (default 256x64, 134.71 x 95.20 um = 12,824 um^2):
  * 1RW 256x64 interpolated between fakeram45_256x48 (7,776 um^2)
    and fakeram45_256x96 (13,702 um^2): ~9,751 um^2;
  * x1.3 for the dual-port (8T) bit cell and the second address
    decoder / sense-amp column of a 1R1W array: 12,677 um^2,
    rounded up (+1.2 %) to a site/row-aligned 709 x 68 footprint
    (0.19 um sites, 1.4 um rows).
Timing: clk->rd_out 0.27 ns (between fakeram45_256x48 and
fakeram45_512x64), 0.05 ns setup/hold, as in the stock views.

Ports (all synchronous to clk, rising edge):
  we_in, wr_addr_in, wd_in, w_mask_in (bit mask)   write port
  re_in, rd_addr_in -> rd_out                       read port
rd_out is registered and valid the cycle after re_in. Like the stock
bsg_fakeram views it is undefined (X) after a clock edge with re_in
low, so a user that needs held data must capture it. A read of the
word written in the same cycle is undefined (whole word), as for a
real dual-port SRAM; the user must not issue one.

--ports 1rw instead writes a single-port view in the stock fakeram45
pin style (clk, ce_in, we_in, addr_in, wd_in, w_mask_in, rd_out), used
for sizes ORFS does not ship (the 64x44 L1 cache tag arrays). Its
behavioural model reads when ce_in && !we_in and is undefined after
any other edge. The committed fakeram45_64x44 uses --w 46.93 --h 56.0
--tcq 0.21: 2,628 um^2, the stock fakeram45_64x32 (1,241 um^2) to
64x62 (4,713 um^2) interpolated by width, with a height that fits its
141 pins; clk->q as the stock 64-deep views (0.198 ns) plus margin. --model-only writes just the .v model, for stock
fakeram45 sizes whose LEF/Liberty come from the platform
(fakeram45_512x64, the L1 cache data ways).

Usage: gen_fakeram45_1r1w.py [--ports 1r1w|1rw] [--model-only]
                             [--depth 256] [--width 64] [--w W --h H] OUTDIR
"""

import argparse
import math
from pathlib import Path

PITCH = 0.28
PIN = 0.07
EDGE = 2.8          # keep-out at bottom/top, as in fakeram45
GROUP_GAP = 1.4
STRIPE_W = 0.28
STRIPE_PITCH = 4.48  # VSS-to-VSS; VDD halfway


def fmt(x):
    return f"{x:.3f}"


def gen(depth, width, w, h, tcq, outdir, ports="1r1w", model_only=False):
    one = ports == "1rw"
    name = f"fakeram45_{depth}x{width}" + ("" if one else "_1r1w")
    aw = int(math.log2(depth))
    assert 1 << aw == depth
    if model_only:
        (outdir / f"{name}.v").write_text(model(name, depth, width, aw, one))
        print(f"{name}: model only")
        return
    if one:
        groups = [
            [f"w_mask_in[{i}]" for i in range(width)],
            [f"rd_out[{i}]" for i in range(width)],
            [f"wd_in[{i}]" for i in range(width)],
            [f"addr_in[{i}]" for i in range(aw)],
            ["we_in", "ce_in", "clk"],
        ]
    else:
        groups = [
            [f"w_mask_in[{i}]" for i in range(width)],
            [f"wd_in[{i}]" for i in range(width)],
            [f"rd_out[{i}]" for i in range(width)],
            [f"wr_addr_in[{i}]" for i in range(aw)],
            [f"rd_addr_in[{i}]" for i in range(aw)],
            ["we_in", "re_in", "clk"],
        ]
    pins = []  # (name, y)
    y = EDGE
    for g in groups:
        for p in g:
            pins.append((p, y))
            y += PITCH
        y += GROUP_GAP
    assert y < h - EDGE, f"{len(pins)} pins do not fit in height {h}"

    out = []
    a = out.append
    a("VERSION 5.7 ;\nBUSBITCHARS \"[]\" ;")
    a(f"MACRO {name}\n  FOREIGN {name} 0 0 ;\n  SYMMETRY X Y R90 ;")
    a(f"  SIZE {fmt(w)} BY {fmt(h)} ;\n  CLASS BLOCK ;")
    for p, py in pins:
        d = "OUTPUT" if p.startswith("rd_out") else "INPUT"
        a(f"  PIN {p}\n    DIRECTION {d} ;\n    USE SIGNAL ;\n"
          f"    SHAPE ABUTMENT ;\n    PORT\n      LAYER metal3 ;\n"
          f"      RECT 0.000 {fmt(py)} {fmt(PIN)} {fmt(py + PIN)} ;\n"
          f"    END\n  END {p}")
    # Power stripes on metal4.
    vss, vdd = [], []
    x = 2.66
    while x + STRIPE_W < w - 2.0:
        vss.append(x)
        if x + STRIPE_PITCH / 2 + STRIPE_W < w - 2.0:
            vdd.append(x + STRIPE_PITCH / 2)
        x += STRIPE_PITCH
    for net, use, xs in (("VSS", "GROUND", vss), ("VDD", "POWER", vdd)):
        a(f"  PIN {net}\n    DIRECTION INOUT ;\n    USE {use} ;\n"
          f"    PORT\n      LAYER metal4 ;")
        for sx in xs:
            a(f"      RECT {fmt(sx)} {fmt(EDGE)} {fmt(sx + STRIPE_W)} "
              f"{fmt(h - EDGE)} ;")
        a(f"    END\n  END {net}")
    a("  OBS")
    a(f"    LAYER metal1 ;\n    RECT 0 0 {fmt(w)} {fmt(h)} ;")
    a(f"    LAYER metal2 ;\n    RECT 0 0 {fmt(w)} {fmt(h)} ;")
    a(f"    LAYER metal3 ;\n    RECT {fmt(PIN)} 0 {fmt(w)} {fmt(h)} ;")
    prev = 0.0
    for _, py in pins:
        if py > prev:
            a(f"    RECT 0 {fmt(prev)} {fmt(PIN)} {fmt(py)} ;")
        prev = py + PIN
    a(f"    RECT 0 {fmt(prev)} {fmt(PIN)} {fmt(h)} ;")
    a("    LAYER metal4 ;")
    a(f"    RECT 0 0 {fmt(w)} {fmt(EDGE)} ;")
    a(f"    RECT 0 {fmt(h - EDGE)} {fmt(w)} {fmt(h)} ;")
    stripes = sorted(vss + vdd)
    prev = 0.0
    for sx in stripes:
        a(f"    RECT {fmt(prev)} {fmt(EDGE)} {fmt(sx)} {fmt(h - EDGE)} ;")
        prev = sx + STRIPE_W
    a(f"    RECT {fmt(prev)} {fmt(EDGE)} {fmt(w)} {fmt(h - EDGE)} ;")
    a(f"  END\nEND {name}\n\nEND LIBRARY")
    (outdir / f"{name}.lef").write_text("\n".join(out) + "\n")

    # Liberty.
    area = w * h
    leak = 289841.0 * area / 5065.704  # scale fakeram45_256x32 leakage
    con = """        timing() {{
            related_pin : clk;
            timing_type : {kind}_rising ;
            rise_constraint(scalar) {{
                values ("0.050");
            }}
            fall_constraint(scalar) {{
                values ("0.050");
            }}
        }}"""
    cons = con.format(kind="setup") + "\n" + con.format(kind="hold")
    pwr = """        internal_power(){
            rise_power(scalar) {
                values ("18.744");
            }
            fall_power(scalar) {
                values ("18.744");
            }
        }"""

    def inpin(kind, pname, btype=None, extra=""):
        head = f"    {kind}({pname}) {{\n"
        if btype:
            head += f"        bus_type : {name}_{btype};\n"
        return (head + extra + "        direction : input;\n"
                "        capacitance : 5.000;\n" + cons + "\n" + pwr
                + "\n    }\n")

    wa = "addr_in" if one else "wr_addr_in"
    ra = "addr_in" if one else "rd_addr_in"
    wr = ("        memory_write() {\n            address : " + wa + ";\n"
          "            clocked_on : \"clk\";\n        }\n")
    lib = f"""library({name}) {{
    technology (cmos);
    delay_model : table_lookup;
    revision : 1.0;
    comment : "{'1RW' if one else '1R1W'} fakeram45 estimate, see gen_fakeram45_1r1w.py";
    time_unit : "1ns";
    voltage_unit : "1V";
    current_unit : "1uA";
    leakage_power_unit : "1nw";
    nom_process : 1;
    nom_temperature : 25.000;
    nom_voltage : 1.1;
    capacitive_load_unit (1,ff);
    pulling_resistance_unit : "1kohm";
    operating_conditions(tt_1.0_25.0) {{
        process : 1;
        temperature : 25.000;
        voltage : 1.1;
        tree_type : balanced_tree;
    }}
    default_cell_leakage_power : 0;
    default_fanout_load : 1;
    default_inout_pin_cap : 0.0;
    default_input_pin_cap : 0.0;
    default_output_pin_cap : 0.0;
    default_max_transition : 0.227;
    default_operating_conditions : tt_1.0_25.0;
    default_leakage_power_density : 0.0;
    slew_derate_from_library : 1.000;
    slew_lower_threshold_pct_fall : 20.000;
    slew_upper_threshold_pct_fall : 80.000;
    slew_lower_threshold_pct_rise : 20.000;
    slew_upper_threshold_pct_rise : 80.000;
    input_threshold_pct_fall : 50.000;
    input_threshold_pct_rise : 50.000;
    output_threshold_pct_fall : 50.000;
    output_threshold_pct_rise : 50.000;
    lu_table_template({name}_mem_out_slew_template) {{
        variable_1 : total_output_net_capacitance;
            index_1 ("1000, 1001");
    }}
    library_features(report_delay_calculation);
    type ({name}_DATA) {{
        base_type : array ;
        data_type : bit ;
        bit_width : {width};
        bit_from : {width - 1};
        bit_to : 0 ;
        downto : true ;
    }}
    type ({name}_ADDRESS) {{
        base_type : array ;
        data_type : bit ;
        bit_width : {aw};
        bit_from : {aw - 1};
        bit_to : 0 ;
        downto : true ;
    }}
cell({name}) {{
    area : {area:.3f};
    interface_timing : true;
    memory() {{
        type : ram;
        address_width : {aw};
        word_width : {width};
    }}
    pin(clk)   {{
        direction : input;
        capacitance : 25.000;
        clock : true;
        min_period           : 0.250 ;
        internal_power(){{
            rise_power(scalar) {{
                values ("3000.000")
            }}
            fall_power(scalar) {{
                values ("3000.000")
            }}
        }}
    }}
    bus(rd_out)   {{
        bus_type : {name}_DATA;
        direction : output;
        max_capacitance : 500.000;
        memory_read() {{
            address : {ra};
        }}
        timing() {{
            related_pin : "clk" ;
            timing_type : rising_edge;
            timing_sense : non_unate;
            cell_rise(scalar) {{
                values ("{tcq:.3f}");
            }}
            cell_fall(scalar) {{
                values ("{tcq:.3f}");
            }}
            rise_transition({name}_mem_out_slew_template) {{
                index_1 ("5.000, 500.000");
                values ("0.009, 0.227")
            }}
            fall_transition({name}_mem_out_slew_template) {{
                index_1 ("5.000, 500.000");
                values ("0.009, 0.227")
            }}
        }}
    }}
"""
    lib += inpin("pin", "we_in")
    if one:
        lib += inpin("pin", "ce_in")
        lib += inpin("bus", "addr_in", "ADDRESS")
    else:
        lib += inpin("pin", "re_in")
        lib += inpin("bus", "wr_addr_in", "ADDRESS")
        lib += inpin("bus", "rd_addr_in", "ADDRESS")
    lib += inpin("bus", "wd_in", "DATA", wr)
    lib += inpin("bus", "w_mask_in", "DATA", wr)
    lib += f"    cell_leakage_power : {leak:.3f};\n}}\n\n}}\n"
    (outdir / f"{name}.lib").write_text(lib)

    (outdir / f"{name}.v").write_text(model(name, depth, width, aw, one))
    print(f"{name}: {fmt(w)} x {fmt(h)} um = {area:.1f} um^2, "
          f"{len(pins)} signal pins")


def model(name, depth, width, aw, one):
    """Behavioural model (synthesis blackboxes it via the .lib; also
    used by the Verilator SRAM-macro tests)."""
    junk = f"{width}'({{{(width + 63) // 64}{{junk}}}})"
    head = f"""// Behavioural model of {name} (generated by
// gen_fakeram45_1r1w.py). Read data is registered and valid the
// cycle after a read; after any other clock edge it is undefined,
// modelled as pseudo-random garbage (2-state simulators turn X into
// 0, which could hide a missing capture register)."""
    if one:
        return head + f"""
module {name} (
    input  wire              clk,
    input  wire              ce_in,
    input  wire              we_in,
    input  wire [{aw - 1}:0]        addr_in,
    input  wire [{width - 1}:0]       wd_in,
    input  wire [{width - 1}:0]       w_mask_in,
    output reg  [{width - 1}:0]       rd_out
);
  reg [{width - 1}:0] mem [0:{depth - 1}];
  reg [63:0] junk;
  initial junk = 64'h9e3779b97f4a7c15;
  always @(posedge clk) begin
    junk <= {{junk[62:0], junk[63] ^ junk[62] ^ junk[60] ^ junk[59]}};
    if (ce_in && we_in)
      mem[addr_in] <= (mem[addr_in] & ~w_mask_in) | (wd_in & w_mask_in);
    if (ce_in && !we_in) rd_out <= mem[addr_in];
    else rd_out <= {junk};
  end
endmodule
"""
    return head + f"""
// A read of the word written in the same cycle is undefined and
// returns whole-word garbage (the write itself completes).
module {name} (
    input  wire              clk,
    input  wire              we_in,
    input  wire [{aw - 1}:0]        wr_addr_in,
    input  wire [{width - 1}:0]       wd_in,
    input  wire [{width - 1}:0]       w_mask_in,
    input  wire              re_in,
    input  wire [{aw - 1}:0]        rd_addr_in,
    output reg  [{width - 1}:0]       rd_out
);
  reg [{width - 1}:0] mem [0:{depth - 1}];
  reg [63:0] junk;
  initial junk = 64'h9e3779b97f4a7c15;
  always @(posedge clk) begin
    junk <= {{junk[62:0], junk[63] ^ junk[62] ^ junk[60] ^ junk[59]}};
    if (we_in)
      mem[wr_addr_in] <= (mem[wr_addr_in] & ~w_mask_in) |
                         (wd_in & w_mask_in);
    if (re_in && !(we_in && (wr_addr_in == rd_addr_in))) rd_out <= mem[rd_addr_in];
    else rd_out <= {junk};
  end
endmodule
"""


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--depth", type=int, default=256)
    ap.add_argument("--width", type=int, default=64)
    ap.add_argument("--w", type=float, default=134.71)
    ap.add_argument("--h", type=float, default=95.2)
    ap.add_argument("--tcq", type=float, default=0.27)
    ap.add_argument("--ports", choices=["1r1w", "1rw"], default="1r1w")
    ap.add_argument("--model-only", action="store_true")
    ap.add_argument("outdir", type=Path)
    args = ap.parse_args()
    args.outdir.mkdir(parents=True, exist_ok=True)
    gen(args.depth, args.width, args.w, args.h, args.tcq, args.outdir,
        args.ports, args.model_only)


if __name__ == "__main__":
    main()
