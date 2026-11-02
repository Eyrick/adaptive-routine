import 'dart:io';

import 'package:adaptive_routine/data/rule_repository.dart';
import 'package:adaptive_routine/domain/fixed_rule.dart';
import 'package:adaptive_routine/domain/models.dart';
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

  test('expande por semana e dia correto (3 = quarta)', () {
    final blocks = expandRules([calc], monday, 0, 1);
    expect(blocks.length, 4); // 2 dias x 2 semanas
    final wed = blocks.firstWhere((b) => b.start.day == 28);
    expect(wed.start, DateTime(2026, 10, 28, 8));
    expect(wed.end, DateTime(2026, 10, 28, 10));
    expect(wed.layer, Layer.fixed);
    expect(blocks.map((b) => b.id).toSet().length, 4); // ids únicos
  });

  test('semanas anteriores e fim às 24:00', () {
    const night = FixedRule(
        id: 'r2', title: 'Noite', weekdays: [5], startMin: 19 * 60, endMin: 24 * 60);
    final blocks = expandRules([night], monday, 1, 0);
    expect(blocks.first.start, DateTime(2026, 10, 23, 19)); // sexta da semana anterior
    expect(blocks.first.end, DateTime(2026, 10, 24, 0));
  });

  test('validação', () {
    expect(validateRule(title: ' ', weekdays: [1], startMin: 480, endMin: 600), isNotNull);
    expect(validateRule(title: 'A', weekdays: [], startMin: 480, endMin: 600), isNotNull);
    expect(validateRule(title: 'A', weekdays: [1], startMin: 600, endMin: 600), isNotNull);
    expect(validateRule(title: 'A', weekdays: [1], startMin: 480, endMin: 600), isNull);
  });

  test('formatação', () {
    expect(fmtMinutes(8 * 60 + 5), '08:05');
    expect(fmtMinutes(24 * 60), '24:00');
    expect(calc.daysLabel, 'Seg · Qua');
  });

  test('JSON ida e volta e arquivo', () async {
    final r = FixedRule.fromJson(calc.toJson());
    expect(r.title, 'Cálculo II');
    expect(r.weekdays, [1, 3]);

    final dir = await Directory.systemTemp.createTemp('ar_rules');
    final repo = FileRuleRepository(File('${dir.path}/routine.json'));
    expect(await repo.load(), isNull);
    await repo.save([calc]);
    final loaded = await repo.load();
    expect(loaded!.single.endMin, 600);
    await dir.delete(recursive: true);
  });
}
