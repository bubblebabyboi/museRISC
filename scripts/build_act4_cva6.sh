#!/usr/bin/env bash
# Generate ACT4 (riscv-arch-test) self-checking ELFs for the Sigil
# CVA6 DUT config in sw/act4-cva6/ (B2.4). Generation only: ELFs land
# in third_party/riscv-arch-test/work/sigil-cv64a6/elfs/ and are
# then run on the CVA6 Verilator model by the batch runner in
# scripts/cva6_docker.sh (ACT directory mode). The Sail reference
# model supplies expected results at generation time; each ELF is
# self-checking and reports pass/fail via the HTIF tohost halt.
set -euo pipefail
cd "$(dirname "$0")/.."
ACT=third_party/riscv-arch-test
[ -d "$ACT/framework" ] || { echo "fetch riscv-arch-test first: ./scripts/setup.sh --fetch-act"; exit 1; }
command -v mise >/dev/null || { echo "install mise (https://mise.jdx.dev)"; exit 1; }
[ -x third_party/sail/bin/sail_riscv_sim ] || { echo "install Sail 0.15 into third_party/sail"; exit 1; }
if command -v riscv64-unknown-elf-gcc >/dev/null; then
  toolchain_prefix=riscv64-unknown-elf-
elif command -v riscv64-elf-gcc >/dev/null; then
  toolchain_prefix=riscv64-elf-
else
  echo "install a RISC-V bare-metal GCC (riscv64-unknown-elf- or riscv64-elf-)" >&2; exit 1
fi

# ACT configs expect riscv64-unknown-elf-* names (same aliasing as
# scripts/run_compliance.sh).
mkdir -p build/riscv-alias/bin
for t in gcc g++ objdump objcopy nm ar as ld readelf size strip ranlib; do
  src="$(command -v "${toolchain_prefix}$t" || true)"
  if [ -n "$src" ]; then
    ln -sf "$src" "build/riscv-alias/bin/riscv64-unknown-elf-$t"
  fi
done
[ -x build/riscv-alias/bin/riscv64-unknown-elf-gcc ] || { echo "RISC-V GCC alias failed" >&2; exit 1; }
ln -sf "$PWD/third_party/sail/bin/sail_riscv_sim" build/riscv-alias/bin/sail_riscv_sim

if [ "$(uname -s)" = Darwin ] && [ -f /opt/homebrew/lib/libz3.dylib ]; then
  D="$HOME/.cache/udb/z3/z3-5.1.0/arm64"; mkdir -p "$D"
  for n in libz3.so libz3.so.4.8 libz3 z3 libz3.dylib; do
    # Shim files from a prior run may already exist read-only.
    [ -f "$D/$n" ] || cp /opt/homebrew/lib/libz3.dylib "$D/$n"
  done
fi

# Canonical config lives in sw/act4-cva6/ (committed); the framework
# discovers configs under config/, so sync a copy into the
# (uncommitted) third_party tree on every run.
DST="$ACT/config/cores/sigil-cv64a6"
mkdir -p "$DST"
cp sw/act4-cva6/sigil-cv64a6.yaml sw/act4-cva6/sail.json \
   sw/act4-cva6/link.ld sw/act4-cva6/rvmodel_macros.h \
   sw/act4-cva6/test_config.yaml sw/act4-cva6/run_cmd.txt "$DST/"
echo "Synced DUT config to $DST"

cd "$ACT"
mise trust >/dev/null 2>&1 || true
PATH="$PWD/../../build/riscv-alias/bin:$PATH" \
  mise exec -- make elfs \
  CONFIG_FILES=config/cores/sigil-cv64a6/test_config.yaml \
  EXTENSIONS="${EXTENSIONS:-I,M}" FAST=1
echo "ELFs: $ACT/work/sigil-cv64a6/elfs/"
cd - >/dev/null

# Stage flat copies (suffix stripped) where the Docker batch runner
# can see them through its /cva6 mount: third_party/cva6/act-elfs/.
# Run with: ELF_SUBDIR=act-elfs TEST_LISTS=act-im TESTS="..." \
#   RUN_NAME=act-<n> ./scripts/cva6_docker.sh regression
mkdir -p third_party/cva6/act-elfs
find "$ACT/work/sigil-cv64a6/elfs" -type f -name '*.elf' | sort | while read -r f; do
  b="$(basename "$f" .elf)"
  cp "$f" "third_party/cva6/act-elfs/$b"
done
echo "Staged: $(ls third_party/cva6/act-elfs | wc -l | tr -d ' ') ELFs in third_party/cva6/act-elfs/"
