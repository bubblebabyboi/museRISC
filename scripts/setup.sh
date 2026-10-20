#!/usr/bin/env bash
# Sigil environment setup. Reports missing host tools, then fetches
# the pinned third-party sources (not committed) on request.
#   ./scripts/setup.sh             # report only
#   ./scripts/setup.sh --fetch     # clone all third_party/ sources
#   ./scripts/setup.sh --fetch-cva6
#   ./scripts/setup.sh --fetch-act # riscv-arch-test + matching Sail binary
set -euo pipefail
cd "$(dirname "$0")/.."

echo "== Host tools =="
for t in verilator python3 docker make git yosys mise; do
  if command -v "$t" >/dev/null; then echo "  ok       $t"; else
    echo "  MISSING  $t"; fi
done
if command -v riscv64-elf-gcc >/dev/null; then
  echo "  ok       riscv64-elf-gcc"
elif command -v riscv64-unknown-elf-gcc >/dev/null; then
  echo "  ok       riscv64-unknown-elf-gcc"
else
  echo "  MISSING  riscv64-elf-gcc or riscv64-unknown-elf-gcc"
fi
cat <<'EOF'
Install on macOS (Linux: use your distro equivalents):
  brew install verilator yosys riscv64-elf-gcc mise z3 gh
  # Ubuntu CI: apt-get install verilator yosys z3 \
  #   gcc-riscv64-unknown-elf curl git make python3

Pinned third-party sources (Phase 1, not needed for `make test`):
  cva6            81245a47fad8fe1a5d562d953ef2662e099def76
  ara             34bd3bc152421b4601a7bf3d6e8e91ffb545c99e
  riscv-arch-test 6af53584adc8b944fdc34c361988674870146d91
  sail-riscv      0.15 release (sail-riscv-Mac-arm64 on macOS)
Host build/test: ./scripts/cva6_docker.sh
ACT4 harness:    ./scripts/run_compliance.sh
EOF

fetch_cva6=0; fetch_ara=0; fetch_act=0
case "${1:-}" in
  --fetch) fetch_cva6=1; fetch_ara=1; fetch_act=1 ;;
  --fetch-cva6) fetch_cva6=1 ;;
  --fetch-act) fetch_act=1 ;;
  "") ;;
  *) echo "unknown option: $1 (use --fetch, --fetch-cva6, or --fetch-act)" >&2; exit 2 ;;
esac

if [ "$fetch_cva6" = 1 ] || [ "$fetch_ara" = 1 ] || [ "$fetch_act" = 1 ]; then
  clone_pin() { # dir url commit
    if [ ! -d "$1/.git" ]; then git clone "$2" "$1"; fi
    git -C "$1" checkout "$3"
    echo "pinned $1 @ $3"
  }
  mkdir -p third_party
  if [ "$fetch_cva6" = 1 ]; then
    clone_pin third_party/cva6 https://github.com/openhwgroup/cva6.git \
      81245a47fad8fe1a5d562d953ef2662e099def76
    git -C third_party/cva6 submodule update --init --recursive --jobs 4
  fi
  if [ "$fetch_ara" = 1 ]; then
    clone_pin third_party/ara https://github.com/pulp-platform/ara.git \
      34bd3bc152421b4601a7bf3d6e8e91ffb545c99e
  fi
  if [ "$fetch_act" = 1 ]; then
    clone_pin third_party/riscv-arch-test \
      https://github.com/riscv-non-isa/riscv-arch-test.git \
      6af53584adc8b944fdc34c361988674870146d91
    if [ ! -x third_party/sail/bin/sail_riscv_sim ]; then
      case "$(uname -s)-$(uname -m)" in
        Darwin-arm64) sail_asset=sail-riscv-Mac-arm64.tar.gz ;;
        Linux-x86_64) sail_asset=sail-riscv-Linux-x86_64.tar.gz ;;
        Linux-aarch64|Linux-arm64) sail_asset=sail-riscv-Linux-aarch64.tar.gz ;;
        *) echo "no prebuilt Sail 0.15 asset for $(uname -s)-$(uname -m)" >&2; exit 1 ;;
      esac
      mkdir -p third_party/sail
      curl -fsSL "https://github.com/riscv/sail-riscv/releases/download/0.15/$sail_asset" \
        | tar xz -C third_party/sail --strip-components=1
    fi
  fi
fi
echo "Baseline check: run 'make test && make lint'"
