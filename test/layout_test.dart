import 'package:adaptive_routine/features/chat/chat_panel.dart';
import 'package:adaptive_routine/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

int dayHeaders() => find
    .byWidgetPredicate((w) =>
        w.key is ValueKey<String> && (w.key as ValueKey<String>).value.startsWith('day-header'))
    .evaluate()
    .length;

Future<void> openApp(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(const ProviderScope(child: AdaptiveRoutineApp()));
  await tester.pump();
}

void main() {
  testWidgets('celular: 3 dias e chat compacto embaixo', (tester) async {
    await openApp(tester, const Size(390, 844));
    expect(dayHeaders(), 3);
    expect(find.byType(ChatDock), findsOneWidget);
    expect(find.byType(ChatPanel), findsNothing);
  });

  testWidgets('desktop: semana de 7 dias e chat lateral', (tester) async {
    await openApp(tester, const Size(1400, 900));
    expect(dayHeaders(), 7);
    expect(find.byType(ChatPanel), findsOneWidget);
    expect(find.byType(ChatDock), findsNothing);
  });
}
