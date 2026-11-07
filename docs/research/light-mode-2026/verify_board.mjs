// Node 22+, installed Chrome. No packages, network uploads or normal browser profile.
// Artifacts go to JCODE_SCRATCH_DIR. Run after build_palette.py.
import {spawn} from 'node:child_process';
import {mkdtempSync, readFileSync, writeFileSync, existsSync} from 'node:fs';
import {join} from 'node:path';
import assert from 'node:assert/strict';

const scratch = process.env.JCODE_SCRATCH_DIR;
assert(scratch, 'Set JCODE_SCRATCH_DIR to an existing writable scratch directory');
const profile = mkdtempSync(join(scratch, 'axe-palette-cdp-'));
const chrome = spawn(process.env.CHROME_PATH || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome', [
  '--headless', '--disable-gpu', '--disable-background-networking', '--disable-component-update',
  '--no-first-run', '--no-default-browser-check', '--remote-debugging-port=0',
  `--user-data-dir=${profile}`, 'about:blank',
], {stdio: 'ignore'});
const deadline = setTimeout(() => chrome.kill('SIGKILL'), 60000);
const delay = ms => new Promise(resolve => setTimeout(resolve, ms));
let socket;
try {
  const portFile = join(profile, 'DevToolsActivePort');
  for (let i = 0; !existsSync(portFile) && i < 100; i++) await delay(100);
  const port = readFileSync(portFile, 'utf8').split('\n')[0];
  const targets = await (await fetch(`http://127.0.0.1:${port}/json/list`)).json();
  const page = targets.find(x => x.type === 'page');
  assert(page, 'Chrome must expose a page target');
  socket = new WebSocket(page.webSocketDebuggerUrl);
  await new Promise((resolve, reject) => {
    socket.addEventListener('open', resolve, {once: true});
    socket.addEventListener('error', reject, {once: true});
  });
  let id = 0;
  const pending = new Map();
  socket.addEventListener('message', ({data}) => {
    const message = JSON.parse(data);
    const request = pending.get(message.id);
    if (!request) return;
    pending.delete(message.id);
    clearTimeout(request.timer);
    if (message.error) request.reject(new Error(JSON.stringify(message.error)));
    else request.resolve(message.result);
  });
  const send = (method, params = {}) => new Promise((resolve, reject) => {
    const requestId = ++id;
    const timer = setTimeout(() => {
      pending.delete(requestId);
      reject(new Error(`CDP timeout: ${method}`));
    }, 12000);
    pending.set(requestId, {resolve, reject, timer});
    socket.send(JSON.stringify({id: requestId, method, params}));
  });
  await send('Page.enable');
  await send('Page.navigate', {url: new URL('index.html', import.meta.url).href});
  const reports = [];
  for (const width of [1480, 390, 320]) {
    const height = width === 1480 ? 1400 : 1500;
    await send('Emulation.setDeviceMetricsOverride', {width, height, deviceScaleFactor: 1, mobile: width < 600});
    const evaluation = await send('Runtime.evaluate', {
      expression: `new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(() => resolve({
        width: innerWidth, height: innerHeight, scrollWidth: document.documentElement.scrollWidth,
        previewCount: document.querySelectorAll('.phone').length,
        referenceCount: document.querySelectorAll('.reference').length,
        phoneBounds: [...document.querySelectorAll('.phone')].map(e => ({left:e.getBoundingClientRect().left,right:e.getBoundingClientRect().right})),
        title: document.title
      }))))`,
      awaitPromise: true, returnByValue: true,
    });
    assert(!evaluation.exceptionDetails, JSON.stringify(evaluation.exceptionDetails));
    const report = evaluation.result.value;
    assert.equal(report.width, width, 'Screenshot size alone is not proof of viewport size');
    assert(report.scrollWidth <= width, 'Page must not overflow horizontally');
    assert.equal(report.previewCount, 4);
    assert.equal(report.referenceCount, 4);
    assert(report.phoneBounds.every(x => x.left >= 0 && x.right <= width));
    const screenshot = await send('Page.captureScreenshot', {format: 'png', captureBeyondViewport: false});
    const path = join(scratch, `hashfleet-palette-verified-${width}.png`);
    writeFileSync(path, Buffer.from(screenshot.data, 'base64'));
    reports.push({...report, screenshot: path});
    console.log(`Verified actual ${width}px viewport, four previews, no horizontal overflow: ${path}`);
  }
  writeFileSync(join(scratch, 'hashfleet-palette-layout.json'), JSON.stringify(reports, null, 2) + '\n');
  await send('Browser.close').catch(() => {});
} finally {
  socket?.close();
  chrome.kill('SIGTERM');
  clearTimeout(deadline);
}
