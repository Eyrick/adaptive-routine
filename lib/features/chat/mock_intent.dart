import '../../domain/models.dart';

/// Substituto local do IntentService (LLM). Na M2 troca-se por tool calling.
/// Entende: "reunião de última hora hoje às 17h", "dentista amanhã 9:30".
TimeBlock? parseIntent(String text, DateTime now) {
  final m = RegExp(r'(\d{1,2})\s*(?:h|:)\s*(\d{2})?').firstMatch(text.toLowerCase());
  if (m == null) return null;
  final h = int.parse(m.group(1)!);
  final min = int.tryParse(m.group(2) ?? '0') ?? 0;
  if (h > 23 || min > 59) return null;

  final lower = text.toLowerCase();
  final offset = (lower.contains('amanhã') || lower.contains('amanha')) ? 1 : 0;
  final start = DateTime(now.year, now.month, now.day + offset, h, min);

  const stop = {
    'tenho', 'uma', 'um', 'hoje', 'amanhã', 'amanha', 'às', 'as', 'a', 'para',
    'de', 'última', 'ultima', 'hora', 'marque', 'agende', 'me', 'preciso', 'eu',
  };
  final title = text
      .replaceFirst(m.group(0)!, ' ')
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty && !stop.contains(w.toLowerCase()))
      .join(' ');
  final t = title.isEmpty ? 'Evento' : title[0].toUpperCase() + title.substring(1);

  return TimeBlock(
    id: 'dy-${DateTime.now().microsecondsSinceEpoch}',
    title: t,
    layer: Layer.dynamic,
    start: start,
    end: start.add(const Duration(hours: 1)),
  );
}

/// Interpreta preferência de data/hora em respostas como "amanhã 19h" ou "quinta".
DateTime? parsePreference(String text, DateTime now) {
  final t = text.toLowerCase();
  final today = DateTime(now.year, now.month, now.day);
  DateTime? day;
  if (t.contains('hoje')) {
    day = today;
  } else if (t.contains('amanhã') || t.contains('amanha')) {
    day = today.add(const Duration(days: 1));
  } else {
    const names = {
      'segunda': 1, 'terça': 2, 'terca': 2, 'quarta': 3, 'quinta': 4,
      'sexta': 5, 'sábado': 6, 'sabado': 6, 'domingo': 7,
    };
    for (final e in names.entries) {
      if (t.contains(e.key)) {
        final off = (e.value - now.weekday) % 7;
        day = DateTime(now.year, now.month, now.day + off);
        break;
      }
    }
  }
  final m = RegExp(r'(\d{1,2})\s*(?:h|:)\s*(\d{2})?').firstMatch(t);
  if (day == null && m == null) return null;
  day ??= today;
  final h = m == null ? 8 : int.parse(m.group(1)!).clamp(0, 23);
  final min = m == null ? 0 : (int.tryParse(m.group(2) ?? '0') ?? 0).clamp(0, 59);
  return DateTime(day.year, day.month, day.day, h, min);
}
