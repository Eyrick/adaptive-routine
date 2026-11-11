import 'dart:convert';

import '../domain/fixed_rule.dart';
import '../domain/holiday.dart';
import '../domain/models.dart';

/// Tudo o que é sincronizado: atividades dinâmicas, rotina fixa e feriados.
/// Os blocos da rotina fixa não entram: são gerados a partir das regras.
class Snapshot {
  const Snapshot({required this.blocks, required this.rules, required this.holidays});

  final List<TimeBlock> blocks; // só a camada dinâmica
  final List<FixedRule> rules;
  final Map<String, Holiday> holidays;

  /// Agenda "de fábrica": sem rotina, sem feriados e só com o exemplo inicial.
  /// Um aparelho assim pode adotar a agenda da nuvem sem perguntar nada.
  bool get isPristine =>
      rules.isEmpty && holidays.isEmpty && blocks.every((b) => b.id == 'dy-fis');

  Map<String, dynamic> toJson() => {
        'version': 1,
        'blocks': [for (final b in blocks) b.toJson()],
        'rules': [for (final r in rules) r.toJson()],
        'holidays': {for (final e in holidays.entries) e.key: e.value.toJson()},
      };

  factory Snapshot.fromJson(Map<String, dynamic> j) => Snapshot(
        blocks: [
          for (final x in (j['blocks'] as List? ?? const []))
            TimeBlock.fromJson((x as Map).cast<String, dynamic>()),
        ],
        rules: [
          for (final x in (j['rules'] as List? ?? const []))
            FixedRule.fromJson((x as Map).cast<String, dynamic>()),
        ],
        holidays: {
          for (final e in ((j['holidays'] as Map?) ?? const {}).entries)
            e.key as String: Holiday.fromJson((e.value as Map).cast<String, dynamic>()),
        },
      );

  /// Texto canônico: chaves em ordem e listas ordenadas por id. Dois aparelhos
  /// com os mesmos dados geram exatamente o mesmo texto, e é com ele que se
  /// descobre se algo mudou.
  String canonical() {
    final sortedBlocks = [...blocks]..sort((a, b) => a.id.compareTo(b.id));
    final sortedRules = [...rules]..sort((a, b) => a.id.compareTo(b.id));
    return canonicalJson({
      'version': 1,
      'blocks': [for (final b in sortedBlocks) b.toJson()],
      'rules': [for (final r in sortedRules) r.toJson()],
      'holidays': {for (final e in holidays.entries) e.key: e.value.toJson()},
    });
  }
}

String canonicalJson(Object? value) => jsonEncode(_sorted(value));

Object? _sorted(Object? v) {
  if (v is Map) {
    final keys = v.keys.map((k) => k.toString()).toList()..sort();
    return {for (final k in keys) k: _sorted(v[k])};
  }
  if (v is List) return [for (final x in v) _sorted(x)];
  return v;
}
