import 'package:adaptive_routine/domain/holiday.dart';
import 'package:adaptive_routine/domain/models.dart';
import 'package:adaptive_routine/notify/reminders.dart';
import 'package:flutter_test/flutter_test.dart';

TimeBlock block(String id, String title, DateTime start,
        {BlockStatus status = BlockStatus.planned, int minutes = 60}) =>
    TimeBlock(
      id: id,
      title: title,
      layer: Layer.dynamic,
      start: start,
      end: start.add(Duration(minutes: minutes)),
      status: status,
    );

void main() {
  final now = DateTime(2026, 11, 20, 10); // sexta, 10h

  test('aviso 30 min antes; compromissos sem tempo, feitos ou longe ficam de fora', () {
    final r = buildReminders(
      now: now,
      holidays: const {},
      blocks: [
        block('a', 'Aula', DateTime(2026, 11, 20, 11)), // aviso às 10:30
        block('b', 'Já em cima', DateTime(2026, 11, 20, 10, 20)), // aviso seria 9:50, já passou
        block('c', 'Feito', DateTime(2026, 11, 20, 12), status: BlockStatus.done),
        block('d', 'Faltou', DateTime(2026, 11, 20, 13), status: BlockStatus.missed),
        block('e', 'Longe', DateTime(2026, 12, 20, 9)), // além de 14 dias
      ],
    );
    final events = r.where((x) => x.key.startsWith('b:')).toList();
    expect(events.map((x) => x.title), ['Aula']);
    expect(events.single.fireAt, DateTime(2026, 11, 20, 10, 30));
    expect(events.single.body, contains('11:00'));
  });

  test('a chave muda quando o horário muda (o aviso antigo é substituído)', () {
    String keyFor(DateTime start) => buildReminders(
          now: now,
          holidays: const {},
          blocks: [block('a', 'Aula', start)],
        ).firstWhere((x) => x.key.startsWith('b:')).key;
    expect(keyFor(DateTime(2026, 11, 20, 11)), isNot(keyFor(DateTime(2026, 11, 20, 15))));
  });

  test('resumo das 21h sobre o dia seguinte', () {
    final r = buildReminders(
      now: now,
      holidays: const {},
      blocks: [
        block('x', 'Cálculo', DateTime(2026, 11, 21, 8)),
        block('y', 'Academia', DateTime(2026, 11, 21, 20, 30)),
      ],
    );
    final s = r.singleWhere((x) => x.key == 's:2026-11-21');
    expect(s.fireAt, DateTime(2026, 11, 20, 21));
    expect(s.title, 'Sua rotina de amanhã');
    expect(s.body, contains('2 compromissos'));
    expect(s.body, contains('Cálculo às 08:00'));
  });

  test('feriado de amanhã vira título do resumo, mesmo sem compromissos', () {
    final r = buildReminders(
      now: now,
      holidays: {'2026-11-21': const Holiday(name: 'Dia da Consciência', kind: DayKind.holiday)},
      blocks: const [],
    );
    final s = r.singleWhere((x) => x.key == 's:2026-11-21');
    expect(s.title, 'Amanhã: Dia da Consciência');
    expect(s.body, 'Nenhum compromisso marcado.');
  });

  test('sem nada amanhã, não há resumo; resumo que já passou também não', () {
    final r = buildReminders(now: DateTime(2026, 11, 20, 22), holidays: const {}, blocks: [
      block('z', 'Hoje à noite', DateTime(2026, 11, 21, 8)),
    ]);
    // às 22h o resumo de hoje (21h) já passou; o de amanhã (dia 21 às 21h) é sobre o dia 22: vazio
    expect(r.where((x) => x.key.startsWith('s:')), isEmpty);
  });

  test('toJson usa horário UTC', () {
    final j = buildReminders(
      now: now,
      holidays: const {},
      blocks: [block('a', 'Aula', DateTime(2026, 11, 20, 11))],
    ).firstWhere((x) => x.key.startsWith('b:')).toJson();
    expect(j['fire_at'], endsWith('Z'));
    expect(j['title'], 'Aula');
  });
}
