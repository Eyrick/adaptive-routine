import 'package:adaptive_routine/features/chat/mock_intent.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 11, 1, 12);

  test('intervalo "8h as 9:30"', () {
    final b = parseIntent('Estudar ML hoje 8h as 9:30', now)!;
    expect(b.title, 'Estudar ML');
    expect(b.start, DateTime(2026, 11, 1, 8));
    expect(b.end, DateTime(2026, 11, 1, 9, 30));
  });

  test('horário único usa 1h', () {
    final b = parseIntent('reunião hoje às 17h', now)!;
    expect(b.title, 'Reunião');
    expect(b.end.difference(b.start), const Duration(hours: 1));
  });

  test('duração explícita', () {
    final b = parseIntent('dentista amanhã 14h por 2 horas', now)!;
    expect(b.start, DateTime(2026, 11, 2, 14));
    expect(b.end, DateTime(2026, 11, 2, 16));
  });

  test('comando de remoção por dia e hora', () {
    expect(isRemoveCommand('remover programação de Dom 8h'), isTrue);
    expect(isRemoveCommand('reunião hoje 17h'), isFalse);
    final r = parseRemove('remover programação de Dom 8h', now, DateTime(2026, 10, 26));
    expect(r.day, DateTime(2026, 11, 1));
    expect(r.minutes, 480);
    expect(r.words, isEmpty);
  });

  test('remoção por título', () {
    final r = parseRemove('cancelar Estudar ML de hoje', now, DateTime(2026, 10, 26));
    expect(r.day, DateTime(2026, 11, 1));
    expect(r.words, ['estudar', 'ml']);
  });

  test('verbo inicial e "de" interno no título; duração 2:30h', () {
    final b = parseIntent('adicione Estudo de Física hoje 14h por 2:30h', now)!;
    expect(b.title, 'Estudo de Física');
    expect(b.start, DateTime(2026, 11, 1, 14));
    expect(b.end, DateTime(2026, 11, 1, 16, 30));
  });

  test('"com duração de 45min"', () {
    final b = parseIntent('adicione Estudar PAA 14h com duração de 45min', now)!;
    expect(b.title, 'Estudar PAA');
    expect(b.end.difference(b.start), const Duration(minutes: 45));
  });

  test('dia da semana ao criar', () {
    // 2026-11-01 é domingo; quinta = 5/11
    final b = parseIntent('reunião quinta 15h', now)!;
    expect(b.start, DateTime(2026, 11, 5, 15));
    expect(b.title, 'Reunião');
  });
}