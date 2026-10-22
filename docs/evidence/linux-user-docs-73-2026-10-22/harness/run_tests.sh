#!/bin/bash
# sigil-linux logic tests with a fake sigil_host / fake AFI tools.
set -uo pipefail
T=/home/ubuntu/docs73/test
rm -rf "$T/cache" "$T/disk" "$T/fake" "$T/bin"; mkdir -p "$T"/{rel,bin,fake,disk,sigil/fpga/host}
cp "$T/src/fake_sigil_host" "$T/sigil/fpga/host/sigil_host"
cp "$T/src/fake_sudo" "$T/bin/sudo"
cp "$T/src/fake_describe" "$T/bin/fpga-describe-local-image"
cp "$T/src/fake_load" "$T/bin/fpga-load-local-image"
chmod +x "$T"/bin/* "$T/sigil/fpga/host/sigil_host"
if [ ! -f "$T/rel/SHA256SUMS" ]; then
  cp ~/os-artifacts/{fw_jump.bin,Image,sigil-f2.dtb,sigil-debian-13-riscv64.ext4.zst,SHA256SUMS} "$T/rel/"
fi
export PATH=$T/bin:$PATH SIGIL=$T/sigil SIGIL_LINUX_CACHE=$T/cache SIGIL_LINUX_URL=file://$T/rel SIGIL_DISK=$T/disk/d.ext4
SL=$T/src/sigil-linux
ctl() { printf 'rc=%s\naction=%s\n' "$1" "$2" > "$T/fake/ctl"; }
has() { debugfs -R "cat /home/sigil/$2" "$1" 2>/dev/null | grep -q "hello"; }
pass=0; fail=0
ok() { if eval "$2"; then echo "PASS: $1"; pass=$((pass+1)); else echo "FAIL: $1"; fail=$((fail+1)); fi; }
D=$SIGIL_DISK

echo "== 1. first run: download, verify, unpack, load AFI, power off -> saved"
ctl 0 write:run1.txt
t0=$(date +%s.%N); $SL < /dev/null > "$T/out1" 2>&1; rc=$?; t1=$(date +%s.%N)
cat "$T/out1"; echo "rc=$rc time=$(echo "$t1 - $t0" | bc)"
ok "rc 0" '[ $rc = 0 ]'
ok "AFI loaded" 'grep -q agfi-0a1fd54ef68bdc754 $T/fake/afi'
ok "disk has run1" 'has $D run1.txt'
ok "disk is 8 GiB" '[ $(stat -c %s $D) = 8589934592 ]'
ok "release sidecar" '[ "$(cat $D.release)" = sigil-linux-f2-2026-10-22 ]'
ok "e2fsck clean" 'e2fsck -fn $D >/dev/null 2>&1'
ok "args" 'grep -q -- "--linux --fw $T/cache/sigil-linux-f2-2026-10-22/fw_jump.bin --image $T/cache/sigil-linux-f2-2026-10-22/Image --dtb $T/cache/sigil-linux-f2-2026-10-22/sigil-f2.dtb --load 0xC80000000=$D --save 0xC80000000=/dev/shm/sigil-linux.*/pmem.ext4:17179869184 --console --on-reboot rerun" $T/fake/last-args'
ok "tmp cleaned" '! ls -d /dev/shm/sigil-linux.* 2>/dev/null'
du -h --apparent-size $D; du -h $D

echo "== 2. rerun: no download, AFI kept, Ctrl-] (rc 4) -> disk unchanged, .unclean kept"
ctl 4 write:run2.txt
$SL -- --log $T/console.log < /dev/null > "$T/out2" 2>&1; rc=$?; cat "$T/out2"
ok "rc 4" '[ $rc = 4 ]'
ok "no download" '! grep -q downloading $T/out2'
ok "no AFI load" '! grep -q "loading the Sigil AFI" $T/out2'
ok "extra args passed" 'grep -q -- "--on-reboot rerun --log $T/console.log" $T/fake/last-args'
ok "disk unchanged (run1, no run2)" 'has $D run1.txt && ! has $D run2.txt'
ok "unclean has run2" 'has $D.unclean run2.txt'

echo "== 3. power off after resize2fs to 16 GiB -> disk 16 GiB"
ctl 0 resize
$SL < /dev/null > "$T/out3" 2>&1; rc=$?; cat "$T/out3"
ok "rc 0" '[ $rc = 0 ]'
ok "disk 16 GiB" '[ $(stat -c %s $D) = 17179869184 ]'
ok "resized file" 'has $D resized.txt && has $D run1.txt'
ok "dumpe2fs agrees" '[ $(( $(dumpe2fs -h $D 2>/dev/null | sed -n "s/^Block count: *//p") * 4096 )) = 17179869184 ]'
ok "e2fsck clean" 'e2fsck -fn $D >/dev/null 2>&1'

echo "== 4. garbage beyond the file system (fresh 8 GiB disk) is trimmed"

ctl 0 garbage
$SL --fresh < /dev/null > "$T/out4" 2>&1; rc=$?; cat "$T/out4"
ok "rc 0" '[ $rc = 0 ]'
ok "old kept" '[ -f $D.old ]'
ok "disk 8 GiB again" '[ $(stat -c %s $D) = 8589934592 ]'
ok "fresh disk lacks run1" '! has $D run1.txt'

echo "== 5. setup error (rc 3): nothing saved"
ctl 3 none
$SL < /dev/null > "$T/out5" 2>&1; rc=$?; cat "$T/out5"
ok "rc 3" '[ $rc = 3 ]'
ok "message" 'grep -q "nothing saved" $T/out5'

echo "== 6. power off but window wiped (no ext4): disk unchanged"
ctl 0 wipe
md5_before=$(md5sum < $D)
$SL < /dev/null > "$T/out6" 2>&1; rc=$?; cat "$T/out6"
ok "disk unchanged" '[ "$(md5sum < $D)" = "$md5_before" ]'
ok "message" 'grep -q "no longer holds an ext4" $T/out6'

echo "== 7. corrupted cache file is downloaded again"
printf 'x' >> $T/cache/sigil-linux-f2-2026-10-22/Image
ctl 0 write:run7.txt
$SL < /dev/null > "$T/out7" 2>&1; rc=$?; cat "$T/out7"
ok "rc 0" '[ $rc = 0 ]'
ok "redownloaded" 'grep -q "downloading Image" $T/out7'

echo "== 8. a tag that is not published fails before touching anything"
md5_before=$(md5sum < $D)
SIGIL_LINUX_URL=file://$T/nonexistent $SL --tag bogus-tag < /dev/null > "$T/out8" 2>&1; rc=$?; cat "$T/out8"
ok "rc 1" '[ $rc = 1 ]'
ok "disk unchanged" '[ "$(md5sum < $D)" = "$md5_before" ]'

echo "== 9. lock"
( exec 9> $T/cache/.lock; flock 9; sleep 3 ) & sleep 0.5
$SL < /dev/null > "$T/out9" 2>&1; rc=$?; cat "$T/out9"; wait
ok "locked out" 'grep -q "another sigil-linux" $T/out9'

echo "== 10. --help"
$SL --help > "$T/out10" 2>&1; rc=$?; head -5 "$T/out10"
ok "help rc 0" '[ $rc = 0 ] && grep -q -- "--fresh" $T/out10'

echo "== 11. save path at full size: 16 GiB written in /dev/shm (as sigil_host does), sparse copy to the disk volume"
d=$(mktemp -d /dev/shm/sl-save.XXXX)
dd if=$D of=$d/pmem.ext4 bs=4M status=none; dd if=/dev/zero of=$d/pmem.ext4 bs=4M seek=2048 count=2048 status=none
eval "$(sed -n "/^# Size in bytes/,/^fresh=0/p" $SL | sed '$d')"
fsb=$(ext4_bytes $d/pmem.ext4)
t0=$(date +%s.%N); sparse_copy $d/pmem.ext4 $T/disk/save-test.ext4 $fsb; t1=$(date +%s.%N)
echo "window file $(du -h $d/pmem.ext4 | cut -f1) allocated; file system $fsb bytes; sparse copy $(echo "$t1 - $t0" | bc) s -> $(du -h $T/disk/save-test.ext4 | cut -f1) allocated"
ok "ext4_bytes = dumpe2fs" '[ $fsb = $(( $(dumpe2fs -h $D 2>/dev/null | sed -n "s/^Block count: *//p") * 4096 )) ]'
ok "copy identical" 'cmp <(head -c $fsb $d/pmem.ext4) $T/disk/save-test.ext4'
rm -rf $d $T/disk/save-test.ext4

echo "RESULT: $pass passed, $fail failed"
