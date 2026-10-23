import csv, sys
path = sys.argv[1]
mem = sys.argv[2] if len(sys.argv) > 2 else 'soc'
filt = sys.argv[3] if len(sys.argv) > 3 else ''
cols = ['cycles','instret','ret_alu','ret_load','ret_store','ret_branch','ret_jal','ret_jalr','ret_mul','ret_div','ret_fp','ret_vec','ret_vls','ret_vset','ret_csr','ret_rvc','muldiv_busy','fpu_busy','vec_busy','vec_ex_stall','vls_cyc','loaduse_cyc','br_taken','jal_redir','jalr_redir','squash_id','squash_if','ic_access','stk_retire','stk_fetch_lat','stk_fetch_straddle','stk_fetch_miss','stk_branch','stk_jal','stk_jalr','stk_loaduse','stk_muldiv','stk_fpu','stk_vec','stk_vls','stk_dc_lat','stk_dc_miss','stk_io','stk_serial','dc_unc','dc_unc_cyc']
with open(path) as f:
    for r in csv.DictReader(f):
        if r['rep'] != '0' or r['mem'] != mem: continue
        name = f"{r['bench']}[{r['variant']}] {r['region']} {r['label']}"
        if filt and filt not in name: continue
        out = [name]
        for c in cols:
            v = r.get(c,'')
            if v not in ('','0'):
                out.append(f"{c}={v}")
        print(' '.join(out))
