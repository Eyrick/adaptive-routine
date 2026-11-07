import 'package:flutter/foundation.dart' show immutable;

/// Tipo do dia especial: feriado ou evento (cores diferentes no calendário).
enum DayKind { holiday, event }

/// Dia especial (feriado ou evento). Para cada compromisso fixo do dia dá para
/// escolher se ele acontece ou não.
///
/// [hidesFixed] é a regra geral do dia: o que acontece com os compromissos que
/// **não** estão em [exceptions]. Os de [exceptions] fazem o contrário. Assim um
/// compromisso cadastrado depois segue a regra geral, e arquivos antigos (só
/// com `hidesFixed`) continuam valendo.
///
/// A escolha fica aqui, e não em "aula cancelada", para que desmarcar o dia
/// devolva as aulas.
@immutable
class Holiday {
  const Holiday({
    this.name = '',
    this.hidesFixed = true,
    this.exceptions = const [],
    this.kind = DayKind.holiday,
  });
  final String name;
  final DayKind kind;
  final bool hidesFixed;
  final List<String> exceptions; // ids das regras que fazem o contrário da regra geral

  /// true = o compromisso fixo [ruleId] NÃO acontece neste dia.
  bool hides(String ruleId) => exceptions.contains(ruleId) ? !hidesFixed : hidesFixed;

  Map<String, dynamic> toJson() => {
        'name': name,
        'hidesFixed': hidesFixed,
        'exceptions': exceptions,
        'kind': kind.name,
      };

  factory Holiday.fromJson(Map<String, dynamic> j) => Holiday(
        name: (j['name'] as String?) ?? '',
        hidesFixed: (j['hidesFixed'] as bool?) ?? true,
        exceptions: [for (final id in (j['exceptions'] as List? ?? const [])) id as String],
        kind: DayKind.values.byName((j['kind'] as String?) ?? 'holiday'),
      );
}
