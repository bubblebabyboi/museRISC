# museRISC Specification (v0.1, Phase 0)

## 1. Goal

A verifiable RV64GCV SoC with hardware acceleration for Solana /
Ethereum / Bitcoin primitives, hardened with OpenROAD, on a credible
path to an MPW shuttle. v1 target is simulation + OpenROAD only.

## 2. ISA contract (target, phased)

RV64GCV = RV64I + Zicsr/Zifencei + M + A + F + D + C + V (RVV 1.0),
privileged spec with Sv39, M/S/U modes (via CVA6). Compliance is only
claimed per-extension after the matrix in COMPLIANCE.md passes.
Floating point must pass TestFloat vectors; vector must pass the RVV
arch tests with a fixed VLEN (default 512 via Ara, configurable).

## 3. Crypto accelerator (`muse_crypto`, original RTL)

Memory-mapped AXI-Lite slave (base `0x2000_0000` in SoC map, RTL in
`rtl/crypto/muse_crypto_top.sv`, integration KATs in
`tb/cpp/crypto_top_tb.cpp` and `tb/cpp/hash_stream_tb.cpp` via
`make test`). Register map (32-bit regs):

| Offset | Name | Meaning |
|---|---|---|
| 0x00 | CTRL | bit0=start, bits[5:4]=engine (0=SHA256, 1=reserved/ignored, 2=Field), bits[7:6]=field op (0=add,1=sub,2=mul) |
| 0x04 | STATUS | bit0=busy, bit1=done (SHA-256 / field engines only) |
| 0x08–0x47 | DIN0..15 / A,B | Input block / field operands |
| 0x48–0x67 | DOUT0..7 | Digest / field result |
| 0x68 | MODSEL | 0=secp256k1 p, 1=Curve25519 p, 2=custom MOD regs |
| 0x6C–0x8B | MOD0..7 | Custom modulus |
| 0x8C | HCTRL | W: bit0=INIT (new message, mode = bits[5:4]), bit1=SQUEEZE (Keccak modes, when done; ignored with INIT). R: bits[5:4]=mode. Mode: 0=SHA-512, 1=SHA3-256, 2=Keccak-256, 3=SHAKE256 |
| 0x90 | HSTATUS | R: bit0=busy, bit1=done (output valid), bit2=ready (HDATA/HFIN taken without stall), bit3=err (sticky until INIT) |
| 0x94 | HDATA | W: append 4 message bytes, first byte in bits[7:0] |
| 0x98 | HFIN | W: end of message: bits[25:24]=n (0..3) trailing bytes in bits[8n-1:0]; hardware pads and finishes |
| 0x9C | HOPTR | R/W: output word index (0..33); reset to 0 by INIT/SQUEEZE |
| 0xA0 | HDOUT | R: output word HOPTR (first output byte in bits[7:0] of word 0), then HOPTR += 1 |

Engines in this repo today:

- **SHA-256** (FIPS 180-4): one 512-bit block per start from the
  IV (no chaining), standard padding done by driver/SW; KATs in
  `tb/cpp/`.
- **Streaming hash** (`rtl/crypto/muse_hash_stream.sv`, issue #6):
  arbitrary-length SHA-512 (FIPS 180-4) and Keccak sponge at rate
  1088 / capacity 512 (FIPS 202): SHA3-256 (domain `0x06`),
  Keccak-256 (original Keccak padding `0x01`, as used by Ethereum)
  and SHAKE256 (`0x1F`, multi-block squeeze). Built on
  `sha512_block.sv` (chaining `cont` input) and `keccak_f1600.sv`.
  See 3.1.
- **EC field unit**: 256-bit add/sub/mul-mod with selectable modulus
  (secp256k1 `p = 2^256-2^32-977`; Curve25519 `p = 2^255-19`).
  Point add/double and scalar multiplication are firmware sequences
  over this unit in Phase 1–2, dedicated hardware sequencer later.
  All secret-dependent paths must be constant-time (no early exit,
  no secret-indexed tables) — review gate before any key handling.

### 3.1 Streaming hash interface (issue #6)

Driver sequence for a message `m` of `len` bytes:

1. `HCTRL = (mode << 4) | 1` (INIT; clears the buffer, length and
   `err`; the SHA-256/field registers are untouched and both sides
   can be used in any interleaving).
2. For each whole 4-byte word of `m`, write it to HDATA
   (little-endian: `m[4i]` in bits[7:0]).
3. Write HFIN = `(n << 24) | tail`, where `n = len % 4` and `tail`
   holds the last `n` bytes the same way. HFIN is required even when
   `n = 0`, and it is the only end-of-message marker.
4. Poll HSTATUS until done (bit1). Read the output from HDOUT
   (auto-incrementing; HOPTR can be written for random access).
   SHA-512: 16 words (64 bytes, digest byte order). SHA3-256 /
   Keccak-256: the first 8 words are the 32-byte digest. Keccak
   modes expose the whole 136-byte rate (34 words); for SHAKE256
   output beyond that, write `HCTRL = 2` (SQUEEZE), wait for done
   again and read the next 34 words.

Hardware buffers one rate block (128 B SHA-512, 136 B Keccak);
padding (`0x80 … ‖ 128-bit length` for SHA-512, `pad10*1` with the
domain byte for Keccak) is inserted in hardware. A full block is
handed to the core, which latches it, so software can refill the
buffer while the previous block is compressed (80 cycles SHA-512,
24 Keccak). Only when the buffer is full again and the core is
still busy does the slave hold AWREADY low on HDATA/HFIN writes,
so software may write back to back without polling; HSTATUS.ready
exposes the same condition for polling drivers. Data/FIN outside
an open message, and SQUEEZE outside a done Keccak-mode message, are
ignored and set the sticky `err` bit. A new INIT aborts the current
message at any time. Messages up to 2^64−1 bytes (64-bit byte counter).

Choice and rationale: **register FIFO streaming with hardware
padding, no DMA.** One MMIO store per 4 message bytes (plus AXI
backpressure) removes the one-block-per-burst limit without giving
the accelerator a bus-master port. A DMA engine would need a second
master on the SoC memory bus (arbitration with the CPU's L1 refill
path in `muserisc_soc_fabric`), coherence with the write-back L1
D$ (flushes or a snooping path before every hash), address
translation/PMP rules for a device master, and a bigger
verification surface; none of it is needed for correctness, and
the per-word store cost is small next to the hash rounds for the
target workloads (Ed25519 `SHA-512(R‖A‖M)`, transaction hashing).
Byte-granular input with in-hardware padding keeps drivers trivial
and makes the length/padding logic part of the KAT-verified RTL.
DMA can be added later as a front end that writes the same HDATA/
HFIN port. CTRL engine select 1 stays reserved: the streaming engine
has its own control register, so existing SHA-256/field drivers see
no change (including STATUS, which does not reflect hash activity).

Security note: Phase 0 is a functional accelerator, **not** a
side-channel-hardened HSM. No private keys on this design until the
constant-time + fault review in ROADMAP Phase 2 is complete.

## 4. Memory map (SoC)

Implemented by `rtl/soc/muserisc_soc_top.sv` (issue #4) and
shared by the RTL SoC, the `soc_tb` C++ platform, and
`sw/linux/muserisc.dts`:

`0x0000_1000` boot ROM (4 KiB) · `0x0200_0000` CLINT ·
`0x0C00_0000` PLIC · `0x1000_0000` 16550 UART ·
`0x2000_0000` crypto · `0x8000_0000` external RAM window.
The SoC instantiates `muserisc_cpu` (core + L1 I$/D$);
`muserisc_soc_fabric` routes its memory bus: the RAM window to
the external `mem_req_*`/`mem_rsp_*` memory-bus port
(valid/ready requests, line bursts, any latency; AXI4-mappable,
see `docs/CORE.md`), everything else to the on-chip devices as
single uncached accesses. Crypto is reached through a scalar-
MMIO to AXI4-Lite bridge whose stall holds the fabric's device
access (also while the accelerator backpressures a hash-stream
write). RAM is external at block level (simulation model, ASIC
SRAM wrapper, or FPGA BRAM/DDR bridge behind the memory bus).

Cacheability (PMA): the L1 caches cache only the configured
windows — by default `0x8000_0000..0xFFFF_FFFF` (DRAM);
everything else (ROM, CLINT, PLIC, UART, crypto) is I/O,
accessed uncached as single in-order bus beats so device side
effects happen exactly once.

## 5. Physical targets (v1, non-binding)

Nangate45 @ 100 MHz for `muse_crypto` macro closure in ORFS;
Sky130HD config provided for the same macro. Full-SoC Sky130 closure
is expected to be area-dominated (RV64GCV + crypto ≫ TinyTapeout tile,
tight even in Caravel user area) — hierarchy/macro hardening required.
