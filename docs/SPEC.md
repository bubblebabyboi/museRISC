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
`rtl/crypto/muse_crypto_top.sv`, integration KAT in
`tb/cpp/crypto_top_tb.cpp` via `make test`). Register map (32-bit regs):

| Offset | Name | Meaning |
|---|---|---|
| 0x00 | CTRL | bit0=start, bits[5:4]=engine (0=SHA256,1=Keccak reserved,2=Field), bits[7:6]=field op (0=add,1=sub,2=mul) |
| 0x04 | STATUS | bit0=busy, bit1=done |
| 0x08–0x47 | DIN0..15 / A,B | Input block / field operands |
| 0x48–0x67 | DOUT0..7 | Digest / field result |
| 0x68 | MODSEL | 0=secp256k1 p, 1=Curve25519 p, 2=custom MOD regs |
| 0x6C–0x8B | MOD0..7 | Custom modulus |

Engines in this repo today:

- **SHA-256** (FIPS 180-4): one 512-bit block per start, standard
  padding done by driver/SW shim for messages; KATs in `tb/cpp/`.
- **Keccak-f1600** permutation (FIPS 202): sponge wrapper in SW for
  SHA3-256 / Keccak-256 rate=1088; permutation KATs in `tb/cpp/`.
- **EC field unit**: 256-bit add/sub/mul-mod with selectable modulus
  (secp256k1 `p = 2^256-2^32-977`; Curve25519 `p = 2^255-19`).
  Point add/double and scalar multiplication are firmware sequences
  over this unit in Phase 1–2, dedicated hardware sequencer later.
  All secret-dependent paths must be constant-time (no early exit,
  no secret-indexed tables) — review gate before any key handling.

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
access. RAM is external at block level (simulation model, ASIC
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
