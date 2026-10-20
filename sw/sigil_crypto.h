/* Sigil crypto accelerator register map (see docs/SPEC.md).
 * Base in SoC: 0x2000_0000. Registers are little-endian w.r.t. DIN:
 * DIN0 holds the first SHA-256 message word / the low field word,
 * DOUT0 holds the low word of the 256-bit result. */
#ifndef SIGIL_CRYPTO_H
#define SIGIL_CRYPTO_H
#define SIGIL_CRYPTO_BASE   0x20000000UL
#define SIGIL_CTRL          (SIGIL_CRYPTO_BASE + 0x00) /* b0 start, b[5:4] engine, b[7:6] field op */
#define SIGIL_STATUS        (SIGIL_CRYPTO_BASE + 0x04) /* b0 busy, b1 done */
#define SIGIL_DIN(i)        (SIGIL_CRYPTO_BASE + 0x08 + 4*(i))  /* i=0..15 */
#define SIGIL_DOUT(i)       (SIGIL_CRYPTO_BASE + 0x48 + 4*(i))  /* i=0..7  */
#define SIGIL_MODSEL        (SIGIL_CRYPTO_BASE + 0x68) /* 0 secp256k1, 1 Curve25519, 2 custom */
#define SIGIL_MOD(i)        (SIGIL_CRYPTO_BASE + 0x6C + 4*(i))  /* i=0..7  */
#define SIGIL_ENG_SHA256    0
#define SIGIL_ENG_KECCAK_RSVD 1 /* reserved/ignored: hashing uses SIGIL_H* below */
#define SIGIL_ENG_FIELD     2
#define SIGIL_FLD_ADD 0
#define SIGIL_FLD_SUB 1
#define SIGIL_FLD_MUL 2

/* Streaming hash engine (docs/SPEC.md 3.1): arbitrary-length messages,
 * padding in hardware. Sequence: SIGIL_HCTRL = SIGIL_HCTRL_INIT(mode);
 * each whole 4-byte word -> SIGIL_HDATA (first byte in bits[7:0]);
 * SIGIL_HFIN = SIGIL_HFIN_WORD(n, tail) with n = len % 4 (always, also
 * for n = 0); poll SIGIL_HSTATUS for SIGIL_HS_DONE; read SIGIL_HDOUT
 * (auto-increments SIGIL_HOPTR). HDATA/HFIN stores stall in hardware
 * while the block buffer is full, so no polling is needed between
 * words. SHAKE256: after 34 words write SIGIL_HCTRL = SIGIL_HCTRL_SQUEEZE
 * and wait for SIGIL_HS_DONE again. */
#define SIGIL_HCTRL         (SIGIL_CRYPTO_BASE + 0x8C) /* W b0 init, b1 squeeze, b[5:4] mode; R b[5:4] mode */
#define SIGIL_HSTATUS       (SIGIL_CRYPTO_BASE + 0x90) /* b0 busy, b1 done, b2 ready, b3 err */
#define SIGIL_HDATA         (SIGIL_CRYPTO_BASE + 0x94) /* W 4 message bytes */
#define SIGIL_HFIN          (SIGIL_CRYPTO_BASE + 0x98) /* W b[25:24] n tail bytes, b[23:0] bytes */
#define SIGIL_HOPTR         (SIGIL_CRYPTO_BASE + 0x9C) /* R/W output word index 0..33 */
#define SIGIL_HDOUT         (SIGIL_CRYPTO_BASE + 0xA0) /* R output word, HOPTR++ */
#define SIGIL_HASH_SHA512    0 /* 64-byte digest, 16 words */
#define SIGIL_HASH_SHA3_256  1 /* 32-byte digest, 8 words */
#define SIGIL_HASH_KECCAK256 2 /* 32-byte digest (Ethereum Keccak-256) */
#define SIGIL_HASH_SHAKE256  3 /* 136 bytes per squeeze */
#define SIGIL_HCTRL_INIT(mode) (((unsigned)(mode) << 4) | 1u)
#define SIGIL_HCTRL_SQUEEZE  2u
#define SIGIL_HFIN_WORD(n, tail) (((unsigned)(n) << 24) | ((unsigned)(tail) & 0xFFFFFFu))
#define SIGIL_HS_BUSY  1u
#define SIGIL_HS_DONE  2u
#define SIGIL_HS_READY 4u
#define SIGIL_HS_ERR   8u
#endif
