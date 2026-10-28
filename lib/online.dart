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

class OnlineSync {
  static final OnlineSync i = OnlineSync._();
  OnlineSync._();

  late AppState _s;
  bool get active => firebaseReady;

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
    final db = FirebaseFirestore.instance;

    _worldSub = db.collection('world').doc('main').snapshots().listen(_applyWorld,
        onError: (e) => debugPrint('[AQUA sync] world listener error: $e'));
    _ordersSub = db.collection('orders').snapshots().listen(_applyOrders,
        onError: (e) => debugPrint('[AQUA sync] orders listener error: $e'));
    _ridersSub = db.collection('riders').snapshots().listen(_applyRiders,
        onError: (e) => debugPrint('[AQUA sync] riders listener error: $e'));

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
          onError: (e) => debugPrint('[AQUA sync] user listener error: $e'));
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
        'seq': _s.seq,
        'anotifs': _s.anotifs.map((n) => n.toJson()).toList(),
        'rnotifs': _s.rnotifs.map((n) => n.toJson()).toList(),
      };

  Future<void> _push() async {
    if (!active || _wiping) return;
    final db = FirebaseFirestore.instance;
    try {
      // world
      final wj = _worldJson();
      if (_worldCache == null || _differs(_worldCache!, wj)) {
        await db.collection('world').doc('main').set(wj);
        _worldCache = wj;
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
      debugPrint('[AQUA sync] push failed: $e');
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
      _s.seq = (d['seq'] ?? _s.seq) as int;
      _s.anotifs =
          ((d['anotifs'] ?? []) as List).map((x) => Notif.fromJson(x)).toList();
      _s.rnotifs =
          ((d['rnotifs'] ?? []) as List).map((x) => Notif.fromJson(x)).toList();
      _s.updateUI();
    } catch (e) {
      debugPrint('[AQUA sync] world apply failed: $e');
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
          debugPrint('[AQUA sync] bad order doc ${doc.id}: $e');
        }
      }
      _orderCache
        ..clear()
        ..addAll(newCache);
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      _s.orders = list;
      _s.updateUI();
    } catch (e) {
      debugPrint('[AQUA sync] orders apply failed: $e');
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
          debugPrint('[AQUA sync] bad rider doc ${doc.id}: $e');
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
      debugPrint('[AQUA sync] riders apply failed: $e');
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
      _s.notifs =
          ((d['notifs'] ?? []) as List).map((x) => Notif.fromJson(x)).toList();
      final remoteName = (d['name'] ?? '') as String;
      if (remoteName.isNotEmpty) _s.user!.name = remoteName;
      _s.updateUI();
    } catch (e) {
      debugPrint('[AQUA sync] user apply failed: $e');
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
      debugPrint('[AQUA sync] fetchUser failed: $e');
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
      debugPrint('[AQUA sync] createUserDoc failed: $e');
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
      debugPrint('[AQUA sync] fetchRider failed: $e');
      return null;
    }
  }

  /// Transaction-safe order counter shared by all devices.
  Future<int> nextSeq() async {
    if (!active) return ++_s.seq;
    final ref = FirebaseFirestore.instance.collection('world').doc('main');
    try {
      return await FirebaseFirestore.instance.runTransaction((tx) async {
        final snap = await tx.get(ref);
        final cur = (snap.data()?['seq'] ?? _s.seq) as int;
        final next = cur + 1;
        tx.set(ref, {'seq': next}, SetOptions(merge: true));
        return next;
      });
    } catch (e) {
      debugPrint('[AQUA sync] nextSeq failed, using local: $e');
      return ++_s.seq;
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
      debugPrint('[AQUA sync] wipeAll failed: $e');
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
