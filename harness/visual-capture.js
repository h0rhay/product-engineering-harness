// Screenshot one page after scrolling through it, so lazy content is loaded on any stack.
// Usage: node visual-capture.js <WxH> <url> <out.png>. Env: VISUAL_STORAGE_STATE.
let pw;
try { pw = require('playwright'); } catch { pw = require('@playwright/test'); }

(async () => {
  const [, , viewport, url, out] = process.argv;
  const [width, height] = viewport.split('x').map(Number);
  const browser = await pw.chromium.launch();
  try {
    const context = await browser.newContext({
      viewport: { width, height },
      storageState: process.env.VISUAL_STORAGE_STATE || undefined,
    });
    const page = await context.newPage();
    await page.goto(url, { waitUntil: 'load', timeout: 60000 });
    await page.evaluate(async () => {
      for (let y = 0; y < document.documentElement.scrollHeight; y += innerHeight) {
        scrollTo({ top: y, behavior: 'instant' });
        await new Promise((r) => setTimeout(r, 150));
      }
      scrollTo({ top: 0, behavior: 'instant' });
    });
    // ponytail: pages with analytics may never go idle, so this wait is capped, not required.
    await page.waitForLoadState('networkidle', { timeout: 5000 }).catch(() => {});
    await page.evaluate(() => Promise.all([...document.images].filter((i) => !i.complete).map(
      (i) => new Promise((r) => { i.onload = i.onerror = r; setTimeout(r, 5000); }),
    )));
    await page.screenshot({ path: out, fullPage: true, animations: 'disabled' });
  } finally {
    await browser.close();
  }
})().catch((e) => { console.error(e.message); process.exit(1); });
