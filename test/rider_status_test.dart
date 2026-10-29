/* The rider drives the order status from the delivery screen.
 *
 * The customer's Track page reads that status, so these tests check both the
 * state transition and that the control is actually reachable in the UI. */

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aqua/models.dart';
import 'package:aqua/rider.dart' as rider;
import 'package:aqua/state.dart';

void main() {
  AppState seededState({int status = 2}) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final state = AppState()..noSave = true;
    state.riders.add(Rider(id: 'r1', name: 'Juan Dela Cruz', email: 'juan@aqua.ph'));
    state.rider = state.riders.first;
    state.riderId = 'r1';
    state.orders.add(Order(
      id: 'AQ-TEST-001',
      items: [OrderItem(type: 'refill', qty: 2)],
      total: 50,
      address: AddrLine(label: 'Home', line: 'Purok 1, Villanueva'),
      createdAt: now,
      stamps: [now, now, now],
      owner: 'other',
      cust: Customer(name: 'Ana Reyes', phone: '+63 915 222 3344'),
      riderId: 'r1',
      status: status,
    ));
    state.detailId = 'AQ-TEST-001';
    return state;
  }

  Widget wrap(AppState state) => MaterialApp(
        home: AnimatedBuilder(
          animation: state,
          builder: (context, _) {
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

  test('the rider status control only moves an order forward', () {
    final s = seededState(status: 2);
    final o = s.orders.first;

    s.riderSetStatus('AQ-TEST-001', 2); // same stage — ignored
    expect(o.status, 2);
    s.riderSetStatus('AQ-TEST-001', 1); // backwards — ignored
    expect(o.status, 2);
    s.riderSetStatus('AQ-TEST-001', 5); // past delivered — ignored
    expect(o.status, 2);

    s.riderSetStatus('AQ-TEST-001', 3);
    expect(o.status, 3);
    expect(o.byRider, isTrue, reason: 'a rider move stops the demo auto-progress');
    s.riderSetStatus('AQ-TEST-001', 4);
    expect(o.status, 4);
  });

  test('a cancelled order cannot be moved by the rider', () {
    final s = seededState(status: 2);
    s.orders.first.cancelled = true;
    s.riderSetStatus('AQ-TEST-001', 3);
    expect(s.orders.first.status, 2);
  });

  test('every stage leaves the customer exactly one note', () {
    final s = seededState(status: 0);
    final o = s.orders.first;
    // The customer is signed in on this device, so their inbox is local.
    s.user = Account(name: 'Ana Reyes', phone: '', email: 'ana@aqua.ph');
    o.owner = 'ana@aqua.ph';

    for (final n in [1, 2, 3, 4]) {
      s.riderSetStatus(o.id, n);
    }

    final notes = s.notifs.where((x) => x.orderId == o.id).map((x) => x.title).toList();
    expect(o.status, 4);
    expect(notes, [
      'Delivered',
      'Out for delivery',
      'Preparing your water',
      'Order confirmed',
    ]);
  });

  test('the rider phone does not write into its own customer inbox', () {
    // The order belongs to another email, so the note has to travel to that
    // account's document instead of landing in this device's customer list.
    final s = seededState(status: 0);
    s.riderSetStatus('AQ-TEST-001', 1);
    s.riderSetStatus('AQ-TEST-001', 2);
    expect(s.orders.first.status, 2);
    expect(s.notifs, isEmpty);
  });

  test('the demo clock never marks a rider order out for delivery', () {
    final s = seededState(status: 2);
    s.session = true;
    s.settings.autoDeliver = true;
    final old = DateTime.now().millisecondsSinceEpoch - 10 * 60 * 1000;
    final o = s.orders.first;
    o.createdAt = old;
    o.owner = ''; // orders placed on this device, not synced in from another one
    o.stamps = [old, old, old];

    s.tick();

    // A rider has the order, so only the rider may say it left the station.
    expect(o.status, 2);
  });

  test('the demo clock never walks an order to delivered', () {
    // The reported bug: place an order with demo mode on and the status read
    // Delivered a minute later with nobody riding anywhere. The clock may only
    // confirm and prepare; the road and the door belong to a person.
    final s = seededState(status: 0);
    s.session = true;
    s.settings.autoDeliver = true;
    final old = DateTime.now().millisecondsSinceEpoch - 10 * 60 * 1000;
    final o = s.orders.first;
    o.owner = '';
    o.stamps = [old];

    for (var i = 0; i < 6; i++) {
      s.tick();
      // Age every stamp so each pass is "due" if the clock allowed it.
      o.stamps = [for (final _ in o.stamps) old];
    }

    expect(o.status, 2);
    expect(o.stamps.length, 3);
    expect(s.notifs.any((n) => n.title == 'Delivered'), isFalse);
    expect(s.notifs.any((n) => n.title == 'Out for delivery'), isFalse);
  });

  test('without a rider the demo clock still confirms orders', () {
    final s = seededState(status: 0);
    s.session = true;
    s.settings.autoDeliver = true;
    s.station.autoAssign = false;
    final old = DateTime.now().millisecondsSinceEpoch - 10 * 60 * 1000;
    final o = s.orders.first;
    o.riderId = null;
    o.createdAt = old;
    o.owner = '';
    o.stamps = [old];

    s.tick();

    expect(o.status, 1);
  });

  testWidgets('the header badge names the real stage', (tester) async {
    await tester.pumpWidget(wrap(seededState(status: 3)));
    await tester.pumpAndSettle();
    // Not the list's "In Progress" grouping — the stage the customer sees.
    expect(find.text('Out for Delivery'), findsOneWidget);
    expect(find.text('Pending'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the delivery screen shows the stages and the next step',
      (tester) async {
    await tester.pumpWidget(wrap(seededState()));
    await tester.pumpAndSettle();

    expect(find.text('Delivery Status'), findsOneWidget);
    for (final stage in ['Confirmed', 'Out for delivery', 'Delivered']) {
      expect(find.text(stage), findsOneWidget);
    }
    // The badge names the stage too, so "Preparing" shows twice.
    expect(find.text('Preparing'), findsNWidgets(2));
    // One action, in the dock, in the admin's words; the card stays a record.
    expect(find.text('Send Out for Delivery'), findsOneWidget);
    expect(find.text('Mark as Delivered'), findsNothing);
    expect(find.text('Confirm Order'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the stage buttons advance the order the admin way',
      (tester) async {
    final state = seededState(status: 1);
    await tester.pumpWidget(wrap(state));
    await tester.pumpAndSettle();

    expect(find.text('Start Preparing'), findsOneWidget);
    expect(find.text('Send Out for Delivery'), findsNothing);

    await tester.tap(find.text('Start Preparing'));
    await tester.pumpAndSettle();
    expect(state.orders.first.status, 2);

    await tester.tap(find.text('Send Out for Delivery'));
    await tester.pumpAndSettle();
    expect(state.orders.first.status, 3);
    expect(find.text('Mark as Delivered'), findsOneWidget);
    expect(find.text('Send Out for Delivery'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
