import test from 'node:test';
import assert from 'node:assert/strict';
import { Zipline } from '../src/zipline.js';
import { sha256 } from '../src/protocol.js';
const json = value => new Response(JSON.stringify(value), { headers: { 'content-type': 'application/json' } });
function fixture({ protectedFile = false, corrupt = false, expired = false, exists = false, maxViews = null } = {}) {
  const bytes = Buffer.from('original-photo'); const digest = sha256(bytes); const calls = [];
  let present = exists;
  const zipline = new Zipline({ url: 'https://zipline.example.com', token: 'private-api-token', fetchImpl: async (url, options) => {
    calls.push({ url, options });
    assert.equal(options.redirect, 'error');
    assert.equal(options.headers.authorization, 'private-api-token');
    if (url.endsWith('/api/upload')) {
      assert.equal(options.headers['x-zipline-password'], undefined);
      assert.equal(options.headers['x-zipline-image-compression-percent'], undefined);
      assert.ok(options.body instanceof FormData); present = true; return json({ files: [{ id: 'file-id' }] });
    }
    assert.ok(!url.includes('/password') && !url.includes('?token='));
    if (url.endsWith('/raw')) return protectedFile
      ? new Response('{}', { status: 403 })
      : new Response(corrupt ? Buffer.from('recompressed-photo') : bytes);
    // Zipline v4.8.3 search omits the password flag.
    return json({page: present ? [{ id: 'file-id', name: new URL(url).searchParams.get('searchQuery'), deletesAt: expired ? '2030-01-01' : null, maxViews }] : []});
  } });
  return { zipline, bytes, digest, calls };
}

test('uploads public original images without duplicates and verifies their bytes', async () => {
  const { zipline, bytes, digest, calls } = fixture();
  assert.equal(await zipline.upload('owner', digest, bytes), 'file-id');
  assert.equal(calls.filter(c => c.url.endsWith('/api/upload')).length, 1);
  assert.equal(await zipline.upload('owner', digest, bytes), 'file-id');
  assert.equal(calls.filter(c => c.url.endsWith('/api/upload')).length, 1);
});

test('downloads existing public images without a password token', async () => {
  const { zipline, bytes, digest, calls } = fixture({ exists: true });
  assert.deepEqual(await zipline.download('owner', digest, 'file-id'), bytes);
  assert.equal(calls.length, 1);
  assert.ok(calls[0].url.endsWith('/file-id/raw'));
});

test('reuses existing public images instead of copying them', async () => {
  const { zipline, bytes, digest, calls } = fixture({ exists: true });
  assert.equal(await zipline.upload('owner', digest, bytes), 'file-id');
  assert.equal(calls.filter(c => c.url.endsWith('/api/upload')).length, 0);
});

test('refuses password-protected, expiring, view-limited or transformed image storage', async () => {
  for (const settings of [{ protectedFile: true }, { expired: true }, { maxViews: 10 }, { corrupt: true }]) {
    const { zipline, bytes, digest } = fixture(settings);
    await assert.rejects(zipline.upload('owner', digest, bytes));
  }
});

test('waits for the Zipline rate-limit window before retrying', async () => {
  const waits = []; let requests = 0;
  const zipline = new Zipline({ url: 'https://zipline.example.com', token: 'private-token', wait: async ms => waits.push(ms), fetchImpl: async () => {
    requests++;
    return requests === 1 ? new Response('{}', { status: 429, headers: { 'retry-after': '45' } }) : json({ page: [] });
  } });
  assert.equal(await zipline.metadata('photo.png'), null);
  assert.deepEqual(waits, [45250]);
  assert.equal(requests, 2);
});
