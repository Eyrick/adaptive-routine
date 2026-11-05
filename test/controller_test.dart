import 'package:adaptive_routine/data/rule_repository.dart';
import 'package:adaptive_routine/domain/fixed_rule.dart';
import 'package:adaptive_routine/domain/models.dart';
import 'package:adaptive_routine/features/calendar/calendar_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Deixa os ouvintes do provider (pilha de desfazer, gravação) rodarem.
Future<void> tick() => Future<void>.delayed(Duration.zero);

void main() {
  final n = DateTime.now();
  final tomorrow = DateTime(n.year, n.month, n.day + 1);

  ProviderContainer make({List<FixedRule>? rules}) {
    final c = ProviderContainer(overrides: [initialRulesProvider.overrideWithValue(rules)]);
    addTearDown(c.dispose);
    return c;
  }

  List<TimeBlock> dyn(ProviderContainer c, String title) => c
      .read(calendarProvider)
      .blocks
      .where((b) => b.layer == Layer.dynamic && b.title == title)
      .toList();

  test('remarcar para horário livre e desfazer', () async {
    final c = make();
    final ctl = c.read(calendarProvider.notifier);

    ctl.submit('reunião amanhã 10h');
    await tick();
    expect(dyn(c, 'Reunião').single.start,
        DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 10));

    ctl.submit('remarcar reunião para amanhã 11h');
    await tick();
    expect(dyn(c, 'Reunião').single.start.hour, 11);

    ctl.submit('desfazer');
    await tick();
    expect(dyn(c, 'Reunião').single.start.hour, 10);
  });

  test('remarcar com choque pergunta; cancelar mantém o original', () async {
    final c = make();
    final ctl = c.read(calendarProvider.notifier);

    ctl.submit('reunião amanhã 10h');
    ctl.submit('dentista amanhã 11h');
    await tick();
    ctl.submit('remarcar dentista para amanhã 10h');
    await tick();
    final pending = c.read(calendarProvider).pending;
    expect(pending, isNotNull);
    expect(pending!.replaces, isNotNull);

    ctl.submit('cancelar');
    await tick();
    expect(c.read(calendarProvider).pending, isNull);
    expect(dyn(c, 'Dentista').single.start.hour, 11);
  });

  test('remarcar aula fixa de um dia: cancela só a data e cria atividade', () async {
    const rule = FixedRule(
      id: 'r1',
      title: 'Academia',
      weekdays: [1, 2, 3, 4, 5, 6, 7],
      startMin: 20 * 60 + 30,
      endMin: 22 * 60,
    );
    final c = make(rules: [rule]);
    final ctl = c.read(calendarProvider.notifier);

    ctl.submit('remarque academia de amanhã para 15h');
    await tick();
    final st = c.read(calendarProvider);
    expect(st.rules.single.skipDates, [dateKey(tomorrow)]);
    expect(
      st.blocks.where((b) =>
          b.layer == Layer.fixed && b.start.day == tomorrow.day && b.start.month == tomorrow.month),
      isEmpty,
    );
    final moved = dyn(c, 'Academia').single;
    expect(moved.start, DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 15));
    expect(moved.end, DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 16, 30));

    ctl.submit('desfazer');
    await tick();
    expect(c.read(calendarProvider).rules.single.skipDates, isEmpty);
    expect(dyn(c, 'Academia'), isEmpty);
  });

  test('eventos criados em sequência rápida têm ids diferentes', () async {
    final c = make();
    final ctl = c.read(calendarProvider.notifier);
    ctl.submit('reunião amanhã 10h');
    ctl.submit('dentista amanhã 11h');
    ctl.submit('academia amanhã 13h');
    await tick();
    final ids = c.read(calendarProvider).blocks.map((b) => b.id).toList();
    expect(ids.toSet().length, ids.length);
  });

  test('carregar exemplo só vale em agenda sem rotina e dá para desfazer', () async {
    final c = make();
    final ctl = c.read(calendarProvider.notifier);

    ctl.submit('carregar exemplo');
    await tick();
    expect(c.read(calendarProvider).rules.length, 2);
    expect(c.read(calendarProvider).blocks.where((b) => b.layer == Layer.fixed), isNotEmpty);

    ctl.submit('carregar exemplo'); // já há rotina: recusa
    await tick();
    expect(c.read(calendarProvider).rules.length, 2);

    ctl.submit('desfazer');
    await tick();
    expect(c.read(calendarProvider).rules, isEmpty);
  });
}
