/*
 * Headless check of the HtmlDialog: real init/validation messages from the
 * Ruby code, a fake window.sketchup bridge, screenshots written to the folder
 * given as the first argument. Run: node tests/ui/dialog_test.js <out-dir>
 * Requires Playwright with Chromium.
 */
const { chromium } = require('playwright');
const { spawn } = require('child_process');
const fs = require('fs');
const readline = require('readline');
const path = require('path');
const OUT = process.argv[2] || require('os').tmpdir();
const HERE = __dirname;
require('child_process').execFileSync('ruby', [path.join(HERE, 'dump_init.rb'), path.join(OUT, 'kcd_init.json')]);
const init = JSON.parse(fs.readFileSync(path.join(OUT, 'kcd_init.json'))).init;
const rb = spawn('ruby', [path.join(HERE, 'bridge_server.rb')]);
const rl = readline.createInterface({ input: rb.stdout });
const waiting = [];
rl.on('line', l => { if (l.startsWith('{')) waiting.shift()(l); });
const validate = j => new Promise(r => { waiting.push(r); rb.stdin.write(j + '\n'); });
(async () => {
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 480, height: 1400 } });
  const logs = [];
  page.on('console', m => logs.push(m.type() + ': ' + m.text()));
  page.on('pageerror', e => logs.push('PAGEERROR: ' + e.message));
  await page.exposeFunction('rubyValidate', validate);
  await page.addInitScript(init => {
    window.__calls = [];
    window.sketchup = {
      ready() { KCD.receive(init); },
      validate(j) { window.__calls.push(['validate', j]); rubyValidate(j).then(m => KCD.receive(JSON.parse(m))); },
      create_cabinet(j) { window.__calls.push(['create', j]); KCD.receive({type:'result', ok:true, message:'Created CABINET_600_BASE.', errors:[], warnings:[]}); },
      refresh_materials() {}, load_selected() {}, close() {}, clear_target() {}, update_cabinet() {}
    };
  }, init);
  await page.goto('file://' + path.resolve(HERE, '../../kitchen_cabinet_designer/dialogs/main.html'));
  await page.waitForTimeout(800);
  const rects1 = await page.$$eval('#preview rect', r => r.length);
  await page.screenshot({ path: path.join(OUT, 'ui_base.png'), fullPage: true });
  // switch to drawers
  await page.selectOption('#f-cabinet_type', 'drawers');
  await page.waitForTimeout(800);
  const rects2 = await page.$$eval('#preview rect', r => r.length);
  const shelvesVisible = await page.isVisible('#f-shelf_count');
  const drawersVisible = await page.isVisible('#f-drawer_count');
  // invalid input
  await page.fill('#f-drawer_heights', '300;300;300');
  await page.waitForTimeout(800);
  const err = await page.textContent('[data-error-for="drawer_heights"]');
  await page.fill('#f-drawer_heights', '140;0;0');
  await page.waitForTimeout(800);
  await page.screenshot({ path: path.join(OUT, 'ui_drawers.png'), fullPage: false });
  // existing material locks colour
  await page.fill('#f-front_material', 'Oak Veneer');
  await page.waitForTimeout(400);
  const locked = await page.$eval('#f-front_color', e => [e.disabled, e.value]);
  // wall
  await page.click('[data-category-button="wall"]');
  await page.waitForTimeout(800);
  const wallDepth = await page.inputValue('#f-depth');
  const wallTypes = await page.$$eval('#f-cabinet_type option', o => o.map(x => x.value));
  const plinthVisible = await page.isVisible('#f-plinth_height');
  await page.click('#btn-create');
  await page.waitForTimeout(300);
  const status = await page.textContent('#status');
  const created = await page.evaluate(() => JSON.parse(window.__calls.filter(c => c[0]==='create').pop()[1]));
  await page.screenshot({ path: path.join(OUT, 'ui_wall.png'), fullPage: false });
  console.log(JSON.stringify({rects1, rects2, shelvesVisible, drawersVisible, err, locked, wallDepth, wallTypes, plinthVisible, status,
    createdKeys: Object.keys(created).length, createdCategory: created.category, sentPlinth: 'plinth_height' in created}, null, 1));
  console.log(logs.join('\n'));
  await browser.close(); rb.stdin.end();
})();
