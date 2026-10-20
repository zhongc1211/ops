// usage: node shoot.cjs <repoDir> <outDir> <name=url[@full|@fold]> ...
const path = require('path');
const repo = process.argv[2];
const out = process.argv[3];
const { chromium } = require(path.join(repo, 'node_modules/playwright'));

async function dismiss(page) {
  const re = /^(accept|accept all|allow all|agree|got it|ok|i agree|同意|接受|知道了|好的)$/i;
  for (const b of await page.locator('button, a[role=button]').all()) {
    try {
      const t = ((await b.innerText({ timeout: 300 })) || '').trim();
      if (re.test(t) && (await b.isVisible())) { await b.click({ timeout: 1000 }); console.log('  dismissed:', t); }
    } catch {}
  }
}

async function scrollAll(page) {
  await page.evaluate(async () => {
    const step = 600;
    for (let y = 0; y < document.documentElement.scrollHeight; y += step) {
      window.scrollTo(0, y);
      await new Promise((r) => setTimeout(r, 250));
    }
    window.scrollTo(0, document.documentElement.scrollHeight);
    await new Promise((r) => setTimeout(r, 800));
    window.scrollTo(0, 0);
    await new Promise((r) => setTimeout(r, 1200));
  });
}

(async () => {
  const browser = await chromium.launch();
  const ctx = await browser.newContext({ viewport: { width: 1440, height: 900 }, deviceScaleFactor: 1, locale: 'zh-CN' });
  for (const arg of process.argv.slice(4)) {
    const [name, rest] = arg.split('=');
    const [url, mode = 'full'] = rest.split('@');
    const page = await ctx.newPage();
    try {
      const resp = await page.goto(url, { waitUntil: 'networkidle', timeout: 60000 }).catch(async (e) => {
        console.log('  networkidle timeout, continuing:', e.message.split('\n')[0]);
        return null;
      });
      await page.waitForTimeout(1500);
      await dismiss(page);
      if (mode === 'full') {
        await scrollAll(page);
        await page.waitForLoadState('networkidle', { timeout: 15000 }).catch(() => {});
      }
      await dismiss(page);
      const file = path.join(out, `${name}.png`);
      await page.screenshot({ path: file, fullPage: mode === 'full' });
      const h = await page.evaluate(() => document.documentElement.scrollHeight);
      console.log(`${name}\t${resp ? resp.status() : '?'}\t${page.url()}\theight=${h}\t${file}`);
    } catch (e) {
      console.log(`${name}\tFAILED\t${url}\t${e.message.split('\n')[0]}`);
    }
    await page.close();
  }
  await browser.close();
})();
