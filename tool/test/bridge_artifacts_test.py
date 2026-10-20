# Copyright (C) 2026 Intel Corporation
# SPDX-License-Identifier: BSD-3-Clause

import contextlib
import importlib.util
import io
import json
from pathlib import Path
import tarfile
import tempfile
import unittest
from unittest.mock import patch
import urllib.error


REPOSITORY = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location(
    "bridge_artifacts",
    REPOSITORY / "packages/dart_wellen/tool/bridge_artifacts.py",
)
bridge = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bridge)


class BridgeArtifactsTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="bridge artifacts ")
        self.addCleanup(self.temporary.cleanup)
        self.repository = Path(self.temporary.name)
        self.package = self.repository / "packages/dart_wellen"
        (self.package / "tool").mkdir(parents=True)
        (self.package / "pubspec.yaml").write_text(
            "name: dart_wellen\nversion: 0.1.1\n"
            "dependencies:\n  flutter_rust_bridge: 2.7.1\n"
        )
        for name in bridge.FILES:
            source = self.package / name
            if name.startswith("web/pkg/"):
                source = self.repository / name
            source.parent.mkdir(parents=True, exist_ok=True)
            source.write_text(f"fixture {name}\n")
        (self.package / "lib/src/rust/frb_generated.dart").write_text(
            "String get codegenVersion => '2.7.1';\n"
        )
        (self.repository / "web/pkg/wellen_bridge_bg.wasm").write_bytes(b"\0asm")
        notices = self.repository / "assets/licenses/wellen_bridge_LICENSES.txt"
        notices.parent.mkdir(parents=True)
        notices.write_text("third-party license notices\n")
        self.url = "https://example.invalid/releases/immutable/web.tar.gz"
        with patch.object(bridge.subprocess, "run") as validate:
            with contextlib.redirect_stdout(io.StringIO()):
                bridge.prepare(self.repository, self.url)
            validate.assert_called_once_with(
                ["bash", str(self.repository / "tool/verify_bridge_release.sh")],
                check=True,
            )
        self.manifest = json.loads((self.package / bridge.MANIFEST).read_text())
        self.archive = (self.repository / "build/dart_wellen-0.1.1-web.tar.gz").read_bytes()

    def remove_artifact(self):
        (self.package / bridge.FILES[0]).unlink()

    def response(self, data=None):
        response = io.BytesIO(self.archive if data is None else data)
        response.url = self.url
        return response

    def test_local_and_hosted_need_no_network(self):
        with patch.object(bridge.urllib.request, "urlopen") as download:
            bridge.install(self.package)
            download.assert_not_called()
        bridge.verify(self.package, self.manifest)

    def test_git_downloads_pinned_complete_bundle(self):
        for name in bridge.FILES:
            (self.package / name).unlink()
        with patch.object(bridge.urllib.request, "urlopen", return_value=self.response()) as download:
            bridge.install(self.package)
            download.assert_called_once_with(self.url, timeout=60)
        bridge.verify(self.package, self.manifest)

    def test_archive_is_reproducible(self):
        with patch.object(bridge.subprocess, "run"):
            bridge.prepare(self.repository, self.url)
        self.assertEqual(
            self.archive,
            (self.repository / "build/dart_wellen-0.1.1-web.tar.gz").read_bytes(),
        )

    def test_bad_archive_hash_does_not_install(self):
        self.remove_artifact()
        with patch.object(bridge.urllib.request, "urlopen", return_value=self.response(b"bad")):
            with self.assertRaisesRegex(ValueError, "SHA-256"):
                bridge.install(self.package)
        self.assertFalse((self.package / bridge.FILES[0]).exists())

    def test_bad_file_hash_does_not_install(self):
        self.remove_artifact()
        self.manifest["files"][bridge.FILES[0]] = "0" * 64
        (self.package / bridge.MANIFEST).write_text(json.dumps(self.manifest))
        with patch.object(bridge.urllib.request, "urlopen", return_value=self.response()):
            with self.assertRaisesRegex(ValueError, "mismatched packaged artifact"):
                bridge.install(self.package)
        self.assertFalse((self.package / bridge.FILES[0]).exists())

    def test_unsafe_archive_inventory_is_rejected(self):
        self.remove_artifact()
        output = io.BytesIO()
        with tarfile.open(fileobj=output, mode="w:gz") as archive:
            entry = tarfile.TarInfo("../outside")
            entry.size = 3
            archive.addfile(entry, io.BytesIO(b"bad"))
        payload = output.getvalue()
        self.manifest["archive_sha256"] = bridge.digest(payload)
        (self.package / bridge.MANIFEST).write_text(json.dumps(self.manifest))
        with patch.object(bridge.urllib.request, "urlopen", return_value=self.response(payload)):
            with self.assertRaisesRegex(ValueError, "inventory"):
                bridge.install(self.package)
        self.assertFalse((self.repository / "outside").exists())

    def test_unpublished_bundle_fails(self):
        self.remove_artifact()
        with patch.object(
            bridge.urllib.request, "urlopen",
            side_effect=urllib.error.HTTPError(self.url, 404, "Not Found", {}, None),
        ):
            with self.assertRaises(urllib.error.HTTPError):
                bridge.install(self.package)

    def test_stale_manifest_never_downloads(self):
        self.manifest["bridge_version"] = "2.7.0"
        (self.package / bridge.MANIFEST).write_text(json.dumps(self.manifest))
        with patch.object(bridge.urllib.request, "urlopen") as download:
            with self.assertRaisesRegex(ValueError, "selected dart_wellen version"):
                bridge.install(self.package)
            download.assert_not_called()

    def test_profile_is_explicit_and_independent_of_flutter_mode(self):
        self.assertEqual(self.manifest["profile"], "release")
        for profile in (None, "debug"):
            with self.subTest(profile=profile):
                self.manifest["profile"] = profile
                (self.package / bridge.MANIFEST).write_text(json.dumps(self.manifest))
                with patch.object(bridge.urllib.request, "urlopen") as download:
                    with self.assertRaisesRegex(ValueError, "release profile"):
                        bridge.install(self.package)
                    download.assert_not_called()

    def test_bridge_version_belongs_to_selected_package(self):
        with self.assertRaisesRegex(ValueError, "bridge version"):
            (self.package / "lib/src/rust/frb_generated.dart").write_text(
                "String get codegenVersion => '2.7.0';\n"
            )
            self.manifest["files"][bridge.FILES[1]] = bridge.digest(
                (self.package / bridge.FILES[1]).read_bytes()
            )
            bridge.verify(self.package, self.manifest)

    def test_another_package_bridge_version_is_supported(self):
        (self.package / "pubspec.yaml").write_text(
            "name: dart_wellen\nversion: 0.1.0\n"
            "dependencies:\n  flutter_rust_bridge: 2.7.0\n"
        )
        generated = self.package / "lib/src/rust/frb_generated.dart"
        generated.write_text("String get codegenVersion => '2.7.0';\n")
        self.manifest.update(version="0.1.0", bridge_version="2.7.0")
        self.manifest["files"][bridge.FILES[1]] = bridge.digest(generated.read_bytes())
        bridge.verify(self.package, self.manifest)

    def test_plain_http_download_is_rejected(self):
        self.remove_artifact()
        self.manifest["archive_url"] = "http://example.invalid/runtime.tar.gz"
        (self.package / bridge.MANIFEST).write_text(json.dumps(self.manifest))
        with patch.object(bridge.urllib.request, "urlopen") as download:
            with self.assertRaisesRegex(ValueError, "HTTPS"):
                bridge.install(self.package)
            download.assert_not_called()

    def test_missing_manifest_never_downloads(self):
        (self.package / bridge.MANIFEST).unlink()
        with patch.object(bridge.urllib.request, "urlopen") as download:
            with self.assertRaisesRegex(ValueError, "Missing artifact manifest"):
                bridge.install(self.package)
            download.assert_not_called()


if __name__ == "__main__":
    unittest.main()
