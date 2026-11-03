import '../../domain/models.dart';

/// Substituto local do IntentService (LLM). Na M2 troca-se por tool calling.
/// Entende: "reunião hoje às 17h", "estudar das 8h às 9:30", "dentista quinta
/// 14h por 2:30h", "adicione Estudar PAA amanhã 10h com duração de 45min".
TimeBlock? parseIntent(String text, DateTime now) {
  var work = text;
  var lower = work.toLowerCase();

  // 1) duração explícita: "por 2 horas", "por 2:30h", "com duração de 45min"
  Duration? explicit;
  final dm = RegExp(
          r'(?:por|durante|(?:com\s+)?dura[çc][ãa]o(?:\s+de)?)\s+(?:(\d+)\s*[:h]\s*(\d{2})(?:\s*(?:h|min))?|(\d+(?:[.,]\d+)?)\s*(horas?|h|minutos?|min))')
      .firstMatch(lower);
  if (dm != null) {
    if (dm.group(1) != null) {
      explicit = Duration(hours: int.parse(dm.group(1)!), minutes: int.parse(dm.group(2)!));
    } else {
      final n = double.parse(dm.group(3)!.replaceAll(',', '.'));
      explicit = Duration(minutes: dm.group(4)!.startsWith('h') ? (n * 60).round() : n.round());
    }
    work = work.replaceRange(dm.start, dm.end, ' ');
    lower = work.toLowerCase();
  }

  // 2) intervalo: "8h as 9:30", "das 8 às 10", "14h-15h30"
  int sh, sm, eh = -1, em = 0;
  final rm = RegExp(
          r'(?:das|de)?\s*(\d{1,2})(?:\s*(?:h|:)\s*(\d{2})?)?\s*(?:às|as|até|ate|–|-|a)\s*(\d{1,2})(?:\s*(?:h|:)\s*(\d{2})?)?')
      .firstMatch(lower);
  if (rm != null) {
    sh = int.parse(rm.group(1)!);
    sm = int.tryParse(rm.group(2) ?? '') ?? 0;
    eh = int.parse(rm.group(3)!);
    em = int.tryParse(rm.group(4) ?? '') ?? 0;
    work = work.replaceRange(rm.start, rm.end, ' ');
  } else {
    // 3) horário único: "17h", "9:30"
    final m = RegExp(r'(\d{1,2})\s*(?:h|:)\s*(\d{2})?(?:\s*h\b)?').firstMatch(lower);
    if (m == null) return null;
    sh = int.parse(m.group(1)!);
    sm = int.tryParse(m.group(2) ?? '') ?? 0;
    work = work.replaceRange(m.start, m.end, ' ');
  }
  if (sh > 23 || sm > 59 || eh > 23 || em > 59) return null;

  // 4) dia (hoje / amanhã / dia da semana) e título
  var offset = 0;
  final kept = <String>[];
  for (final raw in work.split(RegExp(r'\s+'))) {
    if (raw.isEmpty) continue;
    final w = raw.toLowerCase().replaceAll(RegExp(r'[.,;!?]'), '');
    if (w == 'hoje') continue;
    if (w == 'amanhã' || w == 'amanha') {
      offset = 1;
      continue;
    }
    final wd = _createWeekdays[w];
    if (wd != null) {
      offset = (wd - now.weekday) % 7;
      continue;
    }
    kept.add(raw);
  }

  final start = DateTime(now.year, now.month, now.day + offset, sh, sm);
  DateTime end;
  if (eh >= 0) {
    end = DateTime(now.year, now.month, now.day + offset, eh, em);
    if (!end.isAfter(start)) return null;
  } else {
    end = start.add(explicit ?? const Duration(hours: 1));
  }

  // Só corta conectores/verbos nas pontas; "Estudo de Física" mantém o "de".
  bool isFiller(String t) =>
      _fillers.contains(t.toLowerCase().replaceAll(RegExp(r'[.,;!?]'), ''));
  while (kept.isNotEmpty && isFiller(kept.first)) {
    kept.removeAt(0);
  }
  while (kept.isNotEmpty && isFiller(kept.last)) {
    kept.removeLast();
  }
  final title = kept.join(' ');
  final t = title.isEmpty ? 'Evento' : title[0].toUpperCase() + title.substring(1);

  return TimeBlock(
    id: newBlockId(),
    title: t,
    layer: Layer.dynamic,
    start: start,
    end: end,
  );
}

const _createWeekdays = {
  'segunda': 1, 'seg': 1, 'terça': 2, 'terca': 2, 'quarta': 3, 'qua': 3,
  'quinta': 4, 'qui': 4, 'sexta': 5, 'sex': 5, 'sábado': 6, 'sabado': 6,
  'sab': 6, 'domingo': 7, 'dom': 7,
};

const _fillers = {
  'tenho', 'uma', 'um', 'uns', 'umas', 'para', 'pra', 'de', 'da', 'do', 'das',
  'dos', 'as', 'às', 'a', 'o', 'e', 'na', 'no', 'em', 'até', 'ate', 'última',
  'ultima', 'hora', 'marque', 'marcar', 'agende', 'agendar', 'adicione',
  'adicionar', 'adiciona', 'coloque', 'coloca', 'inclua', 'crie', 'criar',
  'anote', 'anotar', 'me', 'preciso', 'eu', 'por', 'favor', 'com', 'duração',
  'duracao', 'durante',
};

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
  final m = RegExp(r'(\d{1,2})\s*(?:h|:)\s*(\d{2})?(?:\s*h\b)?').firstMatch(t);
  if (day == null && m == null) return null;
  day ??= today;
  final h = m == null ? 8 : int.parse(m.group(1)!).clamp(0, 23);
  final min = m == null ? 0 : (int.tryParse(m.group(2) ?? '0') ?? 0).clamp(0, 59);
  return DateTime(day.year, day.month, day.day, h, min);
}


// ---------------------------------------------------------------- remoção

/// Minúsculas, sem acento e sem pontuação: "Lóg. Prog." -> "log prog".
String normalizeText(String s) {
  const from = 'áàâãäéèêëíìîïóòôõöúùûüçñ';
  const to = 'aaaaaeeeeiiiiooooouuuucn';
  final b = StringBuffer();
  for (final ch in s.toLowerCase().runes.map(String.fromCharCode)) {
    final i = from.indexOf(ch);
    b.write(i >= 0 ? to[i] : ch);
  }
  return b.toString().replaceAll(RegExp(r'[.,;!?]'), '');
}

class RemoveIntent {
  const RemoveIntent({this.day, this.minutes, this.words = const []});
  final DateTime? day; // dia alvo (null = qualquer)
  final int? minutes; // minutos desde 00:00; bloco deve cobrir esse instante
  final List<String> words; // palavras (normalizadas) que o título deve conter
  bool get isEmpty => day == null && minutes == null && words.isEmpty;
}

const _removeVerbs = {
  'remover', 'remova', 'remove', 'cancelar', 'cancela', 'cancele', 'apagar',
  'apague', 'apaga', 'excluir', 'exclua', 'tirar', 'tire', 'desmarcar', 'desmarque',
};

const _restoreVerbs = {'restaurar', 'restaure', 'restaura', 'reativar', 'reative', 'reativa'};

const _weekdays = {
  'seg': 1, 'segunda': 1, 'ter': 2, 'terca': 2, 'qua': 3, 'quarta': 3,
  'qui': 4, 'quinta': 4, 'sex': 5, 'sexta': 5, 'sab': 6, 'sabado': 6,
  'dom': 7, 'domingo': 7,
};

bool isRemoveCommand(String text) {
  final w = text.trim().toLowerCase().split(RegExp(r'\s+'));
  return w.length > 1 && _removeVerbs.contains(w.first);
}

/// "aula de Lóg. Prog. de quinta foi cancelada", "sem aula amanhã".
bool isCancelStatement(String text) {
  final t = normalizeText(text);
  return t.contains('cancelad') ||
      t.contains('cancelou') ||
      t.contains('sem aula') ||
      t.contains('nao vai ter aula') ||
      t.contains('nao havera aula');
}

/// "restaurar Lóg. Prog. quinta" / "desfazer cancelamento quinta".
bool isRestoreCommand(String text) {
  final t = normalizeText(text).trim();
  final w = t.split(RegExp(r'\s+'));
  return (w.length > 1 && _restoreVerbs.contains(w.first)) ||
      t.startsWith('desfazer cancelamento');
}

/// "remover programação de Dom 8h" -> dia = domingo da semana exibida, 08:00.
/// Dia da semana que já passou nesta semana vira o da semana seguinte.
RemoveIntent parseRemove(String text, DateTime now, DateTime weekStart) {
  var work = text;
  int? minutes;
  final m = RegExp(r'(\d{1,2})\s*(?:h|:)\s*(\d{2})?(?:\s*h\b)?').firstMatch(work.toLowerCase());
  if (m != null) {
    minutes = int.parse(m.group(1)!) * 60 + (int.tryParse(m.group(2) ?? '') ?? 0);
    work = work.replaceRange(m.start, m.end, ' ');
  }

  const stop = {
    'de', 'da', 'do', 'das', 'dos', 'dia', 'as', 'a', 'o', 'e', 'na', 'no',
    'programacao', 'agenda', 'atividade', 'compromisso', 'evento', 'tarefa',
    'por', 'favor', 'pra', 'para', 'meu', 'minha', 'aula', 'aulas', 'foi',
    'cancelada', 'cancelado', 'cancelou', 'cancelamento', 'feira', 'sem',
    'restaurar', 'restaure', 'restaura', 'reativar', 'reative', 'reativa',
    'desfazer', 'desfaz', 'desfaca', 'horario', 'data', 'quero', 'preciso',
    'pode', 'me', 'os', 'um', 'uma',
  };
  final today = DateTime(now.year, now.month, now.day);
  DateTime? day;
  final words = <String>[];
  for (final raw in work.split(RegExp(r'\s+'))) {
    final w = normalizeText(raw).replaceAll('-feira', '');
    if (w.isEmpty || _removeVerbs.contains(w) || _allMoveVerbs.contains(w) || stop.contains(w)) continue;
    if (w == 'hoje') {
      day = today;
    } else if (w == 'amanha') {
      day = today.add(const Duration(days: 1));
    } else if (_weekdays.containsKey(w)) {
      final base = DateTime(weekStart.year, weekStart.month, weekStart.day + _weekdays[w]! - 1);
      day = base.isBefore(today) ? DateTime(base.year, base.month, base.day + 7) : base;
    } else {
      words.add(w);
    }
  }
  return RemoveIntent(day: day, minutes: minutes, words: words);
}


// ---------------------------------------------------------------- remarcar

/// Verbos que sempre significam "mudar o horário de algo que já existe".
const _strongMove = {
  'mover', 'mova', 'move', 'remarcar', 'remarque', 'remarca', 'reagendar',
  'reagende', 'reagenda', 'transferir', 'transfira', 'transfere', 'adiar',
  'adie', 'adia', 'atrasar', 'atrase', 'atrasa', 'adiantar', 'adiante', 'adianta',
};

/// Verbos comuns demais ("passar na farmácia"): só valem com "para/pra".
const _weakMove = {
  'passar', 'passe', 'passa', 'mudar', 'mude', 'muda', 'trocar', 'troque', 'troca',
};

const _allMoveVerbs = {..._strongMove, ..._weakMove};
const _forwardVerbs = {'adiar', 'adie', 'adia', 'atrasar', 'atrase', 'atrasa'};
const _backwardVerbs = {'adiantar', 'adiante', 'adianta'};

bool isMoveCommand(String text) {
  final t = normalizeText(text).trim();
  final w = t.split(RegExp(r'\s+'));
  if (w.length < 2) return false;
  final head = w.take(3);
  if (head.any(_strongMove.contains)) return true;
  return head.any(_weakMove.contains) && RegExp(r'\b(?:para|pra|pras)\b').hasMatch(t);
}

bool isUndoCommand(String text) {
  final t = normalizeText(text).trim();
  return const {
    'desfazer', 'desfaz', 'desfaca', 'desfazer isso', 'desfazer ultima',
    'desfazer ultima acao', 'desfazer a ultima acao',
  }.contains(t);
}

class MoveIntent {
  const MoveIntent({required this.source, this.targetDay, this.targetMinutes, this.shift});
  final RemoveIntent source; // qual evento remarcar
  final DateTime? targetDay; // novo dia (null = mesmo dia)
  final int? targetMinutes; // novo horário (null = mesmo horário)
  final Duration? shift; // "adiar 30 min" (negativo = adiantar)
  bool get hasTarget => targetDay != null || targetMinutes != null || shift != null;
}

({DateTime? day, int? minutes}) _parseTarget(String s, DateTime today, DateTime weekStart) {
  int? minutes;
  DateTime? day;
  var rest = s;
  final m = RegExp(r'(\d{1,2})\s*(?:h|:)\s*(\d{2})?(?:\s*h\b)?').firstMatch(s);
  if (m != null) {
    final h = int.parse(m.group(1)!), mi = int.tryParse(m.group(2) ?? '') ?? 0;
    if (h <= 23 && mi <= 59) minutes = h * 60 + mi;
    rest = s.replaceRange(m.start, m.end, ' ');
  } else {
    // "para 15" -> 15h
    final b = RegExp(r'(?:^|\s)(?:as\s+)?(\d{1,2})\s*$').firstMatch(s);
    if (b != null) {
      final h = int.parse(b.group(1)!);
      if (h <= 23) minutes = h * 60;
      rest = s.substring(0, b.start);
    }
  }
  for (final raw in rest.split(RegExp(r'\s+'))) {
    final w = raw.replaceAll('-feira', '');
    if (w == 'hoje') {
      day = today;
    } else if (w == 'amanha') {
      day = today.add(const Duration(days: 1));
    } else if (_weekdays.containsKey(w)) {
      final base = DateTime(weekStart.year, weekStart.month, weekStart.day + _weekdays[w]! - 1);
      day = base.isBefore(today) ? DateTime(base.year, base.month, base.day + 7) : base;
    }
  }
  return (day: day, minutes: minutes);
}

/// "remarque academia de sexta para 15h", "passa o Estudar ML para amanhã 10h",
/// "mover reunião de hoje 17h para amanhã 19h", "adiar reunião 30 min".
MoveIntent parseMove(String text, DateTime now, DateTime weekStart) {
  var t = normalizeText(text);
  final today = DateTime(now.year, now.month, now.day);
  final head = t.trim().split(RegExp(r'\s+')).take(3).toList();
  final sign = head.any(_forwardVerbs.contains) ? 1 : (head.any(_backwardVerbs.contains) ? -1 : 0);

  Duration? shift;
  if (sign != 0) {
    final sm = RegExp(
            r'(?:por\s+|em\s+)?(?:(\d+(?:[.,]\d+)?)|(meia|uma))\s*(horas?|hrs?|minutos?|min)\b')
        .firstMatch(t);
    if (sm != null) {
      final amount = sm.group(1) != null
          ? double.parse(sm.group(1)!.replaceAll(',', '.'))
          : (sm.group(2) == 'meia' ? 0.5 : 1.0);
      final mins = sm.group(3)!.startsWith('h') ? amount * 60 : amount;
      shift = Duration(minutes: (mins * sign).round());
      t = t.replaceRange(sm.start, sm.end, ' ');
    }
  }

  var sourceText = t;
  DateTime? tDay;
  int? tMin;
  if (shift == null) {
    final seps = RegExp(r'\b(?:para|pra|pras)\b').allMatches(t).toList();
    for (final m in seps.reversed) {
      final parsed = _parseTarget(t.substring(m.end), today, weekStart);
      if (parsed.day != null || parsed.minutes != null) {
        sourceText = t.substring(0, m.start);
        tDay = parsed.day;
        tMin = parsed.minutes;
        break;
      }
    }
  }
  return MoveIntent(
    source: parseRemove(sourceText, now, weekStart),
    targetDay: tDay,
    targetMinutes: tMin,
    shift: shift,
  );
}
