# ACT4 DUT configuration for the Sigil CVA6 host

Device under test: CVA6 `cv64a6_imafdc_sv39` at openhwgroup/cva6
`81245a47` running in `corev_apu` `ariane_testharness` under
Verilator (the same model as gates B1/B2.2/B2.3 in this repo).
Scalar only; no Ara vector unit is attached in this build.

## Provenance

Adapted from the upstream riscv-arch-test `6af53584` CVA6 configs:

- `sigil-cv64a6.yaml` (UDB) and `sail.json` derive from
  `config/cores/cva6/cv64a6_imafdcv_sv39/` (CVA6+Ara). Ara-specific
  values (vector extensions and parameters, PMP override to zero,
  mock-UART/control-register windows, misaligned-access behavior)
  are replaced with this DUT's values from the pinned config
  package and CSR RTL. Inherited citations reference the upstream
  Ara build; values relied on for the B2.4 `I,M` suites were
  spot-checked against the pinned sources here. Re-verify before
  claiming suites beyond `I,M`.
- `link.ld` derives from the same directory (16 MiB declared DRAM
  window at `0x8000_0000`, kept in sync with `sail.json`).
- `rvmodel_macros.h` derives from `config/cores/cva6/` (HTIF
  `tohost` halt, console store to `0x1000_0000`, which is
  `ariane_soc` UARTBase in this testharness); macros unchanged.

Extensions are declared as their suites are scheduled and
verified (Zcb/Zicond/Zkne/Zknd/Zknh in sweep slice 2; Svnapot
in the privileged slice after the hardware was observed
translating NAPOT PTEs — `SvnapotEn=1` for this target).
Privileged suites are enabled (`include_priv_tests: True`).
Zicntr is not declared because the `time` CSR has no read case
in `csr_regfile` and traps, even though `cycle`/`instret`
exist. Svinval/Svpbmt/Zicbo have no decode at this pin and
stay undeclared; Svade (not Svadu) is declared because the
walker never writes A/D back.

## Use

```sh
./scripts/build_act4_cva6.sh          # generate I,M ELFs (Sail-checked)
# ELFs land in third_party/riscv-arch-test/work/sigil-cv64a6/elfs/
# Run on the CVA6 model via scripts/cva6_docker.sh ACT mode (B2.4).
```

This directory is the canonical committed copy. The build script
syncs it into the uncommitted `third_party/riscv-arch-test` tree
at `config/cores/sigil-cv64a6/` on every run; edit files here,
never only in the synced copy.
