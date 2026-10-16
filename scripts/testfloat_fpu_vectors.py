#!/usr/bin/env python3
"""Convert testfloat_gen output to fpu_tb --testfloat vector lines.

Usage: testfloat_gen ... <op> | testfloat_fpu_vectors.py <op> <rmode>

Output line: "op d rm aux a b c result flags" (op/d/rm/aux decimal,
operands/result 64-bit hex as presented to / produced by
muserisc_fpu: binary32 NaN-boxed, 32-bit integer results
sign-extended, flags in RISC-V fflags order, which matches
SoftFloat's flag bits).
"""
import sys

OP = {"add": 0, "sub": 1, "mul": 2, "div": 3, "sqrt": 4, "mulAdd": 12}
RM = {"near_even": 0, "minMag": 1, "min": 2, "max": 3, "near_maxMag": 4}
INT_AUX = {"i32": 0, "ui32": 1, "i64": 2, "ui64": 3}
CMP_AUX = {"le": 0, "lt": 1, "eq": 2}


def box(v):
    return 0xFFFFFFFF00000000 | v


def sext32(v):
    return v | 0xFFFFFFFF00000000 if v & 0x80000000 else v


def main():
    op, rmode = sys.argv[1], sys.argv[2]
    rm = RM[rmode]
    for line in sys.stdin:
        f = line.split()
        if not f:
            continue
        vals = [int(x, 16) for x in f]
        flags = vals[-1]
        res = vals[-2]
        ins = vals[:-2]
        a = b = c = 0
        if op.startswith(("f32_", "f64_")) and op[4:] in OP:
            d = op.startswith("f64")
            code = OP[op[4:]]
            ops = ins if d else [box(x) for x in ins]
            a, b, c = (ops + [0, 0, 0])[:3]
            want = res if d else box(res)
            aux = 0
        elif "_to_" in op:
            src, dst = op.split("_to_")
            if src in ("f32", "f64") and dst in INT_AUX:
                code, d, aux = 9, src == "f64", INT_AUX[dst]
                a = ins[0] if d else box(ins[0])
                want = sext32(res) if dst.endswith("32") else res
            elif dst in ("f32", "f64") and src in INT_AUX:
                code, d, aux = 10, dst == "f64", INT_AUX[src]
                a = ins[0]
                want = res if d else box(res)
            else:  # f32_to_f64 / f64_to_f32
                code, d, aux = 11, dst == "f64", 0
                a = box(ins[0]) if src == "f32" else ins[0]
                want = res if d else box(res)
        else:  # compares
            fmt, cmp = op.split("_")
            code, d, aux = 7, fmt == "f64", CMP_AUX[cmp]
            a, b = (ins if d else [box(x) for x in ins])
            want = res
        print(f"{code} {int(d)} {rm} {aux} {a:x} {b:x} {c:x} {want:x} {flags:x}")


if __name__ == "__main__":
    main()
