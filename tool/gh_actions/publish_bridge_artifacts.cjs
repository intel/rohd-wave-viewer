// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause

const { createHash } = require('node:crypto');
const fs = require('node:fs/promises');
const path = require('node:path');

module.exports = async function publishBridgeArtifacts({
  github, context, workspace, artifactDirectory,
}) {
  const manifestPath = 'packages/dart_wellen/tool/bridge_artifacts.json';
  const committed = await fs.readFile(path.join(workspace, manifestPath));
  const prepared = await fs.readFile(path.join(artifactDirectory, manifestPath));
  if (!committed.equals(prepared)) {
    throw new Error('Prepared artifact manifest differs from the selected source commit.');
  }
  const manifest = JSON.parse(committed.toString('utf8'));
  if (!/^\d+\.\d+\.\d+(?:-[\w.-]+)?(?:\+[\w.-]+)?$/.test(manifest.version)
      || manifest.profile !== 'release'
      || !/^[a-f0-9]{64}$/.test(manifest.archive_sha256)) {
    throw new Error('The committed artifact manifest has invalid version, profile, or checksum metadata.');
  }
  const url = new URL(manifest.archive_url);
  const location = /^\/([^/]+)\/([^/]+)\/releases\/download\/([^/]+)\/([^/]+)$/.exec(url.pathname);
  const { owner, repo } = context.repo;
  if (url.protocol !== 'https:' || url.host !== 'github.com'
      || url.username || url.password || url.search || url.hash || !location
      || location[1].toLowerCase() !== owner.toLowerCase()
      || location[2].toLowerCase() !== repo.toLowerCase()) {
    throw new Error('Artifact publication URL must belong to this GitHub repository.');
  }
  const tag = decodeURIComponent(location[3]);
  const name = decodeURIComponent(location[4]);
  if (name !== `dart_wellen-${manifest.version}-web.tar.gz`) {
    throw new Error('Artifact publication filename does not match the package version.');
  }
  const archive = await fs.readFile(path.join(artifactDirectory, 'build', name));
  const sha256 = (data) => createHash('sha256').update(data).digest('hex');
  if (sha256(archive) !== manifest.archive_sha256) {
    throw new Error('Prepared archive SHA-256 differs from the committed artifact manifest.');
  }

  let release;
  try {
    ({ data: release } = await github.rest.repos.getReleaseByTag({
      owner, repo, tag,
    }));
  } catch (error) {
    if (error.status !== 404) throw error;
  }
  if (!release) {
    ({ data: release } = await github.rest.repos.createRelease({
      owner,
      repo,
      tag_name: tag,
      target_commitish: context.sha,
      name: tag,
      draft: false,
      prerelease: tag !== `dart-wellen-${manifest.version}` || manifest.version.includes('-'),
      make_latest: 'false',
    }));
  }
  if (release.draft) {
    throw new Error('The pinned release is a draft and cannot serve anonymous consumers.');
  }
  const assets = await github.paginate(github.rest.repos.listReleaseAssets, {
    owner, repo, release_id: release.id, per_page: 100,
  });
  const existing = assets.find((asset) => asset.name === name);
  let asset;
  if (existing) {
    const response = await github.rest.repos.getReleaseAsset({
      owner,
      repo,
      asset_id: existing.id,
      headers: { accept: 'application/octet-stream' },
    });
    if (sha256(Buffer.from(response.data)) !== manifest.archive_sha256) {
      throw new Error('Existing release asset has different bytes; choose a new release URL. No asset was replaced.');
    }
    asset = existing;
  } else {
    ({ data: asset } = await github.rest.repos.uploadReleaseAsset({
      owner,
      repo,
      release_id: release.id,
      name,
      data: archive,
      headers: {
        'content-type': 'application/gzip',
        'content-length': archive.length,
      },
    }));
  }
  return {
    releaseUrl: release.html_url,
    assetUrl: asset.browser_download_url,
    sha256: manifest.archive_sha256,
    alreadyPresent: Boolean(existing),
  };
};
