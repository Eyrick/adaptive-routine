import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'notify_service.dart';

/// Bloco "Notificações neste aparelho", mostrado na tela de conta.
class NotifySection extends ConsumerWidget {
  const NotifySection({super.key});

  String _explain(PushStatus s) => switch (s) {
        PushStatus.notConfigured =>
          'As notificações não foram configuradas neste app (falta a chave VAPID_PUBLIC_KEY). '
              'Veja docs/NOTIFICATIONS.md.',
        PushStatus.unsupported => 'Este aparelho ou navegador não suporta notificações do app web.',
        PushStatus.needsInstall =>
          'No iPhone, as notificações só funcionam no app instalado na Tela de Início. '
              'Toque em Compartilhar, depois em "Adicionar à Tela de Início", e abra o app '
              'pelo ícone novo.',
        PushStatus.off =>
          'Receba um aviso ${NotifyService.leadMinutes} minutos antes de cada compromisso e um '
              'resumo da rotina de amanhã às 21h.',
        PushStatus.denied =>
          'A permissão foi negada. No iPhone: Ajustes, Notificações, Rotina, e permita. '
              'Depois toque em "Verificar de novo".',
        PushStatus.on => 'Ativadas neste aparelho.',
        PushStatus.working => 'Aguarde…',
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = ref.watch(notifyProvider);
    final ctl = ref.read(notifyProvider.notifier);
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    final actions = <Widget>[
      if (n.status == PushStatus.off)
        FilledButton.icon(
          onPressed: ctl.enable,
          icon: const Icon(Icons.notifications_active_outlined),
          label: const Text('Ativar notificações'),
        ),
      if (n.status == PushStatus.denied || n.status == PushStatus.needsInstall)
        OutlinedButton(onPressed: ctl.refresh, child: const Text('Verificar de novo')),
      if (n.status == PushStatus.on) ...[
        FilledButton.tonalIcon(
          onPressed: ctl.sendTest,
          icon: const Icon(Icons.send_outlined),
          label: const Text('Enviar teste'),
        ),
        OutlinedButton(onPressed: ctl.disable, child: const Text('Desativar')),
      ],
    ];

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Notificações neste aparelho', style: text.titleSmall),
      const SizedBox(height: 6),
      Text(_explain(n.status), style: text.bodyMedium),
      if (n.message != null && n.status != PushStatus.notConfigured) ...[
        const SizedBox(height: 6),
        Text(n.message!, style: text.bodySmall?.copyWith(color: cs.primary)),
      ],
      if (actions.isNotEmpty) ...[
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: actions),
      ],
    ]);
  }
}
