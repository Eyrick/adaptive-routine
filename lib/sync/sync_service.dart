import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/models.dart';
import '../features/calendar/calendar_controller.dart';
import 'snapshot.dart';
import 'sync_backend.dart';

enum SyncStatus { notConfigured, signedOut, idle, syncing, offline, conflict, error }

class SyncState {
  const SyncState({
    this.status = SyncStatus.notConfigured,
    this.email,
    this.lastSync,
    this.message,
    this.conflict,
  });

  final SyncStatus status;
  final String? email;
  final DateTime? lastSync;
  final String? message;
  final RemoteState? conflict; // agenda da nuvem, quando há conflito

  SyncState copyWith({
    SyncStatus? status,
    String? email,
    bool clearEmail = false,
    DateTime? lastSync,
    String? message,
    bool clearMessage = false,
    RemoteState? conflict,
    bool clearConflict = false,
  }) =>
      SyncState(
        status: status ?? this.status,
        email: clearEmail ? null : (email ?? this.email),
        lastSync: lastSync ?? this.lastSync,
        message: clearMessage ? null : (message ?? this.message),
        conflict: clearConflict ? null : (conflict ?? this.conflict),
      );
}

/// A nuvem de verdade (Supabase) entra por aqui; null = sem sincronização.
final syncBackendProvider = Provider<SyncBackend?>((ref) => null);

final syncProvider = NotifierProvider<SyncService, SyncState>(SyncService.new);

/// Sincroniza a agenda entre aparelhos, guardando um único "retrato" da agenda
/// por conta, com número de versão.
///
/// * Este aparelho lembra a versão e o texto da última sincronização.
/// * Mudou só aqui: envia (só se a nuvem ainda estiver na versão conhecida).
/// * Mudou só na nuvem: adota a da nuvem.
/// * Mudou nos dois: pergunta ao usuário qual manter (conflito).
class SyncService extends Notifier<SyncState> {
  int? _base; // versão da nuvem na última sincronização
  String? _last; // texto canônico da agenda na última sincronização
  String? _metaUid; // conta a que _base e _last pertencem
  RemoteState? _pendingRemote;

  Future<void>? _run;
  bool _again = false;
  int _retries = 0;
  bool _disposed = false;
  Timer? _debounce;

  late final Future<void> _ready = _loadMeta();

  SyncBackend? get _backend => ref.read(syncBackendProvider);

  String get _device => kIsWeb ? 'web' : defaultTargetPlatform.name;

  @override
  SyncState build() {
    final backend = ref.watch(syncBackendProvider);
    if (backend == null) return const SyncState(status: SyncStatus.notConfigured);

    final authSub = backend.authChanges.listen((_) => _onAuthChanged());
    // Mudou algo aqui: envia depois de 2 s sem novas mudanças.
    ref.listen(calendarProvider.select((s) => (s.blocks, s.rules, s.holidays)), (_, __) {
      _debounce?.cancel();
      _debounce = Timer(const Duration(seconds: 2), () => syncNow());
    });
    // Confere a nuvem de tempos em tempos e ao voltar para o app.
    final periodic = Timer.periodic(const Duration(seconds: 30), (_) => syncNow());
    final lifecycle = AppLifecycleListener(onResume: () => syncNow());

    ref.onDispose(() {
      _disposed = true;
      authSub.cancel();
      periodic.cancel();
      _debounce?.cancel();
      lifecycle.dispose();
    });

    unawaited(_boot());
    return SyncState(
      status: backend.signedIn ? SyncStatus.idle : SyncStatus.signedOut,
      email: backend.email,
    );
  }

  Future<void> _boot() async {
    await _ready;
    final b = _backend;
    if (_disposed || b == null || !b.signedIn) return;
    await syncNow();
  }

  // ---------------------------------------------------------------- conta

  /// Entra ou cria a conta. Retorna uma mensagem de erro, ou null se deu certo.
  Future<String?> authenticate(String email, String password, {required bool create}) async {
    final b = _backend;
    if (b == null) return 'A sincronização não está configurada.';
    if (email.isEmpty || password.isEmpty) return 'Preencha o e-mail e a senha.';
    try {
      if (create) {
        await b.signUp(email, password);
      } else {
        await b.signIn(email, password);
      }
    } on SyncAuthException catch (e) {
      return e.message;
    } catch (e) {
      return _isOffline(e) ? 'Sem conexão com a internet.' : 'Não foi possível entrar: $e';
    }
    _setStateSafe(state.copyWith(status: SyncStatus.idle, email: b.email, clearMessage: true));
    unawaited(syncNow());
    return null;
  }

  Future<void> signOut() async {
    final b = _backend;
    if (b == null) return;
    try {
      await b.signOut();
    } catch (_) {}
    _base = null;
    _last = null;
    _metaUid = null;
    _pendingRemote = null;
    await _saveMeta();
    _setStateSafe(const SyncState(status: SyncStatus.signedOut));
  }

  void _onAuthChanged() {
    final b = _backend;
    if (b == null) return;
    final wasIn = state.status != SyncStatus.signedOut;
    if (b.signedIn == wasIn) return; // só reage a entrar ou sair
    if (b.signedIn) {
      _setStateSafe(state.copyWith(status: SyncStatus.idle, email: b.email));
      unawaited(syncNow());
    } else {
      _setStateSafe(const SyncState(status: SyncStatus.signedOut));
    }
  }

  // ----------------------------------------------------------- sincronizar

  /// Sincroniza agora. Chamadas durante uma sincronização esperam por ela.
  Future<void> syncNow() {
    final b = _backend;
    if (b == null || !b.signedIn) return Future.value();
    if (state.status == SyncStatus.conflict) return Future.value(); // espera o usuário decidir
    final running = _run;
    if (running != null) {
      _again = true;
      return running;
    }
    final run = _syncLoop(b).whenComplete(() => _run = null);
    _run = run;
    return run;
  }

  Future<void> _syncLoop(SyncBackend b) async {
    await _ready;
    _retries = 0;
    do {
      _again = false;
      _setStateSafe(state.copyWith(status: SyncStatus.syncing, clearMessage: true));
      try {
        await _syncOnce(b);
      } catch (e) {
        _setStateSafe(state.copyWith(
          status: _isOffline(e) ? SyncStatus.offline : SyncStatus.error,
          message: _isOffline(e) ? null : '$e',
        ));
        return;
      }
    } while (_again && _retries++ < 3 && state.status != SyncStatus.conflict);
  }

  Snapshot _localSnapshot() {
    final s = ref.read(calendarProvider);
    return Snapshot(
      blocks: s.blocks.where((b) => b.layer == Layer.dynamic).toList(),
      rules: s.rules,
      holidays: s.holidays,
    );
  }

  void _applyRemote(Snapshot snap) =>
      ref.read(calendarProvider.notifier).loadSnapshot(snap.blocks, snap.rules, snap.holidays);

  Future<void> _syncOnce(SyncBackend b) async {
    if (_metaUid != b.userId) {
      // outra conta: a memória da última sincronização não vale
      _base = null;
      _last = null;
      _metaUid = b.userId;
    }

    final remote = await b.fetch();
    final local = _localSnapshot();
    final localJson = local.canonical();

    // Nada na nuvem ainda: sobe o que há neste aparelho.
    if (remote == null) {
      final v = await b.insert(local.toJson(), _device);
      if (v == null) {
        _again = true; // outro aparelho criou antes: tenta de novo
        return;
      }
      await _setSynced(v, localJson);
      return;
    }

    final remoteSnap = Snapshot.fromJson(remote.data);
    final remoteJson = remoteSnap.canonical();

    // Este aparelho nunca sincronizou com esta conta.
    if (_base == null) {
      if (localJson == remoteJson) {
        await _setSynced(remote.version, remoteJson);
      } else if (local.isPristine) {
        _applyRemote(remoteSnap);
        await _setSynced(remote.version, remoteJson);
      } else {
        _setConflict(remote);
      }
      return;
    }

    // A nuvem está na versão que este aparelho conhece.
    if (remote.version == _base) {
      if (localJson != _last) {
        final v = await b.update(local.toJson(), _base!, _device);
        if (v == null) {
          _again = true; // a nuvem mudou no meio: refaz
          return;
        }
        await _setSynced(v, localJson);
      } else {
        _markDone();
      }
      return;
    }

    // A nuvem mudou desde a última sincronização.
    if (localJson == _last) {
      _applyRemote(remoteSnap); // aqui nada mudou: adota a nuvem
      await _setSynced(remote.version, remoteJson);
    } else if (localJson == remoteJson) {
      await _setSynced(remote.version, remoteJson);
    } else {
      _setConflict(remote); // mudou nos dois lugares
    }
  }

  void _setConflict(RemoteState remote) {
    _pendingRemote = remote;
    _setStateSafe(state.copyWith(status: SyncStatus.conflict, conflict: remote, clearMessage: true));
  }

  /// Resolve um conflito: [useRemote] adota a agenda da nuvem (descarta as
  /// mudanças deste aparelho); senão, este aparelho substitui a da nuvem.
  Future<void> resolveConflict({required bool useRemote}) async {
    final remote = _pendingRemote;
    final b = _backend;
    if (remote == null || b == null) return;
    try {
      if (useRemote) {
        final snap = Snapshot.fromJson(remote.data);
        _applyRemote(snap);
        await _setSynced(remote.version, snap.canonical());
      } else {
        final local = _localSnapshot();
        final v = await b.overwrite(local.toJson(), remote.version, _device);
        await _setSynced(v, local.canonical());
      }
      _pendingRemote = null;
    } catch (e) {
      _setStateSafe(state.copyWith(
        status: _isOffline(e) ? SyncStatus.offline : SyncStatus.error,
        message: _isOffline(e) ? null : '$e',
      ));
    }
  }

  // ------------------------------------------------------------- memória

  Future<void> _setSynced(int version, String json) async {
    _base = version;
    _last = json;
    await _saveMeta();
    _markDone();
  }

  void _markDone() => _setStateSafe(state.copyWith(
        status: SyncStatus.idle,
        lastSync: DateTime.now(),
        clearConflict: true,
        clearMessage: true,
      ));

  Future<void> _loadMeta() async {
    try {
      final p = await SharedPreferences.getInstance();
      _base = p.getInt('sync.base');
      _last = p.getString('sync.last');
      _metaUid = p.getString('sync.uid');
    } catch (_) {}
  }

  Future<void> _saveMeta() async {
    try {
      final p = await SharedPreferences.getInstance();
      if (_base == null) {
        await p.remove('sync.base');
      } else {
        await p.setInt('sync.base', _base!);
      }
      if (_last == null) {
        await p.remove('sync.last');
      } else {
        await p.setString('sync.last', _last!);
      }
      if (_metaUid == null) {
        await p.remove('sync.uid');
      } else {
        await p.setString('sync.uid', _metaUid!);
      }
    } catch (_) {}
  }

  void _setStateSafe(SyncState s) {
    if (!_disposed) state = s;
  }

  bool _isOffline(Object e) {
    final t = e.toString().toLowerCase();
    return t.contains('socket') ||
        t.contains('host lookup') ||
        t.contains('network') ||
        t.contains('clientexception') ||
        t.contains('timeout') ||
        t.contains('connection');
  }
}
