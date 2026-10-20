#!/usr/bin/env bash
# Build a RISC-V Linux Image (defconfig, modules off, embedded
# initramfs carrying sw/linux/init.c) for the soc_tb boot gate
# (issue #21). Output: build/linux/Image. Kernel source is
# fetched once into build/linux/linux-6.6 (not committed).
# SIGIL_INIT_SRC / SIGIL_IMAGE_OUT select an alternate
# /init and output path (used by the KVM smoke, issue #22).
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/linux
INIT_SRC=${SIGIL_INIT_SRC:-sw/linux/init.c}
IMAGE_OUT=${SIGIL_IMAGE_OUT:-build/linux/Image}
SRC=build/linux/linux-6.6
if [ ! -d "$SRC/kernel" ]; then
  if [ ! -f build/linux/linux-6.6.tar.xz ]; then
    curl -L -o build/linux/linux-6.6.tar.xz \
      https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-6.6.tar.xz
  fi
  tar -xf build/linux/linux-6.6.tar.xz -C build/linux
fi
docker run --rm -e INIT_SRC="$INIT_SRC" -e IMAGE_OUT="$IMAGE_OUT" \
  -v "$PWD:/work" -w /work ubuntu:24.04 \
  bash -euo pipefail -c '
    apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
      --no-install-recommends gcc gcc-riscv64-linux-gnu \
      libc6-dev libc6-dev-riscv64-cross bc bison flex \
      libssl-dev libelf-dev cpio make ca-certificates >/dev/null
    # Embedded initramfs staged in-container (device nodes need root).
    mkdir -p /tmp/initramfs/dev /tmp/initramfs/proc /tmp/initramfs/sys
    riscv64-linux-gnu-gcc -static -O2 -o /tmp/initramfs/init "$INIT_SRC"
    mknod -m 600 /tmp/initramfs/dev/console c 5 1
    mknod -m 666 /tmp/initramfs/dev/null c 1 3
    cd build/linux/linux-6.6
    export ARCH=riscv CROSS_COMPILE=riscv64-linux-gnu-
    make defconfig >/dev/null
    ./scripts/config --disable MODULES --disable DEBUG_INFO \
      --set-str INITRAMFS_SOURCE /tmp/initramfs \
      --enable DEVTMPFS --enable SERIAL_8250_CONSOLE
    make olddefconfig >/dev/null
    make Image -j"$(nproc)" >/dev/null
    cp arch/riscv/boot/Image "/work/$IMAGE_OUT"
  '
echo "built $IMAGE_OUT (init: $INIT_SRC)"
