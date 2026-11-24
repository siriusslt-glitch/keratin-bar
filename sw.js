/* Service worker: офлайн-кэш приложения (регистрируется только на https) */
const CACHE = 'keratin-bar-v1';
const CORE = ['./', './index.html', './manifest.webmanifest', './icon-192.png', './icon-512.png'];

self.addEventListener('install', e => {
  e.waitUntil(
    caches.open(CACHE).then(c => c.addAll(CORE)).then(() => self.skipWaiting())
  );
});

self.addEventListener('activate', e => {
  e.waitUntil(
    caches.keys()
      .then(ks => Promise.all(ks.filter(k => k !== CACHE).map(k => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', e => {
  const req = e.request;
  if (req.method !== 'GET') return;
  const url = new URL(req.url);
  const cacheable =
    url.origin === location.origin ||
    url.hostname === 'cdn.jsdelivr.net' ||
    url.hostname === 'tessdata.projectnaptha.com';
  if (!cacheable) return;

  if (req.mode === 'navigate') {
    // навигация: сеть -> кэш (обновления применяются сразу при онлайне, офлайн — из кэша)
    e.respondWith(
      fetch(req).then(r => {
        const cp = r.clone();
        caches.open(CACHE).then(c => c.put('./index.html', cp));
        return r;
      }).catch(() => caches.match('./index.html'))
    );
    return;
  }

  // остальное: кэш сразу, фоновое обновление (движок OCR работает офлайн после первой загрузки)
  e.respondWith(
    caches.match(req).then(hit => {
      const net = fetch(req).then(r => {
        if (r && r.ok) {
          const cp = r.clone();
          caches.open(CACHE).then(c => c.put(req, cp));
        }
        return r;
      }).catch(() => hit);
      return hit || net;
    })
  );
});
