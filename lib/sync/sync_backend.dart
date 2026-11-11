/// Estado da agenda guardado na nuvem.
class RemoteState {
  const RemoteState({required this.version, required this.data, this.updatedAt, this.device});
  final int version;
  final Map<String, dynamic> data;
  final DateTime? updatedAt;
  final String? device;
}

/// Erro de login ou cadastro, com mensagem pronta para mostrar ao usuário.
class SyncAuthException implements Exception {
  SyncAuthException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// O que o motor de sincronização precisa da nuvem. A implementação real usa
/// o Supabase (supabase_backend.dart); nos testes, uma nuvem de mentira.
abstract class SyncBackend {
  bool get signedIn;
  String? get email;
  String? get userId;

  /// Avisa quando alguém entra ou sai da conta.
  Stream<void> get authChanges;

  Future<void> signIn(String email, String password);
  Future<void> signUp(String email, String password);
  Future<void> signOut();

  /// null = ainda não há agenda na nuvem.
  Future<RemoteState?> fetch();

  /// Cria a agenda na nuvem. Retorna a versão, ou null se outro aparelho
  /// criou antes.
  Future<int?> insert(Map<String, dynamic> data, String device);

  /// Atualiza só se a versão na nuvem ainda for [baseVersion]. Retorna a nova
  /// versão, ou null se a nuvem mudou nesse meio tempo.
  Future<int?> update(Map<String, dynamic> data, int baseVersion, String device);

  /// Sobrescreve sem conferir (quando o usuário escolhe "manter este aparelho").
  Future<int> overwrite(Map<String, dynamic> data, int remoteVersion, String device);
}
