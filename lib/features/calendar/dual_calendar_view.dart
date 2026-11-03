import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models.dart';
import '../../domain/scheduling.dart';
import '../routine/routine_screen.dart';
import 'calendar_controller.dart';

const double _hourH = 56;
const double _gutter = 44;

class DualCalendarView extends ConsumerStatefulWidget {
  const DualCalendarView({super.key});
  @override
  ConsumerState<DualCalendarView> createState() => _DualCalendarViewState();
}

class _DualCalendarViewState extends ConsumerState<DualCalendarView> {
  bool showFixed = true, showDynamic = true;

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(calendarProvider);
    final days = [
      for (var i = 0; i < 7; i++)
        DateTime(s.weekStart.year, s.weekStart.month, s.weekStart.day + i)
    ];
    final weekEnd = DateTime(s.weekStart.year, s.weekStart.month, s.weekStart.day + 7);
    final cs = Theme.of(context).colorScheme;

    final weekBlocks = s.blocks
        .where((b) => !b.start.isBefore(days.first) && b.start.isBefore(weekEnd))
        .toList();

    // A grade cresce para caber aulas cedo/tarde (ex.: 7h30 ou até 22h30).
    var startH = 8, endH = 22;
    final ghost = s.pending?.incoming;
    final inRange = [
      ...weekBlocks,
      if (ghost != null && !ghost.start.isBefore(days.first) && ghost.start.isBefore(weekEnd)) ghost,
    ];
    for (final b in inRange) {
      startH = math.min(startH, b.start.hour);
      final eh = sameDay(b.start, b.end) ? (b.end.minute > 0 ? b.end.hour + 1 : b.end.hour) : 24;
      endH = math.max(endH, eh);
    }

    final routineButton = TextButton.icon(
      icon: const Icon(Icons.lock_outline, size: 18),
      label: const Text('Rotina fixa'),
      onPressed: () => Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => const RoutineScreen())),
    );

    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
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
                const SizedBox(width: 8),
                routineButton,
              ]),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: () => ref.read(calendarProvider.notifier).shiftWeek(-1),
          ),
          TextButton(
            onPressed: () => ref.read(calendarProvider.notifier).goToToday(),
            child: const Text('Hoje'),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: () => ref.read(calendarProvider.notifier).shiftWeek(1),
          ),
        ]),
      ),
      Row(children: [
        const SizedBox(width: _gutter),
        for (final d in days)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                '${dayLabel(d)} ${d.day}',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: sameDay(d, DateTime.now()) ? cs.primary : cs.onSurfaceVariant,
                      fontWeight: sameDay(d, DateTime.now()) ? FontWeight.w700 : null,
                    ),
              ),
            ),
          ),
      ]),
      Expanded(
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
                      blocks: weekBlocks.where((b) {
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
    ]);
  }
}

class _DayColumn extends StatelessWidget {
  const _DayColumn({
    required this.startH,
    required this.endH,
    required this.blocks,
    this.ghost,
  });
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
          border: Border(left: BorderSide(color: cs.outlineVariant.withOpacity(.5)))),
      child: Stack(children: [
        for (var h = 0; h < endH - startH; h++)
          Positioned(
              top: h * _hourH,
              left: 0,
              right: 0,
              child: Divider(height: 1, color: cs.outlineVariant.withOpacity(.4))),
        for (final b in blocks)
          AnimatedPositioned(
            key: ValueKey(b.id),
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeOutCubic,
            top: _geo(b).top,
            height: _geo(b).height,
            left: 2,
            right: 2,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 250),
              builder: (_, v, child) => Opacity(opacity: v, child: child),
              child: _BlockTile(block: b),
            ),
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

class _BlockTile extends StatelessWidget {
  const _BlockTile({required this.block});
  final TimeBlock block;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fixed = block.layer == Layer.fixed;
    final bg = fixed ? cs.surfaceContainerHighest : cs.primaryContainer;
    final fg = fixed ? cs.onSurfaceVariant : cs.onPrimaryContainer;
    final accent = fixed ? cs.outline : cs.primary;

    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: Border(left: BorderSide(color: accent, width: 3)),
      ),
      padding: const EdgeInsets.fromLTRB(6, 4, 4, 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Text('${block.title}\n${hhmm(block.start)}',
              overflow: TextOverflow.ellipsis,
              maxLines: 3,
              style: TextStyle(color: fg, fontSize: 11, height: 1.25)),
        ),
        if (fixed) Icon(Icons.lock, size: 11, color: fg.withOpacity(.6)),
      ]),
    );
  }
}
