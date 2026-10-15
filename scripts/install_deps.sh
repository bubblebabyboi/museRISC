#!/usr/bin/env bash
# Install the host tools museRISC needs (see scripts/setup.sh for the
# list and `make test` / `make lint` / `make core-test` for users).
#   ./scripts/install_deps.sh              # packages + Verilator + SoftFloat
#                                          # + riscv-tests sources
#   ./scripts/install_deps.sh --gcc15      # also the pinned GCC 15+ RISC-V
#                                          # toolchain ACT4 needs (Linux x86_64)
# Project-local tools are built into deps/ (git-ignored); load them with
#   source deps/env.sh
# Supports Ubuntu/Debian (apt) and macOS (Homebrew). Docker is not
# installed here; install it from https://docs.docker.com/engine/install/
# if you want `make openroad` or the CVA6 flows.
set -euo pipefail
SELF=$(cd "$(dirname "$0")" && pwd)/$(basename "$0")
cd "$(dirname "$0")/.."
ROOT=$PWD
case "$ROOT" in
  *[[:space:]]*) echo "repo path contains whitespace; the Verilator build cannot handle it: $ROOT" >&2; exit 1 ;;
esac
DEPS=$ROOT/deps

# Ubuntu's Verilator 5.020 internal-faults (docs/COMPLIANCE.md) and
# crashes `make core-test`. Ara pins a 5.047 devel snapshot; v5.048 is
# the first release containing it.
VERILATOR_TAG="v5.048"
# Same pin as .github/workflows/compliance.yml.
RISCV_TOOLCHAIN_TAG="2026.08.27"
# Same pins as .github/workflows/core-regression.yml.
SOFTFLOAT_COMMIT="a0c6494cdc11865811dec815d5c0049fba9d82a8"
RISCV_TESTS_COMMIT="eeacd5507db7a0f50ca8c4f27aff220fcbb60bdf"

want_gcc15=0
case "${1:-}" in
  --gcc15) want_gcc15=1 ;;
  "") ;;
  -h|--help) sed -n '2,11p' "$SELF"; exit 0 ;;
  *) echo "unknown option: $1 (use --gcc15)" >&2; exit 2 ;;
esac

sudo_cmd() { if [ "$(id -u)" = 0 ]; then "$@"; else sudo "$@"; fi; }
ncpu() { getconf _NPROCESSORS_ONLN 2>/dev/null || sysctl -n hw.ncpu; }

os=$(uname -s)
case "$os" in
  Linux)
    if ! command -v apt-get >/dev/null; then
      echo "only apt-based distros are supported; install the tools listed by ./scripts/setup.sh manually" >&2
      exit 1
    fi
    echo "== Installing apt packages =="
    sudo_cmd apt-get update
    # Second line: Verilator build dependencies.
    sudo_cmd apt-get install -y yosys z3 gcc-riscv64-unknown-elf \
      curl git make python3 xz-utils \
      autoconf g++ flex bison help2man perl libfl-dev zlib1g-dev
    ;;
  Darwin)
    if ! command -v brew >/dev/null; then
      echo "Homebrew is required: https://brew.sh" >&2
      exit 1
    fi
    echo "== Installing Homebrew packages =="
    # Homebrew's Verilator is current, so it is not built from source.
    brew install verilator yosys riscv64-elf-gcc mise z3
    ;;
  *)
    echo "unsupported OS: $os" >&2
    exit 1
    ;;
esac

mkdir -p "$DEPS/src"

if [ "$os" = Linux ]; then
  if [ -x "$DEPS/bin/verilator" ] &&
     "$DEPS/bin/verilator" --version | grep -q "^Verilator ${VERILATOR_TAG#v} "; then
    echo "== Verilator $VERILATOR_TAG already in deps/ =="
  else
    echo "== Building Verilator $VERILATOR_TAG into deps/ =="
    src=$DEPS/src/verilator
    [ -d "$src/.git" ] || git clone https://github.com/verilator/verilator.git "$src"
    git -C "$src" fetch --tags -q
    git -C "$src" -c advice.detachedHead=false checkout -q "$VERILATOR_TAG"
    (
      cd "$src"
      unset VERILATOR_ROOT
      autoconf
      ./configure --prefix="$DEPS"
      make -j"$(ncpu)"
      make install
    )
  fi
fi

if [ "$want_gcc15" = 1 ]; then
  if [ "$os-$(uname -m)" != "Linux-x86_64" ]; then
    echo "--gcc15: no prebuilt toolchain for $os-$(uname -m); Homebrew's riscv64-elf-gcc is already recent" >&2
    exit 1
  fi
  . /etc/os-release
  # Upstream only publishes Ubuntu 22.04 and 24.04 builds.
  case "${ID:-}-${VERSION_ID:-}" in
    ubuntu-22.04) tc_os=22.04 ;;
    ubuntu-24.04) tc_os=24.04 ;;
    *) tc_os=24.04
       echo "warning: no toolchain build for ${ID:-?} ${VERSION_ID:-?}; trying the Ubuntu 24.04 one" >&2 ;;
  esac
  asset="riscv64-elf-ubuntu-${tc_os}-gcc.tar.xz"
  if [ "$(cat "$DEPS/riscv-toolchain/.tag" 2>/dev/null)" = "$RISCV_TOOLCHAIN_TAG-$asset" ]; then
    echo "== GCC 15+ toolchain already in deps/ =="
  else
    echo "== Downloading RISC-V toolchain $RISCV_TOOLCHAIN_TAG ($asset) into deps/ =="
    # Extract into a temp dir and move into place, so an interrupted
    # run is not mistaken for a finished install.
    tmp=$(mktemp -d "$DEPS/.toolchain.XXXXXX")
    trap 'rm -rf "$tmp"' EXIT
    curl -fL "https://github.com/riscv-collab/riscv-gnu-toolchain/releases/download/${RISCV_TOOLCHAIN_TAG}/${asset}" -o "$tmp/tc.tar.xz"
    mkdir -p "$tmp/out"
    tar -xJf "$tmp/tc.tar.xz" -C "$tmp/out"
    rm -rf "$DEPS/riscv-toolchain"
    echo "$RISCV_TOOLCHAIN_TAG-$asset" > "$tmp/out/.tag"
    mv "$tmp/out" "$DEPS/riscv-toolchain"
  fi
fi

clone_pin() { # dir url commit
  [ -d "$1/.git" ] || git clone "$2" "$1"
  # Fetch only when the pin is not already present (pin bumps).
  git -C "$1" cat-file -e "$3^{commit}" 2>/dev/null || git -C "$1" fetch -q origin
  git -C "$1" -c advice.detachedHead=false checkout -q "$3"
}
mkdir -p third_party
# FPU TB oracle; sim/softfloat-host/ supplies its build config.
echo "== Fetching Berkeley SoftFloat ${SOFTFLOAT_COMMIT:0:8} =="
clone_pin third_party/berkeley-softfloat-3 \
  https://github.com/ucb-bar/berkeley-softfloat-3.git "$SOFTFLOAT_COMMIT"
# `make riscv-tests`: point sim/run_riscv_tests.sh here with
# RISCV_TESTS_DIR (deps/env.sh exports it).
echo "== Fetching riscv-tests ${RISCV_TESTS_COMMIT:0:8} =="
clone_pin third_party/riscv-tests \
  https://github.com/riscv-software-src/riscv-tests.git "$RISCV_TESTS_COMMIT"
git -C third_party/riscv-tests submodule update --init --recursive -q

if ! command -v mise >/dev/null && [ ! -x "$HOME/.local/bin/mise" ]; then
  echo "== Installing mise (ACT4 tool manager) =="
  curl -fsSL https://mise.run | sh
fi

cat > "$DEPS/env.sh" <<'EOF'
# Generated by scripts/install_deps.sh. Usage: source deps/env.sh
# Works when sourced from bash or zsh (not dash/sh).
if [ -n "${BASH_VERSION:-}" ]; then _muse_src=${BASH_SOURCE[0]}
elif [ -n "${ZSH_VERSION:-}" ]; then eval '_muse_src=${(%):-%x}'
else _muse_src=$0; fi
_muse_deps=$(cd "$(dirname "$_muse_src")" && pwd)
for _d in "$_muse_deps/riscv-toolchain/riscv/bin" "$_muse_deps/bin" "$HOME/.local/bin"; do
  case ":$PATH:" in *":$_d:"*) ;; *) [ -d "$_d" ] && PATH="$_d:$PATH" ;; esac
done
export PATH
export RISCV_TESTS_DIR="$(dirname "$_muse_deps")/third_party/riscv-tests"
unset VERILATOR_ROOT _d _muse_deps _muse_src
EOF

echo
echo "Load project tools with:  source deps/env.sh"
# shellcheck source=/dev/null
. "$DEPS/env.sh"
./scripts/setup.sh | awk '/== Host tools ==/{p=1} p{print} p && /riscv64/{p=0}'
echo "  verilator: $(verilator --version)"
