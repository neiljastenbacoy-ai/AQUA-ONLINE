/* Walks the real screens the way a person does, and checks that each tap lands
 * on the next screen and changes the data it claims to change.
 *
 * The shell's router lives in main.dart and boots Firebase, so this mirrors its
 * switch: the same view functions, the same content+dock layout, driven by
 * appState the same way. A tap that forgets to navigate — or navigates to a
 * screen with no way back — fails here instead of on the phone.
 */

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aqua/admin.dart' as adm;
import 'package:aqua/customer.dart' as cus;
import 'package:aqua/models.dart';
import 'package:aqua/rider.dart' as rid;
import 'package:aqua/state.dart';
import 'package:aqua/widgets.dart';

Order _order(String id, int status, {String? riderId}) {
  final now = DateTime.now().millisecondsSinceEpoch - 600000;
  return Order(
    id: id,
    items: [OrderItem(type: 'refill', qty: 2)],
    total: 50,
    address: AddrLine(label: 'Home', line: 'zone 9, pob 2, Villanueva', lat: 8.6, lng: 124.8),
    createdAt: now,
    stamps: [for (var i = 0; i <= status; i++) now],
    status: status,
    owner: 'maria@example.com',
    cust: Customer(name: 'Maria Santos', phone: '+63 917 111 2222'),
    riderId: riderId,
  );
}

AppState _customer() {
  final s = AppState()
    ..noSave = true
    ..session = true
    ..role = 'customer'
    ..screen = 'home'
    ..stack = ['home'];
  s.user = Account(name: 'Maria Santos', phone: '+63 917 111 2222', email: 'maria@example.com');
  s.addresses = [
    Address(id: 'a1', label: 'Home', street: 'zone 9', brgy: 'Villanueva', def: true, lat: 8.6, lng: 124.8),
  ];
  s.draft.addressId = 'a1';
  return s;
}

AppState _rider() {
  final s = AppState()
    ..noSave = true
    ..session = true
    ..role = 'rider'
    ..screen = 'rlist'
    ..stack = ['rlist'];
  s.riders = [Rider(id: 'R1', name: 'Rico', email: 'rico@example.com', phone: '+63 917 333 4444')];
  s.rider = s.riders.first;
  s.riderId = 'R1';
  s.orders = [_order('AQ-000-R1', 0, riderId: 'R1')];
  return s;
}

AppState _admin() {
  final s = AppState()
    ..noSave = true
    ..session = true
    ..role = 'admin'
    ..screen = 'aorders'
    ..stack = ['aorders'];
  s.admin = Account(name: 'Admin', email: 'admin@aqua.ph');
  s.riders = [Rider(id: 'R1', name: 'Rico', email: 'rico@example.com')];
  s.orders = [_order('AQ-000-A1', 2, riderId: 'R1')];
  return s;
}

/// The same map as `_screenView` in main.dart.
ScreenView _view(BuildContext context, AppState s) {
  switch (s.screen) {
    case 'home':
      return cus.homeView(context, s);
    case 'order':
      return cus.orderView(context, s);
    case 'cart':
      return cus.cartView(context, s);
    case 'checkout':
      return cus.checkoutView(context, s);
    case 'confirm':
      return cus.confirmView(context, s);
    case 'track':
      return cus.trackView(context, s);
    case 'orders':
      return cus.ordersView(context, s);
    case 'notifs':
      return cus.notifsView(context, s);
    case 'profile':
      return s.role == 'admin'
          ? adm.adminProfileView(context, s)
          : s.role == 'rider'
              ? rid.riderProfileView(context, s)
              : cus.profileView(context, s);
    case 'settings':
      return s.role == 'admin'
          ? adm.adminSettingsView(context, s)
          : s.role == 'rider'
              ? rid.riderSettingsView(context, s)
              : cus.settingsView(context, s);
    case 'rdash':
      return rid.rdashView(context, s);
    case 'rlist':
      return rid.rlistView(context, s);
    case 'rdetail':
      return rid.rdetailView(context, s);
    case 'rroute':
      return rid.rrouteView(context, s);
    case 'rhistory':
      return rid.rhistoryView(context, s);
    case 'rearn':
      return rid.rearnView(context, s);
    case 'adash':
      return adm.adashView(context, s);
    case 'aorders':
      return adm.aordersView(context, s);
    case 'adetail':
      return adm.adetailView(context, s);
    case 'adeliv':
      return adm.adelivView(context, s);
    case 'aprod':
      return adm.aprodView(context, s);
    case 'ainv':
      return adm.ainvView(context, s);
    case 'ausers':
      return adm.ausersView(context, s);
    case 'areports':
      return adm.areportsView(context, s);
  }
  return cus.homeView(context, s);
}

Widget _host(AppState s) {
  return MaterialApp(
    home: AnimatedBuilder(
      animation: s,
      builder: (context, _) {
        final sv = _view(context, s);
        return Scaffold(
          body: Column(children: [
            Expanded(child: sv.content),
            if (sv.dock != null)
              Container(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: Column(mainAxisSize: MainAxisSize.min, children: [sv.dock!]),
              ),
          ]),
        );
      },
    ),
  );
}

Future<void> _tap(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.tap(f, warnIfMissed: false);
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets('customer: product → cart → checkout → confirm → track', (tester) async {
    final s = _customer();
    await tester.pumpWidget(_host(s));
    await tester.pump();

    await _tap(tester, find.text('Refill Gallon').first);
    expect(s.screen, 'order', reason: 'the product card must open the order screen');

    await _tap(tester, find.text('Add to Cart'));
    expect(s.screen, 'cart');
    expect(s.cart, isNotEmpty);

    await _tap(tester, find.textContaining('Checkout'));
    expect(s.screen, 'checkout');

    await _tap(tester, find.text('Place Order'));
    await tester.pump();
    expect(s.screen, 'confirm', reason: 'a placed order must land on its confirmation');
    expect(s.orders.length, 1);
    expect(s.cart, isEmpty, reason: 'the cart is handed to the order');
    expect(s.lastOrderId, s.orders.first.id);
    expect(s.notifs.any((n) => n.title == 'Order placed'), isTrue);

    await _tap(tester, find.text('Track Delivery'));
    expect(s.screen, 'track');
    expect(s.trackId, s.orders.first.id);
  });

  testWidgets('customer: back from the confirmation goes home', (tester) async {
    final s = _customer();
    s.orders = [_order('AQ-000-C1', 0)];
    s.lastOrderId = 'AQ-000-C1';
    s.screen = 'confirm';
    await tester.pumpWidget(_host(s));
    await tester.pump();

    s.back();
    await tester.pump();
    expect(s.screen, 'home');
  });

  testWidgets('customer: a closed station refuses the order', (tester) async {
    final s = _customer();
    s.station.accepting = false;
    s.cart = [CartItem(type: 'refill', qty: 1)];
    s.cartOwner = 'maria@example.com';
    s.screen = 'checkout';
    s.stack = ['home', 'checkout'];
    await tester.pumpWidget(_host(s));
    await tester.pump();

    await _tap(tester, find.text('Place Order'));
    expect(s.orders, isEmpty, reason: 'no order may be created while the station is closed');
    expect(s.screen, 'checkout', reason: 'the customer stays on checkout to read the reason');
    expect(s.cart, isNotEmpty);
  });

  testWidgets('rider: a delivery opens and the dock advances it', (tester) async {
    final s = _rider();
    await tester.pumpWidget(_host(s));
    await tester.pump();

    await _tap(tester, find.bySemanticsLabel(RegExp('AQ-000-R1')));
    expect(s.screen, 'rdetail');
    expect(s.detailId, 'AQ-000-R1');

    await _tap(tester, find.text('Confirm Order'));
    expect(s.orders.first.status, 1, reason: 'the dock action must move the order one stage');
    expect(s.screen, 'rdetail', reason: 'the rider stays on the delivery after a stage');
  });

  testWidgets('admin: an order opens and the dock advances it', (tester) async {
    final s = _admin();
    await tester.pumpWidget(_host(s));
    await tester.pump();

    await _tap(tester, find.bySemanticsLabel(RegExp('AQ-000-A1')));
    expect(s.screen, 'adetail');
    expect(s.aid, 'AQ-000-A1');

    await _tap(tester, find.text('Send Out for Delivery'));
    expect(s.orders.first.status, 3);
    expect(s.screen, 'adetail');
  });

  testWidgets('rider: delivering from the detail returns to the list', (tester) async {
    final s = _rider();
    s.orders.first.status = 3;
    s.orders.first.stamps = [DateTime.now().millisecondsSinceEpoch];
    // A delivery on the road is listed under "in progress", not "assigned".
    s.rtab = 'progress';
    await tester.pumpWidget(_host(s));
    await tester.pump();

    await _tap(tester, find.bySemanticsLabel(RegExp('AQ-000-R1')));
    expect(s.screen, 'rdetail');

    expect(find.text('Mark as Delivered'), findsOneWidget, reason: 'the dock must offer the next stage');
    await _tap(tester, find.text('Mark as Delivered'));
    await tester.pumpAndSettle();
    expect(find.text('Yes, Delivered'), findsOneWidget, reason: 'delivering asks first');
    await _tap(tester, find.text('Yes, Delivered'));
    await tester.pumpAndSettle();

    expect(s.orders.first.status, 4);
    expect(s.screen, 'rlist', reason: 'a finished delivery must not leave the rider on a dead page');
  });

  testWidgets('customer: a notification opens the order it is about', (tester) async {
    final s = _customer();
    s.orders = [_order('AQ-000-N1', 3, riderId: 'R1')];
    s.notifs = [
      Notif(id: 'n1', type: 'order', title: 'Out for delivery', body: 'On the way', ts: 1, orderId: 'AQ-000-N1'),
    ];
    s.screen = 'notifs';
    await tester.pumpWidget(_host(s));
    await tester.pump();

    await _tap(tester, find.text('Out for delivery').first);
    expect(s.screen, 'track');
    expect(s.trackId, 'AQ-000-N1');
    expect(s.notifs.first.read, isTrue);
  });
}
