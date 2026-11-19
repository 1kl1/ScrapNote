import test from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import pg from 'pg';
import { Repository } from '../src/repository.js';
import { sha256 } from '../src/protocol.js';
import { verifyPassword } from '../src/auth.js';

test('PostgreSQL atomic revisions, tenant isolation, immutable blobs and rollback', { skip: !process.env.TEST_DATABASE_URL }, async () => {
  const admin = new pg.Pool({ connectionString: process.env.TEST_DATABASE_URL });
  const schema = 'test_' + randomUUID().replaceAll('-', '');
  await admin.query(`CREATE SCHEMA ${schema}`);
  const url = new URL(process.env.TEST_DATABASE_URL); url.searchParams.set('options', `-c search_path=${schema}`);
  const repository = new Repository(url.toString());
  try {
    await repository.initialize('a@example.com', 'first test password long');
    await repository.initialize('a@example.com', 'different test password');
    await repository.initialize('b@example.com', 'second test password long');
    const a = await repository.findUser('a@example.com'); const b = await repository.findUser('b@example.com');
    assert.equal(await verifyPassword('first test password long', a.password_hash), true);
    const bytes = Buffer.from('original'); const digest = sha256(bytes);
    await repository.storeBlob(a.id, digest, bytes, null);
    await repository.storeBlob(a.id, digest, Buffer.from('replacement'), null);
    assert.deepEqual((await repository.blob(a.id, digest)).content, bytes);
    assert.equal(await repository.blob(b.id, digest), undefined);
    await assert.rejects(repository.commit(b.id, 0, { 'scraps/a.md': digest }), e => e.code === 'missing_blob');
    assert.deepEqual(await repository.manifest(b.id), { revision: 0, entries: {} });
    const results = await Promise.allSettled([
      repository.commit(a.id, 0, { 'scraps/a.md': digest }),
      repository.commit(a.id, 0, { 'notes/b.md': digest }),
    ]);
    assert.equal(results.filter(r => r.status === 'fulfilled').length, 1);
    assert.equal(results.find(r => r.status === 'rejected').reason.code, 'revision_conflict');
    assert.equal((await repository.manifest(a.id)).revision, 1);
    await assert.rejects(repository.commit(a.id, 1, { 'assets/sha256/ab/a.png': digest }), e => e.code === 'invalid_storage');
    assert.equal((await repository.manifest(a.id)).revision, 1);
    const sessionHash = sha256('session');
    await repository.createSession(a.id, sessionHash, new Date(Date.now() + 60000));
    assert.equal((await repository.session(sessionHash)).id, a.id);
    await repository.revoke(sessionHash);
    assert.equal(await repository.session(sessionHash), undefined);
    const image = Buffer.from('photo'); const imageDigest = sha256(image); let uploads = 0;
    await Promise.all([1, 2].map(() => repository.storeBlob(a.id, imageDigest, image, async () => { uploads++; return 'zipline-file'; })));
    assert.equal(uploads, 1);
    assert.equal((await repository.blob(a.id, imageDigest)).content, null);
  } finally {
    await repository.close(); await admin.query(`DROP SCHEMA ${schema} CASCADE`); await admin.end();
  }
});
