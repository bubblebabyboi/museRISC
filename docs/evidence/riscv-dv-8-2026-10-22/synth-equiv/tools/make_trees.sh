#!/usr/bin/env bash
# make_trees.sh <repo> <main-rev> <branch-rev> <dir>: the rtl trees the review
# compares: <dir>/main/rtl, <dir>/br/rtl (git archive), and the branch variants
# made by neutralize_core.py from the branch's sigil_core.sv (sigil_csr.sv and
# every other file stay the branch's):
#   neutral      the three intended hunks reverted (iota, nanbox, pmpwide)
#   ctl_iota     only the viota.m hunk kept
#   ctl_nanbox   only the .vf NaN-box hunk kept
#   ctl_pmpwide  only the pmp_wide_b_i / pmp_wide_c_i connections kept
set -euo pipefail
repo=$1; ra=$2; rb=$3; D=$4; here=$(cd "$(dirname "$0")" && pwd)
mkdir -p "$D/main" "$D/br"
git -C "$repo" archive "$ra" rtl | tar -x -C "$D/main"
git -C "$repo" archive "$rb" rtl | tar -x -C "$D/br"
for v in neutral:iota,nanbox,pmpwide ctl_iota:nanbox,pmpwide ctl_nanbox:iota,pmpwide ctl_pmpwide:iota,nanbox; do
  n=${v%%:*}; rm -rf "${D:?}/$n"; mkdir -p "$D/$n"; cp -R "$D/br/rtl" "$D/$n/rtl"
  echo "== $n (reverted: ${v#*:})"
  python3 "$here/neutralize_core.py" "$D/br/rtl/core/sigil_core.sv" "$D/$n/rtl/core/sigil_core.sv" "${v#*:}"
done
