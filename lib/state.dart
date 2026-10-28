import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:collection/collection.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'constants.dart';
import 'firebase_boot.dart';
import 'models.dart';
import 'notify.dart';
import 'online.dart';

/// Full app state — a 1:1 port of the HTML global `S` + domain helpers + actions.
class AppState extends ChangeNotifier {
  /* ---- current user / session ---- */
  Account? user;
  bool session = false;
  String role = 'customer';
  Rider? rider;
  List<Rider> riders = [];
  String riderId = '';
  Account? admin;
  List<Notif> anotifs = [];
  List<Notif> rnotifs = [];

  /* ---- persistent business data ---- */
  Map<String, Product> products = {
    'refill': Product(price: 25, desc: 'Refill your empty gallon with purified water.'),
    'buy': Product(price: 150, desc: 'New filled gallon with container.'),
  };
  Station station = Station();
  Map<String, InvItem> inv = {'containers': InvItem(qty: 40, low: 10), 'water': InvItem(qty: 600, low: 100)};
  List<InvLog> invLogList = [];

  /* ---- customer ---- */
  List<Address> addresses = [];
  List<Order> orders = [];
  List<Notif> notifs = [];
  List<CartItem> cart = [];
  int seq = 0;
  Draft draft = Draft();

  /* ---- ui/nav ---- */
  String authRole = 'customer';
  String authTab = 'login';
  String filter = 'all';
  String? trackId;
  String? lastOrderId;
  int slide = 0;
  String screen = 'splash';
  List<String> stack = ['splash'];
  bool noSave = false;

  /* rider ui */
  String rtab = 'assigned';
  String rfilter = 'all';
  String? detailId;
  String? routeId;

  /* admin ui */
  String aq = '';
  String atab = 'all';
  String asort = 'new';
  String atype = 'all';
  String autab = 'riders';
  String areport = '7d';
  String? aid;

  /* misc */
  AppSettings settings = AppSettings();
  bool _savedLoaded = false;
  late SharedPreferences prefs;
  bool firstBoot = true;
  int bootAt = DateTime.now().millisecondsSinceEpoch;

  /* ---- price helpers ---- */
  double priceOf(String t) => t == 'refill' ? products['refill']!.price : products['buy']!.price;
  String nameOf(String t) => t == 'refill' ? 'Refill Gallon' : 'Buy Gallon';
  String descOf(String t) => t == 'refill' ? products['refill']!.desc : products['buy']!.desc;

  /* ================= boot / persistence ================= */

  Future<void> init() async {
    // Firebase must be up before the sync layer attaches; this runs inside
    // the splash window so it never delays the first frame.
    await bootFirebase();
    prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(KEY);
    if (raw != null) {
      try {
        _loadJson(raw);
      } catch (_) {}
    }
    _savedLoaded = true;
    // Online: attach Firestore listeners (no-op when Firebase isn't set up).
    await OnlineSync.i.start(this);
    migrate();
    // session validity: role must have a matching signed-in user
    if (session == true &&
        ((role == 'rider' && rider == null) ||
            (role == 'admin' && admin == null) ||
            (role == 'customer' && user == null))) {
      session = false;
    }
    authRole = role;
    notifyListeners();
  }

  void _loadJson(String raw) {
    final d = jsonDecode(raw) as Map<String, dynamic>;
    dynamic pick(String k, dynamic def) {
      final v = d[k];
      return v ?? def;
    }
    if (pick('user', null) != null) user = Account.fromJson(d['user']);
    session = (d['session'] == true) ? true : false;
    if (pick('role', null) != null) role = d['role'];
    riders = ((d['riders'] ?? []) as List).map((x) => Rider.fromJson(x)).toList();
    riderId = (d['riderId'] ?? '') as String;
    if (pick('rider', null) != null) rider = Rider.fromJson(d['rider']);
    if (pick('admin', null) != null) admin = Account.fromJson(d['admin']);
    anotifs = ((d['anotifs'] ?? []) as List).map((x) => Notif.fromJson(x)).toList();
    products = {
      'refill': Product.fromJson((d['products'] ?? {})['refill'] ?? {}),
      'buy': Product.fromJson((d['products'] ?? {})['buy'] ?? {}),
    };
    station = Station.fromJson(d['station'] ?? {});
    final invJson = d['inv'] as Map<String, dynamic>?;
    if (invJson != null) {
      inv = {
        'containers': InvItem.fromJson(invJson['containers'] ?? {}),
        'water': InvItem.fromJson(invJson['water'] ?? {}),
      };
      invLogList = ((invJson['log'] ?? []) as List).map((x) => InvLog.fromJson(x)).toList();
    }
    rnotifs = ((d['rnotifs'] ?? []) as List).map((x) => Notif.fromJson(x)).toList();
    addresses = ((d['addresses'] ?? []) as List).map((x) => Address.fromJson(x)).toList();
    orders = ((d['orders'] ?? []) as List).map((x) => Order.fromJson(x)).toList();
    notifs = ((d['notifs'] ?? []) as List).map((x) => Notif.fromJson(x)).toList();
    cart = ((d['cart'] ?? []) as List).map((x) => CartItem.fromJson(x)).toList();
    seq = (d['seq'] ?? 0) as int;
    if (pick('draft', null) != null) draft = Draft.fromJson(d['draft']);
    settings = AppSettings.fromJson(d['settings'] ?? {});
  }

  void migrate() {
    if (rider != null && riders.isEmpty) {
      rider!.id = rider!.id.isEmpty ? uid() : rider!.id;
      riders = [rider!];
      riderId = rider!.id;
    }
    for (final r in riders) {
      if (r.id.isEmpty) r.id = uid();
    }
    if (riders.isNotEmpty) {
      for (final o in orders) {
        // Only backfill finished orders so active ones keep waiting for a
        // proper auto-assign that respects rider availability.
        if (o.riderId == null && (o.status >= 4 || o.cancelled)) {
          o.riderId = riders[hash(o.id) % riders.length].id;
        }
      }
      autoAssignWaiting();
    }
    rider = riders.where((r) => r.id == riderId).firstOrNull;
    notifyListeners();
  }

  /// Public UI refresh used by the gui modules (notifyListeners stays protected here).
  void updateUI() {
    notifyListeners();
  }

  void save() {
    if (noSave || !_savedLoaded) return;
    try {
      final json = jsonEncode({
        'role': role,
        'riders': riders.map((r) => r.toJson()).toList(),
        'riderId': rider?.id ?? riderId,
        'admin': admin?.toJson(),
        'anotifs': anotifs.map((n) => n.toJson()).toList(),
        'products': products.map((k, v) => MapEntry(k, v.toJson())),
        'station': station.toJson(),
        'inv': {
          'containers': inv['containers']!.toJson(),
          'water': inv['water']!.toJson(),
          'log': invLogList.map((l) => l.toJson()).toList(),
        },
        'rnotifs': rnotifs.map((n) => n.toJson()).toList(),
        'user': user?.toJson(),
        'session': session == true,
        'addresses': addresses.map((a) => a.toJson()).toList(),
        'orders': orders.map((o) => o.toJson()).toList(),
        'notifs': notifs.map((n) => n.toJson()).toList(),
        'cart': cart.map((c) => c.toJson()).toList(),
        'seq': seq,
        'draft': draft.toJson(),
        'settings': settings.toJson(),
      });
      prefs.setString(KEY, json);
    } catch (_) {}
    // Online mirror: push the diff to Firestore (no-op when offline).
    OnlineSync.i.requestPush();
  }

  /// Admin "Reset data" — clears local state AND the shared Firestore data.
  Future<void> resetAll() async {
    noSave = true;
    prefs.remove(KEY);
    await OnlineSync.i.wipeAll();
    // fresh instance state
    user = null; session = false; role = 'customer'; rider = null;
    riders = []; riderId = ''; admin = null; anotifs = []; rnotifs = [];
    products = {
      'refill': Product(price: 25, desc: 'Refill your empty gallon with purified water.'),
      'buy': Product(price: 150, desc: 'New filled gallon with container.'),
    };
    station = Station();
    inv = {'containers': InvItem(qty: 40, low: 10), 'water': InvItem(qty: 600, low: 100)};
    invLogList = [];
    addresses = []; orders = []; notifs = []; cart = []; seq = 0;
    draft = Draft(); settings = AppSettings();
    authRole = 'customer'; authTab = 'login';
    screen = 'auth'; stack = ['auth']; slide = 0;
    noSave = false;
    save(); // re-seeds the world doc with product/station defaults
    notifyListeners();
  }

  /* ================= identity helpers ================= */

  dynamic whoAmI() => role == 'admin' ? admin : (role == 'rider' ? rider : user);
  String homeOf() => role == 'rider' ? 'rdash' : (role == 'admin' ? 'adash' : 'home');
  String roleLabel() =>
      role == 'admin' ? 'Administrator' : (role == 'rider' ? 'Driver / Rider' : 'Customer');
  String firstName() => ((whoAmI()?.name ?? '') as String? ?? 'there').split(' ').first;
  String initials() => initialsOf(whoAmI()?.name);

  /* ================= domain helpers ================= */

  int cartCount() => cart.fold(0, (a, i) => a + i.qty);
  double sumItems(List<dynamic> items) => items.fold<double>(0, (a, i) => a + priceOf(i.type) * i.qty);

  Address? curAddr() {
    Address? find(String? id) => id == null ? null : addresses.where((a) => a.id == id).firstOrNull;
    Address? a = find(draft.addressId);
    a ??= addresses.where((x) => x.def).firstOrNull;
    a ??= addresses.firstOrNull;
    return a;
  }

  bool mine(Order o) => o.owner == null || (user != null && o.owner == user!.email);
  List<Order> myOrders() => orders.where(mine).toList();

  List<Notif> notifList() {
    if (role == 'admin') return anotifs;
    if (role == 'rider') return rnotifs.where((n) => rider != null && n.rid == rider!.id).toList();
    return notifs;
  }

  int unread() => notifList().where((n) => !n.read).length;

  void addNotif({String type = 'info', String title = '', String body = '', String? orderId, List<Notif>? into, String? rid}) {
    if (!settings.notify) return;
    final n = Notif(
        id: uid(), type: type, title: title, body: body,
        ts: DateTime.now().millisecondsSinceEpoch,
        read: false, orderId: orderId, rid: rid);
    into == null ? notifs.insert(0, n) : into.insert(0, n);
    // Customer updates belong to the signed-in user — notify the phone.
    PhoneNotify.push(title, body);
  }

  void addANotif({String type = 'info', String title = '', String body = '', String? orderId}) {
    if (!settings.notify) return;
    anotifs.insert(0, Notif(id: uid(), type: type, title: title, body: body,
        ts: DateTime.now().millisecondsSinceEpoch, read: false, orderId: orderId));
    if (anotifs.length > 60) anotifs.length = 60;
    // Admin alerts only ring the phone while the admin app is in use.
    if (role == 'admin') PhoneNotify.push(title, body);
  }

  void addRNotif({String type = 'info', String title = '', String body = '', String? orderId, String? rid}) {
    if (!settings.notify) return;
    rnotifs.insert(0, Notif(id: uid(), type: type, title: title, body: body,
        ts: DateTime.now().millisecondsSinceEpoch, read: false, orderId: orderId, rid: rid));
    if (rnotifs.length > 120) rnotifs.length = 120;
    // Rider alerts ring the phone for the signed-in rider's assignments.
    final mine = rid == null || (rider != null && rid == rider!.id);
    if (role == 'rider' && mine) PhoneNotify.push(title, body);
  }

  /* ================= navigation ================= */

  void uiGo(String s, {bool side = false, bool fresh = false, bool replace = false}) {
    if (s == 'home' && role != 'customer') s = homeOf();
    if (side) {
      stack = s == 'home' ? ['home'] : (ROOT.contains(s) ? [s] : ['home', s]);
    } else if (ROOT.contains(s) || fresh) {
      stack = [s];
    } else if (replace) {
      stack[stack.length - 1] = s;
    } else {
      stack.add(s);
    }
    screen = stack.last;
    notifyListeners();
  }

  void goScreen(String s, {bool side = false, bool fresh = false, bool replace = false}) {
    uiGo(s, side: side, fresh: fresh, replace: replace);
    save();
  }

  void back() {
    if (screen == 'confirm') {
      goScreen('home', fresh: true);
      return;
    }
    if (stack.length > 1) {
      stack.removeLast();
    } else {
      stack = [homeOf()];
    }
    screen = stack.last;
    save();
    notifyListeners();
  }

  /* ================= stock ================= */

  List<String> stockState(String k) {
    final x = inv[k]!;
    if (x.qty <= 0) return ['Out of stock', '5', 'bad'];
    if (x.qty <= x.low) return ['Low stock', '0', 'warn'];
    return ['In stock', '4', ''];
  }

  void invLog(String kind, String item, int delta, String note) {
    invLogList.insert(0, InvLog(ts: DateTime.now().millisecondsSinceEpoch, kind: kind, item: item, delta: delta, note: note));
    if (invLogList.length > 60) invLogList.length = 60;
  }

  (int, int) need(List<OrderItem> items) {
    int c = 0, w = 0;
    for (final i in items) {
      w += i.qty;
      if (i.type == 'buy') c += i.qty;
    }
    return (c, w);
  }

  void lowCheck((int, int) b) {
    final pairs = [('containers', 'Gallon containers', 'c'), ('water', 'Purified water', 'w')];
    for (final (k, label, key) in pairs) {
      final it = inv[k]!;
      final v = key == 'c' ? b.$1 : b.$2;
      if (v > it.low && it.qty <= it.low) {
        addANotif(type: 'info', title: it.qty <= 0 ? 'Out of stock' : 'Low stock', body: '$label: ${it.qty} left (reorder level ${it.low}).');
      }
    }
  }

  void useStock(Order o) {
    final (c, w) = need(o.items);
    final bc = inv['containers']!.qty, bw = inv['water']!.qty;
    inv['containers']!.qty = (inv['containers']!.qty - c).clamp(0, 1 << 31);
    inv['water']!.qty = (inv['water']!.qty - w).clamp(0, 1 << 31);
    o.stock = {'c': c, 'w': w};
    if (c > 0) invLog('order', 'containers', -c, o.id);
    invLog('order', 'water', -w, o.id);
    lowCheck((bc, bw));
  }

  void restoreStock(Order o) {
    final s = o.stock;
    if (s == null || o.restored) return;
    o.restored = true;
    inv['containers']!.qty += s['c'] ?? 0;
    inv['water']!.qty += s['w'] ?? 0;
    if ((s['c'] ?? 0) > 0) invLog('return', 'containers', s['c']!, '${o.id} cancelled');
    invLog('return', 'water', s['w']!, '${o.id} cancelled');
  }

  String blockFor(List<OrderItem> items) {
    if (!station.accepting) return 'Station is not taking orders now';
    for (final i in items) {
      if (!(i.type == 'refill' ? products['refill']! : products['buy']!).active) {
        return '${nameOf(i.type)} is unavailable';
      }
    }
    final (c, w) = need(items);
    if (c > inv['containers']!.qty) {
      final q = inv['containers']!.qty;
      return 'Only $q Buy Gallon${q == 1 ? '' : 's'} in stock';
    }
    if (w > inv['water']!.qty) return 'Only ${inv['water']!.qty} gallons of water left';
    return '';
  }

  String orderBlock(String t, int q) => blockFor([...cart.map((c) => OrderItem(type: c.type, qty: c.qty)), OrderItem(type: t, qty: q)]);
  String placeBlock() => blockFor(cart.map((c) => OrderItem(type: c.type, qty: c.qty)).toList());

  /* ================= rider assignment ================= */

  int loadOf(Rider r) => orders
      .where((o) => o.riderId == r.id && !o.cancelled && o.status < 4)
      .length;

  List<Order> rorders() => rider == null ? [] : orders.where((o) => o.riderId == rider!.id).toList();

  int rstate(Order o) => o.cancelled ? 5 : (o.status >= 4 ? 4 : (o.status == 3 ? 1 : 0));

  Customer custOf(Order o) => o.cust;

  double feeOf(Order o) => (RIDER_FEE_BASE + RIDER_FEE_PER_GALLON * gallonsOf(o)).toDouble();

  int doneAt(Order o) => o.stamps.length > o.status && o.stamps[o.status] != null ? o.stamps[o.status]! : o.createdAt;

  Rider? riderOf(Order o) {
    if (o.riderId == null) return null;
    return orders.isNotEmpty ? riders.where((r) => r.id == o.riderId).firstOrNull : null;
  }

  Rider? pickRider() {
    final c = riders.where((r) => r.active != false && r.available == 'available').toList()
      ..sort((a, b) => loadOf(a).compareTo(loadOf(b)));
    return c.firstOrNull;
  }

  void assignTo(Order o, Rider? r) {
    o.riderId = r?.id;
    if (r != null) {
      addRNotif(rid: r.id, type: 'order', orderId: o.id, title: 'New delivery assigned', body: '${custOf(o).name} · ${o.id} · ${peso(o.total)}');
    }
  }

  bool autoAssign(Order o) {
    if (!station.autoAssign || o.riderId != null || o.cancelled || o.status >= 4) return false;
    final r = pickRider();
    if (r == null) return false;
    assignTo(o, r);
    return true;
  }

  int autoAssignWaiting() {
    int n = 0;
    final sorted = [...orders]..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    for (final o in sorted) {
      if (o.riderId == null && autoAssign(o)) n++;
    }
    return n;
  }

  /* ================= status transitions ================= */

  void setStatus(Order o, int n) {
    final now = DateTime.now().millisecondsSinceEpoch;
    for (int i = o.status + 1; i <= n; i++) {
      while (o.stamps.length <= i) {
        o.stamps.add(null);
      }
      o.stamps[i] = now;
    }
    o.status = n;
    o.byRider = true;
    if (role == 'rider' && n >= 3) {
      addANotif(type: 'order', orderId: o.id, title: n == 4 ? 'Order delivered' : 'Out for delivery', body: '${custOf(o).name} · ${o.id} · ${riderOf(o)?.name ?? 'rider'}');
    }
    if (mine(o) && n >= 1 && n <= 4) {
      final t = noteText(n, o);
      if (t != null) {
        addNotif(type: 'order', orderId: o.id, title: t.$1, body: t.$2);
      }
    }
    save();
  }

  (String, String)? noteText(int n, Order o) {
    switch (n) {
      case 1: return ('Order confirmed', 'The station accepted order ${o.id}.');
      case 2:
        return ('Preparing your water', o.items.any((i) => i.type == 'refill') ? 'Your gallons are being refilled.' : 'Your gallons are being prepared.');
      case 3:
        return ('Out for delivery', '${riderOf(o) != null ? 'Rider ${riderOf(o)!.name.split(' ').first}' : 'Your rider'} is on the way with order ${o.id}.');
      case 4: return ('Delivered', 'Order ${o.id} was delivered. Enjoy fresh water.');
    }
    return null;
  }

  /* ================= customer actions ================= */

  void doType(String t) {
    draft.type = t;
    notifyListeners();
  }

  void draftQty(int d) {
    final q = draft.qty + d;
    if (q < 1 || q > 20) return;
    draft.qty = q;
    notifyListeners();
  }

  void addToCart() {
    final d = draft;
    CartItem? ex = cart.where((i) => i.type == d.type).firstOrNull;
    if (ex != null) {
      ex.qty = (ex.qty + d.qty).clamp(1, 20);
    } else {
      cart.add(CartItem(type: d.type, qty: d.qty));
    }
    final msg = 'Added ${d.qty} × ${nameOf(d.type)}';
    d.qty = 1;
    goScreen('cart');
    toast(msg);
  }

  void cartQty(int index, int d) {
    final it = cart[index];
    final q = it.qty + d;
    if (q < 1 || q > 20) return;
    it.qty = q;
    notifyListeners();
    save();
  }

  void cartDelete(int index) {
    final n = nameOf(cart[index].type);
    cart.removeAt(index);
    notifyListeners();
    save();
    toast('$n removed');
  }

  void setPay(String p) {
    draft.pay = p;
    notifyListeners();
  }

  void reorder(String id) {
    final o = orders.where((x) => x.id == id).firstOrNull;
    if (o == null) return;
    for (final it in o.items) {
      final ex = cart.where((c) => c.type == it.type).firstOrNull;
      if (ex != null) {
        ex.qty = (ex.qty + it.qty).clamp(1, 20);
      } else {
        cart.add(CartItem(type: it.type, qty: it.qty));
      }
    }
    goScreen('cart');
    toast('Items added to your cart');
  }

  Future<String?> placeOrder() async {
    if (cart.isEmpty) {
      goScreen('cart');
      return null;
    }
    final a = curAddr();
    if (a == null) {
      return 'Add a delivery address before placing your order.';
    }
    final blk = placeBlock();
    if (blk.isNotEmpty) return '$blk. Please update your cart.';
    final now = DateTime.now().millisecondsSinceEpoch;
    final n = await OnlineSync.i.nextSeq();
    seq = n;
    final o = Order(
      id: oid(now, n),
      items: cart.map((i) => OrderItem(type: i.type, qty: i.qty)).toList(),
      total: sumItems(cart),
      prices: {'refill': priceOf('refill'), 'buy': priceOf('buy')},
      address: AddrLine(
        label: a.label,
        line: '${a.line}${a.landmark.isNotEmpty ? ' (${a.landmark})' : ''}',
        lat: a.lat,
        lng: a.lng,
      ),
      time: draft.time, note: draft.note, pay: draft.pay,
      createdAt: now, status: 0, cancelled: false, stamps: [now],
      owner: user!.email,
      cust: Customer(name: user!.name, phone: user!.phone),
      riderId: null,
    );
    orders.insert(0, o);
    cart = [];
    lastOrderId = o.id;
    trackId = o.id;
    draft.note = '';
    addNotif(type: 'order', orderId: o.id, title: 'Order placed', body: 'We received order ${o.id} for ${peso(o.total)}.');
    useStock(o);
    autoAssign(o);
    addANotif(type: 'order', orderId: o.id, title: 'New order', body: '${user!.name} · ${o.id} · ${peso(o.total)}');
    goScreen('confirm', replace: true);
    return null;
  }

  void cancelOrder(String id) {
    final o = orders.where((x) => x.id == id).firstOrNull;
    if (o == null || o.status > 1) return;
    o.cancelled = true;
    addNotif(type: 'order', orderId: o.id, title: 'Order cancelled', body: 'Order ${o.id} was cancelled.');
    if (o.riderId != null) {
      addRNotif(rid: o.riderId, type: 'order', orderId: o.id, title: 'Order cancelled by customer', body: '${o.id} was cancelled before delivery.');
    }
    addANotif(type: 'order', orderId: o.id, title: 'Order cancelled by customer', body: '${o.id} was cancelled.');
    restoreStock(o);
    save();
    notifyListeners();
    toast('Order cancelled');
  }

  /* ================= notifications ================= */

  void openNotif(String id, void Function() after) {
    final n = notifList().where((x) => x.id == id).firstOrNull;
    if (n == null) return;
    n.read = true;
    if (role == 'admin') {
      if (n.orderId != null && orders.any((o) => o.id == n.orderId)) {
        aid = n.orderId;
        goScreen('adetail');
      }
    } else if (role == 'rider') {
      if (n.orderId != null && orders.any((o) => o.id == n.orderId)) {
        detailId = n.orderId;
        goScreen('rdetail');
      }
    } else {
      if (n.orderId != null && orders.any((o) => o.id == n.orderId)) {
        trackId = n.orderId;
        goScreen('track');
      }
    }
    save();
    notifyListeners();
    after();
  }

  void markAllRead() {
    for (final n in notifList()) {
      n.read = true;
    }
    save();
    notifyListeners();
  }

  /* ================= addresses ================= */

  void setAddressDefault(String id) {
    for (final a in addresses) {
      a.def = a.id == id;
    }
    save();
    notifyListeners();
    toast('Default address updated');
  }

  Address saveAddress({String? id, required String label, required String street, required String brgy, String city = '', String landmark = '', required bool def, bool pick = false, double? lat, double? lng}) {
    if (id != null) {
      final a = addresses.where((x) => x.id == id).firstOrNull!;
      a.label = label; a.street = street; a.brgy = brgy; a.city = city; a.landmark = landmark; a.def = def;
      a.lat = lat; a.lng = lng;
      if (a.def || addresses.length == 1) {
        for (final x in addresses) {
          x.def = x.id == a.id;
        }
      } else if (!addresses.any((x) => x.def)) {
        addresses[0].def = true;
      }
      if (pick || draft.addressId == null) draft.addressId = a.id;
      save();
      notifyListeners();
      toast('Address updated');
      return a;
    }
    final a = Address(id: uid(), label: label, street: street, brgy: brgy, city: city, landmark: landmark, def: def, lat: lat, lng: lng);
    addresses.add(a);
    if (a.def || addresses.length == 1) {
      for (final x in addresses) {
        x.def = x.id == a.id;
      }
    } else if (!addresses.any((x) => x.def)) {
      addresses[0].def = true;
    }
    if (pick || draft.addressId == null) draft.addressId = a.id;
    save();
    notifyListeners();
    toast('Address saved');
    return a;
  }

  void deleteAddress(String id) {
    final was = addresses.where((a) => a.id == id).firstOrNull;
    addresses = addresses.where((a) => a.id != id).toList();
    if (was != null && was.def && addresses.isNotEmpty) addresses[0].def = true;
    if (draft.addressId == id) draft.addressId = null;
    save();
    notifyListeners();
    toast('Address deleted');
  }

  void pickAddress(String id) {
    draft.addressId = id;
    save();
    notifyListeners();
  }

  void setDraftTime(String v) {
    draft.time = v;
    save();
    notifyListeners();
  }

  void setDraftNote(String v) {
    draft.note = v;
    save();
    notifyListeners();
  }

  /* ================= auth ================= */

  Future<String?> loginCustomer(String emailRaw, String pw) async {
    final email = emailRaw.trim().toLowerCase();
    if (!isEmail(email)) return 'Enter a valid email address.';
    if (pw.length < 4) return 'Enter your password (at least 4 characters).';
    final doc = await OnlineSync.i.fetchUser(email);
    if (doc == null) {
      return OnlineSync.i.active
          ? 'No account found for that email. Create one on the Register tab.'
          : 'Cannot reach the online database. Check your internet connection.';
    }
    if ((doc['pass'] ?? '') != pw) return 'Incorrect password for that account.';
    user = Account.fromJson(doc);
    addresses = ((doc['addresses'] ?? []) as List).map((x) => Address.fromJson(x)).toList();
    notifs = ((doc['notifs'] ?? []) as List).map((x) => Notif.fromJson(x)).toList();
    session = true;
    role = 'customer';
    OnlineSync.i.sessionChanged();
    save();
    goScreen('home', fresh: true);
    toast('Welcome back, ${firstName()}');
    return null;
  }

  Future<String?> registerCustomer(String name, String phone, String emailRaw, String pw) async {
    final email = emailRaw.trim().toLowerCase();
    if (name.trim().length < 2) return 'Enter your full name.';
    if (phone.replaceAll(RegExp(r'\D'), '').length < 10) return 'Enter a mobile number with at least 10 digits.';
    if (!isEmail(email)) return 'Enter a valid email address.';
    if (pw.length < 4) return 'Choose a password with at least 4 characters.';
    if (await OnlineSync.i.userExists(email)) {
      return 'An account with that email already exists. Log in instead.';
    }
    user = Account(name: name.trim(), phone: phone.trim(), email: email);
    role = 'customer';
    session = true;
    addresses = [];
    cart = [];
    draft.addressId = null; draft.time = 'asap'; draft.note = ''; draft.qty = 1; draft.type = 'refill'; draft.pay = 'cod';
    notifs = [];
    await OnlineSync.i.createUserDoc(email: email, name: name.trim(), phone: phone.trim(), pass: pw);
    addNotif(type: 'info', title: 'Welcome to AQUA', body: 'Choose Refill Gallon if you have an empty gallon, or Buy Gallon for a new filled one.');
    OnlineSync.i.sessionChanged();
    save();
    goScreen('home', fresh: true);
    toast('Account created');
    return null;
  }

  Future<String?> loginRider(String emailRaw, String pw) async {
    final email = emailRaw.trim().toLowerCase();
    if (!isEmail(email)) return 'Enter a valid email address.';
    if (pw.length < 4) return 'Enter your password (at least 4 characters).';
    // Online lookup first (riders live in Firestore); local list as fallback
    // for the brief window before the riders snapshot arrives.
    final hit = await OnlineSync.i.fetchRiderByEmail(email);
    Rider? rr;
    String rid = '';
    if (hit != null) {
      rid = hit.key;
      rr = Rider.fromJson(hit.value);
      rr.id = rid;
    } else {
      rr = riders.where((r) => r.email == email).firstOrNull;
      rid = rr?.id ?? '';
    }
    if (rr == null) return 'No rider account found for that email. Ask the station admin to add your account.';
    if (rr.active == false) return 'This rider account is deactivated. Please contact the station.';
    if (pw != rr.pass) return 'Incorrect password for that rider account.';
    rider = rr;
    riderId = rid;
    role = 'rider';
    session = true;
    save();
    goScreen('rdash', fresh: true);
    // No-op until Firebase is configured (simulation mode otherwise).
    RiderLocationBroadcaster.instance.start(riderId: riderId);
    toast('Welcome, ${firstName()}');
    return null;
  }

  Future<String?> loginAdmin(String emailRaw, String pw) async {
    final email = emailRaw.trim().toLowerCase();
    if (!isEmail(email)) return 'Enter a valid email address.';
    if (pw.length < 4) return 'Enter your password (at least 4 characters).';
    final ad = admin ?? Account(name: 'System Admin', email: ADMIN_SEED_EMAIL, phone: '+63 917 800 1200');
    if (email != ad.email) return 'No admin account found for that email.';
    admin = ad;
    role = 'admin';
    session = true;
    OnlineSync.i.sessionChanged();
    save();
    goScreen('adash', fresh: true);
    toast('Welcome back, Admin');
    return null;
  }

  void logout() {
    authRole = role;
    authTab = 'login';
    session = false;
    RiderLocationBroadcaster.instance.stop();
    OnlineSync.i.sessionChanged();
    goScreen('auth', fresh: true);
  }

  /* ================= rider actions ================= */

  void riderStart(String id) {
    final o = orders.where((x) => x.id == id).firstOrNull;
    if (o == null || o.cancelled || o.status >= 3) return;
    setStatus(o, 3);
    RiderLocationBroadcaster.instance.delivering(id);
    notifyListeners();
    toast('Delivery started');
  }

  void riderDeliver(String id) {
    final o = orders.where((x) => x.id == id).firstOrNull;
    if (o == null || o.cancelled || o.status >= 4) return;
    setStatus(o, 4);
    RiderLocationBroadcaster.instance.delivering(null);
    addRNotif(rid: o.riderId, type: 'order', orderId: o.id, title: 'Delivery completed', body: '${custOf(o).name} · ${o.id} · earned ${peso(feeOf(o))}');
    notifyListeners();
    toast('Delivery completed');
  }

  void riderAvailableTo(String v) {
    rider!.available = v;
    int n = 0;
    if (v == 'available') n = autoAssignWaiting();
    save();
    notifyListeners();
    toast(n > 0 ? 'You are available. $n waiting ${n == 1 ? 'delivery' : 'deliveries'} assigned.' : 'Status: ${AV[v]}');
  }

  void updateRiderProfile({required String name, String phone = '', required String email, String vehicle = 'Motorcycle', String plate = ''}) {
    rider!
      ..name = name.trim()
      ..phone = phone.trim()
      ..email = email.trim().toLowerCase()
      ..vehicle = vehicle
      ..plate = plate.trim().toUpperCase();
    save();
    notifyListeners();
    toast('Profile updated');
  }

  Issue? riderReport({required String orderId, required String type, required String text, required bool cancel}) {
    final o = orders.where((x) => x.id == orderId).firstOrNull;
    if (o == null) return null;
    o.issue = Issue(type: type, text: text.trim(), ts: DateTime.now().millisecondsSinceEpoch);
    o.byRider = true;
    if (cancel) o.cancelled = true;
    if (mine(o)) {
      addNotif(type: 'order', orderId: o.id, title: cancel ? 'Delivery cancelled' : 'Delivery issue', body: cancel ? 'Order ${o.id} was cancelled: $type.' : 'Your rider reported: $type. They will contact you.');
    }
    if (cancel) restoreStock(o);
    addANotif(type: 'order', orderId: o.id, title: cancel ? 'Delivery cancelled by rider' : 'Delivery issue reported', body: '$type · ${o.id}');
    addRNotif(rid: o.riderId, type: 'info', orderId: o.id, title: cancel ? 'Delivery cancelled' : 'Issue reported', body: '$type · ${o.id}');
    save();
    return o.issue;
  }

  /* ================= admin actions ================= */

  void adminPickRider(String orderId, String? riderNewId) {
    final o = orders.where((x) => x.id == orderId).firstOrNull;
    if (o == null) return;
    final prev = o.riderId;
    final r = riderNewId == null || riderNewId.isEmpty ? null : riders.where((x) => x.id == riderNewId).firstOrNull;
    if (prev != null && prev != (r?.id)) {
      addRNotif(rid: prev, type: 'info', orderId: o.id, title: 'Delivery reassigned', body: '${o.id} was given to another rider.');
    }
    if (r != null && r.id != prev) {
      assignTo(o, r);
    } else if (r == null) {
      o.riderId = null;
    }
    save();
    notifyListeners();
    toast(r != null ? 'Assigned to ${r.name}' : 'Rider removed');
  }

  String adminAdvance(Order o, int to) {
    if (o.cancelled || o.status >= to) return '';
    if (to >= 3 && o.riderId == null && !autoAssign(o)) {
      return 'need';
    }
    setStatus(o, to);
    notifyListeners();
    toast(STAGE[to]);
    return '';
  }

  void adminCancel(String id) {
    final o = orders.where((x) => x.id == id).firstOrNull;
    if (o == null || o.status >= 4) return;
    o.cancelled = true;
    o.byRider = true;
    o.issue = Issue(type: 'Cancelled by the station', text: '', ts: DateTime.now().millisecondsSinceEpoch);
    if (mine(o)) {
      addNotif(type: 'order', orderId: o.id, title: 'Order cancelled', body: 'Order ${o.id} was cancelled by the station.');
    }
    if (o.riderId != null) {
      addRNotif(rid: o.riderId, type: 'info', orderId: o.id, title: 'Delivery cancelled', body: '${o.id} was cancelled by the station.');
    }
    restoreStock(o);
    save();
    notifyListeners();
    toast('Order cancelled');
  }

  void updateProduct(String k, {required double price, required String desc, required bool active}) {
    products[k] = Product(price: (price * 100).round() / 100, desc: desc, active: active);
    save();
    notifyListeners();
    toast('${nameOf(k)} updated');
  }

  void toggleProduct(String k) {
    final p = products[k]!;
    p.active = !p.active;
    save();
    notifyListeners();
    toast('${nameOf(k)} ${p.active ? 'is available' : 'is hidden from customers'}');
  }

  String? updatePrices(String refillRaw, String buyRaw) {
    final r = nz(refillRaw), b = nz(buyRaw);
    if (r <= 0 || r > 9999 || b <= 0 || b > 9999) return 'Enter prices between ₱1 and ₱9,999.';
    products['refill']!.price = (r * 100).round() / 100;
    products['buy']!.price = (b * 100).round() / 100;
    save();
    notifyListeners();
    toast('Prices updated');
    return null;
  }

  String? restock(String k, String qtyRaw, String note) {
    final q = nz(qtyRaw);
    if (q <= 0 || q > 99999 || q != q.truncateToDouble()) return 'Enter a whole number greater than 0.';
    inv[k]!.qty += q.toInt();
    invLog('restock', k, q.toInt(), note.trim());
    save();
    notifyListeners();
    toast('Added ${q.toInt()} ${INV_DEFS[k]!.unit}');
    return null;
  }

  String? adjustStock(String k, String qtyRaw, String lowRaw) {
    final q = nz(qtyRaw), l = nz(lowRaw);
    if (q < 0 || q > 99999 || q != q.truncateToDouble() || l < 0 || l > 99999 || l != l.truncateToDouble()) {
      return 'Enter whole numbers, 0 or more.';
    }
    final diff = q.toInt() - inv[k]!.qty;
    inv[k]!.qty = q.toInt();
    inv[k]!.low = l.toInt();
    if (diff != 0) invLog('adjust', k, diff, 'Stock count');
    save();
    notifyListeners();
    toast('Inventory updated');
    return null;
  }

  String? saveRider({String? id, required String name, required String phone, required String vehicle, required String plate, required String email, required String pass}) {
    final e = email.trim().toLowerCase();
    if (name.trim().length < 2) return 'Enter the rider’s full name.';
    if (phone.trim().replaceAll(RegExp(r'\D'), '').length < 10) return 'Enter a mobile number with at least 10 digits.';
    if (!isEmail(e)) return 'Enter a valid email address.';
    if (pass.length < 4) return 'Choose a password with at least 4 characters.';
    if (riders.any((r) => r.email == e && r.id != id)) return 'Another rider already uses that email.';
    if (id != null) {
      final r = riders.where((x) => x.id == id).firstOrNull!;
      r.name = name.trim(); r.phone = phone.trim(); r.email = e; r.vehicle = vehicle; r.plate = plate.trim().toUpperCase();
      r.pass = pass;
    } else {
      riders.add(Rider(id: uid(), name: name.trim(), phone: phone.trim(), email: e, vehicle: vehicle, plate: plate.trim().toUpperCase(), pass: pass));
      autoAssignWaiting();
    }
    save();
    notifyListeners();
    toast(id != null ? 'Rider updated' : 'Rider added');
    return null;
  }

  void toggleRiderActive(String id) {
    final r = riders.where((x) => x.id == id).firstOrNull;
    if (r == null) return;
    r.active = r.active == false;
    if (!r.active) {
      for (final o in orders) {
        if (o.riderId == r.id && !o.cancelled && o.status < 3) o.riderId = null;
      }
      autoAssignWaiting();
    } else {
      autoAssignWaiting();
    }
    save();
    notifyListeners();
    toast('${r.name} ${r.active ? 'is active' : 'was deactivated'}');
  }

  void updateStation({required String name, required String phone, required String address, required String open, required String close, double? lat, double? lng, bool setPin = false}) {
    station
      ..name = name.trim()
      ..phone = phone.trim()
      ..address = address.trim()
      ..open = open
      ..close = close;
    if (setPin) {
      station.lat = lat;
      station.lng = lng;
    }
    save();
    notifyListeners();
    toast('Business details saved');
  }

  void toggleAccepting() {
    station.accepting = !station.accepting;
    save();
    notifyListeners();
    toast(station.accepting ? 'Station is taking orders' : 'Orders are paused');
  }

  void toggleAutoAssign() {
    station.autoAssign = !station.autoAssign;
    final int n = station.autoAssign ? autoAssignWaiting() : 0;
    save();
    notifyListeners();
    toast(station.autoAssign ? (n > 0 ? '$n waiting orders assigned' : 'Auto-assign is on') : 'Auto-assign is off');
  }

  void toggleAutoDeliver() {
    settings.autoDeliver = !settings.autoDeliver;
    save();
    notifyListeners();
    toast(settings.autoDeliver ? 'Demo orders progress automatically' : 'Demo orders wait for the admin and rider apps');
  }

  void toggleNotify() {
    settings.notify = !settings.notify;
    save();
    notifyListeners();
    toast(settings.notify ? 'Order updates are on' : 'Order updates are off');
  }

  String updateAdminProfile({required String name, required String email, String phone = ''}) {
    final e = email.trim().toLowerCase();
    if (name.trim().length < 2) return 'Enter your full name.';
    if (!isEmail(e)) return 'Enter a valid email address.';
    admin = Account(name: name.trim(), phone: phone.trim(), email: e);
    save();
    notifyListeners();
    toast('Profile updated');
    return '';
  }

  String updateCustomerProfile({required String name, required String email, String phone = ''}) {
    final e = email.trim().toLowerCase();
    if (name.trim().length < 2) return 'Enter your full name.';
    if (!isEmail(e)) return 'Enter a valid email address.';
    user = Account(name: name.trim(), phone: phone.trim(), email: e);
    save();
    notifyListeners();
    toast('Profile updated');
    return '';
  }

  /* ================= demo auto-progress (the `tick` loop) ================= */

  void tick() {
    if (session != true) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    var changed = false;
    for (final o in orders) {
      if (o.cancelled || o.status >= 4 || o.byRider || o.owner == 'other' || !settings.autoDeliver) continue;
      if (o.status == 2 && o.riderId == null) {
        autoAssign(o);
        if (o.riderId == null) continue;
      }
      if (o.status >= 2 && !settings.autoDeliver) continue;
      final last = (o.stamps.length > o.status && o.stamps[o.status] != null) ? o.stamps[o.status]! : o.createdAt;
      final needS = o.status < 2 ? DUR[o.status] : (o.status == 2 ? 30 : 40);
      if (now - last >= needS * 1000) {
        o.status += 1;
        while (o.stamps.length <= o.status) {
          o.stamps.add(null);
        }
        o.stamps[o.status] = now;
        changed = true;
        final t = noteText(o.status, o);
        if (t != null) addNotif(type: 'order', orderId: o.id, title: t.$1, body: t.$2);
      }
    }
    if (changed) {
      save();
      notifyListeners();
    }
  }

  /* ---- toast plumbing ---- */
  void Function(String msg)? onToast;
  void toast(String msg) => onToast?.call(msg);
}



