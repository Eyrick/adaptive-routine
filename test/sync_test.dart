import 'dart:async';

import 'package:adaptive_routine/data/rule_repository.dart';
import 'package:adaptive_routine/domain/fixed_rule.dart';
import 'package:adaptive_routine/domain/models.dart';
import 'package:adaptive_routine/features/calendar/calendar_controller.dart';
import 'package:adaptive_routine/sync/snapshot.dart';
import 'package:adaptive_routine/sync/sync_backend.dart';
import 'package:adaptive_routine/sync/sync_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Nuvem de mentira, em memória, que se comporta como a de verdade:
/// versões, atualização condicional e "já existe".
class FakeBackend implements SyncBackend {
  FakeBackend({this.remote});
  RemoteState? remote;
  bool _signedIn = true;
  final _auth = StreamController<void>.broadcast();

  @override
  bool get signedIn => _signedIn;
  @override
  String? get email => 'eu@teste.com';
  @override
  String? get userId => 'u1';
  @override
  Stream<void> get authChanges => _auth.stream;

  @override
  Future<void> signIn(String email, String password) async {
    _signedIn = true;
    _auth.add(null);
  }

  @override
  Future<void> signUp(String email, String password) async {
    _signedIn = true;
    _auth.add(null);
  }

  @override
  Future<void> signOut() async {
    _signedIn = false;
    _auth.add(null);
  }

  @override
  Future<RemoteState?> fetch() async => remote;

  @override
  Future<int?> insert(Map<String, dynamic> data, String device) async {
    if (remote != null) return null;
    remote = RemoteState(version: 1, data: data, device: device);
    return 1;
  }

  @override
  Future<int?> update(Map<String, dynamic> data, int baseVersion, String device) async {
    if (remote == null || remote!.version != baseVersion) return null;
    remote = RemoteState(version: baseVersion + 1, data: data, device: device);
    return baseVersion + 1;
  }

  @override
  Future<int> overwrite(Map<String, dynamic> data, int remoteVersion, String device) async {
    remote = RemoteState(version: remoteVersion + 1, data: data, device: device);
    return remoteVersion + 1;
  }
}

const ra = FixedRule(id: 'ra', title: 'Aula', weekdays: [1, 2, 3, 4, 5], startMin: 540, endMin: 600);
const rb = FixedRule(id: 'rb', title: 'Lab', weekdays: [2, 4], startMin: 840, endMin: 900);

final dentista = TimeBlock(
  id: 'dy-remoto',
  title: 'Dentista',
  layer: Layer.dynamic,
  start: DateTime(2026, 11, 20, 14),
  end: DateTime(2026, 11, 20, 15),
);

ProviderContainer boot(FakeBackend fb, {List<FixedRule>? rules}) {
  final c = ProviderContainer(overrides: [
    syncBackendProvider.overrideWithValue(fb),
    initialRulesProvider.overrideWithValue(rules),
  ]);
  addTearDown(c.dispose);
  return c;
}

Iterable<String> dynTitles(ProviderContainer c) => c
    .read(calendarProvider)
    .blocks
    .where((b) => b.layer == Layer.dynamic)
    .map((b) => b.title);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('texto canônico não depende da ordem', () {
    final a = Snapshot(blocks: [dentista], rules: const [ra, rb], holidays: const {});
    final b = Snapshot(blocks: [dentista], rules: const [rb, ra], holidays: const {});
    expect(a.canonical(), b.canonical());
    expect(Snapshot.fromJson(a.toJson()).canonical(), a.canonical());
  });

  test('primeira sincronização: sobe a agenda deste aparelho', () async {
    final fb = FakeBackend();
    final c = boot(fb, rules: const [ra]);
    await c.read(syncProvider.notifier).syncNow();

    expect(fb.remote!.version, 1);
    expect(Snapshot.fromJson(fb.remote!.data).rules.single.title, 'Aula');
    expect(c.read(syncProvider).status, SyncStatus.idle);
  });

  test('aparelho novo adota a agenda da nuvem, sem enviar o exemplo inicial', () async {
    final remoteSnap = Snapshot(blocks: [dentista], rules: const [ra], holidays: const {});
    final fb = FakeBackend(remote: RemoteState(version: 3, data: remoteSnap.toJson()));
    final c = boot(fb); // sem rotina: aparelho "de fábrica"
    await c.read(syncProvider.notifier).syncNow();

    expect(c.read(calendarProvider).rules.single.id, 'ra');
    expect(dynTitles(c), contains('Dentista'));
    expect(dynTitles(c), isNot(contains('Estudo de Física')));
    expect(fb.remote!.version, 3); // nada foi enviado

    // o que veio da nuvem não entra no "desfazer"
    c.read(calendarProvider.notifier).submit('desfazer');
    expect(c.read(calendarProvider).messages.last.text, 'Não há nada para desfazer.');
  });

  test('mudança feita aqui é enviada e a versão sobe', () async {
    final fb = FakeBackend();
    final c = boot(fb, rules: const [ra]);
    final sync = c.read(syncProvider.notifier);
    await sync.syncNow(); // versão 1

    c.read(calendarProvider.notifier).submit('dentista amanhã 14h');
    await sync.syncNow();

    expect(fb.remote!.version, 2);
    expect(Snapshot.fromJson(fb.remote!.data).blocks.map((b) => b.title), contains('Dentista'));
  });

  test('mudança feita na nuvem é adotada quando aqui nada mudou', () async {
    final fb = FakeBackend();
    final c = boot(fb, rules: const [ra]);
    final sync = c.read(syncProvider.notifier);
    await sync.syncNow();

    // outro aparelho cadastra uma segunda aula
    final other = Snapshot(blocks: const [], rules: const [ra, rb], holidays: const {});
    fb.remote = RemoteState(version: 2, data: other.toJson());
    await sync.syncNow();

    expect(c.read(calendarProvider).rules.length, 2);
    expect(c.read(syncProvider).status, SyncStatus.idle);
  });

  test('conflito: mudou aqui e na nuvem. Usar a da nuvem', () async {
    final fb = FakeBackend();
    final c = boot(fb, rules: const [ra]);
    final sync = c.read(syncProvider.notifier);
    await sync.syncNow();

    c.read(calendarProvider.notifier).submit('dentista amanhã 14h'); // muda aqui
    final other = Snapshot(blocks: const [], rules: const [ra, rb], holidays: const {});
    fb.remote = RemoteState(version: 2, data: other.toJson()); // e na nuvem
    await sync.syncNow();

    expect(c.read(syncProvider).status, SyncStatus.conflict);
    await sync.resolveConflict(useRemote: true);

    expect(c.read(syncProvider).status, SyncStatus.idle);
    expect(c.read(calendarProvider).rules.length, 2);
    expect(dynTitles(c), isNot(contains('Dentista')));
  });

  test('conflito: mudou aqui e na nuvem. Manter a deste aparelho', () async {
    final fb = FakeBackend();
    final c = boot(fb, rules: const [ra]);
    final sync = c.read(syncProvider.notifier);
    await sync.syncNow();

    c.read(calendarProvider.notifier).submit('dentista amanhã 14h');
    final other = Snapshot(blocks: const [], rules: const [ra, rb], holidays: const {});
    fb.remote = RemoteState(version: 2, data: other.toJson());
    await sync.syncNow();
    expect(c.read(syncProvider).status, SyncStatus.conflict);

    await sync.resolveConflict(useRemote: false);

    expect(fb.remote!.version, 3);
    expect(Snapshot.fromJson(fb.remote!.data).blocks.map((b) => b.title), contains('Dentista'));
    expect(c.read(syncProvider).status, SyncStatus.idle);
  });

  test('dois aparelhos com agendas diferentes e sem histórico: pergunta', () async {
    final remoteSnap = Snapshot(blocks: const [], rules: const [rb], holidays: const {});
    final fb = FakeBackend(remote: RemoteState(version: 1, data: remoteSnap.toJson()));
    final c = boot(fb, rules: const [ra]); // este aparelho já tem a sua rotina
    await c.read(syncProvider.notifier).syncNow();

    expect(c.read(syncProvider).status, SyncStatus.conflict);
    expect(c.read(calendarProvider).rules.single.id, 'ra'); // nada foi trocado sem perguntar
  });
}
