#!/usr/bin/env python3
"""Derive the composite-field AES S-box constants in rtl/core/muserisc_bext_pkg.sv.

Tower used by the RTL:
  GF(16)   = GF(2)[w]/(w^4 + w + 1), polynomial basis
  GF(16^2) = GF(16)[z]/(z^2 + z + LAM), element h*z + l packed {h, l}

For every LAM making z^2+z+LAM irreducible and every isomorphism onto the
AES field GF(2)[x]/(x^8+x^4+x^3+x+1) (a fixed primitive tower generator g is
mapped to each AES element r with the same minimal polynomial, i.e. each of
the 8 conjugate roots), build the four 8x8 GF(2) matrices the RTL needs:
  M_IN_FWD  : AES -> tower
  M_IN_INV  : inverse affine (linear part), then AES -> tower
  M_OUT_FWD : tower -> AES, then forward affine (linear part)
  M_OUT_INV : tower -> AES
and pick the candidate with minimum total matrix weight (ties: lowest LAM,
then lowest root). The minimum is unique (LAM=0xA, root 0x1E, weight 110;
next best 112). Every candidate is checked exhaustively against the S-box
computed directly from the GF(2^8) inverse + affine definition.

Usage:
  scripts/gen_aes_tower.py           print the SV constants of the best candidate
  scripts/gen_aes_tower.py --check   also verify they match the committed RTL
                                     (exit 1 on mismatch)
"""
import os
import re
import sys

PKG = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "rtl", "core",
                   "muserisc_bext_pkg.sv")


def aes_mul(a, b):
    r = 0
    for _ in range(8):
        if b & 1:
            r ^= a
        a = ((a << 1) ^ (0x1B if a & 0x80 else 0)) & 0xFF
        b >>= 1
    return r


def g16_mul(a, b):
    r = 0
    for i in range(4):
        if (b >> i) & 1:
            r ^= a << i
    for i in (6, 5, 4):
        if (r >> i) & 1:
            r ^= 0b10011 << (i - 4)
    return r & 0xF


def g16_inv(a):
    return next((b for b in range(16) if g16_mul(a, b) == 1), 0)


def rotl8(v, n):
    return ((v << n) | (v >> (8 - n))) & 0xFF


def aff(x):  # linear part of the AES forward affine map
    return x ^ rotl8(x, 1) ^ rotl8(x, 2) ^ rotl8(x, 3) ^ rotl8(x, 4)


def iaff(y):  # linear part of the inverse affine map
    return rotl8(y, 1) ^ rotl8(y, 3) ^ rotl8(y, 6)


def mat_of(f):
    """Rows (one bitmask per output bit o): bit i = coefficient of input bit i."""
    cols = [f(1 << i) for i in range(8)]
    return [sum(((cols[i] >> o) & 1) << i for i in range(8)) for o in range(8)]


def apply(m, x):
    return sum((bin(m[o] & x).count("1") & 1) << o for o in range(8))


def weight(m):
    return sum(bin(v).count("1") for v in m)


AES_INV = [0] + [next(y for y in range(1, 256) if aes_mul(x, y) == 1) for x in range(1, 256)]
SBOX = [aff(AES_INV[x]) ^ 0x63 for x in range(256)]
ISBOX = [0] * 256
for _x in range(256):
    ISBOX[SBOX[_x]] = _x
assert iaff(0x63) == 0x05 and all(iaff(aff(x)) == x for x in range(256))


def candidates():
    lams = [l for l in range(1, 16) if all(g16_mul(t, t) ^ t ^ l for t in range(16))]
    for lam in lams:
        def c_mul(a, b, lam=lam):
            ah, al, bh, bl = a >> 4, a & 15, b >> 4, b & 15
            hh = g16_mul(ah, bh)
            return ((hh ^ g16_mul(ah, bl) ^ g16_mul(al, bh)) << 4) | \
                (g16_mul(hh, lam) ^ g16_mul(al, bl))

        def order(g):
            x, k = g, 1
            while x != 1:
                x, k = c_mul(x, g), k + 1
            return k

        g = next(v for v in range(2, 256) if order(v) == 255)
        for root in range(2, 256):
            c2a, xc, xa = {0: 0}, 1, 1
            for _ in range(255):
                c2a[xc] = xa
                xc, xa = c_mul(xc, g), aes_mul(xa, root)
            if len(c2a) != 256:
                continue
            if any(c2a[a ^ (1 << i)] != c2a[a] ^ c2a[1 << i]
                   for a in range(256) for i in range(8)):
                continue  # not additive: root has a different minimal polynomial
            a2c = {v: k for k, v in c2a.items()}
            mats = {
                "AES_M_IN_FWD": mat_of(lambda x: a2c[x]),
                "AES_M_IN_INV": mat_of(lambda y: a2c[iaff(y)]),
                "AES_M_OUT_FWD": mat_of(lambda v: aff(c2a[v])),
                "AES_M_OUT_INV": mat_of(lambda v: c2a[v]),
            }
            yield lam, root, g, a2c[0x05], mats


def tower_inv(t, lam):
    h, l = t >> 4, t & 15
    d = g16_inv(g16_mul(g16_mul(h, h), lam) ^ g16_mul(h, l) ^ g16_mul(l, l))
    return (g16_mul(h, d) << 4) | g16_mul(h ^ l, d)


def verify(lam, c_in_inv, m):
    for x in range(256):
        f = apply(m["AES_M_OUT_FWD"], tower_inv(apply(m["AES_M_IN_FWD"], x), lam)) ^ 0x63
        i = apply(m["AES_M_OUT_INV"], tower_inv(apply(m["AES_M_IN_INV"], x) ^ c_in_inv, lam))
        assert f == SBOX[x] and i == ISBOX[x], (hex(lam), x)


def sv_rows(m):
    return [f"8'b{m[o]:08b}" for o in reversed(range(8))]  # {row7, ..., row0}


def main():
    cands = []
    for lam, root, g, c_in_inv, mats in candidates():
        verify(lam, c_in_inv, mats)
        cands.append((sum(weight(v) for v in mats.values()), lam, root, g, c_in_inv, mats))
    cands.sort(key=lambda c: (c[0], c[1], c[2]))
    w, lam, root, g, c_in_inv, mats = cands[0]
    print(f"// {len(cands)} candidates; best total weight {w} "
          f"(next {cands[1][0]}): LAM=0x{lam:X}, tower generator 0x{g:02X} -> AES 0x{root:02X}")
    print(f"localparam logic [3:0] AES_TOWER_LAM = 4'h{lam:X};")
    for name, m in mats.items():
        r = sv_rows(m)
        print(f"localparam logic [63:0] {name} = {{  // weight {weight(m)}")
        print(f"    {', '.join(r[:4])},\n    {', '.join(r[4:])}}};")
    print(f"localparam logic [7:0]  AES_C_IN_INV = 8'h{c_in_inv:02X};")
    print(f"// GF(16) inverse table: {[f'{g16_inv(a):X}' for a in range(16)]}")

    if "--check" in sys.argv:
        src = open(PKG).read()
        ok = re.search(r"AES_TOWER_LAM\s*=\s*4'h([0-9A-Fa-f])", src).group(1).upper() == f"{lam:X}"
        ok &= re.search(r"AES_C_IN_INV\s*=\s*8'h([0-9A-Fa-f]+)", src).group(1).upper() == \
            f"{c_in_inv:02X}"
        for name, m in mats.items():
            body = re.search(name + r"\s*=\s*\{([^}]*)\}", src).group(1)
            ok &= re.findall(r"8'b[01]{8}", body) == sv_rows(m)
        gf16 = re.findall(r"4'h([0-9A-F]): return 4'h([0-9A-F])", src)
        ok &= all(g16_inv(int(a, 16)) == int(b, 16) for a, b in gf16) and len(gf16) == 15
        print("CHECK", "PASS: committed RTL constants match" if ok else "FAIL: RTL constants differ")
        sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
