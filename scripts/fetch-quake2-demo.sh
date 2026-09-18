#!/usr/bin/env bash
set -euo pipefail

# Official Quake II demo installer. The extracted pak is used at package time
# and must never be committed.

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EXE="${ROOT}/cache/q2-314-demo-x86.exe"
PAK="${ROOT}/cache/q2-demo-pak0.pak"
URL="${Q2_DEMO_URL:-https://deponie.yamagi.org/quake2/idstuff/q2-314-demo-x86.exe}"
FALLBACKS=(
  "$URL"
  "https://ftp.gwdg.de/pub/misc/ftp.idsoftware.com/idstuff/quake2/q2-314-demo-x86.exe"
  "http://ftpmirror.infania.net/pub/idsoftware/quake2/q2-314-demo-x86.exe"
  "https://ftp.idsoftware.com/idstuff/quake2/q2-314-demo-x86.exe"
  "http://ftp.idsoftware.com/idstuff/quake2/q2-314-demo-x86.exe"
)
EXE_SHA256="7ace5a43983f10d6bdc9d9b6e17a1032ba6223118d389bd170df89b945a04a1e"
EXE_SIZE=39015499
PAK_SHA256="cae257182f34d3913f3d663e1e7cf865d668feda6af393d4ecf3e9e408b48d09"
PAK_SIZE=49951322

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

if [[ -f "$PAK" ]] && [[ "$(sha256_of "$PAK")" == "$PAK_SHA256" ]]; then
  echo "q2 demo pak0.pak already present and verified."
  exit 0
fi

mkdir -p "${ROOT}/cache"
if [[ ! -f "$EXE" ]] || [[ "$(sha256_of "$EXE")" != "$EXE_SHA256" ]]; then
  ok=0
  for candidate in "${FALLBACKS[@]}"; do
    echo "Downloading Quake II demo installer from ${candidate}..."
    rm -f "${EXE}.tmp"
    set +e
    HTTP_CODE="$(curl -4 -L --retry 3 -A "classic-games-arcade/1.0" \
      -o "${EXE}.tmp" -w "%{http_code}" "$candidate")"
    CURL_RC=$?
    set -e
    if [[ "$CURL_RC" -eq 0 && -f "${EXE}.tmp" ]]; then
      ACTUAL="$(sha256_of "${EXE}.tmp")"
      ACTUAL_SIZE="$(wc -c < "${EXE}.tmp" | tr -d ' ')"
      echo "mirror ${candidate} http=${HTTP_CODE} bytes=${ACTUAL_SIZE} sha256=${ACTUAL}"
      if [[ "$ACTUAL" == "$EXE_SHA256" && "$ACTUAL_SIZE" == "$EXE_SIZE" ]]; then
        ok=1
        break
      fi
      echo "::warning::Checksum mismatch from ${candidate} (http ${HTTP_CODE}, ${ACTUAL}, ${ACTUAL_SIZE} bytes)." >&2
    else
      echo "::warning::Download failed from ${candidate} (curl rc ${CURL_RC}, http ${HTTP_CODE:-none})." >&2
    fi
    rm -f "${EXE}.tmp"
  done
  if [[ "$ok" != 1 ]]; then
    echo "::error::Failed to fetch a verified q2-314-demo-x86.exe from all mirrors." >&2
    exit 1
  fi
  mv "${EXE}.tmp" "$EXE"
fi

WORKDIR="$(mktemp -d)"
cleanup() { rm -rf "$WORKDIR"; }
trap cleanup EXIT

echo "Extracting demo pak0.pak..."
if command -v 7z >/dev/null 2>&1; then
  7z e -y -r -o"$WORKDIR" "$EXE" "pak0.pak" >/dev/null
elif command -v unzip >/dev/null 2>&1; then
  unzip -j -o "$EXE" "Install/Data/baseq2/pak0.pak" -d "$WORKDIR" || \
    unzip -j -o "$EXE" "*/pak0.pak" -d "$WORKDIR"
else
  echo "::error::Need 7z or unzip to extract the demo installer." >&2
  exit 1
fi

FOUND=""
while IFS= read -r candidate_pak; do
  if [[ "$(sha256_of "$candidate_pak")" == "$PAK_SHA256" ]]; then
    FOUND="$candidate_pak"
    break
  fi
done < <(find "$WORKDIR" -iname 'pak0.pak')

if [[ -z "$FOUND" ]]; then
  echo "::error::pak0.pak not found or failed integrity check in demo installer." >&2
  find "$WORKDIR" -type f -exec ls -l {} \; >&2 || true
  exit 1
fi

cp "$FOUND" "$PAK"
echo "Verified Quake II demo pak0.pak -> cache/q2-demo-pak0.pak"
