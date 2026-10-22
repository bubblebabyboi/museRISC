#!/usr/bin/env bash
# Build the Sigil Debian riscv64 root filesystem (issues #70, #69):
# Debian 13 "trixie" from a fixed snapshot.debian.org date, systemd with
# a login on ttyS0, gcc/build-essential and the usual GNU tools, numactl
# + libnuma for the HBM node, the Sigil kernel's modules, written into
# an ext4 image for the pmem disk window (root=/dev/pmem0).
#
#   sudo bash scripts/build_debian_rootfs.sh
#
# Needs (Ubuntu 24.04): mmdebstrap debian-archive-keyring qemu-user-static
# binfmt-support e2fsprogs zstd, and build/linux/modules-<krel>.tar.gz + Image + DTBs +
# fw_jump.bin from scripts/build_linux_kernel.sh and build_opensbi.sh.
# Outputs in build/debian/ (override with SIGIL_ROOTFS_OUT):
#   sigil-debian-13-riscv64.ext4       raw ext4 image (SIGIL_ROOTFS_SIZE, 8G)
#   sigil-debian-13-riscv64.ext4.zst   compressed for publishing
#   manifest.txt (package versions), rootfs.sha256
# Environment: SIGIL_DEBIAN_SNAPSHOT (default 20261020T000000Z),
# SIGIL_ROOTFS_SIZE, SIGIL_ROOTFS_OUT, SIGIL_PASSWORD (default sigil).
set -euo pipefail
cd "$(dirname "$0")/.."
REPO=$PWD

SNAPSHOT=${SIGIL_DEBIAN_SNAPSHOT:-20261020T000000Z}
SUITE=trixie
SIZE=${SIGIL_ROOTFS_SIZE:-8G}
OUT=${SIGIL_ROOTFS_OUT:-build/debian}
PASSWORD=${SIGIL_PASSWORD:-sigil}
NAME=sigil-debian-13-riscv64
MIRROR=http://snapshot.debian.org/archive/debian/$SNAPSHOT
SECMIRROR=http://snapshot.debian.org/archive/debian-security/$SNAPSHOT
# Ubuntu's debian-archive-keyring (2023.4) holds the bookworm archive
# keys, which also sign trixie's Release files; the image then gets
# trixie's own debian-archive-keyring package.
KEYRING=${SIGIL_DEBIAN_KEYRING:-/usr/share/keyrings/debian-archive-keyring.gpg}

MODULES=$(ls build/linux/modules-*.tar.gz 2>/dev/null | head -1 || true)
KREL=$(basename "${MODULES:-none}" .tar.gz); KREL=${KREL#modules-}

[ "$(id -u)" = 0 ] || { echo "error: run with sudo (mmdebstrap --mode=root, chroot)" >&2; exit 1; }
[ -f "$KEYRING" ] || { echo "error: $KEYRING missing (apt install debian-archive-keyring)" >&2; exit 1; }
for t in mmdebstrap mkfs.ext4 zstd; do
  command -v $t >/dev/null || { echo "error: $t missing" >&2; exit 1; }
done
[ -e /proc/sys/fs/binfmt_misc/qemu-riscv64 ] || {
  echo "error: no riscv64 binfmt handler (apt install qemu-user-static binfmt-support)" >&2; exit 1; }
[ -n "$KREL" ] && [ -f "$MODULES" ] || {
  echo "error: run scripts/build_linux_kernel.sh first ($MODULES)" >&2; exit 1; }

# Debian 13 packages: a normal developer system, nothing that needs a
# network or crawls on a 62.5 MHz in-order hart.
PACKAGES=(
  systemd systemd-sysv udev dbus libpam-systemd sudo
  procps psmisc iproute2 iputils-ping kmod util-linux-extra e2fsprogs
  ndctl numactl libnuma-dev tzdata netbase
  build-essential gcc g++ gdb make pkgconf git patch
  vim nano less htop tmux file strace lsof tree time bc
  python3 man-db manpages manpages-dev
  xz-utils zstd bzip2
)

mkdir -p "$OUT"
ROOT=$OUT/root
rm -rf "$ROOT"
echo "== mmdebstrap $SUITE riscv64 from $MIRROR"
mmdebstrap --mode=root --arch=riscv64 --variant=minbase --keyring="$KEYRING" \
  --aptopt='Acquire::Check-Valid-Until "false"' \
  --aptopt='Acquire::Retries "5"' \
  --include="$(IFS=,; echo "${PACKAGES[*]}")" \
  "$SUITE" "$ROOT" \
  "deb $MIRROR $SUITE main" \
  "deb $MIRROR $SUITE-updates main" \
  "deb $SECMIRROR $SUITE-security main"

ch() { chroot "$ROOT" /usr/bin/env -i PATH=/usr/sbin:/usr/bin:/sbin:/bin \
         LC_ALL=C.UTF-8 DEBIAN_FRONTEND=noninteractive "$@"; }

echo "== Sigil configuration"
# Overlay: fstab, hostname, issue/motd, systemd tuning, boot marker, ...
cp -a --no-preserve=ownership sw/linux/debian/overlay/. "$ROOT"/
rm -f "$ROOT/etc/apt/sources.list" "$ROOT/etc/resolv.conf"
cat > "$ROOT/etc/sigil-release" <<EOF
SIGIL_IMAGE=$NAME
DEBIAN_SNAPSHOT=$SNAPSHOT
DEBIAN_MIRROR=$MIRROR
KERNEL=$KREL
BUILT=$(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF
echo 'LANG=C.UTF-8' > "$ROOT/etc/default/locale"
ln -sf /usr/share/zoneinfo/Etc/UTC "$ROOT/etc/localtime"
echo Etc/UTC > "$ROOT/etc/timezone"

# Users. SHA-512 crypt (5000 rounds) instead of Debian's yescrypt
# default: yescrypt costs tens of seconds per login at 62.5 MHz.
HASH=$(openssl passwd -6 -salt sigilsigil "$PASSWORD")
ch useradd -m -s /bin/bash -u 1000 -c "Sigil user" \
  -G "$(for g in sudo adm systemd-journal kvm dialout; do
          ch getent group $g >/dev/null && printf '%s,' $g; done | sed 's/,$//')" sigil
ch usermod -p "$HASH" sigil
ch usermod -p "$HASH" root
sed -i 's/^\(password.*pam_unix\.so.*\) yescrypt/\1 sha512 rounds=5000/' "$ROOT/etc/pam.d/common-password"
sed -i 's/^#\?ENCRYPT_METHOD.*/ENCRYPT_METHOD SHA512/' "$ROOT/etc/login.defs"
grep -q 'sha512 rounds=5000' "$ROOT/etc/pam.d/common-password"

# Examples for the board's own gcc.
install -d -o 1000 -g 1000 "$ROOT/home/sigil/examples"
install -o 1000 -g 1000 -m 644 sw/linux/debian/examples/* "$ROOT/home/sigil/examples/"

# Kernel modules + the boot payloads for reference (the host loads its
# own copies; these document what the image was built for).
tar -C "$ROOT/usr" -xzf "$MODULES"
ch depmod -a "$KREL"
install -d "$ROOT/boot/sigil"
cp build/linux/Image "$ROOT/boot/Image-$KREL"
cp "build/linux/kernel-$KREL.config" "$ROOT/boot/config-$KREL"
cp "build/linux/System.map-$KREL" "$ROOT/boot/System.map-$KREL"
cp build/linux/fw_jump.bin build/linux/sigil-f2.dtb build/linux/sigil-qemu.dtb "$ROOT/boot/sigil/"

# systemd: boot marker on, network/maintenance timers off (no network,
# slow CPU); generated state created now instead of on first boot.
ch systemctl enable sigil-boot-ok.service
ch systemctl mask apt-daily.timer apt-daily-upgrade.timer man-db.timer \
  e2scrub_all.timer e2scrub_reap.service fstrim.timer dpkg-db-backup.timer \
  systemd-networkd-wait-online.service
ch systemctl set-default multi-user.target
ch ldconfig
ch systemd-hwdb update
ch journalctl --update-catalog
ch mandb -q || true
: > "$ROOT/etc/machine-id"           # generated (and committed) at first boot
rm -f "$ROOT/var/lib/dbus/machine-id"
ln -s /etc/machine-id "$ROOT/var/lib/dbus/machine-id"
ch /usr/lib/systemd/systemd-update-done   # no ConditionNeedsUpdate work at boot

# Manifest, then trim caches.
ch dpkg-query -W -f='${Package} ${Version} ${Architecture}\n' | sort > "$OUT/manifest.txt"
rm -rf "$ROOT"/var/cache/apt/*.bin "$ROOT"/var/cache/apt/archives/*.deb \
       "$ROOT"/var/lib/apt/lists/* "$ROOT"/var/log/*.log "$ROOT"/var/log/apt/* "$ROOT"/tmp/* \
       "$ROOT"/etc/ssh/ssh_host_* 2>/dev/null || true

echo "== ext4 image ($SIZE)"
IMG=$OUT/$NAME.ext4
rm -f "$IMG" "$IMG.zst"
mkfs.ext4 -q -F -L sigil-root -d "$ROOT" -b 4096 \
  -E lazy_itable_init=0,lazy_journal_init=0 "$IMG" "$SIZE"
e2fsck -fn "$IMG" >/dev/null
du -sh --apparent-size "$IMG"; du -sh "$IMG"
zstd -q -T16 -19 -f "$IMG" -o "$IMG.zst"
( cd "$OUT" && sha256sum "$NAME.ext4" "$NAME.ext4.zst" manifest.txt > rootfs.sha256 && cat rootfs.sha256 )
echo "packages: $(wc -l < "$OUT/manifest.txt"); used: $(du -sh "$ROOT" | cut -f1)"
echo "built $IMG (+ .zst) from Debian $SUITE snapshot $SNAPSHOT"
