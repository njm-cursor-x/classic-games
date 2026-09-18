# Classic games arcade

Static kiosk: Doom shareware, Quake shareware, and the official Quake II demo.
**Powered by Cursor / SpaceXAI.** Not affiliated with id Software.

## Play

GitHub Pages (after the first `main` deploy):
`https://njm-cursor-x.github.io/classic-games/`

Each cabinet is its own page (`/doom/`, `/quake/`, `/quake2/`) so pointer lock works. The Arcade chip returns to the splash.

## Build

Needs `emcc` (emsdk 3.1.64), Node, cmake, curl, unzip/7z, and fluidsynth (Doom music).

```bash
./scripts/build.sh
python3 -m http.server --directory dist 8000
```

Shareware/demo archives are fetched at build time into `cache/` and copied into `dist/`. They are **not** committed (no WAD/PAK/ZIP/EXE in git). Compiled `.js`/`.wasm` for Quake 2 is produced in CI; Doom and Quake reuse the existing Emscripten ports.

## Engines

| Game | Port | License |
|------|------|---------|
| Doom | [njm-cursor-x/web-doom](https://github.com/njm-cursor-x/web-doom) (doomgeneric) | GPL-2.0 |
| Quake | [njm-cursor-x/quake](https://github.com/njm-cursor-x/quake) (Qwasm) | GPL-2.0 |
| Quake 2 | [GMH-Code/Qwasm2](https://github.com/GMH-Code/Qwasm2) (Yamagi Quake II) | GPL-2.0 |

Game data remains © id Software and is only the redistributable shareware/demo sets.
