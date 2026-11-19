import hashlib
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from urllib.error import HTTPError

from supabase_export import (
    MigrationError, NoRedirects, SupabaseSource, export_bundle,
    validate_manifest, verify_bundle,
)


class MemorySource:
    identity = "https://source.example/11111111-1111-1111-1111-111111111111"

    def __init__(self):
        self.blobs = {}
        self.entries = {"notes/empty": "directory"}
        self.revision = 12
        self.reads = 0
        self.downloads = []
        self.changed = False
        self.corrupt = False
        for name, data in {
            "scraps/a.md": b'---\nphoto_locations: []\n---\n![a](../assets/sha256/ab/photo.png)',
            "notes/trip.md": b"# Travel\n<!-- scrap source -->",
            "expenses/a.json": '{"amount":12345,"currency":"KRW"}'.encode(),
            "expenses/.settings/summary.json": b'{"period":"weekly"}',
            "assets/sha256/ab/photo.png": b"original image bytes",
            "assets/sha256/cd/duplicate.png": b"original image bytes",
        }.items():
            digest = hashlib.sha256(data).hexdigest()
            self.blobs[digest] = data
            self.entries[name] = digest

    def manifest(self):
        self.reads += 1
        return {"revision": self.revision + int(self.changed and self.reads > 1),
                "entries": dict(self.entries)}

    def download(self, digest):
        self.downloads.append(digest)
        return b"corrupt" if self.corrupt else self.blobs[digest]


class ExportTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.output = Path(self.temp.name) / "export"
        self.source = MemorySource()

    def test_exports_all_kinds_and_empty_folders_preserving_bytes_and_paths(self):
        summary = export_bundle(self.source, self.output)
        manifest = json.loads((self.output / "manifest.json").read_text())
        self.assertEqual(manifest["entries"], self.source.entries)
        self.assertEqual(manifest["revision"], 12)
        self.assertEqual(manifest["source_identity"], self.source.identity)
        self.assertEqual(summary["files"], 6)
        self.assertEqual(summary["folders"], 1)
        self.assertEqual(summary["unique_blobs"], 5)
        self.assertEqual(len(self.source.downloads), 5)
        for digest, content in self.source.blobs.items():
            self.assertEqual((self.output / "blobs" / digest).read_bytes(), content)
        self.assertEqual(verify_bundle(self.output), summary)

    def test_no_completion_marker_when_source_changes(self):
        self.source.changed = True
        with self.assertRaisesRegex(MigrationError, "Source changed"):
            export_bundle(self.source, self.output)
        self.assertFalse((self.output / "COMPLETE.json").exists())
        with self.assertRaises(MigrationError):
            verify_bundle(self.output)

    def test_no_completion_marker_for_corrupt_download(self):
        self.source.corrupt = True
        with self.assertRaisesRegex(MigrationError, "integrity"):
            export_bundle(self.source, self.output)
        self.assertFalse((self.output / "COMPLETE.json").exists())

    def test_refuses_existing_export(self):
        export_bundle(self.source, self.output)
        original = (self.output / "manifest.json").read_bytes()
        with self.assertRaises(FileExistsError):
            export_bundle(self.source, self.output)
        self.assertEqual((self.output / "manifest.json").read_bytes(), original)

    def test_detects_tampered_manifest(self):
        export_bundle(self.source, self.output)
        with (self.output / "manifest.json").open("a") as stream:
            stream.write(" ")
        with self.assertRaisesRegex(MigrationError, "Manifest checksum"):
            verify_bundle(self.output)

    def test_detects_missing_or_corrupt_blob(self):
        export_bundle(self.source, self.output)
        blob = next((self.output / "blobs").iterdir())
        blob.write_bytes(b"changed")
        with self.assertRaisesRegex(MigrationError, "Blob checksum"):
            verify_bundle(self.output)
        blob.unlink()
        with self.assertRaisesRegex(MigrationError, "Missing blob"):
            verify_bundle(self.output)

    def test_rejects_symbolic_links(self):
        export_bundle(self.source, self.output)
        blob = next((self.output / "blobs").iterdir())
        external = Path(self.temp.name) / "external"
        blob.rename(external)
        blob.symlink_to(external)
        with self.assertRaisesRegex(MigrationError, "symbolic link"):
            verify_bundle(self.output)

    def test_detects_incorrect_counts(self):
        export_bundle(self.source, self.output)
        marker = self.output / "COMPLETE.json"
        summary = json.loads(marker.read_text())
        summary["files"] = 999
        marker.write_text(json.dumps(summary))
        with self.assertRaisesRegex(MigrationError, "counts"):
            verify_bundle(self.output)

    def test_empty_account_is_valid(self):
        self.source.entries = {}
        self.source.revision = 0
        summary = export_bundle(self.source, self.output)
        self.assertEqual(summary["unique_blobs"], 0)
        self.assertEqual(summary["files"], 0)

    def test_rejects_unsafe_or_out_of_scope_paths_before_creating_backup(self):
        digest = next(iter(self.source.blobs))
        for name in ["scraps/../../secret.md", "/scraps/a.md", "notes//a.md",
                     "notes/.draft.md", "notes/a.txt", "notes/a:b.md",
                     "notes/a\\b.md", "notes/a\x00.md", "expenses/.secret.json",
                     ".sync/state.json", "assets/sha256/a/b/c.png", ".trash/a.md"]:
            with self.subTest(name=name):
                self.source.entries = {name: digest}
                with self.assertRaises(MigrationError):
                    export_bundle(self.source, self.output)
                self.assertFalse(self.output.exists())

    def test_rejects_invalid_digest_or_directory(self):
        for entry in [{"scraps/a.md": "../outside"},
                      {"assets/sha256/ab/a.png": "directory"},
                      {"notes/a.md": "abc"}]:
            with self.subTest(entry=entry), self.assertRaises(MigrationError):
                validate_manifest({"revision": 1, "entries": entry})

    def test_rejects_file_used_as_parent(self):
        digest = next(iter(self.source.blobs))
        with self.assertRaisesRegex(MigrationError, "directory"):
            validate_manifest({"revision": 1, "entries": {
                "notes/a.md": digest, "notes/a.md/b.md": digest,
            }})


class SourceTests(unittest.TestCase):
    config = {"supabase_url": "https://source.example",
              "supabase_publishable_key": "public-key", "access_token": "secret-token"}
    user_id = "11111111-1111-1111-1111-111111111111"

    @staticmethod
    def response(value):
        return io.BytesIO(json.dumps(value).encode())

    def test_authenticated_source_only_reads_own_manifest_and_blob(self):
        requests = []
        payload = b"photo"
        digest = hashlib.sha256(payload).hexdigest()

        def open_request(request, timeout):
            requests.append(request)
            if request.full_url.endswith("/auth/v1/user"):
                return self.response({"id": self.user_id})
            if "/rest/v1/" in request.full_url:
                return self.response([{"revision": 3, "entries": {"scraps/a.md": digest}}])
            return io.BytesIO(payload)

        with patch("supabase_export.build_opener") as factory:
            factory.return_value.open.side_effect = open_request
            source = SupabaseSource(self.config)
            self.assertEqual(source.manifest()["revision"], 3)
            self.assertEqual(source.download(digest), payload)
        self.assertTrue(all(request.get_method() == "GET" for request in requests))
        self.assertTrue(all(request.get_header("Authorization") == "Bearer secret-token"
                            for request in requests))
        self.assertIn(f"user_id=eq.{self.user_id}", requests[1].full_url)
        self.assertTrue(requests[2].full_url.endswith(f"/{self.user_id}/{digest}"))

    def test_rejects_insecure_or_credential_bearing_origins(self):
        for url in ["http://source.example", "https://u:p@source.example",
                    "https://source.example/path", "https://source.example?secret=x"]:
            with self.subTest(url=url), self.assertRaises(MigrationError):
                SupabaseSource({**self.config, "supabase_url": url})

    def test_does_not_expose_upstream_error_body(self):
        with patch("supabase_export.build_opener") as factory:
            factory.return_value.open.side_effect = HTTPError(
                "https://source.example", 401, "private detail", {}, io.BytesIO(b"secret-token"))
            with self.assertRaisesRegex(MigrationError, r"\(HTTP 401\)") as caught:
                SupabaseSource(self.config)
        self.assertNotIn("secret-token", str(caught.exception))
        self.assertNotIn("private detail", str(caught.exception))

    def test_refreshes_expired_password_session_once(self):
        config = {k: v for k, v in self.config.items() if k != "access_token"}
        config.update(email="user@example.com", password="secret")
        with patch("supabase_export.build_opener") as factory:
            factory.return_value.open.side_effect = [
                self.response({"access_token": "old", "refresh_token": "refresh"}),
                self.response({"id": self.user_id}),
                HTTPError("https://source.example", 401, "expired", {}, io.BytesIO()),
                self.response({"access_token": "new", "refresh_token": "refresh2"}),
                self.response([]),
            ]
            source = SupabaseSource(config)
            self.assertEqual(source.manifest(), {"revision": 0, "entries": {}})
            self.assertEqual(source.token, "new")
            self.assertEqual(factory.return_value.open.call_count, 5)

    def test_never_forwards_credentials_to_redirects(self):
        self.assertIsNone(NoRedirects().redirect_request(None, None, 302, "", {},
                                                       "https://other.example"))


if __name__ == "__main__":
    unittest.main()
