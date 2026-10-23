#!/usr/bin/env python3
"""bb_stub.py <sv2v module file>...: print a port-only blackbox stub of each
sv2v-converted module (header, parameters, port declarations)."""
import re, sys
for f in sys.argv[1:]:
    lines = open(f).read().split('\n')
    out = []; i = 0
    while True:
        out.append(lines[i])
        if lines[i].strip() == ');': break
        i += 1
    for l in lines[i+1:]:
        if re.match(r'^\t(input|output|inout|parameter)\b', l):
            if not l.rstrip().endswith(';'): raise SystemExit(f'{f}: multi-line decl {l!r}')
            out.append(re.sub(r'^\toutput reg\b', '\toutput wire', l))
    out.append('endmodule')
    print('(* blackbox *)'); print('\n'.join(out))
