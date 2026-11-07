import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/block_repository.dart';
import 'data/holiday_repository.dart';
import 'data/rule_repository.dart';
import 'domain/fixed_rule.dart';
import 'domain/holiday.dart';
import 'domain/models.dart';
import 'features/calendar/dual_calendar_view.dart';
import 'features/chat/chat_panel.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  BlockRepository repo;
  List<TimeBlock>? saved;
  try {
    final file = await FileBlockRepository.open();
    debugPrint('Agenda salva em: ${file.path}');
    saved = await file.load();
    repo = file;
  } catch (e) {
    debugPrint('Sem armazenamento local, usando memória: $e');
    repo = MemoryBlockRepository();
  }
  RuleRepository ruleRepo;
  List<FixedRule>? savedRules;
  try {
    final file = await FileRuleRepository.open();
    debugPrint('Rotina fixa salva em: ${file.path}');
    savedRules = await file.load();
    ruleRepo = file;
  } catch (e) {
    debugPrint('Sem armazenamento para a rotina fixa, usando memória: $e');
    ruleRepo = MemoryRuleRepository();
  }
  HolidayRepository holidayRepo;
  Map<String, Holiday>? savedHolidays;
  try {
    final file = await FileHolidayRepository.open();
    debugPrint('Feriados salvos em: ${file.path}');
    savedHolidays = await file.load();
    holidayRepo = file;
  } catch (e) {
    debugPrint('Sem armazenamento para os feriados, usando memória: $e');
    holidayRepo = MemoryHolidayRepository();
  }
  runApp(ProviderScope(
    overrides: [
      holidayRepositoryProvider.overrideWithValue(holidayRepo),
      initialHolidaysProvider.overrideWithValue(savedHolidays),
      blockRepositoryProvider.overrideWithValue(repo),
      initialBlocksProvider.overrideWithValue(saved),
      ruleRepositoryProvider.overrideWithValue(ruleRepo),
      initialRulesProvider.overrideWithValue(savedRules),
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
