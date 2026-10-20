// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause

const assert = require('node:assert/strict');
const { createHash } = require('node:crypto');
const fs = require('node:fs/promises');
const os = require('node:os');
const path = require('node:path');
const { test } = require('node:test');
const publish = require('../gh_actions/publish_bridge_artifacts.cjs');

async function fixture(t) {
  const directory = await fs.mkdtemp(path.join(os.tmpdir(), 'bridge-publication-'));
  t.after(() => fs.rm(directory, { recursive: true, force: true }));
  const workspace = path.join(directory, 'source');
  const artifactDirectory = path.join(directory, 'artifact');
  const manifestPath = 'packages/dart_wellen/tool/bridge_artifacts.json';
  const archive = Buffer.from('fixture compressed bundle');
  const manifest = {
    version: '0.1.1',
    profile: 'release',
    archive_url: 'https://github.com/example/viewer/releases/download/dart-wellen-0.1.1-dev/dart_wellen-0.1.1-web.tar.gz',
    git_archive_url_template: 'https://github.com/example/viewer/releases/download/dart-wellen-{commit}/dart_wellen-0.1.1-web.tar.gz',
    archive_sha256: createHash('sha256').update(archive).digest('hex'),
  };
  const calls = [];
  const state = {
    release: undefined,
    assets: [],
    existingBytes: archive,
    lookupError: undefined,
  };
  const asset = {
    id: 2,
    name: 'dart_wellen-0.1.1-web.tar.gz',
    browser_download_url: manifest.archive_url,
  };
  const github = {
    rest: {
      repos: {
        async getReleaseByTag(options) {
          calls.push(['lookup', options]);
          if (state.lookupError) throw state.lookupError;
          if (!state.release) throw Object.assign(new Error('Not Found'), { status: 404 });
          return { data: state.release };
        },
        async createRelease(options) {
          calls.push(['create', options]);
          return { data: { id: 1, html_url: 'https://github.com/example/viewer/releases/tag/dev' } };
        },
        listReleaseAssets() {},
        async getReleaseAsset(options) {
          calls.push(['download', options]);
          return { data: state.existingBytes };
        },
        async uploadReleaseAsset(options) {
          calls.push(['upload', options]);
          return { data: asset };
        },
      },
    },
    async paginate(method, options) {
      assert.equal(method, github.rest.repos.listReleaseAssets);
      calls.push(['list', options]);
      return state.assets;
    },
  };
  async function writeManifest() {
    for (const root of [workspace, artifactDirectory]) {
      const filename = path.join(root, manifestPath);
      await fs.mkdir(path.dirname(filename), { recursive: true });
      await fs.writeFile(filename, JSON.stringify(manifest));
    }
  }
  await writeManifest();
  await fs.mkdir(path.join(artifactDirectory, 'build'));
  const archivePath = path.join(artifactDirectory, 'build', asset.name);
  await fs.writeFile(archivePath, archive);
  const options = {
    github,
    context: { repo: { owner: 'example', repo: 'viewer' }, sha: 'a'.repeat(40) },
    workspace,
    artifactDirectory,
  };
  return {
    options, calls, manifest, writeManifest, state, asset, archive, archivePath, manifestPath,
  };
}

test('creates the pinned development release and uploads the exact verified bundle', async (t) => {
  const f = await fixture(t);
  const result = await publish(f.options);
  const created = f.calls.find(([name]) => name === 'create')[1];
  assert.equal(created.target_commitish, f.options.context.sha);
  assert.equal(created.tag_name, 'dart-wellen-0.1.1-dev');
  assert.equal(created.prerelease, true);
  assert.equal(created.draft, false);
  assert.equal(created.make_latest, 'false');
  const uploaded = f.calls.find(([name]) => name === 'upload')[1];
  assert.deepEqual(uploaded.data, f.archive);
  assert.equal(uploaded.name, f.asset.name);
  assert.equal(result.assetUrl, f.manifest.archive_url);
  assert.equal(result.alreadyPresent, false);
});

test('canonical stable artifact tags create non-prereleases', async (t) => {
  const f = await fixture(t);
  f.manifest.archive_url = f.manifest.archive_url.replace('0.1.1-dev/', '0.1.1/');
  await f.writeManifest();
  await publish(f.options);
  assert.equal(f.calls.find(([name]) => name === 'create')[1].prerelease, false);
});

test('automatic publication uses the exact commit instead of the versioned release tag', async (t) => {
  const f = await fixture(t);
  f.asset.browser_download_url = f.manifest.git_archive_url_template.replace(
    '{commit}', f.options.context.sha,
  );
  const result = await publish({ ...f.options, development: true });
  const created = f.calls.find(([name]) => name === 'create')[1];
  assert.equal(created.tag_name, `dart-wellen-${f.options.context.sha}`);
  assert.equal(created.target_commitish, f.options.context.sha);
  assert.equal(created.prerelease, true);
  assert.equal(created.make_latest, 'false');
  assert.equal(result.assetUrl, f.asset.browser_download_url);
  assert.deepEqual(f.calls.find(([name]) => name === 'upload')[1].data, f.archive);
});

test('development publication rejects missing templates and invalid commits before GitHub access', async (t) => {
  for (const mode of ['missing', 'different-repository', 'invalid-commit']) {
    await t.test(mode, async (child) => {
      const f = await fixture(child);
      if (mode === 'missing') delete f.manifest.git_archive_url_template;
      if (mode === 'different-repository') f.manifest.git_archive_url_template = 'https://example.invalid/{commit}';
      if (mode === 'invalid-commit') f.options.context.sha = 'branch-name';
      await f.writeManifest();
      await assert.rejects(
        publish({ ...f.options, development: true }),
        /valid source commit and matching Git artifact URL template/,
      );
      assert.deepEqual(f.calls, []);
    });
  }
});

test('an existing identical asset is verified without uploading or moving its tag', async (t) => {
  const f = await fixture(t);
  f.state.release = { id: 1, html_url: 'existing-release' };
  f.state.assets = [f.asset];
  f.state.existingBytes = Uint8Array.from(f.archive).buffer;
  const result = await publish(f.options);
  assert.equal(result.alreadyPresent, true);
  assert.deepEqual(f.calls.map(([name]) => name), ['lookup', 'list', 'download']);
});

test('an existing different asset is never replaced', async (t) => {
  const f = await fixture(t);
  f.state.release = { id: 1 };
  f.state.assets = [f.asset];
  f.state.existingBytes = Buffer.from('different bundle');
  await assert.rejects(publish(f.options), /different bytes; choose a new release URL/);
  assert.deepEqual(f.calls.map(([name]) => name), ['lookup', 'list', 'download']);
});

test('changed build metadata fails before contacting GitHub', async (t) => {
  const f = await fixture(t);
  await fs.writeFile(path.join(f.options.artifactDirectory, f.manifestPath), '{}');
  await assert.rejects(publish(f.options), /differs from the selected source commit/);
  assert.deepEqual(f.calls, []);
});

test('a corrupt archive fails before contacting GitHub', async (t) => {
  const f = await fixture(t);
  await fs.writeFile(f.archivePath, 'corrupt');
  await assert.rejects(publish(f.options), /SHA-256 differs/);
  assert.deepEqual(f.calls, []);
});

test('publication rejects invalid metadata and URLs before contacting GitHub', async (t) => {
  for (const changes of [
    { profile: 'debug' },
    { version: '../escape' },
    { archive_sha256: 'not-a-hash' },
    { archive_url: 'http://github.com/example/viewer/releases/download/dev/bundle.tar.gz' },
    { archive_url: 'https://github.com/another/viewer/releases/download/dev/bundle.tar.gz' },
    { archive_url: 'https://example.invalid/example/viewer/releases/download/dev/bundle.tar.gz' },
    { archive_url: 'https://github.com/example/viewer/releases/download/dev/wrong.tar.gz' },
  ]) {
    await t.test(JSON.stringify(changes), async (child) => {
      const f = await fixture(child);
      Object.assign(f.manifest, changes);
      await f.writeManifest();
      await assert.rejects(publish(f.options));
      assert.deepEqual(f.calls, []);
    });
  }
});

test('existing drafts fail instead of claiming a publicly installable bundle', async (t) => {
  const f = await fixture(t);
  f.state.release = { id: 1, draft: true };
  await assert.rejects(publish(f.options), /draft/);
  assert.deepEqual(f.calls.map(([name]) => name), ['lookup']);
});

test('lookup permission and network errors are not treated as missing releases', async (t) => {
  const f = await fixture(t);
  f.state.lookupError = Object.assign(new Error('Permission denied'), { status: 403 });
  await assert.rejects(publish(f.options), /Permission denied/);
  assert.deepEqual(f.calls.map(([name]) => name), ['lookup']);
});
