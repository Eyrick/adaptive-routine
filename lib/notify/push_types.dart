/// Situação das notificações do navegador neste aparelho.
class PushInfo {
  const PushInfo({
    required this.supported,
    required this.ios,
    required this.standalone,
    required this.permission,
    required this.subscribed,
  });

  /// Fora do navegador (Windows, Android nativo): não se aplica.
  const PushInfo.unsupported()
      : supported = false,
        ios = false,
        standalone = false,
        permission = 'unsupported',
        subscribed = false;

  final bool supported; // o navegador sabe receber notificações push
  final bool ios;
  final bool standalone; // o app está instalado na Tela de Início
  final String permission; // default, granted, denied ou unsupported
  final bool subscribed; // este aparelho já está inscrito
}

class PushResult {
  const PushResult({required this.ok, this.subscription, this.error, this.permission});
  final bool ok;
  final Map<String, dynamic>? subscription; // endpoint e chaves
  final String? error;
  final String? permission;
}
