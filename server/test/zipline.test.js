import test from 'node:test';
import assert from 'node:assert/strict';
import { Zipline } from '../src/zipline.js';
import { sha256 } from '../src/protocol.js';
const json = value => new Response(JSON.stringify(value), { headers: { 'content-type': 'application/json' } });
function fixture({ protectedFile = true, corrupt = false, expired = false, exists = false } = {}) {
  const bytes = Buffer.from('original-photo'); const digest = sha256(bytes); const calls = [];
  let present = exists;
  const zipline = new Zipline({ url: 'https://zipline.example.com', token: 'private-api-token', passwordKey: 'k'.repeat(48), fetchImpl: async (url, options) => {
    calls.push({ url, options });
    assert.equal(options.redirect, 'error');
    assert.equal(options.headers.authorization, 'private-api-token');
    if (url.endsWith('/api/upload')) {
      assert.equal(options.headers['x-zipline-password'], zipline.password('owner', digest));
      assert.equal(options.headers['x-zipline-image-compression-percent'], undefined);
      assert.ok(options.body instanceof FormData); present = true; return json({ files: [{ id: 'file-id' }] });
    }
    if (url.endsWith('/password')) return protectedFile ? json({ token: 'short-lived-access' }) : new Response('{}', {status: 400});
    if (url.includes('/raw?')) return new Response(corrupt ? Buffer.from('recompressed-photo') : bytes);
    return json({page: present ? [{ id: 'file-id', name: new URL(url).searchParams.get('searchQuery'), password: undefined, deletesAt: expired ? '2030-01-01' : null, maxViews: null }] : []});
  } });
  return { zipline, bytes, digest, calls };
}

test('uploads password-protected original images and verifies their bytes', async () => {
  const { zipline, bytes, digest, calls } = fixture();
  assert.equal(await zipline.upload('owner', digest, bytes), 'file-id');
  assert.equal(calls.filter(c => c.url.endsWith('/api/upload')).length, 1);
  assert.equal(await zipline.upload('owner', digest, bytes), 'file-id');
  assert.equal(calls.filter(c => c.url.endsWith('/api/upload')).length, 1);
});

test('refuses public, expiring or transformed image storage', async () => {
  for (const settings of [{ protectedFile: false }, { expired: true }, { corrupt: true }]) {
    const { zipline, bytes, digest } = fixture(settings);
    await assert.rejects(zipline.upload('owner', digest, bytes));
  }
});

test('waits for the Zipline rate-limit window before retrying', async () => {
  const waits = []; let requests = 0;
  const zipline = new Zipline({ url: 'https://zipline.example.com', token: 'private-token', passwordKey: 'k'.repeat(48), wait: async ms => waits.push(ms), fetchImpl: async () => {
    requests++;
    return requests === 1 ? new Response('{}', { status: 429, headers: { 'retry-after': '45' } }) : json({ page: [] });
  } });
  assert.equal(await zipline.metadata('photo.png'), null);
  assert.deepEqual(waits, [45250]);
  assert.equal(requests, 2);
});
