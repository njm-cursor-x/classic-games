#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST="${ROOT}/dist"
JOBS="$(nproc 2>/dev/null || echo 4)"

ensure_clone() {
  local dest="$1" url="$2"
  if [[ ! -d "$dest/.git" ]]; then
    git clone "$url" "$dest"
  fi
}

patch_qwasm2_skip_gl1() {
  local makefile="$1"
  # GL4ES is only required for the GL1/WebGL1 renderer. Arcade boots GLES3.
  python3 - "$makefile" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
text = p.read_text()
text = text.replace("release/ref_gl1.wasm ", "")
text = text.replace("all: config ref_soft ref_gl1 ref_gles3 game client",
                    "all: config ref_soft ref_gles3 game client")
p.write_text(text)
PY
}

echo "==> Assembling launcher"
rm -rf "$DIST"
mkdir -p "$DIST"
cp "$ROOT/apps/launcher/index.html" "$ROOT/apps/launcher/styles.css" "$DIST/"
touch "$DIST/.nojekyll"

echo "==> Toolchain"
command -v emcc
emcc -v
echo "==> Doom"
ensure_clone "$ROOT/third_party/web-doom" "https://github.com/njm-cursor-x/web-doom.git"
git -C "$ROOT/third_party/web-doom" submodule update --init --recursive
"$ROOT/scripts/fetch-doom-shareware.sh"
mkdir -p "$ROOT/third_party/web-doom/wad"
cp "$ROOT/cache/doom1.wad" "$ROOT/third_party/web-doom/wad/doom1.wad"
cp "$ROOT/games/doom/index.html" "$ROOT/games/doom/app.js" \
  "$ROOT/games/doom/styles.css" "$ROOT/games/doom/arcade-back.css" \
  "$ROOT/third_party/web-doom/web/"
( cd "$ROOT/third_party/web-doom" && ./scripts/build.sh )
mkdir -p "$DIST/doom"
cp -a "$ROOT/third_party/web-doom/dist/." "$DIST/doom/"
cp "$ROOT/games/doom/arcade-back.css" "$DIST/doom/"

echo "==> Quake"
ensure_clone "$ROOT/third_party/quake" "https://github.com/njm-cursor-x/quake.git"
git -C "$ROOT/third_party/quake" submodule update --init --recursive
"$ROOT/scripts/fetch-quake-shareware.sh"
mkdir -p "$ROOT/third_party/quake/data"
cp "$ROOT/cache/quake106.zip" "$ROOT/third_party/quake/data/quake106.zip"
cp "$ROOT/games/quake/index.html" "$ROOT/games/quake/app.js" \
  "$ROOT/games/quake/styles.css" "$ROOT/games/quake/arcade-back.css" \
  "$ROOT/third_party/quake/web/"
( cd "$ROOT/third_party/quake" && ./scripts/build.sh )
mkdir -p "$DIST/quake/vendor"
cp -a "$ROOT/third_party/quake/dist/." "$DIST/quake/"
cp "$ROOT/games/quake/arcade-back.css" "$DIST/quake/"

echo "==> Quake 2"
ensure_clone "$ROOT/third_party/qwasm2" "https://github.com/GMH-Code/Qwasm2.git"
"$ROOT/scripts/fetch-quake2-demo.sh"
cp "$ROOT/games/quake2/shell.html" "$ROOT/third_party/qwasm2/wasm/shell.html"
mkdir -p "$ROOT/third_party/qwasm2/wasm/baseq2"
cp "$ROOT/games/quake2/baseq2/config.cfg" "$ROOT/games/quake2/baseq2/wasm.cfg" \
  "$ROOT/third_party/qwasm2/wasm/baseq2/"
# Keep configs only in the preload; demo PAK is a sibling asset, not embedded.
patch_qwasm2_skip_gl1 "$ROOT/third_party/qwasm2/Makefile"
if ! command -v emcc >/dev/null 2>&1; then
  echo "emcc not found. Activate emsdk before building Quake 2." >&2
  exit 1
fi
( cd "$ROOT/third_party/qwasm2" && emmake make -j"$JOBS" config ref_soft ref_gles3 game && emmake make -j"$JOBS" client )
mkdir -p "$DIST/quake2/baseq2"
cp "$ROOT/third_party/qwasm2/release/index.js" \
  "$ROOT/third_party/qwasm2/release/index.wasm" \
  "$ROOT/third_party/qwasm2/release/index.html" \
  "$ROOT/third_party/qwasm2/release/index.data" \
  "$ROOT/third_party/qwasm2/release/game_baseq2.wasm" \
  "$ROOT/third_party/qwasm2/release/ref_soft.wasm" \
  "$ROOT/third_party/qwasm2/release/ref_gles3.wasm" \
  "$DIST/quake2/"
# index.data is the Emscripten preload of wasm/baseq2 configs, not the demo PAK.
cp "$ROOT/cache/q2-demo-pak0.pak" "$DIST/quake2/baseq2/pak0.pak"
cp "$ROOT/games/quake2/arcade-back.css" "$ROOT/games/quake2/LICENSE" "$DIST/quake2/"
cp "$ROOT/third_party/qwasm2/wasm/baseq2/config.cfg" \
  "$ROOT/third_party/qwasm2/wasm/baseq2/wasm.cfg" \
  "$DIST/quake2/baseq2/"

python3 - "$DIST" <<'PY'
from pathlib import Path
import sys
root = Path(sys.argv[1])
banned = []
for p in root.rglob("*"):
    if p.suffix.lower() in {".wad", ".pak", ".zip", ".exe"}:
        rel = p.relative_to(root).as_posix()
        allowed = {
            "doom/wad/doom1.wad",
            "quake/data/quake106.zip",
            "quake2/baseq2/pak0.pak",
        }
        if rel not in allowed:
            banned.append(rel)
if banned:
    raise SystemExit("Refusing to package unexpected game data:\n  " + "\n  ".join(banned))
print("[OK] dist ships only shareware/demo blobs")
PY

echo "Built. Serve with: python3 -m http.server --directory dist 8000"
