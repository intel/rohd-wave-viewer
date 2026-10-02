# WASM Webview Compatibility Patch

ROHD Wave Viewer patches the generated Wellen WebAssembly package so it can
initialize inside restricted VS Code Remote webviews, including Remote SSH,
Dev Containers, WSL, and Codespaces.

## Failure Mode

Without the patch, initialization can fail with:

```text
RangeError: WebAssembly.Table.grow(): failed to grow table by 4
```

The generated package has a `funcref` table and an `externref` table. The
affected wasm-bindgen output exports `__wbindgen_externrefs` from the wrong
table and attempts to grow the table during JavaScript initialization. Remote
webview sandboxes can reject that growth operation.

## Build Integration

The supported `make wasm`, `make web-release`, and `make extension` paths run
the compatibility steps automatically:

1. `scripts/patch_wasm_binary.sh` patches the generated binary.
2. `scripts/patch_wasm_js.sh` adds a guarded JavaScript fallback.
3. `scripts/fix_bootstrap.py` adjusts the generated Flutter bootstrap for the
   packaged webview.

Do not package raw wasm-pack output for the extension.

## Binary Patch

For affected legacy output, the binary patch uses wabt to convert the module
to text, makes two changes, and converts it back:

```wat
;; Reserve four slots used by the JavaScript fallback.
(table (;1;) 128 externref)
;; becomes
(table (;1;) 132 externref)

;; Export the externref table instead of the funcref table.
(export "__wbindgen_externrefs" (table 0))
;; becomes
(export "__wbindgen_externrefs" (table 1))
```

Newer generated modules can already export `table[1]` and can use a larger
initial table. The current pinned build, for example, reports an initial size
of 1024. The script recognizes the correct export and leaves that binary
unchanged instead of forcing the legacy 132-entry layout.

## JavaScript Patch

The generated loader normally grows the table unconditionally:

```javascript
const offset = table.grow(4);
```

The patch catches environments that reject the operation and uses the four
preallocated entries:

```javascript
let offset;
try {
  offset = table.grow(4);
} catch (error) {
  console.warn('Table.grow(4) failed, using fallback:', error.message);
  offset = table.length - 4;
}
```

## Required Tools

The binary patch needs `wasm2wat`, `wat2wasm`, and `wasm-objdump` from wabt.
Install the pinned repository toolchain rather than relying on an arbitrary
system version:

```bash
tool/gh_actions/install_wasm_tools.sh
```

The script also installs or verifies wasm-pack, wasm-bindgen-cli, Binaryen, and
wabt. If wabt is absent, the binary script warns and skips its optional step;
such an artifact has not received the complete Remote-webview compatibility
patch and should not be released.

## Verification

After `make wasm`, inspect the generated module:

```bash
wasm-objdump -x web/pkg/wellen_bridge_bg.wasm |
  grep -E 'table\[|externrefs'
```

The output must show `__wbindgen_externrefs` exported from `table[1]`. A
legacy module modified by the script has an initial size of 132; an
already-correct generated module can report another size, such as 1024.

Revalidate this patch in both local and Remote VS Code whenever upgrading
wasm-bindgen, Flutter Rust Bridge, or VS Code. Generated layouts can change,
and a future upstream release may make one or both patches unnecessary.

## Related Projects

- [wasm-bindgen](https://github.com/rustwasm/wasm-bindgen)
- [wabt](https://github.com/WebAssembly/wabt)
- [VS Code webviews](https://code.visualstudio.com/api/extension-guides/webview)
- [WebAssembly reference types](https://github.com/WebAssembly/reference-types)

---

Copyright (C) 2024-2026 Intel Corporation
SPDX-License-Identifier: BSD-3-Clause
