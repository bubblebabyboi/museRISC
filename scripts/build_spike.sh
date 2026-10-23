#!/usr/bin/env bash
# Build the pinned Spike (riscv-isa-sim) that the riscv-dv regression uses
# as its reference model (issue #8; docs/VERIFICATION.md).
#
#   scripts/build_spike.sh [PREFIX]     default $SPIKE_PREFIX or ~/opt/spike
#
# Installs PREFIX/bin/spike and records the commit in PREFIX/.spike-sha;
# does nothing when that file already names the pinned commit. Sources go
# to $SPIKE_SRC (default ~/.cache/sigil/riscv-isa-sim). Needs git, make, a
# C++17 compiler, dtc (device-tree-compiler) and Boost (libboost-regex-dev,
# libboost-system-dev on Ubuntu). JOBS= sets make's parallelism.
set -euo pipefail

SPIKE_URL=https://github.com/riscv-software-src/riscv-isa-sim.git
SPIKE_SHA=2c300cd90eb74bb79f3fcdd58596a6f8d842d01c   # master, 2026-10-21
PREFIX=${1:-${SPIKE_PREFIX:-$HOME/opt/spike}}
SRC=${SPIKE_SRC:-$HOME/.cache/sigil/riscv-isa-sim}
JOBS=${JOBS:-$(nproc 2>/dev/null || sysctl -n hw.ncpu)}

if [ -x "$PREFIX/bin/spike" ] && [ "$(cat "$PREFIX/.spike-sha" 2>/dev/null)" = "$SPIKE_SHA" ]; then
  echo "spike $SPIKE_SHA already installed in $PREFIX"
  exit 0
fi

if [ ! -d "$SRC/.git" ]; then
  mkdir -p "$(dirname "$SRC")"
  git clone -q "$SPIKE_URL" "$SRC"
fi
if ! git -C "$SRC" cat-file -e "$SPIKE_SHA^{commit}" 2>/dev/null; then
  git -C "$SRC" fetch -q origin
fi
git -C "$SRC" -c advice.detachedHead=false checkout -q "$SPIKE_SHA"
# Spike takes SoftFloat from its berkeley-softfloat-3 submodule.
git -C "$SRC" submodule update -q --init --recursive

rm -rf "$SRC/build"
mkdir -p "$SRC/build"
(
  cd "$SRC/build"
  ../configure --prefix="$PREFIX" > configure.log 2>&1 || { tail -20 configure.log; exit 1; }
  make -j"$JOBS" > make.log 2>&1 || { tail -40 make.log; exit 1; }
  make install > install.log 2>&1 || { tail -20 install.log; exit 1; }
)
echo "$SPIKE_SHA" > "$PREFIX/.spike-sha"
echo "spike $SPIKE_SHA installed in $PREFIX ($("$PREFIX/bin/spike" --help 2>&1 | head -1))"
