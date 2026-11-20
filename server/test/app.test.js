import test from 'node:test';
import assert from 'node:assert/strict';
import { buildApp } from '../src/app.js';
import { hashPassword } from '../src/auth.js';
import { ApiError, sha256, validateEntries } from '../src/protocol.js';
import { mergeCapture } from '../src/capture.js';

class MemoryRepository {
  receipts = new Map();
  resets = new Map();
  users = []; sessions = new Map(); manifests = new Map(); blobs = new Map();
  async ping() {}
  async findUser(email) { return this.users.find(u => u.email === email); }
  async changePassword(id, oldHash, newHash) { const user = this.users.find(u => u.id === id && u.password_hash === oldHash); if (!user) return false; user.password_hash = newHash; return true; }
  async issuePasswordReset(id, hash, expires) {
    const previous = this.resets.get(id);
    if (previous && previous.issued > Date.now() - 60000) return false;
    this.resets.set(id, { hash, expires, issued: Date.now() }); return true;
  }
  async resetPassword(email, hash, next) {
    const user = await this.findUser(email); const reset = this.resets.get(user?.id);
    if (!reset || reset.hash !== hash || new Date(reset.expires) <= new Date()) return false;
    user.password_hash = next; this.resets.delete(user.id);
    for (const [key, session] of this.sessions) if (session.id === user.id) this.sessions.delete(key);
    return true;
  }
  async createSession(id, hash, expires) { this.sessions.set(hash, { id, expires }); return this.users.find(u => u.id === id); }
  async session(hash) { const s = this.sessions.get(hash); return s && new Date(s.expires) > new Date() ? this.users.find(u => u.id === s.id) : null; }
  async revoke(hash) { this.sessions.delete(hash); }
  async manifest(owner) { return this.manifests.get(owner) ?? { revision: 0, entries: {} }; }
  async captureStatus(owner, paths) {
    const { entries } = await this.manifest(owner);
    return Object.fromEntries(paths.map(path => [path, entries[path] ?? null]));
  }
  async capture(owner, change) {
    const key = `${owner}/${change.operation}`;
    const receipt = this.receipts.get(key);
    if (receipt) {
      if (receipt.fingerprint !== change.fingerprint) throw new ApiError(409, 'operation_reused', 'Conflict');
      return receipt.result;
    }
    const manifest = await this.manifest(owner);
    const entries = mergeCapture(manifest.entries, change);
    await this.commit(owner, manifest.revision, entries);
    const result = { digest: change.digest };
    this.receipts.set(key, { fingerprint: change.fingerprint, result }); return result;
  }
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

async function fixture(t, { mailEnabled = true } = {}) {
  const repository = new MemoryRepository();
  const password = 'a strong fixture password';
  const hash = await hashPassword(password);
  repository.users = ['a', 'b'].map(id => ({ id, email: `${id}@example.com`, password_hash: hash, created_at: new Date().toISOString() }));
  const pictures = new Map();
  const zipline = {
    async upload(owner, digest, bytes) { const id = owner + digest; pictures.set(id, bytes); return id; },
    async download(owner, digest, id) { return pictures.get(id); },
  };
  const mail = [];
  const passwordResetMailer = mailEnabled ? { async send(email, code) { mail.push({ email, code }); } } : undefined;
  const app = await buildApp({ repository, zipline, passwordResetMailer }); t.after(() => app.close());
  async function login(email = 'a@example.com', pass = password) {
    return app.inject({ method: 'POST', url: '/v1/auth/login', payload: { email, password: pass } });
  }
  const a = (await login()).json().access_token;
  const b = (await login('b@example.com')).json().access_token;
  const request = (method, url, payload, token = a, raw = false) => app.inject({ method, url, payload,
    headers: { authorization: `Bearer ${token}`, ...(raw ? { 'content-type': 'application/octet-stream' } : {}) } });
  return { repository, pictures, app, request, login, a, b, mail };
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


test('forgotten password resets with emailed code without login and revokes only owner sessions', async t => {
  const { app, mail, repository, request, login, a, b } = await fixture(t);
  const send = email => app.inject({ method: 'POST', url: '/v1/auth/password/reset/request', payload: { email } });
  const reset = (email, code, new_password = 'new forgotten password fixture') => app.inject({ method: 'POST', url: '/v1/auth/password/reset', payload: { email, code, new_password } });
  const known = await send(' A@EXAMPLE.COM ');
  const unknown = await send('unknown@example.com');
  assert.equal(known.statusCode, 200);
  assert.deepEqual(known.json(), unknown.json());
  assert.equal(mail.length, 1);
  const code = mail[0].code;
  assert.equal(mail[0].email, 'a@example.com');
  assert.match(code, /^[A-Za-z0-9_-]{32}$/);
  assert.equal(repository.resets.get('a').hash, sha256(code));
  assert.equal((await reset('b@example.com', code)).json().code, 'invalid_reset_code');
  assert.equal((await reset('unknown@example.com', code)).json().code, 'invalid_reset_code');
  assert.equal((await reset('a@example.com', 'wrong')).json().code, 'invalid_reset_code');
  assert.equal((await reset('a@example.com', code, 'short')).statusCode, 400);
  assert.equal((await reset(' A@EXAMPLE.COM ', code)).statusCode, 200);
  assert.equal(repository.resets.has('a'), false);
  assert.equal((await reset('a@example.com', code)).json().code, 'invalid_reset_code');
  assert.equal((await request('GET', '/v1/auth/me', undefined, a)).statusCode, 401);
  assert.equal((await request('GET', '/v1/auth/me', undefined, b)).statusCode, 200);
  assert.equal((await login()).statusCode, 401);
  assert.equal((await login('a@example.com', 'new forgotten password fixture')).statusCode, 200);
});

test('reset codes expire and resending invalidates the previous code with a cooldown', async t => {
  const { app, mail, repository } = await fixture(t);
  const send = () => app.inject({ method: 'POST', url: '/v1/auth/password/reset/request', payload: { email: 'a@example.com' } });
  const reset = code => app.inject({ method: 'POST', url: '/v1/auth/password/reset', payload: { email: 'a@example.com', code, new_password: 'replacement long password' } });
  await send(); const old = mail[0].code;
  await send(); assert.equal(mail.length, 1);
  repository.resets.get('a').issued -= 61000;
  await send(); assert.equal(mail.length, 2);
  assert.equal((await reset(old)).json().code, 'invalid_reset_code');
  repository.resets.get('a').expires = new Date(Date.now() - 1000).toISOString();
  assert.equal((await reset(mail[1].code)).json().code, 'invalid_reset_code');
});

test('reset requests validate email, require mail configuration and are rate limited', async t => {
  const { app, mail } = await fixture(t);
  const send = email => app.inject({ method: 'POST', url: '/v1/auth/password/reset/request', payload: { email } });
  assert.equal((await send('invalid')).statusCode, 400);
  assert.equal(mail.length, 0);
  let response;
  for (let i = 0; i < 6; i++) response = await send('unknown@example.com');
  assert.equal(response.statusCode, 429);
  const unavailable = await fixture(t, { mailEnabled: false });
  for (const email of ['a@example.com', 'unknown@example.com']) {
    assert.equal((await unavailable.app.inject({ method: 'POST', url: '/v1/auth/password/reset/request', payload: { email } })).json().code, 'mail_unavailable');
  }
});


test('reset submissions are rate limited without a session', async t => {
  const { app } = await fixture(t);
  let response;
  for (let i = 0; i < 11; i++) response = await app.inject({ method: 'POST', url: '/v1/auth/password/reset', payload: { email: 'a@example.com', code: 'wrong', new_password: 'a sufficiently long password' } });
  assert.equal(response.statusCode, 429);
});

test('mobile status is scoped; create/edit/delete preserve desktop data and retry receipts', async t => {
  const { request, b, repository } = await fixture(t);
  const upload = async (path, contents) => {
    const bytes = Buffer.from(contents); const digest = sha256(bytes);
    assert.equal((await request('PUT', `/v1/blobs/${digest}?path=${path}`, bytes, undefined, true)).statusCode, 204);
    return digest;
  };
  const pc = await upload('notes/pc.md', 'desktop');
  await request('PUT', '/v1/manifest', { expected_revision: 0, entries: { 'notes/pc.md': pc, 'expenses/pc.json': pc } });
  const path = 'scraps/phone.md'; const digest = await upload(path, 'phone');
  const create = { operation_id: 'create-phone-operation', path, base: null, digest, assets: {} };
  assert.equal((await request('POST', '/v1/capture', create)).statusCode, 200);
  assert.equal((await request('POST', '/v1/capture', create)).statusCode, 200);
  assert.equal((await repository.manifest('a')).revision, 2);
  assert.deepEqual((await request('POST', '/v1/capture/status', { paths: [path] })).json(), { entries: { [path]: digest } });
  assert.deepEqual((await request('POST', '/v1/capture/status', { paths: [path] }, b)).json(), { entries: { [path]: null } });
  for (const paths of [['notes/pc.md'], ['expenses/pc.json'], ['../secret'], Array(101).fill(path)]) {
    assert.equal((await request('POST', '/v1/capture/status', { paths })).statusCode, 400);
  }
  const edited = await upload(path, 'edited phone');
  assert.equal((await request('POST', '/v1/capture', { ...create, operation_id: 'edit-phone-operation', base: digest, digest: edited })).statusCode, 200);
  assert.equal((await request('POST', '/v1/capture', { ...create, operation_id: 'stale-phone-operation', digest: pc })).json().code, 'capture_conflict');
  assert.equal((await request('POST', '/v1/capture', { ...create, operation_id: 'delete-phone-operation', base: edited, digest: null })).statusCode, 200);
  assert.equal((await request('POST', '/v1/capture', create)).statusCode, 200);
  assert.deepEqual((await repository.manifest('a')).entries, { 'notes/pc.md': pc, 'expenses/pc.json': pc });
  assert.equal((await request('POST', '/v1/capture', { ...create, digest: edited })).json().code, 'operation_reused');
  assert.equal((await request('POST', '/v1/capture', { ...create, operation_id: 'missing-blob-operation', digest: 'f'.repeat(64) })).json().code, 'missing_blob');
  assert.equal((await request('POST', '/v1/capture', { ...create, path: 'notes/pc.md' })).statusCode, 400);
  assert.equal((await request('POST', '/v1/capture', { ...create, assets: { 'expenses/a.json': pc } })).statusCode, 400);
});
