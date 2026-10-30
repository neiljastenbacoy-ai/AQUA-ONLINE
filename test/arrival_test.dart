/* The customer is told when the rider reaches the door — by the rider's GPS
 * crossing the pin's radius, or by the rider's own "I've Arrived" tap — and
 * notes another phone wrote into the customer's inbox ring this phone. */

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aqua/models.dart';
import 'package:aqua/online.dart';
import 'package:aqua/rider.dart' as rider;
import 'package:aqua/state.dart';

// Villanueva, Misamis Oriental — any fixed spot works.
const double pinLat = 8.5853, pinLng = 124.7745;

void main() {
  AppState riderOn({int status = 3, bool pin = true}) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final s = AppState()..noSave = true;
    s.role = 'rider';
    s.riders.add(Rider(id: 'r1', name: 'Juan Dela Cruz', email: 'juan@aqua.ph'));
    s.rider = s.riders.first;
    s.riderId = 'r1';
    // The customer is on this device so the note lands in the local inbox.
    s.user = Account(name: 'Ana Reyes', phone: '', email: 'ana@aqua.ph');
    s.orders.add(Order(
      id: 'AQ-ARR-001',
      items: [OrderItem(type: 'refill', qty: 2)],
      total: 50,
      address: AddrLine(
          label: 'Home', line: 'Purok 1, Villanueva',
          lat: pin ? pinLat : null, lng: pin ? pinLng : null),
      createdAt: now,
      stamps: [now, now, now, now],
      owner: 'ana@aqua.ph',
      cust: Customer(name: 'Ana Reyes', phone: '+63 915 222 3344'),
      riderId: 'r1',
      status: status,
    ));
    s.detailId = 'AQ-ARR-001';
    return s;
  }

  int arrivedNotes(AppState s) =>
      s.notifs.where((n) => n.title == 'Your rider has arrived').length;

  test('a GPS fix far from the pin does not tell the customer', () {
    final s = riderOn();
    s.checkArrival(pinLat + 0.01, pinLng); // ~1.1 km away
    expect(s.orders.first.arrivedAt, isNull);
    expect(arrivedNotes(s), 0);
  });

  test('a GPS fix at the pin tells the customer exactly once', () {
    final s = riderOn();
    s.checkArrival(pinLat + 0.0005, pinLng); // ~55 m away
    expect(s.orders.first.arrivedAt, isNotNull);
    expect(arrivedNotes(s), 1);
    // The rider keeps standing there: fixes every 3 s must not re-notify.
    s.checkArrival(pinLat, pinLng);
    s.riderArrived('AQ-ARR-001');
    expect(arrivedNotes(s), 1);
    expect(s.orders.first.status, 3, reason: 'arriving never moves the stage');
  });

  test('arrival only counts while the order is out for delivery', () {
    for (final st in [1, 2, 4]) {
      final s = riderOn(status: st);
      s.checkArrival(pinLat, pinLng);
      expect(s.riderArrived('AQ-ARR-001'), isFalse);
      expect(s.orders.first.arrivedAt, isNull, reason: 'status $st');
    }
    final s = riderOn()..orders.first.cancelled = true;
    expect(s.riderArrived('AQ-ARR-001'), isFalse);
  });

  test('another rider\'s GPS does not mark this delivery', () {
    final s = riderOn();
    s.riderId = 'r2';
    s.checkArrival(pinLat, pinLng);
    expect(s.orders.first.arrivedAt, isNull);
  });

  test('an order with no pin can still be marked by the rider tap', () {
    final s = riderOn(pin: false);
    s.checkArrival(pinLat, pinLng);
    expect(s.orders.first.arrivedAt, isNull);
    expect(s.riderArrived('AQ-ARR-001'), isTrue);
    expect(arrivedNotes(s), 1);
  });

  test('arrivedAt survives the cloud round trip and stays out of old orders', () {
    final s = riderOn();
    expect(s.orders.first.toJson().containsKey('arrivedAt'), isFalse,
        reason: 'existing orders must not all be rewritten with a null key');
    s.riderArrived('AQ-ARR-001');
    final back = Order.fromJson(s.orders.first.toJson());
    expect(back.arrivedAt, s.orders.first.arrivedAt);
  });

  test('only fresh notes from another phone ring this one', () {
    final now = DateTime.now().millisecondsSinceEpoch;
    Notif n(String id, {int ago = 0, bool read = false}) =>
        Notif(id: id, title: id, ts: now - ago, read: read);
    final local = [n('mine')];
    final remote = [
      n('mine'), // made on this phone — already rang
      n('arrived'), // the rider's phone wrote it just now
      n('old', ago: 60 * 60 * 1000), // an hour ago — no replay
      n('seen', read: true), // already read elsewhere
    ];
    expect(cloudOnlyNotifs(remote, local, now: now).map((x) => x.id), ['arrived']);
  });

  test('admin/rider inboxes use the same guard, riders only their own stops', () {
    final now = DateTime.now().millisecondsSinceEpoch;
    Notif n(String id, {String? rid, int ago = 0, bool read = false}) =>
        Notif(id: id, title: id, ts: now - ago, read: read, rid: rid);
    // The world/main path applies cloudOnlyNotifs then keeps only this rider's
    // assignments, so a note for another rider never rings this phone and an
    // old or already-seen note is not replayed.
    final remote = [
      n('r-mine', rid: 'R1'),
      n('r-other', rid: 'R2'), // belongs to another rider
      n('r-old', rid: 'R1', ago: 60 * 60 * 1000), // an hour ago — no replay
      n('r-seen', rid: 'R1', read: true), // already read elsewhere
    ];
    final fresh = cloudOnlyNotifs(remote, const <Notif>[], now: now)
        .where((x) => x.rid == 'R1')
        .map((x) => x.id)
        .toList();
    expect(fresh, ['r-mine']);
  });

  Widget wrap(AppState s) => MaterialApp(
        home: AnimatedBuilder(
          animation: s,
          builder: (context, _) {
            final sv = rider.rdetailView(context, s);
            return Scaffold(body: Column(children: [Expanded(child: sv.content)]));
          },
        ),
      );

  testWidgets('the rider taps Notify Customer and sees the customer was told',
      (tester) async {
    final s = riderOn(pin: false);
    await tester.pumpWidget(wrap(s));
    await tester.pumpAndSettle();

    const send = 'Notify Customer: I\'ve Arrived';
    await tester.ensureVisible(find.text(send));
    await tester.tap(find.text(send));
    await tester.pumpAndSettle();

    expect(s.orders.first.arrivedAt, isNotNull);
    expect(arrivedNotes(s), 1);
    expect(find.text(send), findsNothing);
    expect(find.textContaining('Customer notified you arrived'), findsOneWidget);

    // The customer has not come out: one more ring, then the call button.
    await tester.ensureVisible(find.text('Notify Again'));
    await tester.tap(find.text('Notify Again'));
    await tester.pumpAndSettle();
    expect(s.notifs.where((n) => n.title == 'Your rider is still waiting').length, 1);
    expect(find.text('Notify Again'), findsNothing);
    expect(find.text('Call Customer'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('Notify Again rings once and only after arriving', () {
    final s = riderOn();
    expect(s.riderNudge('AQ-ARR-001'), isFalse, reason: 'not arrived yet');
    s.riderArrived('AQ-ARR-001');
    expect(s.riderNudge('AQ-ARR-001'), isTrue);
    expect(s.riderNudge('AQ-ARR-001'), isFalse);
    expect(s.notifs.where((n) => n.title == 'Your rider is still waiting').length, 1);
  });

  testWidgets('the arrival button sits above the order items', (tester) async {
    final s = riderOn();
    await tester.pumpWidget(wrap(s));
    await tester.pumpAndSettle();
    final btn = tester.getTopLeft(find.text('Notify Customer: I\'ve Arrived'));
    final items = tester.getTopLeft(find.text('Order Items'));
    expect(btn.dy, lessThan(items.dy));
  });

  testWidgets('no arrival button before the order is on the road', (tester) async {
    await tester.pumpWidget(wrap(riderOn(status: 2)));
    await tester.pumpAndSettle();
    expect(find.textContaining('I\'ve Arrived'), findsNothing);
  });
}
