import 'dart:math';

import 'package:flutter/services.dart';

import 'models.dart';

/* ---------- constants (ported from the HTML app) ---------- */
const double PRICE_REFILL = 25,
    PRICE_BUY = 150; // defaults; live values in state.products
const List<String> STAGE = [
  'Order Placed',
  'Confirmed',
  'Preparing',
  'Out for Delivery',
  'Delivered',
];
const List<String> BADGE = [
  'Pending',
  'Confirmed',
  'Preparing',
  'Out for Delivery',
  'Delivered',
  'Cancelled',
];
const List<int> DUR = [5, 7, 9, 14]; // demo seconds per active stage
const String KEY = 'aqua.customer.v1';
const Duration screenTransitionDuration = Duration(milliseconds: 220);

const Map<String, String> TITLES = {
  'order': 'Order Water',
  'cart': 'My Cart',
  'checkout': 'Checkout',
  'confirm': 'Order Placed',
  'orders': 'My Orders',
  'track': 'Track Delivery',
  'notifs': 'Notifications',
  'profile': 'My Profile',
  'settings': 'Settings',
  'rlist': 'My Deliveries',
  'rdetail': 'Delivery Details',
  'rroute': 'Map Route',
  'rhistory': 'Delivery History',
  'rearn': 'Earnings',
  'adetail': 'Order Details',
  'aorders': 'Orders',
  'adeliv': 'Deliveries',
  'aprod': 'Products & Inventory',
  'ainv': 'Inventory',
  'ausers': 'Users',
  'areports': 'Reports',
};

const Set<String> ROOT = {
  'home',
  'orders',
  'track',
  'profile',
  'settings',
  'rdash',
  'rlist',
  'rhistory',
  'rearn',
  'adash',
  'aorders',
  'adeliv',
  'aprod',
  'ainv',
  'ausers',
  'areports',
};

const List<String> AV_KEYS = ['available', 'break', 'offline'];
const Map<String, String> AV = {
  'available': 'Available',
  'break': 'On break',
  'offline': 'Offline',
};
const Map<String, String> AVTXT = {
  'available': 'You can receive new delivery assignments.',
  'break':
      'New assignments are paused. Finish the deliveries you already have.',
  'offline':
      'You will not be assigned new deliveries until you are available again.',
};
const List<String> RLBL = [
  'Pending',
  'In Progress',
  '',
  '',
  'Completed',
  'Cancelled',
];
const List<String> ISSUES = [
  'Customer not available',
  'Wrong or unclear address',
  'Cannot reach the customer',
  'Gallon damaged or leaking',
  'Vehicle problem',
  'Other',
];
const int RIDER_FEE_BASE = 20, RIDER_FEE_PER_GALLON = 5;

const Map<String, String> AVS = {
  'available': '4',
  'break': '0',
  'offline': '3',
};
const Map<String, InvItemDef> INV_DEFS = {
  'containers': InvItemDef(
    'Gallon Containers',
    'Used by Buy Gallon orders',
    'pcs',
  ),
  'water': InvItemDef(
    'Purified Water',
    'Used by Refill and Buy orders, 1 gallon each',
    'gallons',
  ),
};
const Map<String, String> LOGK = {
  'restock': 'Restocked',
  'adjust': 'Adjusted',
  'order': 'Used by order',
  'return': 'Returned',
};
const Map<String, String> PER = {
  'today': 'Today',
  '7d': '7 Days',
  '30d': '30 Days',
  'all': 'All Time',
};
const int DAY = 86400000;
const List<String> VEHICLES = ['Motorcycle', 'Tricycle', 'E-bike', 'Bicycle'];
const List<List<String>> SLIDES_DATA = [
  [
    'Clean & Safe Purified Water Delivered to You',
    'Order in a few taps and track every step.',
    'refill',
  ],
  [
    'Refill your empty gallon for {R}',
    'Hand over your empty gallon. We refill it with purified water.',
    'refill',
  ],
  [
    'No gallon yet? Buy one for {B}',
    'You get a new filled gallon with its container.',
    'buy',
  ],
];

// Admin is the one built-in account (no registration path); customers
// register themselves and riders are created by the admin in Users.
const String ADMIN_SEED_EMAIL = 'admin@aqua.ph';
const String ADMIN_SEED_PASS = 'aqua1234';

/* ---------- helpers ---------- */
final Random _rand = Random();
String uid() {
  const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
  return List.generate(7, (_) => chars[_rand.nextInt(chars.length)]).join();
}

String pl(num n, String w) => '$n $w${n == 1 ? '' : 's'}';

int hash(String s) {
  int h = 7;
  for (int i = 0; i < s.length; i++) {
    h = (h * 31 + s.codeUnitAt(i)) & 0xFFFFFFFF;
  }
  return h;
}

String peso(num n) {
  final v = n.toDouble();
  final s = v.toStringAsFixed(2);
  // insert thousands separators
  final parts = s.split('.');
  final intPart = parts[0].replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (m) => ',',
  );
  return '₱$intPart.${parts[1]}';
}

String _two(int n) => n < 10 ? '0$n' : '$n';

String tfmt(int ts) {
  final d = DateTime.fromMillisecondsSinceEpoch(ts);
  final h12 = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final ap = d.hour >= 12 ? 'PM' : 'AM';
  return '$h12:${_two(d.minute)} $ap';
}

const List<String> _MON = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];
const List<String> _MONL = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];
const List<String> _WD = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
const List<String> _WDL = [
  'Sunday',
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
];

String dfmt(int ts) {
  final d = DateTime.fromMillisecondsSinceEpoch(ts);
  return '${_MON[d.month - 1]} ${d.day}';
}

String placed(int ts) {
  final d = DateTime.fromMillisecondsSinceEpoch(ts);
  final h12 = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final ap = d.hour >= 12 ? 'PM' : 'AM';
  return '${_MON[d.month - 1]} ${d.day}, ${d.year}, $h12:${_two(d.minute)} $ap';
}

String placedLong(int ts) {
  final d = DateTime.fromMillisecondsSinceEpoch(ts);
  final h12 = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final ap = d.hour >= 12 ? 'PM' : 'AM';
  return '${_MONL[d.month - 1]} ${d.day}, ${d.year}, $h12:${_two(d.minute)} $ap';
}

String dayShort(DateTime d) => _WD[d.weekday % 7];
String dayLong(DateTime d) => _WDL[d.weekday % 7];

String ago(int ts) {
  final m = ((DateTime.now().millisecondsSinceEpoch - ts) / 60000).round();
  if (m < 1) return 'Just now';
  if (m < 60) return '$m min ago';
  final h = (m / 60).round();
  if (h < 24) return h == 1 ? '1 hr ago' : '$h hrs ago';
  final d = (h / 24).round();
  return d == 1 ? '1 day ago' : '$d days ago';
}

String oid(int ts, int n) {
  final d = DateTime.fromMillisecondsSinceEpoch(ts);
  final y = d.year.toString().substring(2);
  return 'AQ-$y${_two(d.month)}${_two(d.day)}-${('00$n').substring(('00$n').length - 3)}';
}

/// HTML-escape is unnecessary in Flutter, kept only where JS had it embedded.
bool isEmail(String s) => RegExp(r'^\S+@\S+\.\S+$').hasMatch(s);

String hh(String t) {
  final p = t.split(':');
  final h = int.tryParse(p[0]);
  if (h == null) return t;
  final m = p.length > 1 ? p[1] : '00';
  return '${(h % 12) == 0 ? 12 : (h % 12)}:$m ${h >= 12 ? 'PM' : 'AM'}';
}

List<String> slots() {
  final now = DateTime.now();
  final mins = now.hour * 60 + now.minute;
  String h12(int h) {
    final s = h >= 12 ? 'PM' : 'AM';
    final x = h % 12 == 0 ? 12 : h % 12;
    return '$x:00 $s';
  }

  final out = <String>[];
  for (final h in [9, 11, 13, 15, 17, 19]) {
    if (h * 60 > mins + 60) out.add('Today, ${h12(h)}–${h12(h + 2)}');
  }
  for (final h in [8, 10, 13, 15]) {
    out.add('Tomorrow, ${h12(h)}–${h12(h + 2)}');
  }
  return out.toSet().toList();
}

String timeLabel(String v) =>
    v == 'asap' ? 'As soon as possible · 30–45 min' : v;

int sod(int ts) {
  final d = DateTime.fromMillisecondsSinceEpoch(ts);
  return DateTime(d.year, d.month, d.day).millisecondsSinceEpoch;
}

bool sameDay(int tsA, int tsB) =>
    DateTime.fromMillisecondsSinceEpoch(tsA)
        .toIso8601String()
        .substring(0, 10) ==
    DateTime.fromMillisecondsSinceEpoch(tsB).toIso8601String().substring(0, 10);

double nz(String v) =>
    double.tryParse(v.replaceAll(',', '').trim()) ?? double.nan;

bool isWholeNum(double v) => v.isFinite && v == v.truncateToDouble();

Future<void> copyToClipboard(String text) =>
    Clipboard.setData(ClipboardData(text: text));

/* domain helpers that need Order */
int statusState(Order o) => o.cancelled ? 5 : o.status;
bool isActive(Order o) => !o.cancelled && o.status < 4;

String itemsText(Order o) =>
    o.items.map((i) => '${i.qty} × ${orderTypeName(i.type)}').join(', ');

String orderTypeName(String t) =>
    t == 'refill' ? 'Refill Gallon' : 'Buy Gallon';

int gallonsOf(Order o) => o.items.fold(0, (a, i) => a + i.qty);

int needContainers(Order o) =>
    o.items.where((i) => i.type == 'buy').fold(0, (a, i) => a + i.qty);
int needWater(Order o) => o.items.fold(0, (a, i) => a + i.qty);

String etaText(Order o) {
  if (o.time.isNotEmpty && o.time != 'asap') return o.time;
  final a = DateTime.fromMillisecondsSinceEpoch(o.createdAt + 30 * 60000);
  final b = DateTime.fromMillisecondsSinceEpoch(o.createdAt + 45 * 60000);
  return '${tfmt(a.millisecondsSinceEpoch)} – ${tfmt(b.millisecondsSinceEpoch)}';
}

String initialsOf(String? n) => ((n ?? '?').trim())
    .split(RegExp(r'\s+'))
    .where((w) => w.isNotEmpty)
    .take(2)
    .map((w) => w[0].toUpperCase())
    .join();

MapPoint pt(Order o) {
  final h = hash(o.id);
  return MapPoint(56.0 + (h % 250), 34.0 + ((h >>> 8) % 140));
}

class MapPoint {
  final double x, y;
  MapPoint(this.x, this.y);
}

String mapsUrl(Order o) =>
    'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(o.address.line)}';
String dirUrl(Order o) =>
    'https://www.google.com/maps/dir/?api=1&destination=${Uri.encodeComponent(o.address.line)}';
