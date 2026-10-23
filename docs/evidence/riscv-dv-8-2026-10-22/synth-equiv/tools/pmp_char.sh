#!/usr/bin/env bash
# pmp_char.sh <main rtl> <branch rtl> <outdir>: SAT characterization of the
# branch's PMP change (properties in pmp_char.py). Each sigil_csr is
# preprocessed with +define+SYNTHESIS, the PMP functions are wrapped
# (verbatim), sv2v converts the wrapper, Yosys maps one property at a time to
# an AIG whose single output is the property's negation, and ABC `iprove`
# decides it for all inputs (the 16 pmpcfg/pmpaddr registers, address,
# access type, privilege, width): UNSATISFIABLE = property holds.
# Non-vacuity: diff_wide must be SATISFIABLE (Yosys `sat` prints a witness),
# and a mutant of the branch (TOR second-word upper bound `enc != a54o`
# dropped) must break the properties.
set -uo pipefail
A=$1; B=$2; O=$3; mkdir -p "$O/mut"; here=$(cd "$(dirname "$0")" && pwd)
for s in A B; do
  r=$A; [ $s = B ] && r=$B
  (cd "$r" && verilator -E -P +define+SYNTHESIS -Icore core/sigil_csr.sv) > "$O/csr_$s.sv" || exit 2
done
sed 's/ && (enc != a54o)//' "$O/csr_B.sv" > "$O/mut/csr_B.sv"
python3 "$here/pmp_char.py" "$O/csr_A.sv" "$O/csr_B.sv" "$O/pmp_char.sv" > /dev/null || exit 2
python3 "$here/pmp_char.py" "$O/csr_A.sv" "$O/mut/csr_B.sv" "$O/mut/pmp_char.sv" > /dev/null || exit 2
sv2v "$O/pmp_char.sv" > "$O/pmp_char.v" && sv2v "$O/mut/pmp_char.sv" > "$O/mut/pmp_char.v" || exit 2

decide() {  # decide <dir> <output port> -> SATISFIABLE / UNSATISFIABLE
  local d=$1 p=$2
  cat > "$d/top_$p.v" <<EOT
module top_$p (input [127:0] cfg_flat, input [1023:0] addr_flat, input [63:0] addr,
  input [1:0] acc, input [1:0] priv, input wide, input [7:0] one_cfg, input [63:0] one_pa,
  input [63:0] one_prev, output o);
  pmp_char u (.cfg_flat(cfg_flat), .addr_flat(addr_flat), .addr(addr), .acc(acc), .priv(priv),
    .wide(wide), .one_cfg(one_cfg), .one_pa(one_pa), .one_prev(one_prev), .$p(o));
endmodule
EOT
  (cd "$d" && yosys -p "read_verilog pmp_char.v top_$p.v; hierarchy -top top_$p; proc; flatten; opt -fast;
     setundef -undriven -zero; opt_clean -purge; techmap; opt -fast; aigmap; opt_clean; write_aiger $p.aig" \
     > $p.ylog 2>&1 && yosys-abc -c "read_aiger $p.aig; strash; print_stats; iprove" > $p.abc 2>&1) || { echo ERROR; return; }
  if grep -q 'UNSATISFIABLE' "$d/$p.abc"; then echo UNSATISFIABLE
  elif grep -q 'SATISFIABLE' "$d/$p.abc"; then echo SATISFIABLE; else echo UNDECIDED; fi
}
t0=$(date +%s)
for p in match narrow wide_nosplit wide_split; do
  r=$(decide "$O" bad_$p)
  [ "$r" = UNSATISFIABLE ] && v=PROVEN || v="NOT PROVEN ($r)"
  echo "ok_$p: $v  [ABC iprove on !ok_$p: $r; $(grep -m1 -oE 'and = *[0-9]+' "$O/bad_$p.abc" | tr -s ' ') AIG nodes]"
done
echo "diff_wide: $(decide "$O" diff_wide) (expected SATISFIABLE: some 8-byte access gets a different verdict)"
# Witness: entry 0 NA4 over PA 0x8000_1004..7 (pmpaddr0 0x2000_0401, cfg 0x10: no
# R/W/X, unlocked), entries 1-15 OFF, M-mode 8-byte read; Yosys sat finds the address.
(cd "$O" && yosys -p "read_verilog pmp_char.v; hierarchy -top pmp_char; proc; flatten; opt -fast;
   sat -set cfg_flat 128'h10 -set addr_flat 1024'h20000401 -set priv 3 -set acc 0 -set wide 1 -set diff_wide 1 -show addr -show n_old -show n_new" > witness.log 2>&1)
echo "    witness: $(grep -q 'SAT solving finished - model found' "$O/witness.log" && echo 'model found:' || echo 'NO MODEL')" \
     $(grep -E '^ +\\(addr|n_old|n_new) ' "$O/witness.log" | python3 -c 'import sys; print(" ".join(f"{l.split()[0][1:]}=0x{int(l.split()[-1], 2):x}" for l in sys.stdin))') \
     "(n_old: main's verdict, n_new: the branch's; 1 = allowed)"
for p in match wide_nosplit wide_split; do
  echo "mutant (TOR 'enc != a54o' dropped) !ok_$p: $(decide "$O/mut" bad_$p) (expected SATISFIABLE)"
done
echo "$(( $(date +%s)-t0 ))s ($(yosys -V | cut -d' ' -f1-2), yosys-abc, $(sv2v --version), $(verilator --version | cut -d' ' -f1-2))"
