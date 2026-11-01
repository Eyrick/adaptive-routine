import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'features/calendar/dual_calendar_view.dart';
import 'features/chat/chat_panel.dart';

void main() => runApp(const ProviderScope(child: AdaptiveRoutineApp()));

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
      return Scaffold(
        appBar: AppBar(title: const Text('Minha semana')),
        endDrawer: Drawer(
          width: math.min(c.maxWidth, 420),
          child: const ChatPanel(),
        ),
        body: const DualCalendarView(),
        floatingActionButton: Builder(
          builder: (ctx) => FloatingActionButton(
            onPressed: () => Scaffold.of(ctx).openEndDrawer(),
            child: const Icon(Icons.chat_bubble_outline),
          ),
        ),
      );
    });
  }
}
