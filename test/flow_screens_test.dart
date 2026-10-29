/* Every screen, in every role, with real data in it.
 *
 * The overflow test in ui_fixes_test only renders empty states, which misses the
 * screens that read a detail id (rdetail, rroute, adetail) and the profile and
 * settings pages. This walks the whole map with an order at every stage so a
 * missing null guard shows up as a test failure instead of a crash on the phone.
 */

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aqua/admin.dart' as admin;
import 'package:aqua/customer.dart' as cus;
import 'package:aqua/models.dart';
import 'package:aqua/rider.dart' as rid;
import 'package:aqua/state.dart';
import 'package:aqua/widgets.dart';

Order _order(String id, int status, {String? riderId, bool cancelled = false, bool mine = true}) {
  final now = DateTime.now().millisecondsSinceEpoch - (5 - status) * 600000;
  final pin = status >= 3;
  return Order(
    id: id,
    items: [OrderItem(type: 'refill', qty: 2), OrderItem(type: 'buy', qty: 1)],
    total: 200,
    address: AddrLine(
      label: 'Home',
      line: 'zone 9, pob 2, Villanueva',
      lat: pin ? 8.6011 : null,
      lng: pin ? 124.8305 : null,
    ),
    time: 'asap',
    note: 'Gate is beside the blue fence, please knock twice.',
    pay: 'cod',
    createdAt: now,
    stamps: [for (var i = 0; i <= status; i++) now + i * 60000],
    status: status,
    cancelled: cancelled,
    owner: mine ? 'maria@example.com' : 'ana@example.com',
    cust: Customer(name: 'Maria Santos', phone: '+63 917 111 2222'),
    riderId: riderId,
    stock: {'c': 1, 'w': 3},
    issue: cancelled ? Issue(type: 'Customer not home', text: 'Nobody answered the gate.', ts: now) : null,
  );
}

AppState _state(String role) {
  final s = AppState()
    ..noSave = true
    ..session = true
    ..role = role;
  s.user = Account(name: 'Maria Santos', phone: '+63 917 111 2222', email: 'maria@example.com');
  s.admin = Account(name: 'System Admin', phone: '+63 917 800 1200', email: 'admin@aqua.ph');
  s.riders = [
    Rider(
      id: 'R1',
      name: 'Rico Bautista',
      phone: '+63 917 333 4444',
      email: 'rico@example.com',
      vehicle: 'Scooter',
      plate: 'ABC 1234',
    ),
  ];
  s.rider = s.riders.first;
  s.riderId = 'R1';
  s.addresses = [
    Address(
      id: 'a1',
      label: 'Home',
      street: 'zone 9, pob 2',
      brgy: 'Villanueva',
      landmark: 'Blue fence',
      def: true,
      lat: 8.6011,
      lng: 124.8305,
    ),
    Address(id: 'a2', label: 'Office', street: 'Poblacion', brgy: 'Villanueva'),
  ];
  s.draft.addressId = 'a1';
  s.orders = [
    _order('AQ-000-001', 0, riderId: 'R1'),
    _order('AQ-000-002', 1, riderId: 'R1'),
    _order('AQ-000-003', 2, riderId: 'R1'),
    _order('AQ-000-004', 3, riderId: 'R1'),
    _order('AQ-000-005', 4, riderId: 'R1'),
    _order('AQ-000-006', 2, riderId: 'R1', cancelled: true),
    _order('AQ-000-007', 3, riderId: 'R1', mine: false),
  ];
  s.notifs = [
    Notif(id: 'n1', type: 'order', title: 'Out for delivery', body: 'Rider Rico is on the way with order AQ-000-004.', ts: 1, orderId: 'AQ-000-004'),
    Notif(id: 'n2', type: 'info', title: 'Welcome to AQUARUN', body: 'Refill or buy — we deliver.', ts: 2, read: true),
  ];
  s.anotifs = [
    Notif(id: 'a1n', type: 'order', title: 'New order', body: 'Maria · AQ-000-001 · ₱200', ts: 3, orderId: 'AQ-000-001'),
  ];
  s.rnotifs = [
    Notif(id: 'r1n', type: 'order', title: 'New delivery assigned', body: 'Maria · AQ-000-001 · ₱200', ts: 4, orderId: 'AQ-000-001', rid: 'R1'),
  ];
  s.invLogList.insertAll(0, [
    InvLog(ts: 5, kind: 'order', item: 'water', delta: -3, note: 'AQ-000-001'),
    InvLog(ts: 6, kind: 'restock', item: 'containers', delta: 20, note: 'Morning delivery'),
  ]);
  s.cart = [CartItem(type: 'refill', qty: 2)];
  s.cartOwner = 'maria@example.com';
  s.trackId = 'AQ-000-004';
  s.lastOrderId = 'AQ-000-001';
  s.detailId = 'AQ-000-004';
  s.aid = 'AQ-000-004';
  s.draft.note = 'Leave at the gate';
  return s;
}

void main() {
  final screens = <String, ScreenView Function(BuildContext, AppState)>{
    // customer
    'home': cus.homeView,
    'order': cus.orderView,
    'cart': cus.cartView,
    'checkout': cus.checkoutView,
    'confirm': cus.confirmView,
    'track': cus.trackView,
    'orders': cus.ordersView,
    'notifs': cus.notifsView,
    'profile': (c, s) => cus.profileView(c, s),
    'settings': (c, s) => cus.settingsView(c, s),
    // rider
    'rdash': rid.rdashView,
    'rlist': rid.rlistView,
    'rdetail': rid.rdetailView,
    'rroute': rid.rrouteView,
    'rhistory': rid.rhistoryView,
    'rearn': rid.rearnView,
    'rprofile': rid.riderProfileView,
    'rsettings': rid.riderSettingsView,
    // admin
    'adash': admin.adashView,
    'aorders': admin.aordersView,
    'adetail': admin.adetailView,
    'adeliv': admin.adelivView,
    'aprod': admin.aprodView,
    'ainv': admin.ainvView,
    'ausers': admin.ausersView,
    'areports': admin.areportsView,
    'aprofile': admin.adminProfileView,
    'asettings': admin.adminSettingsView,
  };

  String roleOf(String key) {
    if (key.startsWith('r') && key != 'rearn' || key == 'rprofile' || key == 'rsettings') {
      return 'rider';
    }
    if (key.startsWith('ad') || key.startsWith('ai') || key.startsWith('au') ||
        key.startsWith('ap') || key.startsWith('ar') || key == 'aorders' || key == 'adeliv') {
      return 'admin';
    }
    return 'customer';
  }

  testWidgets('every screen renders with data at 360dp', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.2;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    final broke = <String>[];
    for (final e in screens.entries) {
      final state = _state(roleOf(e.key));
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) {
            final sv = e.value(context, state);
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
      ));
      await tester.pump();
      for (final ro in tester.allRenderObjects.whereType<RenderFlex>()) {
        if (ro.direction != Axis.horizontal) continue;
        var total = 0.0;
        var c = ro.firstChild;
        while (c != null) {
          total += c.size.width;
          c = ro.childAfter(c);
        }
        if (total > ro.size.width + .5) {
          String textsOf(Element el) {
            final out = <String>[];
            void walk(Element e) {
              final w = e.widget;
              if (w is Text && w.data != null) out.add(w.data!);
              e.visitChildElements(walk);
            }

            walk(el);
            return out.take(6).join(' | ');
          }

          Element? el;
          for (final x in tester.allElements) {
            if (x.renderObject == ro) {
              el = x;
              break;
            }
          }
          // ignore: avoid_print
          print('WIDE ${e.key}: ${ro.size.width} < $total :: ${el == null ? '?' : textsOf(el)}');
        }
      }
      final err = tester.takeException();
      if (err != null) broke.add('${e.key}: $err');
    }
    expect(broke, isEmpty, reason: 'screens that threw or overflowed');
  });
}
