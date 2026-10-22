#!/usr/bin/env python3
"""Host model of the kernels benchmark: generates kernels_kat.h.

An independent re-implementation of main.c's input generator
(splitmix64 streams per kernel and array) and of every kernel's
reference output, in exact arithmetic: Python integers, and
fractions.Fraction for the floating-point kernels. For each FP output
it proves that the result is order-independent in the target format:
every input is k/16 (1 <= |k| <= 127), so every product is a multiple of
1/256, and when the sum of the absolute values of the terms, in units of
1/256, stays below 2^24 (binary32) or 2^53 (binary64), every partial sum
of the terms in any order (and any fusion) is exactly representable.
The C and RVV kernels may then accumulate in any order and must still
match the reference bit for bit.

The KAT of each kernel is the FNV-1a 64 hash of the reference output's
memory image (little-endian), as main.c computes it.

  kernels_model.py            write kernels_kat.h next to this script
  kernels_model.py --check    exit 1 unless kernels_kat.h is up to date
"""

import os
import struct
import sys
from fractions import Fraction

M64 = (1 << 64) - 1

# Sizes: kernels.h
KN_I8, KN_I16, KN_32, KN_64, KN_MEM = 4096, 2048, 1024, 512, 4096
KN_GEMM, KN_FIR, KN_TAPS = 32, 1024, 16
AXPY_A = Fraction(3, 8)  # KN_AXPY_A = 0.375
MEMSET_C = 0x3C


class Rng:
    """splitmix64, one stream per (kernel, array): main.c rng_seed()."""

    def __init__(self, kernel, array):
        self.x = 0x5349474C4B524E00 ^ (kernel << 8) ^ array

    def next(self):
        self.x = (self.x + 0x9E3779B97F4A7C15) & M64
        z = self.x
        z = ((z ^ (z >> 30)) * 0xBF58476D1CE4E5B9) & M64
        z = ((z ^ (z >> 27)) * 0x94D049BB133111EB) & M64
        return z ^ (z >> 31)


def signed(v, bits):
    return v - (1 << bits) if v >> (bits - 1) & 1 else v


def fp_vals(rng, n):
    """k/16 with 1 <= |k| <= 127 (main.c fp_k)."""
    out = []
    for _ in range(n):
        k = (rng.next() >> 33) % 254 - 127
        out.append(Fraction(k + 1 if k >= 0 else k, 16))
    return out


def ints(rng, n, conv):
    return [conv(rng.next()) for _ in range(n)]


def exact(v, fmt, terms=None):
    """v (a Fraction) packed as binary32 ('f') or binary64 ('d'); checks
    that it is exact and, given the terms of a sum, that every partial sum
    in any order is exact too."""
    mant = 24 if fmt == "f" else 53
    if terms is not None:
        q = Fraction(1, 256)
        assert all((t / q).denominator == 1 for t in terms)
        assert sum(abs(t) for t in terms) / q < 2**mant, "sum not order-independent"
    b = struct.pack("<" + fmt, float(v))
    assert Fraction(struct.unpack("<" + fmt, b)[0]) == v, "not exactly representable"
    return b


def fnv1a64(data):
    h = 0xCBF29CE484222325
    for byte in data:
        h = ((h ^ byte) * 0x100000001B3) & M64
    return h


def kats():
    k = {}
    # 1. vadd_i32: int32 in [-2^30, 2^30)
    a = ints(Rng(1, 0), KN_32, lambda r: signed(r >> 32, 32) >> 1)
    b = ints(Rng(1, 1), KN_32, lambda r: signed(r >> 32, 32) >> 1)
    k["VADD_I32"] = b"".join(struct.pack("<i", x + y) for x, y in zip(a, b))
    # 2. vadd_i64: int64 in [-2^62, 2^62)
    a = ints(Rng(2, 0), KN_64, lambda r: signed(r, 64) >> 1)
    b = ints(Rng(2, 1), KN_64, lambda r: signed(r, 64) >> 1)
    k["VADD_I64"] = b"".join(struct.pack("<q", x + y) for x, y in zip(a, b))
    # 3./4. axpy, one application: y = y0 + a x
    for idx, name, n, fmt in ((3, "DAXPY", KN_64, "d"), (4, "SAXPY", KN_32, "f")):
        x = fp_vals(Rng(idx, 0), n)
        y = fp_vals(Rng(idx, 1), n)
        k[name] = b"".join(exact(yi + AXPY_A * xi, fmt, [yi, AXPY_A * xi])
                           for xi, yi in zip(x, y))
    # 5. ddot
    x = fp_vals(Rng(5, 0), KN_64)
    y = fp_vals(Rng(5, 1), KN_64)
    terms = [p * q for p, q in zip(x, y)]
    k["DDOT"] = exact(sum(terms), "d", terms)
    # 6. idot_i32: full-range int32, int64 products, sum mod 2^64
    x = ints(Rng(6, 0), KN_32, lambda r: signed(r >> 32, 32))
    y = ints(Rng(6, 1), KN_32, lambda r: signed(r >> 32, 32))
    k["IDOT_I32"] = struct.pack("<Q", sum(p * q for p, q in zip(x, y)) & M64)
    # 7. memcpy, 8. memset
    k["MEMCPY"] = bytes(ints(Rng(7, 0), KN_MEM, lambda r: r >> 56))
    k["MEMSET"] = bytes([MEMSET_C]) * KN_MEM
    # 9./10. gemm
    n = KN_GEMM
    for idx, name, fmt in ((9, "DGEMM", "d"), (10, "SGEMM", "f")):
        a = fp_vals(Rng(idx, 0), n * n)
        b = fp_vals(Rng(idx, 1), n * n)
        out = []
        for i in range(n):
            for j in range(n):
                terms = [a[i * n + kk] * b[kk * n + j] for kk in range(n)]
                out.append(exact(sum(terms), fmt, terms))
        k[name] = b"".join(out)
    # 11. fir_f32
    h = fp_vals(Rng(11, 0), KN_TAPS)
    x = fp_vals(Rng(11, 1), KN_FIR + KN_TAPS - 1)
    out = []
    for i in range(KN_FIR):
        terms = [h[t] * x[i + t] for t in range(KN_TAPS)]
        out.append(exact(sum(terms), "f", terms))
    k["FIR_F32"] = b"".join(out)
    # 12. mac_i8, 13. mac_i16: full range, sum mod 2^32
    x = ints(Rng(12, 0), KN_I8, lambda r: signed(r >> 56, 8))
    y = ints(Rng(12, 1), KN_I8, lambda r: signed(r >> 56, 8))
    k["MAC_I8"] = struct.pack("<I", sum(p * q for p, q in zip(x, y)) & 0xFFFFFFFF)
    x = ints(Rng(13, 0), KN_I16, lambda r: signed(r >> 48, 16))
    y = ints(Rng(13, 1), KN_I16, lambda r: signed(r >> 48, 16))
    k["MAC_I16"] = struct.pack("<I", sum(p * q for p, q in zip(x, y)) & 0xFFFFFFFF)
    return {name: fnv1a64(img) for name, img in k.items()}


def header(values):
    lines = [
        "/* Generated by kernels_model.py: do not edit. FNV-1a 64 of each",
        " * kernel's reference output (memory image, little-endian), computed",
        " * on the host in exact arithmetic from main.c's inputs. */",
        "#ifndef KERNELS_KAT_H",
        "#define KERNELS_KAT_H",
    ]
    lines += [f"#define KAT_{n} 0x{v:016x}ull" for n, v in values.items()]
    lines += ["#endif", ""]
    return "\n".join(lines)


def main():
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "kernels_kat.h")
    text = header(kats())
    if sys.argv[1:] == ["--check"]:
        with open(path) as f:
            if f.read() != text:
                sys.exit(f"{path} is out of date: run {sys.argv[0]}")
        print(f"{path}: up to date")
        return
    if sys.argv[1:]:
        sys.exit(__doc__)
    with open(path, "w") as f:
        f.write(text)
    print(text, end="")


if __name__ == "__main__":
    main()
