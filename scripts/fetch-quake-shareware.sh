#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ZIP="${ROOT}/cache/quake106.zip"
URL="${QUAKE106_URL:-https://ftp.gwdg.de/pub/misc/ftp.idsoftware.com/idstuff/quake/quake106.zip}"
SHA256="ec6c9d34b1ae0252ac0066045b6611a7919c2a0d78a3a66d9387a8f597553239"
SIZE=9094045

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

if [[ -f "$ZIP" ]] && [[ "$(sha256_of "$ZIP")" == "$SHA256" ]]; then
  echo "quake106.zip already present and verified."
  exit 0
fi

mkdir -p "${ROOT}/cache"
echo "Downloading Quake 1.06 shareware archive..."
curl -L --fail -o "${ZIP}.tmp" "$URL"

ACTUAL="$(sha256_of "${ZIP}.tmp")"
ACTUAL_SIZE="$(wc -c < "${ZIP}.tmp" | tr -d ' ')"
if [[ "$ACTUAL" != "$SHA256" || "$ACTUAL_SIZE" != "$SIZE" ]]; then
  rm -f "${ZIP}.tmp"
  echo "Checksum mismatch (got ${ACTUAL}, ${ACTUAL_SIZE} bytes)." >&2
  exit 1
fi

mv "${ZIP}.tmp" "$ZIP"
echo "Verified Quake 1.06 shareware archive -> cache/quake106.zip"
