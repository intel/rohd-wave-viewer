#!/usr/bin/env bash

# Copyright (C) 2026 Intel Corporation
# SPDX-License-Identifier: BSD-3-Clause

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fixture="$(mktemp -d "${TMPDIR:-/tmp}/rohd-wave-badge-test.XXXXXXXX")"
trap 'rm -rf "$fixture"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

awk '
  /      - name: Commit coverage badge/ { step = 1 }
  step && /^        run: \|/ { script = 1; next }
  script && /^      - / { exit }
  script { sub(/^          /, ""); print }
' "$repo_root/.github/workflows/coverage.yml" |
  sed "s@/tmp/coverage-badge@${fixture}/coverage-badge@g" \
    >"$fixture/publish.sh"
test -s "$fixture/publish.sh"
bash -n "$fixture/publish.sh"

git init --bare "$fixture/remote.git"
git init --initial-branch=main "$fixture/source"
cd "$fixture/source"
git config user.name "Badge Test"
git config user.email "badge-test@example.com"
printf 'original\n' >tracked.txt
git add tracked.txt
git commit -m "Initial source"
git remote add origin "$fixture/remote.git"
git push origin main
source_head="$(git rev-parse HEAD)"

# Generated changes must not prevent publication or be committed with badges.
printf 'generated change\n' >>tracked.txt
mkdir coverage
printf 'report\n' >coverage/lcov.info
source_status="$(git status --porcelain)"
printf '<svg>first</svg>\n' >"$fixture/coverage-badge.svg"
printf 'first PNG fixture\n' >"$fixture/coverage-badge.png"
export RUNNER_TEMP="$fixture"
export BRANCH_NAME=main

verify_publication() {
  test "$(git rev-parse HEAD)" = "$source_head"
  test "$(git branch --show-current)" = main
  test "$(git status --porcelain)" = "$source_status"
  git --git-dir="$fixture/remote.git" show badges:coverage/main.svg \
    >"$fixture/published.svg"
  git --git-dir="$fixture/remote.git" show badges:coverage/main.png \
    >"$fixture/published.png"
  cmp "$fixture/coverage-badge.svg" "$fixture/published.svg"
  cmp "$fixture/coverage-badge.png" "$fixture/published.png"
  test "$(git --git-dir="$fixture/remote.git" ls-tree -r --name-only badges)" = \
    "$(printf 'coverage/main.png\ncoverage/main.svg')"
  test "$(git worktree list --porcelain | grep -c '^worktree ')" = 1
}

# Create the branch, then update it while a stale local badges ref exists.
bash "$fixture/publish.sh"
verify_publication
first_badge_commit="$(git --git-dir="$fixture/remote.git" rev-parse badges)"
git fetch origin badges:badges
printf '<svg>updated</svg>\n' >"$fixture/coverage-badge.svg"
printf 'updated PNG fixture\n' >"$fixture/coverage-badge.png"
bash "$fixture/publish.sh"
verify_publication
updated_badge_commit="$(git --git-dir="$fixture/remote.git" rev-parse badges)"
test "$updated_badge_commit" != "$first_badge_commit"
test "$(git --git-dir="$fixture/remote.git" rev-parse badges^)" = \
  "$first_badge_commit"

# Identical badges need neither a new commit nor a force push.
bash "$fixture/publish.sh"
verify_publication
test "$(git --git-dir="$fixture/remote.git" rev-parse badges)" = \
  "$updated_badge_commit"

# An unreachable remote must fail instead of reporting successful publication.
git remote set-url origin "$fixture/missing.git"
if bash "$fixture/publish.sh"; then
  printf 'error: badge publication unexpectedly succeeded without a remote\n' >&2
  exit 1
fi

printf 'Coverage badge publication tests passed.\n'
