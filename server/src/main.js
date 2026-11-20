import { Repository } from './repository.js';
import { Zipline } from './zipline.js';
import { buildApp } from './app.js';
import { createPasswordResetMailer } from './password_reset_mailer.js';
const repository = new Repository(process.env.DATABASE_URL);
await repository.initialize(process.env.INITIAL_EMAIL, process.env.INITIAL_PASSWORD);
const zipline = new Zipline({ url: process.env.ZIPLINE_URL, token: process.env.ZIPLINE_TOKEN });
const passwordResetMailer = createPasswordResetMailer({ smtpUrl: process.env.SMTP_URL, from: process.env.SMTP_FROM });
const app = await buildApp({ repository, zipline, passwordResetMailer, logger: true });
await app.listen({ host: '0.0.0.0', port: Number(process.env.PORT ?? 8080) });
for (const signal of ['SIGINT', 'SIGTERM']) process.once(signal, async () => {
  await app.close(); await repository.close(); process.exit(0);
});
