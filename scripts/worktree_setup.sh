#!/usr/bin/env bash
# Prepare a git worktree to build without re-fetching dependencies.
# Run from inside the new worktree:
#   /path/to/main/checkout/scripts/worktree_setup.sh [main-checkout]
# The main checkout defaults to the one this worktree belongs to.
# deps/ and read-only third_party/ sources are symlinked to the main
# checkout. riscv-arch-test is the exception: the ACT flow writes ELFs
# into its work/ directory, so each worktree gets its own detached
# `git worktree` of the main checkout's clone (objects are shared,
# nothing is copied). Clean those up with
#   git -C <main>/third_party/riscv-arch-test worktree prune
set -euo pipefail
shopt -s nullglob

wt=$(git rev-parse --show-toplevel)
if [ "$(git rev-parse --path-format=absolute --git-dir)" = \
     "$(git rev-parse --path-format=absolute --git-common-dir)" ]; then
  echo "run this inside a worktree, not the main checkout" >&2
  exit 1
fi
if [ $# -ge 1 ]; then
  main=$1
else
  main=$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")
fi
main=$(cd "$main" && pwd -P)
[ -d "$main/deps" ] || { echo "$main/deps missing: run scripts/install_deps.sh in the main checkout first" >&2; exit 1; }

link() { # target linkname
  [ -e "$1" ] || { echo "missing link target: $1" >&2; exit 1; }
  if [ -L "$2" ] || [ ! -e "$2" ]; then ln -sfn "$1" "$2"; echo "linked  $2 -> $1"; else
    echo "kept    $2 (exists, not a symlink)"; fi
}

cd "$wt"
link "$main/deps" deps
mkdir -p third_party
for src in "$main"/third_party/*; do
  name=$(basename "$src")
  if [ "$name" = riscv-arch-test ]; then
    dst=$wt/third_party/riscv-arch-test
    if [ -d "$dst/.git" ]; then
      echo "warning: third_party/riscv-arch-test is an old standalone clone; delete it and re-run to get a git worktree" >&2
    elif [ ! -e "$dst/.git" ]; then
      git -C "$src" worktree prune   # drop stale registrations for reused paths
      git -C "$src" worktree add -q --detach "$dst" "$(git -C "$src" rev-parse HEAD)"
      echo "added   third_party/riscv-arch-test (git worktree of $src)"
    elif [ -z "$(git -C "$dst" status --porcelain --untracked-files=no)" ]; then
      git -C "$dst" -c advice.detachedHead=false checkout -q "$(git -C "$src" rev-parse HEAD)"
    fi
    if command -v mise >/dev/null; then mise_bin=mise; else mise_bin=$HOME/.local/bin/mise; fi
    if [ -x "$(command -v "$mise_bin")" ]; then
      (cd "$dst" && "$mise_bin" trust -q)
    else
      echo "warning: mise not found; run 'mise trust' in third_party/riscv-arch-test before ACT" >&2
    fi
  else
    link "$src" "third_party/$name"
  fi
done
echo "Done. In each shell: source deps/env.sh"
