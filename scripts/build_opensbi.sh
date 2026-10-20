#!/usr/bin/env bash
# Build OpenSBI (generic, fw_jump to 0x8020_0000) and the Sigil
# DTB for the soc_tb Linux-boot harness (issue #21). Runs in Docker:
# the host bare-metal linker cannot create the PIEs OpenSBI needs
# (docs/evidence/core-stage3d-linux-attempt-2026-10-13.log).
# Outputs: build/linux/fw_jump.bin, build/linux/sigil.dtb.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/linux
SRC="${OPENSBI_SRC:-/tmp/opensbi}"
if [ ! -d "$SRC/lib" ]; then
  echo "cloning OpenSBI to $SRC"
  git clone --depth 1 https://github.com/riscv-software-src/opensbi.git "$SRC"
fi
REV="$(git -C "$SRC" rev-parse --short HEAD 2>/dev/null || echo unknown)"
echo "OpenSBI source: $SRC @ $REV"
docker run --rm -v "$PWD:/work" -v "$SRC:/src/opensbi:ro" -w /work \
  ubuntu:24.04 bash -euo pipefail -c '
    apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
      --no-install-recommends gcc-riscv64-linux-gnu \
      device-tree-compiler make git ca-certificates python3 >/dev/null
    dtc -I dts -O dtb -o build/linux/sigil.dtb sw/linux/sigil.dts
    cp -r /src/opensbi /tmp/opensbi-build
    make -C /tmp/opensbi-build PLATFORM=generic \
      CROSS_COMPILE=riscv64-linux-gnu- \
      FW_JUMP_ADDR=0x80200000 -j"$(nproc)" >/dev/null
    cp /tmp/opensbi-build/build/platform/generic/firmware/fw_jump.bin \
       build/linux/fw_jump.bin
    cp /tmp/opensbi-build/build/platform/generic/firmware/fw_jump.elf \
       build/linux/fw_jump.elf
  '
echo "built build/linux/fw_jump.bin and build/linux/sigil.dtb (OpenSBI $REV)"
