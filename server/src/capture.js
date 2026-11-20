import { invalid, validateEntries, validatePath, sha256, ApiError } from './protocol.js';

export function capturePaths(paths) {
  if (!Array.isArray(paths) || paths.length > 100) throw invalid();
  for (const path of paths) {
    validatePath(path, '0'.repeat(64));
    if (!path.startsWith('scraps/')) throw invalid();
  }
  return [...new Set(paths)];
}

export function captureChange(body) {
  const { operation_id: operation, path, base, digest, assets } = body ?? {};
  if (typeof operation !== 'string' || !/^[a-zA-Z0-9-]{16,80}$/.test(operation)) throw invalid();
  capturePaths([path]);
  for (const value of [base, digest]) {
    if (value !== null && (typeof value !== 'string' || !/^[a-f0-9]{64}$/.test(value))) throw invalid();
  }
  validateEntries(assets);
  if (Object.keys(assets).some(name => !name.startsWith('assets/')) ||
      (digest === null && Object.keys(assets).length)) throw invalid();
  return { operation, path, base, digest, assets,
    fingerprint: sha256(JSON.stringify([path, base, digest, Object.entries(assets).sort()])) };
}

// Called while holding the same manifest row lock as a desktop commit.
export function mergeCapture(entries, change) {
  if ((entries[change.path] ?? null) !== change.base) {
    throw new ApiError(409, 'capture_conflict', '다른 기기에서 이 scrap을 변경했습니다.');
  }
  const next = { ...entries };
  for (const [path, digest] of Object.entries(change.assets)) {
    if (Object.hasOwn(next, path) && next[path] !== digest) throw invalid('Attachment path already exists.');
    next[path] = digest;
  }
  if (change.digest === null) delete next[change.path];
  else next[change.path] = change.digest;
  validateEntries(next);
  return next;
}
