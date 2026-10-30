/* Firestore sync layer — makes the whole app online.
 *
 * The app keeps its in-memory AppState exactly as before; every save() call
 * is diffed against the last-known server copy and only changed documents
 * are written. Real-time listeners apply server changes from other devices.
 *
 * Firestore layout:
 *   world/main      -> products, station, inv(+log), seq, anotifs, rnotifs
 *   users/{email}   -> customer account: name, phone, pass, addresses, notifs
 *   riders/{id}     -> rider profile (+ pass, availability) + live GPS fields
 *   orders/{id}     -> order documents
 *
 * Per-device state (session, role, cart, draft, settings, ui) never leaves
 * the device — it stays in SharedPreferences.
 */

import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart' hide Order;
import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';

import 'firebase_boot.dart';
import 'models.dart';
import 'state.dart';

/// Merges a server snapshot with the orders this device is still carrying.
///
/// A snapshot can arrive in the 400 ms between an order being placed (or moved)
/// and this device pushing it. Replacing the list wholesale there made the
/// order vanish locally, and because nothing local was left to push it never
/// came back. Orders the server has already acknowledged are trusted to be
/// authoritative (so a delete still propagates); only never-pushed ones are
/// kept.
List<Order> keepUnsyncedOrders({
  required List<Order> remote,
  required List<Order> local,
  required Set<String> acknowledged,
}) {
  final ids = <String>{for (final o in remote) o.id};
  final merged = List<Order>.of(remote);
  for (final o in local) {
    if (!ids.contains(o.id) && !acknowledged.contains(o.id)) merged.add(o);
  }
  merged.sort((a, b) => b.createdAt.compareTo(a.createdAt));
  return merged;
}

/// Unions two notification lists by id. The first list wins on a shared id, so
/// callers pass the server copy first and its read flags stick.
List<Notif> mergeNotifs(Iterable<Notif> a, Iterable<Notif> b, {int cap = 120}) {
  final byId = <String, Notif>{};
  for (final n in a) {
    byId[n.id] = n;
  }
  for (final n in b) {
    byId.putIfAbsent(n.id, () => n);
  }
  final list = byId.values.toList()..sort((x, y) => y.ts.compareTo(x.ts));
  if (list.length > cap) list.length = cap;
  return list;
}

/// Notes in the customer's cloud inbox that this phone has never seen — the
/// ones another device (the rider's, the station's) wrote. Those must ring the
/// phone; notes this phone made itself already rang when they were made.
/// Old or already-read notes stay quiet: a phone signing in should not replay
/// yesterday's deliveries as a burst of alerts.
List<Notif> cloudOnlyNotifs(Iterable<Notif> remote, Iterable<Notif> local,
    {required int now, int maxAgeMs = 15 * 60 * 1000}) {
  final seen = <String>{for (final n in local) n.id};
  return [
    for (final n in remote)
      if (!seen.contains(n.id) && !n.read && now - n.ts <= maxAgeMs) n,
  ]..sort((a, b) => a.ts.compareTo(b.ts));
}

class OnlineSync {
  static final OnlineSync i = OnlineSync._();
  OnlineSync._();

  late AppState _s;
  bool get active => firebaseReady;
  /// `_s` is late: nothing may touch it before [start] has run.
  bool _started = false;
  int _localSeq = 0;

  StreamSubscription? _worldSub;
  StreamSubscription? _ordersSub;
  StreamSubscription? _ridersSub;
  StreamSubscription? _meSub;
  String? _meSubEmail;

  Map<String, dynamic>? _worldCache;
  final Map<String, Map<String, dynamic>> _orderCache = {};
  final Map<String, Map<String, dynamic>> _riderCache = {};
  Map<String, dynamic>? _meCache;
  Timer? _pushTimer;
  bool _wiping = false;

  /// Attach listeners + initial session bindings. Call once after
  /// AppState.init() — no-op when Firebase isn't configured.
  Future<void> start(AppState s) async {
    _s = s;
    if (!active) return;
    _started = true;
    final db = FirebaseFirestore.instance;

    _worldSub = db.collection('world').doc('main').snapshots().listen(_applyWorld,
        onError: (e) => debugPrint('[AQUARUN sync] world listener error: $e'));
    _ordersSub = db.collection('orders').snapshots().listen(_applyOrders,
        onError: (e) => debugPrint('[AQUARUN sync] orders listener error: $e'));
    _ridersSub = db.collection('riders').snapshots().listen(_applyRiders,
        onError: (e) => debugPrint('[AQUARUN sync] riders listener error: $e'));

    // Fire-and-forget: a slow/offline network must never block app startup.
    _ensureWorld();
    _attachMe();
    requestPush();
  }

  /// (Re)bind the per-user listener after login / logout / role switch.
  void _attachMe() {
    final db = FirebaseFirestore.instance;
    final email = _s.role == 'customer' && _s.user != null ? _s.user!.email : null;
    final rid = _s.role == 'rider' ? _s.riderId : null;
    if (email == _meSubEmail && _meSub != null) return;
    _meSub?.cancel();
    _meSub = null;
    _meSubEmail = email;
    _meCache = null;
    if (email != null) {
      _meSub = db.collection('users').doc(email).snapshots().listen(_applyMe,
          onError: (e) => debugPrint('[AQUARUN sync] user listener error: $e'));
    } else if (rid != null && rid.isNotEmpty) {
      // Rider profile arrives via the riders collection listener; nothing extra.
    }
  }

  /// Called by AppState after login/logout so per-user bindings follow.
  void sessionChanged() {
    if (!active) return;
    _attachMe();
    requestPush();
  }

  Future<void> _ensureWorld() async {
    final ref = FirebaseFirestore.instance.collection('world').doc('main');
    final snap = await ref.get();
    if (!snap.exists) {
      // First ever boot — seed the world with the product/station defaults.
      await ref.set(_worldJson());
      _worldCache = _worldJson();
    }
  }

  /* ---------- push (device -> Firestore) ---------- */

  /// Debounced push; AppState.save() calls this after every mutation.
  void requestPush() {
    if (!active || _wiping) return;
    _pushTimer?.cancel();
    _pushTimer = Timer(const Duration(milliseconds: 400), _push);
  }

  Map<String, dynamic> _worldJson() => {
        'products': _s.products.map((k, v) => MapEntry(k, v.toJson())),
        'station': _s.station.toJson(),
        'inv': {
          'containers': _s.inv['containers']!.toJson(),
          'water': _s.inv['water']!.toJson(),
          'log': _s.invLogList.map((l) => l.toJson()).toList(),
        },
        // The highest counter this device knows, never its own stale copy:
        // pushing the local value used to rewind the shared counter, and two
        // orders then ended up with the same id.
        'seq': _highWater(),
        'anotifs': _s.anotifs.map((n) => n.toJson()).toList(),
        'rnotifs': _s.rnotifs.map((n) => n.toJson()).toList(),
      };

  /// Highest order counter this device can prove: its own value, the last
  /// server copy, and the numbers on the orders it already holds. Order ids end
  /// in that counter, so handing out a used one puts a new order on top of an
  /// old document — which is how a fresh order read "Delivered".
  int _highWater() {
    var top = _s.seq;
    final cached = _worldCache?['seq'];
    if (cached is int && cached > top) top = cached;
    for (final o in _s.orders) {
      final i = o.id.lastIndexOf('-');
      if (i < 0 || i == o.id.length - 1) continue;
      final n = int.tryParse(o.id.substring(i + 1));
      if (n != null && n > top) top = n;
    }
    return top;
  }

  /// The world document every device shares, with the fields this device has no
  /// authority over taken from the last server copy instead of a stale local
  /// one. Notes are unioned so one phone's push cannot drop another's.
  Map<String, dynamic> _worldPayload() {
    final wj = _worldJson();
    final cached = _worldCache;
    if (cached != null) {
      // Only the station edits its own profile, prices and product copy.
      if (_s.role != 'admin') {
        for (final k in ['products', 'station']) {
          if (cached[k] != null) wj[k] = cached[k];
        }
      }
      wj['anotifs'] = mergeNotifs(
              ((cached['anotifs'] ?? []) as List).map((x) => Notif.fromJson(x)),
              _s.anotifs)
          .map((n) => n.toJson())
          .toList();
      wj['rnotifs'] = mergeNotifs(
              ((cached['rnotifs'] ?? []) as List).map((x) => Notif.fromJson(x)),
              _s.rnotifs)
          .map((n) => n.toJson())
          .toList();
    }
    return wj;
  }

  Future<void> _push() async {
    if (!active || _wiping) return;
    final db = FirebaseFirestore.instance;
    try {
      // world — only once the current copy is known. A device that has not
      // received the snapshot yet has nothing trustworthy to write, and this is
      // a whole-document replace: guessing the counter here rewound it.
      if (_worldCache != null) {
        final wj = _worldPayload();
        if (_differs(_worldCache!, wj)) {
          await db.collection('world').doc('main').set(wj);
          _worldCache = wj;
        }
      }

      // orders (only changed docs)
      for (final o in _s.orders) {
        final j = o.toJson()..['id'] = o.id;
        final c = _orderCache[o.id];
        if (c == null || _differs(c, j)) {
          await db.collection('orders').doc(o.id).set(j);
          _orderCache[o.id] = j;
        }
      }

      // riders (only changed profiles; merge keeps live GPS fields intact)
      for (final r in _s.riders) {
        final j = r.toJson();
        final c = _riderCache[r.id];
        if (c == null || _differs(c, j)) {
          await db.collection('riders').doc(r.id).set(j, SetOptions(merge: true));
          _riderCache[r.id] = Map<String, dynamic>.from(j);
        }
      }

      // own customer account
      final me = _ownUserJson();
      if (me != null) {
        final c = _meCache;
        if (c == null || _differs(c, me)) {
          await db.collection('users').doc(_s.user!.email).set(me, SetOptions(merge: true));
          _meCache = me;
        }
      }
    } catch (e) {
      debugPrint('[AQUARUN sync] push failed: $e');
    }
  }

  Map<String, dynamic>? _ownUserJson() {
    if (_s.role != 'customer' || _s.user == null) return null;
    return {
      'name': _s.user!.name,
      'phone': _s.user!.phone,
      'email': _s.user!.email,
      'addresses': _s.addresses.map((a) => a.toJson()).toList(),
      'notifs': _s.notifs.map((n) => n.toJson()).toList(),
    };
  }

  bool _differs(Map<String, dynamic> a, Map<String, dynamic> b) {
    final ja = jsonEncodeSafe(a);
    final jb = jsonEncodeSafe(b);
    return ja != jb;
  }

  /// Canonical JSON with sorted keys, so maps from Firestore (arbitrary key
  /// order) compare equal to locally built ones.
  String jsonEncodeSafe(Object? o) {
    try {
      return jsonEncode(_canonical(o));
    } catch (_) {
      return o.toString();
    }
  }

  Object? _canonical(Object? o) {
    if (o is Map) {
      final keys = o.keys.map((k) => k.toString()).toList()..sort();
      return {for (final k in keys) k: _canonical(o[k])};
    }
    if (o is List) return o.map(_canonical).toList();
    return o;
  }

  /* ---------- apply (Firestore -> device) ---------- */

  void _applyWorld(DocumentSnapshot<Map<String, dynamic>> snap) {
    if (!snap.exists) return;
    final d = snap.data()!;
    _worldCache = d;
    try {
      _s.products = {
        'refill': Product.fromJson((d['products'] ?? {})['refill'] ?? {}),
        'buy': Product.fromJson((d['products'] ?? {})['buy'] ?? {}),
      };
      _s.station = Station.fromJson(d['station'] ?? {});
      final invJson = d['inv'] as Map<String, dynamic>?;
      if (invJson != null) {
        _s.inv = {
          'containers': InvItem.fromJson(invJson['containers'] ?? {}),
          'water': InvItem.fromJson(invJson['water'] ?? {}),
        };
        _s.invLogList =
            ((invJson['log'] ?? []) as List).map((x) => InvLog.fromJson(x)).toList();
      }
      _s.seq = (d['seq'] as int?) ?? _s.seq;
      if (_s.seq < _highWater()) _s.seq = _highWater();
      // Union, not replace: this device may be holding a note it has not pushed
      // yet, and a note the other phone wrote has to survive here too.
      final remoteA =
          ((d['anotifs'] ?? []) as List).map((x) => Notif.fromJson(x)).toList();
      final remoteR =
          ((d['rnotifs'] ?? []) as List).map((x) => Notif.fromJson(x)).toList();
      // A note another device just wrote into the shared admin/rider inbox must
      // ring here too, the way the customer's own inbox rings in [_applyMe]:
      // only fresh, unread, recent notes this phone has not already seen. A
      // rider rings only for their own assignments. Both sets are computed
      // before the merge, while the local copy is still the "seen" reference.
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final freshA = _s.role == 'admin'
          ? cloudOnlyNotifs(remoteA, _s.anotifs, now: nowMs)
          : const <Notif>[];
      final freshR = _s.role == 'rider' && _s.rider != null
          ? cloudOnlyNotifs(remoteR, _s.rnotifs, now: nowMs)
              .where((n) => n.rid == _s.rider!.id)
              .toList()
          : const <Notif>[];
      _s.anotifs = mergeNotifs(remoteA, _s.anotifs, cap: 60);
      _s.rnotifs = mergeNotifs(remoteR, _s.rnotifs);
      _s.updateUI();
      for (final n in freshA) {
        _s.ringFromCloud(n);
      }
      for (final n in freshR) {
        _s.ringFromCloud(n);
      }
    } catch (e) {
      debugPrint('[AQUARUN sync] world apply failed: $e');
    }
  }

  void _applyOrders(QuerySnapshot<Map<String, dynamic>> snap) {
    try {
      final list = <Order>[];
      final newCache = <String, Map<String, dynamic>>{};
      for (final doc in snap.docs) {
        final j = doc.data();
        newCache[doc.id] = j;
        try {
          list.add(Order.fromJson(j));
        } catch (e) {
          debugPrint('[AQUARUN sync] bad order doc ${doc.id}: $e');
        }
      }
      // What the server knows before this snapshot: anything outside it is
      // either brand new on this device (never pushed yet) or deleted there.
      final acknowledged = Set<String>.of(_orderCache.keys);
      _orderCache
        ..clear()
        ..addAll(newCache);
      _s.orders = keepUnsyncedOrders(
          remote: list, local: _s.orders, acknowledged: acknowledged);
      _s.updateUI();
      _s.ordersSynced();
    } catch (e) {
      debugPrint('[AQUARUN sync] orders apply failed: $e');
    }
  }

  void _applyRiders(QuerySnapshot<Map<String, dynamic>> snap) {
    try {
      final list = <Rider>[];
      final newCache = <String, Map<String, dynamic>>{};
      for (final doc in snap.docs) {
        final j = doc.data();
        newCache[doc.id] = j;
        try {
          final r = Rider.fromJson(j);
          r.id = doc.id; // doc id is the rider id
          list.add(r);
        } catch (e) {
          debugPrint('[AQUARUN sync] bad rider doc ${doc.id}: $e');
        }
      }
      _riderCache
        ..clear()
        ..addAll(newCache);
      _s.riders = list;
      if (_s.role == 'rider') {
        _s.rider = list.where((r) => r.id == _s.riderId).firstOrNull ?? _s.rider;
      }
      _s.updateUI();
    } catch (e) {
      debugPrint('[AQUARUN sync] riders apply failed: $e');
    }
  }

  /// Prepends a notification to another account's inbox.
  ///
  /// Customer notifications are written by the customer's own device — it is
  /// the only writer of its document. The one case that has to cross devices
  /// is a stage change: the rider or the station moves the order, so the note
  /// has to be dropped into the customer's inbox from here.
  Future<void> notifyCustomer(String email, Notif n) async {
    if (!_started || !active || email.isEmpty) return;
    final ref = FirebaseFirestore.instance.collection('users').doc(email);
    try {
      await FirebaseFirestore.instance.runTransaction((tx) async {
        final snap = await tx.get(ref);
        if (!snap.exists) return;
        final list = ((snap.data()?['notifs'] ?? []) as List)
            .map((x) => Notif.fromJson(x))
            .toList();
        // The same stage twice is one note (a double tap, a retry).
        if (list.any((x) => x.orderId == n.orderId && x.title == n.title)) return;
        list.insert(0, n);
        if (list.length > 60) list.length = 60;
        tx.set(ref, {'notifs': list.map((x) => x.toJson()).toList()},
            SetOptions(merge: true));
      });
      if (_s.user?.email == email) _meCache = null; // our own inbox, refetch it
    } catch (e) {
      debugPrint('[AQUARUN sync] notifyCustomer failed: $e');
    }
  }

  void _applyMe(DocumentSnapshot<Map<String, dynamic>> snap) {
    if (_s.role != 'customer' || _s.user == null) return;
    if (!snap.exists) return;
    final d = snap.data()!;
    _meCache = d;
    try {
      _s.addresses =
          ((d['addresses'] ?? []) as List).map((x) => Address.fromJson(x)).toList();
      // Union, not replace: a note the rider sent can land here while this
      // device is still holding its own copy, and losing it would mean the
      // customer never hears that their water moved.
      final remote = ((d['notifs'] ?? []) as List).map((x) => Notif.fromJson(x)).toList();
      final fresh = cloudOnlyNotifs(remote, _s.notifs,
          now: DateTime.now().millisecondsSinceEpoch);
      _s.notifs = mergeNotifs(remote, _s.notifs, cap: 60);
      final remoteName = (d['name'] ?? '') as String;
      if (remoteName.isNotEmpty) _s.user!.name = remoteName;
      _s.updateUI();
      fresh.forEach(_s.ringFromCloud);
    } catch (e) {
      debugPrint('[AQUARUN sync] user apply failed: $e');
    }
  }

  /* ---------- account lookups (login / register) ---------- */

  /// Returns the stored password for a customer email, or null if unknown.
  Future<Map<String, dynamic>?> fetchUser(String email) async {
    if (!active) return null;
    try {
      final snap = await FirebaseFirestore.instance.collection('users').doc(email).get();
      return snap.data();
    } catch (e) {
      debugPrint('[AQUARUN sync] fetchUser failed: $e');
      return null;
    }
  }

  Future<bool> userExists(String email) async {
    if (!active) return false;
    final snap =
        await FirebaseFirestore.instance.collection('users').doc(email).get();
    return snap.exists;
  }

  /// Creates the customer account document (after local register succeeded).
  Future<void> createUserDoc({
    required String email,
    required String name,
    required String phone,
    required String pass,
  }) async {
    if (!active) return;
    try {
      await FirebaseFirestore.instance.collection('users').doc(email).set({
        'name': name,
        'phone': phone,
        'email': email,
        'pass': pass,
        'addresses': [],
        'notifs': [],
      });
      _meCache = null; // force a push of any local extras on next save
    } catch (e) {
      debugPrint('[AQUARUN sync] createUserDoc failed: $e');
    }
  }

  /// Returns the rider doc (id + data) for an email, or null.
  Future<MapEntry<String, Map<String, dynamic>>?> fetchRiderByEmail(
      String email) async {
    if (!active) return null;
    try {
      final q = await FirebaseFirestore.instance
          .collection('riders')
          .where('email', isEqualTo: email)
          .limit(1)
          .get();
      if (q.docs.isEmpty) return null;
      return MapEntry(q.docs.first.id, q.docs.first.data());
    } catch (e) {
      debugPrint('[AQUARUN sync] fetchRider failed: $e');
      return null;
    }
  }

  /// Transaction-safe order counter shared by all devices.
  Future<int> nextSeq() async {
    // Before [start] there is no AppState to read a counter from; a local one
    // still keeps two orders made in the same millisecond apart.
    if (!_started) return ++_localSeq;
    if (!active) return ++_s.seq;
    final ref = FirebaseFirestore.instance.collection('world').doc('main');
    try {
      return await FirebaseFirestore.instance.runTransaction((tx) async {
        final snap = await tx.get(ref);
        final doc = (snap.data()?['seq'] as int?) ?? 0;
        final local = _highWater();
        // Never hand out a number below what either side has already used, even
        // if the shared counter was rewound by an older build.
        final cur = doc > local ? doc : local;
        final next = cur + 1;
        tx.set(ref, {'seq': next}, SetOptions(merge: true));
        return next;
      });
    } catch (e) {
      debugPrint('[AQUARUN sync] nextSeq failed, using local: $e');
      return _highWater() + 1;
    }
  }

  /// Admin "Reset data" — clears every shared collection.
  Future<void> wipeAll() async {
    if (!active) return;
    _wiping = true;
    final db = FirebaseFirestore.instance;
    try {
      await _deleteCollection(db.collection('orders'));
      await _deleteCollection(db.collection('users'));
      await _deleteCollection(db.collection('riders'));
      await db.collection('world').doc('main').delete();
      _orderCache.clear();
      _riderCache.clear();
      _worldCache = null;
      _meCache = null;
    } catch (e) {
      debugPrint('[AQUARUN sync] wipeAll failed: $e');
    }
    _wiping = false;
    await _ensureWorld();
  }

  Future<void> _deleteCollection(CollectionReference<Map<String, dynamic>> ref) async {
    var snap = await ref.limit(300).get();
    while (snap.docs.isNotEmpty) {
      final batch = db_batch();
      for (final d in snap.docs) {
        batch.delete(d.reference);
      }
      await batch.commit();
      if (snap.docs.length < 300) break;
      snap = await ref.limit(300).get();
    }
  }

  WriteBatch db_batch() => FirebaseFirestore.instance.batch();

  void dispose() {
    _worldSub?.cancel();
    _ordersSub?.cancel();
    _ridersSub?.cancel();
    _meSub?.cancel();
    _pushTimer?.cancel();
  }
}
