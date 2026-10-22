# SHA-256 hash chain and bulk hashing

Issue [#10](https://github.com/bubblebabyboi/sigil/issues/10) for the
performance harness ([`docs/PERFORMANCE.md`](../../../docs/PERFORMANCE.md)).
Two benchmarks share the implementations in this directory:

| Benchmark | Work per region | `iterations` (default) | Harness metric |
|---|---|---|---|
| `sha256chain` | hash chain h<sub>i+1</sub> = H(h<sub>i</sub>), *N* hashes | *N* hashes (1024) | cycles/iter = cycles/hash |
| [`sha256chain_bulk`](../sha256chain_bulk/) | hash a buffer once | buffer size in KiB (64) | bytes/cycle (`bytes_per_iteration` 1024) |

```sh
make -C sim perf BENCHES="sha256chain sha256chain_bulk"            # both, soc + axi
make -C sim perf BENCHES=sha256chain MEM=soc REPEAT=2              # determinism check
make -C sw/bench/sha256chain run                                   # one run on soc_rtl_tb
```

The build needs `python3` (see *Validation*).

## Implementations

| Region | `sha256chain` | `sha256chain_bulk` |
|---|---|---|
| 0 | SHA-256, plain C | SHA-256 of the buffer, plain C |
| 1 | SHA-256, C + Zknh | SHA-256 of the buffer, C + Zknh |
| 2 | SHA-256, RVV ×16: 16 independent chains | SHA-256 of 16 equal segments, RVV ×16 |
| 3 | SHA-256 on the accelerator, `sigil_sha256_block()` | SHA-512 on the accelerator, `sigil_hash()` |
| 4 | SHA-256 on the accelerator, `sigil_sha256()` | SHA3-256 on the accelerator, `sigil_hash()` |
| 5 | SHA-512 chain on the accelerator, `sigil_hash()` | |
| 6 | SHA3-256 chain on the accelerator, `sigil_hash()` | |

- **Plain C** ([`sha256_sw.c`](sha256_sw.c)): the FIPS 180-4 textbook
  form: a 64-word schedule array and eight working variables. GCC
  compiles the rotates to Zbb `roriw`.
- **Zknh**: the same template with the four sigma functions computed by
  `sha256sum0/sum1/sig0/sig1` (the `<riscv_crypto.h>` intrinsics). It
  differs from plain C only in those four functions.
  - Both scalar versions read message words with an aligned 32-bit load
    plus `__builtin_bswap32` (Zbb `rev8`) when the input is 4-byte
    aligned, and byte by byte otherwise.
  - `sha256_sw.c` turns off auto-vectorization and loop-to-`memcpy`
    distribution. Without that, GCC turns the word-copy loops into
    `vle8`/`vse8` loops on the element-serial vector unit.
- **RVV ×16** ([`sha256_rvv.c`](sha256_rvv.c)): multi-buffer. Each
  32-bit lane (e32, LMUL 1, 16 lanes at VLEN 512) hashes its own
  message. The working variables and a rolling 16-word schedule stay
  in 24 vector registers, with the rounds unrolled 16 at a time.
  - The core has no Zvbb or Zvknh, so each rotate takes three ops
    (`vsrl`, `vsll`, `vxor`). A round is about 36 vector ops and a
    schedule word 21.
  - The vector unit is element-serial: an e32 ALU op at vl 16 takes
    20 cycles (`docs/CORE.md`). RVV ×16 therefore measures throughput
    over many independent messages, not the latency of one hash.
  - `sha256chain` splits the *N* hashes over 16 chains. Lane *j* runs
    *N*/16 steps, plus one more for *j* < *N* mod 16; that extra step
    runs at vl = *N* mod 16.
  - `sha256chain_bulk` hashes the buffer as 16 contiguous segments,
    one per lane, as for a Merkle leaf layer. Its digests are therefore
    the 16 segment digests, not the digest of the whole buffer. Two
    strided segment loads (`vlsseg8e32`) fetch a block of every lane,
    and a byte gather (`vrgather.vv`, e8) converts it from big-endian.
    The padding block is shared: every lane reads it with stride 0.
  - Plain strided loads (`vlse32`, one per word) would be a poor fit. The
    segments sit 4 KiB apart at 64 KiB, so the 16 lanes' lines of a
    block all fall in the same 4-way D$ set. One strided load per word
    would cycle 16 lines through that set 16 times per block and thrash
    it. Each segment load reads 8 consecutive words of one line per
    lane.
  - An empty `asm` barrier finishes words 0–7 before the second segment
    load. Without it, GCC issues both loads first and spills a register
    group with whole-register stores.
- **Accelerator**: the SDK driver as shipped (`sw/sdk/lib/accel.c`).
  - The SHA-256 engine compresses one block from the IV per start, with
    no chaining. It can hash each 32-byte chain step, which is exactly
    one padded block, but not a multi-block message. The bulk benchmark
    therefore runs SHA-512 and SHA3-256 on the streaming engine, which
    accepts 4 bytes per MMIO store and pads in hardware, and has no
    SHA-256 accelerator region.
  - `sigil_sha256_block()` takes the chain step in word form: the 8
    digest words are the next message words 0–7. `sigil_sha256()` is
    the byte API, which packs, pads and unpacks the bytes on every call.
  - The SHA-512 chain hashes the whole 64-byte digest at each step.

## Build

Both benchmarks use the SDK flags (`sw/sdk/sdk.mk`: `-O2 -mstrict-align
-mcmodel=medany -ffreestanding -std=gnu11`) with the SDK default
`-march` (`rv64gcv` plus B, Zbc, Zcb, Zicond, Zbk\* and Zkn\*), so one
image holds every implementation. The variant is `sdk`. The Makefiles add
`-falign-functions=64`, which starts every function on an I$ line:

- The front end fetches 4-byte words, so shifting a function by 2 bytes
  changes which of its 32-bit instructions straddle two words.
- With identical instructions, the Zknh chain measured 7,212 cycles per
  hash at offset 2 mod 4 and 6,753 at offset 0. Before the flag was
  added, the code linked before the function decided the offset, and
  that code changed with the iteration count.
- The SDK's `sigil_hash` chains gained the most: the SHA-512 chain took
  43% more cycles before alignment (evidence:
  `docs/evidence/perf-sha256chain-56-2026-10-22`).
- With the flag, each region's code placement does not depend on the
  code linked before it.

Each region is a single call: the accelerator loops are functions too.

## Inputs

- **Chain seeds.** Byte *k* of lane *j*'s seed is (*k* + 17*j*) mod
  256. The single chains start from lane 0's seed: bytes 0, 1, 2, …,
  32 of them, or 64 for SHA-512.
- **Bulk buffer.** The LCG of `sw/examples/hash_stream`:
  *x* ← *x*·1103515245 + 12345 mod 2<sup>32</sup>, starting from
  *x* = 12345, and each byte is (*x* >> 16) & 0xff.
- The buffer and the seeds are set up before the regions. Every region
  measures exactly the hashing loop.

## Validation

A run passes only if every check below passes. Otherwise the program
calls `sigil_fail()`.

1. **Known answers, before any region**
   ([`sha256_kat.c`](sha256_kat.c)). They also warm the caches with the
   measured code.
   - **SHA-256 (FIPS 180-4).** `""`, `"abc"` and the 448-bit two-block
     message, on plain C and Zknh.
   - **RVV.** All 16 lanes, with one- and two-block messages. At
     vl = 5, the tail lanes must be left untouched. At vl = 3, the RVV
     chain must equal the plain-C chain.
   - **Accelerator, SHA-256.** `""` and `"abc"`, through `sigil_sha256()`
     and `sigil_sha256_block()`. These are one-block messages only (see
     above).
   - **Accelerator, SHA-512 (FIPS 180-4).** `"abc"` and the 896-bit
     message.
   - **Accelerator, SHA3-256 (FIPS 202).** `""` and `"abc"`.
2. **Results, after each region.** Every final chain value or digest is
   compared with Python `hashlib` (OpenSSL). That includes the 16 lane
   values and the SHA-512 and SHA3-256 results. The expected values come
   from [`gen_kat.py`](gen_kat.py), which the Makefile runs at build
   time for the image's *N* or buffer size (`$(OUT)/*_kat_<n>.h`), so
   `ITER=` overrides are checked too.
3. **Harness `expect` lines.** The three KAT lines and
   `SHA256CHAIN CHECK OK hashes=<N>` (or
   `SHA256CHAIN_BULK CHECK OK kib=<K>`).

## Output

Each region prints the harness's `SIGIL PERF` line and a `RESULT` line
with:
- cycles per hash (or per KiB);
- bytes/cycle, counting 32 message bytes per SHA-256 or SHA3-256 hash
  and 64 per SHA-512 hash;
- hashes/s (or KiB/s) at 62.5 MHz (F2 today) and at 100 MHz (target).

On hardware, where only `mcycle`/`minstret` exist, this is the
measurement. Measured numbers are kept in `docs/evidence/`, not here.

The harness's bytes/cycle metric takes one `bytes_per_iteration` for
every region of a bench. `sha256chain` mixes 32- and 64-byte messages,
so it declares no harness metric: its rows report cycles/hash
(`cycles/iter`), and bytes/cycle is in the `RESULT` lines.
