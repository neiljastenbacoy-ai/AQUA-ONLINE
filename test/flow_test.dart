/* The whole app flow, end to end, without a phone: one customer places two
 * orders, the station accepts and dispatches one, a rider delivers it, and the
 * other is cancelled with its stock put back.
 *
 * This is the guard that was missing. Every screen was tested on its own, so a
 * broken seam between two screens — an order that could be placed but never
 * dispatched, a cancellation that refunded stock twice — would have passed.
 */

import 'package:flutter_test/flutter_test.dart';

import 'package:aqua/constants.dart';
import 'package:aqua/main.dart' show backExitsApp;
import 'package:aqua/models.dart';
import 'package:aqua/online.dart';
import 'package:aqua/state.dart';

/// A fresh state with the sync layer bound but offline: `nextSeq` needs the
/// state handle, and `active` is false until Firebase initialises.
Future<AppState> _boot() async {
  final s = AppState()..noSave = true;
  await OnlineSync.i.start(s);
  return s;
}

Future<AppState> _withCustomer() async {
  final s = await _boot();
  final err =
      await s.registerCustomer('Ana Reyes', '09152223344', 'ana@aqua.ph', 'pass1234');
  expect(err, isNull, reason: 'registering offline must still work');
  s.saveAddress(
    label: 'Home',
    street: 'Purok 1',
    brgy: 'Villanueva',
    def: true,
    pick: true,
    lat: 14.8480,
    lng: 120.8150,
  );
  return s;
}

void main() {
  test('an order runs from cart to delivered across all three roles', () async {
    final s = await _withCustomer();

    /* ---- customer ---- */
    s.cart.add(CartItem(type: 'refill', qty: 2));
    final water = s.inv['water']!.qty;
    expect(await s.placeOrder(), isNull);

    final a = s.orders.single;
    expect(a.status, 0, reason: 'new orders start pending');
    expect(a.cancelled, isFalse);
    expect(a.total, 50);
    expect(s.cart, isEmpty, reason: 'the cart is spent by the order');
    expect(s.cartOwner, 'ana@aqua.ph');
    expect(s.screen, 'confirm', reason: 'the customer sees the receipt');
    expect(s.lastOrderId, a.id);
    expect(s.inv['water']!.qty, water - 2, reason: 'stock leaves on placement');
    expect(a.riderId, isNull, reason: 'auto-assign is off by default');
    expect(s.notifs.first.title, 'Order placed');

    /* ---- station ---- */
    expect(await s.loginAdmin(ADMIN_SEED_EMAIL, ADMIN_SEED_PASS), isNull);
    expect(s.screen, 'adash');

    expect(s.adminAdvance(a, 1), '');
    expect(a.status, 1);
    expect(s.adminAdvance(a, 2), '');
    expect(a.status, 2);

    // Out for delivery with nobody to drive it: the station is asked for a
    // rider rather than the order silently jumping to the road.
    s.station.autoAssign = false;
    expect(s.adminAdvance(a, 3), 'need');
    expect(a.status, 2, reason: 'refused, not half-advanced');

    s.riders.add(Rider(
      id: 'r1',
      name: 'Juan Dela Cruz',
      email: 'juan@aqua.ph',
      phone: '09351234567',
      pass: 'rider1234',
    ));
    s.station.autoAssign = true;
    expect(s.adminAdvance(a, 3), '');
    expect(a.status, 3);
    expect(a.riderId, 'r1', reason: 'dispatch assigns the rider');
    expect(s.rnotifs.any((n) => n.rid == 'r1' && n.orderId == a.id), isTrue);

    /* ---- rider ---- */
    expect(await s.loginRider('juan@aqua.ph', 'wrong-pass'), isNotNull);
    expect(s.role, 'admin', reason: 'a bad password changes nothing');
    expect(s.session, isTrue);
    expect(await s.loginRider('juan@aqua.ph', 'rider1234'), isNull);
    expect(s.screen, 'rdash');
    expect(s.rorders().map((o) => o.id), [a.id]);

    s.riderDeliver(a.id);
    expect(a.status, 4);
    expect(s.notifs.any((n) => n.title == 'Delivered' && n.orderId == a.id),
        isTrue,
        reason: 'the customer is told it arrived');
    expect(s.anotifs.any((n) => n.title == 'Order delivered'), isTrue);
    expect(s.rnotifs.any((n) => n.title == 'Delivery completed'), isTrue);
    expect(s.doneAt(a), isNotNull);

    // The station's next step stops here: the order detail dock only offers
    // stages while the order is still running.
    expect(statusState(a), 4);
  });

  test('a cancelled order puts the stock back exactly once', () async {
    final s = await _withCustomer();
    s.cart.add(CartItem(type: 'refill', qty: 3));
    final water = s.inv['water']!.qty;
    expect(await s.placeOrder(), isNull);

    final o = s.orders.single;
    expect(s.inv['water']!.qty, water - 3);

    s.cancelOrder(o.id);
    expect(o.cancelled, isTrue);
    expect(s.inv['water']!.qty, water, reason: 'gallons return to the shelf');

    // Pressing cancel twice must not invent water.
    s.cancelOrder(o.id);
    expect(s.inv['water']!.qty, water);
    expect(statusState(o), 5);
  });

  test('an order cannot be cancelled once it is on the road', () async {
    final s = await _withCustomer();
    s.cart.add(CartItem(type: 'buy', qty: 1));
    await s.placeOrder();

    final o = s.orders.single;
    o.status = 2;
    s.cancelOrder(o.id);
    expect(o.cancelled, isFalse, reason: 'too late — already being prepared');
  });

  test('an order without an address is refused before it exists', () async {
    final s = await _boot();
    await s.registerCustomer('Ana Reyes', '09152223344', 'ana@aqua.ph', 'pass1234');
    s.cart.add(CartItem(type: 'refill', qty: 1));

    final err = await s.placeOrder();
    expect(err, isNotNull);
    expect(err, contains('address'));
    expect(s.orders, isEmpty, reason: 'nothing half-created');
    expect(s.cart, hasLength(1), reason: 'the cart survives so they can fix it');
  });

  test('an empty cart sends the customer back to the cart', () async {
    final s = await _withCustomer();
    expect(await s.placeOrder(), isNull);
    expect(s.orders, isEmpty);
    expect(s.screen, 'cart');
  });

  test('back from a side-menu page returns to that role home', () async {
    final s = await _boot();
    await s.loginAdmin(ADMIN_SEED_EMAIL, ADMIN_SEED_PASS);

    // A side-menu root replaces the stack, so back has nowhere to go but the
    // role's home — for the station that is the dashboard, never the customer
    // home the stack used to default to.
    s.goScreen('aprod', side: true);
    expect(s.screen, 'aprod');
    expect(s.stack, ['aprod']);

    s.back();
    expect(s.stack, ['adash']);
    expect(s.screen, 'adash');

    // A pushed page keeps its parent, so the customer can back out of the
    // order form into the home screen it came from.
    s.role = 'customer';
    s.goScreen('order', side: true);
    expect(s.stack, ['home', 'order']);
    s.back();
    expect(s.screen, 'home');
  });

  test('back leaves the app only from the entry screen', () {
    // Sign-in has nothing behind it, so back closes the app.
    expect(backExitsApp('auth', 1, 'home'), isTrue);

    // The role's own home is the last screen: back there exits.
    expect(backExitsApp('home', 1, 'home'), isTrue);
    expect(backExitsApp('adash', 1, 'adash'), isTrue);
    expect(backExitsApp('rdash', 1, 'rdash'), isTrue);

    // A pushed page always has somewhere to go back to.
    expect(backExitsApp('notifs', 2, 'home'), isFalse);
    expect(backExitsApp('rdetail', 2, 'rdash'), isFalse);
    expect(backExitsApp('aprod', 1, 'adash'), isFalse);
  });

  test('a cart belongs to the account that filled it', () async {
    final s = await _withCustomer();
    s.cart.add(CartItem(type: 'refill', qty: 4));
    s.draft.addressId = s.addresses.single.id;

    // Signing out keeps it: the same account comes back to its own basket.
    s.adoptCart('ana@aqua.ph');
    expect(s.cart, hasLength(1));

    // A different account on the same phone starts clean.
    s.adoptCart('ben@aqua.ph');
    expect(s.cart, isEmpty);
    expect(s.draft.addressId, isNull);
    expect(s.cartOwner, 'ben@aqua.ph');
  });
}
