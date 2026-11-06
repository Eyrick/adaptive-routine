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

  test('janela de dias: anda de 3 em 3, semana acompanha e há limite', () async {
    final c = make();
    final ctl = c.read(calendarProvider.notifier);
    final s0 = c.read(calendarProvider);

    ctl.shiftDays(3);
    final s1 = c.read(calendarProvider);
    expect(s1.focusDay, DateTime(s0.focusDay.year, s0.focusDay.month, s0.focusDay.day + 3));
    expect(s1.weekStart.weekday, DateTime.monday);

    ctl.shiftDays(7 * 200); // além do limite: ignorado
    expect(c.read(calendarProvider).focusDay, s1.focusDay);

    ctl.goToToday();
    expect(c.read(calendarProvider).focusDay, s0.focusDay);
  });

  test('marcar realizada/não realizada: dinâmica e ocorrência fixa, com desfazer', () async {
    const rule = FixedRule(
      id: 'r1',
      title: 'Aula',
      weekdays: [1, 2, 3, 4, 5, 6, 7],
      startMin: 9 * 60,
      endMin: 10 * 60,
    );
    final c = make(rules: [rule]);
    final ctl = c.read(calendarProvider.notifier);

    ctl.submit('dentista amanhã 14h');
    await tick();
    ctl.setStatus(dyn(c, 'Dentista').single, BlockStatus.done);
    await tick();
    expect(dyn(c, 'Dentista').single.status, BlockStatus.done);

    bool isTomorrow(TimeBlock b) => b.start.day == tomorrow.day && b.start.month == tomorrow.month;
    final aula = c.read(calendarProvider).blocks.firstWhere((b) => b.layer == Layer.fixed && isTomorrow(b));
    ctl.setStatus(aula, BlockStatus.missed);
    await tick();
    final st = c.read(calendarProvider);
    expect(st.rules.single.statuses[dateKey(tomorrow)], BlockStatus.missed);
    expect(st.blocks.firstWhere((b) => b.layer == Layer.fixed && isTomorrow(b)).status, BlockStatus.missed);
    // outro dia segue pendente
    expect(st.blocks.firstWhere((b) => b.layer == Layer.fixed && !isTomorrow(b)).status, BlockStatus.planned);

    ctl.submit('desfazer');
    await tick();
    expect(c.read(calendarProvider).rules.single.statuses, isEmpty);
  });

  test('ações do menu do bloco: remarcar, remover e cancelar só o dia', () async {
    const rule = FixedRule(
      id: 'r1',
      title: 'Aula',
      weekdays: [1, 2, 3, 4, 5, 6, 7],
      startMin: 9 * 60,
      endMin: 10 * 60,
    );
    final c = make(rules: [rule]);
    final ctl = c.read(calendarProvider.notifier);

    ctl.submit('dentista amanhã 14h');
    await tick();
    final d = dyn(c, 'Dentista').single;
    ctl.setStatus(d, BlockStatus.missed);
    await tick();

    // remarcar: volta a pendente no novo horário
    ctl.moveBlock(dyn(c, 'Dentista').single,
        DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 16));
    await tick();
    final moved = dyn(c, 'Dentista').single;
    expect(moved.start.hour, 16);
    expect(moved.status, BlockStatus.planned);

    // cancelar só o dia da aula
    final aula = c.read(calendarProvider).blocks.firstWhere((b) =>
        b.layer == Layer.fixed && b.start.day == tomorrow.day && b.start.month == tomorrow.month);
    ctl.cancelOccurrence(aula);
    await tick();
    expect(c.read(calendarProvider).rules.single.skipDates, [dateKey(tomorrow)]);

    // remover a atividade
    ctl.removeBlock(dyn(c, 'Dentista').single);
    await tick();
    expect(dyn(c, 'Dentista'), isEmpty);
  });
}
