import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/* Stroke icon set — 1:1 port of the HTML `I` path data. */

sealed class _Shape {
  String toXml(double sw, String hex);
}

class _P extends _Shape {
  final String d;
  _P(this.d);
  @override
  String toXml(double sw, String hex) =>
      '<path d="$d" stroke="$hex" stroke-width="$sw"/>';
}

class _C extends _Shape {
  final double cx, cy, r;
  _C(this.cx, this.cy, this.r);
  @override
  String toXml(double sw, String hex) =>
      '<circle cx="$cx" cy="$cy" r="$r" stroke="$hex" stroke-width="$sw"/>';
}

class _R extends _Shape {
  final double x, y, w, h, rx;
  _R(this.x, this.y, this.w, this.h, this.rx);
  @override
  String toXml(double sw, String hex) =>
      '<rect x="$x" y="$y" width="$w" height="$h" rx="$rx" stroke="$hex" stroke-width="$sw"/>';
}

class _E extends _Shape {
  final double cx, cy, rx, ry;
  _E(this.cx, this.cy, this.rx, this.ry);
  @override
  String toXml(double sw, String hex) =>
      '<ellipse cx="$cx" cy="$cy" rx="$rx" ry="$ry" stroke="$hex" stroke-width="$sw"/>';
}

final Map<String, List<_Shape>> _I = {
  'menu': [_P('M4 7h16M4 12h16M4 17h16')],
  'bell': [_P('M6 16v-5a6 6 0 1 1 12 0v5l1.5 2h-15L6 16z'), _P('M10 20.5a2 2 0 0 0 4 0')],
  'cart': [
    _P('M3 4h2.5l2 11h10.5l2-8H7'),
    _C(9, 19.5, 1.4),
    _C(17, 19.5, 1.4),
  ],
  'back': [_P('M19 12H5M11 6l-6 6 6 6')],
  'chev': [_P('M9 6l6 6-6 6')],
  'plus': [_P('M12 5v14M5 12h14')],
  'minus': [_P('M5 12h14')],
  'trash': [_P('M4 7h16M9 7V4h6v3M6 7l1 13h10l1-13M10 11v6M14 11v6')],
  'home': [_P('M3 11l9-7.5 9 7.5M5.5 9.5V20h13V9.5M10 20v-6h4v6')],
  'box': [_P('M12 3l8 4.5v9L12 21l-8-4.5v-9L12 3zM4 7.5l8 4.5 8-4.5M12 12v9')],
  'pin': [
    _P('M12 21s-6.5-6.2-6.5-11a6.5 6.5 0 0 1 13 0c0 4.8-6.5 11-6.5 11z'),
    _C(12, 10, 2.4),
  ],
  'user': [_C(12, 8, 4), _P('M4.5 20.5c1-4 4-6 7.5-6s6.5 2 7.5 6')],
  'gear': [
    _C(12, 12, 3),
    _P('M12 3v2.5M12 18.5V21M3 12h2.5M18.5 12H21M5.6 5.6l1.8 1.8M16.6 16.6l1.8 1.8M18.4 5.6l-1.8 1.8M7.4 16.6l-1.8 1.8'),
  ],
  'logout': [_P('M10 4H5v16h5M15 8l4 4-4 4M19 12H9')],
  'truck': [
    _P('M3 6h11v10H3zM14 9h4l3 3v4h-7'),
    _C(7, 18, 1.8),
    _C(17, 18, 1.8),
  ],
  'drop': [_P('M12 3s6 6.2 6 10.5a6 6 0 0 1-12 0C6 9.2 12 3 12 3z')],
  'clip': [_R(5, 4, 14, 17, 2), _P('M9 4V3h6v1M9 11h6M9 15h6')],
  'cal': [_R(4, 5, 16, 15, 2), _P('M4 10h16M8 3v4M16 3v4')],
  'pencil': [_P('M4 20l1-4L16.5 4.5a2 2 0 0 1 3 3L8 19l-4 1z')],
  'check': [_P('M5 12.5l4.5 4.5L19 7.5')],
  'close': [_P('M6 6l12 12M18 6L6 18')],
  'clock': [_C(12, 12, 8.5), _P('M12 7v5l3 2')],
  'copy': [_R(8, 8, 12, 12, 2), _P('M16 8V5a1 1 0 0 0-1-1H5a1 1 0 0 0-1 1v10a1 1 0 0 0 1 1h3')],
  'cash': [_R(3, 6, 18, 12, 2), _C(12, 12, 2.6)],
  'mail': [_R(3, 5, 18, 14, 2), _P('M3.5 7l8.5 6 8.5-6')],
  'phone': [_R(7, 3, 10, 18, 2.5), _P('M11 18h2')],
  'eye': [_P('M2.5 12S6 5.5 12 5.5 21.5 12 21.5 12 18 18.5 12 18.5 2.5 12 2.5 12z'), _C(12, 12, 2.8)],
  'eyeoff': [_P('M2.5 12S6 5.5 12 5.5 21.5 12 21.5 12 18 18.5 12 18.5 2.5 12 2.5 12z'), _C(12, 12, 2.8), _P('M4 4l16 16')],
  'star': [_P('M12 3.5l2.6 5.4 5.9.8-4.3 4.1 1 5.9L12 16.9 6.8 19.7l1-5.9-5.3-.8 5.9-.8L12 3.5z')],
  'map': [_P('M9 4L3 6.5v13L9 17l6 3 6-2.5v-13L15 7 9 4zM9 4v13M15 7v13')],
  'coins': [
    _E(12, 6, 7, 3),
    _P('M5 6v6c0 1.7 3.1 3 7 3s7-1.3 7-3V6M5 12v6c0 1.7 3.1 3 7 3s7-1.3 7-3v-6'),
  ],
  'alert': [_P('M12 3l10 18H2L12 3zM12 10v5M12 18v.5')],
  'send': [_P('M21 3L3 10.5l7 3 3 7L21 3z')],
  'store': [
    _P('M4 9l1.5-5h13L20 9M4 9v11h16V9M4 9a2.7 2.7 0 0 0 5.3 0 2.7 2.7 0 0 0 5.4 0A2.7 2.7 0 0 0 20 9M10 20v-5h4v5'),
  ],
  'users': [
    _C(9, 8, 3.5),
    _P('M2.5 20c.6-3.5 3.3-5.5 6.5-5.5s5.9 2 6.5 5.5M16 5a3.3 3.3 0 0 1 0 6.3M18 14.8c2 .7 3.2 2.5 3.5 5.2'),
  ],
  'search': [_C(11, 11, 6.5), _P('M16 16l4.5 4.5')],
  'filter': [_P('M4 5h16l-6 7.5V19l-4 1.5v-8L4 5z')],
  'chart': [_P('M4 20V4M4 20h16M8 16v-5M12 16V8M16 16v-8')],
};

String _hex(Color c) => '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

String iconSvg(String name, Color color, {double strokeWidth = 1.9}) {
  final hex = _hex(color);
  final body = (_I[name] ?? []).map((s) => s.toXml(strokeWidth, hex)).join();
  return '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" '
      'stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round">$body</svg>';
}

class Ic extends StatelessWidget {
  final String name;
  final double size;
  final Color? color;
  final double strokeWidth;
  const Ic(this.name, {super.key, this.size = 22, this.color, this.strokeWidth = 1.9});

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.primary;
    return SvgPicture.string(
      iconSvg(name, c, strokeWidth: strokeWidth),
      width: size,
      height: size,
      fit: BoxFit.contain,
    );
  }
}