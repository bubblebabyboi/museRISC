#!/usr/bin/env bash
# Build the Sigil Linux kernel (issues #68, #64): Linux 6.12 LTS with
# sw/linux/kernel/sigil_defconfig. One kernel for every platform; the
# device tree (scripts/build_dtbs.sh) picks memory, timebase and root.
#
# Outputs in build/linux/:
#   Image              Sigil kernel, no initramfs: mounts root from the
#                      DT bootargs (/dev/pmem0 on F2 and QEMU)
#   Image-initramfs    same kernel + embedded initramfs whose /init
#                      (sw/linux/init.c) prints SIGIL_LINUX_BOOT_OK: the
#                      Verilator boot gate and the F2 smoke test
#   modules-<rel>.tar.gz  /lib/modules/<rel> for the root filesystem
#   kernel-<rel>.config, System.map-<rel>, kernel.sha256
#
#   bash scripts/build_linux_kernel.sh                   # build
#   bash scripts/build_linux_kernel.sh --regen-defconfig # riscv defconfig
#        + sw/linux/kernel/sigil.config -> sw/linux/kernel/sigil_defconfig
#
# Env: SIGIL_INIT_SRC / SIGIL_IMAGE_OUT choose another /init and output
# name for the initramfs image (the KVM smoke uses sw/linux/kvm_smoke.c);
# SIGIL_JOBS (default: min(nproc, 16)); SIGIL_KBUILD_TIMESTAMP.
#
# Toolchain: Ubuntu 24.04 packages gcc-riscv64-linux-gnu
# libc6-dev-riscv64-cross bc bison flex libssl-dev libelf-dev cpio make
# kmod. Without a native riscv64 cross compiler the script re-runs
# itself in Docker (ubuntu:24.04) when Docker is available.
set -euo pipefail
cd "$(dirname "$0")/.."

KVER=6.12.114
KSHA256=7a8589912bd7a8adb07fed074283652cf482a35facef8954554654f0154b4af3
KURL=https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-$KVER.tar.xz
MODE=${1:-build}

if ! command -v riscv64-linux-gnu-gcc >/dev/null 2>&1 && [ -z "${SIGIL_IN_DOCKER:-}" ]; then
  command -v docker >/dev/null || {
    echo "error: need riscv64-linux-gnu-gcc (apt install gcc-riscv64-linux-gnu) or Docker" >&2
    exit 1
  }
  exec docker run --rm -e SIGIL_IN_DOCKER=1 -e SIGIL_INIT_SRC -e SIGIL_IMAGE_OUT \
    -e SIGIL_JOBS -e SIGIL_KBUILD_TIMESTAMP -v "$PWD:/work" -w /work ubuntu:24.04 \
    bash -euo pipefail -c '
      apt-get update -qq
      DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends \
        gcc gcc-riscv64-linux-gnu libc6-dev libc6-dev-riscv64-cross bc bison flex \
        libssl-dev libelf-dev cpio make kmod curl xz-utils ca-certificates >/dev/null
      bash scripts/build_linux_kernel.sh '"$MODE"
fi

OUT=build/linux
SRC=$OUT/linux-$KVER
OBJ=$OUT/obj-$KVER
INIT_SRC=${SIGIL_INIT_SRC:-sw/linux/init.c}
INITRAMFS_OUT=${SIGIL_IMAGE_OUT:-$OUT/Image-initramfs}
JOBS=${SIGIL_JOBS:-$(( $(nproc) < 16 ? $(nproc) : 16 ))}
mkdir -p "$OUT"

if [ ! -d "$SRC/kernel" ]; then
  [ -f "$OUT/linux-$KVER.tar.xz" ] || curl -fsSL -o "$OUT/linux-$KVER.tar.xz" "$KURL"
  echo "$KSHA256  $OUT/linux-$KVER.tar.xz" | sha256sum -c --quiet
  tar -xf "$OUT/linux-$KVER.tar.xz" -C "$OUT"
fi

export ARCH=riscv CROSS_COMPILE=riscv64-linux-gnu-
export KBUILD_BUILD_USER=sigil KBUILD_BUILD_HOST=sigil-build
export KBUILD_BUILD_TIMESTAMP="${SIGIL_KBUILD_TIMESTAMP:-$(date -u '+%a %b %e %H:%M:%S UTC %Y')}"
K() { make -s -C "$SRC" O="$PWD/$OBJ" "$@"; }

if [ "$MODE" = --regen-defconfig ]; then
  rm -rf "$OBJ"; mkdir -p "$OBJ"
  K defconfig
  "$SRC/scripts/kconfig/merge_config.sh" -m -O "$OBJ" "$OBJ/.config" \
    sw/linux/kernel/sigil.config >/dev/null
  K olddefconfig
  # Every option the fragment sets must survive olddefconfig.
  bad=0
  while IFS= read -r line; do
    case $line in
      CONFIG_*=*) grep -qxF "$line" "$OBJ/.config" || { echo "not applied: $line"; bad=1; } ;;
      "# CONFIG_"*" is not set")
        sym=${line#\# }; sym=${sym%% *}
        grep -q "^$sym=" "$OBJ/.config" && { echo "still set: $sym"; bad=1; } ;;
    esac
  done < sw/linux/kernel/sigil.config
  [ "$bad" = 0 ] || { echo "error: fragment options not applied (see above)" >&2; exit 1; }
  K savedefconfig
  cp "$OBJ/defconfig" sw/linux/kernel/sigil_defconfig
  echo "wrote sw/linux/kernel/sigil_defconfig"
  exit 0
fi

# 1) Sigil kernel without initramfs.
mkdir -p "$OBJ"
cp sw/linux/kernel/sigil_defconfig "$SRC/arch/riscv/configs/sigil_defconfig"
K sigil_defconfig
K -j"$JOBS" Image modules
KREL=$(K -s kernelrelease)
cp "$OBJ/arch/riscv/boot/Image" "$OUT/Image"
cp "$OBJ/.config" "$OUT/kernel-$KREL.config"
cp "$OBJ/System.map" "$OUT/System.map-$KREL"
rm -rf "$OUT/modules-staging"
K INSTALL_MOD_PATH="$PWD/$OUT/modules-staging" INSTALL_MOD_STRIP=1 modules_install
tar -C "$OUT/modules-staging" --owner=0 --group=0 --sort=name -czf \
  "$OUT/modules-$KREL.tar.gz" lib
rm -rf "$OUT/modules-staging"

# 2) Same kernel + embedded initramfs (/init from $INIT_SRC). The cpio
#    list needs no root (device nodes are described, not created).
IRD=$OUT/initramfs
rm -rf "$IRD"; mkdir -p "$IRD"
riscv64-linux-gnu-gcc -static -O2 -o "$IRD/init" "$INIT_SRC"
cat > "$IRD/list" <<EOF
dir /dev 0755 0 0
nod /dev/console 0600 0 0 c 5 1
nod /dev/null 0666 0 0 c 1 3
dir /proc 0755 0 0
dir /sys 0755 0 0
file /init $PWD/$IRD/init 0755 0 0
EOF
"$SRC/scripts/config" --file "$OBJ/.config" --set-str INITRAMFS_SOURCE "$PWD/$IRD/list"
K olddefconfig
K -j"$JOBS" Image
cp "$OBJ/arch/riscv/boot/Image" "$INITRAMFS_OUT"
# Leave the object tree configured like sigil_defconfig again.
"$SRC/scripts/config" --file "$OBJ/.config" --set-str INITRAMFS_SOURCE ""
K olddefconfig

( cd "$OUT" && sha256sum Image "$(basename "$INITRAMFS_OUT")" "modules-$KREL.tar.gz" \
    "kernel-$KREL.config" > kernel.sha256 )
cat "$OUT/kernel.sha256"
echo "built Linux $KREL: $OUT/Image, $INITRAMFS_OUT (init: $INIT_SRC)"
