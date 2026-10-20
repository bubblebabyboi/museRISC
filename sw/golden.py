"""Golden models / known-answer vectors for Sigil crypto RTL.

Run directly (`python3 sw/golden.py`) to self-check against hashlib,
or import `keccak_f1600` to generate testbench vectors.
"""
import hashlib

MASK64 = (1 << 64) - 1
RC = [
    0x0000000000000001, 0x0000000000008082, 0x800000000000808A,
    0x8000000080008000, 0x000000000000808B, 0x0000000080000001,
    0x8000000080008081, 0x8000000000008009, 0x000000000000008A,
    0x0000000000000088, 0x0000000080008009, 0x000000008000000A,
    0x000000008000808B, 0x800000000000008B, 0x8000000000008089,
    0x8000000000008003, 0x8000000000008002, 0x8000000000000080,
    0x000000000000800A, 0x800000008000000A, 0x8000000080008081,
    0x8000000000008080, 0x0000000080000001, 0x8000000080008008,
]
# Rho offsets indexed [x][y]
RHO = [[0, 36, 3, 41, 18], [1, 44, 10, 45, 2], [62, 6, 43, 15, 61],
       [28, 55, 25, 21, 56], [27, 20, 39, 8, 14]]


def rotl(x, n):
    return ((x << n) | (x >> (64 - n))) & MASK64 if n else x


def keccak_f1600(state):
    """state: list of 25 lanes, index 5*y+x. Returns new list."""
    a = list(state)
    for rnd in range(24):
        c = [a[x] ^ a[5 + x] ^ a[10 + x] ^ a[15 + x] ^ a[20 + x]
             for x in range(5)]
        d = [c[(x - 1) % 5] ^ rotl(c[(x + 1) % 5], 1) for x in range(5)]
        a = [v ^ d[i % 5] for i, v in enumerate(a)]
        b = [0] * 25
        for y in range(5):
            for x in range(5):
                b[5 * ((2 * x + 3 * y) % 5) + y] = rotl(a[5 * y + x],
                                                        RHO[x][y])
        a = [b[5 * y + x] ^ ((~b[5 * y + (x + 1) % 5]) &
                             b[5 * y + (x + 2) % 5] & MASK64)
             for y in range(5) for x in range(5)]
        a[0] ^= RC[rnd]
    return a


def state_to_int(lanes):
    return sum(v << (64 * i) for i, v in enumerate(lanes))


SECP256K1_P = 2**256 - 2**32 - 977
CURVE25519_P = 2**255 - 19

if __name__ == "__main__":
    assert hashlib.sha256(b"abc").hexdigest() == (
        "ba7816bf8f01cfea414140de5dae2223"
        "b00361a396177a9cb410ff61f20015ad")
    zero_out = keccak_f1600([0] * 25)
    print(f"KECCAK_ZERO_OUT={state_to_int(zero_out):0400x}")
    # Cross-check the permutation via a SHA3-256 sponge (rate 1088).
    rate = 1088 // 8
    msg = bytearray(b"abc")
    msg.append(0x06)
    msg += bytes(rate - len(msg))
    msg[-1] |= 0x80
    st = [0] * 25
    for i in range(rate // 8):
        st[i] ^= int.from_bytes(msg[8 * i:8 * i + 8], "little")
    out = b"".join(v.to_bytes(8, "little")
                   for v in keccak_f1600(st))[:32]
    assert out.hex() == hashlib.sha3_256(b"abc").hexdigest(), out.hex()
    print("golden.py: SHA-256 KAT + Keccak/SHA3-256 sponge OK")
