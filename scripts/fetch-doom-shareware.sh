#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WAD="${ROOT}/cache/doom1.wad"
URL="https://raw.githubusercontent.com/Akbar30Bill/DOOM_wads/master/doom1.wad"
MD5="f0cefca49926d00903cf57551d901abe"
SIZE=4196020

md5_of() {
  if command -v md5 >/dev/null 2>&1; then md5 -q "$1"; else md5sum "$1" | awk '{print $1}'; fi
}

if [[ -f "$WAD" ]] && [[ "$(md5_of "$WAD")" == "$MD5" ]]; then
  echo "doom1.wad already present and verified."
  exit 0
fi

mkdir -p "${ROOT}/cache"
echo "Downloading Doom shareware IWAD..."
curl -L --fail -o "${WAD}.tmp" "$URL"

ACTUAL="$(md5_of "${WAD}.tmp")"
ACTUAL_SIZE="$(wc -c < "${WAD}.tmp" | tr -d ' ')"
if [[ "$ACTUAL" != "$MD5" || "$ACTUAL_SIZE" != "$SIZE" ]]; then
  rm -f "${WAD}.tmp"
  echo "Checksum mismatch (got ${ACTUAL}, ${ACTUAL_SIZE} bytes)." >&2
  exit 1
fi

mv "${WAD}.tmp" "$WAD"
echo "Verified Doom 1.9 shareware IWAD -> cache/doom1.wad"
