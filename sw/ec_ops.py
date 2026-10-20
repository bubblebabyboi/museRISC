"""Curve point operations for Sigil, built ONLY from the field
primitives the RTL unit provides (add/sub/mul mod p in `ec_field.v`;
inversion = square-and-multiply chain over mul). This is the golden
sequence the Phase-1/2 firmware and hardware sequencer must reproduce:
every `mul()` here is one accelerator field op.

Tests (run: python3 sw/ec_ops.py):
  * secp256k1: G, 2G known coordinates; n*G = infinity; ECDSA verify
    of a frozen vector produced by the `cryptography` library
    (private key 1, message b"museRISC", ECDSA/SHA-256); tamper fails.
  * Ed25519: RFC 8032 sec.7.1 TEST 1 and TEST 2 -- our sign()
    reproduces the RFC signatures byte-for-byte and verify() accepts
    them and rejects a tampered message.

NOTE: reference code for correctness, NOT constant-time. The hardware
sequencer must use a fixed ladder before handling secrets (SPEC s.3).
"""
import hashlib

# ---- field primitives (mirror rtl/crypto/ec_field.v) ----------------
def fadd(x, y, p): return (x + y) % p
def fsub(x, y, p): return (x - y) % p
def fmul(x, y, p): return (x * y) % p

def fpow(x, e, p):  # square-and-multiply over fmul
    r = 1
    while e:
        if e & 1: r = fmul(r, x, p)
        x = fmul(x, x, p); e >>= 1
    return r

def finv(x, p): return fpow(x, p - 2, p)

# ---- secp256k1 ------------------------------------------------------
SP = 2**256 - 2**32 - 977
SN = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141
G = (0x79BE667EF9DCBBAC55A06295CE870B07029BFCDB2DCE28D959F2815B16F81798,
     0x483ADA7726A3C4655DA4FBFC0E1108A8FD17B448A68554199C47D08FFB10D4B8)
INF = None

def s_add(P, Q):
    if P is INF: return Q
    if Q is INF: return P
    (x1, y1), (x2, y2) = P, Q
    if x1 == x2 and (y1 + y2) % SP == 0: return INF
    if P == Q:
        m = fmul(3 * fmul(x1, x1, SP), finv(2 * y1 % SP, SP), SP)
    else:
        m = fmul(fsub(y2, y1, SP), finv(fsub(x2, x1, SP), SP), SP)
    x3 = fsub(fsub(fmul(m, m, SP), x1, SP), x2, SP)
    return x3, fsub(fmul(m, fsub(x1, x3, SP), SP), y1, SP)

def s_mul(k, P=G):
    R = INF
    while k:
        if k & 1: R = s_add(R, P)
        P = s_add(P, P); k >>= 1
    return R

def ecdsa_verify(Q, z, r, s):
    if not (1 <= r < SN and 1 <= s < SN): return False
    w = pow(s, -1, SN)
    P = s_add(s_mul(z * w % SN), s_mul(r * w % SN, Q))
    return P is not INF and P[0] % SN == r

# ---- Ed25519 (RFC 8032) ---------------------------------------------
QP = 2**255 - 19
L = 2**252 + 27742317777372353535851937790883648493
D = fmul(-121665 % QP, finv(121666, QP), QP)
I = fpow(2, (QP - 1) // 4, QP)

def xrecover(y):
    xx = fmul(fsub(fmul(y, y, QP), 1, QP),
              finv(fadd(fmul(D, fmul(y, y, QP), QP), 1, QP), QP), QP)
    x = fpow(xx, (QP + 3) // 8, QP)
    if fsub(fmul(x, x, QP), xx, QP) != 0: x = fmul(x, I, QP)
    if x & 1: x = QP - x  # choose even x (base point convention)
    return x

BY = fmul(4, finv(5, QP), QP)
B = (xrecover(BY), BY)

def e_add(P, Q):
    (x1, y1), (x2, y2) = P, Q
    t = fmul(D, fmul(fmul(x1, x2, QP), fmul(y1, y2, QP), QP), QP)
    x3 = fmul(fadd(fmul(x1, y2, QP), fmul(x2, y1, QP), QP),
              finv(fadd(1, t, QP), QP), QP)
    y3 = fmul(fadd(fmul(y1, y2, QP), fmul(x1, x2, QP), QP),
              finv(fsub(1, t, QP), QP), QP)
    return x3, y3

def e_mul(k, P=B):
    R = (0, 1)
    while k:
        if k & 1: R = e_add(R, P)
        P = e_add(P, P); k >>= 1
    return R

def encode_point(P):
    x, y = P
    bits = y | ((x & 1) << 255)
    return bits.to_bytes(32, "little")

def decode_point(bts):
    v = int.from_bytes(bts, "little")
    y = v & ((1 << 255) - 1)
    x = xrecover(y)
    if (x & 1) != (v >> 255): x = QP - x
    return x, y

def hint(m): return int.from_bytes(hashlib.sha512(m).digest(), "little")

def ed_publickey(seed32):
    h = hashlib.sha512(seed32).digest()
    a = bytearray(h[:32]); a[0] &= 248; a[31] &= 63; a[31] |= 64
    return encode_point(e_mul(int.from_bytes(a, "little")))

def ed_sign(seed32, msg):
    h = hashlib.sha512(seed32).digest()
    a = bytearray(h[:32]); a[0] &= 248; a[31] &= 63; a[31] |= 64
    a = int.from_bytes(a, "little")
    A = encode_point(e_mul(a))
    r = hint(h[32:] + msg) % L
    R = encode_point(e_mul(r))
    S = (r + hint(R + A + msg) * a) % L
    return R + S.to_bytes(32, "little")

def ed_verify(pub32, msg, sig64):
    if len(sig64) != 64: return False
    R = decode_point(sig64[:32])
    A = decode_point(pub32)
    S = int.from_bytes(sig64[32:], "little")
    if S >= L: return False
    return e_mul(S) == e_add(R, e_mul(hint(sig64[:32] + pub32 + msg) % L, A))

# ---- tests -----------------------------------------------------------
if __name__ == "__main__":
    # secp256k1 anchors
    g2 = (0xC6047F9441ED7D6D3045406E95C07CD85C778E4B8CEF3CA7ABAC09B95C709EE5,
          0x1AE168FEA63DC339A3C58419466CEAEEF7F632653266D0E1236431A950CFE52A)
    assert s_mul(2) == g2, "2G mismatch"
    assert s_mul(SN) is INF, "n*G must be infinity"
    z = int.from_bytes(hashlib.sha256(b"museRISC").digest(), "big")
    r = 0x9d9f248547cf1efdd027a67dbc54c56e9f95ef15de91651cc59a4cb65a1f72a7
    s = 0x33c5aedbec0309c3fd8821eb4fb1d92e6b82031cc6a97e85b6debfc1634fa509
    assert ecdsa_verify(G, z, r, s), "ECDSA verify failed"
    assert not ecdsa_verify(G, z ^ 1, r, s), "tampered ECDSA accepted"
    print("secp256k1: 2G, n*G=inf, ECDSA verify + tamper OK")

    # Ed25519 RFC 8032 vectors
    for seed, pub, msg, sig in [
        ("9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60",
         "d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a",
         "",
         "e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e06522490155"
         "5fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b"),
        ("4ccd089b28ff96da9db6c346ec114e0f5b8a319f35aba624da8cf6ed4fb8a6fb",
         "3d4017c3e843895a92b70aa74d1b7ebc9c982ccf2ec4968cc0cd55f12af4660c",
         "72",
         "92a009a9f0d4cab8720e820b5f642540a2b27b5416503f8fb3762223ebdb69da"
         "085ac1e43e15996e458f3613d0f11d8c387b2eaeb4302aeeb00d291612bb0c00"),
    ]:
        seed, pub, msg, sig = (bytes.fromhex(seed), bytes.fromhex(pub),
                               bytes.fromhex(msg), bytes.fromhex(sig))
        assert ed_publickey(seed) == pub, "Ed25519 pubkey mismatch"
        assert ed_sign(seed, msg) == sig, "Ed25519 sign != RFC 8032"
        assert ed_verify(pub, msg, sig), "Ed25519 verify failed"
        assert not ed_verify(pub, msg + b"x", sig), "tampered Ed accepted"
    print("Ed25519: RFC 8032 TEST 1+2 sign/verify + tamper OK")
    print("EC_OPS PASS")
