import '../domain/fixed_rule.dart';
import '../domain/holiday.dart';
import '../domain/models.dart';
import '../domain/scheduling.dart';

/// Um aviso a ser entregue em [fireAt]. A [key] identifica a ocorrência: se o
/// compromisso muda de horário, a chave muda e o aviso antigo é substituído.
class Reminder {
  const Reminder({
    required this.key,
    required this.fireAt,
    required this.title,
    required this.body,
  });

  final String key;
  final DateTime fireAt;
  final String title;
  final String body;

  Map<String, dynamic> toJson() => {
        'key': key,
        'fire_at': fireAt.toUtc().toIso8601String(),
        'title': title,
        'body': body,
      };
}

/// Calcula os lembretes dos próximos [horizonDays] dias:
///
/// * um aviso [leadMinutes] minutos antes de cada compromisso pendente
///   (da base fixa ou dinâmico). Se esse horário já passou, não há aviso;
/// * um resumo às [summaryHour]h sobre o dia seguinte (e, se ele for feriado
///   ou evento, o nome aparece no título).
///
/// Função pura: não depende de relógio, rede ou tela.
List<Reminder> buildReminders({
  required List<TimeBlock> blocks,
  required Map<String, Holiday> holidays,
  required DateTime now,
  int leadMinutes = 30,
  int horizonDays = 14,
  int summaryHour = 21,
  int maxItems = 400,
}) {
  final out = <Reminder>[];
  final horizon = now.add(Duration(days: horizonDays));

  for (final b in blocks) {
    if (b.status != BlockStatus.planned) continue;
    if (!b.start.isAfter(now) || b.start.isAfter(horizon)) continue;
    final fireAt = b.start.subtract(Duration(minutes: leadMinutes));
    if (!fireAt.isAfter(now)) continue;
    out.add(Reminder(
      key: 'b:${b.id}:${b.start.millisecondsSinceEpoch}:$leadMinutes',
      fireAt: fireAt,
      title: b.title,
      body: 'Começa às ${hhmm(b.start)} (em $leadMinutes min)',
    ));
  }

  final today = DateTime(now.year, now.month, now.day);
  for (var i = 0; i < horizonDays; i++) {
    final day = DateTime(today.year, today.month, today.day + i);
    final summaryAt = DateTime(day.year, day.month, day.day, summaryHour);
    if (!summaryAt.isAfter(now)) continue;

    final tomorrow = DateTime(day.year, day.month, day.day + 1);
    final events = blocks.where((b) => sameDay(b.start, tomorrow)).toList()
      ..sort((a, b) => a.start.compareTo(b.start));
    final holiday = holidays[dateKey(tomorrow)];
    if (events.isEmpty && holiday == null) continue;

    final kind = holiday?.kind == DayKind.event ? 'evento' : 'feriado';
    final title = holiday == null
        ? 'Sua rotina de amanhã'
        : 'Amanhã: ${holiday.name.isEmpty ? kind : holiday.name}';
    final body = events.isEmpty
        ? 'Nenhum compromisso marcado.'
        : '${events.length} ${events.length == 1 ? 'compromisso' : 'compromissos'}. '
            'Primeiro: ${events.first.title} às ${hhmm(events.first.start)}.';
    out.add(Reminder(key: 's:${dateKey(tomorrow)}', fireAt: summaryAt, title: title, body: body));
  }

  out.sort((a, b) => a.fireAt.compareTo(b.fireAt));
  return out.take(maxItems).toList();
}
