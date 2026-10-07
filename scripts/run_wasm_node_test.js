#!/usr/bin/env node
// Node harness to load web/pkg/wellen_bridge.js and its wasm and run simple tests
// Usage: node scripts/run_wasm_node_test.js

const fs = require('fs');
const path = require('path');
const vm = require('vm');

async function main() {
  const repoRoot = path.resolve(__dirname, '..');
  const pkgDir = path.join(repoRoot, 'web', 'pkg');
  const jsPath = path.join(pkgDir, 'wellen_bridge.js');
  const wasmPath = path.join(pkgDir, 'wellen_bridge_bg.wasm');

  if (!fs.existsSync(jsPath) || !fs.existsSync(wasmPath)) {
    console.error('web/pkg artifacts not found. Run rust/wellen_bridge/build_wasm.sh first.');
    process.exit(2);
  }

  // Provide a simple fetch implementation for the JS wrapper to fetch the wasm
  globalThis.fetch = async function(url, opts) {
    // Normalize url to file path when it points to pkg
    if (url.endsWith('wellen_bridge_bg.wasm') || url.includes('wellen_bridge_bg.wasm')) {
      const wasmBuf = await fs.promises.readFile(wasmPath);
      return {
        arrayBuffer: async () => wasmBuf.buffer.slice(wasmBuf.byteOffset, wasmBuf.byteOffset + wasmBuf.byteLength),
        ok: true,
        status: 200,
        headers: {
          get: () => 'application/wasm'
        }
      };
    }
    // Attempt to load relative file
    const maybe = path.join(repoRoot, url.replace(/^\//, ''));
    if (fs.existsSync(maybe)) {
      const buf = await fs.promises.readFile(maybe);
      return {
        arrayBuffer: async () => buf.buffer.slice(buf.byteOffset, buf.byteOffset + buf.byteLength),
        ok: true,
        status: 200,
        headers: { get: () => 'application/octet-stream' }
      };
    }
    throw new Error('fetch: not found ' + url);
  };

  // Provide a minimal console and globalThis for the VM
  const context = vm.createContext({
    console: console,
    globalThis: globalThis,
    window: globalThis,
    self: globalThis,
    TextDecoder: global.TextDecoder,
    TextEncoder: global.TextEncoder,
  });

  // Load the generated JS wrapper and evaluate in context
  const jsCode = await fs.promises.readFile(jsPath, 'utf8');
  vm.runInContext(jsCode, context, { filename: jsPath });

  if (typeof context.wasm_bindgen !== 'function') {
    console.error('wasm_bindgen not exposed by wrapper');
    process.exit(3);
  }

  // Initialize; wrapper expects either a path or fetch; we pass the URL path used by the wrapper
  const wasmUrl = './web/pkg/wellen_bridge_bg.wasm';
  try {
    await context.wasm_bindgen(wasmUrl);
  } catch (e) {
    console.error('wasm_bindgen init failed:', e);
    process.exit(4);
  }

  console.log('wasm initialized in Node context');

  // Now call some exported functions via the generated JS API
  if (!context.wellen_bridge) {
    console.error('wellen_bridge namespace not found on global object');
    process.exit(5);
  }

  // The generated FRB JS exports functions under the rust namespace or exposes bindgen wrappers.
  // The rohd_wellen wrapper expects functions like 'load_waveform_from_bytes' to be callable from Dart.
  // For our Node harness, call the exported function names directly if present.

  // We'll attempt to call the low-level exported function `frbgen_rohd_wellen_wire__crate__api__load_waveform_from_bytes` if exposed.
  var maybeLoadBytes = context.frbgen_rohd_wellen_wire__crate__api__load_waveform_from_bytes || null;
  if (!maybeLoadBytes) {
    if (context.rohd_wellen && context.rohd_wellen.wire__crate__api__load_waveform_from_bytes) {
      maybeLoadBytes = context.rohd_wellen.wire__crate__api__load_waveform_from_bytes;
    }
  }
  if (!maybeLoadBytes && context.load_waveform_from_bytes) maybeLoadBytes = context.load_waveform_from_bytes;

  if (!maybeLoadBytes) {
    console.warn('Could not find a direct JS binding for load_waveform_from_bytes; attempting to use high-level API');
  }

  // Read an example file and call the load function via wasm_bindgen-generated wrappers
  const examplePath = path.join(repoRoot, 'surfer', 'examples', 'vhdl3.vcd');
  const fileBuf = await fs.promises.readFile(examplePath);
  const bytes = new Uint8Array(fileBuf);

  // The wrapper likely exposes a function under the wasm-bindgen exports. If FRB generated a convenient binding, it might be under globalThis.
  // As fallback, we can call the raw exported function via the module's exports object if present.
  try {
    if (typeof context.wellen_bridge !== 'undefined' && typeof context.wellen_bridge.load_waveform_from_bytes === 'function') {
      await context.wellen_bridge.load_waveform_from_bytes(bytes, 'vhdl3.vcd');
      console.log('load_waveform_from_bytes succeeded via wellen_bridge.load_waveform_from_bytes');
    } else if (maybeLoadBytes) {
      // Some wrappers expect JS arrays; pass as Array.from
      await maybeLoadBytes(Array.from(bytes), 'vhdl3.vcd');
      console.log('load_waveform_from_bytes succeeded via low-level binding');
    } else {
      console.error('No suitable entrypoint to call load_waveform_from_bytes');
      process.exit(6);
    }
  } catch (e) {
    console.error('Calling load_waveform_from_bytes failed:', e);
    process.exit(7);
  }

  console.log('WASM-based load completed successfully');
}

main().catch((e) => {
  console.error('Unhandled error in harness', e);
  process.exit(1);
});
