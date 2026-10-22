import csv, sys
base = sys.argv[1]
for cfg, lat in (('default', 2), ('sky130', 3)):
    with open(f"{base}/{cfg}/results.csv") as f:
        for r in csv.DictReader(f):
            if r['rep'] != '0' or r['mem'] != 'soc': continue
            if r['bench'] not in ('coremark', 'dhrystone', 'sha256chain', 'sha256chain_bulk', 'kernels'): continue
            if r['bench'] == 'kernels' and r['variant'] != 'scalar': continue
            cyc = int(r['cycles']); ia = int(r['ic_access']); ins = int(r['instret'])
            icm = int(r['ic_miss_cyc'] or 0)
            occ = (ia * lat + icm) / cyc
            print(f"{cfg:7s} {r['bench']}[{r['variant']}] {r['label']:32s} cyc={cyc:>9} ipc={ins/cyc:.3f} fetch/instr={ia/ins:.3f} I$occ={occ*100:5.1f}% idle={cyc-ia*lat-icm:>8} ({(1-occ)*100:4.1f}%) ceilIPC={ins/(ia*lat+icm):.3f}")
