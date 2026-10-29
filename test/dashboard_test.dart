/* Guards for the role dashboards: what each one leads with, the data scope of
 * its counters, and that the busiest state still fits a 320dp phone. */

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aqua/admin.dart' as adm;
import 'package:aqua/customer.dart' as cus;
import 'package:aqua/models.dart';
import 'package:aqua/rider.dart' as rid;
import 'package:aqua/state.dart';
import 'package:aqua/widgets.dart';

/// Noon on the day [shift] days from today — always inside "today" /
/// "yesterday" for the dashboard scopes, whatever hour the suite runs at.
int _day(int shift) {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day, 12)
      .add(Duration(days: shift))
      .millisecondsSinceEpoch;
}

Order _order(
  String id, {
  int status = 0,
  int qty = 2,
  int shift = 0,
  String? riderId,
  bool cancelled = false,
}) {
  final at = _day(shift);
  // stamps[status] is the time the order reached its current stage; doneAt()
  // reads it for delivered orders, so the list must cover the status.
  final last = status > 4 ? 4 : status;
  return Order(
    id: id,
    items: [OrderItem(type: 'refill', qty: qty)],
    total: 25.0 * qty,
    address: AddrLine(label: 'Home', line: '12 Mabini St, Malolos'),
    createdAt: at,
    stamps: [at, for (var i = 1; i <= last; i++) at],
    cust: Customer(name: 'Ana Reyes', phone: '+63 915 222 3344'),
    status: status,
    cancelled: cancelled,
    riderId: riderId,
  );
}

AppState _customer() => AppState()
  ..noSave = true
  ..session = true
  ..role = 'customer'
  ..user = Account(name: 'Maria Santos', email: 'maria@example.com');

AppState _riderState() {
  final s = AppState()
    ..noSave = true
    ..session = true
    ..role = 'rider'
    ..user = Account(name: 'Rico Cruz', email: 'rico@aqua.ph');
  s.riders.add(Rider(id: 'r1', name: 'Rico Cruz', email: 'rico@aqua.ph'));
  s.rider = s.riders.first;
  s.riderId = 'r1';
  return s;
}

AppState _adminState() {
  final s = AppState()
    ..noSave = true
    ..session = true
    ..role = 'admin'
    ..admin = Account(name: 'Station Admin', email: 'admin@aqua.ph');
  s.riders.add(Rider(
      id: 'r1', name: 'Rico Cruz', email: 'rico@aqua.ph', available: 'break'));
  return s;
}

/// Mirrors the shell: a 56dp app bar, the stage, then the dock under it.
Widget _screen(
  AppState s,
  ScreenView Function(BuildContext, AppState) view,
) =>
    MaterialApp(
      home: AnimatedBuilder(
        animation: s,
        builder: (context, _) {
          final sv = view(context, s);
          return Scaffold(
            body: Column(children: [
              const SizedBox(height: 56, width: double.infinity),
              Expanded(child: sv.content),
              if (sv.dock != null)
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [sv.dock!],
                  ),
                ),
            ]),
          );
        },
      ),
    );

void main() {
  testWidgets('customer home leads with the live order before the shop',
      (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final s = _customer()
      ..orders.addAll([
        _order('AQ-1001', status: 1),
        _order('AQ-0999', status: 4, qty: 3, shift: -3),
      ]);
    await tester.pumpWidget(_screen(s, cus.homeView));
    await tester.pump();

    // "2 × Refill Gallon" is the live banner; the older order holds 3.
    final live = tester.getRect(find.text('2 × Refill Gallon')).top;
    final shop = tester.getRect(find.text('Our Products')).top;
    final price = tester.getRect(find.text('₱25.00 / gallon')).top;
    final again = tester.getRect(find.text('Order again')).top;
    final promo = tester
        .getRect(find.text('Clean & Safe Purified Water Delivered to You'))
        .top;

    expect(live, lessThan(shop), reason: 'live order comes first');
    expect(shop, lessThan(price), reason: 'the price list follows its heading');
    expect(price, lessThan(again), reason: 'reorder sits under the products');
    expect(again, lessThan(promo), reason: 'the promo carousel comes last');
    expect(price, lessThan(640),
        reason: 'prices used to start at ~654dp, under the fold');
    expect(tester.takeException(), isNull);
  });

  testWidgets('order again refills the cart in one tap', (tester) async {
    final s = _customer()
      ..orders.add(_order('AQ-0999', status: 4, qty: 3, shift: -3));
    await tester.pumpWidget(_screen(s, cus.homeView));
    await tester.pump();

    await tester.tap(find.text('Order again'));
    await tester.pump();

    expect(s.cart.fold<int>(0, (a, c) => a + c.qty), 3);
    expect(s.screen, 'cart');
    expect(tester.takeException(), isNull);
  });

  testWidgets('rider dashboard pins the next delivery and maps the route',
      (tester) async {
    final s = _riderState()
      ..orders.addAll([
        _order('AQ-2001', status: 0, riderId: 'r1'),
        _order('AQ-2002', status: 1, qty: 3, riderId: 'r1'),
        _order('AQ-1900', status: 4, riderId: 'r1', shift: -2),
      ]);
    await tester.pumpWidget(_screen(s, rid.rdashView));
    await tester.pump();

    expect(find.text('NEXT DELIVERY'), findsOneWidget);

    // The dock is the map only. Starting a delivery belongs on the delivery
    // screen, where the rider has the address and the phone number in front
    // of them; a dashboard button started whichever order sorted first.
    expect(find.text('View Map Route'), findsOneWidget);
    expect(find.textContaining('Start '), findsNothing);
    expect(find.textContaining('Complete '), findsNothing);

    // Counters are today-only: the older completed delivery must not appear.
    var tiles = tester.widgetList<StatTile>(find.byType(StatTile)).toList();
    expect(tiles.map((t) => t.label).toList(),
        ['Assigned', 'On the way', 'Delivered', 'Earned today']);
    expect(tiles.map((t) => t.value).toList(), ['2', '0', '0', '₱0.00']);

    // The next-delivery card is the way in, and it lands on that order.
    await tester.tap(find.text('NEXT DELIVERY'));
    await tester.pump();
    expect(s.detailId, 'AQ-2001');
    expect(s.screen, 'rdetail');

    // Starting from the delivery screen moves the order into "On the way".
    s.riderStart('AQ-2001');
    await tester.pump();
    tiles = tester.widgetList<StatTile>(find.byType(StatTile)).toList();
    expect(tiles[1].value, '1', reason: 'the started delivery is on the way');

    // The map button asks for the whole route rather than a focused stop.
    expect(find.text('View Map Route'), findsOneWidget);
    s.routeId = 'AQ-2001';
    await tester.tap(find.text('View Map Route'));
    await tester.pump();
    expect(s.routeId, isNull, reason: 'all assigned stops, not one');
    expect(s.screen, 'rroute');
    expect(tester.takeException(), isNull);
  });

  testWidgets('availability can be changed from the rider header',
      (tester) async {
    final s = _riderState()..orders.add(_order('AQ-2001', riderId: 'r1'));
    await tester.pumpWidget(_screen(s, rid.rdashView));
    await tester.pump();

    await tester.tap(find.text('Break'));
    await tester.pump();

    expect(s.rider!.available, 'break');

    // With nothing on the road the dock falls back to the map.
    await tester.pumpWidget(_screen(_riderState(), rid.rdashView));
    await tester.pump();
    expect(find.text('View Map Route'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('admin overview leads with sales and today-scoped counters',
      (tester) async {
    final s = _adminState()
      ..orders.addAll([
        _order('AQ-3001', status: 0),
        _order('AQ-3002', status: 4),
        _order('AQ-2900', status: 4, qty: 3, shift: -1),
      ]);
    await tester.pumpWidget(_screen(s, adm.adashView));
    await tester.pump();

    expect(find.text('Sales today'), findsOneWidget);
    expect(tester.getRect(find.text('Sales today')).top,
        lessThan(tester.getRect(find.text('Needs attention')).top),
        reason: 'money first, then the tasks');

    final tiles = tester.widgetList<StatTile>(find.byType(StatTile)).toList();
    expect(tiles.map((t) => t.label).toList(),
        ['Orders today', 'Ongoing', 'Delivered', 'Gallons out']);
    expect(tiles.map((t) => t.value).toList(), ['2', '0', '1', '2']);

    // ₱50 today against ₱75 yesterday.
    expect(find.textContaining('-₱25.00 vs yesterday'), findsOneWidget);
    // One order waits for a rider and the only rider is on break.
    expect(find.text('No rider is available'), findsOneWidget);
    expect(find.textContaining('0 of 1 riders available'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dashboards survive a station with no data', (tester) async {
    // A fresh install: no orders, no riders, default stock. Every counter reads
    // zero and every list has to say so instead of dividing by zero.
    final admin = AppState()
      ..noSave = true
      ..session = true
      ..role = 'admin'
      ..admin = Account(name: 'Station Admin', email: 'admin@aqua.ph');
    await tester.pumpWidget(_screen(admin, adm.adashView));
    await tester.pump();

    expect(find.text('₱0.00'), findsOneWidget);
    expect(find.text('No orders yet. New orders will show up here.'),
        findsOneWidget);
    expect(find.textContaining('no riders yet'), findsOneWidget);
    expect(find.text('Needs attention'), findsNothing,
        reason: 'nothing is low and no order is waiting');
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(_screen(_riderState(), rid.rdashView));
    await tester.pump();
    expect(find.text('No deliveries assigned'), findsOneWidget);
    expect(find.text('View Map Route'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(_screen(_customer(), cus.homeView));
    await tester.pump();
    expect(find.text('Our Products'), findsOneWidget);
    expect(find.text('Order again'), findsNothing,
        reason: 'there is no finished order to repeat');
    expect(tester.takeException(), isNull);
  });

  testWidgets('dashboard shortcuts open the screens their labels promise',
      (tester) async {
    final admin = _adminState()..orders.add(_order('AQ-3001'));
    await tester.pumpWidget(_screen(admin, adm.adashView));
    await tester.pump();

    await tester.tap(find.text('Ongoing'));
    await tester.pump();
    expect(admin.screen, 'aorders');
    expect(admin.atab, 'delivery');

    final rider = _riderState()..orders.add(_order('AQ-2001', riderId: 'r1'));
    await tester.pumpWidget(_screen(rider, rid.rdashView));
    await tester.pump();

    await tester.tap(find.text('Assigned'));
    await tester.pump();
    expect(rider.screen, 'rlist');
    expect(rider.rtab, 'assigned');

    final customer = _customer()..orders.add(_order('AQ-1001'));
    await tester.pumpWidget(_screen(customer, cus.homeView));
    await tester.pump();

    await tester.tap(find.text('My Orders'));
    await tester.pump();
    expect(customer.screen, 'orders');

    await tester.tap(find.text('Track Delivery'));
    await tester.pump();
    expect(customer.screen, 'track');
    expect(customer.trackId, isNull,
        reason: 'tracking the live order is the fallback');
    expect(tester.takeException(), isNull);
  });

  testWidgets('every dashboard fits 320dp at 1.3x text when busy',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    final customer = _customer()
      ..orders.addAll([
        _order('AQ-1001', status: 2),
        _order('AQ-0999', status: 4, qty: 3, shift: -3),
      ]);

    final rider = _riderState()
      ..orders.addAll([
        _order('AQ-2001', status: 0, riderId: 'r1'),
        _order('AQ-2002', status: 3, qty: 3, riderId: 'r1'),
        _order('AQ-2003', status: 4, riderId: 'r1'),
      ]);

    final admin = _adminState()
      ..orders.addAll([
        _order('AQ-3001', status: 0),
        _order('AQ-3002', status: 3, riderId: 'r1'),
        _order('AQ-3003', status: 4),
        _order('AQ-2900', status: 4, qty: 3, shift: -1),
        _order('AQ-2800', cancelled: true, shift: -2),
      ]);
    admin.inv['containers']!.qty = 4;
    admin.inv['water']!.qty = 40;

    final screens = <String, (AppState, ScreenView Function(BuildContext, AppState))>{
      'customer': (customer, cus.homeView),
      'rider': (rider, rid.rdashView),
      'admin': (admin, adm.adashView),
    };

    for (final e in screens.entries) {
      await tester.pumpWidget(_screen(e.value.$1, e.value.$2));
      await tester.pump();
      expect(tester.takeException(), isNull, reason: '${e.key} overflowed');
    }
  });
}
