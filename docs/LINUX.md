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
FPGA, and how to use it. To boot it on your own F2, go to
[§4](#4-boot-debian-on-your-f2); to use it, [§5](#5-using-sigil-linux).

## Contents

1. [What you get](#1-what-you-get)
2. [Build it](#2-build-it)
3. [Boot it in QEMU](#3-boot-it-in-qemu)
4. [Boot Debian on your F2](#4-boot-debian-on-your-f2): [one command](#41-one-command-sigil-linux), [by hand](#42-by-hand-the-sigil_host-command-reference)
5. [Using Sigil Linux](#5-using-sigil-linux): [logging in](#51-logging-in),
   [what is installed](#52-what-is-installed),
   [compiling](#53-compiling-programs-on-the-board),
   [DDR4 and HBM](#54-ddr4-and-hbm-numa-nodes-0-and-1),
   [vector code](#55-vector-code-zve64d-vlen-512),
   [files in and out](#56-getting-files-in-and-out),
   [shutting down](#57-shutting-down-safely),
   [it is slow](#58-it-is-slow)
6. [The disk: pmem, saving it back, adding packages](#6-the-disk-pmem-saving-it-back-adding-packages)
7. [Boot time and speed](#7-boot-time-and-speed)
8. [Limits](#8-limits)
9. [Files and versions](#9-files-and-versions)

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
the evidence directory). `~/examples` holds small C programs (§5.3–§5.5).

Tuned for a slow single hart (each item measured in QEMU's
instruction-counting mode, §7): no apt/man-db/fstrim/e2scrub timers,
no network services, no ndctl/cxl monitors, no `modprobe@` units for
built-in drivers, no binfmt service; no boot-time fsck (it would wait
for udev to announce `/dev/pmem0`; ext4 replays its journal at mount);
generous systemd timeouts (`DefaultTimeoutStartSec=15min`); a small
persistent journal; SHA-512 password hashes (Debian's default yescrypt
takes tens of seconds per login at 62.5 MHz); no login timeout
(`login` gives up after 60 s by default); logins register a logind
session of class `background-light`, which does not start the per-user
service manager (`user@UID.service`, about a minute of CPU at 62.5 MHz;
`sudo systemctl start user@1000` if you want `systemctl --user`); and a
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
`--disk FILE` uses another disk, `--net` adds a NIC (it passes no traffic yet, §6),
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
- QEMU is fast: its timings say nothing about the FPGA (§7).

`python3 scripts/qemu_sigil_check.py [--fresh]` is the automated
acceptance run: boot, log in on the console, compile and run the
examples, check NUMA placement and RVV, sudo, a file surviving a
reboot, and power-off.

## 4. Boot Debian on your F2

All you need is an AWS account that can launch F2 instances. The FPGA
image is Sigil's **public AFI `agfi-0a1fd54ef68bdc754`** (64 GiB DDR4 +
16 GiB HBM, test finisher, RTC; [`FPGA_F2.md`](FPGA_F2.md#flash-sigil-on-your-own-f2)),
and the boot files and the Debian disk come from the GitHub release
`sigil-linux-f2-2026-10-22`. An `f2.6xlarge` (us-east-1, the smallest
F2) costs about $2/h On-Demand: stop it when you are done.

> **Status:** the AFI passed its hardware tests
> ([`evidence/f2-platform-73-2026-10-22/`](evidence/f2-platform-73-2026-10-22/SUMMARY.md))
> and this Debian passed 23/23 acceptance checks in QEMU
> ([`evidence/linux-debian-73-2026-10-22/`](evidence/linux-debian-73-2026-10-22/)).
> `sigil-linux` passed its tests against a simulated `sigil_host` and
> AFI tools ([`sigil-linux-tests.log`](evidence/linux-user-docs-73-2026-10-22/sigil-linux-tests.log)).
> First Debian boot on the F2: `<F2 Debian boot evidence: pending>`.
> First `sigil-linux` run on the F2 (boot, `poweroff`, save, second boot
> from the saved disk): `<sigil-linux on F2: pending>`.

### 4.1 One command: `sigil-linux`

On a new `f2.6xlarge` launched from the AWS **FPGA Developer AMI**
(Ubuntu), logged in as `ubuntu`:

```sh
curl -fsSL https://raw.githubusercontent.com/bubblebabyboi/sigil/main/fpga/scripts/f2_playground_setup.sh | bash
tmux                 # recommended: if SSH drops, Debian and your work survive inside tmux
~/bin/sigil-linux    # downloads, unpacks your disk, loads the AFI, boots to the login prompt
```

(The short names `sigil-linux` and `sigil-run` work in new shells,
including the `tmux` one; in the shell that ran the setup, use
`~/bin/...` or `source ~/.bashrc` first.)

The setup script runs once per instance (rerun it to update `~/sigil`,
`sigil_host` and the helpers; it keeps `~/hello` and does not reload
an AFI that is already loaded). It installs the AWS FPGA
runtime SDK (aws-fpga v2.3.5), a bare-metal RISC-V GCC, `zstd` and
`tmux`, clones Sigil into `~/sigil`, builds `sigil_host`, loads the
AFI, and puts `sigil-run` (bare-metal programs,
[`PROGRAMMING.md`](PROGRAMMING.md)) and `sigil-linux` in `~/bin`.

[`sigil-linux`](../fpga/scripts/sigil-linux) then:

1. downloads `fw_jump.bin`, `Image`, `sigil-f2.dtb` and
   `sigil-debian-13-riscv64.ext4.zst` (about 240 MB) from the release
   into `~/.cache/sigil-linux/<tag>/`, once, and checks them against the
   release's `SHA256SUMS`;
2. unpacks the Debian image once into **`~/sigil-disk.ext4`**: your
   disk, an 8 GiB ext4 file system stored sparse (about 0.9 GiB on the
   volume at first);
3. loads the Sigil AFI if the FPGA does not have it; the first boot
   after a load also zeroes all 64 GiB of DDR4 (about 17 s, #62);
4. boots OpenSBI + Linux with your disk in the pmem window and your
   terminal as the console (the `sigil_host` command of §4.2);
5. after you power Debian off, copies the pmem window back into
   `~/sigil-disk.ext4`, so the next `sigil-linux` continues where you
   left off.

The login prompt appears **`<F2 boot time: pending>`** after the start
(estimate from QEMU: about 9 minutes at 62.5 MHz, §7). Log in as
`sigil` / `sigil` and go on with §5.

| Command | |
|---|---|
| `sigil-linux` | boot your disk (made on the first run) |
| `sigil-linux --fresh` | start again from the release image; the old disk is kept as `~/sigil-disk.ext4.old` |
| `sigil-linux --disk ~/work.ext4` | use another disk file, e.g. one per project (made from the release image if it does not exist) |
| `sigil-linux --tag TAG` | boot another release (or set `SIGIL_LINUX_TAG`) |
| `sigil-linux -- --log console.log` | options after `--` go to `sigil_host` (here: also write the console to a file) |

How a session ends:

| You | Debian | Your disk |
|---|---|---|
| `sudo poweroff` | shuts down; OpenSBI writes back the L1 D$ and powers off through the test finisher | **saved**: `sigil-linux` reads the 16 GiB window back, trims it to the file system and replaces `~/sigil-disk.ext4` |
| `sudo reboot` | restarts on the same disk: `sigil_host` reloads OpenSBI, the kernel and the DTB, not the disk | the session goes on (after 16 reboots in one session `sigil_host` stops with exit status 5, and `sigil-linux` saves the disk as after a power-off) |
| Ctrl-] | keeps running on the FPGA, but nothing can reattach to it | **not saved**: `~/sigil-disk.ext4` stays as it was; the window at that moment is kept as `~/sigil-disk.ext4.unclean` (`e2fsck -f` it before use) |
| SSH drops, outside tmux | `sigil_host` ends with your shell | **not saved** |

Rerunning is safe: the downloads, your disk and a loaded AFI are
reused, and the disk file is only ever replaced by a copy saved after a
clean power-off. The save goes to `/dev/shm` first (the window comes
back over PCIe at about 1 GB/s; the instance has 256 GiB of RAM) and
then into the disk file as a sparse copy, so only the blocks the file
system uses reach the EBS volume (≈ 130 MB/s). If you grew the file
system (`sudo resize2fs /dev/pmem0`, §6), the disk file grows with it.
Space needed in your home directory: the downloads (≈ 240 MB), your
disk (≈ 0.9 GiB to start, more as you add files) and, while saving, one
more copy of it.

### 4.2 By hand: the `sigil_host` command (reference)

The boot payloads are the same files as in QEMU, with `sigil-f2.dtb`:

| What | SoC address | PCIS offset |
|---|---|---|
| `fw_jump.bin` | `0x8000_0000` | `0x0` |
| `Image` | `0x8020_0000` | `0x20_0000` |
| `sigil-f2.dtb` | `0x8300_0000` (the boot ROM's `a1`) | `0x300_0000` |
| `sigil-debian-13-riscv64.ext4` | `0xC_8000_0000` (`/dev/pmem0`) | `0xC_0000_0000` |

OpenSBI is built with `FW_JUMP_FDT_ADDR=0x83000000`, so the DTB stays
where the host put it and the kernel may be up to 46 MiB.

What `sigil-linux` does, by hand (after the setup script, or steps 1–4
of [`FPGA_F2.md`](FPGA_F2.md#flash-sigil-on-your-own-f2)):

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

- `--linux --fw --image --dtb` load OpenSBI, the kernel and the DTB at
  the addresses above; `--load 0xC80000000=FILE` puts the disk at the
  start of the pmem window.
- `--console` makes your terminal a raw console; Ctrl-] detaches (exit
  status 4, the SoC keeps running).
- `--save 0xC80000000=FILE:8G` writes the first 8 GiB of the window to
  `FILE` when the run ends: the whole file system unless you grew it
  (then `:16G`). `sigil_host` saves whenever its run loop ends
  (power-off, fail code, `--on-reboot exit`, Ctrl-], timeout), but not
  when it stops on a setup or load error or is killed (e.g. SSH drops);
  only a save after `poweroff` (exit status 0) is a consistent disk. Next time,
  `--load 0xC80000000=sigil-disk-saved.ext4`. Saving straight to the
  root EBS volume is disk-bound (≈ 130 MB/s); `/dev/shm` or the
  instance NVMe is not.
- `--on-reboot rerun` (the default) handles a guest `reboot` as in
  §4.1; `--on-reboot exit` ends the run instead (exit status 5).

The QEMU acceptance run drives the F2 the same way (timeouts × 40, no
reboot round; a second run checks the saved disk). Run it from `~/sigil`
with `D` set to the directory of the downloads and the unpacked image
above:

```sh
sudo apt-get install -y python3-pexpect
D=$PWD          # the directory you downloaded and unpacked into above
cd ~/sigil
H="sudo fpga/host/sigil_host --linux --fw $D/fw_jump.bin --image $D/Image --dtb $D/sigil-f2.dtb --console --on-reboot exit"
python3 scripts/qemu_sigil_check.py --label F2 --scale 40 --no-reboot --stamp 1 --log f2-check.log \
  --cmd "$H --load 0xC80000000=$D/sigil-debian-13-riscv64.ext4 --save 0xC80000000=$D/saved.ext4:8G"
python3 scripts/qemu_sigil_check.py --label F2 --scale 40 --persist-check 1 --log f2-persist.log \
  --cmd "$H --load 0xC80000000=$D/saved.ext4"
```

**Power-off, reboot and the disk.** Sigil's L1 D$ is write-back and the
host's PCIS view of DDR4 does not see dirty lines. Linux therefore
powers off and reboots only through SBI SRST (the kernel has no syscon
reset driver), and the Sigil OpenSBI (`sw/linux/opensbi/0001-*.patch`)
executes `FENCE.I` — which on Sigil writes back every dirty D$ line —
before it writes the test finisher. After `poweroff` the pmem window in
DDR4 therefore holds the complete file system and the host can save it.
`reboot` keeps DDR4: the host must reload OpenSBI, the kernel and the
DTB (Linux reused that memory) but **not** the disk image, or the
reboot discards everything written since boot. `sigil_host --on-reboot
rerun` does exactly that: checked on the F2 with the platform test
firmware (`platform-reboot` in the platform evidence), and Debian's
`reboot` keeps the disk in QEMU; Debian `reboot` on the F2:
`<F2 Debian reboot: pending>`.

## 5. Using Sigil Linux

### 5.1 Logging in

On the F2 the login prompt comes `<F2 boot time: pending>` after
`sigil-linux` starts (estimate: about 9 minutes, §7). Until then the
console shows OpenSBI's banner, the kernel log and systemd starting
services; `SIGIL_LINUX_BOOT_OK Debian GNU/Linux 13 (trixie) up, login
prompt next` is printed just before the prompt:

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

### 5.2 What is installed

Debian 13 "trixie" riscv64 (257 packages; the full list is the image's
`manifest.txt`, a release asset, or `dpkg -l` on the board):
**build-essential** (gcc/g++ 14.2, binutils 2.44, make 4.4, glibc 2.41
headers), **gdb 16**, git, pkgconf, patch; vim, nano, less, tmux, htop,
file, strace, lsof, tree, time, bc; **python3 3.13**; **numactl +
libnuma-dev**; man pages; xz/zstd/bzip2. `~/examples` holds small C
programs with a `Makefile` (`make && make run`). There is no network on
the F2 yet (#72), so install more packages into the disk file from the
host (§6).

### 5.3 Compiling programs on the board

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
`numa_hbm.c` and `memwhere.c` (§5.4), `rvv_vadd.c` and `autovec.c`
(§5.5). gdb, strace and `man 3 printf` work as on any Debian machine.
Default code generation is Debian's `rv64gc`; add
`-march=rv64gc_zba_zbb_zbs_zicond` for the bit-manipulation extensions,
`_zve64d_zvl512b` for vector code. On the F2, `gcc -O2 hello.c` takes
`<F2 measured: pending>` (estimate: about a minute, §7): keep programs
in several small files and let `make` rebuild only what changed.

Cross-compiling from a PC also works (Ubuntu/Debian
`gcc-riscv64-linux-gnu`): the image's glibc is 2.41, so link statically
(`-static`) or against a matching sysroot. A full Linux SDK is #71.

### 5.4 DDR4 and HBM: NUMA nodes 0 and 1

```console
sigil@sigil:~$ numactl --hardware
available: 2 nodes (0-1)
node 0 cpus: 0
node 0 size: 48305 MB
node 1 cpus:
node 1 size: 16110 MB
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
  `set_mempolicy()` from `<numaif.h>`:

  ```c
  /* hbm.c: one buffer in HBM, one in DDR4.  gcc -O2 hbm.c -lnuma -o hbm */
  #include <numa.h>
  #include <stdio.h>
  #include <string.h>

  int main(void) {
    size_t size = 64 << 20;                      /* 64 MiB each */
    if (numa_available() < 0) return 1;
    char *hbm = numa_alloc_onnode(size, 1);      /* node 1 = HBM */
    char *ddr = numa_alloc_onnode(size, 0);      /* node 0 = DDR4 */
    if (!hbm || !ddr) return 1;
    memset(hbm, 1, size);                        /* pages are placed at first touch */
    memcpy(ddr, hbm, size);
    long long free_hbm;
    numa_node_size64(1, &free_hbm);
    printf("copied %zu MiB from HBM to DDR4, %lld MiB of HBM free\n", size >> 20, free_hbm >> 20);
    numa_free(hbm, size);
    numa_free(ddr, size);
    return 0;
  }
  ```

- **Check where memory landed:** `~/examples/memwhere 1024` prints the
  node of every page of a malloc'd buffer (`numactl --membind=1
  ./memwhere 1024` → `node 1: 1024 MiB`); `numastat -p PID`;
  `/sys/devices/system/node/node1/meminfo`.
- `~/examples/numa_hbm [MiB]` (`make numa_hbm`, i.e. `gcc -O2 -Wall
  numa_hbm.c -lnuma -o numa_hbm`) allocates on each node with
  `numa_alloc_onnode`, verifies the placement page by page
  (`numa_move_pages`) and times a write pass and a dependent-load
  (pointer-chasing) pass on each node.
  On the F2 it shows the difference. Measured from bare-metal code, a
  cold 64-byte refill takes 729 ns from DDR4 and 813 ns from HBM, and a
  sequential read runs at 77 MB/s from DDR4 and 70 MB/s from HBM: with
  one memory request in flight both are latency-bound, so for this core
  HBM is not faster, it is 16 GiB more memory you can place data in.

### 5.5 Vector code (Zve64d, VLEN 512)

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
`-march=rv64gcv` (or `rv64gcv_zvl512b`): binaries for full V may use
instructions Zve64d lacks. The vector unit is element-serial
([`PROGRAMMING.md`](PROGRAMMING.md#11-vector-code)): vector code runs
far fewer instructions, but is not dramatically faster yet.

### 5.6 Getting files in and out

There is no network on the F2 yet (#72). Files travel in the disk file,
while Debian is **not** running (`sigil-linux` reads the disk file at
boot and overwrites it at power-off, so changes made to it in between
are lost):

- **In, with a loop mount** (any number of files):

  ```sh
  sudo mount -o loop ~/sigil-disk.ext4 /mnt
  sudo cp -r myproject /mnt/home/sigil/ && sudo chown -R 1000:1000 /mnt/home/sigil/myproject
  sudo umount /mnt
  ```

- **In, with `debugfs`** (no root, no mount; one file at a time; the
  file arrives owned by root, so `sudo chown sigil:sigil ~/prog.c` on
  the board):

  ```sh
  debugfs -w -R "write prog.c /home/sigil/prog.c" ~/sigil-disk.ext4
  ```

- **Out, after `sudo poweroff`** (once `sigil-linux` has saved the disk):

  ```sh
  debugfs -R "cat /home/sigil/results.txt" ~/sigil-disk.ext4 > results.txt
  debugfs -R "rdump /home/sigil/results ." ~/sigil-disk.ext4     # a whole directory
  ```

  or `sudo mount -o loop,ro ~/sigil-disk.ext4 /mnt`.
- **A few lines of text:** paste them into `cat > file` on the console
  (Ctrl-D ends it).

These commands were checked in QEMU with the release image (the
root-owned `debugfs` file, the loop-mounted copy owned by `sigil`, files
read back after `sudo poweroff`, `e2fsck -fn` clean;
[`evidence/linux-user-docs-73-2026-10-22/`](evidence/linux-user-docs-73-2026-10-22/qemu-docs-check.log)),
as were the §5.4 program and the §5.5 compiler lines.

### 5.7 Shutting down safely

`sudo poweroff` (password `sigil`), then wait: Debian stops its
services and remounts the disk read-only, and OpenSBI writes the L1 D$
back before it powers off through the test finisher; then `sigil-linux`
saves the disk and prints `disk saved: ...`. Only this path keeps your work.
`sudo reboot` restarts Debian on the same disk without saving it to the
host (it stays in DDR4). Ctrl-], a dropped SSH session outside tmux, or
stopping the instance with Debian still running lose everything since
the last power-off (§4.1). Stop the F2 instance (`sudo shutdown -h
now` on the host, or the EC2 console) only after `sigil-linux` has
returned; `~/sigil-disk.ext4` is on the EBS volume and survives a stop.

### 5.8 It is slow

Sigil Linux on the F2 is a complete Debian, but on a slow machine. The
core runs at an interim **62.5 MHz** and needs about **13 cycles per
instruction** running Linux (derived from the #55 F2 boot, §7): it is in
order, its L1 caches block on a miss, it has one memory request in
flight, and a cold refill from DDR4 takes ≈ 46 cycles (729 ns). That is roughly 5
million instructions per second. Booting takes `<F2 boot time: pending>`
(estimate ≈ 9 min), `gcc hello.c` about a minute and starting `python3`
about 15 s (estimates, §7). Use it to run and measure code on Sigil, not
to build big projects: compile small programs, keep `make` incremental,
and run long jobs under `nohup`. A faster FPGA clock (#53) and the
microarchitecture work (#61) are the planned fixes.

## 6. The disk: pmem, saving it back, adding packages

The root file system lives in RAM: the host copies the ext4 image into
the pmem window before boot, Linux exposes the window as `/dev/pmem0`
(a raw libnvdimm namespace; the kernel warns that it "cannot guarantee
persistence", which is expected for DRAM) and mounts it as `/`. Writes
are as fast as memory. They persist as long as the window is not
overwritten: across `reboot` (the finisher resets the SoC, not the
DDR4), and across runs if the host saves the window back to a file
after `poweroff` (F2: `sigil-linux`, or `sigil_host --save`, §4; QEMU:
automatically, the disk file is the window). Always `poweroff` (or at
least `sync`) before saving, or the copy may hold a dirty, unjournaled
state.

- **Checking the file system:** there is no fsck at boot. Run
  `e2fsck -f` on a saved image on the host while nothing uses it.
- **More room:** the file system is 8 GiB in a 16 GiB window. `sudo
  resize2fs /dev/pmem0` grows it online to 16 GiB (then the saved image
  is 16 GiB too).
- **More packages:** the F2 has no network yet (#72). Install them from
  the F2 host into your disk file, while `sigil-linux` is not running:
  `qemu-user-static` runs the riscv64 `apt` and package scripts on the
  x86 host, through the host's network:

  ```sh
  sudo apt-get install -y qemu-user-static        # once: riscv64 programs on the host
  M=/mnt/sigil; sudo mkdir -p $M
  sudo mount -o loop ~/sigil-disk.ext4 $M
  sudo mount --bind /dev $M/dev; sudo mount -t devpts devpts $M/dev/pts; sudo mount -t proc proc $M/proc
  sudo cp -L /etc/resolv.conf $M/etc/resolv.conf   # DNS for apt
  sudo chroot $M apt-get update
  sudo chroot $M apt-get install -y <packages>
  sudo umount $M/proc $M/dev/pts $M/dev $M
  ```

  The next `sigil-linux` boots the disk with the new packages. They come
  from the live Debian 13 archive (`deb.debian.org`), not from the
  snapshot the image was built from. Any Ubuntu 24.04 machine works the
  same way; copy the disk file there and back. (`qemu_sigil_boot.sh
  --net` does not work for this: QEMU's `virt` machine wires virtio
  interrupts to the PLIC of its second NUMA socket, whose hart OpenSBI
  parks, so the NIC passes no traffic.)
- **Files in and out:** §5.6 (loop mount or `debugfs` on the disk file
  while nothing is running on it).

## 7. Boot time and speed

| | QEMU (TCG, build instance) | QEMU `--icount` (62.5 MHz at IPC 1) | F2 estimate (62.5 MHz) |
|---|---:|---:|---:|
| reset → login prompt | 21 s | 42 s | **≈ 9 min** |
| `gcc -O2 hello.c` | < 1 s | 4.9 s | ≈ 1 min |
| `python3 -c 'print(42)'` | < 1 s | 1.0 s | ≈ 15 s |

QEMU's own speed says nothing about the FPGA. `scripts/qemu_sigil_check.py
--icount` runs QEMU so that guest time advances 16 ns per instruction —
a 62.5 MHz hart executing one instruction per cycle, a lower bound. The
F2 hart (in order, blocking L1 caches, one memory request in flight)
needed about 13 cycles per instruction on the #55 Linux 6.6 boot
(calibrated by running that exact payload in the same icount QEMU), so
the F2 column is the icount column × 13. Measured F2 numbers replace it
in the evidence when the run happens. A faster FPGA clock (#53) scales
everything.

The image is tuned for this (§1); `systemd-analyze blame` on the board
shows where the time goes.

## 8. Limits

- One hart (`nproc` = 1); no SMP.
- No network on the F2 yet (#72); install packages from the host (§6).
- No swap; no Sv48 (Sv39 maps up to 128 GiB physical, enough for the
  80 GiB here).
- No full V: build vector code for Zve64d (§5.5).
- No Sstc/Svpbmt/Zicbo*: timers go through SBI; DMA coherence is moot
  (no DMA devices).
- The RTC keeps time only if the host sets it; otherwise the clock
  starts at the image build date.
- Early boot entropy comes from timer jitter (there is no hardware RNG
  yet); a host-provided `/chosen/rng-seed` would make it instant.
- The system clock of the F2 build is the core clock; a faster FPGA
  build (#53) changes `timebase-frequency` in `sigil-f2.dts`.

## 9. Files and versions

| Path | What |
|---|---|
| `sw/linux/kernel/sigil.config`, `sigil_defconfig` | kernel configuration (fragment and full defconfig) |
| `sw/linux/dts/sigil.dtsi` + `sigil-{f2,qemu,sim}.dts` | device trees, one source |
| `sw/linux/sigil.dts` | historic name, = `sigil-sim.dts` (Verilator gate) |
| `sw/linux/opensbi/*.patch` | applied to OpenSBI v1.9 by `build_opensbi.sh` (D$ write-back before a system reset) |
| `sw/linux/debian/overlay/` | files the image adds to Debian (fstab, issue, motd, systemd tuning, boot marker, helpers) |
| `sw/linux/debian/examples/` | `~/examples` in the image |
| `sw/linux/init.c`, `boot_stub.S` | initramfs `/init` (`SIGIL_LINUX_BOOT_OK`) and the simulator boot stub |
| `scripts/build_opensbi.sh`, `build_dtbs.sh`, `build_linux_kernel.sh`, `build_debian_rootfs.sh` | builds |
| `scripts/qemu_sigil_boot.sh`, `qemu_sigil_check.py` | QEMU boot and acceptance run |
| `fpga/scripts/sigil-linux` | download, unpack, boot and save on an F2 (§4.1) |
| `fpga/scripts/f2_playground_setup.sh` | one-time F2 instance setup (SDK, `sigil_host`, AFI, `sigil-run`, `sigil-linux`) |
