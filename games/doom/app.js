const CACHE_NAME = "web-doom-v1";
const WASM_URL = "doomgeneric.wasm";
const DATA_URL = "doomgeneric.data";

const splash = document.getElementById("splash");
const game = document.getElementById("game");
const canvas = document.getElementById("canvas");
const startBtn = document.getElementById("start");
const statusEl = document.getElementById("status");
const progressEl = document.getElementById("progress");
const fillEl = document.getElementById("fill");
const wadFile = document.getElementById("wad-file");
const wadName = document.getElementById("wad-name");

// A 60 MB speculative download is hostile on a metered connection.
const autoPrefetch = navigator.connection?.saveData !== true;

const tally = new Map();
const wadRequests = new Map();
let engineRequest = null;
let scriptRequest = null;
let droppedWad = null;
let readinessToken = 0;
let launched = false;

const mib = (bytes) => (bytes / 1024 / 1024).toFixed(1);

function setStatus(text) {
  statusEl.textContent = text;
}

function reportProgress() {
  let received = 0;
  let total = 0;
  let sized = true;

  for (const entry of tally.values()) {
    received += entry.received;
    total += entry.total;
    if (!entry.known) sized = false;
  }

  if (received === 0) return;
  progressEl.hidden = false;

  if (sized && total > 0) {
    fillEl.style.width = `${Math.min(100, Math.round((received / total) * 100))}%`;
    setStatus(`Downloading ${mib(received)} / ${mib(total)} MB`);
  } else {
    setStatus(`Downloading ${mib(received)} MB`);
  }
}

// Engine artifacts change on every build, so a returning player must not be
// left holding a stale wasm. IWADs are versioned upstream and survive rebuilds.
const ENGINE_ASSETS = [WASM_URL, DATA_URL];
const BUILD_KEY = "__build";

async function evictStaleEngine(cache) {
  const [current, stored] = await Promise.all([
    fetch("build.txt", { cache: "no-store" }).then((r) => (r.ok ? r.text() : "")),
    cache.match(BUILD_KEY).then((r) => r?.text() ?? ""),
  ]);
  if (current.trim() === stored.trim()) return;
  await Promise.all(ENGINE_ASSETS.map((name) => cache.delete(name)));
  await cache.put(BUILD_KEY, new Response(current.trim()));
}

let cacheRequest = null;
function openCache() {
  if (!cacheRequest) {
    // Cache Storage is absent on insecure origins; fall back to network-only.
    cacheRequest =
      typeof caches === "undefined"
        ? Promise.resolve(null)
        : caches
            .open(CACHE_NAME)
            .then(async (cache) => {
              await evictStaleEngine(cache).catch(() => {});
              return cache;
            })
            .catch(() => null);
  }
  return cacheRequest;
}

async function loadAsset(url) {
  // `known` distinguishes a real Content-Length from a running byte count, so a
  // server that omits the header shows MB downloaded instead of a fake 100%.
  const entry = { received: 0, total: 0, known: false };
  tally.set(url, entry);

  const cache = await openCache();
  const hit = await cache?.match(url);
  if (hit) {
    const buffer = await hit.arrayBuffer();
    entry.total = buffer.byteLength;
    entry.received = buffer.byteLength;
    entry.known = true;
    reportProgress();
    return buffer;
  }

  const response = await fetch(url);
  if (!response.ok) {
    throw new Error(`Could not load ${url} (HTTP ${response.status})`);
  }
  entry.total = Number(response.headers.get("content-length")) || 0;
  entry.known = entry.total > 0;

  const reader = response.body.getReader();
  const chunks = [];
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    chunks.push(value);
    entry.received += value.length;
    entry.total = Math.max(entry.total, entry.received);
    reportProgress();
  }

  const bytes = new Uint8Array(entry.received);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.length;
  }

  // Persisting is an optimisation, so a quota failure must not block the game.
  cache
    ?.put(url, new Response(bytes, { headers: { "content-length": String(bytes.length) } }))
    .catch(() => {});

  return bytes.buffer;
}

function loadEngineScript() {
  scriptRequest ??= new Promise((resolve, reject) => {
    const script = document.createElement("script");
    script.src = "doomgeneric.js";
    script.onload = resolve;
    script.onerror = () => reject(new Error("Failed to load doomgeneric.js"));
    document.body.appendChild(script);
  });
  return scriptRequest;
}

// The engine script only defines createDoom(); the wasm and the instrument
// package are fetched here so instantiation later is instant.
function requestEngine() {
  if (!engineRequest) {
    engineRequest = Promise.all([
      loadEngineScript(),
      loadAsset(WASM_URL),
      loadAsset(DATA_URL),
    ]).then(([, wasmBinary, packageData]) => ({ wasmBinary, packageData }));
    engineRequest.catch(() => {
      engineRequest = null;
    });
  }
  return engineRequest;
}

function requestWad(name) {
  let request = wadRequests.get(name);
  if (!request) {
    request = loadAsset(`wad/${name}`);
    request.catch(() => wadRequests.delete(name));
    wadRequests.set(name, request);
  }
  return request;
}

// The shareware episode is the only IWAD this deployment is allowed to serve;
// anything else has to come from the player's own copy via the file picker.
const BUNDLED_IWAD = "doom1.wad";

function pendingIwad() {
  return droppedWad ? droppedWad.buffer : requestWad(BUNDLED_IWAD);
}

function watchReadiness() {
  const token = ++readinessToken;
  Promise.all([requestEngine(), pendingIwad()])
    .then(() => {
      if (token !== readinessToken || launched) return;
      progressEl.hidden = false;
      fillEl.style.width = "100%";
      setStatus("Ready.");
    })
    .catch((err) => {
      if (token === readinessToken) setStatus(err.message);
    });
}

wadFile.addEventListener("change", () => {
  const file = wadFile.files?.[0];
  if (!file) {
    droppedWad = null;
    wadName.hidden = true;
    return;
  }
  // Record the selection synchronously and keep the read as a promise, so a
  // fast Start click cannot slip past it and fall back to the shareware IWAD.
  droppedWad = {
    name: file.name.replace(/[^A-Za-z0-9._-]/g, "_"),
    buffer: file.arrayBuffer(),
  };
  wadName.hidden = false;
  wadName.textContent = `Using ${file.name} (${mib(file.size)} MB)`;
  if (autoPrefetch) watchReadiness();
});

startBtn.addEventListener("click", async () => {
  if (launched) return;
  launched = true;
  startBtn.disabled = true;

  try {
    const iwadName = droppedWad?.name ?? BUNDLED_IWAD;
    const [{ wasmBinary, packageData }, iwadData] = await Promise.all([
      requestEngine(),
      pendingIwad(),
    ]);

    setStatus("Starting…");
    splash.hidden = true;
    game.hidden = false;

    const Module = await window.createDoom({
      canvas,
      // Module.wasmBinary is stripped from this build's incoming JS API, so
      // hand over the already-downloaded binary through instantiateWasm.
      instantiateWasm: (imports, onSuccess) => {
        WebAssembly.instantiate(wasmBinary, imports).then(
          (result) => onSuccess(result.instance),
          (err) => setStatus(`WebAssembly failed to start: ${err.message}`)
        );
      },
      getPreloadedPackage: () => packageData,
      locateFile: (path) => path,
      print: (text) => console.log(text),
      printErr: (text) => console.error(text),
    });

    Module.FS.writeFile(iwadName, new Uint8Array(iwadData));
    canvas.focus();
    canvas.addEventListener("click", () => {
      canvas.requestPointerLock?.();
    });
    Module.callMain(["doomgeneric", "-iwad", iwadName]);
  } catch (err) {
    console.error(err);
    launched = false;
    splash.hidden = false;
    game.hidden = true;
    startBtn.disabled = false;
    setStatus(err.message || String(err));
  }
});

if (autoPrefetch) {
  watchReadiness();
} else {
  setStatus("Data Saver is on — the download starts when you press Start.");
}
