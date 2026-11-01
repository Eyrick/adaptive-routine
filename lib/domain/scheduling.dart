import 'models.dart';

/// Motor determinístico: nada aqui depende de LLM ou de Flutter UI.

List<TimeBlock> findConflicts(List<TimeBlock> all, TimeBlock candidate) =>
    all.where((b) => b.id != candidate.id && b.overlaps(candidate)).toList();

/// Retorna até [max] janelas livres que comportam [duration], ordenadas pela
/// proximidade de [preferred]. Procura [horizonDays] dias a partir de [weekStart]
/// (pode cruzar para a próxima semana). Se o horário exato de [preferred] estiver
/// livre, ele é oferecido. Blocos em [ignoreIds] são tratados como livres.
List<SlotSuggestion> suggestSlots(
  List<TimeBlock> all, {
  required Duration duration,
  required DateTime weekStart,
  required DateTime preferred,
  Set<String> ignoreIds = const {},
  DateTime? notBefore,
  int max = 3,
  int dayStartHour = 8,
  int dayEndHour = 22,
  int horizonDays = 14,
}) {
  final busy = all.where((b) => !ignoreIds.contains(b.id)).toList()
    ..sort((a, b) => a.start.compareTo(b.start));
  final found = <SlotSuggestion>[];

  void addGap(DateTime gs, DateTime ge) {
    if (ge.difference(gs) < duration) return;
    found.add(SlotSuggestion(gs, gs.add(duration)));
    if (preferred.isAfter(gs) && !preferred.add(duration).isAfter(ge)) {
      found.add(SlotSuggestion(preferred, preferred.add(duration)));
    }
  }

  for (var d = 0; d < horizonDays; d++) {
    final dayStart =
        DateTime(weekStart.year, weekStart.month, weekStart.day + d, dayStartHour);
    final dayEnd =
        DateTime(weekStart.year, weekStart.month, weekStart.day + d, dayEndHour);
    var cursor = dayStart;
    if (notBefore != null && notBefore.isAfter(cursor)) cursor = _ceil15(notBefore);
    if (!cursor.isBefore(dayEnd)) continue;

    for (final b in busy) {
      if (!b.end.isAfter(dayStart) || !b.start.isBefore(dayEnd)) continue;
      if (b.start.isAfter(cursor)) addGap(cursor, b.start);
      if (b.end.isAfter(cursor)) cursor = b.end;
    }
    addGap(cursor, dayEnd);
  }

  final seen = <DateTime>{};
  final unique = found.where((f) => seen.add(f.start)).toList()
    ..sort((a, b) => a.start
        .difference(preferred)
        .abs()
        .compareTo(b.start.difference(preferred).abs()));
  return unique.take(max).toList();
}

DateTime _ceil15(DateTime t) {
  final total = t.hour * 60 + t.minute + (t.second > 0 ? 1 : 0);
  return DateTime(t.year, t.month, t.day, 0, ((total + 14) ~/ 15) * 15);
}

const _days = ['Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb', 'Dom'];
String dayLabel(DateTime d) => _days[d.weekday - 1];
String dayDate(DateTime d) => '${_days[d.weekday - 1]} ${d.day}/${d.month}';
String hhmm(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
bool sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;
