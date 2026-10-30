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
    debugPrint('[AQUARUN tracking] Firebase ready — live GPS sync active');
  } catch (e) {
    debugPrint('[AQUARUN tracking] Firebase init failed: $e');
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

/// Rider side — publishes this device's GPS to Firestore every few seconds.
/// No-op when Firebase is not active.
///
/// It runs from the moment the rider signs in, not from the first delivery:
/// the customer's map has to show a rider the instant one is assigned, and a
/// rider who is parked at the station still has to keep reporting, otherwise
/// the fix ages out and the map goes back to "waiting".
class RiderLocationBroadcaster {
  static final RiderLocationBroadcaster instance = RiderLocationBroadcaster._();
  RiderLocationBroadcaster._();

  StreamSubscription<Position>? _gps;
  Timer? _flush;
  String? _riderId;
  String? _orderId;
  Position? _last;
  bool _firstWriteDone = false;
  int _pushedTs = 0;
  String? _pushedOrder;
  bool _starting = false;
  bool _asked = false;
  DateTime _lastAttempt = DateTime.fromMillisecondsSinceEpoch(0);

  bool get running => _riderId != null;

  /// Called with every fresh GPS fix on this phone — the app uses it to spot
  /// the rider reaching a customer's pin.
  void Function(double lat, double lng)? onFix;

  void _fix(Position p) {
    _last = p;
    try {
      onFix?.call(p.latitude, p.longitude);
    } catch (e) {
      debugPrint('[AQUARUN tracking] arrival check failed: $e');
    }
  }

  void start({required String riderId, String? orderId}) {
    if (!_ready || riderId.isEmpty) return;
    _orderId = orderId;
    if (_riderId == riderId) {
      // Same rider: never open a second stream, but do re-arm one that never
      // came up (permission answered late, service killed by the OS).
      _rearm(force: true);
      return;
    }
    stop();
    _riderId = riderId;
    _asked = false;
    _beginGps();
    // Firestore writes are throttled independently of GPS fixes.
    _flush = Timer.periodic(const Duration(seconds: 3), (_) => _push());
  }

  /// Brings the stream back if it is down. Permission is only ever *asked*
  /// once — after that we re-check silently, so a rider who grants location
  /// from Settings later starts reporting on their own.
  void _rearm({bool force = false}) {
    if (_riderId == null || _gps != null || _starting) return;
    if (!force &&
        DateTime.now().difference(_lastAttempt) < const Duration(seconds: 10)) {
      return;
    }
    _beginGps();
  }

  Future<void> _beginGps() async {
    if (_starting || _riderId == null) return;
    _starting = true;
    _lastAttempt = DateTime.now();
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied && !_asked) {
        // Fired from a login tap, so the system dialog can surface here.
        _asked = true;
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        debugPrint('[AQUARUN tracking] location permission denied — rider GPS off');
        return;
      }
      // One fix straight away so the customer sees the rider in seconds rather
      // than waiting for the first stream event, which on a parked phone can
      // take a while.
      try {
        final now = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 8),
        ));
        if (_riderId == null) return; // stopped while we were asking
        _fix(now);
        await _push();
      } catch (_) {/* no cached fix — the stream below will supply one */}
      if (_riderId == null) return;
      _gps = Geolocator.getPositionStream(
        locationSettings: AndroidSettings(
          accuracy: LocationAccuracy.best,
          // No distance filter on purpose: a rider parked at the gate must
          // keep sending fixes, or the timestamp ages out and the customer's
          // map drops back to "signal lost" while the rider is outside.
          intervalDuration: const Duration(seconds: 3),
          // Android throttles location to nothing once the app leaves the
          // foreground, and riders ride with the phone in a pocket. The
          // foreground service keeps the stream alive and shows the rider why
          // the app is still running.
          foregroundNotificationConfig: ForegroundNotificationConfig(
            notificationTitle: 'AQUARUN — sharing your location',
            notificationText: 'Customers can follow your position while this is on.',
            notificationIcon: const AndroidResource(name: 'ic_launcher', defType: 'mipmap'),
            enableWakeLock: true,
            setOngoing: true,
          ),
        ),
      ).listen(
        _fix,
        onError: (e) {
          debugPrint('[AQUARUN tracking] GPS stream error: $e');
          _gps?.cancel();
          _gps = null; // the flush timer re-arms it
        },
      );
    } catch (e) {
      debugPrint('[AQUARUN tracking] could not start GPS: $e');
    } finally {
      _starting = false;
    }
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
    _pushedTs = 0;
    _pushedOrder = null;
    _asked = false;
  }

  Future<void> _push() async {
    final rid = _riderId;
    if (rid == null || !_ready) return;
    // Self-heal: the stream can die silently (permission revoked, service
    // killed, hours in the background). Re-arm it instead of leaving the
    // customer staring at "waiting" for a rider who thinks they are sharing.
    _rearm();
    final p = _last;
    if (p == null) return;
    // Write the fix's own timestamp, not the wall clock. If the GPS goes quiet
    // (tunnel, building) the customer's map has to read "signal lost" instead
    // of a stopwatch that keeps ticking over a parked rider.
    final ts = p.timestamp.millisecondsSinceEpoch;
    if (ts == _pushedTs && _pushedOrder == _orderId) return;
    _pushedTs = ts;
    _pushedOrder = _orderId;
    try {
      await FirebaseFirestore.instance.collection('riders').doc(rid).set({
        'lat': p.latitude,
        'lng': p.longitude,
        'ts': ts,
        'orderId': _orderId,
      }, SetOptions(merge: true));
      if (_firstWriteDone == false) {
        _firstWriteDone = true;
        debugPrint('[AQUARUN tracking] first GPS write to Firestore ok');
      }
    } catch (e) {
      debugPrint('[AQUARUN tracking] Firestore write failed: $e');
      // transient Firestore errors are fine — next tick retries
    }
  }
}
