// PROTOTYPE - NOT FOR PRODUCTION
// Question: Är det roligt att kapa skepp med Clash-liknande anfall?
// Date: 2026-10-22
//
// Gör att spelet fungerar utan nät när det installerats på hemskärmen.
// Nätet först (alltid senaste versionen), cachen som reserv.
const CACHE = 'kaparna-v2';
const FILES = ['./', './index.html', './css/style.css', './manifest.webmanifest',
  './js/data.js', './js/ship.js', './js/gfx.js', './js/art.js', './js/art-ship.js', './js/audio.js',
  './js/battle.js', './js/harbor.js', './js/ui.js', './js/main.js',
  './icons/icon-192.png', './icons/icon-512.png', './icons/apple-touch-icon.png'];

self.addEventListener('install', (e) => {
  e.waitUntil(caches.open(CACHE).then((c) => c.addAll(FILES)));
  self.skipWaiting();
});
self.addEventListener('activate', (e) => {
  e.waitUntil(caches.keys().then((ks) => Promise.all(ks.filter((k) => k !== CACHE).map((k) => caches.delete(k)))));
  self.clients.claim();
});
self.addEventListener('fetch', (e) => {
  if (e.request.method !== 'GET') return;
  const url = new URL(e.request.url);
  const font = url.hostname === 'fonts.googleapis.com' || url.hostname === 'fonts.gstatic.com';
  if (url.origin !== self.location.origin && !font) return;
  e.respondWith(
    fetch(e.request)
      .then((r) => { const copy = r.clone(); caches.open(CACHE).then((c) => c.put(e.request, copy)); return r; })
      .catch(() => caches.match(e.request, { ignoreSearch: true }))
  );
});
