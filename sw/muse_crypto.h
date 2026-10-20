/* museRISC crypto accelerator register map (see docs/SPEC.md).
 * Base in SoC: 0x2000_0000. Registers are little-endian w.r.t. DIN:
 * DIN0 holds the first SHA-256 message word / the low field word,
 * DOUT0 holds the low word of the 256-bit result. */
#ifndef MUSE_CRYPTO_H
#define MUSE_CRYPTO_H
#define MUSE_CRYPTO_BASE   0x20000000UL
#define MUSE_CTRL          (MUSE_CRYPTO_BASE + 0x00) /* b0 start, b[5:4] engine, b[7:6] field op */
#define MUSE_STATUS        (MUSE_CRYPTO_BASE + 0x04) /* b0 busy, b1 done */
#define MUSE_DIN(i)        (MUSE_CRYPTO_BASE + 0x08 + 4*(i))  /* i=0..15 */
#define MUSE_DOUT(i)       (MUSE_CRYPTO_BASE + 0x48 + 4*(i))  /* i=0..7  */
#define MUSE_MODSEL        (MUSE_CRYPTO_BASE + 0x68) /* 0 secp256k1, 1 Curve25519, 2 custom */
#define MUSE_MOD(i)        (MUSE_CRYPTO_BASE + 0x6C + 4*(i))  /* i=0..7  */
#define MUSE_ENG_SHA256    0
#define MUSE_ENG_KECCAK_RSVD 1 /* reserved/ignored: hashing uses MUSE_H* below */
#define MUSE_ENG_FIELD     2
#define MUSE_FLD_ADD 0
#define MUSE_FLD_SUB 1
#define MUSE_FLD_MUL 2

/* Streaming hash engine (docs/SPEC.md 3.1): arbitrary-length messages,
 * padding in hardware. Sequence: MUSE_HCTRL = MUSE_HCTRL_INIT(mode);
 * each whole 4-byte word -> MUSE_HDATA (first byte in bits[7:0]);
 * MUSE_HFIN = MUSE_HFIN_WORD(n, tail) with n = len % 4 (always, also
 * for n = 0); poll MUSE_HSTATUS for MUSE_HS_DONE; read MUSE_HDOUT
 * (auto-increments MUSE_HOPTR). HDATA/HFIN stores stall in hardware
 * while the block buffer is full, so no polling is needed between
 * words. SHAKE256: after 34 words write MUSE_HCTRL = MUSE_HCTRL_SQUEEZE
 * and wait for MUSE_HS_DONE again. */
#define MUSE_HCTRL         (MUSE_CRYPTO_BASE + 0x8C) /* W b0 init, b1 squeeze, b[5:4] mode; R b[5:4] mode */
#define MUSE_HSTATUS       (MUSE_CRYPTO_BASE + 0x90) /* b0 busy, b1 done, b2 ready, b3 err */
#define MUSE_HDATA         (MUSE_CRYPTO_BASE + 0x94) /* W 4 message bytes */
#define MUSE_HFIN          (MUSE_CRYPTO_BASE + 0x98) /* W b[25:24] n tail bytes, b[23:0] bytes */
#define MUSE_HOPTR         (MUSE_CRYPTO_BASE + 0x9C) /* R/W output word index 0..33 */
#define MUSE_HDOUT         (MUSE_CRYPTO_BASE + 0xA0) /* R output word, HOPTR++ */
#define MUSE_HASH_SHA512    0 /* 64-byte digest, 16 words */
#define MUSE_HASH_SHA3_256  1 /* 32-byte digest, 8 words */
#define MUSE_HASH_KECCAK256 2 /* 32-byte digest (Ethereum Keccak-256) */
#define MUSE_HASH_SHAKE256  3 /* 136 bytes per squeeze */
#define MUSE_HCTRL_INIT(mode) (((unsigned)(mode) << 4) | 1u)
#define MUSE_HCTRL_SQUEEZE  2u
#define MUSE_HFIN_WORD(n, tail) (((unsigned)(n) << 24) | ((unsigned)(tail) & 0xFFFFFFu))
#define MUSE_HS_BUSY  1u
#define MUSE_HS_DONE  2u
#define MUSE_HS_READY 4u
#define MUSE_HS_ERR   8u
#endif
