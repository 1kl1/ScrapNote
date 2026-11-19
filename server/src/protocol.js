import { createHash } from 'node:crypto';
export const MAX_BLOB = 25 * 1024 * 1024;
export const MAX_MANIFEST = 4 * 1024 * 1024;
export const sha256 = (bytes) => createHash('sha256').update(bytes).digest('hex');
export class ApiError extends Error {
  constructor(statusCode, code, message) { super(message); Object.assign(this, { statusCode, code }); }
}
export const invalid = (message = 'Invalid vault data.') => new ApiError(400, 'invalid_data', message);
export function validatePath(name, digest) {
  if (typeof name !== 'string' || name.length > 1024) throw invalid();
  const parts = name.split('/');
  if (parts.length < 2 || parts.some(s => !s || s === '.' || s === '..' || /[\\:\x00-\x1f]/.test(s))) throw invalid();
  let allowed = false;
  if (parts[0] === 'notes' || parts[0] === 'scraps') {
    allowed = !parts.slice(1).some(s => s.startsWith('.')) &&
      (name.endsWith('.md') || (parts[0] === 'notes' && digest === 'directory'));
  } else if (parts[0] === 'assets') {
    allowed = parts.length === 4 && parts[1] === 'sha256';
  } else if (parts[0] === 'expenses') {
    allowed = name === 'expenses/.settings/summary.json' ||
      (parts.length === 2 && parts[1].endsWith('.json') && !parts[1].startsWith('.'));
  }
  if (!allowed || name.endsWith('.tmp')) throw invalid();
  if (digest === 'directory') {
    if (parts[0] !== 'notes') throw invalid();
  } else if (typeof digest !== 'string' || !/^[a-f0-9]{64}$/.test(digest)) throw invalid();
}
export function validateEntries(entries) {
  if (!entries || Array.isArray(entries) || typeof entries !== 'object' ||
      Buffer.byteLength(JSON.stringify(entries)) > MAX_MANIFEST) throw invalid();
  for (const [name, digest] of Object.entries(entries)) {
    validatePath(name, digest);
    const parts = name.split('/');
    for (let i = 1; i < parts.length; i++) {
      const parent = parts.slice(0, i).join('/');
      if (Object.hasOwn(entries, parent) && entries[parent] !== 'directory') throw invalid();
    }
  }
}
export function imageType(bytes) {
  if (bytes.subarray(0, 8).equals(Buffer.from('89504e470d0a1a0a', 'hex'))) return ['png', 'image/png'];
  if (bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff) return ['jpg', 'image/jpeg'];
  if (/^GIF8[79]a$/.test(bytes.subarray(0, 6).toString())) return ['gif', 'image/gif'];
  if (bytes.subarray(0, 4).toString() === 'RIFF' && bytes.subarray(8, 12).toString() === 'WEBP') return ['webp', 'image/webp'];
  if (bytes.subarray(4, 8).toString() === 'ftyp') {
    const brands = bytes.subarray(8, Math.min(bytes.length, 64)).toString();
    if (/heic|heix|hevc|hevx|mif1/.test(brands)) return ['heic', 'image/heic'];
    if (/avif|avis/.test(brands)) return ['avif', 'image/avif'];
  }
  // Unsupported attachments are still byte-preserved in Zipline, without inline rendering.
  return ['bin', 'application/octet-stream'];
}
