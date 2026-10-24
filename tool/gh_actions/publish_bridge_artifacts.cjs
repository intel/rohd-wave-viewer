// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause

const { createHash } = require('node:crypto');
const fs = require('node:fs/promises');
const path = require('node:path');

function parsePublicationLocation(archiveUrl) {
  let url;
  try {
    url = new URL(archiveUrl);
  } catch {
    throw new Error('Artifact publication URL must be a GitHub release asset URL.');
  }
  const location = /^\/([^/]+)\/([^/]+)\/releases\/download\/([^/]+)\/([^/]+)$/.exec(url.pathname);
  if (url.protocol !== 'https:' || url.host !== 'github.com'
      || url.username || url.password || url.search || url.hash || !location
  ) {
    throw new Error('Artifact publication URL must be a GitHub release asset URL.');
  }
  return {
    owner: location[1],
    repo: location[2],
    tag: decodeURIComponent(location[3]),
    name: decodeURIComponent(location[4]),
  };
}

function publicationLocation(archiveUrl, { owner, repo }) {
  const location = parsePublicationLocation(archiveUrl);
  if (location.owner.toLowerCase() !== owner.toLowerCase()
      || location.repo.toLowerCase() !== repo.toLowerCase()) {
    throw new Error('Artifact publication URL must belong to this GitHub repository.');
  }
  return location;
}

async function publishBridgeArtifacts({
  github, context, workspace, artifactDirectory, development = false,
}) {
  const manifestPath = 'packages/dart_wellen/tool/bridge_artifacts.json';
  const contract = JSON.parse(await fs.readFile(path.join(workspace, manifestPath), 'utf8'));
  const prepared = await fs.readFile(path.join(
    artifactDirectory, 'packages/dart_wellen/tool/bridge_artifacts.build.json',
  ));
  const manifest = JSON.parse(prepared.toString('utf8'));
  for (const key of ['version', 'bridge_version', 'profile', 'archive_url', 'git_archive_url_template']) {
    if (manifest[key] !== contract[key]) {
      throw new Error(`Prepared artifact metadata differs from the source contract: ${key}`);
    }
  }
  if (!manifest.files || Array.isArray(manifest.files)
      || !Array.isArray(contract.files)
      || JSON.stringify(Object.keys(manifest.files).sort()) !== JSON.stringify([...contract.files].sort())) {
    throw new Error('Prepared artifact inventory differs from the source contract.');
  }
  if (!/^[a-f0-9]{40}$/.test(context.sha) || manifest.source_commit !== context.sha) {
    throw new Error('Prepared artifact metadata does not match the tested source commit.');
  }
  if (!/^\d+\.\d+\.\d+(?:-[\w.-]+)?(?:\+[\w.-]+)?$/.test(manifest.version)
      || manifest.profile !== 'release'
      || !/^[a-f0-9]{64}$/.test(manifest.archive_sha256)
      || !Object.values(manifest.files).every((value) => /^[a-f0-9]{64}$/.test(value))) {
    throw new Error('Prepared artifact metadata has invalid version, profile, or checksums.');
  }
  const archiveLocation = parsePublicationLocation(manifest.archive_url);
  const name = archiveLocation.name;
  if (name !== `dart_wellen-${manifest.version}-web.tar.gz`) {
    throw new Error('Artifact publication filename does not match the package version.');
  }
  let { owner, repo, tag } = archiveLocation;
  if (development) {
    const template = `https://github.com/${archiveLocation.owner}/${archiveLocation.repo}/releases/download/dart-wellen-{commit}/${name}`;
    if (!/^[a-f0-9]{40}$/.test(context.sha)
        || manifest.git_archive_url_template !== template) {
      throw new Error('Development publication requires a valid source commit and canonical Git artifact URL template.');
    }
    ({ owner, repo } = context.repo);
    tag = `dart-wellen-${context.sha}`;
  } else {
    ({ owner, repo, tag } = publicationLocation(manifest.archive_url, context.repo));
  }
  const archive = await fs.readFile(path.join(artifactDirectory, 'build', name));
  const sha256 = (data) => createHash('sha256').update(data).digest('hex');
  if (sha256(archive) !== manifest.archive_sha256) {
    throw new Error('Prepared archive SHA-256 differs from the CI build metadata.');
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
      prerelease: development || tag !== `dart-wellen-${manifest.version}` || manifest.version.includes('-'),
      make_latest: 'false',
    }));
  }
  if (release.draft) {
    throw new Error('The pinned release is a draft and cannot serve anonymous consumers.');
  }
  const assets = await github.paginate(github.rest.repos.listReleaseAssets, {
    owner, repo, release_id: release.id, per_page: 100,
  });
  const payloads = [
    { name, data: archive, contentType: 'application/gzip' },
    { name: `${name}.json`, data: prepared, contentType: 'application/json' },
  ];
  for (const payload of payloads) {
    payload.asset = assets.find((asset) => asset.name === payload.name);
    if (payload.asset) {
      const response = await github.rest.repos.getReleaseAsset({
        owner,
        repo,
        asset_id: payload.asset.id,
        headers: { accept: 'application/octet-stream' },
      });
      if (!payload.data.equals(Buffer.from(response.data))) {
        throw new Error('Existing release asset has different bytes; choose a new release URL. No asset was replaced.');
      }
    }
  }
  const alreadyPresent = payloads.every((payload) => payload.asset);
  for (const payload of payloads) {
    if (!payload.asset) {
      ({ data: payload.asset } = await github.rest.repos.uploadReleaseAsset({
        owner,
        repo,
        release_id: release.id,
        name: payload.name,
        data: payload.data,
        headers: {
          'content-type': payload.contentType,
          'content-length': payload.data.length,
        },
      }));
    }
  }
  return {
    releaseUrl: release.html_url,
    assetUrl: payloads[0].asset.browser_download_url,
    metadataUrl: payloads[1].asset.browser_download_url,
    sha256: manifest.archive_sha256,
    alreadyPresent,
  };
}

module.exports = publishBridgeArtifacts;
module.exports.publicationLocation = publicationLocation;
