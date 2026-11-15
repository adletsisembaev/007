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
const dumped = JSON.parse(fs.readFileSync(path.join(OUT, 'kcd_init.json')));
const init = dumped.init;
const locales = dumped.locales;
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
  await page.addInitScript(([init, locales]) => {
    window.__calls = [];
    window.sketchup = {
      ready() { KCD.receive(init); },
      validate(j) { window.__calls.push(['validate', j]); rubyValidate(j).then(m => KCD.receive(JSON.parse(m))); },
      create_cabinet(j) { window.__calls.push(['create', j]); KCD.receive({type:'result', ok:true, message:'Created CABINET_600_BASE.', errors:[], warnings:[]}); },
      set_locale(j) { KCD.receive(locales[JSON.parse(j)]); },
      refresh_materials() {}, load_selected() {}, close() {}, clear_target() {}, update_cabinet() {}
    };
  }, [init, locales]);
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
  // material picker: texture preset, model material, custom colour
  const russianTitle = await page.textContent('h1');
  await page.click('[data-material-button="front_material"]');
  const pickerOpen = await page.isVisible('[data-picker-for="front_material"]');
  const chipCount = await page.$$eval('[data-picker-for="front_material"] .chip', c => c.length);
  await page.screenshot({ path: path.join(OUT, 'ui_picker.png'), fullPage: false });
  await page.click('[data-picker-for="front_material"] .chip[title="Орех"]');
  const afterPreset = await page.inputValue('#f-front_material');
  const buttonLabel = await page.textContent('[data-material-button="front_material"] .swatch-label');
  await page.click('[data-material-button="carcass_material"]');
  await page.click('[data-picker-for="carcass_material"] .chip[title="Egger W1000"]');
  const afterModel = await page.inputValue('#f-carcass_material');
  await page.click('[data-material-button="hardware_material"]');
  await page.fill('[data-picker-for="hardware_material"] .custom-color input[type="text"]', 'zz');
  await page.click('[data-picker-for="hardware_material"] .custom-color button');
  const badHex = await page.textContent('[data-picker-for="hardware_material"] .field-error');
  await page.fill('[data-picker-for="hardware_material"] .custom-color input[type="text"]', '2a6f97');
  await page.press('[data-picker-for="hardware_material"] .custom-color input[type="text"]', 'Enter');
  const afterCustom = await page.inputValue('#f-hardware_material');
  await page.waitForTimeout(700);
  const texturedRects = await page.$$eval('#preview rect', r => r.filter(x => (x.getAttribute('fill') || '').startsWith('url(')).length);
  const locked = { pickerOpen, chipCount, afterPreset, buttonLabel, afterModel, badHex, afterCustom, texturedRects, russianTitle };
  // language switch keeps edited values
  await page.selectOption('#language-select', 'en');
  await page.waitForTimeout(500);
  locked.englishTitle = await page.textContent('h1');
  locked.valueKept = await page.inputValue('#f-front_material');
  locked.englishLabel = await page.textContent('[data-material-button="front_material"] .swatch-label');
  await page.selectOption('#language-select', 'ru');
  await page.waitForTimeout(300);
  // corner cabinet
  await page.selectOption('#f-cabinet_type', 'corner');
  await page.waitForTimeout(700);
  locked.cornerFields = await page.isVisible('#f-blind_width');
  locked.cornerPreview = await page.$$eval('#preview rect', r => r.map(x => x.textContent).filter(n => n === 'BLIND_PANEL' || n === 'DOOR'));
  await page.screenshot({ path: path.join(OUT, 'ui_corner.png'), fullPage: false });
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
  if (logs.some(l => l.startsWith('PAGEERROR') || l.startsWith('error'))) { process.exitCode = 1; }
  await browser.close(); rb.stdin.end();
})();
