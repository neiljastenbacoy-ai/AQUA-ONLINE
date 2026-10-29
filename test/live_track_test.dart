/* The customer's live map shows the rider's real GPS or nothing at all.
 *
 * It used to fall back to a simulated marker derived from the order's status
 * stamps, which drew a rider gliding down the road even when nobody had left
 * the station. These tests pin the honest states in place. */

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:aqua/customer.dart' as cus;
import 'package:aqua/models.dart';
import 'package:aqua/state.dart';
import 'package:aqua/tracking_map.dart';

void main() {
  AppState trackState({String? riderId, int status = 3}) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final state = AppState()..noSave = true;
    state.user = Account(name: 'Ana Reyes', phone: '0915', email: 'ana@aqua.ph');
    state.session = true;
    state.orders.add(Order(
      id: 'AQ-TRACK-001',
      items: [OrderItem(type: 'refill', qty: 2)],
      total: 50,
      address: AddrLine(label: 'Home', line: 'Purok 9, Dayawan', lat: 8.6080, lng: 124.8240),
      createdAt: now,
      // Placed → confirmed → preparing → out for delivery: the old simulation
      // interpolated a position out of exactly these stamps.
      stamps: [now, now + 1000, now + 2000, now + 3000],
      owner: 'ana@aqua.ph',
      cust: Customer(name: 'Ana Reyes', phone: '0915'),
      riderId: riderId,
      status: status,
    ));
    state.trackId = 'AQ-TRACK-001';
    return state;
  }

  Widget wrap(AppState state) => MaterialApp(
        home: Scaffold(
          body: Builder(builder: (context) => cus.trackView(context, state).content),
        ),
      );

  // The map runs its own animation/tile timers, so settle on frames rather
  // than waiting for the tree to go quiet.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('a rider with no fix yet is explained, never flagged',
      (tester) async {
    await tester.pumpWidget(wrap(trackState(riderId: 'r1')));
    await settle(tester);

    expect(find.text('Live Tracking'), findsOneWidget);
    // The card no longer shouts about a missing or late fix.
    expect(find.text('WAITING'), findsNothing);
    expect(find.text('SIGNAL LOST'), findsNothing);
    expect(find.text('ESTIMATED'), findsNothing);
    expect(find.text('LIVE GPS'), findsNothing);
    // Firebase is not booted in tests, so the card explains the real reason:
    // there is no live connection feeding positions.
    expect(find.textContaining('Live tracking needs an internet connection'),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('without a rider the card says the station is matching one',
      (tester) async {
    await tester.pumpWidget(wrap(trackState()));
    await settle(tester);

    expect(find.text('The station is matching a rider to this order.'),
        findsOneWidget);
    expect(find.text('NO RIDER YET'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an assigned rider is on the map before the water is out',
      (tester) async {
    // Status 1 (confirmed) used to hide the map until "out for delivery", so
    // the customer had nothing to watch while the rider was already on shift.
    await tester.pumpWidget(wrap(trackState(riderId: 'r1', status: 1)));
    await settle(tester);

    expect(find.text('Live Tracking'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('delivering stops the live map', (tester) async {
    // Nothing is left to watch once the gallons are handed over, and a last
    // position left on the map would read as a rider still on the road.
    await tester.pumpWidget(wrap(trackState(riderId: 'r1', status: 4)));
    await settle(tester);

    expect(find.text('Live Tracking'), findsNothing);
    expect(find.byType(DeliveryTrackMap), findsNothing);
    expect(tester.takeException(), isNull);
  });

  const station = LatLng(8.6069, 124.8222);
  const dest = LatLng(8.6080, 124.8240);
  const rider = LatLng(8.6150, 124.8300);

  Widget mapWith(LatLng? rider) => MaterialApp(
        home: Scaffold(
          body: DeliveryTrackMap(
            station: station,
            dest: dest,
            rider: rider,
            legend: false,
          ),
        ),
      );

  testWidgets('the route line starts at the rider, not the station',
      (tester) async {
    await tester.pumpWidget(mapWith(rider));
    await settle(tester);

    final line = tester
        .widget<PolylineLayer>(find.byType(PolylineLayer))
        .polylines
        .single;
    expect(line.points.first, rider);
    expect(line.points.last, dest);
    expect(tester.takeException(), isNull);
  });

  testWidgets('without a fix the line falls back to the station leg',
      (tester) async {
    await tester.pumpWidget(mapWith(null));
    await settle(tester);

    final line = tester
        .widget<PolylineLayer>(find.byType(PolylineLayer))
        .polylines
        .single;
    expect(line.points.first, station);
    expect(line.points.last, dest);
    expect(tester.takeException(), isNull);
  });
}
