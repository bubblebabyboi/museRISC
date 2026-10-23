#!/bin/bash
# 100 MHz Debian trial, runs 1+2 with absolute paths (OS agent)
W=/mnt/nvme/os73
exec > $W/trialb.log 2>&1
set -x
cd $W
STAMP=$(date +%s); echo $STAMP > $W/stamp
H="sudo /home/ubuntu/sigil/fpga/host/sigil_host --linux --fw $W/fw_jump.bin --image $W/Image --dtb $W/sigil-f2-100.dtb --console --on-reboot exit"
python3 /home/ubuntu/os73/qemu_sigil_check.py --label F2-100 --scale 40 --no-reboot --stamp $STAMP \
  --release "SoC released" --log $W/f2-100-run1.log \
  --cmd "$H --load 0xC80000000=$W/sigil-debian-13-riscv64.ext4 --save 0xC80000000=$W/sigil-disk-saved.ext4:8G" > $W/f2-100-run1.out 2>&1
python3 /home/ubuntu/os73/qemu_sigil_check.py --label F2-100 --scale 40 --persist-check $STAMP \
  --release "SoC released" --log $W/f2-100-run2.log \
  --cmd "$H --load 0xC80000000=$W/sigil-disk-saved.ext4 --save 0xC80000000=$W/sigil-disk-saved2.ext4:8G" > $W/f2-100-run2.out 2>&1
sudo sha256sum $W/sigil-disk-saved.ext4 $W/sigil-disk-saved2.ext4 > $W/saved.sha256
date -u
echo TRIAL_DONE
