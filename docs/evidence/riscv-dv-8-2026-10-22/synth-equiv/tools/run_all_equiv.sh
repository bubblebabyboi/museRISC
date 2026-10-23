#!/usr/bin/env bash
# run_all_equiv.sh <dir> [jobs]: every Yosys equivalence run of the review, for
# each synthesis define set of scripts/synth_view_diff.sh. <dir> holds the rtl
# trees main/ (9da0006), br/ (origin/8-riscv-dv) and the branch variants made by
# neutralize_core.py: neutral/ (all three intended hunks reverted), ctl_iota/,
# ctl_nanbox/, ctl_pmpwide/ (only that hunk kept). Per define set:
#   core_neutral  sigil_core main vs neutral     (expect: all proven)
#   core_full     sigil_core main vs branch      (unproven points listed)
#   ctl_<hunk>    sigil_core main vs one hunk    (unproven points listed)
#   csr_tie       sigil_csr main vs branch, branch pmp_wide_b/c_i tied 0
#   csr_free      sigil_csr main vs branch, pmp_wide_b/c_i free inputs
set -u
D=$1; J=${2:-4}; cd "$D" || exit 1
TIE="u_csr pmp_wide_b_i 1'b0;u_csr pmp_wide_c_i 1'b0"
jobs=()
for t in "SYNTHESIS" "SYNTHESIS SIGIL_SRAM_OREG" "SYNTHESIS SIGIL_SRAM_SKY130" \
         "SYNTHESIS SIGIL_SRAM_FAKERAM45" "SYNTHESIS SIGIL_VRF_OREG"; do
  tag=$(echo $t | tr ' ' '+')
  jobs+=("tools/equiv_core.sh '$t' $D/main/rtl $D/neutral/rtl eq/$tag/core_neutral > eq/$tag.core_neutral.txt 2>&1")
  jobs+=("KIDS_FROM=gate GOLD_TIE=\"$TIE\" tools/equiv_core.sh '$t' $D/main/rtl $D/br/rtl eq/$tag/core_full > eq/$tag.core_full.txt 2>&1")
  jobs+=("tools/equiv_core.sh '$t' $D/main/rtl $D/ctl_iota/rtl eq/$tag/ctl_iota > eq/$tag.ctl_iota.txt 2>&1")
  jobs+=("tools/equiv_core.sh '$t' $D/main/rtl $D/ctl_nanbox/rtl eq/$tag/ctl_nanbox > eq/$tag.ctl_nanbox.txt 2>&1")
  jobs+=("KIDS_FROM=gate GOLD_TIE=\"$TIE\" tools/equiv_core.sh '$t' $D/main/rtl $D/ctl_pmpwide/rtl eq/$tag/ctl_pmpwide > eq/$tag.ctl_pmpwide.txt 2>&1")
  jobs+=("tools/equiv_csr.sh '$t' $D/main/rtl $D/br/rtl eq/$tag/csr_tie tie > eq/$tag.csr_tie.txt 2>&1")
  jobs+=("tools/equiv_csr.sh '$t' $D/main/rtl $D/br/rtl eq/$tag/csr_free free > eq/$tag.csr_free.txt 2>&1")
done
mkdir -p eq/jobs
i=0; for j in "${jobs[@]}"; do i=$((i+1)); printf '%s\n' "cd $D" "$j" > eq/jobs/$(printf %02d $i).sh; done
ls eq/jobs/*.sh | xargs -P "$J" -n 1 bash
echo ALL_EQUIV_DONE
