import 'package:supabase_flutter/supabase_flutter.dart';

import 'sync_backend.dart';

/// Nuvem de verdade: guarda um registro por conta na tabela `user_state`
/// (veja supabase/schema.sql). A segurança vem das regras de acesso por linha.
class SupabaseBackend implements SyncBackend {
  SupabaseBackend(this._c);
  final SupabaseClient _c;

  @override
  bool get signedIn => _c.auth.currentSession != null;

  @override
  String? get email => _c.auth.currentUser?.email;

  @override
  String? get userId => _c.auth.currentUser?.id;

  @override
  Stream<void> get authChanges => _c.auth.onAuthStateChange.map((_) {});

  @override
  Future<void> signIn(String email, String password) async {
    try {
      await _c.auth.signInWithPassword(email: email, password: password);
    } on AuthException catch (e) {
      throw SyncAuthException(_translate(e.message));
    }
  }

  @override
  Future<void> signUp(String email, String password) async {
    try {
      await _c.auth.signUp(email: email, password: password);
    } on AuthException catch (e) {
      throw SyncAuthException(_translate(e.message));
    }
    if (_c.auth.currentSession == null) {
      // a confirmação por e-mail está ligada no projeto
      throw SyncAuthException(
          'Conta criada. Confirme o e-mail que você recebeu e depois toque em Entrar.');
    }
  }

  @override
  Future<void> signOut() => _c.auth.signOut();

  @override
  Future<RemoteState?> fetch() async {
    final uid = userId;
    if (uid == null) return null;
    final row = await _c
        .from('user_state')
        .select('version, data, updated_at, device')
        .eq('user_id', uid)
        .maybeSingle();
    if (row == null) return null;
    return RemoteState(
      version: (row['version'] as num).toInt(),
      data: (row['data'] as Map).cast<String, dynamic>(),
      updatedAt: DateTime.tryParse('${row['updated_at']}'),
      device: row['device'] as String?,
    );
  }

  @override
  Future<int?> insert(Map<String, dynamic> data, String device) async {
    final uid = userId;
    if (uid == null) return null;
    try {
      await _c.from('user_state').insert({
        'user_id': uid,
        'data': data,
        'version': 1,
        'device': device,
      });
      return 1;
    } on PostgrestException catch (e) {
      if (e.code == '23505') return null; // já existe: outro aparelho criou antes
      rethrow;
    }
  }

  @override
  Future<int?> update(Map<String, dynamic> data, int baseVersion, String device) async {
    final uid = userId;
    if (uid == null) return null;
    final rows = await _c
        .from('user_state')
        .update({
          'data': data,
          'version': baseVersion + 1,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
          'device': device,
        })
        .eq('user_id', uid)
        .eq('version', baseVersion)
        .select('version');
    return rows.isEmpty ? null : baseVersion + 1;
  }

  @override
  Future<int> overwrite(Map<String, dynamic> data, int remoteVersion, String device) async {
    final uid = userId;
    if (uid == null) throw SyncAuthException('Sem conta conectada.');
    await _c.from('user_state').update({
      'data': data,
      'version': remoteVersion + 1,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
      'device': device,
    }).eq('user_id', uid);
    return remoteVersion + 1;
  }

  // ---- Notificações -------------------------------------------------------

  @override
  Future<void> savePushSubscription(Map<String, dynamic> subscription, String device) async {
    final uid = userId;
    if (uid == null) return;
    final keys = (subscription['keys'] as Map).cast<String, dynamic>();
    await _c.from('push_subscriptions').upsert({
      'endpoint': subscription['endpoint'],
      'user_id': uid,
      'p256dh': keys['p256dh'],
      'auth': keys['auth'],
      'device': device,
    }, onConflict: 'endpoint');
  }

  @override
  Future<void> removePushSubscription(String endpoint) async {
    await _c.from('push_subscriptions').delete().eq('endpoint', endpoint);
  }

  @override
  Future<void> replaceReminders(List<Map<String, dynamic>> items) async {
    await _c.rpc('sync_reminders', params: {'items': items});
  }

  @override
  Future<String> sendTestPush() async {
    final res = await _c.functions.invoke('send-reminders', body: {'test': true});
    final d = res.data;
    if (d is Map) {
      if (d['message'] != null) return '${d['message']}';
      final sent = d['sent'] ?? 0;
      final gone = d['gone'] ?? 0;
      final failed = d['failed'] ?? 0;
      return 'Enviado para $sent aparelho(s)'
          '${gone == 0 ? '' : ', $gone expirado(s)'}'
          '${failed == 0 ? '' : ', $failed com falha'}.';
    }
    return '$d';
  }

  String _translate(String m) {
    final t = m.toLowerCase();
    if (t.contains('invalid login')) return 'E-mail ou senha incorretos.';
    if (t.contains('already registered')) return 'Este e-mail já tem conta. Use "Entrar".';
    if (t.contains('not confirmed')) return 'Confirme o e-mail antes de entrar.';
    if (t.contains('at least')) return 'A senha precisa ter pelo menos 6 caracteres.';
    if (t.contains('valid email') || t.contains('invalid email')) return 'E-mail inválido.';
    if (t.contains('rate limit')) return 'Muitas tentativas. Espere um pouco e tente de novo.';
    return m;
  }
}
