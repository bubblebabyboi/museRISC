# AGENTS.md

Working rules for AI agents (and humans) on this repository. Project
background, ISA status and evidence live in `README.md`, `docs/CORE.md`
and `docs/evidence/`.

## Environment

- First-time setup in the main checkout: `./scripts/install_deps.sh --gcc15`
  (builds pinned Verilator into `deps/`, fetches SoftFloat and
  riscv-tests), plus `./scripts/setup.sh --fetch-act` for ACT/Sail.
- In every shell: `source deps/env.sh` (bash or zsh; puts `deps/`
  Verilator and the GCC 15+ RISC-V toolchain first on `PATH`, sets
  `RISCV_TESTS_DIR`). With `--gcc15` that toolchain also builds the
  core tests, unlike CI (Ubuntu's GCC 13); all gates pass with both.
- The `regression.yml` and `core-regression.yml` CI workflows
  `apt-get install verilator` on `ubuntu-24.04`, which gives 5.020
  (this changes if the runner image is bumped), not the pinned `deps/`
  build. 5.020 rejects some constructs 5.048 accepts (e.g.
  `%Error-IMPURE` on a variable-index write to a local inside a
  package function). Before opening a PR that touches RTL or
  testbenches, also lint and build with the CI version, e.g.
  `docker run --rm -v "$PWD":/w -w /w ubuntu:24.04 sh -c 'apt-get update -qq && apt-get install -y -qq verilator make && make lint'`;
  never install it system-wide.
- Baseline gates: `make test`, `make lint`, `make core-test`,
  `make riscv-tests`; ACT on the core via `scripts/build_act4_core.sh`
  then `sim/run_act_core.sh`.

## Long-running commands

Run anything that takes more than a minute or two (Verilator builds,
`make core-test`, riscv-tests, ACT, TestFloat, synthesis, OpenROAD) in
the background, logging to a file under `build/`, and keep working
while it runs. Report wall-clock time with results.

## Subagents work in git worktrees

- Every subagent that changes files works in its own git worktree on
  its own branch, never in the main checkout or another agent's
  worktree, so parallel work cannot collide.
- Branch from the current `main`; name the branch after the feature
  (e.g. `fpu-multicycle`).
- Do not copy or re-fetch dependencies into a worktree. Run
  `scripts/worktree_setup.sh` from inside the worktree: it symlinks
  `deps/` and the `third_party/` sources to the main checkout.
  `riscv-arch-test` is the one exception (the ACT flow writes into it),
  so it gets its own detached `git worktree` of the main checkout's
  clone, which shares git objects instead of copying them.
- Never write into symlinked `deps/` or `third_party/` from a worktree.
  `build/` is per-worktree. Flows that write into `third_party/` other
  than ACT (e.g. `scripts/build_testfloat.sh` and the CVA6 scripts,
  which write under `third_party/cva6/`) must run in the main checkout,
  one at a time.
