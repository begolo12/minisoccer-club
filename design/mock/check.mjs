// Cek error console halaman preview lewat CDP langsung.
// Pakai: node design/mock/check.mjs <url>
import { spawn } from 'node:child_process';
import { setTimeout as sleep } from 'node:timers/promises';

const url = process.argv[2];
const w = Number(process.argv[3] ?? 390);
const h = Number(process.argv[4] ?? 844);
const out = process.argv[5] ?? '/tmp/opencode/cdp.png';
const port = 9333;
const chrome = spawn('google-chrome', [
  '--headless=new',
  `--remote-debugging-port=${port}`,
  '--no-sandbox',
  '--disable-gpu',
  '--user-data-dir=/tmp/opencode/chrome-check',
  `--window-size=${w},${h}`,
  'about:blank',
]);

try {
  await sleep(2500);
  const list = await (await fetch(`http://127.0.0.1:${port}/json/list`)).json();
  const target = list.find((t) => t.type === 'page');
  const ws = new WebSocket(target.webSocketDebuggerUrl);
  await new Promise((r) => ws.addEventListener('open', r, { once: true }));

  let id = 0;
  const send = (method, params = {}) => ws.send(JSON.stringify({ id: ++id, method, params }));

  ws.addEventListener('message', (ev) => {
    const msg = JSON.parse(ev.data);
    if (msg.method === 'Runtime.consoleAPICalled') {
      const text = (msg.params.args ?? []).map((a) => a.value ?? a.description ?? '').join(' ');
      console.log(`[${msg.params.type}]`, String(text).slice(0, 600));
    }
    if (msg.method === 'Runtime.exceptionThrown') {
      const d = msg.params.exceptionDetails;
      console.log('[exception]', (d.exception?.description ?? d.text ?? '').slice(0, 1200));
    }
  });

  ws.addEventListener('message', async (ev) => {
    const msg = JSON.parse(ev.data);
    if (msg.id && msg.result?.data) {
      const { writeFileSync } = await import('node:fs');
      writeFileSync(out, Buffer.from(msg.result.data, 'base64'));
      console.log('screenshot saved');
    }
  });
  send('Runtime.enable');
  send('Emulation.setDeviceMetricsOverride', { width: w, height: h, deviceScaleFactor: 1, mobile: false });
  send('Page.enable');
  send('Page.navigate', { url });
  await sleep(8000);
  send('Page.captureScreenshot', { format: 'png' });
  await sleep(1500);
} finally {
  chrome.kill();
}
