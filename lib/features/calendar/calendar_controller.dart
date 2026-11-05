import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/block_repository.dart';
import '../../data/rule_repository.dart';
import '../../domain/fixed_rule.dart';
import '../../domain/models.dart';
import '../../domain/scheduling.dart';
import '../chat/command_parser.dart';

class ChatMessage {
  const ChatMessage(this.text, {this.fromUser = false});
  final String text;
  final bool fromUser;
}

enum Stage { priority, preference }

class PendingConflict {
  const PendingConflict({
    required this.incoming,
    required this.conflicts,
    required this.suggestions,
    required this.blockedByFixed,
    required this.stage,
    this.replaces,
  });
  final TimeBlock incoming;
  final List<TimeBlock> conflicts;
  final List<SlotSuggestion> suggestions;
  final bool blockedByFixed; // true: o NOVO evento é que precisa de outra janela
  final Stage stage;
  /// id do bloco que está sendo remarcado (some quando a remarcação é confirmada).
  final String? replaces;

  PendingConflict copyWith({List<SlotSuggestion>? suggestions, bool? blockedByFixed, Stage? stage}) =>
      PendingConflict(
        incoming: incoming,
        conflicts: conflicts,
        suggestions: suggestions ?? this.suggestions,
        blockedByFixed: blockedByFixed ?? this.blockedByFixed,
        stage: stage ?? this.stage,
        replaces: replaces,
      );
}

class CalendarState {
  const CalendarState({
    required this.blocks,
    required this.weekStart,
    required this.focusDay,
    this.pending,
    this.messages = const [],
    this.rules = const [],
  });
  final List<TimeBlock> blocks;
  final DateTime weekStart; // segunda-feira da semana que contém [focusDay]
  final DateTime focusDay; // 1º dia visível no celular (3 dias); no desktop, qualquer dia da semana
  final PendingConflict? pending;
  final List<ChatMessage> messages;
  final List<FixedRule> rules; // rotina fixa cadastrada pelo usuário

  CalendarState copyWith({
    List<TimeBlock>? blocks,
    List<ChatMessage>? messages,
    PendingConflict? pending,
    DateTime? weekStart,
    DateTime? focusDay,
    List<FixedRule>? rules,
    bool clearPending = false,
  }) =>
      CalendarState(
        blocks: blocks ?? this.blocks,
        weekStart: weekStart ?? this.weekStart,
        focusDay: focusDay ?? this.focusDay,
        rules: rules ?? this.rules,
        messages: messages ?? this.messages,
        pending: clearPending ? null : (pending ?? this.pending),
      );
}

final calendarProvider =
    NotifierProvider<CalendarController, CalendarState>(CalendarController.new);

class CalendarController extends Notifier<CalendarState> {
  static const _backWeeks = 4, _aheadWeeks = 26;
  final List<({List<TimeBlock> blocks, List<FixedRule> rules})> _undoStack = [];
  List<TimeBlock>? _skipBlocks; // marca uma restauração do "desfazer"
  List<FixedRule>? _skipRules;
  DateTime _baseMonday = DateTime(2000);

  @override
  CalendarState build() {
    final blockRepo = ref.read(blockRepositoryProvider);
    final ruleRepo = ref.read(ruleRepositoryProvider);
    final saved = ref.read(initialBlocksProvider); // só camada dinâmica
    final rules = ref.read(initialRulesProvider) ?? const <FixedRule>[];
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final monday = DateTime(today.year, today.month, today.day - (today.weekday - 1));
    _baseMonday = monday;

    final dynamicBlocks = saved ?? _seedDynamic(today);
    if (saved == null) Future.microtask(() => blockRepo.save(dynamicBlocks));

    // Persiste sempre que blocos dinâmicos ou rotina fixa mudam.
    ref.listenSelf((prev, next) {
      if (prev == null) return;
      final changed = !identical(prev.blocks, next.blocks) || !identical(prev.rules, next.rules);
      if (changed) {
        if (identical(next.blocks, _skipBlocks) && identical(next.rules, _skipRules)) {
          _skipBlocks = null;
          _skipRules = null;
        } else {
          _undoStack.add((blocks: prev.blocks, rules: prev.rules));
          if (_undoStack.length > 30) _undoStack.removeAt(0);
        }
      }
      if (!identical(prev.blocks, next.blocks)) {
        blockRepo.save(next.blocks.where((b) => b.layer == Layer.dynamic).toList());
      }
      if (!identical(prev.rules, next.rules)) ruleRepo.save(next.rules);
    });

    return CalendarState(
      weekStart: monday,
      focusDay: today,
      rules: rules,
      blocks: [...expandRules(rules, monday, _backWeeks, _aheadWeeks), ...dynamicBlocks],
      messages: [
        ChatMessage(saved == null
            ? 'Olá! Tente: "Tenho uma reunião de última hora hoje às 17h" ou "remover Estudar ML de hoje".'
            : 'Bem-vindo de volta! Sua agenda foi carregada.'),
        if (rules.isEmpty)
          const ChatMessage(
              'Você ainda não cadastrou sua rotina fixa. Toque em "Rotina fixa" no topo do calendário para adicionar suas aulas, ou digite "carregar exemplo" para ver o app funcionando.'),
      ],
    );
  }

  DateTime get _today {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  void shiftWeek(int delta) => shiftDays(7 * delta);

  /// Move a janela visível: de 7 em 7 dias no desktop, de 3 em 3 no celular.
  /// A semana de referência (usada para "quinta", "sexta"...) acompanha.
  void shiftDays(int delta) {
    final f = state.focusDay;
    final next = DateTime(f.year, f.month, f.day + delta);
    final monday = DateTime(next.year, next.month, next.day - (next.weekday - 1));
    final weeks = (monday.difference(_baseMonday).inDays / 7).round();
    if (weeks < -_backWeeks || weeks > _aheadWeeks) return;
    state = state.copyWith(focusDay: next, weekStart: monday);
  }

  void goToToday() {
    final t = _today;
    state = state.copyWith(
      focusDay: t,
      weekStart: DateTime(t.year, t.month, t.day - (t.weekday - 1)),
    );
  }

  // ---- Rotina fixa (cadastro manual; o chat nunca altera estes blocos) ---------

  void saveRule(FixedRule rule) {
    final isNew = !state.rules.any((r) => r.id == rule.id);
    final rules = [...state.rules.where((r) => r.id != rule.id), rule]
      ..sort((a, b) {
        final c = a.weekdays.first.compareTo(b.weekdays.first);
        return c != 0 ? c : a.startMin.compareTo(b.startMin);
      });
    _applyRules(
      rules,
      '${isNew ? 'Adicionei' : 'Atualizei'} na rotina fixa: "${rule.title}" '
      '(${rule.daysLabel}, ${fmtMinutes(rule.startMin)}–${fmtMinutes(rule.endMin)}).',
    );
  }

  void deleteRule(String id) {
    final rule = state.rules.where((r) => r.id == id).firstOrNull;
    if (rule == null) return;
    _applyRules(
      state.rules.where((r) => r.id != id).toList(),
      'Removi "${rule.title}" da rotina fixa.',
    );
  }

  void _applyRules(List<FixedRule> rules, String note) {
    final dyn = state.blocks.where((b) => b.layer == Layer.dynamic).toList();
    final fixed = expandRules(rules, _baseMonday, _backWeeks, _aheadWeeks);
    final now = DateTime.now();
    final clashes = dyn
        .where((d) => d.end.isAfter(now) && fixed.any((f) => f.overlaps(d)))
        .toList()
      ..sort((a, b) => a.start.compareTo(b.start));

    state = state.copyWith(rules: rules, blocks: [...fixed, ...dyn], clearPending: true);
    _say(note);
    if (clashes.isNotEmpty) {
      final list = clashes
          .take(5)
          .map((b) => '"${b.title}" (${dayDate(b.start)} ${hhmm(b.start)})')
          .join(', ');
      _say('Atenção: ${clashes.length} atividade(s) do calendário dinâmico agora colidem com a rotina fixa: $list. '
          'Use "remover <nome>" se quiser tirar alguma.');
    }
  }

  void _say(String text, {bool user = false}) {
    state = state.copyWith(
        messages: [...state.messages, ChatMessage(text, fromUser: user)]);
  }

  void submit(String text) {
    final t = text.trim();
    if (t.isEmpty) return;
    _say(t, user: true);
    if (t.toLowerCase() == 'limpar atividades') {
      final n = state.blocks.where((b) => b.layer == Layer.dynamic).length;
      state = state.copyWith(
        blocks: state.blocks.where((b) => b.layer == Layer.fixed).toList(),
        clearPending: true,
      );
      _say(n == 0
          ? 'Não há atividades para limpar.'
          : 'Removi $n atividade(s) do calendário dinâmico. A base fixa não foi alterada.');
      return;
    }
    if (isDemoCommand(t)) {
      _loadDemo();
      return;
    }
    if (isUndoCommand(t)) {
      _undo();
      return;
    }
    if (isRestoreCommand(t)) {
      state = state.copyWith(clearPending: true);
      _restore(parseRemove(t, DateTime.now(), state.weekStart));
      return;
    }
    if (isMoveCommand(t)) {
      final mv = parseMove(t, DateTime.now(), state.weekStart);
      // "mover para amanhã 19h" no meio de uma negociação é resposta, não comando.
      if (!(mv.source.isEmpty && state.pending != null)) {
        state = state.copyWith(clearPending: true);
        _move(mv);
        return;
      }
    }
    if (isRemoveCommand(t) || isCancelStatement(t)) {
      state = state.copyWith(clearPending: true);
      _remove(parseRemove(t, DateTime.now(), state.weekStart));
      return;
    }
    final open = state.pending;
    if (open != null) {
      _handleReply(t, open);
      return;
    }
    final incoming = parseIntent(t, DateTime.now());
    if (incoming == null) {
      _say('Não identifiquei um horário. Ex.: "reunião hoje às 17h".');
      return;
    }
    request(incoming);
  }

  /// Dados de exemplo para quem acabou de abrir o app (só em agenda sem rotina).
  void _loadDemo() {
    if (state.rules.isNotEmpty) {
      _say('Você já tem uma rotina fixa cadastrada. O exemplo só carrega numa agenda sem rotina, para não misturar com os seus dados.');
      return;
    }
    const rules = [
      FixedRule(id: 'demo-calc', title: 'Cálculo II', weekdays: [1, 3, 5], startMin: 8 * 60, endMin: 10 * 60),
      FixedRule(id: 'demo-lab', title: 'Laboratório', weekdays: [2, 4], startMin: 14 * 60, endMin: 16 * 60),
    ];
    final dyn = state.blocks.where((b) => b.layer == Layer.dynamic).toList();
    final fixed = expandRules(rules, _baseMonday, _backWeeks, _aheadWeeks);
    state = state.copyWith(
      rules: rules,
      blocks: [...fixed, ...dyn, if (!dyn.any((b) => b.id == 'dy-fis')) ..._seedDynamic(_today)],
      clearPending: true,
    );
    _say('Carreguei um exemplo: Cálculo II e Laboratório na rotina fixa e um "Estudo de Física" hoje às 17h. '
        'Tente: "Tenho uma reunião de última hora hoje às 17h".');
  }

  List<TimeBlock> _match(RemoveIntent r) => state.blocks.where((b) {
        if (r.day != null && !sameDay(b.start, r.day!)) return false;
        if (r.minutes != null) {
          final s = b.start.hour * 60 + b.start.minute;
          if (!(s <= r.minutes! && r.minutes! < s + b.duration.inMinutes)) return false;
        }
        final t = normalizeText(b.title);
        return r.words.every(t.contains);
      }).toList();

  void _undo() {
    if (_undoStack.isEmpty) {
      _say('Não há nada para desfazer.');
      return;
    }
    final snap = _undoStack.removeLast();
    _skipBlocks = snap.blocks;
    _skipRules = snap.rules;
    state = state.copyWith(blocks: snap.blocks, rules: snap.rules, clearPending: true);
    _say('Desfeito. Voltei a agenda ao estado anterior.');
  }

  /// Remarca um evento: "remarque X para amanhã 15h", "adiar X 30 min".
  /// Evento fixo: só aquela data é cancelada e vira uma atividade dinâmica.
  void _move(MoveIntent mv) {
    final r = mv.source;
    if (r.isEmpty) {
      _say('O que devo remarcar? Ex.: "remarcar Estudar ML para amanhã 10h".');
      return;
    }
    if (!mv.hasTarget) {
      _say('Para quando? Ex.: "remarcar ${r.words.isEmpty ? 'a reunião' : r.words.join(' ')} para amanhã 15h" ou "adiar 30 min".');
      return;
    }
    final now = DateTime.now();
    final matches = _match(r).where((b) => r.day != null || b.end.isAfter(now)).toList();
    final dyn = matches.where((b) => b.layer == Layer.dynamic).toList();
    final fixed = matches.where((b) => b.layer == Layer.fixed).toList();

    TimeBlock b;
    if (matches.isEmpty) {
      _say('Não encontrei nenhuma atividade com esse filtro.');
      return;
    } else if (dyn.length > 1) {
      final list = dyn.map((x) => '"${x.title}" (${dayDate(x.start)} ${hhmm(x.start)})').join(', ');
      _say('Encontrei ${dyn.length} atividades: $list. Diga qual remarcar, ex.: "remarcar ${dyn.first.title} para ...".');
      return;
    } else if (dyn.length == 1) {
      b = dyn.first;
    } else {
      if (r.day == null) {
        _say('"${fixed.first.title}" é da rotina fixa. Diga de qual dia, ex.: "remarcar ${fixed.first.title} de quinta para 15h".');
        return;
      }
      if (fixed.length > 1) {
        final list = fixed.map((x) => '"${x.title}" (${hhmm(x.start)})').join(', ');
        _say('Há ${fixed.length} compromissos fixos em ${dayDate(r.day!)}: $list. Diga qual remarcar.');
        return;
      }
      b = fixed.first;
    }

    final day = mv.targetDay ?? DateTime(b.start.year, b.start.month, b.start.day);
    final mins = mv.targetMinutes ?? (b.start.hour * 60 + b.start.minute);
    final newStart = mv.shift != null ? b.start.add(mv.shift!) : DateTime(day.year, day.month, day.day, 0, mins);
    final newEnd = newStart.add(b.duration);

    if (newStart == b.start) {
      _say('"${b.title}" já está nesse horário.');
      return;
    }
    if (newEnd.isBefore(now)) {
      _say('Esse horário já passou. Escolha um horário futuro para "${b.title}".');
      return;
    }
    final incoming = b.layer == Layer.dynamic
        ? b.copyWith(start: newStart, end: newEnd)
        : TimeBlock(
            id: newBlockId(),
            title: b.title,
            layer: Layer.dynamic,
            start: newStart,
            end: newEnd,
          );
    request(incoming, replaceId: b.id);
  }

  void _remove(RemoveIntent r) {
    if (r.isEmpty) {
      _say('O que devo remover? Ex.: "remover Estudar ML de hoje" ou "aula de Cálculo de quinta foi cancelada".');
      return;
    }
    final matches = _match(r);
    final dyn = matches.where((b) => b.layer == Layer.dynamic).toList();
    final fixed = matches.where((b) => b.layer == Layer.fixed).toList();

    if (matches.isEmpty) {
      _say('Não encontrei nenhuma atividade com esse filtro.');
    } else if (dyn.isEmpty) {
      _cancelFixed(fixed, r);
    } else if (dyn.length > 1) {
      final list = dyn.map((b) => '"${b.title}" (${dayDate(b.start)} ${hhmm(b.start)})').join(', ');
      _say('Encontrei ${dyn.length} atividades: $list. Diga qual remover, ex.: "remover ${dyn.first.title}".');
    } else {
      final b = dyn.first;
      state = state.copyWith(blocks: state.blocks.where((x) => x.id != b.id).toList());
      _say('Removi "${b.title}" (${dayDate(b.start)} ${hhmm(b.start)}–${hhmm(b.end)}).');
    }
  }

  /// Cancela só a ocorrência daquele dia; a regra da rotina fixa não muda.
  void _cancelFixed(List<TimeBlock> fixed, RemoveIntent r) {
    if (r.day == null) {
      _say('"${fixed.first.title}" é da rotina fixa. Diga o dia para eu cancelar só aquela aula, '
          'ex.: "aula de ${fixed.first.title} de quinta foi cancelada". Para remover de todas as semanas, use Rotina fixa.');
      return;
    }
    if (fixed.length > 1 && r.words.isEmpty && r.minutes == null) {
      final list = fixed.map((b) => '"${b.title}" (${hhmm(b.start)})').join(', ');
      _say('Há ${fixed.length} compromissos fixos em ${dayDate(r.day!)}: $list. Diga qual foi cancelado.');
      return;
    }
    final key = dateKey(r.day!);
    var rules = state.rules;
    final done = <String>[];
    for (final b in fixed) {
      final rule = rules.where((x) => b.id.startsWith('fx-${x.id}-')).firstOrNull;
      if (rule == null || rule.skipDates.contains(key)) continue;
      rules = [
        for (final x in rules)
          x.id == rule.id ? x.copyWith(skipDates: [...x.skipDates, key]) : x,
      ];
      done.add('"${b.title}" ${hhmm(b.start)}–${hhmm(b.end)}');
    }
    if (done.isEmpty) {
      _say('Essa aula já está cancelada em ${dayDate(r.day!)}.');
      return;
    }
    final dow = weekdayShort[r.day!.weekday - 1].toLowerCase();
    _applyRules(
      rules,
      'Cancelei só em ${dayDate(r.day!)}: ${done.join(', ')}. A rotina fixa continua valendo nas outras semanas. '
      'Para desfazer: "restaurar ${fixed.first.title} $dow".',
    );
  }

  void _restore(RemoveIntent r) {
    if (r.day == null) {
      _say('Qual dia? Ex.: "restaurar Lóg. Prog. quinta".');
      return;
    }
    final key = dateKey(r.day!);
    final hit = state.rules
        .where((x) => x.skipDates.contains(key) && r.words.every(normalizeText(x.title).contains))
        .toList();
    if (hit.isEmpty) {
      _say('Não encontrei aula cancelada em ${dayDate(r.day!)}.');
      return;
    }
    final ids = hit.map((x) => x.id).toSet();
    _applyRules(
      [
        for (final x in state.rules)
          ids.contains(x.id) ? x.copyWith(skipDates: x.skipDates.where((d) => d != key).toList()) : x,
      ],
      'Restaurei ${hit.map((x) => '"${x.title}"').join(', ')} em ${dayDate(r.day!)}.',
    );
  }

  List<TimeBlock> _without(String? id) =>
      id == null ? state.blocks : state.blocks.where((b) => b.id != id).toList();

  /// Regras com a data do bloco fixo [replaceId] marcada como cancelada
  /// (usado ao remarcar uma aula fixa de um dia só).
  List<FixedRule> _rulesSkipping(String? replaceId) {
    if (replaceId == null || !replaceId.startsWith('fx-')) return state.rules;
    final b = state.blocks.where((x) => x.id == replaceId).firstOrNull;
    if (b == null) return state.rules;
    final key = dateKey(b.start);
    return [
      for (final r in state.rules)
        replaceId.startsWith('fx-${r.id}-') && !r.skipDates.contains(key)
            ? r.copyWith(skipDates: [...r.skipDates, key])
            : r,
    ];
  }

  /// Coloca [incoming] na agenda. Com [replaceId], é uma remarcação: o bloco
  /// antigo só some quando o novo horário é confirmado.
  void request(TimeBlock incoming, {String? replaceId}) {
    final others = _without(replaceId);
    final conflicts = findConflicts(others, incoming);
    final moving = replaceId != null;
    final lead = moving
        ? 'Ok, remarcando "${incoming.title}" para ${dayDate(incoming.start)} ${hhmm(incoming.start)}.'
        : 'OK, adicionando "${incoming.title}" ao calendário de atividades.';

    if (conflicts.isEmpty) {
      final later = others
          .where((b) => !b.start.isBefore(incoming.end) && sameDay(b.start, incoming.end))
          .toList()
        ..sort((a, b) => a.start.compareTo(b.start));
      final free = later.isEmpty
          ? 'Esse horário está livre pelo resto do dia.'
          : 'Esse horário está livre até ${hhmm(later.first.start)}, quando você tem "${later.first.title}".';
      state = state.copyWith(
        blocks: [...others, incoming],
        rules: _rulesSkipping(replaceId),
        clearPending: true,
      );
      _say(moving
          ? 'Remarquei "${incoming.title}" para ${dayDate(incoming.start)} ${hhmm(incoming.start)}–${hhmm(incoming.end)}. $free'
          : '$lead $free');
      return;
    }

    final blockedByFixed = conflicts.any((b) => b.layer == Layer.fixed);
    final subject = blockedByFixed ? incoming : conflicts.first;
    final ignore = blockedByFixed ? <String>{} : conflicts.map((b) => b.id).toSet();
    final base = blockedByFixed ? others : [...others, incoming];

    final sug = suggestSlots(
      base,
      duration: subject.duration,
      weekStart: _today,
      preferred: subject.start,
      ignoreIds: ignore,
      notBefore: DateTime.now(),
    );

    if (sug.isEmpty) {
      _say('Há choque com "${conflicts.first.title}" e não encontrei janela livre nos próximos dias. Nada foi alterado.');
      return;
    }

    state = state.copyWith(
      pending: PendingConflict(
        incoming: incoming,
        conflicts: conflicts,
        suggestions: sug,
        blockedByFixed: blockedByFixed,
        stage: blockedByFixed ? Stage.preference : Stage.priority,
        replaces: replaceId,
      ),
    );
    final c = conflicts.first;
    _say(blockedByFixed
        ? '$lead Esse horário está ocupado por "${c.title}" (compromisso fixo, não posso mover). Qual a data de preferência para encaixar "${incoming.title}"?'
        : '$lead Esse horário está ocupado com "${c.title}". Gostaria de dar prioridade para "${incoming.title}" e encaixar "${c.title}" em outro horário durante a semana?');
  }

  static const _yes = {'sim', 's', 'ok', 'pode', 'claro', 'quero', 'prioridade', 'priorize', 'priorizar'};
  static const _no = {'não', 'nao', 'n', 'nunca'};

  void _handleReply(String t, PendingConflict p) {
    final words = t.toLowerCase().split(RegExp(r'[^a-zà-ú]+')).where((w) => w.isNotEmpty).toList();
    if (words.contains('cancelar') || words.contains('cancela')) {
      cancelPending();
      return;
    }
    if (p.stage == Stage.priority) {
      if (words.any(_no.contains)) {
        final sug = suggestSlots(_without(p.replaces),
            duration: p.incoming.duration,
            weekStart: _today,
            preferred: p.incoming.start,
            notBefore: DateTime.now());
        state = state.copyWith(
            pending: p.copyWith(blockedByFixed: true, suggestions: sug, stage: Stage.preference));
        _say('Ok, mantenho "${p.conflicts.first.title}". Qual a data de preferência para "${p.incoming.title}"? Escolha uma opção ou escreva, ex.: "amanhã 19h".');
      } else if (words.any(_yes.contains)) {
        state = state.copyWith(pending: p.copyWith(stage: Stage.preference));
        _say('Qual a data de preferência para encaixar "${p.conflicts.first.title}"? Escolha uma opção ou escreva, ex.: "amanhã 19h".');
      } else {
        _say('Responda "sim" para priorizar "${p.incoming.title}" ou "não" para mantê-la como está.');
      }
      return;
    }
    final pref = parsePreference(t, DateTime.now());
    if (pref == null) {
      _say('Não entendi a data. Escreva algo como "amanhã 19h" ou escolha uma opção.');
      return;
    }
    final subject = p.blockedByFixed ? p.incoming : p.conflicts.first;
    final ignore = p.blockedByFixed ? <String>{} : p.conflicts.map((b) => b.id).toSet();
    final cur = _without(p.replaces);
    final base = p.blockedByFixed ? cur : [...cur, p.incoming];
    final sug = suggestSlots(base,
        duration: subject.duration,
        weekStart: _today,
        preferred: pref,
        ignoreIds: ignore,
        notBefore: DateTime.now());
    if (sug.isEmpty) {
      _say('Não encontrei janela livre nesta semana. Quer tentar outro dia?');
      return;
    }
    state = state.copyWith(pending: p.copyWith(suggestions: sug));
    if (sug.first.start == pref) {
      resolve(0);
    } else {
      _say('Não há janela livre exatamente nesse horário. Estas são as opções mais próximas:');
    }
  }

  void resolve(int index) {
    final p = state.pending;
    if (p == null || index >= p.suggestions.length) return;
    final s = p.suggestions[index];

    if (p.blockedByFixed) {
      final placed = p.incoming.copyWith(start: s.start, end: s.end);
      state = state.copyWith(
        blocks: [..._without(p.replaces), placed],
        rules: _rulesSkipping(p.replaces),
        clearPending: true,
      );
      _say('Pronto: ${p.replaces != null ? 'remarquei ' : ''}"${placed.title}" ${dayDate(s.start)} às ${hhmm(s.start)}.');
      return;
    }

    var working = [
      ..._without(p.replaces).where((b) => !p.conflicts.any((c) => c.id == b.id)),
      p.incoming,
    ];
    final moved = <String>[];
    for (var i = 0; i < p.conflicts.length; i++) {
      final c = p.conflicts[i];
      final slot = i == 0
          ? s
          : suggestSlots(working,
                  duration: c.duration,
                  weekStart: _today,
                  preferred: s.start,
                  notBefore: DateTime.now(),
                  max: 1)
              .firstOrNull;
      if (slot == null) {
        _say('Não consegui realocar "${c.title}". Nada foi alterado.');
        return;
      }
      working = [...working, c.copyWith(start: slot.start, end: slot.start.add(c.duration))];
      moved.add('"${c.title}" → ${dayDate(slot.start)} ${hhmm(slot.start)}');
    }
    state = state.copyWith(blocks: working, rules: _rulesSkipping(p.replaces), clearPending: true);
    _say('Feito. ${p.incoming.title} às ${hhmm(p.incoming.start)}; ${moved.join(', ')}.');
  }

  void cancelPending() {
    state = state.copyWith(clearPending: true);
    _say('Ok, nada foi alterado.');
  }
}


List<TimeBlock> _seedDynamic(DateTime today) => [
      TimeBlock(
        id: 'dy-fis',
        title: 'Estudo de Física',
        layer: Layer.dynamic,
        start: DateTime(today.year, today.month, today.day, 17),
        end: DateTime(today.year, today.month, today.day, 18, 30),
      ),
    ];
