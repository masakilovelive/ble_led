import 'package:septronics/app/product_ui_state.dart';
import 'package:septronics/main.dart';
import 'package:septronics/screens/stock_select_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('app boots', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: BleLedApp()));
    await tester.pump(const Duration(seconds: 4));

    expect(find.byType(BleLedApp), findsOneWidget);
  });

  test('demo mode is disabled by default', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(demoModeProvider), isFalse);
  });

  testWidgets('demo mode opens virtual Stock A and B controls',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          demoModeProvider.overrideWith((ref) => true),
        ],
        child: const MaterialApp(home: StockSelectScreen()),
      ),
    );
    await tester.pump();

    expect(find.text('DEMO MODE'), findsOneWidget);
    expect(find.text('STOCK SELECT'), findsOneWidget);
  });
}
