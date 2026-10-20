#!/usr/bin/env bash
# QEMU reference boot oracle (issue #30).
#
# QEMU cannot execute RTL. This script boots the *same* kernel
# Image used by the soc_tb Linux gate (scripts/build_linux_kernel.sh,
# embedded initramfs with sw/linux/init.c) under
# qemu-system-riscv64 -machine virt, captures the UART log, and
# diffs the platform-independent markers against the recorded
# Verilated-SoC boot log. The Verilated SoC remains the only
# "Linux on our RTL" evidence; this is a fast software oracle.
#
# QEMU runs in Docker (no host install needed), matching the
# other scripts/ flows. Output: build/linux/qemu-virt-boot.log.
set -euo pipefail
cd "$(dirname "$0")/.."

IMAGE=${SIGIL_KERNEL_IMAGE:-build/linux/Image}
OUT=${SIGIL_QEMU_LOG:-build/linux/qemu-virt-boot.log}
RTL_LOG=${SIGIL_RTL_LOG:-docs/evidence/core-stage6-linux-boot-2026-10-14.log}
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
docker run --rm -v "$PWD:/work" -w /work ubuntu:24.04 \
  bash -euo pipefail -c '
    apt-get update -qq >/dev/null
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
      --no-install-recommends qemu-system-riscv64 >/dev/null 2>&1 || \
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
      --no-install-recommends qemu-system-misc >/dev/null
    qemu-system-riscv64 --version | head -1
    # /init idles forever after printing the OK marker, so the
    # run is bounded by timeout and judged by the marker below.
    timeout '"$TIMEOUT"' qemu-system-riscv64 -machine virt -cpu rv64 \
      -smp 1 -m 256M -nographic -monitor none -serial stdio \
      -display none -bios default -kernel "'"$IMAGE"'" \
      -append "console=ttyS0,115200 earlycon=sbi cryptomgr.notests loglevel=8 rw" \
      > "'"$OUT"'" 2>&1 || true
  '

if ! grep -aq 'SIGIL_LINUX_BOOT_OK' "$OUT"; then
  echo "FAIL: QEMU boot did not reach SIGIL_LINUX_BOOT_OK ($OUT)" >&2
  tail -20 "$OUT" >&2 || true
  exit 1
fi

# Compare platform-independent markers (timestamps and CRs stripped).
markers() {
  grep -a -E 'Linux version 6\.6\.0|sigil init: userspace alive|uname: Linux|/proc/version:|SIGIL_LINUX_BOOT_OK' "$1" \
    | sed -E 's/\r//g; s/^\[[^]]*\] //'
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
