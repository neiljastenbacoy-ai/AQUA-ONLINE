import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aqua/models.dart';
import 'package:aqua/rider.dart' as rider;
import 'package:aqua/state.dart';

void main() {
  AppState seededState() {
    final state = AppState()..noSave = true;
    state.riders.add(Rider(id: 'r1', name: 'Juan Dela Cruz', email: 'juan@aqua.ph'));
    state.rider = state.riders.first;
    state.riderId = 'r1';
    state.orders.add(Order(
      id: 'AQ-TEST-001',
      items: [OrderItem(type: 'refill', qty: 2)],
      total: 50,
      address: AddrLine(label: 'Home', line: 'Purok 1, Villanueva'),
      createdAt: DateTime.now().millisecondsSinceEpoch,
      stamps: [DateTime.now().millisecondsSinceEpoch],
      owner: 'other',
      cust: Customer(name: 'Ana Reyes', phone: '+63 915 222 3344'),
      riderId: 'r1',
      status: 0,
    ));
    state.detailId = 'AQ-TEST-001';
    return state;
  }

  Widget wrap(AppState state) => MaterialApp(
        home: Builder(
          builder: (context) {
            final sv = rider.rdetailView(context, state);
            return Scaffold(
              body: Column(children: [
                Expanded(child: sv.content),
                if (sv.dock != null) sv.dock!,
              ]),
            );
          },
        ),
      );

  testWidgets('assigned delivery pins the Start Delivery action in the dock', (tester) async {
    await tester.pumpWidget(wrap(seededState()));
    await tester.pumpAndSettle();
    expect(find.text('Start Delivery'), findsOneWidget);
    expect(find.text('View on Map'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('completed delivery shows no action dock', (tester) async {
    final state = seededState();
    state.orders.first
      ..status = 4
      ..stamps = const [1, 2, 3, 4, 5];
    await tester.pumpWidget(wrap(state));
    await tester.pumpAndSettle();
    expect(find.text('Start Delivery'), findsNothing);
    expect(find.text('Mark as Delivered'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
