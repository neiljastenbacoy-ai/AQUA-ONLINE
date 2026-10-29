/* The account and tracking rules the flow depends on.
 *
 * These are the paths where the screens happily accept a change that the rest
 * of the app cannot follow: an email is the account key, the admin record is
 * the only copy of the station's sign-in, and a cancelled order must still be
 * viewable when the customer explicitly opens it.
 */

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aqua/constants.dart';
import 'package:aqua/customer.dart' as cus;
import 'package:aqua/models.dart';
import 'package:aqua/state.dart';

AppState _customer() {
  final s = AppState()
    ..noSave = true
    ..session = true
    ..role = 'customer';
  s.user = Account(name: 'Maria Santos', phone: '+63 917 111 2222', email: 'maria@example.com');
  return s;
}

Order _order(String id, {required bool cancelled, int status = 1}) {
  final now = DateTime.now().millisecondsSinceEpoch;
  return Order(
    id: id,
    items: [OrderItem(type: 'refill', qty: 1)],
    total: 25,
    address: AddrLine(label: 'Home', line: 'zone 9, Villanueva'),
    createdAt: now,
    stamps: [now],
    status: status,
    cancelled: cancelled,
    owner: 'maria@example.com',
    cust: Customer(name: 'Maria Santos', phone: '+63 917 111 2222'),
  );
}

void main() {
  test('a customer profile cannot change the account email', () {
    final s = _customer();
    final err = s.updateCustomerProfile(
        name: 'Maria S.', email: 'somebody@else.com', phone: '+63 917 000 0000');
    expect(err, isNotEmpty, reason: 'changing the email must be refused with a reason');
    expect(s.user!.email, 'maria@example.com');
    expect(s.user!.name, 'Maria Santos', reason: 'a refused save changes nothing');

    final ok = s.updateCustomerProfile(
        name: 'Maria S.', email: 'maria@example.com', phone: '+63 917 000 0000');
    expect(ok, '');
    expect(s.user!.name, 'Maria S.');
    expect(s.user!.phone, '+63 917 000 0000');
  });

  test('an admin who renamed their email can still log in after logout', () async {
    final s = AppState()
      ..noSave = true
      ..session = true
      ..role = 'admin';
    s.admin = Account(name: 'Station Owner', email: 'admin@aqua.ph');

    expect(s.updateAdminProfile(name: 'Station Owner', email: 'owner@aqua.ph'), '');
    s.logout();
    expect(s.admin, isNotNull, reason: 'the admin record is the only copy of the sign-in email');

    final err = await s.loginAdmin('owner@aqua.ph', ADMIN_SEED_PASS);
    expect(err, isNull, reason: 'the renamed address must still sign in');
    expect(s.session, isTrue);
    expect(s.screen, 'adash');
  });

  testWidgets('Details on a cancelled order shows that order', (tester) async {
    final s = _customer();
    s.orders = [
      _order('AQ-000-OLD', cancelled: true),
      _order('AQ-000-LIVE', cancelled: false, status: 3),
    ];
    s.trackId = 'AQ-000-OLD';
    s.screen = 'track';

    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) => Scaffold(body: cus.trackView(context, s).content)),
    ));
    await tester.pump();

    expect(find.text('AQ-000-OLD'), findsOneWidget,
        reason: 'the customer asked for this order by id');
    expect(find.text('AQ-000-LIVE'), findsNothing);
    expect(find.text('This order was cancelled.'), findsOneWidget);
  });

  testWidgets('Track Delivery from the menu follows the live order', (tester) async {
    final s = _customer();
    s.orders = [
      _order('AQ-000-OLD', cancelled: true),
      _order('AQ-000-LIVE', cancelled: false, status: 3),
    ];
    // The side menu clears the stale selection before opening the screen.
    s.trackId = null;

    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) => Scaffold(body: cus.trackView(context, s).content)),
    ));
    await tester.pump();

    expect(find.text('AQ-000-LIVE'), findsOneWidget);
    expect(find.text('AQ-000-OLD'), findsNothing);
  });
}
