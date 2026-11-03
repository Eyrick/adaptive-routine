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

  test('normalizeText ignora acento e pontuação', () {
    expect(normalizeText('Lóg. Prog.'), 'log prog');
    expect(normalizeText('ÁGUA, Coração!'), 'agua coracao');
  });

  test('"13:30h" não deixa o h solto', () {
    final b = parseIntent('estudar hoje 13:30h', now)!;
    expect(b.title, 'Estudar');
    expect(b.start, DateTime(2026, 11, 1, 13, 30));
  });

  test('aula cancelada: frase do usuário', () {
    const text = 'aula de Log. Prog. 13:30h de quinta feira foi cancelada';
    expect(isCancelStatement(text), isTrue);
    expect(isCancelStatement('reunião hoje às 17h'), isFalse);
    final r = parseRemove(text, now, DateTime(2026, 10, 26));
    expect(r.day, DateTime(2026, 11, 5)); // quinta desta semana já passou
    expect(r.minutes, 13 * 60 + 30);
    expect(r.words, ['log', 'prog']);
  });

  test('restaurar', () {
    expect(isRestoreCommand('restaurar Lóg. Prog. quinta'), isTrue);
    expect(isRestoreCommand('desfazer cancelamento quinta'), isTrue);
    expect(isRestoreCommand('remover quinta'), isFalse);
  });

  final ws = DateTime(2026, 10, 26);

  test('remarcar: origem com dia e destino só com hora', () {
    final mv = parseMove('remarque academia de sexta para 15h', now, ws);
    expect(isMoveCommand('remarque academia de sexta para 15h'), isTrue);
    expect(mv.source.words, ['academia']);
    expect(mv.source.day, DateTime(2026, 11, 6)); // sexta desta semana já passou
    expect(mv.targetMinutes, 15 * 60);
    expect(mv.targetDay, isNull);
  });

  test('remarcar: destino com dia e hora', () {
    const t = 'passa o Estudar ML para amanhã 10h';
    expect(isMoveCommand(t), isTrue);
    final mv = parseMove(t, now, ws);
    expect(mv.source.words, ['estudar', 'ml']);
    expect(mv.targetDay, DateTime(2026, 11, 2));
    expect(mv.targetMinutes, 600);
  });

  test('remarcar: origem com horário', () {
    final mv = parseMove('mover reunião de hoje 17h para amanhã 19h', now, ws);
    expect(mv.source.day, DateTime(2026, 11, 1));
    expect(mv.source.minutes, 17 * 60);
    expect(mv.source.words, ['reuniao']);
    expect(mv.targetDay, DateTime(2026, 11, 2));
    expect(mv.targetMinutes, 19 * 60);
  });

  test('adiar e adiantar', () {
    expect(parseMove('adiar reunião 30 min', now, ws).shift, const Duration(minutes: 30));
    expect(parseMove('adiantar reunião 1 hora', now, ws).shift, const Duration(minutes: -60));
    expect(parseMove('adiar reunião por meia hora', now, ws).shift, const Duration(minutes: 30));
  });

  test('verbo comum só vira remarcação com "para"', () {
    expect(isMoveCommand('preciso passar na farmácia hoje 17h'), isFalse);
    expect(isMoveCommand('mudar reunião para amanhã'), isTrue);
    expect(isMoveCommand('reunião hoje 17h'), isFalse);
  });

  test('desfazer e restaura', () {
    expect(isUndoCommand('desfazer'), isTrue);
    expect(isUndoCommand('desfazer cancelamento quinta'), isFalse);
    expect(isRestoreCommand('restaura logica quinta'), isTrue);
  });
}
