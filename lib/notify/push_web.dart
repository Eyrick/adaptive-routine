import 'dart:convert';
import 'dart:js_interop';

import 'push_types.dart';

// Funções definidas em web/push.js
@JS('rotinaPushInfo')
external JSPromise<JSString> _info();

@JS('rotinaPushEnable')
external JSPromise<JSString> _enable(JSString vapidKey);

@JS('rotinaPushDisable')
external JSPromise<JSString> _disable();

Future<PushInfo> pushInfo() async {
  try {
    final j = jsonDecode((await _info().toDart).toDart) as Map<String, dynamic>;
    return PushInfo(
      supported: j['supported'] == true,
      ios: j['ios'] == true,
      standalone: j['standalone'] == true,
      permission: (j['permission'] as String?) ?? 'unsupported',
      subscribed: j['subscribed'] == true,
    );
  } catch (_) {
    return const PushInfo.unsupported(); // por exemplo, push.js ainda não carregou
  }
}

Future<PushResult> pushEnable(String vapidPublicKey) async {
  try {
    // A chamada ao JavaScript acontece antes de qualquer "await", para o toque
    // do usuário ainda valer como gesto (o iPhone exige isso).
    final text = (await _enable(vapidPublicKey.toJS).toDart).toDart;
    final j = jsonDecode(text) as Map<String, dynamic>;
    return PushResult(
      ok: j['ok'] == true,
      subscription: (j['subscription'] as Map?)?.cast<String, dynamic>(),
      error: j['error'] as String?,
      permission: j['permission'] as String?,
    );
  } catch (e) {
    return PushResult(ok: false, error: 'Falha ao ativar: $e');
  }
}

Future<String> pushDisable() async {
  try {
    final j = jsonDecode((await _disable().toDart).toDart) as Map<String, dynamic>;
    return (j['endpoint'] as String?) ?? '';
  } catch (_) {
    return '';
  }
}
