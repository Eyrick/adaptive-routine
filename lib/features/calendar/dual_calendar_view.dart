import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models.dart';
import '../../domain/scheduling.dart';
import 'calendar_controller.dart';

const double _hourH = 56;
const int _startH = 8, _endH = 22;
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
    final cs = Theme.of(context).colorScheme;

    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
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
          const Spacer(),
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
            height: (_endH - _startH) * _hourH,
            child: Row(children: [
              SizedBox(
                width: _gutter,
                child: Stack(clipBehavior: Clip.none, children: [
                  for (var h = _startH; h < _endH; h++)
                    Positioned(
                      top: (h - _startH) * _hourH - 7,
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
                      day: d,
                      blocks: s.blocks.where((b) {
                        if (!sameDay(b.start, d)) return false;
                        return b.layer == Layer.fixed ? showFixed : showDynamic;
                      }).toList(),
                      ghost: (s.pending != null && sameDay(s.pending!.incoming.start, d))
                          ? s.pending!.incoming
                          : null,
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
  const _DayColumn({required this.day, required this.blocks, this.ghost});
  final DateTime day;
  final List<TimeBlock> blocks;
  final TimeBlock? ghost;

  double _top(DateTime t) => (t.hour + t.minute / 60 - _startH) * _hourH;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
          border: Border(left: BorderSide(color: cs.outlineVariant.withOpacity(.5)))),
      child: Stack(children: [
        for (var h = 0; h < _endH - _startH; h++)
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
            top: _top(b.start),
            height: b.duration.inMinutes / 60 * _hourH - 2,
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
            top: _top(ghost!.start),
            height: ghost!.duration.inMinutes / 60 * _hourH - 2,
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