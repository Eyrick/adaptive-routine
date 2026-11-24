// Ponte entre o app (Dart) e as notificações do navegador (Web Push).
// Todas as funções devolvem um texto JSON e nunca "rejeitam": erros viram
// { ok: false, error: "..." }, o que facilita mostrar a mensagem no app.
(function () {
  function isIos() {
    return /iPad|iPhone|iPod/.test(navigator.userAgent) ||
      (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);
  }
  function isStandalone() {
    return window.navigator.standalone === true ||
      (window.matchMedia && window.matchMedia('(display-mode: standalone)').matches);
  }
  function supported() {
    return 'serviceWorker' in navigator && 'PushManager' in window && 'Notification' in window;
  }
  function b64ToBytes(b64) {
    var pad = '='.repeat((4 - (b64.length % 4)) % 4);
    var s = (b64 + pad).replace(/-/g, '+').replace(/_/g, '/');
    var raw = atob(s);
    var out = new Uint8Array(raw.length);
    for (var i = 0; i < raw.length; i++) out[i] = raw.charCodeAt(i);
    return out;
  }
  function whenActive(reg) {
    return new Promise(function (resolve) {
      if (reg.active) return resolve(reg);
      var w = reg.installing || reg.waiting;
      if (!w) return resolve(reg);
      var t = setTimeout(function () { resolve(reg); }, 10000);
      w.addEventListener('statechange', function () {
        if (w.state === 'activated') { clearTimeout(t); resolve(reg); }
      });
    });
  }
  async function registration() {
    var reg = await navigator.serviceWorker.getRegistration('push/');
    if (!reg) reg = await navigator.serviceWorker.register('push-sw.js', { scope: 'push/' });
    return whenActive(reg);
  }

  window.rotinaPushInfo = async function () {
    var info = {
      supported: false, ios: isIos(), standalone: isStandalone(),
      permission: 'Notification' in window ? Notification.permission : 'unsupported',
      subscribed: false
    };
    try {
      info.supported = supported();
      if (info.supported) {
        var reg = await navigator.serviceWorker.getRegistration('push/');
        if (reg) info.subscribed = !!(await reg.pushManager.getSubscription());
      }
    } catch (e) { info.error = String(e); }
    return JSON.stringify(info);
  };

  // Precisa ser chamada direto do toque do usuário (o iPhone exige isso para
  // pedir a permissão): por isso o primeiro "await" é o pedido de permissão.
  window.rotinaPushEnable = async function (vapidKey) {
    try {
      if (!supported()) {
        return JSON.stringify({ ok: false, error: 'Este navegador não suporta notificações.' });
      }
      var perm = await Notification.requestPermission();
      if (perm !== 'granted') {
        return JSON.stringify({ ok: false, permission: perm, error: 'Permissão não concedida.' });
      }
      var reg = await registration();
      var sub = await reg.pushManager.getSubscription();
      if (!sub) {
        sub = await reg.pushManager.subscribe({
          userVisibleOnly: true,
          applicationServerKey: b64ToBytes(vapidKey)
        });
      }
      return JSON.stringify({ ok: true, subscription: sub.toJSON() });
    } catch (e) {
      return JSON.stringify({ ok: false, error: String(e && e.message ? e.message : e) });
    }
  };

  window.rotinaPushDisable = async function () {
    try {
      var reg = await navigator.serviceWorker.getRegistration('push/');
      if (!reg) return JSON.stringify({ ok: true, endpoint: '' });
      var sub = await reg.pushManager.getSubscription();
      if (!sub) return JSON.stringify({ ok: true, endpoint: '' });
      var endpoint = sub.endpoint;
      await sub.unsubscribe();
      return JSON.stringify({ ok: true, endpoint: endpoint });
    } catch (e) {
      return JSON.stringify({ ok: false, error: String(e && e.message ? e.message : e) });
    }
  };
})();
