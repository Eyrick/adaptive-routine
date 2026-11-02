import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/block_repository.dart';
import '../../domain/models.dart';
import '../../domain/scheduling.dart';
import '../chat/mock_intent.dart';

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
  });
  final TimeBlock incoming;
  final List<TimeBlock> conflicts;
  final List<SlotSuggestion> suggestions;
  final bool blockedByFixed; // true: o NOVO evento é que precisa de outra janela
  final Stage stage;

  PendingConflict copyWith({List<SlotSuggestion>? suggestions, bool? blockedByFixed, Stage? stage}) =>
      PendingConflict(
        incoming: incoming,
        conflicts: conflicts,
        suggestions: suggestions ?? this.suggestions,
        blockedByFixed: blockedByFixed ?? this.blockedByFixed,
        stage: stage ?? this.stage,
      );
}

class CalendarState {
  const CalendarState({
    required this.blocks,
    required this.weekStart,
    this.pending,
    this.messages = const [],
  });
  final List<TimeBlock> blocks;
  final DateTime weekStart;
  final PendingConflict? pending;
  final List<ChatMessage> messages;

  CalendarState copyWith({
    List<TimeBlock>? blocks,
    List<ChatMessage>? messages,
    PendingConflict? pending,
    DateTime? weekStart,
    bool clearPending = false,
  }) =>
      CalendarState(
        blocks: blocks ?? this.blocks,
        weekStart: weekStart ?? this.weekStart,
        messages: messages ?? this.messages,
        pending: clearPending ? null : (pending ?? this.pending),
      );
}

final calendarProvider =
    NotifierProvider<CalendarController, CalendarState>(CalendarController.new);

class CalendarController extends Notifier<CalendarState> {
  static const _backWeeks = 4, _aheadWeeks = 26;
  DateTime _baseMonday = DateTime(2000);

  @override
  CalendarState build() {
    final repo = ref.read(blockRepositoryProvider);
    final saved = ref.read(initialBlocksProvider); // só camada dinâmica
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final monday = today.subtract(Duration(days: today.weekday - 1));
    _baseMonday = monday;

    final dynamicBlocks = saved ?? _seedDynamic(today);
    if (saved == null) Future.microtask(() => repo.save(dynamicBlocks));

    // Persiste a camada dinâmica sempre que a lista de blocos muda.
    ref.listenSelf((prev, next) {
      if (prev != null && !identical(prev.blocks, next.blocks)) {
        repo.save(next.blocks.where((b) => b.layer == Layer.dynamic).toList());
      }
    });

    return CalendarState(
      weekStart: monday,
      blocks: [..._expandFixed(monday, _backWeeks, _aheadWeeks), ...dynamicBlocks],
      messages: [
        ChatMessage(saved == null
            ? 'Olá! Tente: "Tenho uma reunião de última hora hoje às 17h" ou "remover Estudar ML de hoje".'
            : 'Bem-vindo de volta! Sua agenda foi carregada.'),
      ],
    );
  }

  DateTime get _today {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  void shiftWeek(int delta) {
    final w = state.weekStart;
    final next = DateTime(w.year, w.month, w.day + 7 * delta);
    final weeks = (next.difference(_baseMonday).inDays / 7).round();
    if (weeks < -_backWeeks || weeks > _aheadWeeks) return;
    state = state.copyWith(weekStart: next);
  }

  void goToToday() {
    final t = _today;
    state = state.copyWith(weekStart: t.subtract(Duration(days: t.weekday - 1)));
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
    if (isRemoveCommand(t)) {
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

  void _remove(RemoveIntent r) {
    if (r.isEmpty) {
      _say('O que devo remover? Ex.: "remover Estudar ML de hoje" ou "remover Dom 8h".');
      return;
    }
    final matches = state.blocks.where((b) {
      if (r.day != null && !sameDay(b.start, r.day!)) return false;
      if (r.minutes != null) {
        final s = b.start.hour * 60 + b.start.minute;
        if (!(s <= r.minutes! && r.minutes! < s + b.duration.inMinutes)) return false;
      }
      final t = b.title.toLowerCase();
      return r.words.every(t.contains);
    }).toList();
    final dyn = matches.where((b) => b.layer == Layer.dynamic).toList();

    if (matches.isEmpty) {
      _say('Não encontrei nenhuma atividade com esse filtro.');
    } else if (dyn.isEmpty) {
      _say('Isso é da base fixa e eu não altero compromissos fixos. Edite direto no calendário.');
    } else if (dyn.length > 1) {
      final list = dyn.map((b) => '"${b.title}" (${dayDate(b.start)} ${hhmm(b.start)})').join(', ');
      _say('Encontrei ${dyn.length} atividades: $list. Diga qual remover, ex.: "remover ${dyn.first.title}".');
    } else {
      final b = dyn.first;
      state = state.copyWith(blocks: state.blocks.where((x) => x.id != b.id).toList());
      _say('Removi "${b.title}" (${dayDate(b.start)} ${hhmm(b.start)}–${hhmm(b.end)}).');
    }
  }

  void request(TimeBlock incoming) {
    final conflicts = findConflicts(state.blocks, incoming);

    if (conflicts.isEmpty) {
      final later = state.blocks
          .where((b) => !b.start.isBefore(incoming.end) && sameDay(b.start, incoming.end))
          .toList()
        ..sort((a, b) => a.start.compareTo(b.start));
      final free = later.isEmpty
          ? 'Esse horário está livre pelo resto do dia.'
          : 'Esse horário está livre até ${hhmm(later.first.start)}, quando você tem "${later.first.title}".';
      state = state.copyWith(blocks: [...state.blocks, incoming], clearPending: true);
      _say('OK, adicionando "${incoming.title}" ao calendário de atividades. $free');
      return;
    }

    final blockedByFixed = conflicts.any((b) => b.layer == Layer.fixed);
    final subject = blockedByFixed ? incoming : conflicts.first;
    final ignore = blockedByFixed ? <String>{} : conflicts.map((b) => b.id).toSet();
    final base = blockedByFixed ? state.blocks : [...state.blocks, incoming];

    final sug = suggestSlots(
      base,
      duration: subject.duration,
      weekStart: _today,
      preferred: subject.start,
      ignoreIds: ignore,
      notBefore: DateTime.now(),
    );

    if (sug.isEmpty) {
      _say('Há choque com "${conflicts.first.title}" e não encontrei janela livre nesta semana.');
      return;
    }

    state = state.copyWith(
      pending: PendingConflict(
        incoming: incoming,
        conflicts: conflicts,
        suggestions: sug,
        blockedByFixed: blockedByFixed,
        stage: blockedByFixed ? Stage.preference : Stage.priority,
      ),
    );
    final c = conflicts.first;
    _say(blockedByFixed
        ? 'OK, adicionando "${incoming.title}". Esse horário está ocupado por "${c.title}" (compromisso fixo, não posso mover). Qual a data de preferência para encaixar "${incoming.title}"?'
        : 'OK, adicionando "${incoming.title}" ao calendário de atividades. Esse horário está ocupado com "${c.title}". Gostaria de dar prioridade para "${incoming.title}" e encaixar "${c.title}" em outro horário durante a semana?');
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
        final sug = suggestSlots(state.blocks,
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
    final base = p.blockedByFixed ? state.blocks : [...state.blocks, p.incoming];
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
      state = state.copyWith(blocks: [...state.blocks, placed], clearPending: true);
      _say('Pronto: "${placed.title}" ${dayDate(s.start)} às ${hhmm(s.start)}.');
      return;
    }

    var working = [
      ...state.blocks.where((b) => !p.conflicts.any((c) => c.id == b.id)),
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
    state = state.copyWith(blocks: working, clearPending: true);
    _say('Feito. ${p.incoming.title} às ${hhmm(p.incoming.start)}; ${moved.join(', ')}.');
  }

  void cancelPending() {
    state = state.copyWith(clearPending: true);
    _say('Ok, nada foi alterado.');
  }
}


// ---- Base fixa de demonstração (até o cadastro real da rotina, M4) ----------

class _Rule {
  const _Rule(this.id, this.title, this.days, this.startH, this.endH);
  final String id, title;
  final List<int> days; // 0 = segunda
  final int startH, endH;
}

const _demoRules = [
  _Rule('calc', 'Cálculo II', [0, 1, 2, 3, 4], 8, 10),
  _Rule('lab', 'Laboratório', [1, 3], 14, 16),
];

List<TimeBlock> _expandFixed(DateTime baseMonday, int back, int ahead) => [
      for (var w = -back; w <= ahead; w++)
        for (final r in _demoRules)
          for (final d in r.days)
            TimeBlock(
              id: 'fx-${r.id}-$w-$d',
              title: r.title,
              layer: Layer.fixed,
              start: DateTime(baseMonday.year, baseMonday.month, baseMonday.day + w * 7 + d, r.startH),
              end: DateTime(baseMonday.year, baseMonday.month, baseMonday.day + w * 7 + d, r.endH),
            ),
    ];

List<TimeBlock> _seedDynamic(DateTime today) => [
      TimeBlock(
        id: 'dy-fis',
        title: 'Estudo de Física',
        layer: Layer.dynamic,
        start: DateTime(today.year, today.month, today.day, 17),
        end: DateTime(today.year, today.month, today.day, 18, 30),
      ),
    ];
