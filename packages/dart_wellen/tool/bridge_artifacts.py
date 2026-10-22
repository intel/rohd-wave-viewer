#!/usr/bin/env python3
# Copyright (C) 2026 Intel Corporation
# SPDX-License-Identifier: BSD-3-Clause
"""Prepare or install the package's pinned web bridge without consumer builds."""

import argparse
import gzip
import hashlib
import io
import json
from pathlib import Path
import re
import shutil
import subprocess
import tarfile
import tempfile
import urllib.error
import urllib.request
from urllib.parse import urlparse


PACKAGE = Path(__file__).resolve().parents[1]
MANIFEST = Path("tool/bridge_artifacts.json")
BUILD_MANIFEST = Path("tool/bridge_artifacts.build.json")
FILES = (
    "lib/src/rust/api.dart",
    "lib/src/rust/frb_generated.dart",
    "lib/src/rust/frb_generated.io.dart",
    "lib/src/rust/frb_generated.web.dart",
    "web/pkg/wellen_bridge.js",
    "web/pkg/wellen_bridge_bg.wasm",
    "web/pkg/LICENSE",
    "web/pkg/wellen_bridge_LICENSES.txt",
)


def digest(data):
    return hashlib.sha256(data).hexdigest()


def git_archive_template(release_url, version):
    location = re.fullmatch(
        r"https://github\.com/([^/]+)/([^/]+)/releases/download/[^/]+/[^/?#]+",
        release_url,
    )
    if not location:
        return None
    return (
        f"https://github.com/{location[1]}/{location[2]}/releases/download/"
        f"dart-wellen-{{commit}}/dart_wellen-{version}-web.tar.gz"
    )


def manifest_versions(package):
    text = (package / "pubspec.yaml").read_text()
    version = re.search(r"^version:\s*(\S+)", text, re.M)
    bridge = re.search(
        r"^[ \t]+flutter_rust_bridge:[ \t]*['\"]?([\d.]+)['\"]?[ \t]*$",
        text, re.M,
    )
    if not version or not bridge:
        raise ValueError("dart_wellen must declare its version and exact bridge version")
    return version[1], bridge[1]


def validate_manifest(package, manifest):
    if not isinstance(manifest, dict):
        raise ValueError("Artifact metadata must be a JSON object")
    version, bridge = manifest_versions(package)
    if (manifest["version"], manifest["bridge_version"]) != (version, bridge):
        raise ValueError("Artifact manifest does not match the selected dart_wellen version")
    inventory = manifest.get("files")
    if (
        not isinstance(inventory, (list, dict))
        or not all(isinstance(name, str) for name in inventory)
        or len(inventory) != len(FILES)
        or set(inventory) != set(FILES)
    ):
        raise ValueError("Artifact manifest has an unexpected file inventory")
    if not isinstance(manifest.get("archive_url"), str):
        raise ValueError("Artifact manifest requires a download URL")
    if manifest.get("profile") != "release":
        raise ValueError("This web artifact contract requires an explicit release profile")
    if "git_archive_url_template" in manifest:
        expected = git_archive_template(manifest["archive_url"], version)
        if not expected or manifest["git_archive_url_template"] != expected:
            raise ValueError("Git artifact URL template does not match the pinned repository/version")


def validate_build_manifest(package, contract, manifest, commit=None):
    validate_manifest(package, manifest)
    for key in ("version", "bridge_version", "profile", "archive_url", "git_archive_url_template"):
        if manifest.get(key) != contract.get(key):
            raise ValueError(f"Build metadata does not match the source contract: {key}")
    if not isinstance(manifest["files"], dict) or not all(
        isinstance(value, str) and re.fullmatch(r"[a-f0-9]{64}", value)
        for value in (*manifest["files"].values(), manifest.get("archive_sha256"))
    ):
        raise ValueError("Build metadata requires valid file and archive SHA-256 checksums")
    if commit and manifest.get("source_commit") != commit:
        raise ValueError("Build metadata does not match the selected Git commit")


def source_commit(repository):
    if not (repository / ".git").exists():
        return None
    commit = subprocess.run(
        ["git", "-C", str(repository), "rev-parse", "HEAD"],
        check=True, capture_output=True, text=True,
    ).stdout.strip()
    if not re.fullmatch(r"[a-f0-9]{40}", commit):
        raise ValueError("Could not determine the selected Git commit for artifact installation")
    return commit


def download_target(package, manifest):
    template = manifest.get("git_archive_url_template")
    commit = source_commit(package.parents[1]) if template else None
    if commit:
        return template.replace("{commit}", commit), commit
    return manifest["archive_url"], None


def verify(package, manifest):
    validate_manifest(package, manifest)
    if not isinstance(manifest["files"], dict):
        raise ValueError("Prepared artifact checksum metadata is missing")
    _, bridge = manifest_versions(package)
    for name, expected in manifest["files"].items():
        path = package / name
        if not path.is_file() or digest(path.read_bytes()) != expected:
            raise ValueError(f"Missing or mismatched packaged artifact: {path}")
    generated = (package / "lib/src/rust/frb_generated.dart").read_text()
    if f"String get codegenVersion => '{bridge}';" not in generated:
        raise ValueError("Generated bindings do not match the package bridge version")
    if (package / "web/pkg/wellen_bridge_bg.wasm").read_bytes()[:4] != b"\0asm":
        raise ValueError("Packaged runtime is not WebAssembly")


def read_contract(package):
    if not (package / MANIFEST).is_file():
        raise ValueError(
            f"Missing artifact manifest: {package / MANIFEST}. Prepare/release the selected "
            "dart_wellen package in rohd-wave-viewer; consumers never build it."
        )
    contract = json.loads((package / MANIFEST).read_text())
    validate_manifest(package, contract)
    return contract


def verify_prepared(package, contract):
    if not (package / BUILD_MANIFEST).is_file():
        raise ValueError(f"Prepared artifact checksum metadata is missing: {package / BUILD_MANIFEST}")
    manifest = json.loads((package / BUILD_MANIFEST).read_text())
    validate_build_manifest(package, contract, manifest)
    verify(package, manifest)


def download(url):
    if urlparse(url).scheme != "https":
        raise ValueError("Artifact downloads require a pinned HTTPS release URL")
    print(f"Downloading prebuilt dart_wellen artifact: {url}", flush=True)
    try:
        with urllib.request.urlopen(url, timeout=60) as response:
            if urlparse(response.url).scheme != "https":
                raise ValueError("Artifact download redirected away from HTTPS")
            return response.read()
    except urllib.error.HTTPError as error:
        if error.code == 404:
            raise ValueError(
                f"No prebuilt bundle at {url}. Wait for the producer's General workflow, "
                "including Distribute commit-keyed bridge bundle, for this exact commit "
                "to succeed. Pull-request checks do not distribute bundles."
            ) from error
        raise


def atomic_write(target, data):
    target.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(
        dir=target.parent, prefix=f".{target.name}.", delete=False,
    ) as temporary_file:
        temporary_target = Path(temporary_file.name)
        try:
            temporary_file.write(data)
            temporary_file.flush()
            temporary_target.replace(target)
        finally:
            temporary_target.unlink(missing_ok=True)


def install(package):
    contract = read_contract(package)
    try:
        verify_prepared(package, contract)
        return
    except ValueError as error:
        print(f"Packaged artifacts need installation: {error}", flush=True)
    url, commit = download_target(package, contract)
    metadata = download(url + ".json")
    manifest = json.loads(metadata)
    validate_build_manifest(package, contract, manifest, commit)
    archive = download(url)
    if digest(archive) != manifest["archive_sha256"]:
        raise ValueError("Downloaded artifact archive SHA-256 does not match the build metadata")
    # Extract only the fixed inventory; reject links, duplicates and traversal.
    with tempfile.TemporaryDirectory(prefix="dart-wellen-artifacts-") as temporary:
        staging = Path(temporary)
        with tarfile.open(fileobj=io.BytesIO(archive), mode="r:gz") as bundle:
            members = bundle.getmembers()
            if len(members) != len(FILES) or {m.name for m in members} != set(FILES):
                raise ValueError("Downloaded artifact archive has an unexpected file inventory")
            for member in members:
                if not member.isfile():
                    raise ValueError(f"Artifact is not a regular file: {member.name}")
                target = staging / member.name
                target.parent.mkdir(parents=True, exist_ok=True)
                with bundle.extractfile(member) as source:
                    target.write_bytes(source.read())
        shutil.copyfile(package / "pubspec.yaml", staging / "pubspec.yaml")
        verify(staging, manifest)
        for name in FILES:
            atomic_write(package / name, (staging / name).read_bytes())
    atomic_write(package / BUILD_MANIFEST, metadata)
    verify_prepared(package, contract)


def prepare(repository, release_url):
    package = repository / "packages/dart_wellen"
    # The producer owns compilation and semantic validation, including the
    # generated Dart/native/WASM content hash agreement.
    subprocess.run(["bash", str(repository / "tool/verify_bridge_release.sh")], check=True)
    version, bridge = manifest_versions(package)
    runtime = package / "web/pkg"
    runtime.mkdir(parents=True, exist_ok=True)
    for name in ("wellen_bridge.js", "wellen_bridge_bg.wasm", "LICENSE"):
        shutil.copyfile(repository / "web/pkg" / name, runtime / name)
    shutil.copyfile(
        repository / "assets/licenses/wellen_bridge_LICENSES.txt",
        runtime / "wellen_bridge_LICENSES.txt",
    )
    contract = {
        "version": version,
        "bridge_version": bridge,
        "profile": "release",
        "archive_url": release_url,
    }
    template = git_archive_template(release_url, version)
    if template:
        contract["git_archive_url_template"] = template
    contract["files"] = list(FILES)
    manifest = {**contract, "files": {name: digest((package / name).read_bytes()) for name in FILES}}
    commit = source_commit(repository)
    if commit:
        manifest["source_commit"] = commit
    verify(package, manifest)
    # Reproducible bytes keep the pinned archive hash stable across machines.
    output = io.BytesIO()
    with gzip.GzipFile(fileobj=output, mode="wb", mtime=0) as compressed:
        with tarfile.open(fileobj=compressed, mode="w") as bundle:
            for name in FILES:
                data = (package / name).read_bytes()
                info = tarfile.TarInfo(name)
                info.size = len(data)
                info.mode = 0o644
                bundle.addfile(info, io.BytesIO(data))
    archive = repository / "build" / f"dart_wellen-{version}-web.tar.gz"
    archive.parent.mkdir(parents=True, exist_ok=True)
    archive.write_bytes(output.getvalue())
    manifest["archive_sha256"] = digest(output.getvalue())
    (package / MANIFEST).write_text(json.dumps(contract, indent=2) + "\n")
    (package / BUILD_MANIFEST).write_text(json.dumps(manifest, indent=2) + "\n")
    print(f"Prepared {archive}")
    print(f"Commit {package / MANIFEST}; General CI distributes the bundle for each pushed commit.")
    print(f"Explicit release publication remains available at {release_url}.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("install", help="Verify packaged files or download the pinned bundle")
    commands.add_parser("verify", help="Verify packaged files without network access")
    producer = commands.add_parser("prepare", help="Package artifacts already built by the viewer")
    producer.add_argument("--repository-root", type=Path, default=PACKAGE.parents[1])
    producer.add_argument("--release-url", required=True)
    args = parser.parse_args()
    try:
        if args.command == "prepare":
            if urlparse(args.release_url).scheme != "https":
                raise ValueError("Release URL must use HTTPS")
            prepare(args.repository_root.resolve(), args.release_url)
        elif args.command == "install":
            install(PACKAGE)
        else:
            verify_prepared(PACKAGE, read_contract(PACKAGE))
    except (OSError, ValueError, KeyError, tarfile.TarError,
            urllib.error.URLError, subprocess.CalledProcessError) as error:
        parser.exit(1, f"dart_wellen artifact error: {error}\n")


if __name__ == "__main__":
    main()
