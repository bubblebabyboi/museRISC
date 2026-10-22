#!/usr/bin/env bash
# Build OpenSBI v1.9 (generic platform, fw_jump) for Sigil (issues #21,
# #68) and the device trees (scripts/build_dtbs.sh).
#   fw_jump at 0x8000_0000, next stage (Linux Image) at 0x8020_0000,
#   FDT relocated to / passed at 0x8300_0000 (the boot ROM's a1).
# Reset/power-off come from the DT (syscon-poweroff/-reboot on the
# sifive,test1 finisher), so SBI SRST and Linux poweroff work.
# Outputs: build/linux/fw_jump.bin, fw_jump.elf, *.dtb, opensbi.sha256.
# Toolchain: gcc-riscv64-linux-gnu + device-tree-compiler (Ubuntu
# 24.04); without them the script re-runs itself in Docker. The host
# bare-metal linker cannot create the PIEs OpenSBI needs
# (docs/evidence/core-stage3d-linux-attempt-2026-10-13.log).
set -euo pipefail
cd "$(dirname "$0")/.."

OSBI_TAG=v1.9
OSBI_COMMIT=cbf9f6734dd85a982c63e3cb5db7ffe09da839ca

if { ! command -v riscv64-linux-gnu-gcc || ! command -v dtc; } >/dev/null 2>&1 \
   && [ -z "${SIGIL_IN_DOCKER:-}" ]; then
  command -v docker >/dev/null || {
    echo "error: need riscv64-linux-gnu-gcc and dtc, or Docker" >&2; exit 1; }
  exec docker run --rm -e SIGIL_IN_DOCKER=1 -v "$PWD:/work" -w /work ubuntu:24.04 \
    bash -euo pipefail -c '
      apt-get update -qq
      DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends \
        gcc-riscv64-linux-gnu device-tree-compiler make git ca-certificates python3 >/dev/null
      bash scripts/build_opensbi.sh'
fi

mkdir -p build/linux
SRC=${OPENSBI_SRC:-build/linux/opensbi-$OSBI_TAG}
if [ ! -d "$SRC/lib" ]; then
  git clone -q --depth 1 --branch "$OSBI_TAG" \
    https://github.com/riscv-software-src/opensbi.git "$SRC"
fi
REV=$(git -C "$SRC" rev-parse HEAD)
[ "$REV" = "$OSBI_COMMIT" ] || {
  echo "error: $SRC is at $REV, expected $OSBI_TAG = $OSBI_COMMIT" >&2; exit 1; }

bash scripts/build_dtbs.sh
make -s -C "$SRC" O="$PWD/build/linux/opensbi-build" PLATFORM=generic \
  CROSS_COMPILE=riscv64-linux-gnu- FW_JUMP_ADDR=0x80200000 \
  FW_JUMP_FDT_ADDR=0x83000000 -j"$(nproc)"
FW=build/linux/opensbi-build/platform/generic/firmware
cp "$FW/fw_jump.bin" "$FW/fw_jump.elf" build/linux/
( cd build/linux && sha256sum fw_jump.bin fw_jump.elf > opensbi.sha256 && cat opensbi.sha256 )
echo "built build/linux/fw_jump.bin (OpenSBI $OSBI_TAG $REV) and the DTBs"
