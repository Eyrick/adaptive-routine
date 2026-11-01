import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/scheduling.dart';
import '../calendar/calendar_controller.dart';

class ChatPanel extends ConsumerStatefulWidget {
  const ChatPanel({super.key});
  @override
  ConsumerState<ChatPanel> createState() => _ChatPanelState();
}

class _ChatPanelState extends ConsumerState<ChatPanel> {
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();

  void _send() {
    ref.read(calendarProvider.notifier).submit(_ctrl.text);
    _ctrl.clear();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      }
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(calendarProvider);
    final cs = Theme.of(context).colorScheme;

    return SafeArea(
      child: Column(children: [
        Expanded(
          child: ListView.builder(
            controller: _scroll,
            padding: const EdgeInsets.all(16),
            itemCount: s.messages.length,
            itemBuilder: (_, i) {
              final m = s.messages[i];
              return Align(
                alignment: m.fromUser ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  constraints: const BoxConstraints(maxWidth: 300),
                  decoration: BoxDecoration(
                    color: m.fromUser ? cs.primary : cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(m.text,
                      style: TextStyle(color: m.fromUser ? cs.onPrimary : cs.onSurface)),
                ),
              );
            },
          ),
        ),
        if (s.pending != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(spacing: 8, runSpacing: 4, children: [
              if (s.pending!.stage == Stage.priority) ...[
                ActionChip(label: const Text('Sim, priorizar'), onPressed: () => ref.read(calendarProvider.notifier).submit('sim')),
                ActionChip(label: const Text('Não'), onPressed: () => ref.read(calendarProvider.notifier).submit('não')),
              ] else ...[
                for (var i = 0; i < s.pending!.suggestions.length; i++)
                  ActionChip(
                    label: Text('${dayDate(s.pending!.suggestions[i].start)} ${hhmm(s.pending!.suggestions[i].start)}'),
                    onPressed: () => ref.read(calendarProvider.notifier).resolve(i),
                  ),
                ActionChip(label: const Text('Cancelar'), onPressed: () => ref.read(calendarProvider.notifier).cancelPending()),
              ],
            ]),
          ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            controller: _ctrl,
            onSubmitted: (_) => _send(),
            decoration: InputDecoration(
              hintText: 'Fale com sua agenda…',
              filled: true,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
              suffixIcon: IconButton(icon: const Icon(Icons.arrow_upward), onPressed: _send),
            ),
          ),
        ),
      ]),
    );
  }
}
