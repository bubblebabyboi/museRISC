#!/usr/bin/env bash
# One-shot project rename museRISC -> Sigil. Idempotent: re-run it after
# merging branches that still use the old names.
#
#   ./scripts/rename_to_sigil.sh        # rewrite the working tree (tracked files)
#   ./scripts/rename_to_sigil.sh check  # exit 1 if any old name remains
#
# Renames tracked paths (git mv) and rewrites identifiers in tracked text
# files. Not touched:
#   - raw evidence under docs/evidence/ (*.log, *.csv, ...): historical tool
#     output stays as it was recorded; docs/evidence/README.md is rewritten.
#   - links to the contributor fork CantelopePeel/museRISC (a different repo),
#     the README's "Formerly museRISC" note, and the quoted test-vector
#     message "museRISC" (frozen ECDSA signature over those exact bytes).
#   - binary files and this script.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
mode=${1:-apply}
self=scripts/rename_to_sigil.sh

# Paths whose content is rewritten: tracked text files, minus exclusions.
content_files() {
  git ls-files -z | while IFS= read -r -d '' f; do
    case $f in
      "$self") continue ;;
      docs/evidence/README.md) ;;
      docs/evidence/*) continue ;;
    esac
    [ -f "$f" ] && grep -Iq . "$f" 2>/dev/null && printf '%s\0' "$f"
  done
}

if [ "$mode" = check ]; then
  left=$(content_files | xargs -0 grep -nE 'muserisc|museRISC|MUSERISC|muse_|MUSE_|"MUSE"|4D55_?5345' \
           | grep -v -e 'CantelopePeel/museRISC' -e 'Formerly museRISC' -e '"museRISC"' || true)
  paths=$(git ls-files | grep -iE 'muserisc|muse_' || true)
  [ -z "$left$paths" ] && { echo "rename check: clean"; exit 0; }
  printf '%s\n' "$paths" "$left" | sed '/^$/d' | head -40
  exit 1
fi

# 1) Paths: deepest first so directory moves don't strand children.
rename_path() {
  sed -e 's/museRISC/sigil/g' -e 's/muserisc/sigil/g' -e 's/muse_/sigil_/g' <<<"$1"
}
{ git ls-files | grep -E 'muserisc|museRISC|muse_' || true; } | awk '{print length, $0}' | sort -rn | cut -d' ' -f2- |
while IFS= read -r f; do
  new=$(rename_path "$f")
  [ "$f" = "$new" ] && continue
  mkdir -p "$(dirname "$new")"
  git mv -k "$f" "$new"
done
# Directories left empty by the moves.
find . -path ./.git -prune -o -path ./third_party -prune -o -type d -empty -print |
  grep -E 'muserisc|muse_' | xargs -r rmdir 2>/dev/null || true

# 2) Content. Order matters: protect fork links, fix URLs, then identifiers.
content_files | xargs -0 perl -pi -e '
  s{CantelopePeel/museRISC}{\x00FORK\x00}g;
  s{Formerly museRISC}{\x00FORMER\x00}g;
  s{"museRISC"}{\x00MSG\x00}g;   # frozen ECDSA test-vector message bytes
  s{bubblebabyboi/museRISC}{bubblebabyboi/sigil}g;
  s{museRISC}{Sigil}g;
  s{MUSERISC}{SIGIL}g;
  s{muserisc}{sigil}g;
  s{MUSE_}{SIGIL_}g;
  s{muse_}{sigil_}g;
  s{"MUSE"}{"SIGL"}g;
  s{HostMuse}{HostSigil}g;
  s{64\x27h4D55_5345}{64\x27h5349_474C}g;
  s{0x4D555345}{0x5349474C}g;
  s{\x00FORK\x00}{CantelopePeel/museRISC}g;
  s{\x00FORMER\x00}{Formerly museRISC}g;
  s{\x00MSG\x00}{"museRISC"}g;
'
echo "renamed; run '$self check' to confirm"
