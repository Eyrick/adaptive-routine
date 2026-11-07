import 'dart:io';

import 'package:adaptive_routine/data/holiday_repository.dart';
import 'package:adaptive_routine/domain/fixed_rule.dart';
import 'package:adaptive_routine/domain/holiday.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final monday = DateTime(2026, 10, 26);
  const calc = FixedRule(
    id: 'r1',
    title: 'Cálculo II',
    weekdays: [1, 3],
    startMin: 8 * 60,
    endMin: 10 * 60,
  );
  final quarta = dateKey(DateTime(2026, 10, 28));

  test('feriado esconde a rotina fixa só quando hidesFixed', () {
    final hidden = expandRules([calc], monday, 0, 0,
        holidays: {quarta: const Holiday(name: 'X', hidesFixed: true)});
    expect(hidden.where((b) => b.start.day == 28), isEmpty);
    expect(hidden.where((b) => b.start.day == 26), isNotEmpty); // outro dia segue

    final kept = expandRules([calc], monday, 0, 0,
        holidays: {quarta: const Holiday(hidesFixed: false)});
    expect(kept.where((b) => b.start.day == 28), isNotEmpty);
  });

  test('JSON ida e volta, arquivo e arquivo corrompido', () async {
    final h = Holiday.fromJson(const Holiday(name: 'Natal', hidesFixed: false).toJson());
    expect(h.name, 'Natal');
    expect(h.hidesFixed, isFalse);
    expect(Holiday.fromJson(<String, dynamic>{}).hidesFixed, isTrue); // padrão

    final dir = await Directory.systemTemp.createTemp('ar_holidays');
    final repo = FileHolidayRepository(File('${dir.path}/holidays.json'));
    expect(await repo.load(), isNull);
    await repo.save({quarta: const Holiday(name: 'Natal', hidesFixed: false)});
    final loaded = await repo.load();
    expect(loaded![quarta]!.name, 'Natal');
    expect(loaded[quarta]!.hidesFixed, isFalse);

    final bad = File('${dir.path}/holidays.json');
    await bad.writeAsString('não é json');
    expect(await repo.load(), isNull);
    expect(await File('${bad.path}.corrupt').exists(), isTrue);
    await dir.delete(recursive: true);
  });

  test('por compromisso: exceções fazem o contrário da regra geral', () {
    const a = FixedRule(id: 'a', title: 'Aula A', weekdays: [3], startMin: 8 * 60, endMin: 9 * 60);
    const b = FixedRule(id: 'b', title: 'Aula B', weekdays: [3], startMin: 14 * 60, endMin: 15 * 60);

    // regra geral "não acontece", mas A é exceção: só A acontece
    const soA = Holiday(hidesFixed: true, exceptions: ['a']);
    expect(soA.hides('a'), isFalse);
    expect(soA.hides('b'), isTrue);
    final r1 = expandRules([a, b], monday, 0, 0, holidays: {quarta: soA});
    expect(r1.where((x) => x.start.day == 28).map((x) => x.title), ['Aula A']);

    // regra geral "acontece", mas B é exceção: só B some
    const semB = Holiday(hidesFixed: false, exceptions: ['b']);
    final r2 = expandRules([a, b], monday, 0, 0, holidays: {quarta: semB});
    expect(r2.where((x) => x.start.day == 28).map((x) => x.title), ['Aula A']);

    // compromisso cadastrado depois segue a regra geral
    expect(soA.hides('novo'), isTrue);
    expect(semB.hides('novo'), isFalse);
  });

  test('JSON com exceções e arquivo antigo (só hidesFixed)', () {
    final h = Holiday.fromJson(
        const Holiday(name: 'Evento', hidesFixed: true, exceptions: ['a']).toJson());
    expect(h.exceptions, ['a']);
    expect(h.hides('a'), isFalse);

    final old = Holiday.fromJson({'name': 'Natal', 'hidesFixed': true}); // versão anterior
    expect(old.exceptions, isEmpty);
    expect(old.hides('qualquer'), isTrue); // continua: nenhum compromisso acontece
  });

  test('tipo: feriado ou evento, com padrão feriado para arquivos antigos', () {
    final ev = Holiday.fromJson(
        const Holiday(name: 'Congresso', kind: DayKind.event, hidesFixed: false).toJson());
    expect(ev.kind, DayKind.event);
    expect(ev.name, 'Congresso');
    expect(Holiday.fromJson({'name': 'Natal', 'hidesFixed': true}).kind, DayKind.holiday);
    expect(const Holiday().kind, DayKind.holiday);
  });
}
