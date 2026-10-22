#!/usr/bin/env bash
# Build ptwstress (static riscv64 Linux binary) and Image-ptwstress, the
# Sigil 6.12 kernel with an initramfs whose /init is ptwstress (issue
# #73 oops hunt). Boot like Image-initramfs (fw_jump at 0x8000_0000,
# Image at 0x8020_0000, any sigil-*.dtb at 0x8300_0000).
#   KSRC=<linux-6.12.114 source>  KCONFIG=<kernel .config>  OUT=<dir>
#   sw/linux/oops/build_ptwstress.sh
# Needs riscv64-linux-gnu-gcc (static glibc) and a clean kernel source
# (built out of tree with O=).
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
KSRC=${KSRC:?kernel source}
KCONFIG=${KCONFIG:?kernel config}
OUT=${OUT:?output dir}
mkdir -p "$OUT/initramfs" "$OUT/obj"
python3 "$HERE/gen_ptwstress_gadgets.py" 48 > "$OUT/ptwstress_gadgets.S"
riscv64-linux-gnu-gcc -static -O2 -march=rv64gc -mabi=lp64d \
  -o "$OUT/initramfs/ptwstress" "$HERE/ptwstress.c" "$OUT/ptwstress_gadgets.S"
cat > "$OUT/initramfs/ptwstress.list" <<LIST
dir /dev 0755 0 0
nod /dev/console 0600 0 0 c 5 1
nod /dev/null 0666 0 0 c 1 3
dir /proc 0755 0 0
dir /tmp 1777 0 0
file /init $OUT/initramfs/ptwstress 0755 0 0
LIST
export ARCH=riscv CROSS_COMPILE=riscv64-linux-gnu-
export KBUILD_BUILD_USER=sigil KBUILD_BUILD_HOST=sigil-build
cp "$KCONFIG" "$OUT/obj/.config"
"$KSRC/scripts/config" --file "$OUT/obj/.config" --set-str INITRAMFS_SOURCE "$OUT/initramfs/ptwstress.list"
make -s -C "$KSRC" O="$OUT/obj" olddefconfig
make -s -C "$KSRC" O="$OUT/obj" -j"${JOBS:-8}" Image
cp "$OUT/obj/arch/riscv/boot/Image" "$OUT/Image-ptwstress"
( cd "$OUT" && sha256sum Image-ptwstress initramfs/ptwstress )
