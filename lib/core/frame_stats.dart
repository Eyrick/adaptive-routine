import 'dart:async';
import 'dart:ui' show FrameTiming;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Liga ou desliga o medidor de desempenho (comando "desempenho" no chat).
final ValueNotifier<bool> showFrameStats = ValueNotifier<bool>(false);

/// Medidor simples de quadros, para olhar números reais no próprio aparelho
/// (por exemplo, no iPhone). Mostra, a cada segundo: quantos quadros foram
/// desenhados, a duração média e a pior. Um quadro leva ~16,7 ms a 60 fps.
/// Se a tela está parada, não há quadros, e isso é normal.
class FrameStatsOverlay extends StatefulWidget {
  const FrameStatsOverlay({super.key, required this.child});
  final Widget child;

  @override
  State<FrameStatsOverlay> createState() => _FrameStatsOverlayState();
}

class _FrameStatsOverlayState extends State<FrameStatsOverlay> {
  final List<double> _spans = []; // duração total de cada quadro (ms) no último segundo
  Timer? _timer;
  String _text = 'medindo...';

  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _flush());
  }

  @override
  void dispose() {
    SchedulerBinding.instance.removeTimingsCallback(_onTimings);
    _timer?.cancel();
    super.dispose();
  }

  void _onTimings(List<FrameTiming> timings) {
    if (!showFrameStats.value) return;
    for (final t in timings) {
      _spans.add(t.totalSpan.inMicroseconds / 1000.0);
    }
  }

  void _flush() {
    if (!showFrameStats.value || !mounted) return;
    if (_spans.isEmpty) {
      setState(() => _text = 'tela parada (sem quadros)');
      return;
    }
    final n = _spans.length;
    final avg = _spans.reduce((a, b) => a + b) / n;
    final worst = _spans.reduce((a, b) => a > b ? a : b);
    final slow = _spans.where((m) => m > 16.7).length;
    setState(() => _text = '$n quadros/s · média ${avg.toStringAsFixed(1)} ms · '
        'pior ${worst.toStringAsFixed(0)} ms · lentos $slow');
    _spans.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      widget.child,
      ValueListenableBuilder<bool>(
        valueListenable: showFrameStats,
        builder: (context, on, _) {
          if (!on) return const SizedBox.shrink();
          return Positioned(
            left: 6,
            top: 6 + MediaQuery.paddingOf(context).top,
            child: IgnorePointer(
              child: Material(
                type: MaterialType.transparency,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  color: const Color(0xCC000000),
                  child: Text(
                    _text,
                    style: const TextStyle(color: Colors.white, fontSize: 11),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    ]);
  }
}
