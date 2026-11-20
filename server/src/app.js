import Fastify from 'fastify';
import rateLimit from '@fastify/rate-limit';
import { randomBytes } from 'node:crypto';
import { hashPassword, verifyPassword, publicUser } from './auth.js';
import { ApiError, MAX_BLOB, MAX_MANIFEST, invalid, sha256, validatePath, validateEntries } from './protocol.js';
import { capturePaths, captureChange } from './capture.js';
export async function buildApp({ repository, zipline, passwordResetMailer, logger = false }) {
  const app = Fastify({ logger, bodyLimit: MAX_MANIFEST + 16384, requestTimeout: 180000, trustProxy: 1 });
  const dummyHash = await hashPassword(randomBytes(32).toString('hex'));
  await app.register(rateLimit, { global: false });
  app.addContentTypeParser('application/octet-stream', { parseAs: 'buffer', bodyLimit: MAX_BLOB }, (_, body, done) => done(null, body));
  app.addHook('onRequest', async (request, reply) => {
    reply.header('cache-control', 'no-store').header('x-content-type-options', 'nosniff');
    if (request.routeOptions.url === '/healthz' || request.routeOptions.url === '/v1/auth/login' || request.routeOptions.url === '/v1/auth/password/reset/request' || request.routeOptions.url === '/v1/auth/password/reset') return;
    const match = /^Bearer ([A-Za-z0-9_-]{43})$/.exec(request.headers.authorization ?? '');
    if (!match) throw new ApiError(401, 'unauthorized', '다시 로그인해 주세요.');
    request.sessionHash = sha256(match[1]);
    request.user = await repository.session(request.sessionHash);
    if (!request.user) throw new ApiError(401, 'unauthorized', '다시 로그인해 주세요.');
  });
  app.setErrorHandler((error, request, reply) => {
    const status = error.statusCode >= 400 && error.statusCode < 600 ? error.statusCode : 500;
    if (status >= 500) request.log.error({ code: error.code ?? 'internal_error' }, 'Request failed');
    reply.code(status).send({ code: error.code ?? 'request_error',
      message: error instanceof ApiError ? error.message : status === 429 ? '잠시 후 다시 시도해 주세요.' : '요청을 처리하지 못했습니다.' });
  });
  app.get('/healthz', async () => { await repository.ping(); return { status: 'ok' }; });
  app.post('/v1/auth/login', { bodyLimit: 8192, config: { rateLimit: { max: 10, timeWindow: '1 minute' } } }, async request => {
    const { email, password } = request.body ?? {};
    if (typeof email !== 'string' || email.length > 320 || typeof password !== 'string' || password.length > 1024) throw invalid();
    const user = await repository.findUser(email.trim().toLowerCase());
    const valid = await verifyPassword(password, user?.password_hash ?? dummyHash);
    if (!user || !valid) throw new ApiError(401, 'invalid_credentials', '이메일 또는 비밀번호가 맞지 않습니다.');
    const token = randomBytes(32).toString('base64url');
    const expires = new Date(Date.now() + 30 * 86400000).toISOString();
    const current = await repository.createSession(user.id, sha256(token), expires, user.password_hash);
    return { access_token: token, expires_at: expires, user: publicUser(current) };
  });
  app.post('/v1/auth/password/reset/request', { bodyLimit: 8192, config: { rateLimit: { max: 5, timeWindow: '1 minute' } } }, async request => {
    const { email } = request.body ?? {};
    if (typeof email !== 'string' || email.length > 320 || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email.trim())) throw invalid();
    if (!passwordResetMailer) throw new ApiError(503, 'mail_unavailable', '서버의 메일 발송 설정이 필요합니다.');
    const user = await repository.findUser(email.trim().toLowerCase());
    if (user) {
      const code = randomBytes(24).toString('base64url');
      const expires = new Date(Date.now() + 15 * 60000).toISOString();
      const issued = await repository.issuePasswordReset(user.id, sha256(code), expires);
      if (issued) {
        try { await passwordResetMailer.send(user.email, code); }
        catch { request.log.error({ code: 'password_reset_delivery_failed' }, 'Password reset email delivery failed'); }
      }
    }
    // Do not disclose whether the email belongs to an account.
    return { ok: true };
  });
  app.post('/v1/auth/password/reset', { bodyLimit: 8192, config: { rateLimit: { max: 10, timeWindow: '1 minute' } } }, async request => {
    const { email, code, new_password: next } = request.body ?? {};
    if (typeof email !== 'string' || email.length > 320 || typeof next !== 'string' || next.length < 16 || next.length > 1024) throw invalid();
    if (typeof code !== 'string' || !/^[A-Za-z0-9_-]{32}$/.test(code)) throw new ApiError(400, 'invalid_reset_code', '재설정 코드가 올바르지 않거나 만료되었습니다.');
    const changed = await repository.resetPassword(email.trim().toLowerCase(), sha256(code), await hashPassword(next));
    if (!changed) throw new ApiError(400, 'invalid_reset_code', '재설정 코드가 올바르지 않거나 만료되었습니다.');
    return { ok: true };
  });
  app.post('/v1/auth/password', { bodyLimit: 8192, config: { rateLimit: { max: 10, timeWindow: '1 minute' } } }, async request => {
    const { current_password: current, new_password: next } = request.body ?? {};
    if (typeof current !== 'string' || current.length > 1024 || typeof next !== 'string' || next.length < 16 || next.length > 1024) throw invalid('새 비밀번호는 16자 이상 1024자 이하여야 합니다.');
    if (!await verifyPassword(current, request.user.password_hash)) throw new ApiError(400, 'incorrect_password', '현재 비밀번호가 맞지 않습니다.');
    const changed = await repository.changePassword(request.user.id, request.user.password_hash, await hashPassword(next));
    if (!changed) throw new ApiError(400, 'incorrect_password', '현재 비밀번호가 맞지 않습니다.');
    return { ok: true };
  });
  app.get('/v1/auth/me', async request => ({ user: publicUser(request.user) }));
  app.post('/v1/auth/logout', async request => { await repository.revoke(request.sessionHash); return { ok: true }; });
  app.get('/v1/manifest', async request => repository.manifest(request.user.id));
  app.post('/v1/capture/status', async request => {
    const paths = capturePaths(request.body?.paths);
    return { entries: await repository.captureStatus(request.user.id, paths) };
  });
  app.post('/v1/capture', async request => repository.capture(request.user.id, captureChange(request.body)));
  app.put('/v1/blobs/:digest', { bodyLimit: MAX_BLOB }, async (request, reply) => {
    const digest = request.params.digest;
    const path = request.query.path;
    validatePath(path, digest);
    if (digest === 'directory' || !Buffer.isBuffer(request.body) || request.body.length > MAX_BLOB || sha256(request.body) !== digest) throw invalid('Uploaded file failed integrity verification.');
    const owner = request.user.id;
    await repository.storeBlob(owner, digest, request.body, path.startsWith('assets/') ? () => zipline.upload(owner, digest, request.body) : null);
    return reply.code(204).send();
  });
  app.get('/v1/blobs/:digest', async (request, reply) => {
    const digest = request.params.digest;
    if (!/^[a-f0-9]{64}$/.test(digest)) throw invalid();
    const row = await repository.blob(request.user.id, digest);
    if (!row) throw new ApiError(404, 'not_found', '파일을 찾을 수 없습니다.');
    const bytes = row.zipline_id ? await zipline.download(request.user.id, digest, row.zipline_id) : row.content;
    if (bytes.length !== row.size || sha256(bytes) !== digest) throw new ApiError(502, 'integrity_error', '파일 검증에 실패했습니다.');
    return reply.type('application/octet-stream').send(bytes);
  });
  app.put('/v1/manifest', async request => {
    const { expected_revision: revision, entries } = request.body ?? {};
    if (!Number.isSafeInteger(revision) || revision < 0 || revision >= 2147483647) throw invalid();
    validateEntries(entries);
    return { revision: await repository.commit(request.user.id, revision, entries) };
  });
  return app;
}
