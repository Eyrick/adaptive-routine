import 'package:adaptive_routine/domain/week.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('início da semana: domingo ou segunda', () {
    final qua = DateTime(2026, 10, 28);
    expect(startOfWeek(qua, firstDay: DateTime.sunday), DateTime(2026, 10, 25));
    expect(startOfWeek(qua, firstDay: DateTime.monday), DateTime(2026, 10, 26));

    final dom = DateTime(2026, 11, 1);
    expect(startOfWeek(dom, firstDay: DateTime.sunday), DateTime(2026, 11, 1));
    expect(startOfWeek(dom, firstDay: DateTime.monday), DateTime(2026, 10, 26));

    final sab = DateTime(2026, 10, 31);
    expect(startOfWeek(sab, firstDay: DateTime.sunday), DateTime(2026, 10, 25));
  });

  test('ordem dos dias na tela', () {
    expect(weekdayOrder(firstDay: DateTime.sunday), [7, 1, 2, 3, 4, 5, 6]);
    expect(weekdayOrder(firstDay: DateTime.monday), [1, 2, 3, 4, 5, 6, 7]);
  });

  test('a semana exibida sempre tem o primeiro dia configurado', () {
    expect(startOfWeek(DateTime(2026, 11, 20)).weekday, kWeekStart);
  });
}
