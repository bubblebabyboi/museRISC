<!--
DRAFT release notes for tag sigil-linux-f2-2026-10-22 (epic #73). Remove this
comment before publishing.

Suggested title: "Sigil 2026-10-22b: Debian 13 on AWS F2 with 64 GiB DDR4 + 16 GiB HBM (public AFI)"

Assets are staged on sigil-fpga-build:~/release-73/ by
~/rel73-work/stage_release73.sh (checks the DCP against the evidence, the OS
artifacts against ~/os-artifacts/SHA256SUMS, the programs against
fw/SHA256SUMS; reproducible tarballs; no file over 2 GiB).

Before publishing:
1. Fill every `<... pending>` placeholder from the first F2 Debian boot
   (evidence on 73-linux-debian). Do not publish with a placeholder left:
   grep -nE 'pending>|restage after' docs/evidence/linux-release-73-notes-draft.md
2. Copy the new F2 boot evidence directory into ~/rel73-work/evidence/ and
   rerun the stage script: sigil_linux_evidence_2026-10-22.tar.gz and
   SHA256SUMS change, so update their rows in the assets table.
3. If the boot run changes the sigil_host command (docs/LINUX.md section 4),
   update "Boot Debian on your own F2" to match.
-->

The whole Sigil SoC — the in-house RV64GCV core (vector unit, L1 caches) plus the crypto/hash engine and peripherals — now runs **Debian 13 "trixie" with gcc and glibc on a real AWS F2 FPGA**, with **all of the board's memory**: 48 GiB DDR4 as NUMA node 0, **16 GiB HBM as NUMA node 1**, and a 16 GiB DDR4 window as the root disk `/dev/pmem0`. New **public AFI**, Sigil-built OpenSBI v1.9 + Linux 6.12 LTS payloads, and a ready-to-boot Debian image.

## Boot Debian on your own F2

Public AFI **`agfi-0a1fd54ef68bdc754`** (AFI `afi-035809e576d7ea8d5`, us-east-1, Small Shell `0x10212415`, PCI `0x1D0F:0xF054`), core clock **62.5 MHz** (interim; 100 MHz is #53), HBM AXI 250 MHz.

```sh
# on an f2.6xlarge (FPGA Developer AMI, us-east-1)
git clone -b v2.3.5 https://github.com/aws/aws-fpga ~/aws-fpga && (cd ~/aws-fpga && source sdk_setup.sh)
sudo fpga-load-local-image -S 0 -I agfi-0a1fd54ef68bdc754 -H
git clone https://github.com/bubblebabyboi/sigil ~/sigil && make -C ~/sigil/fpga/host SDK_DIR=$HOME/aws-fpga/sdk

# the boot payloads and the Debian disk from this release
R=https://github.com/bubblebabyboi/sigil/releases/download/sigil-linux-f2-2026-10-22
mkdir -p ~/sigil-linux && cd ~/sigil-linux
for f in SHA256SUMS fw_jump.bin Image sigil-f2.dtb sigil-debian-13-riscv64.ext4.zst; do curl -fsSLO "$R/$f"; done
sha256sum -c --ignore-missing SHA256SUMS
zstd -d sigil-debian-13-riscv64.ext4.zst            # 8 GiB ext4 image

sudo ~/sigil/fpga/host/sigil_host --linux --fw fw_jump.bin --image Image --dtb sigil-f2.dtb \
     --load 0xC80000000=sigil-debian-13-riscv64.ext4 \
     --save 0xC80000000=sigil-disk-saved.ext4:8G \
     --console --on-reboot exit
```

The console is your terminal. The login prompt appears after **`<F2 boot time, reset to login prompt: pending>`** (QEMU-based estimate: about 9 minutes at 62.5 MHz). Log in as **`sigil` / `sigil`** (sudo) or `root` / `sigil`, then for example:

```sh
gcc hello.c && ./a.out                          # native gcc 14 / glibc 2.41
numactl --hardware                              # node 0 = DDR4 48 GiB, node 1 = HBM 16 GiB
numactl --membind=1 ~/examples/memwhere 1024    # 1 GiB placed in HBM
sudo poweroff                                   # host saves the disk to sigil-disk-saved.ext4
```

After `poweroff` the host saves the file system, so the next boot can start from it with `--load 0xC80000000=sigil-disk-saved.ext4`. Ctrl-] detaches without saving a consistent disk. The first run after an AFI load zeroes all DDR4 once, which takes about 17 s.

Guides: [`docs/LINUX.md`](https://github.com/bubblebabyboi/sigil/blob/main/docs/LINUX.md) (build it, QEMU, F2, NUMA, vector code, the disk), [`docs/LINUX_PLATFORM.md`](https://github.com/bubblebabyboi/sigil/blob/main/docs/LINUX_PLATFORM.md) (memory map and devices), [`docs/FPGA_F2.md`](https://github.com/bubblebabyboi/sigil/blob/main/docs/FPGA_F2.md#flash-sigil-on-your-own-f2) (the AFI and `sigil_host`). Bare-metal programs still work as before: [`docs/PROGRAMMING.md`](https://github.com/bubblebabyboi/sigil/blob/main/docs/PROGRAMMING.md), `sudo fpga/host/sigil_host --bin prog.bin` (no `--ignore-mem-err` needed any more).

## What is in the image

| Layer | What |
|---|---|
| Firmware | OpenSBI **v1.9** generic `fw_jump` (`cbf9f673`) + a Sigil patch that writes back the L1 D$ before power-off/reboot |
| Kernel | Linux **6.12.114 LTS**, `sw/linux/kernel/sigil_defconfig`; user-space vector on Zve64d (VLEN 512) |
| Device tree | `sigil-f2.dtb` (timebase 62.5 MHz), one source `sw/linux/dts/sigil.dtsi` for F2, QEMU and RTL simulation |
| Root file system | **Debian 13.7 "trixie" riscv64** from `snapshot.debian.org` `20261020T000000Z`, 257 packages, systemd 257, ext4 (8 GiB file system in the 16 GiB pmem window) |
| Tools | build-essential (**gcc/g++ 14.2**, binutils 2.44, make 4.4, **glibc 2.41**), **gdb 16.3**, git 2.47, **python3 3.13**, **numactl/libnuma 2.0.19**, vim, nano, tmux, htop, strace, man pages |
| `~/examples` | `hello`, `malloc_test`, `numa_hbm` (libnuma, DDR4 vs. HBM timing), `memwhere` (NUMA node of every page), `rvv_vadd` (RVV intrinsics), `autovec` (GCC auto-vectorization for Zve64d) |

Memory as Linux sees it on the F2:

| NUMA node | Memory | Physical range | Size |
|---|---|---|---|
| 0 (CPU node) | DDR4 | `0x0_8000_0000 – 0xC_7FFF_FFFF` | 48 GiB |
| — | DDR4 pmem window = root disk `/dev/pmem0` | `0xC_8000_0000 – 0x10_7FFF_FFFF` | 16 GiB |
| 1 (no CPUs) | HBM | `0x10_8000_0000 – 0x14_7FFF_FFFF` | 16 GiB |

## Proven on F2 hardware (measured 62.5 MHz)

**Debian 13 on the new AFI** (`f2.6xlarge`, us-east-1):

| Check | Result |
|---|---|
| Reset → `SIGIL_LINUX_BOOT_OK` → login prompt | `<F2 boot time: pending>` |
| Login, `uname`, systemd state, root on `/dev/pmem0` | `<pending>` |
| `numactl --hardware` (node 0 DDR4, node 1 HBM) | `<pending>` |
| `numactl --membind=1` memory lands in HBM | `<pending>` |
| `gcc hello.c && ./a.out`, time | `<pending>` |
| RVV Zve64d user program (`rvv_vadd`) | `<pending>` |
| `poweroff` → host save → second boot from the saved disk | `<pending>` |

**The memory platform** (same AFI, [`f2-platform-73-2026-10-22`](https://github.com/bubblebabyboi/sigil/blob/main/docs/evidence/f2-platform-73-2026-10-22/SUMMARY.md)):

| Test | Result |
|---|---|
| Full-range memory test, CL memory engine, two seeds | **DDR4 64 GiB + HBM 16 GiB: 0 mismatches, 0 error responses**, 4.0 GB/s |
| Sparse test from the core through the L1s | **DDR4 1,048,576 lines + HBM 262,144 lines over the whole ranges: 0 errors** |
| Cold 64-byte refill latency from the core | **DDR4 729 ns** (45.6 cycles avg) / **HBM 813 ns** (50.8 cycles avg) |
| Bulk load / save through PCIe | **3.6 GB/s** load, 1.0 GB/s save (8 threads); 4 GiB and 8 GiB images round-trip sha256-identical |
| #62 sticky memory error | root cause: ECC on never-written DDR4; fixed by zeroing DDR4 once per AFI load (64 GiB in 17.2 s) |
| #63 UART drops | fixed: Linux console lines intact, 16-byte UART bursts byte-exact |
| Test finisher, RTC | power off / fail code / reboot keeping the disk window; RTC at the host's wall clock, alarm on PLIC source 11 |
| Firmware + all 7 SDK examples, OpenSBI to S-mode | PASS without `--ignore-mem-err` |

Before the hardware run, the same OS was brought up in QEMU shaped like the platform (**23/23 acceptance checks**, [`linux-debian-73-2026-10-22`](https://github.com/bubblebabyboi/sigil/blob/main/docs/evidence/linux-debian-73-2026-10-22/)), and the all-RTL SoC model booted Linux 6.12 to `SIGIL_LINUX_BOOT_OK` in 261 M cycles.

FPGA build: Vivado 2025.2, aws-fpga v2.3.5, commit `e641930`, all timing constraints met (WNS +0.150 ns; core clock +0.635 ns at 16 ns; HBM AXI +0.336 ns at 4 ns); 131,694 LUTs (10.1 % of the VU47P) for the full CL, 82,676 for the SoC.

## Assets

| File | Size | sha256 | What |
|---|---:|---|---|
| `sigil-debian-13-riscv64.ext4.zst` | 221.9 MB | `a9cfcbc977fad8968f07200d595b37ed3df51f7877b7fc0ec26d985e5fb5bf33` | Debian 13 root disk; `zstd -d` gives the 8 GiB ext4 (sha256 `c2d0cd4cf3e543a04e8194283acc7d8c1eec97046189ca8f9d4c1dd9bfe08632`), loaded at `0xC_8000_0000` |
| `fw_jump.bin` | 277.8 kB | `d98908b4ce2187b3a7e26b27f78747b03eb9bd2ee457e4e974d05a49649cacbf` | OpenSBI v1.9 `fw_jump`, loaded at `0x8000_0000` |
| `fw_jump.elf` | 2.3 MB | `c60350fb9bc5cd9ce02f3053bfa0172cbc49adda051da019c11d1ac99291ce3d` | the same with symbols |
| `Image` | 15.5 MB | `0213f645984e386a3799d9be2b9c9bf4de357b2dedbd4a1593b6c3d55f3f7790` | Linux 6.12.114 kernel, loaded at `0x8020_0000` |
| `Image-initramfs` | 15.5 MB | `2f059b6cd7f944d3d2dbdb5b48f837da6351be917f981e15523212e0e4226a48` | the same kernel with a built-in `/init` that prints `SIGIL_LINUX_BOOT_OK` (RTL simulation and QEMU smoke test) |
| `sigil-f2.dtb` | 7.0 kB | `eb1689b43fe38e01d75e36c569d51bb7ea21c3163c10fb6acafa4b466f521e04` | device tree for the F2, loaded at `0x8300_0000` |
| `sigil-qemu.dtb` | 7.8 kB | `9b8313cc7800d0b9368f9ecdf32199afc2507f770b4cba88a5c07c2d19df0a03` | device tree for `scripts/qemu_sigil_boot.sh` |
| `sigil-sim.dtb` | 6.2 kB | `f144da91e67f7ca63cb2189255deac0ad37ad59e00ba3eb4808e8f2ced8c3677` | device tree for the RTL simulation |
| `modules-6.12.114-sigil.tar.gz` | 280.6 kB | `975251423b8e4cc85326187da45ab4a142c97496b6c0c0c99fc647065618812d` | kernel modules (already in the image) |
| `kernel-6.12.114-sigil.config` | 63.7 kB | `dfe19a27fb626f68aa2717ddb77ce0e97eb8d864a148dfe6fba7c6fa87c58bf8` | full kernel configuration |
| `System.map-6.12.114-sigil` | 1.8 MB | `5c1b2e11bfb2153f0ec190a85ccaf1435eba6b970f0a2fd81fedce9fdf3d4ad3` | kernel symbol map |
| `manifest.txt` | 7.9 kB | `09bdec60d5d446f09916628376a01947e21ff2612cf629282c40b724bdf19376` | Debian image manifest: snapshot, kernel, every package with its version |
| `sigil_f2_linux_cl_dcp_e641930.Developer_CL.tar` | 110.9 MB | `69307c690bdcefac9b5d59c786b09f3f7ffa8cf8ea64a51ffa072dbecf86b0cd` | unencrypted F2 design checkpoint the public AFI was created from (manifest `dcp_hash` `2475a285…ab805`) — rebuild or modify it yourself |
| `sigil_programs_2026-10-22b.tar.gz` | 33.4 kB | `142e1f8b2a4b4873428fef05384bcc5106f5dbe308f1d1b93526edd05bc713ec` | prebuilt bare-metal firmware (crypto, Ed25519, hash, smoke, new F2 platform test and memory test) and the 7 SDK example binaries |
| `sigil_linux_evidence_2026-10-22.tar.gz` | `<size: restage after the F2 boot evidence>` | `<sha256: restage after the F2 boot evidence>` | #73 evidence: Vivado reports, every F2 host log and UART capture, QEMU and RTL boot logs, `<F2 Debian boot logs: pending>` |
| `SHA256SUMS` | 1.3 kB | | checksums of all of the above |

Everything rebuilds from the repository: `scripts/build_opensbi.sh`, `build_linux_kernel.sh`, `build_debian_rootfs.sh` (versions, checksums and the Debian snapshot are pinned), `fpga/scripts/build_cl_sigil.sh` for the CL.

## Known issues

- **Speed.** The in-order core with blocking L1 caches and one memory request in flight needs about **13 cycles per instruction** running Linux, at an interim 62.5 MHz. Booting takes minutes and `gcc hello.c` takes about a minute (estimate; `<F2 measured: pending>`). Performance work is epic #61; 100 MHz is #53.
- **No network on the F2** (#72). To install more packages, boot the same disk in QEMU with `--net`, `apt install` there, and use that disk on the F2 (`docs/LINUX.md` §9).
- **The crypto engine has not had a side-channel or fault-injection review.** Do not use real keys.
- One hart (no SMP). The vector unit is **Zve64d with VLEN 512, not full V**: build with `-march=rv64gc_zve64d` (add `_zvl512b` for auto-vectorization), never `rv64gcv`.
- The disk lives in DDR4. It survives `reboot` but not the end of a run unless `sigil_host --save` copies it back after `poweroff`. Saving 8 GiB to the root EBS volume is limited by the disk (≈130 MB/s); `/dev/shm` or the instance NVMe is faster.
- The image is a development system with **public passwords** (`sigil`/`sigil`, `root`/`sigil`); change them with `passwd`.
- No hardware RNG: early boot entropy comes from timer jitter.

## Claim boundaries

- This is an **FPGA prototype** of the SoC on AWS F2 at an interim 62.5 MHz core clock. It is not silicon. The ASIC (GDS) results are in earlier releases and are not part of this one.
- F2 results are measurements from one `f2.6xlarge` in us-east-1 on 2026-10-22. QEMU timings come from QEMU. Every estimate in these notes is labelled as one.
- The Debian image is an **unofficial** image built with `mmdebstrap` from unmodified Debian packages, plus a small configuration overlay (`sw/linux/debian/overlay/`). It is not a Debian release, and Debian has not reviewed or endorsed it.
- Sources: Linux 6.12.114 from kernel.org (tarball sha256 `7a8589912bd7a8adb07fed074283652cf482a35facef8954554654f0154b4af3`) with `sw/linux/kernel/sigil_defconfig`; OpenSBI v1.9 (`cbf9f673`) with `sw/linux/opensbi/*.patch`; Debian package sources from `snapshot.debian.org` at `20261020T000000Z`.
- No security review of the core, the SoC or the crypto engine. Do not use it for production workloads or secrets.
