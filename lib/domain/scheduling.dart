import 'models.dart';

/// Motor determinístico: nada aqui depende de LLM ou de Flutter UI.

List<TimeBlock> findConflicts(List<TimeBlock> all, TimeBlock candidate) =>
    all.where((b) => b.id != candidate.id && b.overlaps(candidate)).toList();

/// Retorna até [max] janelas livres que comportam [duration], ordenadas pela
/// proximidade de [preferred]. Blocos em [ignoreIds] são tratados como livres.
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
}) {
  final busy = all.where((b) => !ignoreIds.contains(b.id)).toList()
    ..sort((a, b) => a.start.compareTo(b.start));
  final found = <SlotSuggestion>[];

  for (var d = 0; d < 7; d++) {
    final dayStart =
        DateTime(weekStart.year, weekStart.month, weekStart.day + d, dayStartHour);
    final dayEnd =
        DateTime(weekStart.year, weekStart.month, weekStart.day + d, dayEndHour);
    var cursor = dayStart;
    if (notBefore != null && notBefore.isAfter(cursor)) cursor = notBefore;

    for (final b in busy) {
      if (!b.end.isAfter(dayStart) || !b.start.isBefore(dayEnd)) continue;
      if (b.start.difference(cursor) >= duration) {
        found.add(SlotSuggestion(cursor, cursor.add(duration)));
      }
      if (b.end.isAfter(cursor)) cursor = b.end;
    }
    if (dayEnd.difference(cursor) >= duration) {
      found.add(SlotSuggestion(cursor, cursor.add(duration)));
    }
  }

  found.sort((a, b) => a.start
      .difference(preferred)
      .abs()
      .compareTo(b.start.difference(preferred).abs()));
  return found.take(max).toList();
}

const _days = ['Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb', 'Dom'];
String dayLabel(DateTime d) => _days[d.weekday - 1];
String hhmm(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
bool sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;
