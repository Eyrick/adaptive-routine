import 'package:adaptive_routine/data/prefs_repositories.dart';
import 'package:adaptive_routine/domain/fixed_rule.dart';
import 'package:adaptive_routine/domain/holiday.dart';
import 'package:adaptive_routine/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('agenda: salva e recarrega no armazenamento do navegador', () async {
    final prefs = await SharedPreferences.getInstance();
    final repo = PrefsBlockRepository(prefs);
    expect(await repo.load(), isNull);

    final b = TimeBlock(
      id: 'dy-1',
      title: 'Estudo',
      layer: Layer.dynamic,
      start: DateTime(2026, 11, 2, 19),
      end: DateTime(2026, 11, 2, 20, 30),
      status: BlockStatus.done,
    );
    await repo.save([b]);
    final loaded = await PrefsBlockRepository(prefs).load();
    expect(loaded!.single.title, 'Estudo');
    expect(loaded.single.status, BlockStatus.done);
    expect(loaded.single.start, b.start);
  });

  test('rotina e feriados: ida e volta', () async {
    final prefs = await SharedPreferences.getInstance();

    final rules = PrefsRuleRepository(prefs);
    await rules.save(const [
      FixedRule(id: 'r1', title: 'Cálculo', weekdays: [1, 3], startMin: 480, endMin: 600),
    ]);
    expect((await rules.load())!.single.title, 'Cálculo');

    final holidays = PrefsHolidayRepository(prefs);
    await holidays.save({
      '2026-11-15': const Holiday(name: 'República', kind: DayKind.holiday, hidesFixed: true),
    });
    expect((await holidays.load())!['2026-11-15']!.name, 'República');
  });

  test('dado ilegível vira cópia e não derruba o app', () async {
    SharedPreferences.setMockInitialValues({'schedule.json': 'isso não é json'});
    final prefs = await SharedPreferences.getInstance();
    expect(await PrefsBlockRepository(prefs).load(), isNull);
    expect(prefs.getString('schedule.json.corrupt'), 'isso não é json');
    expect(prefs.getString('schedule.json'), isNull);
  });
}
