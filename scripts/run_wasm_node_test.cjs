#!/usr/bin/env node
// CommonJS harness to load web/pkg/wellen_bridge.js and its wasm and run simple tests
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

  global.fetch = async function(url, opts) {
    if (url.indexOf('wellen_bridge_bg.wasm') !== -1) {
      const wasmBuf = await fs.promises.readFile(wasmPath);
      return {
          arrayBuffer: async () => Uint8Array.from(wasmBuf).buffer,
          ok: true,
          status: 200,
          headers: {
            get: function() { return 'application/wasm'; }
          }
        };
    }
    const maybe = path.join(repoRoot, url.replace(/^\//, ''));
    if (fs.existsSync(maybe)) {
      const buf = await fs.promises.readFile(maybe);
      return {
        arrayBuffer: async () => buf.buffer.slice(buf.byteOffset, buf.byteOffset + buf.byteLength),
        ok: true,
        status: 200,
        headers: { get: function() { return 'application/octet-stream'; } }
      };
    }
    throw new Error('fetch: not found ' + url);
  };

  const context = vm.createContext({
    console: console,
    globalThis: global,
    window: global,
    self: global,
    TextDecoder: global.TextDecoder,
    TextEncoder: global.TextEncoder,
  });

  // Make fetch available inside the vm context
  context.fetch = global.fetch;
  // Minimal Response/Request shims used by the generated glue
  class Resp {
    constructor(buf) {
      this._buf = buf;
      this.ok = true;
      this.status = 200;
      this.type = 'basic';
      this.headers = { get: () => 'application/wasm' };
    }
    async arrayBuffer() { return Uint8Array.from(this._buf).buffer; }
  }
  context.Response = Resp;
  context.Request = function(u) { return u; };

  const jsCode = await fs.promises.readFile(jsPath, 'utf8');
  // Run the generated wrapper and export its internal symbols onto the global
  // context so we can access wasm_bindgen and the low-level exports.
  const wrapper = '(function(){\n' + jsCode + '\n return { wasm_bindgen: typeof wasm_bindgen !== "undefined" ? wasm_bindgen : undefined, __exports: typeof __exports !== "undefined" ? __exports : undefined, __wbg_init: typeof __wbg_init !== "undefined" ? __wbg_init : undefined, initSync: typeof initSync !== "undefined" ? initSync : undefined };\n})()';

  const result = vm.runInContext(wrapper, context, { filename: jsPath });
  console.log('vm init result keys:', Object.keys(result).filter(k => result[k] !== undefined).join(', '));

  const wasm_bindgen_fn = result.wasm_bindgen;
  if (typeof wasm_bindgen_fn !== 'function') {
    console.error('wasm_bindgen not exposed by wrapper');
    process.exit(3);
  }

  // bind wasm_bindgen and exports into context for later calls
  context.wasm_bindgen = wasm_bindgen_fn;
  context.__exports = result.__exports;

  const wasmUrl = './web/pkg/wellen_bridge_bg.wasm';
  try {
    const wasmBuf = await fs.promises.readFile(wasmPath);
    const wasmArrayBuffer = Uint8Array.from(wasmBuf).buffer;
    if (typeof context.wasm_bindgen.initSync === 'function') {
      context.wasm_bindgen.initSync(wasmArrayBuffer);
    } else {
      await context.wasm_bindgen(wasmArrayBuffer);
    }
  } catch (e) {
    console.error('wasm_bindgen init failed:', e);
    process.exit(4);
  }

  console.log('wasm initialized in Node context');
  // After initialization, prefer functions exported on the wasm_bindgen wrapper
  var maybeLoadBytes = null;
  try {
    if (context.wasm_bindgen && typeof context.wasm_bindgen.wire__crate__api__load_waveform_from_bytes === 'function') {
      maybeLoadBytes = context.wasm_bindgen.wire__crate__api__load_waveform_from_bytes;
    }
  } catch (e) {
    // ignore
  }
  if (!maybeLoadBytes) {
    if (context.frbgen_rohd_wellen_wire__crate__api__load_waveform_from_bytes) {
      maybeLoadBytes = context.frbgen_rohd_wellen_wire__crate__api__load_waveform_from_bytes;
    }
  }
  if (!maybeLoadBytes && context.rohd_wellen && context.rohd_wellen.wire__crate__api__load_waveform_from_bytes) {
    maybeLoadBytes = context.rohd_wellen.wire__crate__api__load_waveform_from_bytes;
  }
  if (!maybeLoadBytes && context.load_waveform_from_bytes) maybeLoadBytes = context.load_waveform_from_bytes;

  const envFile = process.env.TEST_FILE;
  const examplePath = envFile ? path.resolve(envFile) : path.join(repoRoot, 'surfer', 'examples', 'vhdl3.vcd');
  const fileBuf = await fs.promises.readFile(examplePath);
  const bytes = new Uint8Array(fileBuf);

  try {
    if (typeof context.wellen_bridge !== 'undefined' && typeof context.wellen_bridge.load_waveform_from_bytes === 'function') {
      await context.wellen_bridge.load_waveform_from_bytes(bytes, 'vhdl3.vcd');
      console.log('load_waveform_from_bytes succeeded via wellen_bridge.load_waveform_from_bytes');
    } else if (maybeLoadBytes) {
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
