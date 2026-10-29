import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aqua/admin.dart' as admin;
import 'package:aqua/state.dart';

void main() {
  testWidgets('admin dashboard renders its content', (tester) async {
    final state = AppState();
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) => Scaffold(body: admin.adashView(context, state).content)),
    ));
    await tester.pumpAndSettle();

    // The overview leads with money and today's counters, not all-time totals.
    expect(find.text('Sales today'), findsOneWidget);
    expect(find.text('Orders today'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('admin deliveries renders its content', (tester) async {
    final state = AppState();
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) => Scaffold(body: admin.adelivView(context, state).content)),
    ));
    await tester.pumpAndSettle();

    expect(find.text('No active deliveries'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('admin users renders its content', (tester) async {
    final state = AppState();
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) => Scaffold(body: admin.ausersView(context, state).content)),
    ));
    await tester.pumpAndSettle();

    expect(find.text('No riders yet. Add your first rider.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
