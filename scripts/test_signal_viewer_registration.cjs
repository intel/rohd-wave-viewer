const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { test } = require('node:test');

test('registration snapshot cannot overwrite a newer availability notification', async () => {
  const source = fs.readFileSync(
    path.join(__dirname, '../vscode-extension/out/extension.js'), 'utf8',
  );
  const listeners = [];
  const messages = [];
  let finishRegistration;
  const registration = new Promise(resolve => { finishRegistration = resolve; });
  const disposable = { dispose() {} };
  const uri = {
    fsPath: '/tmp/design.fst',
    toString: () => 'file:///tmp/design.fst',
  };
  const sandbox = {
    nextViewerId: 1,
    path,
    fs: { readFileSync: () => '<body></body>' },
    output: { appendLine() {} },
    transformHtml: html => html,
    setTimeout: () => 1,
    clearTimeout() {},
    vscode: {
      Uri: { joinPath: () => uri },
      commands: {
        executeCommand: command => command === 'rohd.registerSignalViewer'
          ? registration : Promise.resolve(),
      },
      workspace: {
        createFileSystemWatcher: () => ({
          ...disposable, onDidChange() {}, onDidCreate() {}, onDidDelete() {},
        }),
      },
    },
  };
  vm.createContext(sandbox);
  vm.runInContext(
    source.slice(source.indexOf('class VcdCustomEditorProvider'),
      source.indexOf('function transformHtml')) +
      '\nthis.Provider = VcdCustomEditorProvider;',
    sandbox,
  );
  const provider = new sandbox.Provider({ extensionPath: '/extension', extensionUri: uri });
  await provider.resolveCustomEditor({ uri }, {
    webview: {
      postMessage: message => { messages.push(message); return Promise.resolve(true); },
      asWebviewUri: () => uri,
      onDidReceiveMessage: listener => { listeners.push(listener); return disposable; },
    },
    onDidChangeViewState() {},
    onDidDispose() {},
  });
  listeners[0]({ type: 'rohdReady', info: { wasm: true } });
  provider.updateSignalViewerAvailability({
    viewerId: 'rohd-wave-viewer:1',
    availableViewers: [{ viewerId: 'schematic:1' }],
  });
  finishRegistration([]);
  await new Promise(resolve => setImmediate(resolve));
  const updates = messages.filter(message => message.type === 'signalViewerAvailability');
  assert.equal(updates.length, 1);
  assert.equal(updates[0].canSendSignals, true);
});
