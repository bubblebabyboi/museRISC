#!/usr/bin/env bash
# QEMU user-mode oracle smoke (issue #30).
#
# Builds sw/qemu/user_oracle.c as a static RISC-V Linux binary
# and runs it under qemu-riscv64 user mode in Docker. This is a
# fast expected-stdout oracle for small static payloads before
# running similar code on RTL; it does not validate the kernel,
# devices, privileges, or RTL timing.
set -euo pipefail
cd "$(dirname "$0")/.."

OUT_DIR=${SIGIL_QEMU_USER_OUT:-build/qemu}
mkdir -p "$OUT_DIR"

docker run --rm -v "$PWD:/work" -w /work ubuntu:24.04 \
  bash -euo pipefail -c '
    apt-get update -qq >/dev/null
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
      --no-install-recommends gcc-riscv64-linux-gnu \
      libc6-dev-riscv64-cross qemu-user >/dev/null
    riscv64-linux-gnu-gcc -static -O2 -march=rv64gc -mabi=lp64d \
      -o "'"$OUT_DIR"'/user_oracle" sw/qemu/user_oracle.c
    qemu-riscv64 "'"$OUT_DIR"'/user_oracle" \
      > "'"$OUT_DIR"'/user_oracle.out"
    cat "'"$OUT_DIR"'/user_oracle.out"
  '

if grep -aq '^SIGIL_QEMU_USER_OK ' "$OUT_DIR/user_oracle.out"; then
  echo "QEMU USER ORACLE PASS: $OUT_DIR/user_oracle.out"
else
  echo "FAIL: qemu-riscv64 user oracle did not print the OK marker" >&2
  cat "$OUT_DIR/user_oracle.out" >&2 || true
  exit 1
fi
