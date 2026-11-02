import 'package:flutter/foundation.dart' show immutable;

import 'models.dart';

const weekdayShort = ['Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb', 'Dom'];

/// Minutos desde 00:00 -> "08:30" (1440 vira "24:00").
String fmtMinutes(int m) =>
    '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';

/// Compromisso fixo que se repete toda semana (aula, trabalho...).
/// [weekdays] segue DateTime.weekday: 1 = segunda ... 7 = domingo.
@immutable
class FixedRule {
  const FixedRule({
    required this.id,
    required this.title,
    required this.weekdays,
    required this.startMin,
    required this.endMin,
  });

  final String id;
  final String title;
  final List<int> weekdays;
  final int startMin; // minutos desde 00:00
  final int endMin; // pode ser 1440 (meia-noite)

  String get daysLabel => weekdays.map((d) => weekdayShort[d - 1]).join(' · ');

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'weekdays': weekdays,
        'startMin': startMin,
        'endMin': endMin,
      };

  factory FixedRule.fromJson(Map<String, dynamic> j) => FixedRule(
        id: j['id'] as String,
        title: j['title'] as String,
        weekdays: [for (final d in j['weekdays'] as List) d as int],
        startMin: j['startMin'] as int,
        endMin: j['endMin'] as int,
      );
}

/// null = válido; senão, a mensagem para mostrar ao usuário.
String? validateRule({
  required String title,
  required Iterable<int> weekdays,
  required int startMin,
  required int endMin,
}) {
  if (title.trim().isEmpty) return 'Dê um nome ao compromisso.';
  if (weekdays.isEmpty) return 'Escolha pelo menos um dia da semana.';
  if (endMin <= startMin) return 'O horário de fim precisa ser depois do início.';
  return null;
}

/// Gera os blocos fixos de [back] semanas atrás até [ahead] semanas à frente
/// de [baseMonday] (a segunda-feira da semana atual).
List<TimeBlock> expandRules(
  List<FixedRule> rules,
  DateTime baseMonday,
  int back,
  int ahead,
) =>
    [
      for (var w = -back; w <= ahead; w++)
        for (final r in rules)
          for (final wd in r.weekdays)
            TimeBlock(
              id: 'fx-${r.id}-$w-$wd',
              title: r.title,
              layer: Layer.fixed,
              start: DateTime(baseMonday.year, baseMonday.month,
                  baseMonday.day + w * 7 + (wd - 1), 0, r.startMin),
              end: DateTime(baseMonday.year, baseMonday.month,
                  baseMonday.day + w * 7 + (wd - 1), 0, r.endMin),
            ),
    ];
