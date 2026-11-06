import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/scheduling.dart';
import '../calendar/calendar_controller.dart';

/// Botões de resposta rápida da negociação em andamento (sim/não, janelas).
class PendingChips extends ConsumerWidget {
  const PendingChips({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(calendarProvider.select((s) => s.pending));
    if (p == null) return const SizedBox.shrink();
    final ctl = ref.read(calendarProvider.notifier);

    return Wrap(spacing: 8, runSpacing: 4, children: [
      if (p.stage == Stage.priority) ...[
        ActionChip(label: const Text('Sim, priorizar'), onPressed: () => ctl.submit('sim')),
        ActionChip(label: const Text('Não'), onPressed: () => ctl.submit('não')),
      ] else ...[
        for (var i = 0; i < p.suggestions.length; i++)
          ActionChip(
            label: Text('${dayDate(p.suggestions[i].start)} ${hhmm(p.suggestions[i].start)}'),
            onPressed: () => ctl.resolve(i),
          ),
        ActionChip(label: Text(p.cancelLabel ?? 'Cancelar'), onPressed: ctl.cancelPending),
      ],
    ]);
  }
}

/// Campo de texto do chat, usado no painel (desktop) e no dock (celular).
class ChatInput extends StatelessWidget {
  const ChatInput({super.key, required this.controller, required this.onSend});
  final TextEditingController controller;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onSubmitted: (_) => onSend(),
      textInputAction: TextInputAction.send,
      decoration: InputDecoration(
        hintText: 'Fale com sua agenda…',
        filled: true,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
        suffixIcon: IconButton(
          tooltip: 'Enviar',
          icon: const Icon(Icons.arrow_upward),
          onPressed: onSend,
        ),
      ),
    );
  }
}

/// Chat completo: histórico + respostas rápidas + campo. Painel lateral no
/// desktop e conteúdo da folha de histórico no celular.
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
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: PendingChips(),
          ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: ChatInput(controller: _ctrl, onSend: _send),
        ),
      ]),
    );
  }
}

/// Chat compacto para o celular: última resposta do app, botões de resposta
/// rápida e o campo de texto, sempre visíveis embaixo do calendário. Tocar na
/// resposta abre o histórico completo.
class ChatDock extends ConsumerStatefulWidget {
  const ChatDock({super.key});
  @override
  ConsumerState<ChatDock> createState() => _ChatDockState();
}

class _ChatDockState extends ConsumerState<ChatDock> {
  final _ctrl = TextEditingController();

  void _send() {
    ref.read(calendarProvider.notifier).submit(_ctrl.text);
    _ctrl.clear();
  }

  void _openHistory() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => Padding(
        // sobe junto com o teclado
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
        child: SizedBox(
          height: MediaQuery.sizeOf(ctx).height * 0.85,
          child: const ChatPanel(),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(calendarProvider);
    final cs = Theme.of(context).colorScheme;
    final reply = s.messages.where((m) => !m.fromUser).lastOrNull;

    return Material(
      color: cs.surfaceContainer,
      elevation: 3,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (reply != null)
                InkWell(
                  onTap: _openHistory,
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Expanded(
                        child: Text(
                          reply.text,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(Icons.history, size: 18, color: cs.onSurfaceVariant),
                    ]),
                  ),
                ),
              if (s.pending != null)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 4),
                  child: PendingChips(),
                ),
              const SizedBox(height: 4),
              ChatInput(controller: _ctrl, onSend: _send),
            ],
          ),
        ),
      ),
    );
  }
}
