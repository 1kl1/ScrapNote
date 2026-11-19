import nodemailer from 'nodemailer';

export function createPasswordResetMailer({ smtpUrl, from, createTransport = nodemailer.createTransport }) {
  if (!smtpUrl || !from) return undefined;
  const url = new URL(smtpUrl);
  if (!['smtp:', 'smtps:'].includes(url.protocol)) throw new Error('SMTP_URL must use smtp or smtps.');
  const transport = createTransport({
    url: smtpUrl,
    requireTLS: true,
    disableFileAccess: true,
    disableUrlAccess: true,
    connectionTimeout: 10000,
    greetingTimeout: 10000,
    socketTimeout: 20000,
  });
  return {
    async send(email, code) {
      await transport.sendMail({
        from: { name: 'Scrapnote', address: from },
        to: { address: email },
        subject: 'Scrapnote 비밀번호 재설정 코드',
        text: `비밀번호 재설정을 요청하셨습니다. 아래 코드를 앱에 붙여 넣어 주세요.\n\n${code}\n\n코드는 15분 동안 한 번만 사용할 수 있습니다. 비밀번호를 재설정하면 모든 기기에서 로그아웃됩니다.\n요청하지 않았다면 이 메일을 무시해 주세요.`,
      });
    },
  };
}
