import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/fixed_rule.dart';
import '../../domain/holiday.dart';
import '../../domain/models.dart';
import '../../domain/scheduling.dart';
import '../../sync/sync_screen.dart';
import '../../sync/sync_service.dart';
import '../routine/routine_screen.dart';
import 'block_sheet.dart';
import 'block_style.dart';
import 'calendar_controller.dart';
import 'holiday_dialog.dart';

const double _hourH = 56;
const double _gutter = 44;

/// Abaixo desta largura (celular) o calendário mostra 3 dias em vez de 7.
const double _compactBelow = 640;

class DualCalendarView extends ConsumerStatefulWidget {
  const DualCalendarView({super.key});
  @override
  ConsumerState<DualCalendarView> createState() => _DualCalendarViewState();
}

class _DualCalendarViewState extends ConsumerState<DualCalendarView> {
  bool showFixed = true, showDynamic = true;

  void _openRoutine() => Navigator.of(context)
      .push(MaterialPageRoute(builder: (_) => const RoutineScreen()));

  @override
  Widget build(BuildContext context) {
    // Só reconstrói o calendário quando algo que ele mostra muda (e não a cada
    // mensagem do chat).
    final s = ref.watch(calendarProvider.select((st) => (
          blocks: st.blocks,
          weekStart: st.weekStart,
          focusDay: st.focusDay,
          holidays: st.holidays,
          ghost: st.pending?.incoming,
        )));
    final ctl = ref.read(calendarProvider.notifier);
    final cs = Theme.of(context).colorScheme;

    return LayoutBuilder(builder: (context, c) {
      final compact = c.maxWidth < _compactBelow;
      final step = compact ? 3 : 7;
      final first = compact ? s.focusDay : s.weekStart;
      final days = [
        for (var i = 0; i < (compact ? 3 : 7); i++)
          DateTime(first.year, first.month, first.day + i)
      ];
      final rangeEnd = DateTime(days.last.year, days.last.month, days.last.day + 1);

      bool inRange(DateTime t) => !t.isBefore(days.first) && t.isBefore(rangeEnd);
      final visible = s.blocks.where((b) => inRange(b.start)).toList();

      // A grade cresce para caber aulas cedo/tarde (ex.: 7h30 ou até 22h30).
      var startH = 8, endH = 22;
      final ghost = s.ghost;
      for (final b in [...visible, if (ghost != null && inRange(ghost.start)) ghost]) {
        startH = math.min(startH, b.start.hour);
        final eh = sameDay(b.start, b.end) ? (b.end.minute > 0 ? b.end.hour + 1 : b.end.hour) : 24;
        endH = math.max(endH, eh);
      }

      return Column(children: [
        Padding(
          padding: EdgeInsets.fromLTRB(compact ? 8 : 16, 8, 4, 4),
          child: Row(children: [
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  FilterChip(
                    avatar: const Icon(Icons.lock_outline, size: 16),
                    label: const Text('Base fixa'),
                    selected: showFixed,
                    onSelected: (v) => setState(() => showFixed = v),
                  ),
                  const SizedBox(width: 8),
                  FilterChip(
                    avatar: const Icon(Icons.bolt, size: 16),
                    label: const Text('Dinâmico'),
                    selected: showDynamic,
                    onSelected: (v) => setState(() => showDynamic = v),
                  ),
                  const SizedBox(width: 4),
                  compact
                      ? IconButton(
                          tooltip: 'Rotina fixa',
                          icon: const Icon(Icons.edit_calendar_outlined),
                          onPressed: _openRoutine,
                        )
                      : TextButton.icon(
                          icon: const Icon(Icons.edit_calendar_outlined, size: 18),
                          label: const Text('Rotina fixa'),
                          onPressed: _openRoutine,
                        ),
                  const _SyncButton(),
                ]),
              ),
            ),
            IconButton(
              tooltip: compact ? '3 dias antes' : 'Semana anterior',
              icon: const Icon(Icons.chevron_left),
              onPressed: () => ctl.shiftDays(-step),
            ),
            TextButton(onPressed: ctl.goToToday, child: const Text('Hoje')),
            IconButton(
              tooltip: compact ? 'Próximos 3 dias' : 'Próxima semana',
              icon: const Icon(Icons.chevron_right),
              onPressed: () => ctl.shiftDays(step),
            ),
          ]),
        ),
        Row(children: [
          const SizedBox(width: _gutter),
          for (var i = 0; i < days.length; i++)
            Expanded(
              child: _DayHeader(
                key: ValueKey('day-header-$i'),
                day: days[i],
                showMonth: (compact && i == 0) || days[i].day == 1,
                holiday: s.holidays[dateKey(days[i])],
                onTap: () => showHolidayDialog(context, days[i]),
              ),
            ),
        ]),
        Expanded(
          // No celular, deslizar para o lado avança ou volta 3 dias.
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragEnd: compact
                ? (d) {
                    final v = d.primaryVelocity ?? 0;
                    if (v < -250) ctl.shiftDays(step);
                    if (v > 250) ctl.shiftDays(-step);
                  }
                : null,
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(top: 10, bottom: 24),
              child: SizedBox(
                height: (endH - startH) * _hourH,
                child: Row(children: [
                  SizedBox(
                    width: _gutter,
                    child: Stack(clipBehavior: Clip.none, children: [
                      for (var h = startH; h < endH; h++)
                        Positioned(
                          top: (h - startH) * _hourH - 7,
                          right: 6,
                          child: Text('${h.toString().padLeft(2, '0')}:00',
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(color: cs.onSurfaceVariant)),
                        ),
                    ]),
                  ),
                  for (final d in days)
                    Expanded(
                      child: RepaintBoundary(
                        child: _DayColumn(
                          startH: startH,
                          endH: endH,
                          onTapBlock: (b) => showBlockActions(context, b),
                          holiday: s.holidays[dateKey(d)],
                          blocks: visible.where((b) {
                            if (!sameDay(b.start, d)) return false;
                            return b.layer == Layer.fixed ? showFixed : showDynamic;
                          }).toList(),
                          ghost: (ghost != null && sameDay(ghost.start, d)) ? ghost : null,
                        ),
                      ),
                    ),
                ]),
              ),
            ),
          ),
        ),
      ]);
    });
  }
}

class _DayColumn extends StatelessWidget {
  const _DayColumn({
    required this.startH,
    required this.endH,
    required this.blocks,
    required this.onTapBlock,
    this.holiday,
    this.ghost,
  });
  final Holiday? holiday;
  final void Function(TimeBlock) onTapBlock;
  final int startH, endH;
  final List<TimeBlock> blocks;
  final TimeBlock? ghost;

  int _min(DateTime t) => t.hour * 60 + t.minute;
  double _y(int minutes) => (minutes - startH * 60) / 60 * _hourH;

  ({double top, double height}) _geo(TimeBlock b) {
    final s = _min(b.start);
    final e = sameDay(b.start, b.end) ? _min(b.end) : 24 * 60;
    return (top: _y(s), height: math.max(14.0, _y(e) - _y(s) - 2));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: holiday != null ? dayKindTint(cs, holiday!.kind) : null,
        border: Border(left: BorderSide(color: cs.outlineVariant.withOpacity(.5))),
      ),
      child: Stack(children: [
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter: _GridPainter(
                hours: endH - startH,
                color: cs.outlineVariant.withOpacity(.4),
              ),
            ),
          ),
        ),
        for (final b in blocks)
          AnimatedPositioned(
            key: ValueKey(b.id),
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeOutCubic,
            top: _geo(b).top,
            height: _geo(b).height,
            left: 2,
            right: 2,
            child: _BlockTile(block: b, onTap: () => onTapBlock(b)),
          ),
        if (ghost != null)
          Positioned(
            top: _geo(ghost!).top,
            height: _geo(ghost!).height,
            left: 2,
            right: 2,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: cs.error, width: 1.5),
                color: Color.alphaBlend(cs.error.withOpacity(.12), cs.surface),
              ),
              padding: const EdgeInsets.all(6),
              child: Text('${ghost!.title}?',
                  style: TextStyle(color: cs.error, fontSize: 11)),
            ),
          ),
      ]),
    );
  }
}

/// Linhas horizontais da grade (uma por hora), desenhadas de uma vez.
class _GridPainter extends CustomPainter {
  _GridPainter({required this.hours, required this.color});
  final int hours;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    for (var i = 0; i < hours; i++) {
      final y = i * _hourH + 0.5;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_GridPainter old) => old.hours != hours || old.color != color;
}

class _BlockTile extends StatelessWidget {
  const _BlockTile({required this.block, required this.onTap});
  final TimeBlock block;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fixed = block.layer == Layer.fixed;
    final st = blockStyle(cs, block.layer, block.status);
    final IconData? statusIcon = switch (block.status) {
      BlockStatus.done => Icons.check_circle,
      BlockStatus.missed => Icons.cancel,
      BlockStatus.planned => null,
    };

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          decoration: BoxDecoration(
            color: st.bg,
            borderRadius: BorderRadius.circular(8),
            border: Border(left: BorderSide(color: st.accent, width: 3)),
          ),
          padding: const EdgeInsets.fromLTRB(6, 4, 4, 4),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Text('${block.title}\n${hhmm(block.start)}',
                  overflow: TextOverflow.ellipsis,
                  maxLines: 3,
                  style: TextStyle(color: st.fg, fontSize: 11, height: 1.25)),
            ),
            if (statusIcon != null) Icon(statusIcon, size: 12, color: st.accent),
            if (fixed) Icon(Icons.lock, size: 11, color: st.fg.withOpacity(.6)),
          ]),
        ),
      ),
    );
  }
}

/// Nome do dia no cabeçalho. Tocar abre a pergunta de feriado; num feriado o
/// nome dele aparece embaixo, em âmbar.
class _DayHeader extends StatelessWidget {
  const _DayHeader({
    super.key,
    required this.day,
    required this.showMonth,
    required this.holiday,
    required this.onTap,
  });
  final DateTime day;
  final bool showMonth;
  final Holiday? holiday;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final today = sameDay(day, DateTime.now());
    final style = Theme.of(context).textTheme.labelMedium;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          color: holiday != null ? dayKindTint(cs, holiday!.kind) : null,
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(
              '${dayLabel(day)} ${day.day}${showMonth ? '/${day.month}' : ''}',
              textAlign: TextAlign.center,
              style: style?.copyWith(
                color: today ? cs.primary : cs.onSurfaceVariant,
                fontWeight: today ? FontWeight.w700 : null,
              ),
            ),
            if (holiday != null)
              Text(
                holiday!.name.isEmpty
                    ? (holiday!.kind == DayKind.event ? 'Evento' : 'Feriado')
                    : holiday!.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .labelSmall
                    ?.copyWith(color: dayKindAccent(cs, holiday!.kind), fontWeight: FontWeight.w600),
              ),
          ]),
        ),
      ),
    );
  }
}

/// Ícone da nuvem na barra: mostra a situação da sincronização e abre a tela
/// de conta. Fica escondido quando o app não foi configurado para sincronizar.
class _SyncButton extends ConsumerWidget {
  const _SyncButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(syncProvider.select((s) => s.status));
    if (status == SyncStatus.notConfigured) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    final (IconData icon, Color? color) = switch (status) {
      SyncStatus.idle => (Icons.cloud_done_outlined, null),
      SyncStatus.syncing => (Icons.sync, null),
      SyncStatus.signedOut => (Icons.cloud_off_outlined, null),
      SyncStatus.offline => (Icons.cloud_off, cs.outline),
      SyncStatus.conflict => (Icons.warning_amber_rounded, cs.error),
      SyncStatus.error => (Icons.error_outline, cs.error),
      SyncStatus.notConfigured => (Icons.cloud_off_outlined, null),
    };
    return IconButton(
      tooltip: 'Conta e sincronização',
      icon: Icon(icon, color: color),
      onPressed: () => Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => const SyncScreen())),
    );
  }
}
