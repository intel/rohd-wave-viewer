#!/usr/bin/env node

// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause

const fs = require('node:fs');
const path = require('node:path');
const publishBridgeArtifacts = require('./publish_bridge_artifacts.cjs');

const repository = process.argv[2] || process.env.GITHUB_REPOSITORY;
const match = /^([^/]+)\/([^/]+)$/.exec(repository || '');
if (!match) {
  console.error(
    'error: supply the GitHub repository as owner/name or set GITHUB_REPOSITORY.',
  );
  process.exit(2);
}

try {
  const workspace = path.resolve(__dirname, '../..');
  const contract = JSON.parse(fs.readFileSync(
    path.join(workspace, 'packages/dart_wellen/tool/bridge_artifacts.json'),
    'utf8',
  ));
  const location = publishBridgeArtifacts.publicationLocation(contract.archive_url, {
    owner: match[1],
    repo: match[2],
  });
  console.log(
    `Bridge artifact publication URL belongs to ${location.owner}/${location.repo}.`,
  );
} catch (error) {
  console.error(`error: ${error.message}`);
  process.exit(1);
}
