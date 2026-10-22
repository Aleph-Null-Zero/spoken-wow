#!/usr/bin/env bash
# Moves a checkout's untracked data from pipelines/zones and pipelines/books into
# pipelines/places and pipelines/readables, after the folders were renamed.
#
#   scripts/migrate-section-folders.sh [checkout]     default: this one
#
# Git moves the tracked files on checkout and leaves everything it ignores behind: the take
# archives (audio-history/, which can take days to pull back from the droplet), the transcode
# cache and the wiki and wago caches. Run it once in every checkout that has them. It merges
# into folders that already exist, never overwrites a file, and says what it left behind.
# node_modules is deleted rather than moved: `pnpm install` rebuilds it at the new path.
set -euo pipefail

root=$(cd "${1:-$(dirname "$0")/..}" && pwd)
left=0

# Moves every entry of $1 into $2, descending into folders both sides have.
merge() {
  local from="$1" to="$2" entry name
  mkdir -p "$to"
  for entry in "$from"/* "$from"/.[!.]*; do
    [[ -e "$entry" || -L "$entry" ]] || continue
    name=$(basename "$entry")
    if [[ ! -e "$to/$name" && ! -L "$to/$name" ]]; then
      mv "$entry" "$to/$name"
    elif [[ -d "$entry" && ! -L "$entry" && -d "$to/$name" ]]; then
      merge "$entry" "$to/$name"
    else
      echo "  left behind: ${entry#"$root"/} (${to#"$root"/}/$name already exists)" >&2
      left=$((left + 1))
    fi
  done
  rmdir "$from" 2>/dev/null || true
}

for pair in zones:places books:readables; do
  old="$root/pipelines/${pair%%:*}" new="$root/pipelines/${pair##*:}"
  if [[ ! -d "$old" ]]; then
    echo "==> pipelines/${pair%%:*}: nothing to move"
    continue
  fi
  if [[ ! -d "$new" ]]; then
    echo "pipelines/${pair##*:} does not exist: check out a branch with the renamed folders first" >&2
    exit 1
  fi
  if [[ -d "$old/node_modules" ]]; then
    echo "==> deleting pipelines/${pair%%:*}/node_modules"
    rm -rf "$old/node_modules"
  fi
  echo "==> pipelines/${pair%%:*} -> pipelines/${pair##*:} ($(du -sh "$old" | cut -f1))"
  merge "$old" "$new"
done

if (( left > 0 )); then
  echo "$left entries left behind; nothing was overwritten" >&2
  exit 1
fi
echo "==> done; run pnpm install"
