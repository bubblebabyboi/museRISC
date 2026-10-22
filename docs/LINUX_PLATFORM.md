# Sigil Linux platform contract (epic #73)

The single source of truth that the hardware side (CL / SoC / host tool)
and the OS side (OpenSBI, kernel, device trees, Debian image, Linux SDK)
both build against. Change it only together with both sides.

Owner requirements (2026-10-22): address **all 64 GiB DDR4 and all 16 GiB
HBM** on the F2; a system that **looks like a real Linux machine at login**
(Debian preferred) with **gcc / glibc (`malloc`, …) and the usual GNU
tools**; and the ability to **target DDR4 or HBM explicitly** when wanted.

The layout deliberately matches QEMU's `virt` machine wherever Sigil already
does (UART, PLIC, CLINT addresses, test finisher, RTC), so the OS can be
brought up in QEMU and run unchanged on the FPGA.

## Physical memory map (F2 build)

| SoC physical address | Size | What | Host PCIS (BAR4) offset |
|---|---:|---|---|
| `0x0000_1000` | 4 KiB | boot ROM (jumps to `0x8000_0000`) | — |
| `0x0010_0000` | 4 KiB | **test finisher** — `sifive,test1`-compatible (new) | — |
| `0x0010_1000` | 4 KiB | **RTC** — `google,goldfish-rtc`-compatible, set by the host; interrupt = PLIC source 11 | — |
| `0x0200_0000` | 64 KiB | CLINT (`msip`, `mtimecmp`, `mtime`) | — |
| `0x0C00_0000` | 64 MiB | PLIC (UART = source 10) | — |
| `0x1000_0000` | 256 B | 16550 UART (virtual UART on F2) | — |
| `0x2000_0000` | 256 B | crypto / hash engine | — |
| `0x0_8000_0000` – `0xC_7FFF_FFFF` | 48 GiB | **DDR4 — system RAM, NUMA node 0** | `0x00_0000_0000` |
| `0xC_8000_0000` – `0x10_7FFF_FFFF` | 16 GiB | **DDR4 — pmem disk** (`pmem-region`, `/dev/pmem0`) | `0x0C_0000_0000` |
| `0x10_8000_0000` – `0x14_7FFF_FFFF` | 16 GiB | **HBM — system RAM, NUMA node 1** (no CPUs) | `0x10_0000_0000` |

- The core, MMU and L1 caches carry 56-bit physical addresses; the SoC
  fabric routes every PA ≥ `0x8000_0000` to the RAM bus. The F2 RAM bridge
  maps PA `0x8000_0000 + x` → DDR4 AXI `x` for `x < 64 GiB`, and PA
  `0x10_8000_0000 + y` → HBM AXI `0x10_0000_0000 + y` for `y < 16 GiB`.
  Anything else in RAM space returns an error response (the bridge
  answers locally: reads return zero, writes are dropped; the event is
  recorded in the OCL error capture, `docs/FPGA_F2.md`).
- The L1 D$ is write-back and the host's PCIS view of memory does not see
  dirty lines (no Zicbom). On Sigil `FENCE.I` writes back every dirty D$
  line.
- DDR4 has ECC: memory the host never wrote reads back as an error. The
  host zero-fills all of DDR4 once per AFI load (CL memory engine), so
  memory not loaded with an image reads as zero after an AFI load (and as
  whatever an earlier run left there after that). HBM has no ECC.
- Simulation builds (`soc_rtl_tb`, `fpga_top_tb`) keep a small RAM window
  (default 128 MiB) through a parameter; the map above is the F2 build.
- Linux (Sv39) direct-maps up to 128 GiB of physical memory, so the 64 GiB
  of system RAM + pmem need no Sv48.

## NUMA and "talking to DDR4 or HBM"

- Device tree: `cpu@0` and the DDR4 `memory` node carry `numa-node-id = <0>`;
  the HBM `memory` node `numa-node-id = <1>`; a `distance-map`
  (`numa-distance-map-v1`) with node0↔node1 > local.
- Default allocations (`malloc`, the kernel) come from node 0 (DDR4).
- HBM explicitly: `numactl --membind=1 ./prog`, `numa_alloc_onnode(n, 1)`
  (libnuma), or `mbind()`/`set_mempolicy()`. Physical ranges appear in
  `/proc/iomem` and `/sys/devices/system/node/node{0,1}/`.

## Devices added for Linux

- **Test finisher** at `0x0010_0000` (QEMU `virt` semantics): 32-bit write
  `0x5555` = power off (pass), `0x7777` = reboot, `(code << 16) | 0x3333` =
  power off with failure `code`. DT: `test@100000 { compatible =
  "sifive,test1", "sifive,test0", "syscon"; }` plus `syscon-poweroff`
  (value `0x5555`) and `syscon-reboot` (value `0x7777`) nodes, through
  which OpenSBI implements SBI SRST; Linux `poweroff` / `reboot` reach the
  finisher only through SBI SRST (below). On F2 the event is visible to the
  host over OCL; `sigil_host` ends the run (or re-boots) accordingly.
- **RTC** at `0x0010_1000`, goldfish-RTC register layout (time, alarm,
  `IRQ_ENABLED` …); interrupt = **PLIC source 11** (as QEMU `virt`; the
  Linux goldfish driver needs it). The host sets the time to its wall
  clock before every release from reset; guest writes last until the next
  SoC reset.
- **Power-off and reboot only through SBI SRST.** The kernel is built
  without syscon power-off/reboot drivers (`CONFIG_POWER_RESET` off), and
  the Sigil OpenSBI (`sw/linux/opensbi/0001-*.patch`) executes `FENCE.I`
  (writes back every dirty D$ line) before it writes the finisher, so
  after a power-off the host's view of memory (e.g. the pmem disk it
  saves) is complete. On a finisher reboot the host reloads
  OpenSBI, the kernel, the DTB and the initrd, but never anything in the
  pmem window; the disk keeps what the guest wrote.

## Timer

`mtime` advances **once per core clock**. The device tree's
`timebase-frequency` therefore equals the core clock of the build:
**62 500 000** for the current F2 recipe B1 (62.5 MHz); update it with the
clock recipe (#53). The host can read the build's clock from OCL `CLK_KHZ`.

## Boot

OpenSBI `fw_jump` at `0x8000_0000`; kernel `Image` at `0x8020_0000` (up
to 46 MiB); DTB at **`0x8300_0000`** (the boot ROM's `a1`; OpenSBI built
with `FW_JUMP_FDT_ADDR=0x83000000`); optional initramfs at `0x8400_0000`.
Optional: if the DTB has a `/chosen/rng-seed` property, the host fills it
with fresh random bytes before every release (same size; the OS build
reserves it). Root filesystem on `/dev/pmem0` (ext4), loaded by the host
into the pmem window before boot and optionally saved back after
power-off; a finisher reboot never reloads the pmem window. Console
`ttyS0` (16550, PLIC source 10) with a login `getty`.

## ISA string for the kernel / toolchains

`rv64imafdc` + `zicsr zifencei zba zbb zbc zbs zbkb zbkc zbkx zkne zknd
zknh zicond zca zcb zcd zve32x zve32f zve64x zve64f zve64d` + `h`; VLEN 512.
Linux 6.12 LTS (Zve support for user-space vector).
