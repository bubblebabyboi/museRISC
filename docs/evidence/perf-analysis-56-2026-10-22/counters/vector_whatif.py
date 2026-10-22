import csv, sys
base = sys.argv[1]
# FPU pipelining savings (cycles, config independent): n_vfmacc * (8*vl - (vl+7))
fma = {'dgemm RVV': (4096, 32), 'sgemm RVV': (4096, 32), 'fir_f32 RVV': (512, 128),
       'daxpy RVV': (32, 64), 'saxpy RVV': (32, 128), 'ddot RVV': (32, 64)}
# packing factor per VLS (elements per 64-bit access) by kernel: e8=8, e16=4, e32=2, e64=1
pack = {'vadd_i32 RVV': 2, 'vadd_i64 RVV': 1, 'daxpy RVV': 1, 'saxpy RVV': 2, 'ddot RVV': 1,
        'idot_i32 RVV': 2, 'memcpy RVV': 1, 'memcpy RVV-e8': 8, 'memset RVV': 1, 'memset RVV-e8': 8,
        'dgemm RVV': 1, 'sgemm RVV': 2, 'fir_f32 RVV': 2, 'mac_i8 RVV': 8, 'mac_i16 RVV': 4}
# vector int multiply pipelining savings: n_mul_instrs * ((k+4)*vl - (vl+2)) ; k by SEW
vmul = {'mac_i8 RVV': (64, 256, 1), 'mac_i16 RVV': (64, 128, 1), 'idot_i32 RVV': (64, 64, 2)}
C = {}
rows = {}
for cfg in ('default', 'sky130', 'fpga'):
    with open(f"{base}/{cfg}/results.csv") as f:
        for r in csv.DictReader(f):
            if r['rep'] != '0' or r['mem'] != 'soc' or r['bench'] != 'kernels' or r['variant'] != 'scalar': continue
            rows[(cfg, r['label'])] = r
for cfg in ('default', 'sky130', 'fpga'):
    print(f"== {cfg}/soc")
    for lab in pack:
        r = rows[(cfg, lab)]
        cyc = int(r['cycles']); vls = int(r['stk_vls']); vec = int(r['stk_vec'])
        cname = lab.replace(' RVV-e8', ' C').replace(' RVV', ' C')
        c = int(rows[(cfg, cname)]['cycles'])
        s_fpu = fma[lab][0] * (8 * fma[lab][1] - (fma[lab][1] + 7)) if lab in fma else 0
        k = pack[lab]; s_pack = int(vls * (1 - 1 / k))
        s_mul = vmul[lab][0] * ((vmul[lab][2] + 4) * vmul[lab][1] - (vmul[lab][1] + 2)) if lab in vmul else 0
        tot = s_fpu + s_pack + s_mul
        out = f"{lab:15s} cyc={cyc:>9} vec={vec/cyc*100:5.1f}% vls={vls/cyc*100:5.1f}% RVV/C={c/cyc:4.2f}x"
        if s_fpu: out += f" | FPUpipe {cyc/(cyc-s_fpu):4.2f}x"
        if s_pack: out += f" | pack {cyc/(cyc-s_pack):4.2f}x"
        if s_mul: out += f" | vmul {cyc/(cyc-s_mul):4.2f}x"
        if tot: out += f" | all {cyc/(cyc-tot):4.2f}x -> RVV/C {c/(cyc-tot):5.2f}x"
        print(out)
