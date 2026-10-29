/* Real-map tracking widgets (OpenStreetMap via flutter_map — free, no API key).
 *
 * - openPinPickerPage  : full-screen drag-to-aim pin picker (addresses, station)
 * - DeliveryTrackMap   : customer's live map — rider's fix → the door
 * - RouteStopMap       : rider's route map — own GPS + numbered delivery pins
 * - simulatedRiderPos  : simulation-mode rider position (no Firebase needed)
 */

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import 'icons.dart';
import 'models.dart';
import 'palette.dart';
import 'widgets.dart';

const String _tiles = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
const String _ua = 'com.example.aqua';

/* ================= simulation ================= */

/// Delivery leg duration in the demo timeline (matches tick(): status 3 -> 4
/// takes 40s). The rider travels station→pin over this window.
const int _deliveryMs = 40 * 1000;

double _ease(double t) {
  t = t.clamp(0.0, 1.0);
  return t * t * (3 - 2 * t); // smoothstep — starts and ends gently
}

/// Simulated rider position between station and the delivery pin, derived
/// only from the order's status stamps — deterministic, nothing persisted.
LatLng? simulatedRiderPos({
  required LatLng station,
  required Order o,
  required int now,
}) {
  if (!o.address.hasPin) return null;
  final dest = LatLng(o.address.lat!, o.address.lng!);
  final start = o.stamps.length > 3 ? o.stamps[3] : null;
  if (o.status >= 4) return dest; // delivered — rider shown at the pin
  if (start == null || start <= 0) return station; // not out yet — at station
  final t = _ease((now - start) / _deliveryMs);
  return LatLng(
    station.latitude + (dest.latitude - station.latitude) * t,
    station.longitude + (dest.longitude - station.longitude) * t,
  );
}

/* ================= pin picker ================= */

/// A confirmed map pin plus the street address resolved from it
/// (empty strings when the reverse geocode found nothing).
class DroppedPin {
  final LatLng point;
  final String street, brgy, city;
  const DroppedPin(this.point, {this.street = '', this.brgy = '', this.city = ''});
}

/// Reverse geocode a coordinate via OSM Nominatim (free, no API key,
/// same data source as the map tiles). Returns null on any failure —
/// callers fall back to just the coordinates.
Future<DroppedPin?> reverseGeocode(LatLng p) async {
  try {
    final uri = Uri.https('nominatim.openstreetmap.org', '/reverse', {
      'lat': p.latitude.toStringAsFixed(7),
      'lon': p.longitude.toStringAsFixed(7),
      'format': 'json',
      'zoom': '18',
      'addressdetails': '1',
    });
    final res = await http.get(uri, headers: {
      // Nominatim usage policy requires an identifying User-Agent.
      'User-Agent': 'AQUARUN/1.0 (com.example.aqua)',
    }).timeout(const Duration(seconds: 8));
    if (res.statusCode != 200) return null;
    final a = (jsonDecode(res.body) as Map<String, dynamic>)['address']
        as Map<String, dynamic>?;
    if (a == null) return null;
    String pick(List<String> keys) =>
        keys.map((k) => a[k]).firstWhere((v) => v != null && v.toString().isNotEmpty,
            orElse: () => '') as String;
    final house = pick(['house_number']);
    final road = pick(['road', 'pedestrian', 'residential', 'footway']);
    final street = [if (house.isNotEmpty) house, if (road.isNotEmpty) road]
        .join(' ')
        .trim();
    final brgy = pick(['suburb', 'village', 'neighbourhood', 'quarter', 'city_district']);
    final city = pick(['city', 'municipality', 'town', 'county']);
    return DroppedPin(p, street: street, brgy: brgy, city: city);
  } catch (_) {
    return null;
  }
}

/// Opens the full-screen map picker. Returns the chosen coordinate with the
/// resolved address, or null if the user backed out.
///
/// Pass `resolveAddress: false` when the caller types the address itself: the
/// picker then returns the coordinate straight away instead of waiting on a
/// Nominatim lookup whose result would be thrown away.
Future<DroppedPin?> openPinPickerPage(BuildContext context,
    {LatLng? initial, bool resolveAddress = true}) {
  return Navigator.of(context).push<DroppedPin>(
    MaterialPageRoute(
      builder: (_) =>
          _PinPickerPage(initial: initial, resolveAddress: resolveAddress),
    ),
  );
}

class _PinPickerPage extends StatefulWidget {
  final LatLng? initial;
  final bool resolveAddress;
  const _PinPickerPage({this.initial, this.resolveAddress = true});
  @override
  State<_PinPickerPage> createState() => _PinPickerPageState();
}

class _PinPickerPageState extends State<_PinPickerPage> {
  final MapController _map = MapController();
  late LatLng _center = widget.initial ?? const LatLng(8.6069, 124.8222);
  String _hint = 'Drag the map so the pin sits on the delivery spot.';
  bool _resolving = false;

  Future<void> _useMyLocation() async {
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        setState(() => _hint = 'Location permission is off — enable it to use this.');
        return;
      }
      final p = await Geolocator.getCurrentPosition();
      _map.move(LatLng(p.latitude, p.longitude), 17);
    } catch (_) {
      setState(() => _hint = 'Could not get your location. Try again outdoors.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    Widget page = Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 6, 18, 6),
            child: Row(children: [
              IconButton(
                icon: Icon(Icons.arrow_back, color: p.ink),
                onPressed: () => Navigator.of(context).pop(),
              ),
              Expanded(
                child: Text('Set delivery pin',
                    style: tx(context, 18, disp: true, w: FontWeight.w700)),
              ),
            ]),
          ),
          Expanded(
            child: Stack(children: [
              FlutterMap(
                mapController: _map,
                options: MapOptions(
                  initialCenter: _center,
                  initialZoom: widget.initial == null ? 13 : 17,
                  onPositionChanged: (cam, hasGesture) {
                    if (hasGesture) setState(() => _center = cam.center);
                  },
                ),
                children: [
                  TileLayer(urlTemplate: _tiles, userAgentPackageName: _ua),
                ],
              ),
              // Fixed center pin — the map moves under it.
              IgnorePointer(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.location_on,
                          size: 48, color: p.danger, shadows: const [
                        Shadow(color: Color(0x55000000), blurRadius: 6, offset: Offset(0, 3)),
                      ]),
                      const SizedBox(height: 2),
                    ],
                  ),
                ),
              ),
              Positioned(
                right: 14,
                bottom: 14,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: p.card,
                    shape: BoxShape.circle,
                    border: Border.all(color: p.line),
                  ),
                  child: IconButton(
                    tooltip: 'Use my current location',
                    icon: Icon(Icons.my_location, color: p.link),
                    onPressed: _useMyLocation,
                  ),
                ),
              ),
            ]),
          ),
          Container(
            color: p.card,
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
            child: SafeArea(
              top: false,
              child: VGap([
                Text(_hint, style: tx(context, 13, color: p.muted, h: 1.4)),
                Btn(
                  _resolving ? 'Looking up address…' : 'Confirm pin location',
                  icon: 'pin',
                  onPressed: _resolving
                      ? null
                      : () async {
                          if (!widget.resolveAddress) {
                            Navigator.of(context).pop(DroppedPin(_center));
                            return;
                          }
                          setState(() => _resolving = true);
                          final pin = await reverseGeocode(_center);
                          if (!mounted || !context.mounted) return;
                          Navigator.of(context).pop(
                            pin ?? DroppedPin(_center),
                          );
                        },
                ),
              ]),
            ),
          ),
        ]),
      ),
    );
    // This page lives above the shell, so it has to bring its own frame and
    // status-bar styling instead of inheriting them.
    if (framedLayout(context)) {
      page = phoneFrame(context, child: page, background: p.bg);
    }
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: p.isDark ? Brightness.light : Brightness.dark,
        statusBarBrightness: p.isDark ? Brightness.dark : Brightness.light,
        systemNavigationBarColor: p.bg,
        systemNavigationBarIconBrightness:
            p.isDark ? Brightness.light : Brightness.dark,
      ),
      child: page,
    );
  }
}

/* ================= shared marker builders ================= */

/// One tile per role — shop, door, rider — so a three-pin map reads without
/// hunting. The white border keeps a pin visible over pale map tiles and
/// separates the rider from the door pin once they meet.
Widget _mapTile(
  BuildContext context, {
  required String icon,
  required Color bg,
  double size = 34,
  bool square = false,
  double iconScale = .52,
  double stroke = 1.9,
}) {
  return Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: bg,
      shape: square ? BoxShape.rectangle : BoxShape.circle,
      borderRadius: square ? BorderRadius.circular(size * .28) : null,
      border: Border.all(color: Colors.white, width: 2),
      boxShadow: const [
        BoxShadow(color: Color(0x33000000), blurRadius: 6, offset: Offset(0, 2)),
      ],
    ),
    alignment: Alignment.center,
    child: Ic(icon, size: size * iconScale, color: Colors.white, strokeWidth: stroke),
  );
}

/// The station: the store the water leaves from.
Widget _stationMarker(BuildContext context) =>
    _mapTile(context, icon: 'store', bg: Pal.of(context).navy, square: true);

/// The customer's door: where the water has to arrive.
Widget _destMarker(BuildContext context) =>
    _mapTile(context, icon: 'home', bg: Pal.of(context).danger, square: true);

/// The rider on the road — a scooter, not a van: it is what actually turns up
/// at the gate, and it tells the rider pin apart from the delivery icon used
/// elsewhere in the app. Drawn larger and heavier than the address pins: a
/// fine-lined scooter turns to mush at the 18px the other tiles give it.
Widget _riderMarker(BuildContext context) => _mapTile(context,
    icon: 'scooter', bg: Pal.of(context).blue, size: 38, iconScale: .66, stroke: 2.3);

/// The rider's own GPS fix — the same scooter the customer sees, so both
/// sides of the delivery are looking at the same thing.
Widget _meMarker(BuildContext context) =>
    _mapTile(context, icon: 'scooter', bg: Pal.of(context).blue, size: 34, iconScale: .66, stroke: 2.3);

/// Key printed under a map: the same tile and colour as the pin, so nobody has
/// to guess what the icons mean.
class MapLegend extends StatelessWidget {
  /// (icon name, label, tile colour)
  final List<(String, String, Color)> entries;
  const MapLegend(this.entries, {super.key});

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return Wrap(spacing: 14, runSpacing: 6, children: [
      for (final e in entries)
        RowW([
          _mapTile(context, icon: e.$1, bg: e.$3, size: 20, square: true),
          Text(e.$2,
              style: tx(context, 12, w: FontWeight.w700, color: p.muted)),
        ], gap: 6),
    ]);
  }
}

/* ================= customer live map ================= */

class DeliveryTrackMap extends StatefulWidget {
  final LatLng station;
  final LatLng dest;
  final LatLng? rider; // null hides the rider marker
  final double height;
  /// Prints the icon key under the map (station / drop-off / rider).
  final bool legend;
  const DeliveryTrackMap({
    super.key,
    required this.station,
    required this.dest,
    this.rider,
    this.height = 240,
    this.legend = true,
  });
  @override
  State<DeliveryTrackMap> createState() => _DeliveryTrackMapState();
}

class _DeliveryTrackMapState extends State<DeliveryTrackMap> {
  final MapController _map = MapController();
  LatLng? _fittedDest; // destination the current framing was built for
  LatLng? _fittedRider; // rider position at that moment
  int _fitRetries = 0;

  /// The map is built before the first GPS fix arrives, so framing has to be
  /// redone when the rider appears — otherwise a rider a few kilometres out
  /// starts off-screen and the card looks empty. After that it only follows
  /// again after a big jump, never on every fix.
  bool get _needsFit {
    if (_fittedDest != widget.dest) return true;
    final r = widget.rider;
    if (r == null) return false;
    if (_fittedRider == null) return true;
    return metersBetween(_fittedRider!, r) > 500;
  }

  void _fit() {
    final r = widget.rider;
    // Frame the whole story while the rider is near the station, because the
    // store, the door and the scooter all fit. Once the rider is 2 km out,
    // framing the start would shrink the part that matters, so keep it on the
    // leg still to ride (rider → door).
    final coords = r == null
        ? [widget.station, widget.dest]
        : (metersBetween(widget.station, r) > 2000
            ? [r, widget.dest]
            : [widget.station, widget.dest, r]);
    final ok = _map.fitCamera(CameraFit.coordinates(
      coordinates: coords,
      maxZoom: 16,
      padding: const EdgeInsets.all(52),
    ));
    if (ok) {
      _fittedDest = widget.dest;
      _fittedRider = r;
    } else if (_fitRetries < 10) {
      // fitCamera returns false until the map has built its first camera;
      // retry a few frames so the first view is always framed.
      _fitRetries++;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _fit();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _needsFit) {
        _fitRetries = 0;
        _fit();
      }
    });
    // The line is the leg still to ride. Anchoring it at the station made the
    // map say "the rider is still at the store" even after the fix arrived, so
    // it starts at the rider as soon as there is one; with no fix at all the
    // station leg is the only honest thing left to draw.
    final rider = widget.rider;
    final leg = rider == null
        ? [widget.station, widget.dest]
        : (metersBetween(rider, widget.dest) <= 15
            ? null // already at the door — there is no leg left
            : [rider, widget.dest]);
    final map = SizedBox(
      height: widget.height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Stack(children: [
          FlutterMap(
            mapController: _map,
            options: MapOptions(
              initialCenter: LatLng(
                (widget.station.latitude + widget.dest.latitude) / 2,
                (widget.station.longitude + widget.dest.longitude) / 2,
              ),
              initialZoom: 14,
            ),
            children: [
              TileLayer(urlTemplate: _tiles, userAgentPackageName: _ua),
              if (leg != null)
                PolylineLayer(polylines: [
                  Polyline(
                    points: leg,
                    strokeWidth: 3,
                    color: Pal.mixAlpha(p.blue, 0.55),
                    pattern: StrokePattern.dashed(segments: [6, 6]),
                  ),
                ]),
              MarkerLayer(markers: [
                Marker(
                    point: widget.station,
                    width: 38,
                    height: 38,
                    child: _stationMarker(context)),
                Marker(
                    point: widget.dest,
                    width: 38,
                    height: 38,
                    child: _destMarker(context)),
                if (rider != null)
                  Marker(
                      point: rider,
                      width: 40,
                      height: 40,
                      child: _riderMarker(context)),
              ]),
            ],
          ),
          Positioned(
            right: 8,
            top: 8,
            child: _mapButton(context, Icons.center_focus_strong,
                'Frame the whole route', () {
              setState(() {
                _fittedDest = null;
                _fittedRider = null;
                _fitRetries = 0;
              });
            }),
          ),
          const Positioned(left: 6, bottom: 4, child: _Attribution()),
        ]),
      ),
    );
    if (!widget.legend) return map;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        map,
        const SizedBox(height: 8),
        MapLegend([
          ('store', 'Station', p.navy),
          ('home', 'Drop-off', p.danger),
          if (widget.rider != null) ('scooter', 'Rider', p.blue),
        ]),
      ],
    );
  }
}

/// Small round button that floats over a map.
Widget _mapButton(BuildContext context, IconData icon, String tip, VoidCallback onTap) {
  final p = Pal.of(context);
  return DecoratedBox(
    decoration: BoxDecoration(
      color: p.card.withValues(alpha: .94),
      shape: BoxShape.circle,
      border: Border.all(color: p.line),
      boxShadow: const [
        BoxShadow(color: Color(0x22000000), blurRadius: 6, offset: Offset(0, 2)),
      ],
    ),
    child: IconButton(
      tooltip: tip,
      visualDensity: VisualDensity.compact,
      iconSize: 20,
      color: p.link,
      icon: Icon(icon),
      onPressed: onTap,
    ),
  );
}

/// The OSM tile policy requires the credit to sit on the map itself.
class _Attribution extends StatelessWidget {
  const _Attribution();
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .82),
          borderRadius: BorderRadius.circular(3),
        ),
        child: const Text('© OpenStreetMap contributors',
            style: TextStyle(
                fontSize: 8.5,
                height: 1.2,
                color: Color(0xFF3A3A3A),
                fontWeight: FontWeight.w600)),
      );
}

/* ================= rider route map ================= */

class RouteStop {
  final LatLng point;
  final int n;
  final bool focused;
  const RouteStop(this.point, this.n, {this.focused = false});
}

class RouteStopMap extends StatefulWidget {
  final LatLng station;
  final List<RouteStop> stops;
  final LatLng? me;
  final double height;
  /// Prints the icon key under the map (station / stops / you).
  final bool legend;
  const RouteStopMap({
    super.key,
    required this.station,
    required this.stops,
    this.me,
    this.height = 260,
    this.legend = true,
  });
  @override
  State<RouteStopMap> createState() => _RouteStopMapState();
}

class _RouteStopMapState extends State<RouteStopMap> {
  final MapController _map = MapController();
  int? _fittedFor;
  int _fitRetries = 0;

  LatLng? _fittedMe;

  void _fit() {
    final pts = [
      widget.station,
      if (widget.me != null) widget.me!,
      ...widget.stops.map((s) => s.point),
    ];
    if (pts.length < 2) return;
    // When one stop is focused ("View on Map"), frame the route from the
    // station to THAT pin up close; otherwise frame everything.
    final focused = widget.stops.where((s) => s.focused).toList();
    final target = (focused.isNotEmpty ? focused.map((s) => s.point).toList() : pts);
    final ok = _map.fitCamera(CameraFit.coordinates(
      coordinates: [widget.station, ...target],
      maxZoom: 17,
      padding: const EdgeInsets.all(56),
    ));
    if (ok) {
      _fittedFor = widget.stops.length;
      _fittedMe = widget.me;
    } else if (_fitRetries < 10) {
      _fitRetries++;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _fit();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Re-frame when the stops change, and once the rider's own fix shows up
      // — the first fit happens before the phone has a position.
      if (mounted &&
          (_fittedFor != widget.stops.length ||
              (widget.me != null && _fittedMe == null))) {
        _fitRetries = 0;
        _fit();
      }
    });
    // me -> each stop in order (same shape as the old schematic route).
    final route = [
      if (widget.me != null) widget.me!,
      ...widget.stops.map((s) => s.point),
    ];
    final map = SizedBox(
      height: widget.height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Stack(children: [
          FlutterMap(
            mapController: _map,
            options: MapOptions(
              initialCenter: widget.stops.isNotEmpty
                  ? widget.stops.first.point
                  : widget.station,
              initialZoom: 14,
            ),
            children: [
              TileLayer(urlTemplate: _tiles, userAgentPackageName: _ua),
              if (route.length >= 2)
                PolylineLayer(polylines: [
                  Polyline(
                    points: route,
                    strokeWidth: 3.5,
                    color: Pal.mixAlpha(p.blue, 0.6),
                    pattern: StrokePattern.dashed(segments: [7, 7]),
                  ),
                ]),
              MarkerLayer(markers: [
                Marker(
                    point: widget.station,
                    width: 36,
                    height: 36,
                    child: _stationMarker(context)),
                for (final s in widget.stops)
                  Marker(
                    point: s.point,
                    width: 32,
                    height: 32,
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: s.focused ? Pal.btnGreen : Pal.btnBlue,
                        border: Border.all(color: p.card, width: 2.5),
                        boxShadow: const [
                          BoxShadow(color: Color(0x33000000), blurRadius: 5, offset: Offset(0, 2)),
                        ],
                      ),
                      alignment: Alignment.center,
                      child: Text('${s.n}',
                          style: tx(context, 13, disp: true, w: FontWeight.w700,
                              color: Colors.white)),
                    ),
                  ),
                if (widget.me != null)
                  Marker(
                      point: widget.me!,
                      width: 34,
                      height: 34,
                      child: _meMarker(context)),
              ]),
            ],
          ),
          Positioned(
            right: 8,
            top: 8,
            child: _mapButton(context, Icons.center_focus_strong,
                'Frame the whole route', () {
              setState(() {
                _fittedFor = null;
                _fitRetries = 0;
              });
            }),
          ),
          const Positioned(left: 6, bottom: 4, child: _Attribution()),
        ]),
      ),
    );
    if (!widget.legend) return map;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        map,
        const SizedBox(height: 8),
        MapLegend([
          ('store', 'Station', p.navy),
          ('home', 'Customer stops', p.blue),
          if (widget.me != null) ('scooter', 'You', p.blue),
        ]),
      ],
    );
  }
}

/// Small helper so callers can compute great-circle distance if ever needed.
double metersBetween(LatLng a, LatLng b) =>
    Geolocator.distanceBetween(
        a.latitude, a.longitude, b.latitude, b.longitude);
