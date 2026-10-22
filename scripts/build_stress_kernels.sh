#!/usr/bin/env bash
# Build the Sigil Linux stress kernels for the F2 bring-up (#73): the
# sigil_defconfig kernel with an embedded initramfs whose /init is
#   Image-memstress   sw/linux/stress/memstress.c (static C: anonymous
#                     memory, FENCE.I, fork/COW, AMO + LR/SC, 6 processes)
#   Image-execstress  sw/linux/stress/execstress.sh + Debian's static
#                     busybox (6 parallel fork/exec loops)
#   Image-pmemstress  sw/linux/stress/pmemstress.sh + busybox: mounts the
#                     Debian disk (/dev/pmem0) read-only, checksums files
#                     and execs Debian binaries from it (needs the disk)
# Outputs: build/linux/stress/{Image-memstress,Image-execstress,Image-pmemstress,SHA256SUMS}.
# Boot them like Image-initramfs (OpenSBI fw_jump + any sigil-*.dtb);
# only pmemstress needs the disk image in the pmem window. Run scripts/build_linux_kernel.sh first (source + config).
set -euo pipefail
cd "$(dirname "$0")/.."
KVER=6.12.114
SRC=$PWD/build/linux/linux-$KVER
OUT=$PWD/build/linux/stress
OBJ=$PWD/build/linux/obj-stress
BB_URL=http://snapshot.debian.org/archive/debian/20261020T000000Z/pool/main/b/busybox/busybox-static_1.37.0-6+b9_riscv64.deb
BB_SHA256=4add476d2b185c5b487c285b38d790f0881a7e4a8e2ddde835f917e770eb8633
[ -d "$SRC/kernel" ] || { echo "error: run scripts/build_linux_kernel.sh first" >&2; exit 1; }
mkdir -p "$OUT/initramfs"
export ARCH=riscv CROSS_COMPILE=riscv64-linux-gnu-
export KBUILD_BUILD_USER=sigil KBUILD_BUILD_HOST=sigil-build

# Static busybox from the same Debian snapshot as the root file system.
BB=$OUT/initramfs/busybox
if [ ! -x "$BB" ]; then
  curl -fsSL -o "$OUT/busybox.deb" "$BB_URL"
  echo "$BB_SHA256  $OUT/busybox.deb" | sha256sum -c --quiet
  rm -rf "$OUT/bbx"; dpkg-deb -x "$OUT/busybox.deb" "$OUT/bbx"
  cp "$OUT/bbx/usr/bin/busybox" "$BB"
fi
riscv64-linux-gnu-gcc -static -O2 -o "$OUT/initramfs/memstress" sw/linux/stress/memstress.c

build() {  # $1 = output name, $2 = /init source path, $3 = extra cpio lines
  cat > "$OUT/initramfs/$1.list" <<LIST
dir /bin 0755 0 0
dir /dev 0755 0 0
nod /dev/console 0600 0 0 c 5 1
nod /dev/null 0666 0 0 c 1 3
dir /proc 0755 0 0
dir /sys 0755 0 0
dir /tmp 1777 0 0
file /init $2 0755 0 0
$3
LIST
  mkdir -p "$OBJ"
  cp sw/linux/kernel/sigil_defconfig "$SRC/arch/riscv/configs/sigil_defconfig"
  make -s -C "$SRC" O="$OBJ" sigil_defconfig
  "$SRC/scripts/config" --file "$OBJ/.config" --set-str INITRAMFS_SOURCE "$OUT/initramfs/$1.list"
  make -s -C "$SRC" O="$OBJ" olddefconfig
  make -s -C "$SRC" O="$OBJ" -j"$(( $(nproc) < 16 ? $(nproc) : 16 ))" Image
  cp "$OBJ/arch/riscv/boot/Image" "$OUT/$1"
}
build Image-memstress "$OUT/initramfs/memstress" ""
build Image-execstress "$PWD/sw/linux/stress/execstress.sh" "file /bin/busybox $BB 0755 0 0"
build Image-pmemstress "$PWD/sw/linux/stress/pmemstress.sh" "file /bin/busybox $BB 0755 0 0"
( cd "$OUT" && sha256sum Image-memstress Image-execstress Image-pmemstress > SHA256SUMS && cat SHA256SUMS )
