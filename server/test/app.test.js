import test from 'node:test';
import assert from 'node:assert/strict';
import { buildApp } from '../src/app.js';
import { hashPassword } from '../src/auth.js';
import { ApiError, sha256, validateEntries } from '../src/protocol.js';

class MemoryRepository {
  users = []; sessions = new Map(); manifests = new Map(); blobs = new Map();
  async ping() {}
  async findUser(email) { return this.users.find(u => u.email === email); }
  async changePassword(id, oldHash, newHash) { const user = this.users.find(u => u.id === id && u.password_hash === oldHash); if (!user) return false; user.password_hash = newHash; return true; }
  async createSession(id, hash, expires) { this.sessions.set(hash, { id, expires }); return this.users.find(u => u.id === id); }
  async session(hash) { const s = this.sessions.get(hash); return s && new Date(s.expires) > new Date() ? this.users.find(u => u.id === s.id) : null; }
  async revoke(hash) { this.sessions.delete(hash); }
  async manifest(owner) { return this.manifests.get(owner) ?? { revision: 0, entries: {} }; }
  async blob(owner, digest) { return this.blobs.get(`${owner}/${digest}`); }
  async storeBlob(owner, digest, bytes, upload) {
    const key = `${owner}/${digest}`;
    if (!this.blobs.has(key)) this.blobs.set(key, { size: bytes.length, content: upload ? null : bytes, zipline_id: upload ? await upload() : null });
  }
  async commit(owner, revision, entries) {
    if ((await this.manifest(owner)).revision !== revision) throw new ApiError(409, 'revision_conflict', 'Conflict');
    for (const digest of Object.values(entries)) if (digest !== 'directory' && !await this.blob(owner, digest)) throw new ApiError(400, 'missing_blob', 'Missing');
    this.manifests.set(owner, { revision: revision + 1, entries }); return revision + 1;
  }
}

async function fixture(t) {
  const repository = new MemoryRepository();
  const password = 'a strong fixture password';
  const hash = await hashPassword(password);
  repository.users = ['a', 'b'].map(id => ({ id, email: `${id}@example.com`, password_hash: hash, created_at: new Date().toISOString() }));
  const pictures = new Map();
  const zipline = {
    async upload(owner, digest, bytes) { const id = owner + digest; pictures.set(id, bytes); return id; },
    async download(owner, digest, id) { return pictures.get(id); },
  };
  const app = await buildApp({ repository, zipline }); t.after(() => app.close());
  async function login(email = 'a@example.com', pass = password) {
    return app.inject({ method: 'POST', url: '/v1/auth/login', payload: { email, password: pass } });
  }
  const a = (await login()).json().access_token;
  const b = (await login('b@example.com')).json().access_token;
  const request = (method, url, payload, token = a, raw = false) => app.inject({ method, url, payload,
    headers: { authorization: `Bearer ${token}`, ...(raw ? { 'content-type': 'application/octet-stream' } : {}) } });
  return { repository, pictures, app, request, login, a, b };
}

test('login, owner isolation, logout and no public signup', async t => {
  const { app, request, login, a } = await fixture(t);
  assert.equal((await app.inject('/v1/manifest')).statusCode, 401);
  assert.equal((await login('a@example.com', 'wrong')).statusCode, 401);
  const me = await request('GET', '/v1/auth/me');
  assert.equal(me.json().user.email, 'a@example.com');
  assert.equal(me.json().user.password_hash, undefined);
  assert.equal((await app.inject({ method: 'POST', url: '/v1/auth/signup', payload: {} })).statusCode, 401);
  assert.equal((await request('POST', '/v1/auth/logout')).statusCode, 200);
  assert.equal((await request('GET', '/v1/manifest', undefined, a)).statusCode, 401);
});

test('documents and settings round-trip; missing blobs and stale commits fail', async t => {
  const { request, b } = await fixture(t);
  const bytes = Buffer.from('{"currency":"USD","amount":1245}'); const digest = sha256(bytes);
  assert.equal((await request('PUT', '/v1/manifest', { expected_revision: 0, entries: { 'expenses/a.json': digest } })).statusCode, 400);
  assert.equal((await request('PUT', `/v1/blobs/${digest}?path=expenses/a.json`, bytes, undefined, true)).statusCode, 204);
  const entries = { 'expenses/a.json': digest, 'expenses/.settings/summary.json': digest, 'notes/empty': 'directory' };
  assert.equal((await request('PUT', '/v1/manifest', { expected_revision: 0, entries })).statusCode, 200);
  assert.deepEqual((await request('GET', '/v1/manifest')).json(), { revision: 1, entries });
  assert.deepEqual((await request('GET', `/v1/blobs/${digest}`)).rawPayload, bytes);
  assert.equal((await request('GET', `/v1/blobs/${digest}`, undefined, b)).statusCode, 404);
  assert.deepEqual((await request('GET', '/v1/manifest', undefined, b)).json().entries, {});
  assert.equal((await request('PUT', '/v1/manifest', { expected_revision: 0, entries })).statusCode, 409);
});

test('image bytes use Zipline and retrying upload does not create duplicates', async t => {
  const { request, repository, pictures } = await fixture(t);
  const bytes = Buffer.from('image fixture'); const digest = sha256(bytes);
  const url = `/v1/blobs/${digest}?path=assets/sha256/ab/photo.png`;
  for (let i = 0; i < 2; i++) assert.equal((await request('PUT', url, bytes, undefined, true)).statusCode, 204);
  assert.equal(pictures.size, 1);
  assert.equal((await repository.blob('a', digest)).content, null);
  assert.deepEqual((await request('GET', `/v1/blobs/${digest}`)).rawPayload, bytes);
});

test('hash mismatch and unsafe paths are rejected before storage', async t => {
  const { request, repository } = await fixture(t);
  const bytes = Buffer.from('original'); const digest = sha256(bytes);
  assert.equal((await request('PUT', `/v1/blobs/${digest}?path=scraps/a.md`, Buffer.from('changed'), undefined, true)).statusCode, 400);
  assert.equal((await request('PUT', `/v1/blobs/${digest}?path=scraps/../a.md`, bytes, undefined, true)).statusCode, 400);
  assert.equal(repository.blobs.size, 0);
  for (const entries of [ { 'notes/a.md': digest, 'notes/a.md/b.md': digest }, { '.sync/state.json': digest }, { 'notes/private.txt': digest }, { 'expenses/a.json': 'directory' } ]) {
    assert.throws(() => validateEntries(entries));
  }
});

test('login attempts are rate limited', async t => {
  const { login } = await fixture(t);
  let response;
  for (let i = 0; i < 11; i++) response = await login('unknown@example.com', 'wrong');
  assert.equal(response.statusCode, 429);
});


test('password change checks current password and preserves sessions', async t => {
  const { app, request, login, a } = await fixture(t);
  const url = '/v1/auth/password';
  const next = 'a new sufficiently long password';
  assert.equal((await app.inject({ method: 'POST', url, payload: {} })).statusCode, 401);
  assert.equal((await request('POST', url, { current_password: 'wrong', new_password: next })).json().code, 'incorrect_password');
  assert.equal((await request('POST', url, { current_password: 'a strong fixture password', new_password: 'short' })).statusCode, 400);
  assert.equal((await request('POST', url, { current_password: 'a strong fixture password', new_password: next })).statusCode, 200);
  assert.equal((await request('GET', '/v1/auth/me', undefined, a)).statusCode, 200);
  assert.equal((await login('a@example.com', 'a strong fixture password')).statusCode, 401);
  assert.equal((await login('a@example.com', next)).statusCode, 200);
});
