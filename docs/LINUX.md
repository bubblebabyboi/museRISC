# Sigil Linux: Debian on the Sigil SoC

A real Linux system for Sigil (epic #73): log in on the serial console
and you are on **Debian 13 "trixie" riscv64** with systemd, **gcc 14 /
build-essential, glibc 2.41, gdb, make, git, vim, python3** and the
usual GNU tools, running on **Linux 6.12 LTS** with **all of the board's
memory**: 48 GiB DDR4 as NUMA node 0, 16 GiB HBM as NUMA node 1 (target
it with `numactl --membind=1`), and a 16 GiB DDR4 window as the root
disk `/dev/pmem0`.

The platform contract both sides build against is
[`LINUX_PLATFORM.md`](LINUX_PLATFORM.md). This guide covers what is in
the system, how to build it, how to boot it in QEMU and on an AWS F2
FPGA, and how to use it.

## Contents

1. [What you get](#1-what-you-get)
2. [Build it](#2-build-it)
3. [Boot it in QEMU](#3-boot-it-in-qemu)
4. [Boot it on the F2](#4-boot-it-on-the-f2)
5. [Logging in](#5-logging-in)
6. [Writing programs: gcc, make, gdb](#6-writing-programs-gcc-make-gdb)
7. [DDR4 and HBM: NUMA nodes 0 and 1](#7-ddr4-and-hbm-numa-nodes-0-and-1)
8. [Vector code (Zve64d, VLEN 512)](#8-vector-code-zve64d-vlen-512)
9. [The disk: pmem, saving it back, adding packages](#9-the-disk-pmem-saving-it-back-adding-packages)
10. [Boot time and speed](#10-boot-time-and-speed)
11. [Limits](#11-limits)
12. [Files and versions](#12-files-and-versions)

## 1. What you get

| Layer | What | Pinned to |
|---|---|---|
| Firmware | OpenSBI generic `fw_jump` at `0x8000_0000` | v1.9 (`cbf9f673`) |
| Kernel | Linux 6.12 LTS, `sw/linux/kernel/sigil_defconfig`, `Image` at `0x8020_0000` | 6.12.114 |
| Device tree | `sigil-f2.dtb` / `sigil-qemu.dtb` / `sigil-sim.dtb` from `sw/linux/dts/sigil.dtsi`, at `0x8300_0000` | this repo |
| Root file system | Debian 13 trixie riscv64, ext4, 8 GiB file system on the 16 GiB pmem disk | snapshot.debian.org `20261020T000000Z` (Debian 13.7) |

**Hardware view from Linux** (F2 build): one RV64 hart
(`rv64imafdch` + Zicntr, Zicond, Zba/Zbb/Zbc/Zbs, Zbkb/Zbkc/Zbkx,
Zkne/Zknd/Zknh, Zca/Zcb/Zcd, Zve32x..Zve64d with VLEN 512), Sv39, a
16550 console on `ttyS0`, the PLIC and CLINT, a test finisher for
power-off/reboot, a goldfish RTC, and

| NUMA node | Memory | Physical range | Size |
|---|---|---|---|
| 0 (CPU node) | DDR4 | `0x0_8000_0000 – 0xC_7FFF_FFFF` | 48 GiB |
| — (disk) | DDR4 pmem window, `/dev/pmem0` | `0xC_8000_0000 – 0x10_7FFF_FFFF` | 16 GiB |
| 1 (no CPUs) | HBM | `0x10_8000_0000 – 0x14_7FFF_FFFF` | 16 GiB |

**In the image** (257 Debian packages, ~0.9 GiB used of 7.8 GiB):
systemd 257 with a login on the serial console, dbus/logind, sudo;
**build-essential** (gcc/g++ 14.2, binutils 2.44, make 4.4, dpkg-dev,
glibc 2.41 headers), **gdb 16**, git, pkgconf, patch; vim, nano, less,
tmux, htop, file, strace, lsof, tree, time, bc; **python3 3.13**;
**numactl + libnuma-dev**, ndctl; man-db with manpages and manpages-dev;
xz/zstd/bzip2; iproute2/ping (no network on the F2 yet, #72). The full
package list with versions is the image's `manifest.txt` (recorded in
the evidence directory). `~/examples` holds small C programs (§6–§8).

Tuned for a slow single hart: no apt/man-db/fstrim/e2scrub timers, no
network services, generous systemd timeouts (`DefaultTimeoutStartSec=15min`),
a small persistent journal, SHA-512 password hashes (Debian's default
yescrypt takes tens of seconds per login at 62.5 MHz), and a
`SIGIL_LINUX_BOOT_OK` line printed on the console just before the login
prompt so host tools can tell the boot finished.

## 2. Build it

Everything builds on Ubuntu 24.04 x86-64 (the `sigil-fpga-build`
instance). Packages:

```sh
sudo apt install gcc-riscv64-linux-gnu g++-riscv64-linux-gnu libc6-dev-riscv64-cross \
  bc bison flex libssl-dev libelf-dev cpio make kmod device-tree-compiler \
  mmdebstrap debian-archive-keyring qemu-user-static binfmt-support \
  qemu-system-misc e2fsprogs zstd python3-pexpect
```

Then, from the repository root:

```sh
bash scripts/build_opensbi.sh            # OpenSBI v1.9 fw_jump + all DTBs (build_dtbs.sh)
bash scripts/build_linux_kernel.sh       # Linux 6.12.114: Image, Image-initramfs, modules
sudo bash scripts/build_debian_rootfs.sh # Debian 13 ext4 image + .zst + manifest
```

Outputs: `build/linux/{fw_jump.bin,Image,Image-initramfs,sigil-f2.dtb,
sigil-qemu.dtb,sigil-sim.dtb}` and `build/debian/sigil-debian-13-riscv64.ext4`
(+ `.ext4.zst`, `manifest.txt`, `rootfs.sha256`). The kernel takes about a
minute on 16 cores; the root file system about six minutes (package
maintainer scripts run under qemu-user). Versions, checksums and the
Debian snapshot are pinned in the scripts; published artifacts and their
sha256 are listed in the evidence for each release.

`scripts/build_linux_kernel.sh --regen-defconfig` rebuilds
`sigil_defconfig` from the riscv `defconfig` plus the readable fragment
`sw/linux/kernel/sigil.config` and checks that every option of the
fragment took effect.

## 3. Boot it in QEMU

```sh
bash scripts/qemu_sigil_boot.sh          # console on your terminal; Ctrl-A X quits
```

The first run makes `build/debian/sigil-disk.img`, a sparse 16 GiB copy
of the built image; it is the pmem window, file-backed and shared, so
whatever the guest writes stays in that file across QEMU runs (like
saving the F2 window back). `--fresh` starts again from the built image,
`--disk FILE` uses another disk, `--net` adds a NIC (§9),
`--initramfs` boots the `SIGIL_LINUX_BOOT_OK` smoke kernel instead.

The QEMU machine follows the contract: one hart with Sigil's
extensions and none it lacks (no full V, Sstc, Svpbmt, Zicbo*, Zfa,
Zfh, Zihpm), Sv39 only, the same physical memory map and NUMA nodes,
the same UART/PLIC/CLINT/finisher/RTC addresses, and the same OpenSBI,
kernel and disk image as the F2. Deviations, all from QEMU:

- **Timebase 10 MHz** (QEMU's fixed CLINT rate; F2: 62.5 MHz). That is
  the only difference between `sigil-qemu.dtb` and `sigil-f2.dtb` apart
  from the next two points.
- **Three QEMU NUMA "sockets"** lay out the three memory ranges (QEMU
  cannot place memory-only ranges otherwise), so QEMU creates two extra
  harts. They are not in the device tree; OpenSBI parks them and Linux
  sees one hart.
- **virtio-mmio slots** (QEMU virt) in `sigil-qemu.dtb` for the
  optional NIC; **no crypto engine** node (QEMU has flash at
  `0x2000_0000`).
- QEMU is fast: its timings say nothing about the FPGA (§10).

`python3 scripts/qemu_sigil_check.py [--fresh]` is the automated
acceptance run: boot, log in on the console, compile and run the
examples, check NUMA placement and RVV, sudo, a file surviving a
reboot, and power-off.

## 4. Boot it on the F2

The F2 needs the AFI with the full memory map (64 GiB DDR4 + 16 GiB
HBM), the test finisher and RTC (epic #73, phase 1–2) and a
`sigil_host` that can bulk-load the disk image into the pmem window
(PCIS offset `0x0C_0000_0000`) and save it back after power-off.

> **Status:** written against the contract; the commands and measured
> numbers are filled in by the F2 integration run (see
> `docs/evidence/README.md`, "Debian on Sigil").

The boot payloads are the same files as in QEMU, with `sigil-f2.dtb`:

| What | SoC address | PCIS offset |
|---|---|---|
| `fw_jump.bin` | `0x8000_0000` | `0x0` |
| `Image` | `0x8020_0000` | `0x20_0000` |
| `sigil-f2.dtb` | `0x8300_0000` (the boot ROM's `a1`) | `0x300_0000` |
| `sigil-debian-13-riscv64.ext4` | `0xC_8000_0000` (`/dev/pmem0`) | `0xC_0000_0000` |

OpenSBI is built with `FW_JUMP_FDT_ADDR=0x83000000`, so the DTB stays
where the host put it and the kernel may be up to 46 MiB.

## 5. Logging in

```
Sigil RV64 SoC - Debian GNU/Linux 13 sigil ttyS0
Log in as sigil (password sigil, sudo) or root (password sigil).

sigil login:
```

| User | Password | Notes |
|---|---|---|
| `sigil` (uid 1000) | `sigil` | groups sudo, adm, systemd-journal, kvm, dialout |
| `root` | `sigil` | console login allowed |

Change them with `passwd` (the image is a development system whose
passwords are public). The banner after login shows the board: CPU
ISA, the memory per NUMA node, and the disk. The serial console does
not carry the window size; `agetty` asks the terminal, and
`sigil-resize` asks again if needed (run it after resizing the window).
In QEMU, Ctrl-A X quits and Ctrl-A C opens the QEMU monitor.

## 6. Writing programs: gcc, make, gdb

The board has a native toolchain; nothing to cross-compile:

```console
sigil@sigil:~$ cat > hello.c <<'EOF'
#include <stdio.h>
int main(void) { printf("hello, Sigil\n"); return 0; }
EOF
sigil@sigil:~$ gcc hello.c && ./a.out
hello, Sigil
sigil@sigil:~$ cd examples && make && make run
```

`~/examples`: `hello.c`, `malloc_test.c` (glibc malloc/realloc/free,
small brk and large mmap blocks, one big block touched page by page),
`numa_hbm.c` and `memwhere.c` (§7), `rvv_vadd.c` (§8). gdb, strace and
`man 3 printf` work as on any Debian machine. Default code generation is
Debian's `rv64gc`; add `-march=rv64gc_zba_zbb_zbs_zicond` for the bit
manipulation extensions, `_zve64d_zvl512b` for vector code.

Cross-compiling from a PC also works (Ubuntu/Debian
`gcc-riscv64-linux-gnu`): the image's glibc is 2.41, so link statically
(`-static`) or against a matching sysroot. A full Linux SDK is #71.

## 7. DDR4 and HBM: NUMA nodes 0 and 1

```console
sigil@sigil:~$ numactl --hardware
available: 2 nodes (0-1)
node 0 cpus: 0
node 0 size: 48xxx MB
node 1 cpus:
node 1 size: 16xxx MB
node distances:
node     0    1
   0:   10   20
   1:   20   10
```

- **Default:** everything (`malloc`, the page cache, the kernel) comes
  from node 0, the DDR4 next to the CPU; node 1 is used only when node 0
  runs out.
- **A whole program in HBM:** `numactl --membind=1 ./prog` (fails
  allocations rather than spilling to DDR4); `numactl --preferred=1`
  prefers HBM but may spill; `numactl --interleave=0,1` stripes pages.
- **Parts of a program:** link with `-lnuma` and use
  `numa_alloc_onnode(size, 1)` / `numa_free()`, or `mbind()` /
  `set_mempolicy()` from `<numaif.h>`.
- **Check where memory landed:** `~/examples/memwhere 1024` prints the
  node of every page of a malloc'd buffer (`numactl --membind=1
  ./memwhere 1024` → `node 1: 1024 MiB`); `numastat -p PID`;
  `/sys/devices/system/node/node1/meminfo`.
- `~/examples/numa_hbm [MiB]` allocates on each node with libnuma,
  verifies the placement and times a write pass and a dependent-load
  (pointer-chasing) pass on each node — on the F2 this shows the
  latency/bandwidth difference between DDR4 and HBM.

## 8. Vector code (Zve64d, VLEN 512)

Sigil implements the embedded vector profile **Zve64d** (all SEW up to
64, single and double FP) with VLEN = 512, not the full V extension.
Linux 6.12 enables vector for user space on Zve* (6.6 needed full V),
so vector programs just work; the kernel saves the 2 KiB vector state
per task lazily (first use traps once).

```sh
gcc -O2 -march=rv64gc_zve64d rvv_vadd.c -o rvv_vadd     # RVV intrinsics
gcc -O3 -march=rv64gc_zve64d_zvl512b prog.c             # auto-vectorization
```

`rvv_vadd.c` asks the kernel with `riscv_hwprobe` (it reports
`ZVE32X/ZVE64X/ZVE64D`, not `IMA_V`), prints VLEN (512) and checks a
daxpy and an int64 reduction against scalar code. `zvl512b` tells GCC
the vector length so it vectorizes loops; without it GCC assumes the
Zve64d minimum (64 bits) and usually does not. Do not use
`-march=rv64gcv`: binaries for full V may use instructions Zve64d lacks.

## 9. The disk: pmem, saving it back, adding packages

The root file system lives in RAM: the host copies the ext4 image into
the pmem window before boot, Linux exposes the window as `/dev/pmem0`
(a raw libnvdimm namespace; the kernel warns that it "cannot guarantee
persistence", which is expected for DRAM) and mounts it as `/`. Writes
are as fast as memory. They persist as long as the window is not
overwritten: across `reboot` (the finisher resets the SoC, not the
DDR4), and across runs if the host saves the window back to a file
after `poweroff` (F2: `sigil_host` save; QEMU: automatically, the disk
file is the window). Always `poweroff` (or at least `sync`) before
saving, or the copy may hold a dirty, unjournaled state.

- **More room:** the file system is 8 GiB in a 16 GiB window. `sudo
  resize2fs /dev/pmem0` grows it online to 16 GiB (then the saved image
  is 16 GiB too).
- **More packages:** the F2 has no network yet (#72). Boot the same disk
  in QEMU with `--net`, then `sudo sigil-qemu-net && sudo apt update &&
  sudo apt install ...`, power off, and use that disk on the F2.
- **Files in and out:** loop-mount the image on the host (`sudo mount -o
  loop sigil-disk.img /mnt`) while nothing is running on it.

## 10. Boot time and speed

QEMU (TCG on the build instance, 2026-10-22): about 17 s from reset to
`multi-user.target`, 25 s to the login prompt. These numbers say
nothing about the FPGA.

On the F2 the hart runs at 62.5 MHz, in order, with blocking L1 caches
and one memory request in flight, roughly a 1990s workstation without
its L2. Expect minutes to the login prompt and seconds for small
commands; `gcc hello.c` takes a few seconds, Python starts slowly. The
measured numbers are in the F2 evidence (§4).

## 11. Limits

- One hart (`nproc` = 1); no SMP.
- No network on the F2 yet (#72); QEMU only with `--net`.
- No swap; no Sv48 (Sv39 maps up to 128 GiB physical, enough for the
  80 GiB here).
- No full V: build vector code for Zve64d (§8).
- No Sstc/Svpbmt/Zicbo*: timers go through SBI; DMA coherence is moot
  (no DMA devices).
- The RTC keeps time only if the host sets it; otherwise the clock
  starts at the image build date.
- Early boot entropy comes from timer jitter (there is no hardware RNG
  yet); a host-provided `/chosen/rng-seed` would make it instant.
- The system clock of the F2 build is the core clock; a faster FPGA
  build (#53) changes `timebase-frequency` in `sigil-f2.dts`.

## 12. Files and versions

| Path | What |
|---|---|
| `sw/linux/kernel/sigil.config`, `sigil_defconfig` | kernel configuration (fragment and full defconfig) |
| `sw/linux/dts/sigil.dtsi` + `sigil-{f2,qemu,sim}.dts` | device trees, one source |
| `sw/linux/sigil.dts` | historic name, = `sigil-sim.dts` (Verilator gate) |
| `sw/linux/debian/overlay/` | files the image adds to Debian (fstab, issue, motd, systemd tuning, boot marker, helpers) |
| `sw/linux/debian/examples/` | `~/examples` in the image |
| `sw/linux/init.c`, `boot_stub.S` | initramfs `/init` (`SIGIL_LINUX_BOOT_OK`) and the simulator boot stub |
| `scripts/build_opensbi.sh`, `build_dtbs.sh`, `build_linux_kernel.sh`, `build_debian_rootfs.sh` | builds |
| `scripts/qemu_sigil_boot.sh`, `qemu_sigil_check.py` | QEMU boot and acceptance run |
