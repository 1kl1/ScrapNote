import json
from pathlib import Path
import tempfile
import unittest
from urllib.parse import urlsplit
from local_import import MigrationError, migrate, scan


class MemoryApi:
    identity = 'https://api.example/owner'
    def __init__(self):
        self.manifest = {'revision': 0, 'entries': {}}
        self.blobs = {}
        self.corrupt = False
        self.on_upload = None
    def json(self, method, path, data=None):
        if method == 'PUT':
            assert data['expected_revision'] == self.manifest['revision']
            self.manifest = {'revision': self.manifest['revision'] + 1, 'entries': dict(data['entries'])}
        return dict(self.manifest)
    def request(self, method, path, data=None, raw=False):
        digest = urlsplit(path).path.rsplit('/', 1)[-1]
        if method == 'PUT':
            self.blobs[digest] = data
            if self.on_upload:
                self.on_upload()
            return b''
        return b'corrupted' if self.corrupt else self.blobs[digest]


class LocalMigrationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(); self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.vault = self.root / 'vault'; self.vault.mkdir()
        self.report = self.root / 'report.json'; self.api = MemoryApi()
        self.write('scraps/a.md', 'local latest')
        self.write('notes/travel/n.md', 'note')
        self.write('expenses/a.json', '{"amount":1234}')
        self.write('expenses/.settings/summary.json', '{}')
        self.write('assets/sha256/ab/a.png', 'photo')
        self.write('.trash/a.md', 'not synchronized')
        self.write('.sync/state.json', '{"identity":"old-supabase/owner","entries":{}}')
        (self.vault / 'notes/empty').mkdir()
    def write(self, name, text):
        p = self.vault / name; p.parent.mkdir(parents=True, exist_ok=True); p.write_text(text)
    def test_migrates_local_bytes_and_binds_only_after_verification(self):
        original_state = (self.vault / '.sync/state.json').read_bytes()
        original_entries = scan(self.vault)
        result = migrate(self.api, self.vault, self.report, bind=True)
        self.assertEqual(result['entries'], original_entries)
        self.assertEqual(result['counts'], {'scraps': 1, 'notes': 1, 'expenses': 2, 'assets': 1})
        self.assertEqual(result['folders'], 2)
        state = json.loads((self.vault / '.sync/state.json').read_text())
        self.assertEqual(state['identity'], self.api.identity)
        self.assertEqual(state['entries'], original_entries)
        self.assertEqual(self.report.with_suffix('.previous-state.json').read_bytes(), original_state)
        self.assertEqual(scan(self.vault), original_entries)
    def test_corrupt_download_never_binds_or_marks_complete(self):
        old = (self.vault / '.sync/state.json').read_bytes(); self.api.corrupt = True
        with self.assertRaises(MigrationError): migrate(self.api, self.vault, self.report, bind=True)
        self.assertEqual((self.vault / '.sync/state.json').read_bytes(), old)
        self.assertFalse(self.report.exists())
    def test_refuses_to_overwrite_different_destination(self):
        self.api.manifest = {'revision': 2, 'entries': {'notes/empty': 'directory'}}
        with self.assertRaises(MigrationError): migrate(self.api, self.vault, self.report)
        self.assertFalse(self.api.blobs)
    def test_changed_local_snapshot_does_not_commit(self):
        self.api.on_upload = lambda: self.write('scraps/new.md', 'changed')
        with self.assertRaises(MigrationError): migrate(self.api, self.vault, self.report)
        self.assertEqual(self.api.manifest['revision'], 0)
    def test_completed_import_can_be_reverified_without_overwrite(self):
        migrate(self.api, self.vault, self.report)
        revision = self.api.manifest['revision']
        migrate(self.api, self.vault, self.root / 'verification.json')
        self.assertEqual(self.api.manifest['revision'], revision)
    def test_rejects_symlinks(self):
        (self.vault / 'scraps/link.md').symlink_to(self.vault / 'scraps/a.md')
        with self.assertRaises(MigrationError): scan(self.vault)


if __name__ == '__main__': unittest.main()
