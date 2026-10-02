// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// extension.ts
// VS Code custom editor integration for the ROHD Wave Viewer.
//
// 2026 August
// Author: Desmond Kirkpatrick <desmond.a.kirkpatrick@intel.com>

import * as vscode from 'vscode';
import * as path from 'path';
import * as fs from 'fs';

type ModuleInfoHelper = {
  buildModuleInfo: (
    documentUri: vscode.Uri,
    moduleName: string | null,
    instancePath?: string[],
    output?: vscode.OutputChannel,
  ) => Promise<Record<string, unknown>>;
  resolveFlcPath: (
    documentUri: vscode.Uri,
    output?: vscode.OutputChannel,
  ) => Promise<string | null>;
  lookupSignalFrames: (
    flcPath: string,
    moduleName: string | null,
    signalName: string,
    format?: string,
    output?: vscode.OutputChannel,
  ) => Promise<SourceFrame[]>;
};

type SourceFrame = {
  file: string;
  line: number;
  col: number;
  desc: string;
  type: string;
};

// Generated beside extension.js from rohd_devtools_widgets extension assets.
const moduleInfoHelper =
  require('./shared/module_info_helper') as ModuleInfoHelper;
const { buildModuleInfo, resolveFlcPath, lookupSignalFrames } = moduleInfoHelper;

const output = vscode.window.createOutputChannel('ROHD Wave Viewer');
let nextViewerId = 1;

export function activate(context: vscode.ExtensionContext) {
  output.appendLine('ROHD Wave Viewer: activating extension');
  const disposable = vscode.commands.registerCommand('rohd-wave-viewer.open', () => {
    output.appendLine('ROHD Wave Viewer: open command invoked');
    openStandalone(context);
  });
  context.subscriptions.push(disposable);

  // Register custom editor for .vcd files
  const provider = new VcdCustomEditorProvider(context);
  context.subscriptions.push(
    vscode.commands.registerCommand(
      'rohd-wave-viewer.receiveSignals',
      payload => provider.receiveSignals(payload),
    ),
    vscode.commands.registerCommand(
      'rohd-wave-viewer.signalViewerAvailability',
      payload => provider.updateSignalViewerAvailability(payload),
    ),
  );
  context.subscriptions.push(vscode.window.registerCustomEditorProvider('rohdWaveViewer.vcd', provider, {
    supportsMultipleEditorsPerDocument: false,
    webviewOptions: {
      retainContextWhenHidden: true  // Keep WebView alive when hidden to prevent rendering issues
    }
  }));

  // Register arrow-key (and other shortcut) commands that VS Code would
  // otherwise swallow before they reach the webview.  Each command posts a
  // lightweight message to the active webview; the embed shim dispatches a
  // synthetic KeyboardEvent that Flutter's KeyboardListener can pick up.
  const keyCommands: { command: string; key: string; shiftKey?: boolean }[] = [
    { command: 'rohd-wave-viewer.arrowLeft',     key: 'ArrowLeft' },
    { command: 'rohd-wave-viewer.arrowRight',    key: 'ArrowRight' },
    { command: 'rohd-wave-viewer.arrowUp',       key: 'ArrowUp' },
    { command: 'rohd-wave-viewer.arrowDown',     key: 'ArrowDown' },
    { command: 'rohd-wave-viewer.shiftArrowUp',  key: 'ArrowUp',  shiftKey: true },
    { command: 'rohd-wave-viewer.shiftArrowDown',key: 'ArrowDown',shiftKey: true },
    { command: 'rohd-wave-viewer.delete',        key: 'Delete' },
  ];
  for (const kc of keyCommands) {
    context.subscriptions.push(
      vscode.commands.registerCommand(kc.command, () => {
        provider.postKeyToActiveWebview(kc.key, kc.shiftKey ?? false);
      })
    );
  }
}

function openStandalone(context: vscode.ExtensionContext) {
  output.appendLine('ROHD Wave Viewer: opening standalone webview');
  const panel = vscode.window.createWebviewPanel(
    'rohdWaveViewer',
    'ROHD Wave Viewer',
    vscode.ViewColumn.One,
    {
      enableScripts: true,
      localResourceRoots: [vscode.Uri.joinPath(context.extensionUri, 'flutter_web')],
      retainContextWhenHidden: true  // Keep WebView alive when hidden to prevent rendering issues
    }
  );

  const mediaPath = path.join(context.extensionPath, 'flutter_web');
  const indexPath = path.join(mediaPath, 'index.html');
  let html = '<h1>Missing build</h1>';
  try {
    html = fs.readFileSync(indexPath, { encoding: 'utf8' });
  } catch (e) {
    panel.webview.html = html;
    return;
  }

  const transformed = transformHtml(html, panel.webview, context);
  panel.webview.html = transformed;

  panel.webview.onDidReceiveMessage(msg => {
    output.appendLine(`webview -> extension message: ${JSON.stringify(msg)}`);
    if (msg && msg.command === 'ping') {
      panel.webview.postMessage({ reply: 'pong' });
    }
    // Handle repaint request - echo back to webview to force compositor update
    if (msg && msg.type === 'requestRepaint') {
      panel.webview.postMessage({ type: 'repaintAck', timestamp: Date.now() });
    }
  });
}

class VcdCustomEditorProvider implements vscode.CustomReadonlyEditorProvider {
  private readonly context: vscode.ExtensionContext;
  private activeWebview: vscode.Webview | undefined;
  private readonly webviews = new Map<string, vscode.Webview>();
  constructor(context: vscode.ExtensionContext) { this.context = context; }

  /** Post a synthetic key event to the currently active webview. */
  postKeyToActiveWebview(key: string, shiftKey: boolean) {
    if (this.activeWebview) {
      this.activeWebview.postMessage({ type: 'keyEvent', key, shiftKey });
    }
  }

  receiveSignals(payload: any) {
    const targetViewerId = payload?.targetViewerId as string | undefined;
    const signalPaths = Array.isArray(payload?.signalPaths)
      ? payload.signalPaths.filter((signalPath: unknown): signalPath is string => typeof signalPath === 'string')
      : [];
    if (!targetViewerId || signalPaths.length === 0) {
      return;
    }
    this.webviews.get(targetViewerId)?.postMessage({
      type: 'incomingSignals',
      sourceViewerId: payload?.sourceViewerId,
      signalPaths,
    });
  }

  updateSignalViewerAvailability(payload: any) {
    const viewerId = payload?.viewerId as string | undefined;
    if (!viewerId) {
      return;
    }
    const availableViewers = Array.isArray(payload?.availableViewers)
      ? payload.availableViewers
      : [];
    this.webviews.get(viewerId)?.postMessage({
      type: 'signalViewerAvailability',
      viewerId,
      canSendSignals: availableViewers.length > 0,
      availableViewers,
    });
  }

  public async openCustomDocument(
    uri: vscode.Uri,
    _openContext: vscode.CustomDocumentOpenContext,
    _token: vscode.CancellationToken
  ): Promise<vscode.CustomDocument> {
    return { uri, dispose: () => {} };
  }

  public async resolveCustomEditor(document: vscode.CustomDocument, webviewPanel: vscode.WebviewPanel, _token: vscode.CancellationToken): Promise<void> {
    // Allow the webview to load extension media and the document's folder so it can fetch the file URI directly.
    const docUri = document.uri as vscode.Uri;
    const docFolder = vscode.Uri.joinPath(docUri, '..');
    const webview = webviewPanel.webview;
    let disposed = false;
    webview.options = { enableScripts: true, localResourceRoots: [vscode.Uri.joinPath(this.context.extensionUri, 'flutter_web'), docFolder] };

    const indexPath = path.join(this.context.extensionPath, 'flutter_web', 'index.html');
    let html = '<h1>Missing build</h1>';
    try { html = fs.readFileSync(indexPath, { encoding: 'utf8' }); } catch (e) { webview.html = html; return; }

    webview.html = transformHtml(html, webview, this.context);

    // Track which webview is active so key commands reach the right panel.
    const viewerId = `rohd-wave-viewer:${nextViewerId++}`;
    this.webviews.set(viewerId, webview);
    this.activeWebview = webview;
    webviewPanel.onDidChangeViewState(() => {
      if (webviewPanel.active) { this.activeWebview = webview; }
    });
    webviewPanel.onDidDispose(() => {
      disposed = true;
      if (this.activeWebview === webview) { this.activeWebview = undefined; }
      this.webviews.delete(viewerId);
      vscode.commands.executeCommand('rohd.unregisterSignalViewer', { viewerId }).then(
        undefined,
        err => output.appendLine(`[SignalViewers] unregister failed: ${err}`),
      );
    });

    const registerSignalViewer = async () => {
      try {
        const availableViewers = await vscode.commands.executeCommand<any[]>(
          'rohd.registerSignalViewer',
          {
            viewerId,
            label: `Wave Viewer: ${path.basename(docUri.fsPath)}`,
            receiveCommand: 'rohd-wave-viewer.receiveSignals',
            availabilityCommand: 'rohd-wave-viewer.signalViewerAvailability',
          },
        );
        if (disposed) {
          await vscode.commands.executeCommand('rohd.unregisterSignalViewer', { viewerId });
          return;
        }
        webview.postMessage({
          type: 'signalViewerAvailability',
          viewerId,
          canSendSignals: Array.isArray(availableViewers) && availableViewers.length > 0,
          availableViewers: Array.isArray(availableViewers) ? availableViewers : [],
        });
      } catch (e) {
        output.appendLine(`[SignalViewers] register failed: ${e}`);
        if (disposed) {
          return;
        }
        webview.postMessage({
          type: 'signalViewerAvailability',
          viewerId,
          canSendSignals: false,
          availableViewers: [],
        });
      }
    };

    // Send a lightweight vcdUri message — the Dart side will HTTP-fetch
    // the file via the webview URI (like Surfer).  This avoids reading the
    // entire file into the extension host and serialising it through
    // postMessage, which fails for files >200 MB.
    // Guard: ensure we only send the initial payload once.  The immediate send
    // (bottom of resolveCustomEditor) is essential so VS Code queues the message
    // for delivery once the webview JS context is ready.  The rohdReady handler
    // and the 2-second timeout are kept as fallbacks but gated by this flag.
    let contentsSent = false;
    const sendContents = async () => {
      const vcdUri = webviewPanel.webview.asWebviewUri(docUri);
      const fileName = path.basename(docUri.fsPath);
      output.appendLine(`Posting vcdUri to webview for ${docUri.toString()} → ${vcdUri.toString()}`);
      webviewPanel.webview.postMessage({ type: 'vcdUri', uri: vcdUri.toString(), originalUri: docUri.toString(), fileName });
    };

    const sendContentsOnce = async () => {
      if (contentsSent) {
        output.appendLine('sendContentsOnce: already sent, skipping');
        return;
      }
      contentsSent = true;
      await sendContents();
    };

    // Wait for the embedded app to post a 'rohdReady' message, or fallback after timeout.
    let readyReceived = false;
    const readyListener = webviewPanel.webview.onDidReceiveMessage((msg) => {
      if (msg && msg.type === 'rohdReady') {
        output.appendLine('Received rohdReady from webview');
        readyReceived = true;
        registerSignalViewer();
        const wasmOk = msg.info && msg.info.wasm === true;
        if (!wasmOk) {
          output.appendLine('Webview reported WASM initialization FAILED; not sending VCD bytes.');
        } else {
          // Fallback: resend if initial send somehow didn't arrive
          sendContentsOnce();
        }
      }
      if (msg && msg.type === 'console') {
        const line = `[webview:${msg.level}] ${Array.isArray(msg.args) ? msg.args.join(' ') : String(msg.args)}`;
        try { output.appendLine(line); } catch (e) { console.log(line); }
      }
    });

    const readyTimeout = setTimeout(() => {
      if (!readyReceived) {
        output.appendLine('rohdReady not received after 2s; sending vcdUri as fallback');
        sendContentsOnce();
      }
    }, 2000);

    // Basic file watcher: re-send contents when file changes
    const fsWatcher = vscode.workspace.createFileSystemWatcher(docUri.fsPath);
    const onChange = () => sendContents();  // file-change reloads always re-send
    fsWatcher.onDidChange(onChange);
    fsWatcher.onDidCreate(onChange);
    fsWatcher.onDidDelete(onChange);
    webviewPanel.onDidDispose(() => { fsWatcher.dispose(); readyListener.dispose(); clearTimeout(readyTimeout); });

    // Forward messages from webview to host (optional save handling)
    webviewPanel.webview.onDidReceiveMessage(async (msg) => {
      output.appendLine(`[customEditor] Received message: ${msg?.type} keys=${Object.keys(msg || {}).join(',')}`);

      // ── Ping — extension handshake ──
      if (msg && msg.type === 'ping') {
        const requestId = msg.requestId as string | undefined;
        webviewPanel.webview.postMessage({
          type: 'pingResponse',
          ...(requestId && { requestId }),
          available: true,
        });
        return;
      }

      if (msg && msg.type === 'sendSignals') {
        const signalPaths = Array.isArray(msg.signalPaths)
          ? (msg.signalPaths as unknown[]).filter((signalPath): signalPath is string => typeof signalPath === 'string')
          : [];
        if (signalPaths.length === 0) {
          return;
        }
        try {
          await vscode.commands.executeCommand('rohd.sendSignals', {
            sourceViewerId: viewerId,
            signalPaths,
          });
        } catch (e) {
          output.appendLine(`[SignalViewers] send failed: ${e}`);
        }
        return;
      }

      // ── Module info query — source availability check ──
      if (msg && (msg.type === 'getModuleInfo' || msg.type === 'setActiveModule')) {
        const moduleName = msg.module as string | null;
        const instancePath = Array.isArray(msg.instancePath)
          ? (msg.instancePath as string[])
          : undefined;
        const requestId = msg.requestId as string | undefined;
        output.appendLine(
          `[moduleInfo] Query for module: ${moduleName}` +
          `${instancePath ? ` instancePath=${instancePath.join('/')}` : ''}`,
        );
        const info = await buildModuleInfo(
          docUri,
          moduleName,
          instancePath,
          output,
        );
        output.appendLine(`[moduleInfo] Result: ${JSON.stringify(info)}`);
        const responseMsg = {
          type: msg.type === 'setActiveModule' ? 'setActiveModuleResult' : 'getModuleInfoResult',
          ...(requestId && { requestId }),
          ...info,
        };
        output.appendLine(`[moduleInfo] Posting response: ${JSON.stringify(responseMsg)}`);
        webviewPanel.webview.postMessage(responseMsg);
        return;
      }

      // ── FLC frame lookup: returns frames to webview for popup selection ──
      if (msg && msg.type === 'lookupSignalFrames') {
        const signals: { module: string; name: string }[] = msg.signals || [];
        const format: string | undefined = msg.format;
        const requestId = msg.requestId as string | undefined;
        output.appendLine(`[lookupFrames] ${signals.length} signal(s), format=${format ?? 'all'}`);

        const flcPath = await resolveFlcPath(docUri, output);
        if (!flcPath) {
          webviewPanel.webview.postMessage({
            type: 'lookupSignalFramesResult',
            ...(requestId && { requestId }),
            frames: [],
            error: 'No .flc.json sidecar found.',
          });
          return;
        }

        const allFrames: any[] = [];
        for (const sig of signals) {
          const frames = await lookupSignalFrames(flcPath, sig.module || null, sig.name, format, output);
          allFrames.push(...frames);
        }
        output.appendLine(`[lookupFrames] Resolved ${allFrames.length} frames`);
        webviewPanel.webview.postMessage({
          type: 'lookupSignalFramesResult',
          ...(requestId && { requestId }),
          frames: allFrames,
        });
        return;
      }

      // ── Open a specific source location (chosen by user from popup) ──
      if (msg && msg.type === 'openSourceLocation') {
        output.appendLine(`[crossProbe] openSourceLocation: ${msg.file}:${msg.line}:${msg.col}`);
        try {
          await vscode.commands.executeCommand('rohd.openSourceLocation', {
            file: msg.file,
            line: msg.line,
            col: msg.col || 0,
          });
        } catch (e: any) {
          output.appendLine(`[crossProbe] rohd.openSourceLocation not available: ${e.message}`);
        }
        return;
      }

      if (msg && msg.type === 'requestSave') {
        if (typeof msg.text === 'string') {
          // Overwrite via workspace edit (best-effort)
          const edit = new vscode.WorkspaceEdit();
          const uri = docUri;
          try {
            const bytes = Buffer.from(msg.text, 'utf8');
            await vscode.workspace.fs.writeFile(uri, bytes);
          } catch (e) {
            output.appendLine(`Failed to write file: ${e}`);
          }
        } else if (typeof msg.uri === 'string') {
          try {
            const updated = await vscode.workspace.fs.readFile(vscode.Uri.parse(msg.uri));
            const text = Buffer.from(updated).toString('utf8');
            // best-effort write
            await vscode.workspace.fs.writeFile(docUri, Buffer.from(text, 'utf8'));
          } catch (e) {
            output.appendLine(`Failed to read save URI from webview: ${e}`);
          }
        }
      }
      if (msg && msg.type === 'requestRepaint') {
        webviewPanel.webview.postMessage({ type: 'repaintAck', timestamp: Date.now() });
      }
      if (msg && msg.type === 'requestReload') {
        // User requested manual reload of the original file (bypasses sent guard)
        output.appendLine('Webview requested file reload');
        sendContents();
      }
      if (msg && msg.type === 'saveSignalList') {
        // User wants to save the signal list JSON via a native VS Code dialog.
        const content = msg.content as string;
        const suggestedName = (msg.fileName as string) || 'signals.json';
        const defaultUri = vscode.Uri.joinPath(docUri, '..', suggestedName);
        const saveUri = await vscode.window.showSaveDialog({
          defaultUri,
          filters: { 'JSON files': ['json'] },
          title: 'Save Signal List',
        });
        if (saveUri) {
          try {
            await vscode.workspace.fs.writeFile(saveUri, Buffer.from(content, 'utf8'));
            webviewPanel.webview.postMessage({ type: 'saveSignalListResult', success: true });
            output.appendLine(`Signal list saved to ${saveUri.fsPath}`);
          } catch (e) {
            webviewPanel.webview.postMessage({ type: 'saveSignalListResult', success: false, error: String(e) });
            output.appendLine(`Failed to save signal list: ${e}`);
          }
        }
      }
      if (msg && msg.type === 'loadSignalList') {
        // User wants to load a signal list JSON via a native VS Code dialog.
        const defaultUri = vscode.Uri.joinPath(docUri, '..');
        const openUris = await vscode.window.showOpenDialog({
          defaultUri,
          canSelectMany: false,
          filters: { 'JSON files': ['json'] },
          title: 'Load Signal List',
        });
        if (openUris && openUris.length > 0) {
          try {
            const fileBytes = await vscode.workspace.fs.readFile(openUris[0]);
            const content = Buffer.from(fileBytes).toString('utf8');
            webviewPanel.webview.postMessage({ type: 'loadSignalListResult', success: true, content });
            output.appendLine(`Signal list loaded from ${openUris[0].fsPath}`);
          } catch (e) {
            webviewPanel.webview.postMessage({ type: 'loadSignalListResult', success: false, error: String(e) });
            output.appendLine(`Failed to load signal list: ${e}`);
          }
        } else {
          // User cancelled the dialog
          webviewPanel.webview.postMessage({ type: 'loadSignalListResult', success: false, cancelled: true });
        }
      }

      // ── Save PNG via native Save dialog ──
      if (msg && msg.type === 'savePng') {
        const base64Data = msg.data as string | undefined;
        const suggestedName = (msg.suggestedName as string) || 'waveform.png';
        if (!base64Data) {
          output.appendLine('[savePng] No data received');
          webviewPanel.webview.postMessage({ type: 'savePngResult', success: false, error: 'No data' });
        } else {
          output.appendLine(`[savePng] Prompting save dialog, suggested: ${suggestedName}`);
          const defaultUri = vscode.Uri.joinPath(docUri, '..', suggestedName);
          const saveUri = await vscode.window.showSaveDialog({
            defaultUri,
            filters: { 'PNG Image': ['png'] },
            title: 'Save Waveform Snapshot',
          });
          if (saveUri) {
            try {
              const pngBytes = Buffer.from(base64Data, 'base64');
              await vscode.workspace.fs.writeFile(saveUri, pngBytes);
              output.appendLine(`[savePng] Saved: ${saveUri.fsPath}`);
              vscode.window.showInformationMessage(`Waveform saved: ${path.basename(saveUri.fsPath)}`);
              webviewPanel.webview.postMessage({ type: 'savePngResult', success: true, path: saveUri.fsPath });
            } catch (e) {
              output.appendLine(`[savePng] Error: ${e}`);
              vscode.window.showErrorMessage(`Failed to save PNG: ${e}`);
              webviewPanel.webview.postMessage({ type: 'savePngResult', success: false, error: String(e) });
            }
          } else {
            output.appendLine('[savePng] User cancelled');
            webviewPanel.webview.postMessage({ type: 'savePngResult', success: false, error: 'Cancelled' });
          }
        }
      }

      // ── Cross-probe: Go to Source — delegated to rohd_extension ──
      if (msg && msg.type === 'goToSource') {
        const signals: { module: string; name: string }[] = msg.signals || [];
        const format: string | undefined = msg.format;  // 'rohd' | 'sv' | undefined
        output.appendLine(`[crossProbe] goToSource: ${signals.length} signal(s), format=${format ?? 'all'}`);

        // Resolve FLC sidecar via shared helper.
        const flcPath = await resolveFlcPath(docUri, output);

        if (!flcPath) {
          vscode.window.showWarningMessage(
            'ROHD: No .flc.json sidecar found. Generate one with TraceService.writeFlcFiles().');
          return;
        }
        output.appendLine(`[crossProbe] Using FLC: ${flcPath}`);

        let allFrames: { file: string; line: number; col: number; desc: string; type: string }[] = [];

        for (const sig of signals) {
          const frames = await lookupSignalFrames(flcPath, sig.module || null, sig.name, format, output);
          if (frames && frames.length > 0) {
            output.appendLine(`[crossProbe] ${sig.name}: ${frames.length} frame(s)`);
            allFrames.push(...frames);
          } else {
            output.appendLine(`[crossProbe] ${sig.name}: no frames found`);
          }
        }

        if (allFrames.length === 0) {
          vscode.window.showInformationMessage(
            'ROHD: No source locations found in FLC for the selected signal(s).');
          return;
        }

        output.appendLine(`[crossProbe] Resolved ${allFrames.length} frames (${allFrames.filter(f => f.type === 'sv').length} SV, ${allFrames.filter(f => f.type === 'rohd').length} ROHD)`);

        try {
          if (allFrames.length === 1) {
            await vscode.commands.executeCommand('rohd.openSourceLocation', allFrames[0]);
          } else {
            await vscode.commands.executeCommand('rohd.openSourceLocations', {
              frames: allFrames,
              index: 0,
            });
          }
        } catch (e: any) {
          output.appendLine(`[crossProbe] rohd extension not available: ${e.message}`);
          vscode.window.showInformationMessage('Install the ROHD extension for source navigation.');
        }
      }
    });

    // Initial send — must happen immediately after setting webviewPanel.webview.html.
    // VS Code queues this message internally and delivers it once the webview's JS
    // context is ready.  The embed shim's window.addEventListener('message') catches
    // it and queues it in __rohdMessageQueue for Dart to replay when ready.
    // The rohdReady handler and 2s timeout are fallbacks gated by sendContentsOnce.
    sendContentsOnce();
  }
}

function transformHtml(html: string, webview: vscode.Webview, context: vscode.ExtensionContext) {
  const cspSource = webview.cspSource;
  // Inject CSP meta if missing - includes wasm-unsafe-eval for WASM support and gstatic.com for CanvasKit
  if (!/Content-Security-Policy/i.test(html)) {
    const meta = `<meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'wasm-unsafe-eval' 'unsafe-eval' 'unsafe-inline' ${cspSource} https://www.gstatic.com; style-src 'unsafe-inline' ${cspSource}; img-src ${cspSource} data: blob:; connect-src ${cspSource} https://www.gstatic.com https:; font-src ${cspSource} data:; worker-src ${cspSource} blob:;">`;
    html = html.replace(/<head[^>]*>/i, match => match + meta);
  }

  // The Flutter web build is in flutter_web/
  const flutterWebUri = vscode.Uri.joinPath(context.extensionUri, 'flutter_web');

  // Replace base href with the webview URI for flutter_web folder
  const baseUri = webview.asWebviewUri(flutterWebUri).toString() + '/';
  html = html.replace(/<base\s+href="[^"]*"/gi, `<base href="${baseUri}"`);

  // Replace absolute / asset paths with webview URIs
  html = html.replace(/src="\/([^\"]+)"/g, (m, p1) => {
    const uri = webview.asWebviewUri(vscode.Uri.joinPath(flutterWebUri, p1));
    return `src="${uri.toString()}"`;
  });
  html = html.replace(/href="\/([^\"]+)"/g, (m, p1) => {
    const uri = webview.asWebviewUri(vscode.Uri.joinPath(flutterWebUri, p1));
    return `href="${uri.toString()}"`;
  });

  // Replace relative paths (not starting with http/data/blob) with webview URIs
  html = html.replace(/src="([^\.\/][^\"]*\.js)"/g, (m, p1) => {
    if (p1.startsWith('http') || p1.startsWith('data:') || p1.startsWith('blob:')) return m;
    const uri = webview.asWebviewUri(vscode.Uri.joinPath(flutterWebUri, p1));
    return `src="${uri.toString()}"`;
  });

  // Inject embed shim for communication between Flutter and extension
  const shimScript = `
<script>
  // Shim for Flutter web <-> VS Code extension communication
  const vscode = acquireVsCodeApi();

  // Mark that we are running inside a VS Code webview so the Dart side
  // (isVscodeWebview()) can detect extension mode.
  window.VSCODE_WEBVIEW = true;

  // Global for Flutter to post messages back
  window.postRohd = function(msg) { vscode.postMessage(msg); };

  // Queue for messages that arrive before Dart callback is registered
  window.__rohdMessageQueue = [];

  // Setup message receiver for Flutter
  window.rohdEmbed = {
    onMessage: function(callback) {
      window.__rohdMessageCallback = callback;
      // Replay any queued messages
      console.log('[embedShim] Callback registered, replaying', window.__rohdMessageQueue.length, 'queued messages');
      while (window.__rohdMessageQueue.length > 0) {
        const queuedMsg = window.__rohdMessageQueue.shift();
        try {
          callback(queuedMsg);
        } catch (e) {
          console.error('[embedShim] Error replaying queued message:', e);
        }
      }
    },
    postMessage: function(msg) { vscode.postMessage(msg); }
  };

  // Forward console messages to extension for debugging
  ['log','warn','error','info','debug'].forEach(level => {
    const orig = console[level];
    console[level] = function(...args) {
      orig.apply(console, args);
      vscode.postMessage({ type: 'console', level: level, args: args.map(a => String(a)) });
    };
  });

  // Listen for messages from extension
  window.addEventListener('message', (e) => {
    const msg = e.data;
    console.log('[embedShim] Received message:', msg?.type);

    // Handle keyEvent from extension — dispatch a synthetic KeyboardEvent
    // to Flutter's canvas so that KeyboardListener picks it up.
    if (msg && msg.type === 'keyEvent') {
      try {
        var target = document.querySelector('flt-glass-pane') || document.querySelector('canvas') || document.body;
        // Dispatch keydown then keyup so Flutter sees a complete key press
        var opts = { key: msg.key, code: msg.key, bubbles: true, cancelable: true, shiftKey: !!msg.shiftKey };
        target.dispatchEvent(new KeyboardEvent('keydown', opts));
        target.dispatchEvent(new KeyboardEvent('keyup', opts));
      } catch(e) { console.error('[embedShim] keyEvent dispatch failed:', e); }
      return; // don't forward to Dart callback — already handled via DOM event
    }

    // Handle repaintAck from extension - this round-trip should wake up compositor
    if (msg && msg.type === 'repaintAck') {
      console.log('[embedShim] Got repaintAck, forcing DOM update');
      // Do a visible DOM change to try to wake up the compositor
      document.body.style.opacity = '0.9999';
      requestAnimationFrame(function() {
        document.body.style.opacity = '1';
        // Also dispatch a pointer event to simulate mouse movement
        try {
          var canvas = document.querySelector('canvas');
          if (canvas) {
            var rect = canvas.getBoundingClientRect();
            var evt = new PointerEvent('pointermove', {
              bubbles: true,
              clientX: rect.left + rect.width / 2,
              clientY: rect.top + rect.height / 2,
              pointerType: 'mouse'
            });
            canvas.dispatchEvent(evt);
          }
        } catch(e) {}
      });
    }

    // Forward message to Dart callback, or queue if not ready yet
    if (window.__rohdMessageCallback) {
      console.log('[embedShim] Invoking callback for message type:', msg?.type);
      try {
        window.__rohdMessageCallback(msg);
        console.log('[embedShim] Callback invoked successfully');
      } catch (e) {
        console.error('[embedShim] Callback invocation failed:', e);
      }
    } else {
      console.log('[embedShim] Callback not ready, queuing message:', msg?.type);
      window.__rohdMessageQueue.push(msg);
    }
  });

  // Notify when Flutter app signals ready
  window.__rohdEmbedReady = function(info) {
    console.log('[embedShim] Flutter app ready:', JSON.stringify(info));
    vscode.postMessage({ type: 'rohdReady', info: info });
  };
</script>`;

  // Insert shim after opening <body> tag.
  // NOTE: No fetchHandler is needed — the Dart side handles vcdUri messages
  // by HTTP-fetching the webview URI directly (like Surfer does).
  html = html.replace(/<body[^>]*>/i, match => match + shimScript);

  return html;
}

export function deactivate() {}
