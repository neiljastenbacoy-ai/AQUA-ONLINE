/* Live tracking backend.
 *
 * Firebase sync is optional: when it is not configured yet the app still
 * tracks fully, but the rider marker is simulated (interpolated from the
 * order's status timestamps). The moment Firebase initializes successfully,
 * riders broadcast their real GPS and customers read it live.
 *
 * Firestore layout:
 *   riders/{riderId} -> { lat, lng, ts, orderId? }
 */

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import 'firebase_config.dart';

bool _ready = false;

/// True when Firebase initialized and Firestore sync is active.
bool get firebaseReady => _ready;

/// Safe boot — never throws. Falls back to simulation mode.
Future<void> bootFirebase() async {
  if (_ready) return;
  try {
    if (kIsWeb) {
      if (!FirebaseConfig.webConfigured) return;
      await Firebase.initializeApp(options: FirebaseConfig.webOptions);
    } else {
      // Android reads google-services.json; iOS reads GoogleService-Info.plist.
      await Firebase.initializeApp();
    }
    _ready = true;
  } catch (_) {
    _ready = false; // not configured / offline — simulation mode
  }
}

class RiderFix {
  final double lat;
  final double lng;
  final int ts; // ms epoch of the fix
  final String? orderId;
  const RiderFix({required this.lat, required this.lng, required this.ts, this.orderId});

  LatLng get point => LatLng(lat, lng);

  /// Fixes older than this are considered stale (device probably offline).
  bool get isFresh => DateTime.now().millisecondsSinceEpoch - ts < 90 * 1000;
}

/// Customer side — live stream of a rider's position, or null when Firebase
/// is not active (caller falls back to the simulated position).
Stream<RiderFix?>? watchRider(String riderId) {
  if (!_ready || riderId.isEmpty) return null;
  return FirebaseFirestore.instance
      .collection('riders')
      .doc(riderId)
      .snapshots()
      .map((d) {
    final v = d.data();
    if (v == null) return null;
    return RiderFix(
      lat: (v['lat'] as num?)?.toDouble() ?? 0,
      lng: (v['lng'] as num?)?.toDouble() ?? 0,
      ts: (v['ts'] as num?)?.toInt() ?? 0,
      orderId: v['orderId'] as String?,
    );
  });
}

/// Rider side — publishes this device's GPS to Firestore every few seconds
/// while there is an active delivery. No-op when Firebase is not active.
class RiderLocationBroadcaster {
  static final RiderLocationBroadcaster instance = RiderLocationBroadcaster._();
  RiderLocationBroadcaster._();

  StreamSubscription<Position>? _gps;
  Timer? _flush;
  String? _riderId;
  String? _orderId;
  Position? _last;

  bool get running => _riderId != null;

  void start({required String riderId, String? orderId}) {
    if (!_ready || riderId.isEmpty) return;
    _orderId = orderId;
    if (_riderId == riderId) return;
    stop();
    _riderId = riderId;
    _gps = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 10,
      ),
    ).listen((p) => _last = p);
    // Firestore writes are throttled independently of GPS fixes.
    _flush = Timer.periodic(const Duration(seconds: 5), (_) => _push());
  }

  /// Update which order the rider is currently delivering (optional marker).
  void delivering(String? orderId) => _orderId = orderId;

  void stop() {
    _gps?.cancel();
    _gps = null;
    _flush?.cancel();
    _flush = null;
    _last = null;
    _riderId = null;
    _orderId = null;
  }

  Future<void> _push() async {
    final p = _last;
    final rid = _riderId;
    if (p == null || rid == null || !_ready) return;
    try {
      await FirebaseFirestore.instance.collection('riders').doc(rid).set({
        'lat': p.latitude,
        'lng': p.longitude,
        'ts': DateTime.now().millisecondsSinceEpoch,
        'orderId': _orderId,
      }, SetOptions(merge: true));
    } catch (_) {
      // transient Firestore errors are fine — next tick retries
    }
  }
}
