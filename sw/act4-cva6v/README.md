# ACT4 DUT configuration for the Sigil CVA6+Ara host

Device under test: CVA6 `cv64a6_imafdcv_sv39` at pulp-platform/cva6
`99eac9a6` (the pin Bender checks out for Ara `34bd3bc1`) with the Ara
vector unit, built `config=2_lanes vlen=512` under Verilator 5.047
(`scripts/ara_docker.sh`). This is the vector counterpart of
`sw/act4-cva6/` (which targets the scalar `81245a47` pin in
`ariane_testharness`); scalar ACT evidence does not transfer between
the two pins.

## Provenance

Copied from the upstream riscv-arch-test `6af53584` configuration
`config/cores/cva6/cv64a6_imafdcv_sv39/`, which was written and probed
against exactly these Ara/CVA6 pins at VLEN 512:

- `sigil-cv64a6v.yaml` (UDB), `sail.json`, `link.ld`, and
  `rvmodel_macros.h` are byte-identical to upstream except the UDB
  `name:`/`description:` fields. Upstream probed at 4 lanes; this DUT
  is 2 lanes. Lane count is not architecturally visible at fixed VLEN
  (VLEN/ELEN/VLENB and all CSR values the config cites are
  lane-independent), so the probed values carry over.
- Upstream's DUT build (`.github/scripts/install-ara.sh`) is not stock
  Ara: it widens the testbench ELF loader window to the 16 MiB L2 and
  enables CVA6 `cfg.RVB`/`cfg.ZKN`, which `cv64a6_imafdcv_sv39`
  leaves off. `scripts/ara_docker.sh` applies both patches
  (idempotently) before every command, so the local model is the
  config this directory describes; re-verilate after pulling them.
- Termination is a store to the Ara control registers at
  `0xD000_0000`, not HTIF `tohost` (see `rvmodel_macros.h`); the
  testbench exits 0 on its cycle limit, so `run_actv.sh` decides
  pass/fail from the `RVCP-SUMMARY` console lines, as upstream
  `run-ara.sh` does.

## Use

```sh
./scripts/build_act4_cva6v.sh       # generate V ELFs (Sail-checked)
# ELFs staged flat into third_party/ara/act-elfs/
./scripts/ara_docker.sh /repo/sw/act4-cva6v/run_actv.sh 1 60  # chunk
```

This directory is the canonical committed copy. The build script
syncs it into the uncommitted `third_party/riscv-arch-test` tree at
`config/cores/sigil-cv64a6v/` on every run; edit files here, never
only in the synced copy.

Vector compliance is claimed only to the extent of stored green
evidence under `docs/evidence/`; this config existing is not a claim.
