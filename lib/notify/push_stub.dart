import 'push_types.dart';

/// Fora do navegador não há notificações push do app web.
Future<PushInfo> pushInfo() async => const PushInfo.unsupported();

Future<PushResult> pushEnable(String vapidPublicKey) async => const PushResult(
      ok: false,
      error: 'As notificações do app web só funcionam no navegador.',
    );

/// Retorna o endereço da inscrição removida (vazio se não havia).
Future<String> pushDisable() async => '';
