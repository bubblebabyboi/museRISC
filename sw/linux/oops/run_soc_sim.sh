#!/bin/bash
# Launch a Linux stress kernel on oops_soc_rtl_tb (soc_rtl_tb + the #73
# consistency checker, make -C sim -f Makefile.oops oops-soc-rtl-tb) in
# the background (issue #73 oops hunt). Logs: <tag>.out (harness +
# OOPSCHK reports), <tag>.uart (console), in the current directory.
#   run_soc_sim.sh <tag> <tb-binary> <ptw|exec|mem|boot> [tb args, e.g. --mem-lat 40:50]
# Images: ptw = $PTW_IMAGE (default ./Image-ptwstress, built by
# build_ptwstress.sh); exec/mem = ~/os-artifacts/stress/Image-*stress;
# boot = ~/os-artifacts/Image-initramfs. Firmware/DTB from ~/os-artifacts.
set -e
tag=$1; tb=$2; img=$3; shift 3
A=~/os-artifacts; S=~/os-artifacts/stress
case $img in
  ptw)  FW=$S/fw_jump.bin; IM=${PTW_IMAGE:-$PWD/Image-ptwstress}; DTB=$S/sigil-sim.dtb; EXIT=(--exit-string "PTWSTRESS DONE") ;;
  exec) FW=$S/fw_jump.bin; IM=$S/Image-execstress; DTB=$S/sigil-sim.dtb; EXIT=(--exit-string "EXECSTRESS DONE") ;;
  mem)  FW=$S/fw_jump.bin; IM=$S/Image-memstress;  DTB=$S/sigil-sim.dtb; EXIT=() ;;
  boot) FW=$A/fw_jump.bin; IM=$A/Image-initramfs;  DTB=$A/sigil-sim.dtb; EXIT=(--exit-string SIGIL_LINUX_BOOT_OK) ;;
esac
nohup "$tb" 20000000000 "$@" --load 0x80000000="$FW" --load 0x80200000="$IM" --load 0x83000000="$DTB" \
  --uart-log "$tag.uart" "${EXIT[@]}" > "$tag.out" 2>&1 < /dev/null &
echo "started $tag pid $!"
