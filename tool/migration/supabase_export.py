#!/usr/bin/env python3
"""Export Scrapnote's authenticated Supabase vault without modifying the source.

Python 3.10+, standard library only. See docs/oracle-migration.md.
"""

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import sys
from datetime import datetime, timezone
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode, urlsplit
from urllib.request import HTTPRedirectHandler, Request, build_opener
from uuid import UUID

MAX_FILE_BYTES = 25 * 1024 * 1024
MAX_MANIFEST_BYTES = 4 * 1024 * 1024
DIGEST = re.compile(r"[a-f0-9]{64}\Z")
DIRECTORY = "directory"


class MigrationError(Exception):
    """An error safe to display without including credentials or document text."""


def validate_manifest(manifest):
    if not isinstance(manifest, dict):
        raise MigrationError("Invalid manifest.")
    revision = manifest.get("revision")
    entries = manifest.get("entries")
    if type(revision) is not int or revision < 0 or not isinstance(entries, dict):
        raise MigrationError("Invalid manifest revision or entries.")
    if revision == 0 and entries:
        raise MigrationError("An uninitialized manifest cannot contain files.")
    for name, digest in entries.items():
        if not isinstance(name, str) or not isinstance(digest, str):
            raise MigrationError("Invalid manifest entry.")
        parts = name.split("/")
        if (len(parts) < 2 or len(name) > 1024 or
                any(not s or s in (".", "..") or re.search(r"[\\:\x00-\x1f]", s)
                    for s in parts)):
            raise MigrationError("Unsafe vault path.")
        allowed = False
        if parts[0] in ("scraps", "notes"):
            allowed = (not any(s.startswith(".") for s in parts[1:]) and
                       (name.endswith(".md") or
                        (parts[0] == "notes" and digest == DIRECTORY)))
        elif parts[0] == "assets":
            allowed = len(parts) == 4 and parts[1] == "sha256"
        elif parts[0] == "expenses":
            allowed = (name == "expenses/.settings/summary.json" or
                       (len(parts) == 2 and parts[-1].endswith(".json") and
                        not parts[-1].startswith(".")))
        if not allowed or name.endswith(".tmp"):
            raise MigrationError("File outside the synchronized vault.")
        if digest == DIRECTORY:
            if parts[0] != "notes":
                raise MigrationError("Only note folders may be synchronized.")
        elif not DIGEST.fullmatch(digest):
            raise MigrationError("Invalid blob digest.")
        for index in range(1, len(parts)):
            parent = "/".join(parts[:index])
            if parent in entries and entries[parent] != DIRECTORY:
                raise MigrationError("A vault file is also used as a directory.")
    return {"revision": revision, "entries": entries}


def read_json(path, limit=MAX_MANIFEST_BYTES * 2 + 16384):
    if path.is_symlink() or not path.is_file():
        raise MigrationError("Expected a regular JSON file.")
    with path.open("rb") as stream:
        data = stream.read(limit + 1)
    if len(data) > limit:
        raise MigrationError("JSON file exceeds the size limit.")
    try:
        return json.loads(data)
    except (ValueError, UnicodeError) as error:
        raise MigrationError("Invalid JSON.") from error


def write_json(path, value):
    # Exclusive creation prevents replacing an existing backup or following a link.
    with path.open("x", encoding="utf-8") as stream:
        json.dump(value, stream, ensure_ascii=False, indent=2)
        stream.write("\n")
        stream.flush()
        os.fsync(stream.fileno())


class NoRedirects(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        # Never forward the API key or access token to a redirect target.
        return None


class SupabaseSource:
    def __init__(self, config):
        url = config.get("supabase_url", "").rstrip("/")
        parsed = urlsplit(url)
        if (parsed.scheme != "https" or not parsed.hostname or parsed.username or
                parsed.password or parsed.path or parsed.query or parsed.fragment):
            raise MigrationError("supabase_url must be an HTTPS origin.")
        self.url = url
        self.key = config.get("supabase_publishable_key", "")
        if not isinstance(self.key, str) or not self.key:
            raise MigrationError("Missing supabase_publishable_key.")
        self.token = config.get("access_token")
        self.refresh_token = None
        self.opener = build_opener(NoRedirects())
        if not self.token:
            email, password = config.get("email"), config.get("password")
            if not email or not password:
                raise MigrationError("Provide email/password or access_token in the config file.")
            self._set_session(self._json(
                "/auth/v1/token?grant_type=password",
                {"email": email, "password": password},
            ))
        user = self._json("/auth/v1/user")
        try:
            self.user_id = str(UUID(user["id"]))
        except (KeyError, TypeError, ValueError) as error:
            raise MigrationError("Could not identify the authenticated owner.") from error
        self.identity = f"{self.url}/{self.user_id}"

    def _set_session(self, session):
        self.token = session["access_token"]
        self.refresh_token = session.get("refresh_token")

    def _request(self, path, data=None, limit=MAX_FILE_BYTES, retry=True):
        headers = {"apikey": self.key}
        if self.token:
            headers["Authorization"] = f"Bearer {self.token}"
        if data is not None:
            headers["Content-Type"] = "application/json"
        request = Request(self.url + path, headers=headers,
                          data=None if data is None else json.dumps(data).encode())
        try:
            with self.opener.open(request, timeout=90) as response:
                content = response.read(limit + 1)
        except HTTPError as error:
            status = error.code
            error.close()
            if status == 401 and retry and self.refresh_token:
                session = self._json(
                    "/auth/v1/token?grant_type=refresh_token",
                    {"refresh_token": self.refresh_token}, retry=False,
                )
                self._set_session(session)
                return self._request(path, data, limit, retry=False)
            raise MigrationError(f"Supabase request failed (HTTP {status}).") from None
        except (URLError, TimeoutError, OSError):
            raise MigrationError("Could not connect to Supabase.") from None
        if len(content) > limit:
            raise MigrationError("Supabase response exceeds the size limit.")
        return content

    def _json(self, path, data=None, retry=True):
        try:
            return json.loads(self._request(path, data, MAX_MANIFEST_BYTES + 16384, retry))
        except (ValueError, UnicodeError):
            raise MigrationError("Supabase returned invalid JSON.") from None

    def manifest(self):
        query = urlencode({"user_id": f"eq.{self.user_id}",
                           "select": "revision,entries"})
        rows = self._json(f"/rest/v1/vault_manifests?{query}")
        if not isinstance(rows, list) or len(rows) > 1:
            raise MigrationError("Unexpected manifest response.")
        return validate_manifest(rows[0] if rows else {"revision": 0, "entries": {}})

    def download(self, digest):
        if not DIGEST.fullmatch(digest):
            raise MigrationError("Invalid blob digest.")
        return self._request(f"/storage/v1/object/authenticated/vault-blobs/{self.user_id}/{digest}")


def export_bundle(source, output):
    manifest = validate_manifest(source.manifest())
    # Refuse existing destinations, including links and incomplete exports.
    output.mkdir(mode=0o700, parents=False, exist_ok=False)
    blobs = output / "blobs"
    blobs.mkdir(mode=0o700)
    write_json(output / "manifest.json", {
        "format": "scrapnote-vault-export-v1",
        "source_identity": source.identity,
        "exported_at": datetime.now(timezone.utc).isoformat(),
        **manifest,
    })
    total_bytes = 0
    digests = sorted(set(manifest["entries"].values()) - {DIRECTORY})
    for digest in digests:
        content = source.download(digest)
        if len(content) > MAX_FILE_BYTES or hashlib.sha256(content).hexdigest() != digest:
            raise MigrationError("Downloaded blob failed integrity verification; export is incomplete.")
        with (blobs / digest).open("xb") as stream:
            stream.write(content)
            stream.flush()
            os.fsync(stream.fileno())
        total_bytes += len(content)
    if manifest != validate_manifest(source.manifest()):
        raise MigrationError("Source changed during export. Stop device sync and export again to a new folder.")
    summary = {"files": sum(d != DIRECTORY for d in manifest["entries"].values()),
               "folders": sum(d == DIRECTORY for d in manifest["entries"].values()),
               "unique_blobs": len(digests), "bytes": total_bytes,
               "manifest_sha256": hashlib.sha256((output / "manifest.json").read_bytes()).hexdigest()}
    # This marker is written last. Its absence means the export must not be imported.
    write_json(output / "COMPLETE.json", summary)
    return verify_bundle(output)


def verify_bundle(bundle):
    if bundle.is_symlink() or not bundle.is_dir():
        raise MigrationError("Expected a regular export directory.")
    complete = read_json(bundle / "COMPLETE.json")
    raw = read_json(bundle / "manifest.json")
    if (not isinstance(complete, dict) or not isinstance(raw, dict) or
            raw.get("format") != "scrapnote-vault-export-v1" or
            not isinstance(raw.get("source_identity"), str)):
        raise MigrationError("Unsupported export format.")
    actual_manifest_digest = hashlib.sha256((bundle / "manifest.json").read_bytes()).hexdigest()
    if actual_manifest_digest != complete.get("manifest_sha256"):
        raise MigrationError("Manifest checksum mismatch.")
    manifest = validate_manifest(raw)
    blobs = bundle / "blobs"
    if blobs.is_symlink() or not blobs.is_dir():
        raise MigrationError("Expected a regular blobs directory.")
    digests = set(manifest["entries"].values()) - {DIRECTORY}
    total_bytes = 0
    for digest in sorted(digests):
        blob = blobs / digest
        if blob.is_symlink() or not blob.is_file():
            raise MigrationError("Missing blob or symbolic link in export.")
        with blob.open("rb") as stream:
            content = stream.read(MAX_FILE_BYTES + 1)
        if len(content) > MAX_FILE_BYTES or hashlib.sha256(content).hexdigest() != digest:
            raise MigrationError("Blob checksum mismatch.")
        total_bytes += len(content)
    expected = {"files": sum(d != DIRECTORY for d in manifest["entries"].values()),
                "folders": sum(d == DIRECTORY for d in manifest["entries"].values()),
                "unique_blobs": len(digests), "bytes": total_bytes,
                "manifest_sha256": actual_manifest_digest}
    if complete != expected:
        raise MigrationError("Export counts do not match the manifest.")
    return expected


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    export = commands.add_parser("export")
    export.add_argument("--config", type=Path, required=True)
    export.add_argument("--output", type=Path, required=True)
    verify = commands.add_parser("verify")
    verify.add_argument("bundle", type=Path)
    args = parser.parse_args()
    os.umask(0o077)
    try:
        if args.command == "export":
            config = read_json(args.config, limit=65536)
            if not isinstance(config, dict):
                raise MigrationError("Config must be a JSON object.")
            summary = export_bundle(SupabaseSource(config), args.output)
        else:
            summary = verify_bundle(args.bundle)
        print(json.dumps(summary, ensure_ascii=False))
    except MigrationError as error:
        print(f"Migration stopped: {error}", file=sys.stderr)
        return 1
    except (OSError, ValueError, KeyError, TypeError):
        # Do not print raw exceptions: upstream errors can contain secrets.
        print("Migration stopped: check config, output path and permissions. Source data was not changed.",
              file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
