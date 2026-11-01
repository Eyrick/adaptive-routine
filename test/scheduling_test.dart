import 'package:adaptive_routine/domain/models.dart';
import 'package:adaptive_routine/domain/scheduling.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final mon = DateTime(2026, 10, 26);
  TimeBlock b(String id, int h, int dur, [Layer l = Layer.dynamic]) => TimeBlock(
      id: id, title: id, layer: l,
      start: DateTime(2026, 10, 26, h), end: DateTime(2026, 10, 26, h + dur));

  test('detecta choque', () {
    expect(findConflicts([b('a', 17, 2)], b('n', 18, 1)).length, 1);
    expect(findConflicts([b('a', 17, 1)], b('n', 18, 1)), isEmpty);
  });

  test('sugere janelas que comportam a duração', () {
    final s = suggestSlots([b('a', 8, 2, Layer.fixed)],
        duration: const Duration(hours: 1), weekStart: mon, preferred: DateTime(2026, 10, 26, 9));
    expect(s.length, 3);
    expect(s.first.start.hour, 10);
  });
}
