import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/* Gallon / scooter / store artwork — 1:1 port of the HTML <symbol> defs. */

const String _gBodyDef = '<linearGradient id="gBody" x1="0" y1="0" x2="1" y2="0">'
    '<stop offset="0" stop-color="#8FD0FF"/><stop offset=".45" stop-color="#2F8DF0"/>'
    '<stop offset="1" stop-color="#0D52C0"/></linearGradient>';
const String _gCapDef = '<linearGradient id="gCap" x1="0" y1="0" x2="1" y2="0">'
    '<stop offset="0" stop-color="#1B5FCB"/><stop offset="1" stop-color="#093A91"/></linearGradient>';
const String _galBaseInner =
    '<path d="M22 52c-13 2-15 25-4 35" fill="none" stroke="#1D6FDA" stroke-width="5" stroke-linecap="round"/>'
    '<path d="M34 22h32v10c0 6 18 10 18 26v62c0 8-6 14-14 14H30c-8 0-14-6-14-14V58c0-16 18-20 18-26z" fill="url(#gBody)"/>'
    '<path d="M16 68h68M16 76h68" stroke="#fff" stroke-opacity=".28" stroke-width="2"/>'
    '<rect x="27" y="86" width="46" height="28" rx="7" fill="#fff" fill-opacity=".24"/>'
    '<path d="M50 92c0 0 7 7.5 7 12.2a7 7 0 0 1-14 0C43 99.5 50 92 50 92z" fill="#fff"/>'
    '<path d="M25 60v50" stroke="#fff" stroke-opacity=".5" stroke-width="5" stroke-linecap="round"/>'
    '<rect x="35" y="8" width="30" height="16" rx="4" fill="url(#gCap)"/>'
    '<rect x="32" y="19" width="36" height="7" rx="3.5" fill="#0A3585"/>';
const String _galRefillInner = '$_galBaseInner'
    '<circle cx="80" cy="116" r="17" fill="#fff" stroke="#1565D8" stroke-width="2.5"/>'
    '<path d="M72 116a8 8 0 0 1 13-6M88 109v6h-6M88 116a8 8 0 0 1-13 6M72 123v-6h6" fill="none" stroke="#1565D8" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"/>';
const String _galBuyInner = '$_galBaseInner'
    '<circle cx="80" cy="116" r="17" fill="#17A56F" stroke="#fff" stroke-width="2.5"/>'
    '<path d="M72 116.5l5.5 5.5L89 110" fill="none" stroke="#fff" stroke-width="3.2" stroke-linecap="round" stroke-linejoin="round"/>';

String gallonSvg(String type) {
  final inner = type == 'refill' ? _galRefillInner : (type == 'buy' ? _galBuyInner : _galBaseInner);
  return '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 140">'
      '<defs>$_gBodyDef$_gCapDef</defs>$inner</svg>';
}

/// Gallon illustration with the size classes from the HTML:
/// hero 124 / prod 84 / item 70 / big 150 / promo 104 / sm 44 (height, aspect 100/140).
class Gal extends StatelessWidget {
  final String type; // refill | buy
  final double h;
  const Gal(this.type, {super.key, this.h = 70});

  // SVG parsing is the expensive part — cache the finished widget per
  // type+size so scrolling long lists doesn't re-parse artwork.
  static final Map<String, Widget> _cache = {};

  @override
  Widget build(BuildContext context) {
    final key = '$type-$h';
    return _cache.putIfAbsent(key, () {
      final w = h * 100 / 140;
      return SizedBox(
        height: h,
        width: w,
        child: SvgPicture.string(gallonSvg(type), fit: BoxFit.contain),
      );
    });
  }
}

const String _scooterInner =
    '<ellipse cx="82" cy="112" rx="66" ry="5" fill="#000" opacity=".14"/>'
    '<rect x="8" y="54" width="36" height="24" rx="5" fill="#EAF3FE" stroke="#0A3A8A" stroke-width="2"/>'
    '<g transform="translate(10,26) scale(0.18 0.178571)">$_galBaseInner</g>'
    '<g transform="translate(27,26) scale(0.18 0.178571)">$_galBaseInner</g>'
    '<circle cx="36" cy="96" r="15" fill="#0A2A66"/><circle cx="36" cy="96" r="6.5" fill="#CFE3FF"/>'
    '<circle cx="128" cy="96" r="15" fill="#0A2A66"/><circle cx="128" cy="96" r="6.5" fill="#CFE3FF"/>'
    '<path d="M44 84c0-10 8-18 20-18h26l12 20H56l-4 10H46z" fill="#1565D8"/>'
    '<path d="M104 88l9-42" stroke="#0A47A6" stroke-width="8" stroke-linecap="round"/>'
    '<path d="M108 44h14" stroke="#0A2A66" stroke-width="6" stroke-linecap="round"/>'
    '<circle cx="124" cy="52" r="4" fill="#FFD86B"/>'
    '<rect x="46" y="60" width="32" height="8" rx="4" fill="#0A2A66"/>'
    '<path d="M66 62l24 22" stroke="#0A2A66" stroke-width="8" stroke-linecap="round"/>'
    '<ellipse cx="74" cy="42" rx="11" ry="19" fill="#2D8DF4"/>'
    '<path d="M78 38l28 6" stroke="#2D8DF4" stroke-width="7" stroke-linecap="round"/>'
    '<circle cx="76" cy="17" r="9" fill="#F2C9A5"/>'
    '<path d="M66 16a10 10 0 0 1 20 0z" fill="#0A3A8A"/><rect x="82" y="14" width="9" height="3.5" rx="1.7" fill="#0A3A8A"/>';

String scooterSvg() => '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 160 120">'
    '<defs>$_gBodyDef$_gCapDef</defs>$_scooterInner</svg>';

const String _storeInner =
    '<ellipse cx="80" cy="112" rx="64" ry="5" fill="#000" opacity=".14"/>'
    '<rect x="26" y="52" width="108" height="58" rx="4" fill="#EAF3FE"/>'
    '<rect x="38" y="66" width="44" height="30" rx="4" fill="#9CC7FF"/>'
    '<g transform="translate(52,68) scale(0.16 0.157143)">$_galBaseInner</g>'
    '<rect x="94" y="66" width="28" height="44" rx="4" fill="#0A3A8A"/>'
    '<circle cx="116" cy="90" r="2" fill="#FFD86B"/>'
    '<path d="M18 54l8-34h108l8 34z" fill="#fff"/>'
    '<path d="M26 20h18l-5.3 34H18zM62 20h18v34H59.3zM98 20h18l5.3 34h-20.6z" fill="#1565D8"/>'
    '<rect x="56" y="6" width="48" height="13" rx="3" fill="#0A3A8A"/>'
    '<path d="M80 8.5s4 3.8 4 6.6a4 4 0 0 1-8 0c0-2.8 4-6.6 4-6.6z" fill="#fff"/>';

String storeSvg() => '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 160 120">'
    '<defs>$_gBodyDef$_gCapDef</defs>$_storeInner</svg>';

/* Wave shape used at hero/splash bottoms. w1 = translucent white ribbon, w2 = bg fill. */
class Wave extends StatelessWidget {
  final double height;
  final Color w2;
  const Wave({super.key, this.height = 50, this.w2 = const Color(0xFFF1F7FE)});

  @override
  Widget build(BuildContext context) {
    final svg = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 440 60" preserveAspectRatio="none">'
        '<path fill="${_hexA(const Color(0xFFFFFFFF))}" fill-opacity=".38" d="M0 30C60 5 110 5 170 25s120 30 180 10 70-14 90-8V60H0z"/>'
        '<path fill="${_hexA(w2)}" d="M0 42C70 22 120 28 190 40s130 12 250-12V60H0z"/>'
        '</svg>';
    return SizedBox(
        height: height,
        width: double.infinity,
        child: SvgPicture.string(svg, fit: BoxFit.fill));
  }
}

const String _wavePathA = 'M0 30C60 5 110 5 170 25s120 30 180 10 70-14 90-8V60H0z';
const String _wavePathB = 'M0 42C70 22 120 28 190 40s130 12 250-12V60H0z';

String waveSvg({required Color w2}) =>
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 440 60" preserveAspectRatio="none">'
    '<path fill="${_hexA(const Color(0xFFFFFFFF))}" fill-opacity=".38" d="$_wavePathA"/>'
    '<path fill="${_hexA(w2)}" d="$_wavePathB"/></svg>';

String _hexA(Color c) => '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

/// The little wave tucked at the bottom of the sidebar drawer.
class SideWave extends StatelessWidget {
  const SideWave({super.key});
  @override
  Widget build(BuildContext context) {
    const svg = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 320 120" preserveAspectRatio="none">'
        '<path fill="#1E7FEA" d="M0 50C50 20 100 20 160 45s110 25 160-5V120H0z"/></svg>';
    return SizedBox(
        height: 120, width: double.infinity, child: SvgPicture.string(svg, fit: BoxFit.fill));
  }
}

/// "AQUA" brand wordmark with the droplet icon.
class AquaLogo extends StatelessWidget {
  final bool lg;
  final Color color;
  const AquaLogo({super.key, this.lg = false, required this.color});
  @override
  Widget build(BuildContext context) {
    final ic = lg ? 34.0 : 26.0;
    final drops = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" '
        'stroke="${_hexA(color)}" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round">'
        '<path d="M12 2.5s7 7.2 7 12a7 7 0 0 1-14 0c0-4.8 7-12 7-12z"/>'
        '<path d="M9 15a3.5 3.5 0 0 0 3.5 3.5" opacity=".8"/></svg>';
    return Row(mainAxisSize: MainAxisSize.min, children: [
      SvgPicture.string(drops, width: ic, height: ic),
      const SizedBox(width: 6),
      Text('AQUA',
          style: TextStyle(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w700,
              fontSize: lg ? 30 : 22,
              letterSpacing: 0.5,
              color: color)),
    ]);
  }
}

/// Pre-parsed hero artworks — build once, reuse everywhere.
final Widget scooterArt = SvgPicture.string(scooterSvg(), fit: BoxFit.contain);
final Widget storeArt = SvgPicture.string(storeSvg(), fit: BoxFit.contain);
