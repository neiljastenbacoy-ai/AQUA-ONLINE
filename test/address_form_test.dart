/* The address form is the one place a wrong value strands a rider at the wrong
 * gate, so the rules it enforces are pinned here:
 *
 *  - the map pin never writes into the address fields; the customer types them
 *  - city / municipality is required, not optional
 *
 * The form is a private sheet, so these drive it the way a customer does:
 * through the Add button on the customer profile screen.
 */

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aqua/customer.dart' as cus;
import 'package:aqua/models.dart';
import 'package:aqua/state.dart';

AppState _customer() {
  final s = AppState()
    ..noSave = true
    ..session = true
    ..role = 'customer'
    ..screen = 'profile'
    ..stack = ['profile'];
  s.user = Account(
      name: 'Maria Santos', phone: '+63 917 111 2222', email: 'maria@example.com');
  return s;
}

Widget _host(AppState s) => MaterialApp(
      home: AnimatedBuilder(
        animation: s,
        builder: (context, _) => Scaffold(
          body: cus.profileView(context, s).content,
        ),
      ),
    );

/// Opens the New Address sheet from the profile screen.
Future<void> _openForm(WidgetTester tester, AppState s) async {
  await tester.pumpWidget(_host(s));
  await tester.pump();
  final add = find.text('Add');
  await tester.ensureVisible(add);
  await tester.tap(add, warnIfMissed: false);
  await tester.pumpAndSettle();
}

Future<void> _fill(WidgetTester tester, String label, String value) async {
  final field = find.ancestor(
    of: find.text(label),
    matching: find.byType(Column),
  );
  expect(field, findsWidgets, reason: 'the form must show a "$label" field');
  await tester.enterText(
    find.descendant(of: field.first, matching: find.byType(TextField)).first,
    value,
  );
  await tester.pump();
}

void main() {
  testWidgets('the city field is required, not optional', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final s = _customer();
    await _openForm(tester, s);

    expect(find.text('City / municipality'), findsOneWidget);
    expect(find.text('City / municipality (optional)'), findsNothing,
        reason: 'the city is part of a deliverable address');
  });

  testWidgets('saving without a city is refused', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final s = _customer();
    await _openForm(tester, s);

    await _fill(tester, 'House no. / street / building', 'Purok 1');
    await _fill(tester, 'Barangay', 'Villanueva');

    final save = find.text('Save Address');
    await tester.ensureVisible(save);
    await tester.tap(save, warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(s.addresses, isEmpty, reason: 'an address with no city must not save');
    expect(
      find.textContaining('city or municipality'),
      findsOneWidget,
      reason: 'the customer must be told which field is missing',
    );
  });

  testWidgets('a complete address saves what was typed', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final s = _customer();
    await _openForm(tester, s);

    await _fill(tester, 'House no. / street / building', 'Purok 1');
    await _fill(tester, 'Barangay', 'Villanueva');
    await _fill(tester, 'City / municipality', 'Villanueva');

    final save = find.text('Save Address');
    await tester.ensureVisible(save);
    await tester.tap(save, warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(s.addresses.length, 1);
    final a = s.addresses.first;
    expect(a.street, 'Purok 1');
    expect(a.brgy, 'Villanueva');
    expect(a.city, 'Villanueva');
    expect(a.line, 'Purok 1, Villanueva, Villanueva');
    expect(a.hasPin, isFalse, reason: 'no pin was set, so none may be invented');
  });
}
