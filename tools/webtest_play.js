// Loads the exported browser build in a REAL browser and reports what
// happened: whether the page is cross-origin isolated (no isolation, no
// threads, no game), whether the wasm booted, and whether it reached the
// world server over wss.
//
// A run that merely fails to crash proves nothing, so this fails loudly
// unless it sees the game actually connect.
const puppeteer = require('puppeteer-core');

const URL = process.argv[2] || 'https://localhost:8443/play/';
const SECONDS = parseInt(process.argv[3] || '90', 10);

(async () => {
  const browser = await puppeteer.launch({
    executablePath: '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
    headless: 'new',
    args: [
      '--ignore-certificate-errors',           // it is self-signed on purpose
      '--enable-unsafe-swiftshader',           // WebGL2 without a real GPU
      '--use-gl=angle', '--use-angle=swiftshader',
      '--no-sandbox', '--window-size=1280,800',
    ],
  });
  const page = await browser.newPage();
  await page.setViewport({ width: 1280, height: 800 });

  const log = [];
  const errors = [];
  page.on('console', m => log.push(`${m.type()}: ${m.text()}`));
  page.on('pageerror', e => errors.push(`pageerror: ${e.message}`));
  page.on('requestfailed', r =>
    errors.push(`requestfailed: ${r.url().split('/').pop()} ${r.failure()?.errorText}`));

  const started = Date.now();
  await page.goto(URL, { waitUntil: 'domcontentloaded', timeout: 120000 });

  // Poll until the game says it connected, or we run out of patience.
  let connected = false;
  for (let i = 0; i < SECONDS; i++) {
    await new Promise(r => setTimeout(r, 1000));
    if (log.some(l => /Connected to world server/i.test(l))) { connected = true; break; }
  }

  // Actually join. A browser hands out pointer lock and audio only after
  // a real user gesture, so this clicks the canvas first — exactly what a
  // player does. Synthetic CDP input counts as a gesture, so this is a
  // genuine test of that path, not a bypass of it.
  await page.mouse.click(640, 400);
  await new Promise(r => setTimeout(r, 1000));
  await page.keyboard.press('Space');
  await new Promise(r => setTimeout(r, 8000));
  await page.screenshot({ path: (process.argv[4] || 'shot.png').replace('.png', '-joined.png') });
  const joined = await page.evaluate(() => ({
    pointerLocked: document.pointerLockElement !== null,
  }));

  const state = await page.evaluate(() => ({
    isolated: window.crossOriginIsolated === true,
    hasSAB: typeof SharedArrayBuffer !== 'undefined',
    canvas: (() => {
      const c = document.querySelector('canvas');
      return c ? `${c.width}x${c.height}` : 'no canvas';
    })(),
  }));

  await page.screenshot({ path: process.argv[4] || 'shot.png' });

  console.log('--- browser run ---');
  console.log('url            :', URL);
  console.log('crossOriginIso :', state.isolated);
  console.log('SharedArrayBuf :', state.hasSAB);
  console.log('canvas         :', state.canvas);
  console.log('pointerLocked  :', joined.pointerLocked);
  console.log('connected      :', connected, `(after ${Math.round((Date.now()-started)/1000)}s)`);
  console.log('--- console (last 40) ---');
  console.log(log.slice(-40).join('\n') || '(nothing)');
  if (errors.length) {
    console.log('--- errors ---');
    console.log([...new Set(errors)].slice(0, 25).join('\n'));
  }
  await browser.close();

  const ok = state.isolated && state.hasSAB && connected;
  console.log(ok ? '\nWEB PLAY: PASS' : '\nWEB PLAY: FAIL');
  process.exit(ok ? 0 : 1);
})();
