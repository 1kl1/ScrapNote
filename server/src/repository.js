import { readFile } from 'node:fs/promises';
import { randomUUID } from 'node:crypto';
import pg from 'pg';
import { hashPassword } from './auth.js';
import { ApiError } from './protocol.js';
import { mergeCapture } from './capture.js';
export class Repository {
  constructor(connectionString) { this.pool = new pg.Pool({ connectionString, max: 8 }); }
  async initialize(email, password) {
    await this.pool.query(await readFile(new URL('./schema.sql', import.meta.url), 'utf8'));
    if (email && password) {
      if (password.length < 16) throw new Error('Initial account password must have at least 16 characters.');
      await this.pool.query('INSERT INTO users(id,email,password_hash) VALUES($1,$2,$3) ON CONFLICT(email) DO NOTHING',
        [randomUUID(), email.trim().toLowerCase(), await hashPassword(password)]);
    }
  }
  async ping() { await this.pool.query('SELECT 1'); }
  async close() { await this.pool.end(); }
  async findUser(email) { return (await this.pool.query('SELECT * FROM users WHERE email=$1', [email])).rows[0]; }
  async changePassword(userId, oldHash, newHash) {
    const result = await this.pool.query('UPDATE users SET password_hash=$3 WHERE id=$1 AND password_hash=$2', [userId, oldHash, newHash]);
    return result.rowCount === 1;
  }
  async issuePasswordReset(userId, hash, expiresAt) {
    const result = await this.pool.query(`INSERT INTO password_resets(user_id,token_hash,expires_at) VALUES($1,$2,$3)
      ON CONFLICT(user_id) DO UPDATE SET token_hash=$2, expires_at=$3, issued_at=now()
      WHERE password_resets.issued_at <= now() - interval '1 minute'`, [userId, hash, expiresAt]);
    return result.rowCount === 1;
  }
  async resetPassword(email, hash, passwordHash) {
    const client = await this.pool.connect();
    try {
      await client.query('BEGIN');
      const { rows } = await client.query(`SELECT u.id FROM users u JOIN password_resets r ON r.user_id=u.id
        WHERE u.email=$1 AND r.token_hash=$2 AND r.expires_at>now() FOR UPDATE OF u,r`, [email, hash]);
      if (!rows.length) { await client.query('ROLLBACK'); return false; }
      const userId = rows[0].id;
      await client.query('UPDATE users SET password_hash=$2 WHERE id=$1', [userId, passwordHash]);
      await client.query('DELETE FROM password_resets WHERE user_id=$1', [userId]);
      await client.query('DELETE FROM sessions WHERE user_id=$1', [userId]);
      await client.query('COMMIT'); return true;
    } catch (e) { await client.query('ROLLBACK'); throw e; } finally { client.release(); }
  }
  async createSession(userId, hash, expiresAt, passwordHash = null) {
    const client = await this.pool.connect();
    try {
      await client.query('BEGIN');
      await client.query('DELETE FROM sessions WHERE expires_at < now()');
      // Lock the account before creating a session so a concurrent reset cannot
      // leave a new session authenticated by the old password.
      const { rows } = await client.query('UPDATE users SET last_sign_in_at=now() WHERE id=$1 AND ($2::text IS NULL OR password_hash=$2) RETURNING *', [userId, passwordHash]);
      if (!rows.length) throw new ApiError(401, 'invalid_credentials', '이메일 또는 비밀번호가 맞지 않습니다.');
      await client.query('INSERT INTO sessions VALUES($1,$2,$3)', [hash, userId, expiresAt]);
      await client.query('COMMIT'); return rows[0];
    } catch (e) { await client.query('ROLLBACK'); throw e; } finally { client.release(); }
  }
  async session(hash) {
    return (await this.pool.query('SELECT u.* FROM sessions s JOIN users u ON u.id=s.user_id WHERE s.token_hash=$1 AND s.expires_at>now()', [hash])).rows[0];
  }
  async revoke(hash) { await this.pool.query('DELETE FROM sessions WHERE token_hash=$1', [hash]); }
  async manifest(owner) {
    return (await this.pool.query('SELECT revision,entries FROM vault_manifests WHERE user_id=$1', [owner])).rows[0] ?? { revision: 0, entries: {} };
  }
  async blob(owner, digest) {
    return (await this.pool.query('SELECT * FROM vault_blobs WHERE user_id=$1 AND digest=$2', [owner, digest])).rows[0];
  }
  async captureStatus(owner, paths) {
    const { rows } = await this.pool.query(`SELECT p.path, m.entries->>p.path AS digest
      FROM unnest($2::text[]) AS p(path)
      LEFT JOIN vault_manifests m ON m.user_id=$1`, [owner, paths]);
    return Object.fromEntries(rows.map(row => [row.path, row.digest]));
  }
  async capture(owner, change) {
    const client = await this.pool.connect();
    try {
      await client.query('BEGIN');
      await client.query('INSERT INTO vault_manifests(user_id) VALUES($1) ON CONFLICT DO NOTHING', [owner]);
      const current = (await client.query('SELECT revision,entries FROM vault_manifests WHERE user_id=$1 FOR UPDATE', [owner])).rows[0];
      const receipt = (await client.query('SELECT fingerprint,result FROM capture_receipts WHERE user_id=$1 AND operation_id=$2', [owner, change.operation])).rows[0];
      if (receipt) {
        if (receipt.fingerprint !== change.fingerprint) throw new ApiError(409, 'operation_reused', '전송 식별자가 다른 내용에 사용되었습니다.');
        await client.query('COMMIT'); return receipt.result;
      }
      const entries = mergeCapture(current.entries, change);
      const digests = [...new Set([change.digest, ...Object.values(change.assets)].filter(Boolean))];
      const found = await client.query('SELECT digest,zipline_id FROM vault_blobs WHERE user_id=$1 AND digest=ANY($2::text[])', [owner, digests]);
      if (found.rowCount !== digests.length) throw new ApiError(400, 'missing_blob', 'Upload all files before committing.');
      const images = new Set(found.rows.filter(row => row.zipline_id).map(row => row.digest));
      if (Object.values(change.assets).some(digest => !images.has(digest))) throw new ApiError(400, 'invalid_storage', 'Image assets must be stored in Zipline.');
      const result = { digest: change.digest };
      await client.query('UPDATE vault_manifests SET revision=revision+1, entries=$2, updated_at=now() WHERE user_id=$1', [owner, JSON.stringify(entries)]);
      await client.query('INSERT INTO capture_receipts(user_id,operation_id,fingerprint,result) VALUES($1,$2,$3,$4)', [owner, change.operation, change.fingerprint, JSON.stringify(result)]);
      await client.query('COMMIT'); return result;
    } catch (error) { await client.query('ROLLBACK'); throw error; } finally { client.release(); }
  }
  async storeBlob(owner, digest, bytes, uploadImage) {
    const client = await this.pool.connect();
    try {
      await client.query('BEGIN');
      // Serialize retries for the same immutable blob across API processes.
      await client.query('SELECT pg_advisory_xact_lock(hashtextextended($1,0))', [owner + '/' + digest]);
      const { rows } = await client.query('SELECT digest FROM vault_blobs WHERE user_id=$1 AND digest=$2', [owner, digest]);
      if (!rows.length) {
        const ziplineId = uploadImage ? await uploadImage() : null;
        await client.query('INSERT INTO vault_blobs(user_id,digest,size,content,zipline_id) VALUES($1,$2,$3,$4,$5)',
          [owner, digest, bytes.length, ziplineId ? null : bytes, ziplineId]);
      }
      await client.query('COMMIT');
    } catch (e) { await client.query('ROLLBACK'); throw e; } finally { client.release(); }
  }
  async commit(owner, revision, entries) {
    const client = await this.pool.connect();
    try {
      await client.query('BEGIN');
      await client.query('INSERT INTO vault_manifests(user_id) VALUES($1) ON CONFLICT DO NOTHING', [owner]);
      const current = (await client.query('SELECT revision FROM vault_manifests WHERE user_id=$1 FOR UPDATE', [owner])).rows[0];
      if (current.revision !== revision) throw new ApiError(409, 'revision_conflict', '다른 기기가 먼저 동기화했습니다. 다시 시도해 주세요.');
      const digests = [...new Set(Object.values(entries).filter(d => d !== 'directory'))];
      const found = await client.query('SELECT digest,zipline_id FROM vault_blobs WHERE user_id=$1 AND digest=ANY($2::text[])', [owner, digests]);
      if (found.rowCount !== digests.length) throw new ApiError(400, 'missing_blob', 'Upload all files before committing.');
      const images = new Set(found.rows.filter(r => r.zipline_id).map(r => r.digest));
      if (Object.entries(entries).some(([name, digest]) => name.startsWith('assets/') && !images.has(digest))) {
        throw new ApiError(400, 'invalid_storage', 'Image assets must be stored in Zipline.');
      }
      await client.query('UPDATE vault_manifests SET revision=revision+1, entries=$2, updated_at=now() WHERE user_id=$1', [owner, JSON.stringify(entries)]);
      await client.query('COMMIT'); return revision + 1;
    } catch (e) { await client.query('ROLLBACK'); throw e; } finally { client.release(); }
  }
}
