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
    version, bridge = manifest_versions(package)
    if (manifest["version"], manifest["bridge_version"]) != (version, bridge):
        raise ValueError("Artifact manifest does not match the selected dart_wellen version")
    if set(manifest["files"]) != set(FILES):
        raise ValueError("Artifact manifest has an unexpected file inventory")
    if manifest.get("profile") != "release":
        raise ValueError("This web artifact contract requires an explicit release profile")


def verify(package, manifest):
    validate_manifest(package, manifest)
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


def install(package):
    path = package / MANIFEST
    if not path.is_file():
        raise ValueError(
            f"Missing artifact manifest: {path}. Prepare/release the selected "
            "dart_wellen package in rohd-wave-viewer; consumers never build it."
        )
    manifest = json.loads(path.read_text())
    # Reject stale metadata before attempting any network access.
    validate_manifest(package, manifest)
    try:
        verify(package, manifest)
        return
    except ValueError as error:
        print(f"Packaged artifacts need installation: {error}", flush=True)
    url = manifest["archive_url"]
    if urlparse(url).scheme != "https":
        raise ValueError("Artifact downloads require a pinned HTTPS release URL")
    print(f"Downloading prebuilt dart_wellen artifacts: {url}", flush=True)
    with urllib.request.urlopen(url, timeout=60) as response:
        if urlparse(response.url).scheme != "https":
            raise ValueError("Artifact download redirected away from HTTPS")
        archive = response.read()
    if digest(archive) != manifest["archive_sha256"]:
        raise ValueError("Downloaded artifact archive SHA-256 does not match the package manifest")
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
            target = package / name
            target.parent.mkdir(parents=True, exist_ok=True)
            with tempfile.NamedTemporaryFile(
                dir=target.parent, prefix=f".{target.name}.", delete=False,
            ) as temporary_file:
                temporary_target = Path(temporary_file.name)
                try:
                    temporary_file.write((staging / name).read_bytes())
                    temporary_file.flush()
                    temporary_target.replace(target)
                finally:
                    temporary_target.unlink(missing_ok=True)
    verify(package, manifest)


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
    manifest = {
        "version": version,
        "bridge_version": bridge,
        "profile": "release",
        "archive_url": release_url,
        "files": {name: digest((package / name).read_bytes()) for name in FILES},
    }
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
    (package / MANIFEST).write_text(json.dumps(manifest, indent=2) + "\n")
    print(f"Prepared {archive}")
    print(f"Commit {package / MANIFEST} and publish the archive at {release_url} before Git consumers use it.")


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
            verify(PACKAGE, json.loads((PACKAGE / MANIFEST).read_text()))
    except (OSError, ValueError, KeyError, tarfile.TarError,
            urllib.error.URLError, subprocess.CalledProcessError) as error:
        parser.exit(1, f"dart_wellen artifact error: {error}\n")


if __name__ == "__main__":
    main()
