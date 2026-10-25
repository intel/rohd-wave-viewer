# Copyright (C) 2026 Intel Corporation
# SPDX-License-Identifier: BSD-3-Clause

import contextlib
import importlib.util
import io
import json
from pathlib import Path
import subprocess
import tarfile
import tempfile
import unittest
from unittest.mock import call, patch
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
            "name: dart_wellen\nversion: 0.1.2\n"
            "dependencies:\n  flutter_rust_bridge: 2.8.0\n"
        )
        for name in bridge.FILES:
            source = self.package / name
            if name.startswith("web/pkg/"):
                source = self.repository / name
            source.parent.mkdir(parents=True, exist_ok=True)
            source.write_text(f"fixture {name}\n")
        (self.package / "lib/src/rust/frb_generated.dart").write_text(
            "String get codegenVersion => '2.8.0';\n"
        )
        (self.repository / "web/pkg/wellen_bridge_bg.wasm").write_bytes(b"\0asm")
        notices = self.repository / "assets/licenses/wellen_bridge_LICENSES.txt"
        notices.parent.mkdir(parents=True)
        notices.write_text("third-party license notices\n")
        self.url = (
            "https://github.com/intel/rohd-wave-viewer/releases/download/"
            "dart-wellen-0.1.2/dart_wellen-0.1.2-web.tar.gz"
        )
        contract = {
            "version": "0.1.2",
            "bridge_version": "2.8.0",
            "profile": "release",
            "archive_url": self.url,
            "git_archive_url_template": bridge.git_archive_template(self.url, "0.1.2"),
            "files": list(bridge.FILES),
        }
        (self.package / bridge.MANIFEST).write_text(json.dumps(contract))
        with patch.object(bridge.subprocess, "run") as validate:
            with contextlib.redirect_stdout(io.StringIO()):
                bridge.prepare(self.repository, self.url)
            validate.assert_called_once_with(
                ["bash", str(self.repository / "tool/verify_bridge_release.sh")],
                check=True,
            )
        self.manifest = json.loads((self.package / bridge.BUILD_MANIFEST).read_text())
        self.archive = (self.repository / "build/dart_wellen-0.1.2-web.tar.gz").read_bytes()

    def remove_artifact(self):
        (self.package / bridge.FILES[0]).unlink()

    def response(self, data=None):
        response = io.BytesIO(self.archive if data is None else data)
        response.url = self.url
        return response

    def responses(self, archive=None):
        def respond(url, timeout):
            self.assertEqual(timeout, 60)
            if url.endswith(".json"):
                return self.response(json.dumps(self.manifest).encode())
            return self.response(archive)
        return respond

    def test_local_and_hosted_need_no_network(self):
        with patch.object(bridge.urllib.request, "urlopen") as download:
            bridge.install(self.package)
            download.assert_not_called()
        bridge.verify(self.package, self.manifest)

    def test_git_downloads_pinned_complete_bundle(self):
        for name in bridge.FILES:
            (self.package / name).unlink()
        with patch.object(bridge.urllib.request, "urlopen", side_effect=self.responses()) as download:
            bridge.install(self.package)
            self.assertEqual(download.call_args_list, [
                call(self.url + ".json", timeout=60), call(self.url, timeout=60),
            ])
        bridge.verify(self.package, self.manifest)

    def test_archive_is_reproducible(self):
        with patch.object(bridge.subprocess, "run"):
            bridge.prepare(self.repository, self.url)
        self.assertEqual(
            self.archive,
            (self.repository / "build/dart_wellen-0.1.2-web.tar.gz").read_bytes(),
        )

    def test_runner_specific_wasm_does_not_rewrite_source_contract(self):
        source_contract = (self.package / bridge.MANIFEST).read_bytes()
        (self.repository / "web/pkg/wellen_bridge_bg.wasm").write_bytes(b"\0asmCI-build")
        with patch.object(bridge.subprocess, "run"):
            bridge.prepare(self.repository, self.url)
        self.assertEqual(source_contract, (self.package / bridge.MANIFEST).read_bytes())

    def enable_git_artifacts(self):
        self.manifest["archive_url"] = (
            "https://github.com/example/viewer/releases/download/"
            "dart-wellen-0.1.2/dart_wellen-0.1.2-web.tar.gz"
        )
        self.manifest["git_archive_url_template"] = bridge.git_archive_template(
            self.manifest["archive_url"], self.manifest["version"],
        )
        contract = {
            key: value for key, value in self.manifest.items()
            if key not in ("archive_sha256", "source_commit", "files")
        }
        contract["files"] = list(bridge.FILES)
        (self.package / bridge.MANIFEST).write_text(json.dumps(contract))
        (self.package / bridge.BUILD_MANIFEST).write_text(json.dumps(self.manifest))

    def test_git_download_selects_exact_commit_and_second_install_is_offline(self):
        self.enable_git_artifacts()
        (self.repository / ".git").mkdir()
        self.remove_artifact()
        commit = "a" * 40
        self.manifest["source_commit"] = commit
        expected = self.manifest["git_archive_url_template"].replace("{commit}", commit)
        revision = subprocess.CompletedProcess([], 0, stdout=commit + "\n")
        origin = subprocess.CompletedProcess([], 0, stdout="https://github.com/example/viewer.git\n")
        with patch.object(bridge.subprocess, "run", side_effect=[revision, origin]) as git:
            with patch.object(bridge.urllib.request, "urlopen", side_effect=self.responses()) as download:
                bridge.install(self.package)
                self.assertEqual(download.call_args_list, [
                    call(expected + ".json", timeout=60), call(expected, timeout=60),
                ])
            self.assertEqual(git.call_args_list, [
                call(
                    ["git", "-C", str(self.repository), "rev-parse", "HEAD"],
                    check=True, capture_output=True, text=True,
                ),
                call(
                    ["git", "-C", str(self.repository), "remote", "get-url", "origin"],
                    check=False, capture_output=True, text=True,
                ),
            ])
        with patch.object(bridge.subprocess, "run") as git:
            with patch.object(bridge.urllib.request, "urlopen") as download:
                bridge.install(self.package)
                git.assert_not_called()
                download.assert_not_called()

    def test_hosted_files_with_git_metadata_need_neither_git_nor_download(self):
        self.enable_git_artifacts()
        with patch.object(bridge.subprocess, "run") as git:
            with patch.object(bridge.urllib.request, "urlopen") as download:
                bridge.install(self.package)
                git.assert_not_called()
                download.assert_not_called()

    def test_ci_checksums_can_differ_from_local_and_install_the_tested_bundle(self):
        self.enable_git_artifacts()
        with patch.object(bridge.subprocess, "run"):
            bridge.prepare(self.repository, self.manifest["archive_url"])
        contract = (self.package / bridge.MANIFEST).read_bytes()
        old_hash = self.manifest["archive_sha256"]
        (self.repository / "web/pkg/wellen_bridge_bg.wasm").write_bytes(b"\0asmCI-build")
        with patch.object(bridge.subprocess, "run"):
            bridge.prepare(self.repository, self.manifest["archive_url"])
        self.assertEqual(contract, (self.package / bridge.MANIFEST).read_bytes())
        self.manifest = json.loads((self.package / bridge.BUILD_MANIFEST).read_text())
        self.archive = (self.repository / "build/dart_wellen-0.1.2-web.tar.gz").read_bytes()
        self.assertNotEqual(old_hash, self.manifest["archive_sha256"])
        commit = "c" * 40
        self.manifest["source_commit"] = commit
        (self.repository / ".git").mkdir()
        (self.package / bridge.BUILD_MANIFEST).unlink()
        for name in bridge.FILES:
            (self.package / name).unlink()
        result = subprocess.CompletedProcess([], 0, stdout=commit)
        with patch.object(bridge.subprocess, "run", return_value=result):
            with patch.object(bridge.urllib.request, "urlopen", side_effect=self.responses()):
                bridge.install(self.package)
        bridge.verify_prepared(self.package, json.loads(contract))
        self.assertEqual((self.package / "web/pkg/wellen_bridge_bg.wasm").read_bytes(), b"\0asmCI-build")

    def test_git_bundle_uses_fork_origin_while_contract_stays_canonical(self):
        source_contract = (self.package / bridge.MANIFEST).read_bytes()
        (self.repository / ".git").mkdir()
        self.remove_artifact()
        commit = "f" * 40
        self.manifest["source_commit"] = commit
        (self.package / bridge.BUILD_MANIFEST).write_text(json.dumps(self.manifest))
        expected = (
            "https://github.com/desmonddak/rohd-wave-viewer/releases/download/"
            f"dart-wellen-{commit}/dart_wellen-0.1.2-web.tar.gz"
        )
        git_results = [
            subprocess.CompletedProcess([], 0, stdout=commit + "\n"),
            subprocess.CompletedProcess([], 0, stdout="git@github.com:desmonddak/rohd-wave-viewer.git\n"),
        ]
        with patch.object(bridge.subprocess, "run", side_effect=git_results):
            with patch.object(bridge.urllib.request, "urlopen", side_effect=self.responses()) as download:
                bridge.install(self.package)
        self.assertEqual(download.call_args_list, [
            call(expected + ".json", timeout=60), call(expected, timeout=60),
        ])
        self.assertEqual(source_contract, (self.package / bridge.MANIFEST).read_bytes())

    def test_wrong_commit_metadata_fails_before_archive_download(self):
        self.enable_git_artifacts()
        self.manifest["source_commit"] = "d" * 40
        (self.repository / ".git").mkdir()
        self.remove_artifact()
        result = subprocess.CompletedProcess([], 0, stdout="e" * 40)
        with patch.object(bridge.subprocess, "run", return_value=result):
            with patch.object(bridge.urllib.request, "urlopen", side_effect=self.responses()) as download:
                with self.assertRaisesRegex(ValueError, "selected Git commit"):
                    bridge.install(self.package)
                self.assertEqual(download.call_count, 1)
                self.assertTrue(download.call_args.args[0].endswith(".json"))
        self.assertFalse((self.package / bridge.FILES[0]).exists())

    def test_missing_commit_bundle_explains_the_producer_ci_requirement(self):
        self.enable_git_artifacts()
        (self.repository / ".git").write_text("gitdir: fixture\n")
        self.remove_artifact()
        result = subprocess.CompletedProcess([], 0, stdout="b" * 40)
        with patch.object(bridge.subprocess, "run", return_value=result):
            with patch.object(
                bridge.urllib.request, "urlopen",
                side_effect=urllib.error.HTTPError(self.url, 404, "Not Found", {}, None),
            ):
                with self.assertRaisesRegex(ValueError, "including Distribute commit-keyed bridge bundle"):
                    bridge.install(self.package)

    def test_git_revision_failure_does_not_fall_back_to_another_bundle(self):
        self.enable_git_artifacts()
        (self.repository / ".git").mkdir()
        self.remove_artifact()
        with patch.object(
            bridge.subprocess, "run", side_effect=subprocess.CalledProcessError(1, "git"),
        ):
            with patch.object(bridge.urllib.request, "urlopen") as download:
                with self.assertRaises(subprocess.CalledProcessError):
                    bridge.install(self.package)
                download.assert_not_called()

    def test_invalid_git_template_never_downloads(self):
        self.enable_git_artifacts()
        self.manifest["git_archive_url_template"] = (
            self.manifest["git_archive_url_template"].replace("example/viewer", "another/viewer")
        )
        (self.package / bridge.MANIFEST).write_text(json.dumps(self.manifest))
        with patch.object(bridge.urllib.request, "urlopen") as download:
            with self.assertRaisesRegex(ValueError, "Git artifact URL template"):
                bridge.install(self.package)
            download.assert_not_called()

    def test_producer_records_commit_template_without_changing_archive_bytes(self):
        source_contract = (self.package / bridge.MANIFEST).read_bytes()
        with patch.object(bridge.subprocess, "run"):
            bridge.prepare(self.repository, self.url)
        self.assertEqual(source_contract, (self.package / bridge.MANIFEST).read_bytes())
        manifest = json.loads((self.package / bridge.BUILD_MANIFEST).read_text())
        contract = json.loads(source_contract)
        for key in ("version", "bridge_version", "profile", "archive_url", "git_archive_url_template"):
            self.assertEqual(manifest[key], contract[key])
        self.assertEqual(
            self.archive,
            (self.repository / "build/dart_wellen-0.1.2-web.tar.gz").read_bytes(),
        )

    def test_producer_rejects_a_fork_release_url_without_rewriting_contract(self):
        source_contract = (self.package / bridge.MANIFEST).read_bytes()
        with self.assertRaisesRegex(ValueError, "does not match the checked-in artifact contract"):
            bridge.prepare(
                self.repository,
                "https://github.com/desmonddak/rohd-wave-viewer/releases/download/"
                "dart-wellen-0.1.2/dart_wellen-0.1.2-web.tar.gz",
            )
        self.assertEqual(source_contract, (self.package / bridge.MANIFEST).read_bytes())

    def test_bad_archive_hash_does_not_install(self):
        self.remove_artifact()
        with patch.object(bridge.urllib.request, "urlopen", side_effect=self.responses(b"bad")):
            with self.assertRaisesRegex(ValueError, "SHA-256"):
                bridge.install(self.package)
        self.assertFalse((self.package / bridge.FILES[0]).exists())

    def test_bad_file_hash_does_not_install(self):
        self.remove_artifact()
        self.manifest["files"][bridge.FILES[0]] = "0" * 64
        (self.package / bridge.MANIFEST).write_text(json.dumps(self.manifest))
        with patch.object(bridge.urllib.request, "urlopen", side_effect=self.responses()):
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
        with patch.object(bridge.urllib.request, "urlopen", side_effect=self.responses(payload)):
            with self.assertRaisesRegex(ValueError, "inventory"):
                bridge.install(self.package)
        self.assertFalse((self.repository / "outside").exists())

    def test_unpublished_bundle_fails(self):
        self.remove_artifact()
        with patch.object(
            bridge.urllib.request, "urlopen",
            side_effect=urllib.error.HTTPError(self.url, 404, "Not Found", {}, None),
        ):
            with self.assertRaisesRegex(ValueError, "No prebuilt bundle"):
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
        self.manifest["archive_url"] = (
            "https://github.com/intel/rohd-wave-viewer/releases/download/"
            "dart-wellen-0.1.0/dart_wellen-0.1.0-web.tar.gz"
        )
        self.manifest["git_archive_url_template"] = bridge.git_archive_template(
            self.manifest["archive_url"], "0.1.0",
        )
        self.manifest["files"][bridge.FILES[1]] = bridge.digest(generated.read_bytes())
        bridge.verify(self.package, self.manifest)

    def test_plain_http_download_is_rejected(self):
        self.remove_artifact()
        self.manifest["archive_url"] = "http://example.invalid/runtime.tar.gz"
        self.manifest.pop("git_archive_url_template")
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
