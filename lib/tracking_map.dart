/* Real-map tracking widgets (OpenStreetMap via flutter_map — free, no API key).
 *
 * - openPinPickerPage  : full-screen drag-to-aim pin picker (addresses, station)
 * - DeliveryTrackMap   : customer's live map — station → pin with moving rider
 * - RouteStopMap       : rider's route map — own GPS + numbered delivery pins
 * - simulatedRiderPos  : simulation-mode rider position (no Firebase needed)
 */

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

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

/// Opens the full-screen map picker. Returns the chosen coordinate, or null
/// if the user backed out.
Future<LatLng?> openPinPickerPage(BuildContext context, {LatLng? initial}) {
  return Navigator.of(context).push<LatLng>(
    MaterialPageRoute(builder: (_) => _PinPickerPage(initial: initial)),
  );
}

class _PinPickerPage extends StatefulWidget {
  final LatLng? initial;
  const _PinPickerPage({this.initial});
  @override
  State<_PinPickerPage> createState() => _PinPickerPageState();
}

class _PinPickerPageState extends State<_PinPickerPage> {
  final MapController _map = MapController();
  late LatLng _center = widget.initial ?? const LatLng(8.6069, 124.8222);
  String _hint = 'Drag the map so the pin sits on the delivery spot.';

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
    return Scaffold(
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
                Btn('Confirm pin location',
                    icon: 'pin',
                    onPressed: () => Navigator.of(context).pop(_center)),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

/* ================= shared marker builders ================= */

Widget _pinMarker(BuildContext context, {required Color color, double size = 34}) {
  return Icon(Icons.location_on, size: size, color: color, shadows: const [
    Shadow(color: Color(0x55000000), blurRadius: 5, offset: Offset(0, 2)),
  ]);
}

Widget _dotMarker(BuildContext context, Widget child, {Color? ring, double size = 34}) {
  final p = Pal.of(context);
  return Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: p.card,
      border: Border.all(color: ring ?? p.line, width: 2),
      boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 5, offset: Offset(0, 2))],
    ),
    alignment: Alignment.center,
    child: child,
  );
}

Widget _stationMarker(BuildContext context) {
  final p = Pal.of(context);
  return _dotMarker(
    context,
    Icon(Icons.store, size: 18, color: p.navy),
    ring: p.navy,
  );
}

/* ================= customer live map ================= */

class DeliveryTrackMap extends StatefulWidget {
  final LatLng station;
  final LatLng dest;
  final LatLng? rider; // null hides the rider marker
  final double height;
  const DeliveryTrackMap({
    super.key,
    required this.station,
    required this.dest,
    this.rider,
    this.height = 240,
  });
  @override
  State<DeliveryTrackMap> createState() => _DeliveryTrackMapState();
}

class _DeliveryTrackMapState extends State<DeliveryTrackMap> {
  final MapController _map = MapController();
  LatLng? _fittedFor;
  int _fitRetries = 0;

  void _fit() {
    // fitCamera returns false until the map has built its first camera;
    // retry a few frames so the first view is always framed correctly.
    final ok = _map.fitCamera(CameraFit.coordinates(
      coordinates: [
        widget.station,
        widget.dest,
        if (widget.rider != null) widget.rider!,
      ],
      padding: const EdgeInsets.all(48),
    ));
    _fittedFor = ok ? widget.dest : null;
    if (!ok && _fitRetries < 10) {
      _fitRetries++;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _fittedFor == null) _fit();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    // Re-fit only when the destination changes — never on rider updates, so
    // the camera doesn't jump every second.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _fittedFor != widget.dest) {
        _fitRetries = 0;
        _fit();
      }
    });
    return SizedBox(
      height: widget.height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: FlutterMap(
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
            PolylineLayer(polylines: [
              Polyline(
                points: [widget.station, widget.dest],
                strokeWidth: 3,
                color: Pal.mixAlpha(p.blue, 0.55),
                pattern: StrokePattern.dashed(segments: [6, 6]),
              ),
            ]),
            MarkerLayer(markers: [
              Marker(
                  point: widget.station,
                  width: 36,
                  height: 36,
                  child: _stationMarker(context)),
              Marker(
                  point: widget.dest,
                  width: 36,
                  height: 36,
                  child: _pinMarker(context, color: p.danger)),
              if (widget.rider != null)
                Marker(
                    point: widget.rider!,
                    width: 34,
                    height: 34,
                    child: _dotMarker(
                      context,
                      const Icon(Icons.local_shipping, size: 18, color: Colors.white),
                      ring: p.blue,
                    )),
            ]),
          ],
        ),
      ),
    );
  }
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
  const RouteStopMap({
    super.key,
    required this.station,
    required this.stops,
    this.me,
    this.height = 260,
  });
  @override
  State<RouteStopMap> createState() => _RouteStopMapState();
}

class _RouteStopMapState extends State<RouteStopMap> {
  final MapController _map = MapController();
  int? _fittedFor;
  int _fitRetries = 0;

  void _fit() {
    final pts = [
      widget.station,
      if (widget.me != null) widget.me!,
      ...widget.stops.map((s) => s.point),
    ];
    if (pts.length < 2) return;
    final ok = _map.fitCamera(CameraFit.coordinates(
      coordinates: pts,
      padding: const EdgeInsets.all(44),
    ));
    _fittedFor = ok ? widget.stops.length : null;
    if (!ok && _fitRetries < 10) {
      _fitRetries++;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _fittedFor == null) _fit();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _fittedFor != widget.stops.length) {
        _fitRetries = 0;
        _fit();
      }
    });
    // me -> each stop in order (same shape as the old schematic route).
    final route = [
      if (widget.me != null) widget.me!,
      ...widget.stops.map((s) => s.point),
    ];
    return SizedBox(
      height: widget.height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: FlutterMap(
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
                    width: 30,
                    height: 30,
                    child: _dotMarker(
                      context,
                      Icon(Icons.person, size: 16, color: p.navy),
                      ring: p.navy,
                    )),
            ]),
          ],
        ),
      ),
    );
  }
}

/// Small helper so callers can compute great-circle distance if ever needed.
double metersBetween(LatLng a, LatLng b) =>
    Geolocator.distanceBetween(
        a.latitude, a.longitude, b.latitude, b.longitude);
