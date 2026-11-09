import 'package:adaptive_routine/core/frame_stats.dart';
import 'package:adaptive_routine/data/holiday_repository.dart';
import 'package:adaptive_routine/data/rule_repository.dart';
import 'package:adaptive_routine/domain/fixed_rule.dart';
import 'package:adaptive_routine/domain/holiday.dart';
import 'package:adaptive_routine/domain/models.dart';
import 'package:adaptive_routine/domain/week.dart';
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
    expect(s1.weekStart.weekday, kWeekStart);

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

  test('reencaixe: aula nova colide com duas atividades, uma por vez', () async {
    final c = make();
    final ctl = c.read(calendarProvider.notifier);
    ctl.submit('reunião amanhã 9h');
    ctl.submit('dentista amanhã 10h');
    await tick();
    final reuniao0 = dyn(c, 'Reunião').single;
    final dentista0 = dyn(c, 'Dentista').single;

    // aula nova, das 9h30 às 10h30, colide com as duas
    ctl.saveRule(const FixedRule(
      id: 'r1',
      title: 'Aula',
      weekdays: [1, 2, 3, 4, 5, 6, 7],
      startMin: 9 * 60 + 30,
      endMin: 10 * 60 + 30,
    ));
    await tick();

    var p = c.read(calendarProvider).pending;
    expect(p, isNotNull);
    expect(p!.incoming.title, 'Reunião'); // por ordem de horário
    expect(p.reflowQueue, [dentista0.id]);
    expect(p.cancelLabel, 'Manter onde está');
    expect(p.suggestions, isNotEmpty);

    ctl.resolve(0);
    await tick();
    expect(dyn(c, 'Reunião').single.start, isNot(reuniao0.start));
    p = c.read(calendarProvider).pending;
    expect(p, isNotNull);
    expect(p!.incoming.title, 'Dentista'); // passa para a próxima

    ctl.cancelPending(); // mantém o dentista onde está
    await tick();
    expect(c.read(calendarProvider).pending, isNull);
    expect(dyn(c, 'Dentista').single.start, dentista0.start);
  });

  test('não realizada: oferece reencaixar só atividade dinâmica', () async {
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
    final d0 = dyn(c, 'Dentista').single;

    ctl.setStatus(d0, BlockStatus.missed);
    await tick();
    final p = c.read(calendarProvider).pending;
    expect(p, isNotNull);
    expect(p!.cancelLabel, 'Deixar assim');
    expect(p.suggestions.every((s) => s.start != d0.start), isTrue);

    ctl.resolve(0);
    await tick();
    final d1 = dyn(c, 'Dentista').single;
    expect(d1.status, BlockStatus.planned);
    expect(d1.start, isNot(d0.start));
    expect(c.read(calendarProvider).pending, isNull);

    // aula da rotina fixa não realizada: não oferece reencaixe
    final aula = c.read(calendarProvider).blocks.firstWhere((b) =>
        b.layer == Layer.fixed && b.start.day == tomorrow.day && b.start.month == tomorrow.month);
    ctl.setStatus(aula, BlockStatus.missed);
    await tick();
    expect(c.read(calendarProvider).pending, isNull);

    // "Deixar assim" mantém a atividade como não realizada
    ctl.setStatus(d1, BlockStatus.missed);
    await tick();
    expect(c.read(calendarProvider).pending, isNotNull);
    ctl.cancelPending();
    await tick();
    expect(dyn(c, 'Dentista').single.status, BlockStatus.missed);
  });

  test('uma frase com dois eventos cria os dois', () async {
    final c = make();
    final ctl = c.read(calendarProvider.notifier);

    ctl.submit('reunião amanhã 9h e dentista amanhã 10h');
    await tick();
    expect(dyn(c, 'Reunião').single.start.hour, 9);
    expect(dyn(c, 'Dentista').single.start.hour, 10);
    expect(c.read(calendarProvider).pending, isNull);
  });

  test('dois eventos numa frase: o segundo espera a negociação do primeiro', () async {
    final c = make();
    final ctl = c.read(calendarProvider.notifier);

    ctl.submit('estudo amanhã 9h');
    await tick();
    ctl.submit('reunião amanhã 9h e dentista amanhã 11h'); // a reunião bate com o estudo
    await tick();
    final p = c.read(calendarProvider).pending;
    expect(p, isNotNull);
    expect(p!.queuedCommands, ['dentista amanhã 11h']);
    expect(dyn(c, 'Dentista'), isEmpty); // ainda não entrou

    ctl.submit('sim');
    await tick();
    ctl.resolve(0);
    await tick();
    expect(c.read(calendarProvider).pending, isNull);
    expect(dyn(c, 'Reunião').single.start.hour, 9);
    expect(dyn(c, 'Dentista').single.start.hour, 11); // entrou depois
  });

  test('feriado: esconde os fixos, atividade dinâmica fica, desmarcar devolve e desfazer', () async {
    const rule = FixedRule(
      id: 'r1',
      title: 'Aula',
      weekdays: [1, 2, 3, 4, 5, 6, 7],
      startMin: 9 * 60,
      endMin: 10 * 60,
    );
    final repo = MemoryHolidayRepository();
    final c = ProviderContainer(overrides: [
      initialRulesProvider.overrideWithValue([rule]),
      holidayRepositoryProvider.overrideWithValue(repo),
    ]);
    addTearDown(c.dispose);
    final ctl = c.read(calendarProvider.notifier);
    final key = dateKey(tomorrow);
    bool tomorrowFixed(TimeBlock b) =>
        b.layer == Layer.fixed && b.start.day == tomorrow.day && b.start.month == tomorrow.month;

    expect(c.read(calendarProvider).blocks.where(tomorrowFixed), hasLength(1));
    ctl.submit('dentista amanhã 14h'); // atividade dinâmica no dia
    await tick();

    ctl.setHoliday(tomorrow, name: 'Feriado de teste', hidesFixed: true);
    await tick();
    var st = c.read(calendarProvider);
    expect(st.blocks.where(tomorrowFixed), isEmpty); // aula não acontece
    expect(dyn(c, 'Dentista'), hasLength(1)); // atividade dinâmica continua
    expect(st.holidays[key]!.name, 'Feriado de teste');
    expect((await repo.load())!.containsKey(key), isTrue); // salvo

    ctl.setHoliday(tomorrow, name: 'Feriado de teste', hidesFixed: false);
    await tick();
    expect(c.read(calendarProvider).blocks.where(tomorrowFixed), hasLength(1)); // continua

    ctl.setHoliday(tomorrow, name: 'Feriado de teste', hidesFixed: true);
    ctl.removeHoliday(tomorrow);
    await tick();
    st = c.read(calendarProvider);
    expect(st.holidays, isEmpty);
    expect(st.blocks.where(tomorrowFixed), hasLength(1)); // desmarcar devolve a aula

    ctl.submit('desfazer'); // desfaz a remoção do feriado
    await tick();
    expect(c.read(calendarProvider).holidays.containsKey(key), isTrue);
    expect(c.read(calendarProvider).blocks.where(tomorrowFixed), isEmpty);
  });

  test('evento: alguns compromissos fixos acontecem e outros não', () async {
    const a = FixedRule(
        id: 'ra', title: 'Aula A', weekdays: [1, 2, 3, 4, 5, 6, 7], startMin: 9 * 60, endMin: 10 * 60);
    const b = FixedRule(
        id: 'rb', title: 'Aula B', weekdays: [1, 2, 3, 4, 5, 6, 7], startMin: 14 * 60, endMin: 15 * 60);
    final c = ProviderContainer(overrides: [
      initialRulesProvider.overrideWithValue([a, b]),
    ]);
    addTearDown(c.dispose);
    final ctl = c.read(calendarProvider.notifier);

    List<String> fixedTomorrow() => c
        .read(calendarProvider)
        .blocks
        .where((x) => x.layer == Layer.fixed && x.start.day == tomorrow.day && x.start.month == tomorrow.month)
        .map((x) => x.title)
        .toList()
      ..sort();

    expect(fixedTomorrow(), ['Aula A', 'Aula B']);

    // evento: só a Aula B acontece (regra geral "não acontece", B é exceção)
    ctl.setHoliday(tomorrow,
        name: 'Semana de provas', kind: DayKind.event, hidesFixed: true, exceptions: ['rb']);
    await tick();
    expect(fixedTomorrow(), ['Aula B']);
    expect(c.read(calendarProvider).holidays[dateKey(tomorrow)]!.kind, DayKind.event);

    // agora o contrário: regra geral "acontece", só a Aula B é exceção e some
    ctl.setHoliday(tomorrow, name: 'Semana de provas', hidesFixed: false, exceptions: ['rb']);
    await tick();
    expect(fixedTomorrow(), ['Aula A']);

    ctl.removeHoliday(tomorrow);
    await tick();
    expect(fixedTomorrow(), ['Aula A', 'Aula B']);
  });

  test('"desempenho" liga e desliga o medidor', () async {
    final c = make();
    final ctl = c.read(calendarProvider.notifier);
    addTearDown(() => showFrameStats.value = false);

    expect(showFrameStats.value, isFalse);
    ctl.submit('desempenho');
    expect(showFrameStats.value, isTrue);
    ctl.submit('desempenho');
    expect(showFrameStats.value, isFalse);
  });
}
