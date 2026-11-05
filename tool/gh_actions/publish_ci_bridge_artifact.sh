#!/usr/bin/env bash
# Copyright (C) 2026 Intel Corporation
# SPDX-License-Identifier: BSD-3-Clause
#
# Publish a verified dart_wellen consumer bundle to the public artifacts branch.

set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 <artifact-directory> <source-commit>" >&2
  exit 2
fi

artifact_directory="$(cd "$1" && pwd)"
source_commit="$2"
repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
artifact_branch="${DART_WELLEN_ARTIFACT_BRANCH:-artifacts}"

if [[ ! "$source_commit" =~ ^[a-f0-9]{40}$ ]]; then
  echo "Source commit must be a full Git SHA." >&2
  exit 2
fi

build_manifest="$artifact_directory/packages/dart_wellen/tool/bridge_artifacts.build.json"
archive="$(find "$artifact_directory/build" -maxdepth 1 -type f \
  -name 'dart_wellen-*-web.tar.gz' -print -quit)"
if [[ ! -f "$build_manifest" || -z "$archive" ]]; then
  echo "Prepared dart_wellen artifact archive or build manifest is missing." >&2
  exit 1
fi

python3 - "$build_manifest" "$archive" "$source_commit" <<'PY'
import hashlib
import json
from pathlib import Path
import re
import sys

manifest = json.loads(Path(sys.argv[1]).read_text())
archive = Path(sys.argv[2])
commit = sys.argv[3]
if manifest.get("source_commit") != commit:
    raise SystemExit("Prepared artifact source commit does not match this workflow run.")
if hashlib.sha256(archive.read_bytes()).hexdigest() != manifest.get("archive_sha256"):
    raise SystemExit("Prepared artifact archive checksum does not match build metadata.")
if not re.fullmatch(r"dart_wellen-\d+\.\d+\.\d+(?:-[\w.-]+)?(?:\+[\w.-]+)?-web\.tar\.gz", archive.name):
    raise SystemExit("Prepared artifact archive name does not match the dart_wellen version.")
PY

workspace="$(mktemp -d "${RUNNER_TEMP:-/tmp}/dart-wellen-artifacts.XXXXXX")"
trap 'git -C "$repository_root" worktree remove --force "$workspace" >/dev/null 2>&1 || true; rm -rf "$workspace"' EXIT

if git -C "$repository_root" ls-remote --exit-code origin "refs/heads/$artifact_branch" >/dev/null 2>&1; then
  git -C "$repository_root" fetch origin "$artifact_branch"
  git -C "$repository_root" worktree add --detach "$workspace" "origin/$artifact_branch"
else
  git -C "$repository_root" worktree add --detach "$workspace" HEAD
  git -C "$workspace" checkout --orphan "$artifact_branch"
  git -C "$workspace" rm -rf . >/dev/null 2>&1 || true
fi

destination="$workspace/dart-wellen/$source_commit"
mkdir -p "$destination"
cp "$archive" "$destination/"
cp "$build_manifest" "$destination/$(basename "$archive").json"

git -C "$workspace" add "dart-wellen/$source_commit"
if git -C "$workspace" diff --cached --quiet; then
  echo "Public CI artifact already matches $source_commit."
  exit 0
fi
git -C "$workspace" config user.name "github-actions[bot]"
git -C "$workspace" config user.email "41898282+github-actions[bot]@users.noreply.github.com"
git -C "$workspace" commit -m "Publish dart_wellen CI artifact for $source_commit"
git -C "$workspace" push origin "HEAD:$artifact_branch"
