#!/usr/bin/env bash
# Fetch the EEMBC CoreMark sources at the pinned commit into the
# git-ignored third_party/coremark (README.md). Called by the Makefile
# on first use; safe to re-run.
#
#   fetch_coremark.sh [dest]     (default: <repo>/third_party/coremark)
#
# Pinned: eembc/coremark b56889a7 (2025-05-01), the newest upstream
# commit whose benchmark files match upstream's own coremark.md5 (the
# next and last commit, 1f483d5, only fixes a comment typo in
# coremark.h, which makes upstream's `make check` fail). Every file the
# build uses is checked against the sha256 below; an existing tree that
# does not match is left alone and the script fails. An existing tree
# that matches is not written to (only a missing stamp is added).
set -euo pipefail

COMMIT=b56889a7bd9d5624fbeff2a73ba69878e6a9c146
URL=https://github.com/eembc/coremark.git
SUMS='ca00e4e010ece47d7f040cb92aa50a95345a00d3171b59d088f6b243be06ce7b  core_list_join.c
17884c93c5b94378eb0ff02b4df3725756cf2addb9b8cbcaa6200a4649ff5ca7  core_main.c
ecdff717b5a5c4907d221a606760e25499899cbf617582c05d40db71c91351e4  core_matrix.c
f4b84bb0a3452c45a4daa664ab502bfdccbd31cb57d93e9ac490c60937717a4e  core_state.c
a3fbfcb9bb943b638624b8ece01c5836dd56a96d7bcde2697b248d077447327f  core_util.c
29f7eb0f0bdf6002f6c7dccfa4f8f9f32c0b8f6709f6538c2b73221938a9c8f1  coremark.h
dad92861212f8f012e75974e23ea97f7a275a375e0d3bc1d3b216423ba6b6306  coremark.md5
9577b9c846f61fd69a0d8ac965998c6450c7d8969f71f0bb4a931b91aebad28a  LICENSE.md'

here=$(cd "$(dirname "$0")" && pwd -P)
dest=${1:-$here/../../../third_party/coremark}
mkdir -p "$(dirname "$dest")"
dest=$(cd "$(dirname "$dest")" && pwd -P)/$(basename "$dest")

sha256_check() { # dir: checks $SUMS in dir
  if command -v sha256sum >/dev/null 2>&1; then
    (cd "$1" && printf '%s\n' "$SUMS" | sha256sum -c --quiet -)
  else
    (cd "$1" && printf '%s\n' "$SUMS" | shasum -a 256 -c --quiet -)
  fi
}

if [ -d "$dest" ]; then
  if sha256_check "$dest" >/dev/null 2>&1; then
    # Write the stamp only if it is missing or stale: the tree may be
    # the main checkout's, symlinked into a worktree (AGENTS.md).
    if [ "$(cat "$dest/.sigil-fetched" 2>/dev/null)" != "$COMMIT" ]; then
      echo "$COMMIT" > "$dest/.sigil-fetched"
    fi
    echo "coremark: $dest verified (eembc/coremark $COMMIT)"
    exit 0
  fi
  echo "coremark: $dest exists but does not match the pinned sources;" >&2
  echo "coremark: remove it and re-run $0" >&2
  exit 1
fi

tmp=$(mktemp -d "$dest.tmp.XXXXXX")
chmod 755 "$tmp"
trap 'rm -rf "$tmp"' EXIT
git -C "$tmp" init -q
git -C "$tmp" remote add origin "$URL"
if ! git -C "$tmp" fetch -q --depth 1 origin "$COMMIT"; then
  git -C "$tmp" fetch -q origin
fi
git -C "$tmp" -c advice.detachedHead=false checkout -q "$COMMIT"
got=$(git -C "$tmp" rev-parse HEAD)
[ "$got" = "$COMMIT" ] || { echo "coremark: fetched $got, want $COMMIT" >&2; exit 1; }
sha256_check "$tmp"
# Upstream's own integrity check (`make check` in the CoreMark tree).
if command -v md5sum >/dev/null 2>&1; then
  (cd "$tmp" && md5sum -c --quiet coremark.md5)
fi
echo "$COMMIT" > "$tmp/.sigil-fetched"
mv "$tmp" "$dest"
trap - EXIT
echo "coremark: fetched eembc/coremark $COMMIT into $dest (sha256 verified)"
