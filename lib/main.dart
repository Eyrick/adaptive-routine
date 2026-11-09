import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/frame_stats.dart';
import 'data/block_repository.dart';
import 'data/holiday_repository.dart';
import 'data/prefs_repositories.dart';
import 'data/rule_repository.dart';
import 'domain/fixed_rule.dart';
import 'domain/holiday.dart';
import 'domain/models.dart';
import 'features/calendar/dual_calendar_view.dart';
import 'features/chat/chat_panel.dart';

/// Repositórios e dados já carregados, para o app abrir sem esperar o disco.
class _Storage {
  _Storage({
    required this.blocks,
    required this.savedBlocks,
    required this.rules,
    required this.savedRules,
    required this.holidays,
    required this.savedHolidays,
  });
  final BlockRepository blocks;
  final List<TimeBlock>? savedBlocks;
  final RuleRepository rules;
  final List<FixedRule>? savedRules;
  final HolidayRepository holidays;
  final Map<String, Holiday>? savedHolidays;

  factory _Storage.memory() => _Storage(
        blocks: MemoryBlockRepository(),
        savedBlocks: null,
        rules: MemoryRuleRepository(),
        savedRules: null,
        holidays: MemoryHolidayRepository(),
        savedHolidays: null,
      );
}

Future<_Storage> _openStorage() async {
  // Navegador (app web instalado no celular): não há arquivos, usa o
  // armazenamento do próprio navegador, com o mesmo formato de dados.
  if (kIsWeb) {
    try {
      final prefs = await SharedPreferences.getInstance();
      final blocks = PrefsBlockRepository(prefs);
      final rules = PrefsRuleRepository(prefs);
      final holidays = PrefsHolidayRepository(prefs);
      return _Storage(
        blocks: blocks,
        savedBlocks: await blocks.load(),
        rules: rules,
        savedRules: await rules.load(),
        holidays: holidays,
        savedHolidays: await holidays.load(),
      );
    } catch (e) {
      debugPrint('Sem armazenamento no navegador, usando memória: $e');
      return _Storage.memory();
    }
  }

  // Windows, Android e demais: arquivos JSON no diretório do app.
  BlockRepository blocks;
  List<TimeBlock>? savedBlocks;
  try {
    final file = await FileBlockRepository.open();
    debugPrint('Agenda salva em: ${file.path}');
    savedBlocks = await file.load();
    blocks = file;
  } catch (e) {
    debugPrint('Sem armazenamento local, usando memória: $e');
    blocks = MemoryBlockRepository();
  }
  RuleRepository rules;
  List<FixedRule>? savedRules;
  try {
    final file = await FileRuleRepository.open();
    debugPrint('Rotina fixa salva em: ${file.path}');
    savedRules = await file.load();
    rules = file;
  } catch (e) {
    debugPrint('Sem armazenamento para a rotina fixa, usando memória: $e');
    rules = MemoryRuleRepository();
  }
  HolidayRepository holidays;
  Map<String, Holiday>? savedHolidays;
  try {
    final file = await FileHolidayRepository.open();
    debugPrint('Feriados salvos em: ${file.path}');
    savedHolidays = await file.load();
    holidays = file;
  } catch (e) {
    debugPrint('Sem armazenamento para os feriados, usando memória: $e');
    holidays = MemoryHolidayRepository();
  }
  return _Storage(
    blocks: blocks,
    savedBlocks: savedBlocks,
    rules: rules,
    savedRules: savedRules,
    holidays: holidays,
    savedHolidays: savedHolidays,
  );
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final st = await _openStorage();
  runApp(ProviderScope(
    overrides: [
      blockRepositoryProvider.overrideWithValue(st.blocks),
      initialBlocksProvider.overrideWithValue(st.savedBlocks),
      ruleRepositoryProvider.overrideWithValue(st.rules),
      initialRulesProvider.overrideWithValue(st.savedRules),
      holidayRepositoryProvider.overrideWithValue(st.holidays),
      initialHolidaysProvider.overrideWithValue(st.savedHolidays),
    ],
    child: const AdaptiveRoutineApp(),
  ));
}

class AdaptiveRoutineApp extends StatelessWidget {
  const AdaptiveRoutineApp({super.key});

  ThemeData _theme(Brightness b) => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF5B5BD6), brightness: b),
        visualDensity: VisualDensity.standard,
      );

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Adaptive Routine',
        debugShowCheckedModeBanner: false,
        theme: _theme(Brightness.light),
        darkTheme: _theme(Brightness.dark),
        themeMode: ThemeMode.system,
        locale: const Locale('pt', 'BR'),
        supportedLocales: const [Locale('pt', 'BR')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        builder: (context, child) => FrameStatsOverlay(child: child ?? const SizedBox.shrink()),
        home: const HomePage(),
      );
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      if (c.maxWidth >= 900) {
        return Scaffold(
          body: Row(children: [
            const Expanded(child: DualCalendarView()),
            const VerticalDivider(width: 1),
            const SizedBox(width: 360, child: ChatPanel()),
          ]),
        );
      }
      // Celular (ou janela estreita): calendário de 3 dias + chat compacto embaixo.
      return const Scaffold(
        body: SafeArea(
          bottom: false,
          child: Column(children: [
            Expanded(child: DualCalendarView()),
            ChatDock(),
          ]),
        ),
      );
    });
  }
}
