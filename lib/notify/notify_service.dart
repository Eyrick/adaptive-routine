import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/calendar/calendar_controller.dart';
import '../sync/sync_config.dart';
import '../sync/sync_service.dart';
import 'push_client.dart';
import 'reminders.dart';

enum PushStatus { notConfigured, unsupported, needsInstall, off, denied, on, working }

class NotifyState {
  const NotifyState({this.status = PushStatus.working, this.message});
  final PushStatus status;
  final String? message;

  NotifyState copyWith({PushStatus? status, String? message, bool clearMessage = false}) =>
      NotifyState(
        status: status ?? this.status,
        message: clearMessage ? null : (message ?? this.message),
      );
}

final notifyProvider = NotifierProvider<NotifyService, NotifyState>(NotifyService.new);

/// Mantém as notificações em dia:
///
/// * **Lembretes (na nuvem):** sempre que a agenda muda, recalcula os avisos
///   dos próximos dias e envia para a nuvem, de onde o servidor os dispara na
///   hora certa. Todo aparelho com conta faz isso (e não só o que recebe o
///   aviso), para que mudar a agenda no computador atualize o aviso do iPhone.
/// * **Este aparelho:** liga e desliga o recebimento de avisos (Web Push).
class NotifyService extends Notifier<NotifyState> {
  Timer? _debounce;
  bool _disposed = false;

  /// Minutos de antecedência do aviso de cada compromisso.
  static const leadMinutes = 30;

  String get _device => kIsWeb ? 'web' : defaultTargetPlatform.name;

  @override
  NotifyState build() {
    final backend = ref.watch(syncBackendProvider);
    if (backend == null) {
      return const NotifyState(
        status: PushStatus.notConfigured,
        message: 'A sincronização não está configurada.',
      );
    }

    ref.listen(calendarProvider.select((s) => (s.blocks, s.holidays)), (_, __) => _schedule());
    ref.listen(syncProvider.select((s) => s.status), (prev, next) {
      if (next == SyncStatus.idle && prev != SyncStatus.idle) _schedule();
    });
    ref.onDispose(() {
      _disposed = true;
      _debounce?.cancel();
    });

    // Só depois de o estado inicial existir (não se mexe no estado durante o build).
    Future.microtask(refresh);
    _schedule();
    return const NotifyState(status: PushStatus.working);
  }

  void _schedule() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 5), () => syncReminders());
  }

  void _set(NotifyState s) {
    if (!_disposed) state = s;
  }

  /// Envia os lembretes dos próximos dias para a nuvem.
  Future<void> syncReminders() async {
    final backend = ref.read(syncBackendProvider);
    if (backend == null || !backend.signedIn) return;
    final s = ref.read(calendarProvider);
    final items = buildReminders(
      blocks: s.blocks,
      holidays: s.holidays,
      now: DateTime.now(),
      leadMinutes: leadMinutes,
    );
    try {
      await backend.replaceReminders([for (final r in items) r.toJson()]);
    } catch (e) {
      debugPrint('Lembretes não sincronizados: $e');
    }
  }

  /// Confere a situação das notificações neste aparelho.
  Future<void> refresh() async {
    if (vapidPublicKey.isEmpty) {
      _set(const NotifyState(status: PushStatus.notConfigured));
      return;
    }
    final i = await pushInfo();
    final PushStatus status;
    if (!i.supported) {
      status = (i.ios && !i.standalone) ? PushStatus.needsInstall : PushStatus.unsupported;
    } else if (i.permission == 'denied') {
      status = PushStatus.denied;
    } else {
      status = (i.subscribed && i.permission == 'granted') ? PushStatus.on : PushStatus.off;
    }
    _set(NotifyState(status: status));
  }

  /// Liga as notificações neste aparelho. Deve ser chamada direto de um toque
  /// do usuário: o iPhone só deixa pedir a permissão assim.
  Future<void> enable() async {
    final backend = ref.read(syncBackendProvider);
    if (backend == null || vapidPublicKey.isEmpty) return;
    _set(const NotifyState(status: PushStatus.working));

    final r = await pushEnable(vapidPublicKey); // primeira coisa: mantém o gesto do toque
    if (!r.ok || r.subscription == null) {
      final denied = r.permission == 'denied';
      _set(NotifyState(
        status: denied ? PushStatus.denied : PushStatus.off,
        message: r.error ?? 'Não foi possível ativar.',
      ));
      return;
    }
    try {
      await backend.savePushSubscription(r.subscription!, _device);
      _set(const NotifyState(status: PushStatus.on, message: 'Notificações ativadas neste aparelho.'));
      unawaited(syncReminders());
    } catch (e) {
      _set(NotifyState(status: PushStatus.off, message: 'Não consegui registrar este aparelho: $e'));
    }
  }

  Future<void> disable() async {
    final backend = ref.read(syncBackendProvider);
    _set(const NotifyState(status: PushStatus.working));
    final endpoint = await pushDisable();
    try {
      if (backend != null && endpoint.isNotEmpty) await backend.removePushSubscription(endpoint);
    } catch (_) {}
    _set(const NotifyState(status: PushStatus.off, message: 'Notificações desativadas neste aparelho.'));
  }

  /// Pede ao servidor um aviso de teste agora.
  Future<void> sendTest() async {
    final backend = ref.read(syncBackendProvider);
    if (backend == null) return;
    final before = state.status;
    _set(const NotifyState(status: PushStatus.working));
    try {
      final msg = await backend.sendTestPush();
      _set(NotifyState(status: before, message: msg));
    } catch (e) {
      _set(NotifyState(status: before, message: 'Teste falhou: $e'));
    }
  }
}
