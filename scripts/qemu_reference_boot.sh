#!/usr/bin/env bash
# QEMU reference boot oracle (issue #30).
#
# QEMU cannot execute RTL. This script boots the *same* kernel
# image used by the RTL Linux gate (scripts/build_linux_kernel.sh's
# Image-initramfs: embedded initramfs with sw/linux/init.c) under
# qemu-system-riscv64 -machine virt, captures the UART log, and
# diffs the platform-independent markers against the recorded
# Verilated-SoC boot log. The Verilated SoC remains the only
# "Linux on our RTL" evidence; this is a fast software oracle.
#
# QEMU runs on the host if installed, else in Docker (ubuntu:24.04).
# Output: build/linux/qemu-virt-boot.log.
set -euo pipefail
cd "$(dirname "$0")/.."

IMAGE=${SIGIL_KERNEL_IMAGE:-build/linux/Image-initramfs}
OUT=${SIGIL_QEMU_LOG:-build/linux/qemu-virt-boot.log}
RTL_LOG=${SIGIL_RTL_LOG:-docs/evidence/linux-debian-73-2026-10-22/soc-rtl-linux-6.12-boot.log}
TIMEOUT=${SIGIL_QEMU_TIMEOUT:-90}

if [ ! -f "$IMAGE" ]; then
  echo "error: $IMAGE not found -- run: bash scripts/build_linux_kernel.sh" >&2
  exit 1
fi
if [ ! -f "$RTL_LOG" ]; then
  echo "error: RTL reference log $RTL_LOG not found" >&2
  exit 1
fi
mkdir -p "$(dirname "$OUT")"

echo "== QEMU reference boot: $IMAGE (timeout ${TIMEOUT}s)"
# /init idles forever after printing the OK marker, so the run is
# bounded by timeout and judged by the marker below. Host QEMU if
# installed (apt install qemu-system-misc), else QEMU in Docker.
QEMU_CMD="timeout $TIMEOUT qemu-system-riscv64 -machine virt -cpu rv64 \
  -smp 1 -m 256M -nographic -monitor none -serial stdio \
  -display none -bios default -kernel $IMAGE \
  -append 'console=ttyS0,115200 earlycon=sbi cryptomgr.notests loglevel=8 rw'"
if command -v qemu-system-riscv64 >/dev/null; then
  qemu-system-riscv64 --version | head -1
  bash -c "$QEMU_CMD" > "$OUT" 2>&1 || true
else
  docker run --rm -e QEMU_CMD="$QEMU_CMD" -e OUT="$OUT" -v "$PWD:/work" -w /work ubuntu:24.04 \
    bash -euo pipefail -c '
      apt-get update -qq >/dev/null
      DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
        --no-install-recommends qemu-system-riscv64 >/dev/null 2>&1 || \
      DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
        --no-install-recommends qemu-system-misc >/dev/null
      qemu-system-riscv64 --version | head -1
      bash -c "$QEMU_CMD" > "$OUT" 2>&1 || true
    '
fi

if ! grep -aq 'SIGIL_LINUX_BOOT_OK' "$OUT"; then
  echo "FAIL: QEMU boot did not reach SIGIL_LINUX_BOOT_OK ($OUT)" >&2
  tail -20 "$OUT" >&2 || true
  exit 1
fi

# Compare platform-independent markers (timestamps and CRs stripped,
# and the build stamp "(user@host) ... #N SMP <date>", so any build of
# the same kernel version and compiler compares equal).
markers() {
  grep -a -E 'Linux version [0-9]|sigil init: userspace alive|uname: Linux|/proc/version:|SIGIL_LINUX_BOOT_OK' "$1" \
    | sed -E 's/\r//g; s/^\[[^]]*\] //; s/\([^()]*@[^()]*\) //; s/#[0-9]+ SMP [A-Z][a-z]{2} [A-Z][a-z]{2} [ 0-9]{2} [0-9:]{8} [A-Z]+ [0-9]{4}/#N SMP <date>/'
}
qemu_markers=$(markers "$OUT")
rtl_markers=$(markers "$RTL_LOG")
echo "== marker diff (QEMU vs Verilated SoC evidence)"
if diff <(printf '%s\n' "$qemu_markers") <(printf '%s\n' "$rtl_markers"); then
  echo "QEMU REFERENCE BOOT PASS: markers match $RTL_LOG"
else
  echo "FAIL: boot markers differ (see diff above)" >&2
  exit 1
fi
