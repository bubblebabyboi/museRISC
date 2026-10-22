import sys,re,collections
def parse(path):
    regs=collections.OrderedDict(); cur=None
    for l in open(path):
        if l.startswith('== region'):
            cur=int(l.split()[2]); regs[cur]={'stats':{},'model':collections.OrderedDict()}
        elif l.startswith('model.'):
            name=l.split()[0][6:]
            kv=dict(x.split('=') for x in l.split()[1:])
            regs[cur]['model'][name]={k:int(v) for k,v in kv.items()}
        elif cur is not None:
            for tok in l.split():
                if '=' in tok:
                    k,v=tok.split('=',1)
                    try: regs[cur]['stats'][k]=int(v)
                    except: pass
            m=re.match(r'(btb\.\S+|ras\.\S+)',l)
            if m: regs[cur]['stats'][m.group(1)]=l.strip()
    return regs
if __name__=='__main__':
    path=sys.argv[1]; rid=int(sys.argv[2]) if len(sys.argv)>2 else None
    regs=parse(path)
    for r,d in regs.items():
        if rid is not None and r!=rid: continue
        m=d['model']
        if not m: continue
        b=m['F0_rtl']['cycles']
        print(f'region {r} base={b}')
        for k,v in m.items():
            print(f"  {k:24s} {v['cycles']:>10d}  {100*(v['cycles']-b)/b:+6.1f}%  x{b/v['cycles']:.3f}  mispred={v['mispred']} ic_acc={v['ic_acc']} predtk={v['pred_taken']}")
