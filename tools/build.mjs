/**
 * Production build.
 *
 *   dist/index.html            self-contained game (JS + CSS inlined), PWA-enabled
 *   dist/manifest.webmanifest  install metadata
 *   dist/sw.js                 offline cache
 *   dist/icon-192.png, icon-512.png, apple-touch-icon.png
 *   dist/artifact.html         body-only variant for hosts that supply their own <head>
 *
 * Run: npm run build
 */
import fs from 'node:fs';
import path from 'node:path';
import * as esbuild from 'esbuild';
import { encodePng } from './png.mjs';
import { createRegistries } from '../src/world/registry.js';
import { buildAtlas, collectTextureNames } from '../src/render/textures.js';

const root = path.resolve(path.dirname(new URL(import.meta.url).pathname), '..');
const src = (p) => path.join(root, 'src', p);
const dist = (p) => path.join(root, 'dist', p);
const readJson = (p) => JSON.parse(fs.readFileSync(src(`data/${p}`), 'utf8'));
const pkg = JSON.parse(fs.readFileSync(path.join(root, 'package.json'), 'utf8'));

fs.mkdirSync(dist(''), { recursive: true });

const result = await esbuild.build({
  entryPoints: [src('main.js')],
  bundle: true,
  format: 'esm',
  minify: true,
  target: 'es2022',
  write: false,
  legalComments: 'none',
});
const js = result.outputFiles[0].text.replaceAll('</script', '<\\/script');
const css = fs.readFileSync(src('styles.css'), 'utf8');
const html = fs.readFileSync(src('index.html'), 'utf8');

const pwaTags = [
  '<link rel="manifest" href="manifest.webmanifest">',
  '<link rel="icon" type="image/png" href="icon-192.png">',
  '<link rel="apple-touch-icon" href="apple-touch-icon.png">',
].join('\n');
const swRegister = `<script>if('serviceWorker' in navigator&&location.protocol!=='file:'){addEventListener('load',()=>navigator.serviceWorker.register('sw.js').catch(()=>{}))}</script>`;

const full = html
  .replace('<!--PWA-->', pwaTags)
  .replace('<link rel="stylesheet" href="styles.css">', () => `<style>\n${css}\n</style>`)
  .replace('<script type="module" src="game.js"></script>', () => `${swRegister}\n<script type="module">${js}</script>`);
fs.writeFileSync(dist('index.html'), full);

// Body-only variant for hosts that supply their own document skeleton: <title>, font
// links, style, markup and script. Three.js is loaded from the jsDelivr npm CDN there,
// so the file itself contains only this project's code and data.
const threeVersion = JSON.parse(fs.readFileSync(path.join(root, 'node_modules', 'three', 'package.json'), 'utf8')).version;
const THREE_CDN = `https://cdn.jsdelivr.net/npm/three@${threeVersion}/build/three.module.js`;
const lite = await esbuild.build({
  entryPoints: [src('main.js')],
  bundle: true,
  format: 'esm',
  minify: true,
  target: 'es2022',
  write: false,
  legalComments: 'none',
  external: ['three'],
});
const liteJs = lite.outputFiles[0].text.replace(/from\s*"three"/g, `from"${THREE_CDN}"`).replaceAll('</script', '<\\/script');
if (/from\s*"three"/.test(liteJs) || !liteJs.includes(THREE_CDN)) throw new Error('three import was not rewritten');
const head = html.match(/<title>[\s\S]*?<\/title>/)[0];
const fontLinks = [...html.matchAll(/<link rel="(?:preconnect|stylesheet)" href="https:\/\/fonts[^>]*>/g)].map((m) => m[0]).join('\n');
const body = html.split('<!--BODY-->')[1].split('<!--/BODY-->')[0];
const artifact = `${head}\n${fontLinks}\n<style>\n${css}\n</style>\n${body}\n<script type="module">${liteJs}</script>\n`;
fs.writeFileSync(dist('artifact.html'), artifact);

fs.writeFileSync(dist('manifest.webmanifest'), JSON.stringify({
  name: 'Blockheim',
  short_name: 'Blockheim',
  description: 'Ett kubiskt överlevnads- och byggspel.',
  start_url: './',
  scope: './',
  display: 'fullscreen',
  orientation: 'landscape',
  background_color: '#14120f',
  theme_color: '#1c1a16',
  lang: 'sv',
  icons: [
    { src: 'icon-192.png', sizes: '192x192', type: 'image/png', purpose: 'any maskable' },
    { src: 'icon-512.png', sizes: '512x512', type: 'image/png', purpose: 'any maskable' },
  ],
}, null, 2));

fs.writeFileSync(dist('sw.js'), `// Offline cache for Blockheim ${pkg.version}
const CACHE = 'blockheim-${pkg.version}-${Date.now().toString(36)}';
const FILES = ['./', 'index.html', 'manifest.webmanifest', 'icon-192.png', 'icon-512.png', 'apple-touch-icon.png'];
self.addEventListener('install', (e) => { e.waitUntil(caches.open(CACHE).then((c) => c.addAll(FILES)).then(() => self.skipWaiting())); });
self.addEventListener('activate', (e) => { e.waitUntil(caches.keys().then((keys) => Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k)))).then(() => self.clients.claim())); });
self.addEventListener('fetch', (e) => {
  if (e.request.method !== 'GET') return;
  e.respondWith(caches.match(e.request).then((hit) => hit || fetch(e.request).then((res) => {
    if (res.ok && new URL(e.request.url).origin === location.origin) { const copy = res.clone(); caches.open(CACHE).then((c) => c.put(e.request, copy)); }
    return res;
  }).catch(() => caches.match('index.html'))));
});
`);

// App icon: an isometric grass block on a sky gradient, rendered from the game's own textures.
const { blocks, items } = createRegistries(readJson('blocks.json'), readJson('items.json'));
const atlas = buildAtlas(collectTextureNames(blocks, items), readJson('textures.json'), readJson('sprites.json'));
const tint = readJson('textures.json').defaultGrassTint;

function sample(name, u, v) {
  const t = atlas.tileImage(name);
  const x = Math.min(t.size - 1, Math.max(0, Math.floor(u * t.size)));
  const y = Math.min(t.size - 1, Math.max(0, Math.floor(v * t.size)));
  const [r, g, b, a] = t.get(x, y);
  if (a === 254) return [(r * tint[0]) / 255, (g * tint[1]) / 255, (b * tint[2]) / 255, 255];
  return [r, g, b, a];
}

function renderIcon(size) {
  const out = new Uint8ClampedArray(size * size * 4);
  const s = size * 0.36;
  const cx = size / 2, cy = size * 0.2;
  // Face parallelograms: origin, u-axis, v-axis.
  const faces = [
    { tex: 'grass_top', o: [cx, cy], U: [s, s * 0.5], V: [-s, s * 0.5], shade: 1 },
    { tex: 'grass_side', o: [cx - s, cy + s * 0.5], U: [s, s * 0.5], V: [0, s * 1.15], shade: 0.8 },
    { tex: 'grass_side', o: [cx, cy + s], U: [s, -s * 0.5], V: [0, s * 1.15], shade: 0.6 },
  ];
  for (let y = 0; y < size; y++) {
    for (let x = 0; x < size; x++) {
      const t = y / size;
      let c = [120 + (194 - 120) * t, 167 + (216 - 167) * t, 255, 255];
      for (const f of faces) {
        const det = f.U[0] * f.V[1] - f.U[1] * f.V[0];
        const dx = x + 0.5 - f.o[0], dy = y + 0.5 - f.o[1];
        const u = (dx * f.V[1] - dy * f.V[0]) / det;
        const v = (f.U[0] * dy - f.U[1] * dx) / det;
        if (u >= 0 && u < 1 && v >= 0 && v < 1) {
          const p = sample(f.tex, u, v);
          if (p[3] > 0) c = [p[0] * f.shade, p[1] * f.shade, p[2] * f.shade, 255];
        }
      }
      out.set(c, (y * size + x) * 4);
    }
  }
  return encodePng(size, size, out);
}
fs.writeFileSync(dist('icon-192.png'), renderIcon(192));
fs.writeFileSync(dist('icon-512.png'), renderIcon(512));
fs.writeFileSync(dist('apple-touch-icon.png'), renderIcon(180));

const kb = (f) => `${(fs.statSync(dist(f)).size / 1024).toFixed(0)} KiB`;
console.log(`Built dist/index.html (${kb('index.html')}), dist/artifact.html (${kb('artifact.html')}), icons, manifest, sw.js`);
