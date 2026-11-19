#!/usr/bin/env python3
"""Initialize a fresh Scrapnote API from the authoritative local Vault."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import sys
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode, urlsplit
from urllib.request import Request, build_opener

from supabase_export import (DIRECTORY, MAX_FILE_BYTES, MigrationError, NoRedirects,
                             read_json, validate_manifest)


def scan(vault):
    if vault.is_symlink() or not vault.is_dir():
        raise MigrationError('Vault must be a regular directory.')
    entries = {}
    for folder in ('scraps', 'notes', 'assets', 'expenses'):
        root = vault / folder
        if root.is_symlink():
            raise MigrationError('Vault directories must not be symbolic links.')
        if not root.exists():
            continue
        for current, dirs, files in os.walk(root, followlinks=False):
            for name in dirs + files:
                file = Path(current) / name
                relative = file.relative_to(vault).as_posix()
                if file.is_symlink():
                    raise MigrationError('Symbolic links are not migrated.')
                if file.is_dir():
                    if folder != 'notes':
                        continue
                    digest = DIRECTORY
                else:
                    # Validate scope before reading, including hidden/temp files.
                    try:
                        validate_manifest({'revision': 1, 'entries': {relative: '0' * 64}})
                    except MigrationError:
                        continue
                    if file.stat().st_size > MAX_FILE_BYTES:
                        raise MigrationError('A Vault file exceeds 25 MiB; optimize it in Scrapnote first.')
                    digest = hashlib.sha256(file.read_bytes()).hexdigest()
                try:
                    validate_manifest({'revision': 1, 'entries': {relative: digest}})
                except MigrationError:
                    continue
                entries[relative] = digest
    validate_manifest({'revision': 1, 'entries': entries})
    return entries


class Api:
    def __init__(self, config):
        self.url = config['url'].rstrip('/')
        url = urlsplit(self.url)
        if url.scheme != 'https' or not url.hostname or url.path or url.query or url.fragment or url.username:
            raise MigrationError('API URL must be an HTTPS origin.')
        self.opener = build_opener(NoRedirects())
        self.token = None
        session = self.json('POST', '/v1/auth/login', {'email': config['email'], 'password': config['password']})
        self.token = session['access_token']
        self.user_id = session['user']['id']
        self.identity = self.url + '/' + self.user_id

    def request(self, method, path, data=None, raw=False):
        headers = {}
        if self.token:
            headers['Authorization'] = 'Bearer ' + self.token
        if data is not None:
            headers['Content-Type'] = 'application/octet-stream' if raw else 'application/json'
            if not raw:
                data = json.dumps(data).encode()
        try:
            with self.opener.open(Request(self.url + path, method=method, headers=headers, data=data), timeout=240) as response:
                content = response.read(MAX_FILE_BYTES + 1)
                if len(content) > MAX_FILE_BYTES:
                    raise MigrationError('Server response exceeded the file size limit.')
                return content
        except HTTPError as error:
            status = error.code
            error.close()
            raise MigrationError(f'API request failed (HTTP {status}); source files are unchanged.') from None
        except (URLError, TimeoutError):
            raise MigrationError('API connection failed; retry using the same local snapshot.') from None

    def json(self, method, path, data=None):
        return json.loads(self.request(method, path, data))

    def close(self):
        if self.token:
            self.request('POST', '/v1/auth/logout')
            self.token = None


def migrate(api, vault, report, bind=False):
    entries = scan(vault)
    if not entries:
        raise MigrationError('Refusing to initialize from an empty local Vault.')
    initial = validate_manifest(api.json('GET', '/v1/manifest'))
    if initial['revision'] != 0 and initial['entries'] != entries:
        raise MigrationError('Destination already contains different data; refusing to overwrite it.')
    files = {digest: name for name, digest in entries.items() if digest != DIRECTORY}
    # If bytes happen to be reused by a document and an asset, route them to Zipline.
    files.update({digest: name for name, digest in entries.items() if name.startswith('assets/')})
    if initial['revision'] == 0:
        for index, (digest, name) in enumerate(files.items(), 1):
            data = (vault / name).read_bytes()
            if hashlib.sha256(data).hexdigest() != digest:
                raise MigrationError('Local data changed during migration.')
            api.request('PUT', f'/v1/blobs/{digest}?' + urlencode({'path': name}), data, raw=True)
            if index % 10 == 0 or index == len(files):
                print(f'Uploaded {index}/{len(files)} unique files', flush=True)
        if scan(vault) != entries:
            raise MigrationError('Local data changed; manifest was not committed. Take a fresh snapshot.')
        api.json('PUT', '/v1/manifest', {'expected_revision': 0, 'entries': entries})
    remote = validate_manifest(api.json('GET', '/v1/manifest'))
    if remote['entries'] != entries:
        raise MigrationError('Destination manifest does not match the local snapshot.')
    total = 0
    for index, digest in enumerate(files, 1):
        data = api.request('GET', f'/v1/blobs/{digest}')
        if hashlib.sha256(data).hexdigest() != digest:
            raise MigrationError('Downloaded data does not match the original.')
        total += len(data)
        if index % 10 == 0 or index == len(files):
            print(f'Verified {index}/{len(files)} unique files', flush=True)
    if api.json('GET', '/v1/manifest') != remote or scan(vault) != entries:
        raise MigrationError('Source or destination changed during verification; not binding the Vault.')
    now = datetime.now(timezone.utc).isoformat()
    result = {'identity': api.identity, 'revision': remote['revision'], 'verified_at': now,
              'unique_blobs': len(files), 'unique_bytes': total,
              'counts': {folder: sum(name.startswith(folder + '/') and d != DIRECTORY for name, d in entries.items())
                         for folder in ('scraps', 'notes', 'expenses', 'assets')},
              'folders': sum(d == DIRECTORY for d in entries.values()), 'entries': entries}
    with report.open('x', encoding='utf8') as stream:
        json.dump(result, stream, ensure_ascii=False, indent=2)
    if bind:
        state_dir = vault / '.sync'
        if state_dir.is_symlink() or (state_dir / 'state.json').is_symlink():
            raise MigrationError('Sync state must not be a symbolic link.')
        state_dir.mkdir(exist_ok=True)
        state = state_dir / 'state.json'
        if state.exists():
            backup = report.with_suffix('.previous-state.json')
            with backup.open('xb') as stream:
                stream.write(state.read_bytes())
        temporary = state_dir / 'oracle-migration.tmp'
        with temporary.open('x') as stream:
            json.dump({'identity': api.identity, 'entries': entries, 'synced_at': now}, stream, ensure_ascii=False)
            stream.flush(); os.fsync(stream.fileno())
        temporary.replace(state)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--config', required=True, type=Path)
    parser.add_argument('--vault', required=True, type=Path)
    parser.add_argument('--report', required=True, type=Path)
    parser.add_argument('--bind', action='store_true', help='Bind this Vault only after full round-trip verification; back up prior state.')
    args = parser.parse_args()
    os.umask(0o077)
    api = None
    try:
        if args.report.exists():
            raise MigrationError('Choose a new report path; existing reports are preserved.')
        api = Api(read_json(args.config))
        result = migrate(api, args.vault, args.report, args.bind)
        print(json.dumps({k: v for k, v in result.items() if k != 'entries'}, ensure_ascii=False))
        return 0
    except MigrationError as error:
        print(str(error), file=sys.stderr); return 1
    except (OSError, ValueError, KeyError, TypeError):
        print('Migration failed. Check configuration and file permissions; no source content was deleted.', file=sys.stderr)
        return 1
    finally:
        if api:
            try: api.close()
            except (MigrationError, OSError): pass


if __name__ == '__main__':
    sys.exit(main())
