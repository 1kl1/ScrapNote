import test from 'node:test';
import assert from 'node:assert/strict';
import { createPasswordResetMailer } from '../src/password_reset_mailer.js';

test('reset mail uses TLS, configured sender and the one-time code', async () => {
  let options; let message;
  const mailer = createPasswordResetMailer({
    smtpUrl: 'smtps://user:password@smtp.example.com:465',
    from: 'noreply@example.com',
    createTransport(value) { options = value; return { async sendMail(value) { message = value; } }; },
  });
  await mailer.send('owner@example.com', 'a'.repeat(32));
  assert.equal(options.requireTLS, true);
  assert.equal(options.disableFileAccess, true);
  assert.equal(options.disableUrlAccess, true);
  assert.equal(message.from.address, 'noreply@example.com');
  assert.equal(message.to.address, 'owner@example.com');
  assert.ok(message.text.includes('a'.repeat(32)));
  assert.ok(message.text.includes('15분'));
  assert.ok(message.text.includes('모든 기기'));
});

test('mail configuration is optional and invalid transports are rejected', () => {
  assert.equal(createPasswordResetMailer({}), undefined);
  assert.throws(() => createPasswordResetMailer({ smtpUrl: 'http://example.com', from: 'noreply@example.com' }));
});
