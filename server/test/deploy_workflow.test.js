import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';

const workflow = readFileSync(new URL('../../.github/workflows/deploy-server.yml', import.meta.url), 'utf8');
const remote = workflow.split("<<'REMOTE'\n")[1].split('\n          REMOTE')[0]
  .replace(/^ {10}/gm, '');
// Execute the real deployment commands with Docker/SSH privilege calls stubbed.
const deployment = remote.slice(remote.indexOf('docker build -t '));
const stubs = `
set -euo pipefail
build_dir=/unused
deployed=0
rolled_back=0
docker() {
  printf '%s\\n' "$*" >> "$COMMAND_LOG"
  case "$*" in
    'build -t scrapnote-api:candidate /unused') ;;
    'compose ps -q api')
      if [ "$HAS_CONTAINER" = 1 ] || [ "$deployed" = 1 ]; then
        echo api-container
      fi
      return 0 ;;
    'container inspect --format {{.Image}} api-container')
      echo sha256:running ;;
    'image inspect --format {{.Id}} scrapnote-api:1.0.0')
      if [ "$HAS_TAG" = 1 ]; then echo sha256:tagged; else return 1; fi ;;
    'image tag sha256:running scrapnote-api:previous'|\
    'image tag sha256:tagged scrapnote-api:previous'|\
    'image tag scrapnote-api:candidate scrapnote-api:1.0.0') ;;
    'image tag scrapnote-api:previous scrapnote-api:1.0.0')
      rolled_back=1 ;;
    'compose up -d --no-deps --force-recreate api') deployed=1 ;;
    'inspect -f {{.State.Health.Status}} api-container')
      if [ "$FAIL_NEW" = 1 ] && [ "$rolled_back" = 0 ]; then
        echo unhealthy
      else
        echo healthy
      fi ;;
    *) echo "Unexpected Docker command: $*" >&2; return 99 ;;
  esac
}
sudo() {
  shift 5
  docker compose "$@"
}
sleep() { :; }
`;

function deploy({ container = true, tag = false, fail = false } = {}) {
  const directory = mkdtempSync(join(tmpdir(), 'scrapnote-deploy-'));
  const log = join(directory, 'commands');
  try {
    const result = spawnSync('bash', ['-c', stubs + deployment], {
      encoding: 'utf8',
      timeout: 10000,
      env: {
        ...process.env,
        COMMAND_LOG: log,
        HAS_CONTAINER: container ? '1' : '0',
        HAS_TAG: tag ? '1' : '0',
        FAIL_NEW: fail ? '1' : '0',
      },
    });
    assert.ifError(result.error);
    return { ...result, commands: readFileSync(log, 'utf8') };
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
}

test('deploys when the old tag is missing by backing up the running image', () => {
  const result = deploy({ tag: true });
  assert.equal(result.status, 0, result.stderr);
  assert.match(result.commands, /image tag sha256:running scrapnote-api:previous/);
  assert.doesNotMatch(result.commands, /image inspect/);
  assert.match(result.stdout, /API deployment is healthy/);

  const missingTag = deploy();
  assert.equal(missingTag.status, 0, missingTag.stderr);
  assert.match(missingTag.commands, /image tag sha256:running scrapnote-api:previous/);
});

test('uses the existing image tag when no API container exists', () => {
  const result = deploy({ container: false, tag: true });
  assert.equal(result.status, 0, result.stderr);
  assert.match(result.commands, /image tag sha256:tagged scrapnote-api:previous/);
});

test('allows the first deployment without a previous image', () => {
  const result = deploy({ container: false });
  assert.equal(result.status, 0, result.stderr);
  assert.doesNotMatch(result.commands, /scrapnote-api:previous/);
  assert.match(result.stdout, /API deployment is healthy/);
});

test('restores the running image if the new container fails its health check', () => {
  const result = deploy({ fail: true });
  assert.equal(result.status, 1);
  assert.match(result.commands, /image tag sha256:running scrapnote-api:previous/);
  assert.match(result.commands, /image tag scrapnote-api:previous scrapnote-api:1.0.0/);
  assert.equal(result.commands.match(/compose up /g).length, 2);
  assert.doesNotMatch(result.stderr, /Rollback did not become healthy/);
});

test('reports a failed first deployment without restoring an unrelated previous tag', () => {
  const result = deploy({ container: false, fail: true });
  assert.equal(result.status, 1);
  assert.match(result.stderr, /no previous image is available for rollback/);
  assert.doesNotMatch(result.commands, /scrapnote-api:previous/);
  assert.equal(result.commands.match(/compose up /g).length, 1);
});
