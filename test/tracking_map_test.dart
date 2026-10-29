/* Guards for the map markers: each role's icon has to be on the map and named
 * in the key under it, on a phone narrow enough to wrap the legend. */

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:aqua/icons.dart';
import 'package:aqua/tracking_map.dart';

const _station = LatLng(14.844, 120.811);
const _dest = LatLng(14.852, 120.820);
const _rider = LatLng(14.848, 120.815);

Widget _host(Widget child) => MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

void main() {
  testWidgets('the customer map shows store, door and rider with a key',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await tester.pumpWidget(
        _host(const DeliveryTrackMap(station: _station, dest: _dest, rider: _rider)));
    await tester.pump();

    // One icon tile per marker: shop, home, truck — no bare dots or pins.
    expect(find.byType(Ic), findsNWidgets(3 + 3), // 3 markers + 3 legend keys
        reason: 'every marker and its key are drawn as icon tiles');
    expect(find.text('Station'), findsOneWidget);
    expect(find.text('Drop-off'), findsOneWidget);
    expect(find.text('Rider'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the rider map keys the station, the stops and the rider',
      (tester) async {
    await tester.pumpWidget(_host(RouteStopMap(
      station: _station,
      stops: const [RouteStop(_dest, 1, focused: true)],
      me: _rider,
    )));
    await tester.pump();

    expect(find.text('Station'), findsOneWidget);
    expect(find.text('Customer stops'), findsOneWidget);
    expect(find.text('You'), findsOneWidget);
    // The numbered stop badge is still the pin the route list refers to.
    expect(find.text('1'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the legend can be switched off where a map is bare',
      (tester) async {
    await tester.pumpWidget(_host(const DeliveryTrackMap(
        station: _station, dest: _dest, legend: false)));
    await tester.pump();

    expect(find.text('Station'), findsNothing);
    expect(find.byType(MapLegend), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
