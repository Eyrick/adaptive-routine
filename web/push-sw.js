// Service worker só das notificações (separado do service worker do Flutter).
// Ele recebe o aviso enviado pelo servidor e mostra a notificação. No iPhone,
// todo aviso recebido PRECISA mostrar uma notificação.

self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (event) => event.waitUntil(self.clients.claim()));

self.addEventListener('push', (event) => {
  let data = {};
  try {
    data = event.data ? event.data.json() : {};
  } catch (e) {
    data = { title: 'Rotina', body: event.data ? event.data.text() : '' };
  }
  const title = data.title || 'Rotina';
  event.waitUntil(
    self.registration.showNotification(title, {
      body: data.body || '',
      icon: 'icons/Icon-192.png',
      badge: 'icons/Icon-192.png',
      tag: data.tag || undefined,
      data: { url: data.url || './' },
    })
  );
});

// Tocar na notificação abre (ou volta para) o app.
self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const url = (event.notification.data && event.notification.data.url) || './';
  event.waitUntil(
    (async () => {
      const all = await self.clients.matchAll({ type: 'window', includeUncontrolled: true });
      for (const c of all) {
        if ('focus' in c) return c.focus();
      }
      return self.clients.openWindow(url);
    })()
  );
});
