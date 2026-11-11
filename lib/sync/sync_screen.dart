import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/scheduling.dart';
import 'sync_service.dart';

/// Conta e sincronização: entrar ou criar conta, ver a situação, resolver
/// conflitos e sair.
class SyncScreen extends ConsumerStatefulWidget {
  const SyncScreen({super.key});

  @override
  ConsumerState<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends ConsumerState<SyncScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit({required bool create}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final err = await ref
        .read(syncProvider.notifier)
        .authenticate(_email.text.trim(), _password.text, create: create);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = err;
    });
  }

  String _label(SyncState s) => switch (s.status) {
        SyncStatus.notConfigured => 'Sincronização não configurada',
        SyncStatus.signedOut => 'Sem conta conectada',
        SyncStatus.idle =>
          s.lastSync == null ? 'Conectado' : 'Sincronizado às ${hhmm(s.lastSync!)}',
        SyncStatus.syncing => 'Sincronizando…',
        SyncStatus.offline => 'Sem conexão. Vou tentar de novo sozinho.',
        SyncStatus.conflict => 'Conflito: a agenda mudou aqui e na nuvem',
        SyncStatus.error => 'Erro: ${s.message ?? 'tente de novo'}',
      };

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(syncProvider);
    final ctl = ref.read(syncProvider.notifier);
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    final children = <Widget>[];

    if (s.status == SyncStatus.notConfigured) {
      children.add(Text(
        'Este app foi compilado sem a configuração de sincronização. '
        'Veja docs/SYNC.md para ligar.',
        style: text.bodyMedium,
      ));
    } else if (s.status == SyncStatus.signedOut) {
      children.addAll([
        Text(
          'Entre com a mesma conta em todos os aparelhos (computador, iPhone, '
          'Android) para a agenda ficar igual em todos.',
          style: text.bodyMedium,
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          decoration: const InputDecoration(labelText: 'E-mail'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _password,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'Senha (mínimo 6 caracteres)'),
          onSubmitted: (_) => _submit(create: false),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(_error!, style: TextStyle(color: cs.error)),
          ),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(
            child: FilledButton(
              onPressed: _busy ? null : () => _submit(create: false),
              child: const Text('Entrar'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: OutlinedButton(
              onPressed: _busy ? null : () => _submit(create: true),
              child: const Text('Criar conta'),
            ),
          ),
        ]),
      ]);
    } else {
      children.addAll([
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.account_circle_outlined),
          title: Text(s.email ?? 'Conta conectada'),
          subtitle: Text(_label(s)),
        ),
        if (s.status == SyncStatus.conflict) ...[
          const SizedBox(height: 8),
          Card(
            color: cs.errorContainer.withOpacity(.35),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('A agenda mudou aqui e na nuvem', style: text.titleSmall),
                const SizedBox(height: 6),
                Text(_conflictText(s), style: text.bodyMedium),
                const SizedBox(height: 12),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  FilledButton(
                    onPressed: () => ctl.resolveConflict(useRemote: true),
                    child: const Text('Usar a da nuvem'),
                  ),
                  OutlinedButton(
                    onPressed: () => ctl.resolveConflict(useRemote: false),
                    child: const Text('Manter a deste aparelho'),
                  ),
                ]),
              ]),
            ),
          ),
        ],
        const SizedBox(height: 12),
        FilledButton.tonalIcon(
          onPressed: s.status == SyncStatus.syncing ? null : () => ctl.syncNow(),
          icon: const Icon(Icons.sync),
          label: const Text('Sincronizar agora'),
        ),
        const SizedBox(height: 8),
        TextButton(onPressed: ctl.signOut, child: const Text('Sair desta conta')),
        const SizedBox(height: 8),
        Text(
          'Ao sair, a agenda continua neste aparelho, mas deixa de sincronizar.',
          style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant),
        ),
      ]);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Conta e sincronização')),
      body: ListView(padding: const EdgeInsets.all(20), children: children),
    );
  }

  String _conflictText(SyncState s) {
    final when = s.conflict?.updatedAt?.toLocal();
    final where = s.conflict?.device;
    final info = when == null
        ? 'A versão da nuvem'
        : 'A versão da nuvem é de ${dayDate(when)} ${hhmm(when)}'
            '${where == null ? '' : ' ($where)'}';
    return '$info. Escolha qual manter; a outra será substituída.';
  }
}
