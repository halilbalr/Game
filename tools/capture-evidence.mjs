/**
 * Launches the production build in headless Chromium with phone emulation,
 * drives a scripted session and saves screenshots of every screen to
 * production/qa/evidence/ (the project's run-and-observe evidence).
 *
 * Usage: npm run build && npm run evidence
 * Env:   CHROMIUM=/path/to/chromium (defaults to Playwright's bundled browser)
 */
import fs from 'node:fs';
import path from 'node:path';
import { chromium } from 'playwright';
import { serve } from './static-server.mjs';

const root = path.resolve(path.dirname(new URL(import.meta.url).pathname), '..');
const outDir = path.join(root, 'production', 'qa', 'evidence');
fs.mkdirSync(outDir, { recursive: true });
const date = new Date().toISOString().slice(0, 10);

const server = await serve(path.join(root, 'dist'), 8199);
const browser = await chromium.launch({
  executablePath: process.env.CHROMIUM || undefined,
  args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'],
});
const ctx = await browser.newContext({
  viewport: { width: 844, height: 390 }, deviceScaleFactor: 2, isMobile: true, hasTouch: true, locale: 'sv-SE',
});
const page = await ctx.newPage();
const problems = [];
page.on('pageerror', (e) => problems.push(`pageerror: ${e.message}`));
page.on('console', (m) => { if (m.type() === 'error' && !m.text().includes('ERR_CERT')) problems.push(`console: ${m.text()}`); });

const shots = [];
async function shot(name, caption, wait = 1500) {
  await page.waitForTimeout(wait);
  const file = `${date}-${name}.png`;
  await page.screenshot({ path: path.join(outDir, file) });
  shots.push({ file, caption });
  console.log('captured', file);
}
const ev = (fn, arg) => page.evaluate(fn, arg);
const ready = () => page.waitForFunction(() => window.blockheim?.game?.running && !window.blockheim.ui.blocking, null, { timeout: 180000 });

await page.goto('http://127.0.0.1:8199/index.html');
await page.waitForFunction(() => window.blockheim?.ui);
await shot('01-title', 'Titelskärm med logga och splash-text', 1200);
await page.getByText('Spela', { exact: true }).click();
await page.getByText('Skapa ny värld').click();
await page.locator('input').nth(0).fill('Evidensvärld');
await page.locator('input').nth(1).fill('12345');
await shot('02-create-world', 'Skapa värld: namn, frö, spelläge och svårighetsgrad', 400);
await page.getByText('Skapa värld', { exact: true }).click();
await ready();
await ev(() => { const g = window.blockheim.game; g.player.yaw = Math.PI; g.player.pitch = -0.12; g.time = 2500; });
await shot('03-survival-day', 'Överlevnad dagtid: terräng, träd, HUD och touchkontroller', 3000);

// Mining with the crack overlay.
await ev(() => {
  const g = window.blockheim.game;
  g.inventory.set(0, { id: g.items.id('stone_pickaxe'), count: 1, damage: 40 });
  g.inventory.set(1, { id: g.items.id('torch'), count: 24, damage: 0 });
  g.inventory.set(2, { id: g.items.id('bread'), count: 6, damage: 0 });
  g.select(0);
  g.player.pitch = -0.75;
});
const cdp = await ctx.newCDPSession(page);
await cdp.send('Input.dispatchTouchEvent', { type: 'touchStart', touchPoints: [{ x: 640, y: 180, id: 1 }] });
await page.waitForTimeout(700);
await shot('04-mining', 'Håll för att bryta: sprickor på blocket och hacka i handen', 0);
await cdp.send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] });

await ev(() => {
  const g = window.blockheim.game;
  g.inventory.add(g.items.id('oak_log'), 6); g.inventory.add(g.items.id('cobblestone'), 12); g.inventory.add(g.items.id('coal'), 5);
  window.blockheim.ui.inv.open('inventory');
});
await shot('05-inventory', 'Inventarie med 2×2-tillverkning och receptbok', 800);
await ev(() => { window.blockheim.ui.inv.close(); const g = window.blockheim.game; g.inventory.add(g.items.id('oak_planks'), 16); g.inventory.add(g.items.id('stick'), 8); g.interactBlock('crafting', 0, 0, 0); });
await shot('06-crafting-table', 'Arbetsbänk 3×3 med recept för verktyg', 800);
await ev(() => window.blockheim.ui.inv.close());

// Underground room: torches, ores, furnace, lava.
await ev(() => {
  const g = window.blockheim.game; const B = g.blocks; const p = g.player;
  const x0 = Math.floor(p.x), z0 = Math.floor(p.z), y = 28;
  for (let x = x0 - 6; x <= x0 + 6; x++) for (let z = z0 - 10; z <= z0 + 2; z++) for (let k = -1; k <= 5; k++) {
    const wall = k === -1 || k === 5 || x === x0 - 6 || x === x0 + 6 || z === z0 - 10 || z === z0 + 2;
    g.world.setBlock(x, y + k, z, wall ? B.id('stone') : 0);
  }
  g.world.setBlock(x0 - 3, y, z0 - 5, B.id('torch'));
  g.world.setBlock(x0 + 2, y + 2, z0 - 9, B.id('torch'), 2);
  const ores = ['coal_ore', 'iron_ore', 'gold_ore', 'diamond_ore'];
  ores.forEach((o, i) => g.world.setBlock(x0 - 1 + i, y + 1, z0 - 10, B.id(o)));
  g.world.setBlock(x0 - 3, y, z0 - 9, B.id('furnace'), 3);
  g.world.setBlockEntity(x0 - 3, y, z0 - 9, { type: 'furnace', ...g.furnaceLogic.createState(), input: { id: g.items.id('iron_ore'), count: 4, damage: 0 }, fuel: { id: g.items.id('coal'), count: 2, damage: 0 } });
  g.world.setBlock(x0 - 4, y, z0 - 9, B.id('crafting_table'));
  g.world.setBlock(x0 + 4, y, z0 - 9, B.id('chest'), 3);
  for (let x = x0 + 1; x <= x0 + 4; x++) g.world.setBlock(x, y - 1, z0 - 4, B.id('lava'));
  p.teleport(x0 + 0.5, y, z0 + 0.5); p.yaw = 0; p.pitch = -0.12;
  g.select(1);
});
await shot('07-cave-torches', 'Grotta upplyst av facklor, malmer, ugn, kista och lava', 3500);
await ev(() => { const g = window.blockheim.game; const p = g.player; g.interactBlock('furnace', Math.floor(p.x) - 3, 28, Math.floor(p.z) - 9); });
await shot('08-furnace', 'Ugn: bränsle brinner och järnmalm smälts', 2500);
await ev(() => window.blockheim.ui.inv.close());

// Night on the surface with hostile mobs.
await ev(() => {
  const g = window.blockheim.game; const B = g.blocks; const p = g.player;
  const s = g.meta.spawn;
  const x0 = Math.floor(s.x), z0 = Math.floor(s.z);
  const y = g.world.topSolidY(x0, z0) + 1;
  p.teleport(x0 + 0.5, y, z0 + 0.5); p.yaw = 0; p.pitch = -0.08;
  g.time = 24000 + 17500;
  g.entities.list = g.entities.list.filter((e) => e.type !== 'mob');
  const add = (kind, dx, dz) => { const m = g.entities.spawnMob(kind, x0 + dx + 0.5, g.world.topSolidY(x0 + dx, z0 + dz) + 1, z0 + dz + 0.5); m.yaw = Math.PI * 0.05; return m; };
  add('zombie', -2, -5); add('zombie', 2, -7); add('blastling', 0, -4);
  g.world.setBlock(x0 + 1, y, z0 - 2, B.id('torch'));
});
await shot('09-night-mobs', 'Natt: zombier och en Sprängling närmar sig, fackla lyser', 1200);

// Daytime animals.
await ev(() => {
  const g = window.blockheim.game; const p = g.player;
  g.time = 3000;
  g.entities.list = g.entities.list.filter((e) => e.type !== 'mob');
  const x0 = Math.floor(p.x), z0 = Math.floor(p.z);
  ['pig', 'cow', 'sheep', 'chicken'].forEach((k, i) => {
    const x = x0 - 3 + i * 2, z = z0 - 5;
    const m = g.entities.spawnMob(k, x + 0.5, g.world.topSolidY(x, z) + 1, z + 0.5);
    m.yaw = 0.5; m.wanderTimer = 999;
  });
});
await shot('10-animals', 'Djur: gris, ko, får och höna', 1500);

// Underwater.
await ev(() => {
  const g = window.blockheim.game; const p = g.player; const B = g.blocks;
  const x0 = Math.floor(p.x), z0 = Math.floor(p.z);
  for (let x = x0 - 4; x <= x0 + 4; x++) for (let z = z0 - 4; z <= z0 + 4; z++) for (let y = 50; y <= 62; y++) {
    g.world.setBlock(x, y, z, (Math.abs(x - x0) === 4 || Math.abs(z - z0) === 4 || y === 50) ? B.id('sand') : B.id('water'));
  }
  g.entities.list = g.entities.list.filter((e) => e.type !== 'mob');
  p.teleport(x0 + 0.5, 55, z0 + 0.5); p.pitch = 0.3;
});
await shot('11-underwater', 'Under vattnet: blå dimma och luftbubblor i HUD', 2500);

// Death screen.
await ev(() => { const g = window.blockheim.game; g.player.teleport(g.meta.spawn.x, g.meta.spawn.y + 1, g.meta.spawn.z); g.survival.damage(100, 'zombie'); });
await shot('12-death', 'Dödsskärm med orsak och knapp för att återuppstå', 800);
await ev(() => window.blockheim.app.respawn());

// Creative mode: flying and the item palette.
await ev(() => window.blockheim.app.quitToTitle());
await page.waitForFunction(() => window.blockheim.ui.screenName === 'title');
await ev(() => window.blockheim.app.startWorld({ id: 'evidence-creative', name: 'Kreativ', seed: 99, seedText: '99', mode: 'creative', difficulty: 'normal', created: Date.now(), lastPlayed: Date.now() }));
await ready();
await ev(() => { const g = window.blockheim.game; g.player.flying = true; g.player.teleport(g.player.x, g.player.y + 22, g.player.z); g.player.flying = true; g.player.pitch = -0.4; g.time = 1500; });
await shot('13-creative-flying', 'Kreativt läge: flygning med upp/ner-knappar', 3000);
await ev(() => window.blockheim.ui.inv.open('inventory'));
await shot('14-creative-inventory', 'Kreativt förråd med flikar', 800);
await ev(() => window.blockheim.ui.inv.close());
await ev(() => window.blockheim.app.pause());
await shot('15-pause', 'Pausmeny', 500);
await ev(() => window.blockheim.ui.showSettings(() => window.blockheim.ui.showPause()));
await shot('16-settings', 'Inställningar: siktavstånd, känslighet, ljud, språk m.m.', 500);

// Portrait layout.
await page.setViewportSize({ width: 390, height: 844 });
await ev(() => window.blockheim.app.resume());
await shot('17-portrait', 'Stående läge på telefon', 2000);

fs.writeFileSync(path.join(outDir, `${date}-README.md`), [
  `# Blockheim - run-and-observe evidence (${date})`,
  '',
  'Captured by `npm run evidence` from the production build (`dist/index.html`) in headless Chromium',
  '(SwiftShader WebGL) emulating a phone in landscape, 844×390 CSS px at 2× density, Swedish locale.',
  'Web fonts are blocked in the capture sandbox, so menus show the fallback typeface.',
  '',
  ...shots.map((s) => `- \`${s.file}\` - ${s.caption}`),
  '',
  problems.length ? `Problems logged:\n${problems.map((p) => `- ${p}`).join('\n')}` : 'No page errors were logged during the session.',
  '',
].join('\n'));

await browser.close();
server.close();
if (problems.length) {
  console.error(problems.join('\n'));
  process.exitCode = 1;
}
