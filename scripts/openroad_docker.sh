#!/usr/bin/env bash
# Run OpenROAD-flow-scripts (ORFS) in the official openroad/orfs
# image (amd64; emulated on Apple Silicon).
# Usage: [PLATFORM=nangate45] [DESIGN=sigil_crypto|sigil_soc] \
#          ./scripts/openroad_docker.sh [make-target]
# Results land in build/orfs-results/<PLATFORM>/<DESIGN_NAME>/base/
# (sigil_crypto_top for sigil_crypto, sigil_soc_top for the SoC).
set -euo pipefail
cd "$(dirname "$0")/.."
PLATFORM="${PLATFORM:-nangate45}"
DESIGN="${DESIGN:-sigil_crypto}"
TARGET="${1:-}"
command -v docker >/dev/null || { echo "docker not found"; exit 1; }
docker info >/dev/null 2>&1 || { echo "docker daemon not running"; exit 1; }
mkdir -p build/orfs-results build/orfs-logs build/orfs-reports build/orfs-objects

docker run --rm --platform linux/amd64 \
  -v "$PWD/flow/designs/$PLATFORM/$DESIGN:/OpenROAD-flow-scripts/flow/designs/$PLATFORM/$DESIGN" \
  -v "$PWD/rtl/crypto:/OpenROAD-flow-scripts/flow/designs/src/sigil_crypto" \
  -v "$PWD/rtl:/OpenROAD-flow-scripts/flow/designs/src/sigil_soc" \
  -v "$PWD/build/orfs-results:/OpenROAD-flow-scripts/flow/results" \
  -v "$PWD/build/orfs-logs:/OpenROAD-flow-scripts/flow/logs" \
  -v "$PWD/build/orfs-reports:/OpenROAD-flow-scripts/flow/reports" \
  -v "$PWD/build/orfs-objects:/OpenROAD-flow-scripts/flow/objects" \
  openroad/orfs:latest \
  bash -lc "source ./env.sh && cd flow && \
    make DESIGN_CONFIG=designs/$PLATFORM/$DESIGN/config.mk $TARGET"
echo "Results: build/orfs-results/$PLATFORM/ (per DESIGN_NAME in $DESIGN/config.mk)"
