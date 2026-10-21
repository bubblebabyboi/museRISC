#!/usr/bin/env bash
# Run Sigil CL tests in the aws-fpga HDK XSIM environment (issue #54).
#
#   fpga/scripts/sim_cl_sigil.sh <fw_dir> <test> [<test> ...]
#
# <fw_dir> holds the firmware images the tests load through PCIS:
#   hash_soc_test.bin fpga_smoke_test.bin crypto_soc_test.bin
#   ed25519_soc_test.bin       (make -C sim on the dev machine:
#                               build/soc-tests/*.bin)
#   fw_jump.bin sigil.dtb s_hello.bin   (scripts/build_opensbi.sh /
#                               make soc: build/linux/), test_sigil_hello only
# fpga_smoke_uart_in.txt is taken from sw/fpga-tests/.
# Tests: test_sigil_regs test_sigil_hash test_sigil_smoke
#        test_sigil_crypto test_sigil_ed25519 test_sigil_hello
# Logs: fpga/cl_sigil/verif/sim/xsim/<test>_sv_fast/<test>.log
set -euo pipefail
[ $# -ge 2 ] || { sed -n 2,16p "$0"; exit 2; }
FW_SRC="$(cd "$1" && pwd)"; shift
TESTS=("$@")
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
AWS_FPGA_REPO_DIR="${AWS_FPGA_REPO_DIR:-$HOME/src/project_data/aws-fpga}"
export CL_DIR="$REPO/fpga/cl_sigil"
mkdir -p "$CL_DIR/verif/fw"
cp -f "$FW_SRC"/* "$CL_DIR/verif/fw/" 2>/dev/null || true
cp -f "$REPO/sw/fpga-tests/fpga_smoke_uart_in.txt" "$CL_DIR/verif/fw/"
set +euo pipefail
cd "$AWS_FPGA_REPO_DIR"
set --  # hdk_setup.sh reads positional args
# shellcheck disable=SC1091
source hdk_setup.sh > /dev/null 2>&1
set -euo pipefail
[ -n "${HDK_COMMON_DIR:-}" ] || { echo "hdk_setup.sh failed" >&2; exit 1; }
cd "$CL_DIR/verif/scripts"
for t in "${TESTS[@]}"; do
  s=$(date +%s)
  make "$t" AXI_MEMORY_MODEL=1 > "$CL_DIR/verif/$t.make.log" 2>&1 || true
  log="$CL_DIR/verif/sim/xsim/${t}_sv_fast/$t.log"
  res=$(grep -h "TEST PASSED\|TEST FAILED" "$log" 2>/dev/null | tail -1 || true)
  echo "$t: ${res:-NO RESULT (see $CL_DIR/verif/$t.make.log)} wall=$(( $(date +%s) - s ))s"
done
