import test from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import pg from 'pg';
import { Repository } from '../src/repository.js';
import { sha256 } from '../src/protocol.js';
import { hashPassword, verifyPassword } from '../src/auth.js';

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
    const sessionA = sha256('reset-session-a'); const sessionB = sha256('reset-session-b');
    await repository.createSession(a.id, sessionA, new Date(Date.now() + 60000));
    await repository.createSession(b.id, sessionB, new Date(Date.now() + 60000));
    const code = sha256('reset-token'); const nextHash = await hashPassword('new forgotten password fixture');
    assert.equal(await repository.issuePasswordReset(a.id, code, new Date(Date.now() + 60000)), true);
    assert.equal(await repository.issuePasswordReset(a.id, sha256('too soon'), new Date(Date.now() + 60000)), false);
    assert.equal(await repository.resetPassword(b.email, code, nextHash), false);
    assert.equal(await repository.resetPassword(a.email, sha256('wrong token'), nextHash), false);
    assert.equal((await repository.session(sessionA)).id, a.id);
    const resets = await Promise.all([
      repository.resetPassword(a.email, code, nextHash),
      repository.resetPassword(a.email, code, nextHash),
    ]);
    assert.deepEqual(resets.sort(), [false, true]);
    await assert.rejects(repository.createSession(a.id, sha256('stale login'), new Date(Date.now() + 60000), a.password_hash), e => e.code === 'invalid_credentials');
    assert.equal(await repository.session(sha256('stale login')), undefined);
    assert.equal(await repository.session(sessionA), undefined);
    assert.equal((await repository.session(sessionB)).id, b.id);
    assert.equal(await verifyPassword('new forgotten password fixture', (await repository.findUser(a.email)).password_hash), true);
    assert.equal(await repository.resetPassword(a.email, code, nextHash), false);
    assert.equal(await repository.issuePasswordReset(a.id, code, new Date(Date.now() - 1000)), true);
    assert.equal(await repository.resetPassword(a.email, code, nextHash), false);
    await repository.pool.query("UPDATE password_resets SET issued_at=now()-interval '2 minutes' WHERE user_id=$1", [a.id]);
    const replacement = sha256('replacement token');
    assert.equal(await repository.issuePasswordReset(a.id, replacement, new Date(Date.now() + 60000)), true);
    assert.equal(await repository.resetPassword(a.email, code, nextHash), false);
    assert.equal(await repository.resetPassword(a.email, replacement, nextHash), true);
    const image = Buffer.from('photo'); const imageDigest = sha256(image); let uploads = 0;
    await Promise.all([1, 2].map(() => repository.storeBlob(a.id, imageDigest, image, async () => { uploads++; return 'zipline-file'; })));
    assert.equal(uploads, 1);
    assert.equal((await repository.blob(a.id, imageDigest)).content, null);
  } finally {
    await repository.close(); await admin.query(`DROP SCHEMA ${schema} CASCADE`); await admin.end();
  }
});

test('PostgreSQL capture commits serialize with desktop, isolate owners and replay after deletion', { skip: !process.env.TEST_DATABASE_URL }, async () => {
  const { captureChange } = await import('../src/capture.js');
  const admin = new pg.Pool({ connectionString: process.env.TEST_DATABASE_URL });
  const schema = 'test_' + randomUUID().replaceAll('-', '');
  await admin.query(`CREATE SCHEMA ${schema}`);
  const url = new URL(process.env.TEST_DATABASE_URL); url.searchParams.set('options', `-c search_path=${schema}`);
  const repository = new Repository(url.toString());
  try {
    await repository.initialize('capture@example.com', 'capture test password long');
    await repository.initialize('other@example.com', 'capture test password long');
    const owner = (await repository.findUser('capture@example.com')).id;
    const other = (await repository.findUser('other@example.com')).id;
    const content = Buffer.from('phone'); const digest = sha256(content);
    await repository.storeBlob(owner, digest, content, null);
    await repository.commit(owner, 0, { 'notes/pc.md': digest, 'expenses/pc.json': digest });
    const first = captureChange({ operation_id: randomUUID(), path: 'scraps/phone.md', base: null, digest, assets: {} });
    const results = await Promise.allSettled([
      repository.capture(owner, first),
      repository.commit(owner, 1, { 'notes/new.md': digest, 'expenses/pc.json': digest }),
    ]);
    assert.equal(results[0].status, 'fulfilled');
    const current = await repository.manifest(owner);
    assert.equal(current.entries['scraps/phone.md'], digest);
    assert.equal(current.entries['expenses/pc.json'], digest);
    const before = current.revision;
    await repository.capture(owner, first);
    assert.equal((await repository.manifest(owner)).revision, before);
    await repository.capture(owner, captureChange({ operation_id: randomUUID(), path: first.path, base: digest, digest: null, assets: {} }));
    await repository.capture(owner, first);
    assert.equal((await repository.manifest(owner)).entries[first.path], undefined);
    assert.deepEqual(await repository.captureStatus(other, [first.path]), { [first.path]: null });
    await assert.rejects(repository.capture(other, first), error => error.code === 'missing_blob');
    assert.deepEqual((await repository.manifest(other)).entries, {});
    await assert.rejects(repository.capture(owner, captureChange({ operation_id: randomUUID(), path: 'scraps/missing.md', base: null, digest: 'e'.repeat(64), assets: {} })), error => error.code === 'missing_blob');
    assert.equal((await repository.manifest(owner)).entries['scraps/missing.md'], undefined);
  } finally {
    await repository.close(); await admin.query(`DROP SCHEMA ${schema} CASCADE`); await admin.end();
  }
});
