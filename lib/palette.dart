import 'package:flutter/material.dart';

/// Exact port of the CSS custom properties (light + dark variants).
class Pal {
  final Color navy, navy2, blue, blueHi;
  final Color ice, ice2, card, bg, stage;
  final Color ink, muted, line, link;
  final Color ok, danger;
  final Color mintBg, mintFg, peachBg, peachFg;
  final Color s0bg, s0fg, s1bg, s1fg, s2bg, s2fg, s3bg, s3fg, s4bg, s4fg, s5bg, s5fg;
  final Color pip; // .pip / unread dot background #FF5B4D
  final List<BoxShadow> shadow;
  final Color scrim;
  final bool isDark;

  const Pal({
    required this.navy, required this.navy2, required this.blue, required this.blueHi,
    required this.ice, required this.ice2, required this.card, required this.bg, required this.stage,
    required this.ink, required this.muted, required this.line, required this.link,
    required this.ok, required this.danger,
    required this.mintBg, required this.mintFg, required this.peachBg, required this.peachFg,
    required this.s0bg, required this.s0fg, required this.s1bg, required this.s1fg,
    required this.s2bg, required this.s2fg, required this.s3bg, required this.s3fg,
    required this.s4bg, required this.s4fg, required this.s5bg, required this.s5fg,
    required this.pip, required this.shadow, required this.scrim, required this.isDark,
  });

  static const Pal light = Pal(
    navy: Color(0xFF0A3A8A), navy2: Color(0xFF0B4FB8), blue: Color(0xFF1565D8), blueHi: Color(0xFF2D8DF4),
    ice: Color(0xFFEAF3FE), ice2: Color(0xFFD6E8FD), card: Color(0xFFFFFFFF), bg: Color(0xFFF1F7FE), stage: Color(0xFFDCEAFB),
    ink: Color(0xFF0B1F44), muted: Color(0xFF55688C), line: Color(0xFFD5E3F6), link: Color(0xFF0B4FB8),
    ok: Color(0xFF128058), danger: Color(0xFFC93333),
    mintBg: Color(0xFFE0F5EC), mintFg: Color(0xFF0F7A55), peachBg: Color(0xFFFCE9E1), peachFg: Color(0xFFB9441C),
    s0bg: Color(0xFFFFF1D6), s0fg: Color(0xFF8A5700),
    s1bg: Color(0xFFDDEBFF), s1fg: Color(0xFF0E4FB0),
    s2bg: Color(0xFFDFF3F6), s2fg: Color(0xFF0B6C7A),
    s3bg: Color(0xFFE6E3FF), s3fg: Color(0xFF4B3FC2),
    s4bg: Color(0xFFDDF5E8), s4fg: Color(0xFF107A52),
    s5bg: Color(0xFFFDE2E2), s5fg: Color(0xFFB02A2A),
    pip: Color(0xFFFF5B4D),
    shadow: [BoxShadow(color: Color(0x1A0A3A8A), offset: Offset(0, 6), blurRadius: 18)],
    scrim: Color(0x85051432),
    isDark: false,
  );

  static const Pal dark = Pal(
    navy: Color(0xFF082E6E), navy2: Color(0xFF0A3F96), blue: Color(0xFF2A7BEA), blueHi: Color(0xFF4B97F7),
    ice: Color(0xFF12305E), ice2: Color(0xFF18417F), card: Color(0xFF0D2144), bg: Color(0xFF071429), stage: Color(0xFF040C1A),
    ink: Color(0xFFE6F0FF), muted: Color(0xFF9AB0D4), line: Color(0xFF1C3B6C), link: Color(0xFF8FC0FF),
    ok: Color(0xFF58D6A0), danger: Color(0xFFFF8A8A),
    mintBg: Color(0xFF0F3B2D), mintFg: Color(0xFF7EE2B2), peachBg: Color(0xFF46231A), peachFg: Color(0xFFFFB195),
    s0bg: Color(0xFF3A2A08), s0fg: Color(0xFFFFCF73),
    s1bg: Color(0xFF12305E), s1fg: Color(0xFF9CC7FF),
    s2bg: Color(0xFF0D3A42), s2fg: Color(0xFF7FDCEB),
    s3bg: Color(0xFF2A2660), s3fg: Color(0xFFBDB6FF),
    s4bg: Color(0xFF0F3B2B), s4fg: Color(0xFF7EE2B2),
    s5bg: Color(0xFF4A1B1B), s5fg: Color(0xFFFF9C9C),
    pip: Color(0xFFFF5B4D),
    shadow: [BoxShadow(color: Color(0x59000000), offset: Offset(0, 6), blurRadius: 18)],
    scrim: Color(0xA600040E),
    isDark: true,
  );

  static Pal of(BuildContext c) =>
      Theme.of(c).brightness == Brightness.dark ? dark : light;

  /// `color-mix(in srgb, <c> <pct>%, transparent)` for rings like the focus halo.
  static Color mixAlpha(Color c, double alpha) => c.withValues(alpha: alpha);

  // ---- gradients -----------------------------------------------------------
  static const LinearGradient btnBlue = LinearGradient(
      begin: Alignment.topCenter, end: Alignment.bottomCenter,
      colors: [Color(0xFF2D8DF4), Color(0xFF1565D8)]);
  static const LinearGradient btnGreen = LinearGradient(
      begin: Alignment.topCenter, end: Alignment.bottomCenter,
      colors: [Color(0xFF25A26F), Color(0xFF127A55)]);
  static const LinearGradient hero = LinearGradient(
      begin: Alignment.topCenter, end: Alignment.bottomCenter,
      stops: [0, .62, 1],
      colors: [Color(0xFF0A3A8A), Color(0xFF0B4FB8), Color(0xFF1B7BE8)]);
  static const LinearGradient auth = LinearGradient(
      begin: Alignment.topCenter, end: Alignment.bottomCenter,
      stops: [0, .70, 1],
      colors: [Color(0xFF0A3A8A), Color(0xFF0B4FB8), Color(0xFF1B7BE8)]);
  static const LinearGradient splashG = LinearGradient(
      begin: Alignment.topCenter, end: Alignment.bottomCenter,
      stops: [0, .70, 1],
      colors: [Color(0xFF0A3A8A), Color(0xFF0B4FB8), Color(0xFF1B7BE8)]);
  static const LinearGradient side = LinearGradient(
      begin: Alignment.topCenter, end: Alignment.bottomCenter,
      colors: [Color(0xFF0A3A8A), Color(0xFF0A47A6)]);
  static const LinearGradient avatar = LinearGradient(
      begin: Alignment.topCenter, end: Alignment.bottomCenter,
      colors: [Color(0xFF2D8DF4), Color(0xFF0B4FB8)]);
  static const LinearGradient slide = LinearGradient(
      begin: Alignment(-0.3, -0.6), end: Alignment(0.8, 0.8),
      colors: [Color(0xFFEAF3FE), Color(0xFFD6E8FD)]);
  static const LinearGradient tile1 = LinearGradient(
      begin: Alignment.topCenter, end: Alignment.bottomCenter,
      colors: [Color(0xFF2D8DF4), Color(0xFF1565D8)]);
}

/// A teal gradient used for the admin/rider availability chip strip etc.
const LinearGradient tealBtn = LinearGradient(
    begin: Alignment.topCenter, end: Alignment.bottomCenter,
    colors: [Color(0xFF25A26F), Color(0xFF127A55)]);
