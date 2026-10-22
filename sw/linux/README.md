# Linux on Sigil (#21, #68, #69, #70)

Everything that runs on the SoC: OpenSBI, the Linux 6.12 kernel
configuration, the device trees, the Debian root file system and the
boot-gate initramfs. The user guide is [`docs/LINUX.md`](../../docs/LINUX.md);
the hardware contract is [`docs/LINUX_PLATFORM.md`](../../docs/LINUX_PLATFORM.md).

| Path | What |
|---|---|
| `kernel/sigil.config` | readable kernel config fragment (on top of riscv `defconfig`) |
| `kernel/sigil_defconfig` | the full defconfig the build uses (`--regen-defconfig` recreates it) |
| `dts/sigil.dtsi` | the one device-tree source: hart + ISA, CLINT, PLIC, UART, finisher, RTC, crypto |
| `dts/sigil-f2.dts` | AWS F2: 48 GiB DDR4 node 0 + 16 GiB pmem disk + 16 GiB HBM node 1, 62.5 MHz |
| `dts/sigil-qemu.dts` | QEMU virt reference of the F2 map (10 MHz timebase, virtio slots) |
| `dts/sigil-sim.dts` | Verilator: 128 MiB, embedded initramfs; `sigil.dts` is its historic name |
| `debian/overlay/` | files the Debian image adds (fstab, issue/motd, systemd tuning, boot marker) |
| `debian/examples/` | `~/examples` in the image (gcc, malloc, NUMA/HBM, RVV) |
| `init.c` | initramfs `/init`: prints `SIGIL_LINUX_BOOT_OK` (boot gate, F2 smoke) |
| `kvm_smoke.c` | alternate `/init`: one KVM guest entry/exit (`SIGIL_KVM_OK`) |
| `boot_stub.S`, `s_hello.S` | simulator boot ROM stub; OpenSBI-only smoke payload |

Build (Ubuntu 24.04; package list in `docs/LINUX.md` §2):

```bash
bash scripts/build_opensbi.sh            # build/linux/fw_jump.bin + sigil-{f2,qemu,sim}.dtb, sigil.dtb
bash scripts/build_linux_kernel.sh       # build/linux/Image, Image-initramfs, modules
sudo bash scripts/build_debian_rootfs.sh # build/debian/sigil-debian-13-riscv64.ext4(.zst)
bash scripts/qemu_sigil_boot.sh          # boot it in QEMU (Ctrl-A X quits)
```

Boot layout (all platforms): boot ROM at `0x1000` sets `a0` = 0, `a1` =
`0x8300_0000` and jumps to OpenSBI `fw_jump` at `0x8000_0000`; OpenSBI
(built with `FW_JUMP_ADDR=0x80200000 FW_JUMP_FDT_ADDR=0x83000000`) starts
the kernel `Image` at `0x8020_0000` with the DTB at `0x8300_0000`; an
optional initrd goes to `0x8400_0000`. On F2 and QEMU the root file
system is `/dev/pmem0`, the 16 GiB DDR4 window at `0xC_8000_0000`.

## Verilator boot gate

`soc_tb` models a boot ROM, CLINT, PLIC, 16550 UART and 128 MiB RAM
(the addresses of `dts/sigil-sim.dts`). The gate boots the kernel with
the embedded initramfs:

```bash
make -C sim soc
bash scripts/build_opensbi.sh
bash scripts/build_linux_kernel.sh
build/sim/soc_tb 4000000000 \
  --load 0x1000=build/linux/boot_stub.bin \
  --load 0x80000000=build/linux/fw_jump.bin \
  --load 0x83000000=build/linux/sigil.dtb \
  --load 0x80200000=build/linux/Image-initramfs \
  --uart-log build/linux/linux-boot-uart.log \
  --exit-string SIGIL_LINUX_BOOT_OK
```

The recorded gate (#21, `docs/evidence/core-stage6-linux-boot-2026-10-14.log`)
used Linux 6.6 with riscv `defconfig`; the 6.12 `sigil_defconfig` kernel
drops the debug instrumentation and the drivers for hardware Sigil does
not have, so its boot is shorter. `soc_tb` cycle counts with the new
kernel have not been re-recorded.

Since the L1-cache stage `soc_tb` simulates `sigil_cpu` (core + L1
I$/D$) behind a memory-bus model: only DRAM is cacheable, the boot
ROM/CLINT/PLIC/UART are uncached I/O. Bus timing options `--mem-lat A:B`,
`--mem-gap N`, `--mem-ready PCT`, `--mem-seed S` randomize
latency/backpressure, and `--no-cache` disables the caches.

The OpenSBI-only smoke gate substitutes `s_hello.bin` for the kernel
`Image` and `--exit-string HELLO`.

The kernel command line is part of each DT (`chosen/bootargs`). Sim:
`console=ttyS0,115200 earlycon=sbi cryptomgr.notests initcall_debug
loglevel=8 rw no4lvl`; F2/QEMU: `console=ttyS0,115200 earlycon=sbi
root=/dev/pmem0 rootfstype=ext4 ro rootwait no4lvl`.

PLIC completion: the PLIC (RTL and the `soc_tb` model) follows the spec
and ignores a completion for a source that is not enabled for the
completing context. Linux 6.6.0's `plic_irq_eoi` wrote the completion
without checking that; the guard that briefly re-enables a disabled
source around the completion is present in 6.6.20+ and in 6.12.

## KVM smoke (#22)

The DT advertises H and the kernel has KVM built in. To build the
alternate image whose `/init` creates a one-vCPU VM and runs a
four-instruction guest to an MMIO exit:

```bash
SIGIL_INIT_SRC=sw/linux/kvm_smoke.c \
SIGIL_IMAGE_OUT=build/linux/Image-kvm \
  bash scripts/build_linux_kernel.sh
build/sim/soc_tb 1500000000 \
  --load 0x1000=build/linux/boot_stub.bin \
  --load 0x80000000=build/linux/fw_jump.bin \
  --load 0x83000000=build/linux/sigil.dtb \
  --load 0x80200000=build/linux/Image-kvm \
  --uart-log build/linux/kvm-boot-uart.log \
  --exit-string SIGIL_KVM_OK
```

The recorded run (Linux 6.6) reaches `SOC TB PASS` at 502,972,620
cycles. It proves the KVM ioctl path plus one guest entry/exit; it is
not a guest-OS boot.
