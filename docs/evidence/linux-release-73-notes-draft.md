<!--
DRAFT release notes for tag sigil-linux-f2-2026-10-22 (epic #73). Remove this
comment before publishing.

Title: "Sigil 2026-10-22b: Debian 13 on AWS F2 with 64 GiB DDR4 + 16 GiB HBM
(public AFI)"

Assets are staged on sigil-fpga-build:~/release-73/ by
~/rel73-work/stage_release73.sh (checks the DCP against the evidence, the OS
artifacts against ~/os-artifacts/SHA256SUMS, the programs against
fw/SHA256SUMS; reproducible tarballs; no file over 2 GiB). The DCP is now the
one of the public AFI agfi-0c8aa56fde1a48495 (31a1568, walker-race fix #74);
the evidence tarball holds every docs/evidence/*-73-2026-10-22 directory of
73-linux-release.

Before publishing, in this order (steps 1, 3 and 4 are done):
1. Done: origin/73-oops-fix (31a1568 RTL + evidence) and origin/73-linux-debian
   (6881bff, the F2 Debian boot evidence) are merged into 73-linux-release.
   `git diff 31a15689 HEAD -- rtl/ fpga/cl_sigil/` is empty.
2. sigil-linux has only run against a simulated host (the F2 Debian runs used
   the sigil_host command it wraps). On an F2 with a checkout of this branch
   (sigil_host built) and the staged assets copied to ~/release-73, run inside
   tmux
     SIGIL_LINUX_URL=file://$HOME/release-73 bash ~/sigil/fpga/scripts/sigil-linux
   boot, `sudo poweroff`, check "disk saved", then run it a second time from
   the saved disk. Commit that log under docs/evidence/. If it passes, replace
   "not yet run on an F2" in the sigil-linux row of these notes, and the
   sigil-linux sentences in README "Boot Debian on your own F2", docs/LINUX.md
   §4 (status box) and docs/FPGA_F2.md ("Flash Sigil on your own F2").
3. Done: every placeholder is filled from the F2 runs on agfi-0c8aa56fde1a48495
   (the hbm_touch one says "not yet run on the F2"). This must print nothing:
     git grep -nE '<[^>]*pending>|restage[ ]after' -- README.md 'docs/*.md' fpga/scripts/ docs/evidence/
4. Done: the F2 evidence directories were copied into ~/rel73-work/evidence/
   on sigil-fpga-build and ~/rel73-work/stage_release73.sh was rerun with the
   new DCP; the DCP, evidence and SHA256SUMS rows below are the restaged ones.
   If evidence changes again, copy it and rerun the script, then update those
   rows.
5. Merge 73-linux-release into main and push, and wait for CI on main to
   pass. Do this before (or in the same minute as) the release: the setup
   one-liner, sigil-linux and every guide link below use main.
6. Publish with the tag sigil-linux-f2-2026-10-22 exactly: sigil-linux
   downloads from that tag by default (fpga/scripts/sigil-linux line 33).
     sed '1,/^-->$/d' docs/evidence/linux-release-73-notes-draft.md > notes.md
     gh release create sigil-linux-f2-2026-10-22 --repo bubblebabyboi/sigil \
       --target main --title "<title above>" --notes-file notes.md ~/release-73/*
   (all 16 files of ~/release-73, about 368 MB; none over 2 GiB; SHA256SUMS
   sha256 2e7f2e0bb7a7e33d8e2e773fac5ae4dd48ad8e812776824b2b7e05acca9711a8).
7. On a fresh f2.6xlarge, run the three commands of "Boot Debian on your own
   F2" once against the published release.
8. Delete the merged branches 73-f2-memory-platform, 73-linux-debian,
   73-oops-fix and 73-linux-release.
-->

The whole Sigil SoC — the in-house RV64GCV core (vector unit, L1 caches) plus the crypto/hash engine and peripherals — now boots **Debian 13 "trixie" with gcc and glibc on a real AWS F2 FPGA**, with **all of the board's memory**: 48 GiB DDR4 as NUMA node 0, **16 GiB HBM as NUMA node 1**, and a 16 GiB DDR4 window as the root disk `/dev/pmem0`. On an `f2.6xlarge` it reaches the login prompt **5 min 48 s** after the SoC starts and passes **22/22 acceptance checks**. New **public AFI**, Sigil-built OpenSBI v1.9 + Linux 6.12 LTS payloads, and a ready-to-boot Debian image.

The first Debian boots on the F2 found a bug in the core: a data-TLB miss that preempted an instruction-fetch page walk could take that walk's page-table response as its own, which made the kernel oops ([#74](https://github.com/bubblebabyboi/sigil/issues/74)). The new AFI has the fix.

## Boot Debian on your own F2

Public AFI **`agfi-0c8aa56fde1a48495`** (AFI `afi-059766f9a85c6d39a`, us-east-1, Small Shell `0x10212415`, PCI `0x1D0F:0xF054`), core clock **62.5 MHz** (interim; 100 MHz is #53), HBM AXI 250 MHz. It supersedes `agfi-0a1fd54ef68bdc754` (`afi-035809e576d7ea8d5`), whose core has the walker race: do not use that one for Linux.

```sh
# on a new f2.6xlarge (FPGA Developer AMI, us-east-1), logged in as ubuntu
curl -fsSL https://raw.githubusercontent.com/bubblebabyboi/sigil/main/fpga/scripts/f2_playground_setup.sh | bash
tmux                  # recommended: keeps the session alive if SSH drops
~/bin/sigil-linux     # downloads this release, loads the AFI, boots to the login prompt
```

The console is your terminal. The login prompt appears **5 min 48 s** after the SoC starts (measured on the F2; before that the host zeroes DDR4 and loads the 8 GiB disk, about 21 s, and the first run downloads the release). The F2 runs below used the `sigil_host` command that `sigil-linux` wraps (by hand, next block); `sigil-linux` itself passed its tests against a simulated `sigil_host`. Log in as **`sigil` / `sigil`** (sudo) or `root` / `sigil`, then for example:

```sh
gcc hello.c && ./a.out                          # native gcc 14 / glibc 2.41
numactl --hardware                              # node 0 = DDR4 48 GiB, node 1 = HBM 16 GiB
numactl --membind=1 ~/examples/memwhere 1024    # 1 GiB placed in HBM
sudo poweroff                                   # saves your disk (~/sigil-disk.ext4) for the next sigil-linux
```

`sigil-linux` copies the disk back after `poweroff`; Ctrl-] leaves without saving (the window is kept as `~/sigil-disk.ext4.unclean`); `sudo reboot` keeps the session going on the same disk. The first run after an AFI load zeroes all DDR4 once, which takes about 17 s. Rerunning the setup one-liner updates `~/sigil`, `sigil_host` and the helpers.

By hand (`sigil_host`), as in [`docs/LINUX.md` §4.2](https://github.com/bubblebabyboi/sigil/blob/main/docs/LINUX.md#42-by-hand-the-sigil_host-command-reference):

```sh
R=https://github.com/bubblebabyboi/sigil/releases/download/sigil-linux-f2-2026-10-22
for f in SHA256SUMS fw_jump.bin Image sigil-f2.dtb sigil-debian-13-riscv64.ext4.zst; do curl -fsSLO "$R/$f"; done
sha256sum -c --ignore-missing SHA256SUMS
zstd -d --sparse sigil-debian-13-riscv64.ext4.zst     # 8 GiB ext4 image
sudo ~/sigil/fpga/host/sigil_host --linux --fw fw_jump.bin --image Image --dtb sigil-f2.dtb \
     --load 0xC80000000=sigil-debian-13-riscv64.ext4 \
     --save 0xC80000000=sigil-disk-saved.ext4:8G \
     --console
```

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
| SoC release → `SIGIL_LINUX_BOOT_OK` → login prompt | **337.7 s → 347.9 s (5 min 48 s)**; second boot 333.2 s → 343.2 s; no kernel oops in either |
| Where the time goes | ≈ 129 s OpenSBI + early memory setup for 64 + 16 GiB, then `systemd-analyze`: 10.6 s kernel + 3 min 25.5 s userspace (`dev-pmem0.device` 2 min 13 s); about 5 core cycles per instruction |
| Login, `uname`, systemd state, root on `/dev/pmem0` | PASS: Linux 6.12.114 + Debian 13, `isa` with `zve64d`, systemd `running` with no failed units, `/` = `/dev/pmem0` ext4 rw |
| `numactl --hardware` (node 0 DDR4, node 1 HBM) | PASS: 2 nodes, node 0 48305 MB with cpu 0, node 1 16110 MB without CPUs; `free -h` 62 GiB |
| `numactl --membind=1` memory lands in HBM | PASS: `memwhere 1024` → node 1: 1024 MiB; `numa_hbm`: dependent load 1791 ns DDR4 / 1878 ns HBM |
| `gcc hello.c && ./a.out`, time | PASS: **22.9 s**; `make` of the 6 examples 6 min 23 s; `python3 -c` 9.9 s; `malloc_test` OK |
| RVV Zve64d user program (`rvv_vadd`) | PASS: VLEN 512; GCC auto-vectorized `autovec` PASS |
| `sudo`, git/gdb/strace/vim/file/man | PASS |
| `poweroff` → `sigil_host --save` → second boot from the saved disk | PASS: the file written in run 1 is there, `journalctl --list-boots` shows both boots |
| `sigil-linux`: boot, `sudo poweroff`, save to `~/sigil-disk.ext4`, second boot from it | not yet run on an F2 (the runs above used the `sigil_host` command it wraps); 35/35 tests against a simulated `sigil_host` |

22/22 acceptance checks plus the persistence check, [`linux-debian-73-2026-10-22/f2-boot-fixed/`](https://github.com/bubblebabyboi/sigil/blob/main/docs/evidence/linux-debian-73-2026-10-22/f2-boot-fixed/) (full consoles, check summaries, instance and AFI info). F2 time for all of #73: about 3.9 instance-hours.

**The memory platform** (on the platform AFI `agfi-0a1fd54ef68bdc754`, the same CL without the core's walker fix; not repeated on the new AFI, [`f2-platform-73-2026-10-22`](https://github.com/bubblebabyboi/sigil/blob/main/docs/evidence/f2-platform-73-2026-10-22/SUMMARY.md)):

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

Before the F2 Debian boot, the same OS was brought up in QEMU shaped like the platform (**23/23 acceptance checks**, [`linux-debian-73-2026-10-22`](https://github.com/bubblebabyboi/sigil/blob/main/docs/evidence/linux-debian-73-2026-10-22/)), and the all-RTL SoC model booted Linux 6.12 to `SIGIL_LINUX_BOOT_OK` in 261 M cycles.

FPGA build of the new AFI: Vivado 2025.2, aws-fpga v2.3.5, commit `31a1568`, all timing constraints met (WNS +0.095 ns on the core clock at 16 ns; HBM AXI +0.198 ns at 4 ns); 131,259 LUTs (10.08 % of the VU47P) for the full CL, 82,201 for the SoC + OCL block ([`f2-platform-73-oopsfix-2026-10-22`](https://github.com/bubblebabyboi/sigil/blob/main/docs/evidence/f2-platform-73-oopsfix-2026-10-22/vivado/build-steps.txt)). The walker race and its fix: [`linux-oops-fix-73-2026-10-22`](https://github.com/bubblebabyboi/sigil/blob/main/docs/evidence/linux-oops-fix-73-2026-10-22/README.md) (13 race tests under the checkers 0/39 before, 39/39 after; core-test, riscv-tests 123/123 and ACT 2,577/2,578 rerun).

## Assets

| File | Size | sha256 | What |
|---|---:|---|---|
| `sigil-debian-13-riscv64.ext4.zst` | 221.9 MB | `a9cfcbc977fad8968f07200d595b37ed3df51f7877b7fc0ec26d985e5fb5bf33` | Debian 13 root disk; `zstd -d --sparse` gives the 8 GiB ext4 (sha256 `c2d0cd4cf3e543a04e8194283acc7d8c1eec97046189ca8f9d4c1dd9bfe08632`), loaded at `0xC_8000_0000` |
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
| `sigil_f2_linux_cl_dcp_31a1568.Developer_CL.tar` | 110.2 MB | `9dd83d291f2bea57026f3eb1d623c89260273fb0c051be318ecbba449a30d246` | unencrypted F2 design checkpoint the public AFI `agfi-0c8aa56fde1a48495` was created from (manifest `dcp_hash` `53eed162…11fe73`) — rebuild or modify it yourself |
| `sigil_programs_2026-10-22b.tar.gz` | 33.4 kB | `dde6adc16bc409fefb94159f91dcdae0aeaa7e31cd57ed7c67829fd01b6cded3` | prebuilt bare-metal firmware (crypto, Ed25519, hash, smoke, new F2 platform test and memory test) and the 7 SDK example binaries |
| `sigil_linux_evidence_2026-10-22.tar.gz` | 338.3 kB | `3b15b6dd994648851c84ccfd159281d9a95b42fbeaa5fff983040a25172f9b24` | #73 evidence: Vivado reports of both platform AFIs, every F2 host log and UART capture, QEMU and RTL boot logs, the F2 Debian consoles (the oopses on the old AFI and the 22/22 runs on the new one), the walker-race tests and gates |
| `SHA256SUMS` | 1.3 kB | | checksums of all of the above |

Everything rebuilds from the repository: `scripts/build_opensbi.sh`, `build_linux_kernel.sh`, `build_debian_rootfs.sh` (versions, checksums and the Debian snapshot are pinned), `fpga/scripts/build_cl_sigil.sh` for the CL.

## Known issues

- **Speed.** The in-order core with blocking L1 caches and one memory request in flight needs about **5 cycles per instruction** running Debian, at an interim 62.5 MHz. Booting to the login prompt takes 5 min 48 s, `gcc hello.c && ./a.out` 22.9 s and `python3 -c` 9.9 s (measured on the F2). Performance work is epic #61; 100 MHz is #53.
- **F2 platform quirks** ([#75](https://github.com/bubblebabyboi/sigil/issues/75), open): a `sigil_host` killed by a signal (e.g. Ctrl-C outside `--console`, or `pkill`) leaves the SoC running, and after that the console lost bytes until the AFI was reloaded (`sudo fpga-clear-local-image -S 0 -H`, then `sudo fpga-load-local-image -S 0 -I agfi-0c8aa56fde1a48495 -H`). End Debian sessions with `sudo poweroff`.
- `sudo reboot` inside Debian keeps the disk in QEMU and was checked on the F2 with the platform test firmware, but Debian's own `reboot` has not been run on the F2 yet.
- **No network on the F2** (#72). To install more packages, `apt-get install` them into your disk file from the F2 host through a `qemu-user-static` chroot while `sigil-linux` is not running (commands in [`docs/LINUX.md` §6](https://github.com/bubblebabyboi/sigil/blob/main/docs/LINUX.md#6-the-disk-pmem-saving-it-back-adding-packages)).
- **The crypto engine has not had a side-channel or fault-injection review.** Do not use real keys.
- One hart (no SMP). The vector unit is **Zve64d with VLEN 512, not full V**: build with `-march=rv64gc_zve64d` (add `_zvl512b` for auto-vectorization), never `rv64gcv`.
- The disk lives in DDR4; `sigil-linux` saves it to `~/sigil-disk.ext4` after `sudo poweroff`; Ctrl-] or a dropped SSH session outside tmux loses changes since boot. It survives `reboot` within a session.
- The image is a development system with **public passwords** (`sigil`/`sigil`, `root`/`sigil`); change them with `passwd`.
- No hardware RNG: early boot entropy comes from timer jitter.

## Claim boundaries

- This is an **FPGA prototype** of the SoC on AWS F2 at an interim 62.5 MHz core clock. It is not silicon. The ASIC (GDS) results are in earlier releases and are not part of this one.
- F2 results are measurements from one `f2.6xlarge` in us-east-1 on 2026-10-22. QEMU timings come from QEMU. Every estimate in these notes is labelled as one.
- The Debian image is an **unofficial** image built with `mmdebstrap` from unmodified Debian packages, plus a small configuration overlay (`sw/linux/debian/overlay/`). It is not a Debian release, and Debian has not reviewed or endorsed it.
- Sources: Linux 6.12.114 from kernel.org (tarball sha256 `7a8589912bd7a8adb07fed074283652cf482a35facef8954554654f0154b4af3`) with `sw/linux/kernel/sigil_defconfig`; OpenSBI v1.9 (`cbf9f673`) with `sw/linux/opensbi/*.patch`; Debian package sources from `snapshot.debian.org` at `20261020T000000Z`.
- No security review of the core, the SoC or the crypto engine. Do not use it for production workloads or secrets.
