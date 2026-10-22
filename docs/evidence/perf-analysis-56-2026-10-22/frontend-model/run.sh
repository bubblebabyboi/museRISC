#!/bin/bash
# run.sh <elf> <out> [regions|all] [default|sky130]
cd ~/fe-trace
S=/home/ubuntu/opt/spike/bin/spike
ISA=rv64gcv_zba_zbb_zbc_zbs_zcb_zicond_zbkb_zbkx_zkne_zknd_zknh_zvl512b_zicntr_zihpm
fifo=$(mktemp -u /tmp/fefifo.XXXXXX); mkfifo $fifo
$S --isa=$ISA --log-commits "$1" 2>$fifo >"$2.uart" &
SP=$!
./fe "$1" "${3:-all}" "${4:-default}" < $fifo > "$2" 2>"$2.err"
kill $SP 2>/dev/null; wait $SP 2>/dev/null; rm -f $fifo
