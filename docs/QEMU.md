# QEMU reference oracle (#30)

QEMU cannot execute RTL. It is useful here only as a fast,
independent *software* reference for the same Linux payload
that the Verilated SoC boots. The Verilated `soc_tb` run in
`docs/evidence/core-stage6-linux-boot-2026-10-14.log`
remains the only "Linux on our RTL" evidence.

## Reproduce

Build the kernel once (`build/linux/Image-initramfs`, the
Linux 6.12 kernel with an embedded initramfs carrying
`sw/linux/init.c`), then run the reference boot and the
user-mode oracle smoke. Since #68 the reference RTL log is the
`soc_rtl_tb` boot of that kernel
(`docs/evidence/linux-debian-73-2026-10-22/soc-rtl-linux-6.12-boot.log`)
and build stamps (`user@host`, `#N SMP <date>`) are ignored in
the marker diff; the 6.6 result below is the original spike.
For the full Debian system in QEMU see [`LINUX.md`](LINUX.md).

```bash
bash scripts/build_linux_kernel.sh        # if build/linux/Image-initramfs is absent
bash scripts/qemu_reference_boot.sh       # system-mode virt boot + marker diff
bash scripts/qemu_user_oracle.sh          # static user-mode payload smoke
```

The reference boot uses the host's `qemu-system-riscv64` when
installed and otherwise QEMU inside Docker (`ubuntu:24.04`); the
user-mode smoke runs in Docker. The captured QEMU
system-mode log from the spike run is
[`docs/evidence/qemu-virt-reference-boot-2026-10-14.log`](evidence/qemu-virt-reference-boot-2026-10-14.log).

## Result

`scripts/qemu_reference_boot.sh` boots the exact
`build/linux/Image` used by the `soc_tb` gate under
`qemu-system-riscv64 -machine virt -bios default` (QEMU's
bundled OpenSBI), with the same kernel command line minus
`initcall_debug`, and compares the platform-independent
markers (kernel version banner, `sigil init:
userspace alive`, `uname:` line, `/proc/version:` line,
`SIGIL_LINUX_BOOT_OK`) against the RTL evidence log.
The markers match verbatim: `QEMU REFERENCE BOOT PASS`.

`scripts/qemu_user_oracle.sh` builds `sw/qemu/user_oracle.c`
as a static RISC-V Linux binary and runs it under
`qemu-riscv64` user mode, producing
`SIGIL_QEMU_USER_OK x=655d5f49 sum=325770522 acc=17500.0`.
The kernel `/init` itself is not a user-mode test (it
assumes PID 1, mounts proc, and idles forever), hence the
separate tiny payload.

## Platform differences (not core differences)

- Platform/DT identity: `riscv-virtio,qemu` vs
  `Sigil in-house RV64GC core (Verilator)`; QEMU
  supplies its own virt device tree, RTL uses
  `sw/linux/sigil.dts`.
- Firmware: QEMU-bundled OpenSBI v1.3 vs the locally
  built OpenSBI v1.9 `fw_jump.bin` on RTL. QEMU virt also
  exposes a `sifive_test` reboot/shutdown device; the
  SoC platform does not.
- Memory: 256 MiB on QEMU (script choice) vs 128 MiB in
  `soc_tb`; the `Memory:` availability line differs
  accordingly.
- Interrupt controller: both expose a PLIC at
  `0xc000000` and the 16550 UART at `0x10000000` on
  IRQ 12, but QEMU maps 95 interrupts vs 32 in the
  Sigil DT, and reports `base_baud = 230400` vs 115200.
- Verbosity/timing: the RTL log uses `initcall_debug`
  and ends with the harness line `SOC TB PASS (exit
  string at 508905040 cycles)`; QEMU has no cycle count
  and boots in seconds. Kernel timestamps are wall-clock
  model time in both logs and are not compared.

No unexplained difference was found: every delta above
is attributable to the platform model, firmware, DT, or
harness, not to core behavior. The identical kernel
banner and `/init` output confirm the checked-in Image
is a valid Linux payload independently of the RTL.

## Decision

Boot-log marker diffing plus the user-mode oracle smoke
are enough for now. A lockstep QEMU/Spike-vs-`core_tb`
retire-trace harness is **not** worth building at this
stage: QEMU's virt platform differs from `soc_tb` in DT,
firmware, and devices, so lockstep would compare
platforms more than cores; ISA-level differential
coverage already comes from riscv-tests, ACT against
Sail, and the SoftFloat-checked unit TBs. Revisit only
if a future SoC platform is modeled bit-compatibly in
both environments.
