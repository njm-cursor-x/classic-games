# Quake 2 cabinet

Yamagi Quake II via [GMH-Code/Qwasm2](https://github.com/GMH-Code/Qwasm2). `shell.html` is the Emscripten shell (relative asset URLs, Arcade chip, Cursor palette). Compiled `index.js` / `index.wasm` / renderer side modules are produced at package time and published; only those binaries belong in git if vendored later — never `pak0.pak`. The official demo installer is fetched by `scripts/fetch-quake2-demo.sh`.
