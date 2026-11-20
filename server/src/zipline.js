import { setTimeout as delay } from 'node:timers/promises';
import { ApiError, MAX_BLOB, imageType, sha256 } from './protocol.js';
export class Zipline {
  constructor({ url, token, fetchImpl = fetch, wait = delay }) {
    this.url = new URL(url).origin;
    if (new URL(url).protocol !== 'https:') throw new Error('Zipline requires HTTPS.');
    if (!token) throw new Error('Missing Zipline credentials.');
    Object.assign(this, { token, fetchImpl, wait });
  }
  async request(path, options = {}, allowMissing = false) {
    let waited = 0;
    for (let attempt = 0; attempt < 4; attempt++) {
      const response = await this.fetchImpl(this.url + path, {
        ...options, headers: { authorization: this.token, ...options.headers },
        redirect: 'error', signal: AbortSignal.timeout(120000),
      });
      if (response.status === 429 && attempt < 3) {
        const header = response.headers.get('retry-after');
        const seconds = header && /^\d+$/.test(header) ? Number(header) : NaN;
        const dateDelay = header ? Date.parse(header) - Date.now() : NaN;
        const requested = Number.isFinite(seconds) ? seconds * 1000
          : Number.isFinite(dateDelay) ? dateDelay : 60000;
        const waitMs = Math.max(1000, requested + 250);
        if (waited + waitMs <= 120000) {
          await response.body?.cancel(); await this.wait(waitMs); waited += waitMs; continue;
        }
      }
      if (allowMissing && response.status === 404) { await response.body?.cancel(); return null; }
      if (!response.ok) { await response.body?.cancel(); throw new ApiError(502, 'zipline_error', '사진 저장소에 연결하지 못했습니다. 다시 시도해 주세요.'); }
      return response;
    }
  }
  async metadata(name) {
    // Search provides a stable ID and retention flags.
    const query = new URLSearchParams({ page: '1', perpage: '10', searchField: 'name', searchQuery: name });
    const response = await this.request(`/api/user/files?${query}`);
    const result = await response.json();
    if (!Array.isArray(result.page)) throw new ApiError(502, 'zipline_error', '사진 목록을 확인하지 못했습니다.');
    return result.page.find(file => file.name === name) ?? null;
  }
  async upload(owner, digest, bytes) {
    const [extension, mime] = imageType(bytes);
    const stem = `scrapnote_${owner}_${digest}`;
    const name = `${stem}.${extension}`;
    let metadata = await this.metadata(name);
    // Recover an upload made by a client that included the extension in the header.
    metadata ??= await this.metadata(`${name}.${extension}`);
    if (!metadata) {
      const form = new FormData(); form.append('file', new Blob([bytes], { type: mime }), name);
      await (await this.request('/api/upload', { method: 'POST', body: form, headers: {
        'x-zipline-filename': stem,
        'x-zipline-original-name': 'false',
      } })).body?.cancel();
      metadata = await this.metadata(name);
    }
    if (!metadata?.id || metadata.password === true || metadata.deletesAt || metadata.maxViews) {
      throw new ApiError(502, 'zipline_policy', '사진의 공개 또는 보존 설정을 확인해 주세요.');
    }
    // Round-trip verification also recovers a completed upload after an interrupted DB commit.
    const returned = await this.download(owner, digest, metadata.id);
    if (sha256(returned) !== digest) throw new ApiError(502, 'integrity_error', '사진 저장소의 원본 검증에 실패했습니다.');
    return metadata.id;
  }
  async download(owner, digest, id) {
    const response = await this.request(`/api/user/files/${encodeURIComponent(id)}/raw`);
    const chunks = []; let size = 0;
    for await (const chunk of response.body) {
      size += chunk.length;
      if (size > MAX_BLOB) throw new ApiError(502, 'integrity_error', '사진 크기 검증에 실패했습니다.');
      chunks.push(chunk);
    }
    const bytes = Buffer.concat(chunks);
    if (sha256(bytes) !== digest) throw new ApiError(502, 'integrity_error', '사진 원본 검증에 실패했습니다.');
    return bytes;
  }
}
