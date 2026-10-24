import type { ExtensionAPI } from '@earendil-works/pi-coding-agent';
import { consume } from './mailbox.mjs';

export default function (pi: ExtensionAPI) {
  let timer: ReturnType<typeof setInterval> | undefined;
  const stop = () => { if (timer) clearInterval(timer); timer = undefined; };
  pi.on('session_start', (_event, ctx) => {
    stop();
    const tick = () => {
      try {
        consume({ cwd: ctx.cwd, sessionId: ctx.sessionManager.getSessionId(),
          idle: ctx.isIdle(), send: (message: string) => pi.sendUserMessage(message) });
      } catch { /* A filesystem problem must not interrupt the user's pi. */ }
    };
    timer = setInterval(tick, 1000);
    timer.unref();
    tick();
  });
  pi.on('session_shutdown', stop);
}
