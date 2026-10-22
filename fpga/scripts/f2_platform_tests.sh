#!/bin/bash
# F2 hardware test session for the Sigil Linux platform AFI (issues #62,
# #63, #65, #66, #67). Run on an f2.6xlarge with the aws-fpga SDK set up
# and fpga/host/sigil_host built:
#
#   fpga/scripts/f2_platform_tests.sh AGFI PAYLOAD_DIR OUT_DIR
#
# PAYLOAD_DIR: fw/*.bin (make -C sim: hash_soc_test fpga_smoke_test
# crypto_soc_test ed25519_soc_test f2_platform_test f2_memtest) +
# fw/fpga_smoke_uart_in.txt, examples/*.bin (SDK examples), linux/
# (fw_jump.bin, Image, *.dtb, s_hello.bin). Every step writes
# OUT_DIR/<step>.host (sigil_host stderr) and OUT_DIR/<step>.uart, and
# a line to OUT_DIR/results.txt.
set -uo pipefail
AGFI=$1
P=$(cd "$2" && pwd)
OUT=$(mkdir -p "$3" && cd "$3" && pwd)
H=$(cd "$(dirname "${BASH_SOURCE[0]}")/../host" && pwd)/sigil_host
R=$OUT/results.txt
: > "$R"
step() {  # step NAME EXPECTED_RC sigil_host args...
  local name=$1 want=$2
  shift 2
  local s
  s=$(date +%s.%N)
  sudo "$H" "$@" > "$OUT/$name.uart" 2> "$OUT/$name.host"
  local rc=$?
  local dt
  dt=$(echo "$(date +%s.%N) - $s" | bc)
  local res
  res=$(grep -h "result:" "$OUT/$name.host" | tail -1 | sed 's/.*result: //')
  printf '%-22s rc=%d (want %d) %s  [%.1f s]  %s\n' "$name" "$rc" "$want" \
    "$([ "$rc" = "$want" ] && echo OK || echo MISMATCH)" "$dt" "$res" | tee -a "$R"
}

{
  date -u
  sudo fpga-describe-local-image -S 0 -H
  lscpu | grep "Model name"
  uname -r
} > "$OUT/instance-info.txt" 2>&1

echo "== load $AGFI" | tee -a "$R"
sudo fpga-load-local-image -S 0 -I "$AGFI" -H >> "$OUT/instance-info.txt" 2>&1
sudo fpga-describe-local-image -S 0 -H | tee -a "$OUT/instance-info.txt"
(cd "$P" && sha256sum fw/* examples/* linux/* 2>/dev/null) >> "$OUT/instance-info.txt"

FW=$P/fw
# 1. #62 root cause: fresh AFI, DDR4 not scrubbed -> the first D$ refill
#    of a never-written line (the stack) reads an ECC error (SLVERR).
step ecc62-noscrub 1 --scrub never --bin "$FW/hash_soc_test.bin" --timeout 10
# 2. The fix: scrub DDR4 once (memory engine), then no memory error.
step hash-scrub 0 --bin "$FW/hash_soc_test.bin" --timeout 20
# 3. Full-range memory test of DDR4 and HBM at AXI speed (engine).
step memtest-engine 0 --memtest all --scrub never
# 4. Platform: RTC, window edges, UART bursts, finisher; out-of-window
#    read (mailbox bit 0) caught by the bridge error capture.
step platform 0 --bin "$FW/f2_platform_test.bin" --mailbox 0 --timeout 30
step platform-oob 0 --bin "$FW/f2_platform_test.bin" --mailbox 1 --ignore-mem-err --timeout 30
step platform-failcode 1 --bin "$FW/f2_platform_test.bin" --mailbox 0x100 --timeout 30
step platform-reboot 0 --bin "$FW/f2_platform_test.bin" --mailbox 0x200 --timeout 30
# 5. Sparse test of all DDR4 + HBM from the core, latency, read rate.
step memtest-core 0 --bin "$FW/f2_memtest.bin" --timeout 600
# 6. Existing firmware and SDK examples (no --ignore-mem-err).
step smoke 0 --stdin --bin "$FW/fpga_smoke_test.bin" < "$FW/fpga_smoke_uart_in.txt"
step crypto 0 --bin "$FW/crypto_soc_test.bin"
step ed25519 0 --bin "$FW/ed25519_soc_test.bin"
step s_hello 0 --load 0x80000000="$P/linux/fw_jump.bin" --load 0x80200000="$P/linux/s_hello.bin" \
  --load 0x83000000="$(ls "$P"/linux/*.dtb | head -1)"
for e in "$P"/examples/*.bin; do
  step "ex-$(basename "$e" .bin)" 0 --bin "$e"
done
# 7. Console: raw terminal (pty), the smoke line typed, Ctrl-] detaches.
(sleep 3; cat "$FW/fpga_smoke_uart_in.txt"; sleep 3; printf '\035') |
  script -qfec "sudo $H --console --bin $FW/fpga_smoke_test.bin --log $OUT/console.uart" \
    "$OUT/console.typescript" > /dev/null 2> "$OUT/console.host"
echo "console                rc=$? (want 4: detached)  $(grep -c 'FPGA SMOKE PASS' "$OUT/console.uart") x FPGA SMOKE PASS" | tee -a "$R"
# 8. Bulk load / save of multi-GB images, DDR4 and HBM.
if [ ! -f /tmp/sigil-big.bin ]; then
  dd if=/dev/urandom of=/tmp/sigil-big.bin bs=1M count=4096 status=none
fi
sha256sum /tmp/sigil-big.bin | tee "$OUT/bulk.sha256"
cat /tmp/sigil-big.bin > /dev/null   # page cache: time the PCIe part
for t in 1 8; do
  step "bulk-t$t" 0 --threads "$t" --verify \
    --load 0x100000000=/tmp/sigil-big.bin --load 0x1100000000=/tmp/sigil-big.bin \
    --bin "$FW/hash_soc_test.bin" \
    --save 0x100000000=/tmp/sigil-ddr.out:4G --save 0x1100000000=/tmp/sigil-hbm.out:4G
  sha256sum /tmp/sigil-ddr.out /tmp/sigil-hbm.out | tee -a "$OUT/bulk.sha256"
done
# 9. Linux (the #55 payload: 128 MiB DT) -- #63: every console line intact.
if [ -f "$P/linux/Image" ]; then
  step linux 0 --linux --fw "$P/linux/fw_jump.bin" --image "$P/linux/Image" \
    --dtb "$(ls "$P"/linux/*.dtb | head -1)" --timeout 900 --exit LINUX_BOOT_OK
  gzip -f "$OUT/linux.uart"
fi
echo "done $(date -u)" | tee -a "$R"
