/* The sync layer must not lose what this device just did.
 *
 * A Firestore snapshot can land between an action and its push, so these tests
 * pin the merge rule that keeps a brand-new order alive, plus the two crashes
 * and the duplicate order a fast double tap used to produce. */

import 'package:flutter_test/flutter_test.dart';

import 'package:aqua/constants.dart';
import 'package:aqua/models.dart';
import 'package:aqua/online.dart';
import 'package:aqua/state.dart';

Order makeOrder(String id, int createdAt) => Order(
      id: id,
      items: [OrderItem(type: 'refill', qty: 1)],
      total: 25,
      address: AddrLine(label: 'Home', line: 'Purok 1, Villanueva'),
      createdAt: createdAt,
      stamps: [createdAt],
      owner: 'ana@aqua.ph',
      cust: Customer(name: 'Ana Reyes', phone: '+63 915 222 3344'),
    );

void main() {
  group('orders snapshot merge', () {
    test('an order this device has not pushed yet survives', () {
      final merged = keepUnsyncedOrders(
        remote: [makeOrder('AQ-1', 100)],
        local: [makeOrder('AQ-2', 200), makeOrder('AQ-1', 100)],
        acknowledged: {'AQ-1'},
      );
      expect(merged.map((o) => o.id), ['AQ-2', 'AQ-1']);
    });

    test('an order the server has acknowledged can still be deleted there', () {
      final merged = keepUnsyncedOrders(
        remote: const [],
        local: [makeOrder('AQ-1', 100)],
        acknowledged: {'AQ-1'},
      );
      expect(merged, isEmpty);
    });

    test('the newest order stays on top', () {
      final merged = keepUnsyncedOrders(
        remote: [makeOrder('AQ-1', 100), makeOrder('AQ-3', 300)],
        local: [makeOrder('AQ-2', 200)],
        acknowledged: const {},
      );
      expect(merged.map((o) => o.id), ['AQ-3', 'AQ-2', 'AQ-1']);
    });
  });

  group('notification lists', () {
    Notif note(String id, int ts, {bool read = false}) =>
        Notif(id: id, type: 'order', title: 't$id', body: '', ts: ts, read: read);

    test('one phone pushing its own notes cannot drop another phone\'s', () {
      final merged = mergeNotifs([note('a', 100)], [note('b', 200)]);
      expect(merged.map((n) => n.id), ['b', 'a']);
    });

    test('the server copy keeps its read flag', () {
      final merged = mergeNotifs([note('a', 100, read: true)], [note('a', 100)]);
      expect(merged.length, 1);
      expect(merged.single.read, isTrue);
    });

    test('the list stays capped', () {
      final many = [for (var i = 0; i < 8; i++) note('n$i', 100 + i)];
      expect(mergeNotifs(many, many, cap: 60).length, 8);
      expect(mergeNotifs([], many, cap: 3).length, 3);
    });
  });

  test('the station cancelling reaches the customer\'s own inbox', () {
    final now = DateTime.now().millisecondsSinceEpoch;
    final s = AppState()..noSave = true;
    s.user = Account(name: 'Ana Reyes', email: 'ana@aqua.ph');
    s.role = 'admin';
    s.orders.add(Order(
      id: 'AQ-1',
      items: [OrderItem(type: 'refill', qty: 1)],
      total: 25,
      address: AddrLine(label: 'Home', line: 'Purok 1'),
      createdAt: now,
      stamps: [now],
      owner: 'ana@aqua.ph',
      cust: Customer(name: 'Ana Reyes', phone: '+63 915 222 3344'),
    ));
    s.adminCancel('AQ-1');
    expect(s.orders.single.cancelled, isTrue);
    expect(s.notifs.any((n) => n.title == 'Order cancelled'), isTrue);
  });

  test('the rider\'s phone never advances an order on the clock', () {
    final now = DateTime.now().millisecondsSinceEpoch;
    final s = AppState()
      ..noSave = true
      ..role = 'rider'
      ..session = true
      ..riderId = 'r1';
    s.riders = [Rider(id: 'r1', name: 'Juan Dela Cruz', email: 'juan@aqua.ph')];
    s.rider = s.riders.first;
    s.settings.autoDeliver = true;
    s.orders.add(Order(
      id: 'AQ-2',
      items: [OrderItem(type: 'refill', qty: 1)],
      total: 25,
      address: AddrLine(label: 'Home', line: 'Purok 1'),
      createdAt: now - 120000,
      stamps: [now - 120000],
      owner: 'ana@aqua.ph',
      cust: Customer(name: 'Ana Reyes', phone: '+63 915 222 3344'),
      riderId: 'r1',
    ));
    s.tick();
    expect(s.orders.single.status, 0);
  });

  test('a double tap on Place Order places one order', () async {
    final s = AppState()..noSave = true;
    s.user = Account(name: 'Ana Reyes', email: 'ana@aqua.ph', phone: '+63 915 222 3344');
    s.addresses = [
      Address(id: 'a1', label: 'Home', street: 'Purok 1', brgy: 'Villanueva', def: true),
    ];
    s.cart = [CartItem(type: 'refill', qty: 2)];

    final first = s.placeOrder();
    final second = s.placeOrder(); // tapped again before the first finished
    expect(await first, isNull);
    expect(await second, isNull);
    expect(s.orders.length, 1, reason: 'the cart was already spent by the first tap');
    expect(s.cart, isEmpty);
  });

  test('a new order never reuses an existing order id', () async {
    // A repeated counter once gave a fresh order the id of a delivered one, so
    // the customer's brand-new order showed "Delivered".
    final now = DateTime.now().millisecondsSinceEpoch;
    final taken = oid(now, 1);
    final s = AppState()..noSave = true;
    s.user = Account(name: 'Ana Reyes', email: 'ana@aqua.ph');
    s.addresses = [
      Address(id: 'a1', label: 'Home', street: 'Purok 1', brgy: 'Villanueva', def: true),
    ];
    s.orders.add(Order(
      id: taken,
      items: [OrderItem(type: 'refill', qty: 1)],
      total: 25,
      address: AddrLine(label: 'Home', line: 'Purok 1'),
      createdAt: now - 60000,
      stamps: [now - 60000, now - 50000, now - 40000, now - 30000, now],
      status: 4,
      owner: 'ana@aqua.ph',
      cust: Customer(name: 'Ana Reyes', phone: '+63 915 222 3344'),
    ));
    s.cart = [CartItem(type: 'refill', qty: 1)];

    expect(await s.placeOrder(), isNull);
    final fresh = s.orders.first;
    expect(fresh.id, isNot(taken));
    expect(s.orders.where((o) => o.id == fresh.id).length, 1);
    expect(fresh.status, 0);
  });

  test('an address whose row disappeared is recreated, not crashed', () {
    final s = AppState()..noSave = true;
    final a = s.saveAddress(
        id: 'gone', label: 'Home', street: 'Purok 2', brgy: 'Villanueva', def: true);
    expect(s.addresses.map((x) => x.id), contains(a.id));
    expect(s.addresses.single.street, 'Purok 2');
  });

  test('a rider whose row disappeared cannot be saved over', () {
    final s = AppState()..noSave = true;
    final err = s.saveRider(
        id: 'gone',
        name: 'Juan Dela Cruz',
        phone: '+63 917 800 1200',
        vehicle: 'Scooter',
        plate: 'abc 123',
        email: 'juan@aqua.ph',
        pass: '1234');
    expect(err, isNotNull);
    expect(s.riders, isEmpty);
  });
}
