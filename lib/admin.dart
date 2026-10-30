/* ================= Admin app — 1:1 port of the HTML admin screens =================
   authAdmin, adash, aorders, adetail, adeliv, aprod, ainv, ausers, areports,
   aprofile, asettings + all admin sheets (filter, assign, product, prices,
   restock, adjust, rider form, profile, confirms) and the daily sales chart. */

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import 'art.dart';
import 'constants.dart';
import 'icons.dart';
import 'models.dart';
import 'palette.dart';
import 'state.dart';
import 'tracking_map.dart';
import 'widgets.dart';

/* ================= shared local helpers ================= */

T? firstBy<T>(Iterable<T> l, bool Function(T) t) {
  for (final x in l) {
    if (t(x)) return x;
  }
  return null;
}

/// HTML `String(n)` on a JS number keeps no trailing `.0`.
String _priceStr(double v) {
  final r = v.roundToDouble();
  return v == r ? r.toInt().toString() : v.toString();
}

/// `X.replace('deliverys','deliveries')` — pl() plural fix from the HTML.
String _plOk(num n, String w) {
  final t = pl(n, w);
  return t.contains('deliverys') ? t.replaceAll('deliverys', 'deliveries') : t;
}

int _nowMs() => DateTime.now().millisecondsSinceEpoch;

/// `doneAt(o)` — stamp of the current status, else the placement time.
int _doneAt(Order o) =>
    (o.stamps.length > o.status && o.stamps[o.status] != null)
        ? o.stamps[o.status]!
        : o.createdAt;

Rider? _riderOf(AppState s, Order o) =>
    o.riderId == null || o.riderId!.isEmpty
        ? null
        : firstBy(s.riders, (r) => r.id == o.riderId);

/// `uprice(o,t)` — price snapshot taken when the order was placed.
double _uprice(AppState s, Order o, String t) =>
    o.unitPrice(t, s.priceOf('refill'), s.priceOf('buy'));

int _gsum(List<Order> list, String t) => list.fold(
    0, (a, o) => a + o.items.fold(0, (b, i) => b + ((i.type == t) ? i.qty : 0)));

double _osum(List<Order> list) => list.fold(0.0, (a, o) => a + o.total);

double _irev(AppState s, List<Order> list, String t) => list.fold(
    0.0,
    (a, o) => a +
        o.items.fold(
            0.0, (b, i) => b + (i.type == t ? _uprice(s, o, t) * i.qty : 0.0)));

bool _amatch(Order o, String t) {
  final sv = statusState(o);
  return t == 'all' ||
      (t == 'pending' && sv == 0) ||
      (t == 'delivery' && sv >= 1 && sv <= 3) ||
      (t == 'done' && sv == 4) ||
      (t == 'cancelled' && sv == 5);
}

Order? _orderOf(AppState s, String? id) =>
    id == null ? null : firstBy(s.orders, (o) => o.id == id);

/* ================= small shared widgets ================= */

/// `.rstat` — 88px stat tile used by the 2×2 grids on the other admin screens
/// (Deliveries, Reports). The overview uses the compact [StatTile] row instead.
Widget _rstatTile(BuildContext context,
    {String? icon,
    required Color bg,
    required Color fg,
    required String num,
    required String label,
    VoidCallback? onTap}) {
  final p = Pal.of(context);
  return TapSurface(
    onTap: onTap,
    semanticLabel: '$num $label',
    borderRadius: BorderRadius.circular(18),
    child: Container(
      constraints: const BoxConstraints(minHeight: 88),
      padding: const EdgeInsets.all(14),
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
          color: bg, borderRadius: BorderRadius.circular(18), boxShadow: p.shadow),
      child: Row(children: [
        if (icon != null) ...[Ic(icon, size: 34, color: fg), const SizedBox(width: 12)],
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(num,
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: numStyle(context, size: 28, w: FontWeight.w700, disp: true, color: p.ink)),
            const SizedBox(height: 3),
            Text(label, style: tx(context, 13.5, w: FontWeight.w700, color: p.ink, h: 1.2)),
          ]),
        ),
      ]),
    ),
  );
}

/// 2×N grid with 12px gutters.
Widget _statGrid(List<Widget> tiles) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < tiles.length; i += 2) ...[
          if (i > 0) const SizedBox(height: 12),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: tiles[i]),
            const SizedBox(width: 12),
            Expanded(
                child: i + 1 < tiles.length
                    ? tiles[i + 1]
                    : const SizedBox.shrink()),
          ]),
        ]
      ],
    );

/// `confirmSheet(title,msg,act,id,label,danger,keep)`.
Future<void> _confirmSheet(
  BuildContext context, {
  required String title,
  required Widget msg,
  required String label,
  required bool danger,
  String keep = 'Keep it',
  VoidCallback? onConfirm,
}) {
  return showAquaSheet(
    context,
    title: title,
    body: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Padding(padding: const EdgeInsets.only(bottom: 16), child: msg),
        Btn(label, kind: danger ? BtnKind.danger : BtnKind.primary, onPressed: onConfirm),
        Btn(keep, kind: BtnKind.alt, onPressed: () => Navigator.of(context).pop()),
      ],
    ),
  );
}

/// Confirm message with an inline bold part, e.g. `Order <b>AQ-…</b> will be …`.
Widget _confirmText(BuildContext context, String pre, String bold, String post) {
  final p = Pal.of(context);
  return Text.rich(
    TextSpan(children: [
      TextSpan(text: pre, style: para(context, color: p.muted)),
      TextSpan(text: bold, style: para(context, color: p.muted, w: FontWeight.w700)),
      TextSpan(text: post, style: para(context, color: p.muted)),
    ]),
  );
}

/// Small `.ibtn` icon action (copy / call / edit pencil).
Widget _iconAction(BuildContext context, String icon, VoidCallback onTap,
    {String? label, Color? color}) {
  return IconAction(icon, onTap: onTap, color: color, label: label);
}

/* =====================================================================
   authAdmin — bare auth screen
   ===================================================================== */

class _AdminLoginForm extends StatefulWidget {
  final AppState s;
  const _AdminLoginForm(this.s);
  @override
  State<_AdminLoginForm> createState() => _AdminLoginFormState();
}

class _AdminLoginFormState extends State<_AdminLoginForm> {
  late final TextEditingController _email =
      TextEditingController(text: widget.s.admin?.email ?? 'admin@aqua.ph');
  late final TextEditingController _pass = TextEditingController(text: 'aqua1234');
  final FocusNode _emailFocus = FocusNode();
  final FocusNode _passFocus = FocusNode();
  bool _obscure = true;
  bool _busy = false;
  String _emailErr = '';
  String _passErr = '';
  String _err = '';

  @override
  void dispose() {
    _email.dispose();
    _pass.dispose();
    _emailFocus.dispose();
    _passFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final e = _email.text.trim().toLowerCase();
    if (_busy) return;
    setState(() {
      _err = '';
      _emailErr = '';
      _passErr = '';
    });
    if (!isEmail(e)) {
      setState(() => _emailErr = 'Enter the admin email address.');
      _emailFocus.requestFocus();
      return;
    }
    if (_pass.text.length < 4) {
      setState(() => _passErr = 'Enter your password (at least 4 characters).');
      _passFocus.requestFocus();
      return;
    }
    setState(() => _busy = true);
    final err = await widget.s.loginAdmin(e, _pass.text);
    if (!mounted) return;
    setState(() => _busy = false);
    if (err == null) return;
    final low = err.toLowerCase();
    setState(() {
      if (low.contains('password')) {
        _passErr = err;
      } else if (low.contains('email') || low.contains('account')) {
        _emailErr = err;
      } else {
        _err = err;
      }
    });
    (low.contains('password') ? _passFocus : _emailFocus).requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return VGap([
      AquaField(
        'Email',
        _email,
        error: _emailErr.isEmpty ? null : _emailErr,
        kbType: TextInputType.emailAddress,
        kbAction: TextInputAction.next,
        autofillHints: const [AutofillHints.email],
        focusNode: _emailFocus,
        onSubmitted: (_) => _passFocus.requestFocus(),
        onChanged: (_) {
          if (_emailErr.isNotEmpty) setState(() => _emailErr = '');
        },
      ),
      AquaField(
        'Password',
        _pass,
        error: _passErr.isEmpty ? null : _passErr,
        obscure: _obscure,
        eyeToggle: true,
        onEye: () => setState(() => _obscure = !_obscure),
        kbAction: TextInputAction.done,
        autofillHints: const [AutofillHints.password],
        focusNode: _passFocus,
        onSubmitted: (_) => _submit(),
        onChanged: (_) {
          if (_passErr.isNotEmpty) setState(() => _passErr = '');
        },
      ),
      ErrLine(_err),
      Btn('Log In', busy: _busy, onPressed: _submit),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration:
            BoxDecoration(color: p.ice, borderRadius: BorderRadius.circular(12)),
        child: Text('Demo admin account is filled in. Station data is saved only on this device.',
            style: para(context, color: p.muted, size: 13)),
      ),
    ]);
  }
}

ScreenView authAdminView(BuildContext context, AppState s) {
  return ScreenView(
    bare: true,
    content: Column(children: [
      AuthHero(
        title: 'Station admin sign-in',
        sub: 'Orders, riders, stock and sales.',
        art: storeArt,
      ),
      authOverlapScroll(
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          AquaCard(child: _AdminLoginForm(s)),
          const SizedBox(height: 8),
          // Same sheet the customer form uses, so admin → rider is one tap.
          Center(
            child: TxtLink('Switch account type', icon: 'users',
                onTap: () => showAuthRoleSheet(context, s)),
          ),
        ]),
      ),
    ]),
  );
}

/* =====================================================================
   adash — Admin Dashboard
   ===================================================================== */

/// `.dcard` order card used on adash + aorders.
Widget _acard(BuildContext context, AppState s, Order o) {
  final p = Pal.of(context);
  final c = s.custOf(o);
  return AquaCard(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    child: TapSurface(
      onTap: () {
        s.aid = o.id;
        s.goScreen('adetail');
      },
      semanticLabel: 'Order ${o.id}, ${c.name}',
      semanticButton: false,
      borderRadius: BorderRadius.circular(12),
      child: RowW([
          Gal(o.items.isNotEmpty ? o.items[0].type : 'refill', h: 70),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(o.id, style: tx(context, 15, disp: true, w: FontWeight.w700, ls: 0.4)),
              const SizedBox(height: 2),
              Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: para(context)),
              const SizedBox(height: 2),
              Text(itemsText(o),
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: para(context, color: p.muted, size: 13)),
              const SizedBox(height: 4),
              Text(peso(o.total),
                  style: numStyle(context, size: 15, w: FontWeight.w700, color: p.ink)),
              const SizedBox(height: 8),
              // Inside the column the chip can truncate; beside it, "Out for
              // Delivery" is ~194dp at 1.3x text and overflows a 320dp card.
              OrdBadge(statusState(o)),
            ]),
          ),
          Ic('chev', size: 20, color: p.muted),
        ],
      ),
    ),
  );
}

ScreenView adashView(BuildContext context, AppState s) {
  final p = Pal.of(context);
  final now = _nowMs();
  final all = s.orders;
  final live = all.where((o) => !o.cancelled).toList();
  final ong = all.where((o) {
    final sv = statusState(o);
    return sv >= 1 && sv <= 3;
  }).length;
  final needR =
      all.where((o) => !o.cancelled && o.status < 4 && o.riderId == null).toList();
  final low = ['containers', 'water']
      .where((k) => s.inv[k]!.qty <= s.inv[k]!.low)
      .toList();
  final online =
      s.riders.where((r) => r.active && r.available == 'available').length;
  final dnT = all
      .where((o) => statusState(o) == 4 && _doneAt(o) >= sod(now))
      .toList();
  final yT = all.where((o) {
    final d = _doneAt(o);
    final start = sod(now) - 86400000;
    return statusState(o) == 4 && d >= start && d < sod(now);
  }).toList();
  final todayOrders = live.where((o) => o.createdAt >= sod(now)).toList();
  final recent = [...all]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  final recent3 = recent.take(3).toList();
  final sales = _osum(dnT);
  final weekly = <double>[
    for (var i = 6; i >= 0; i--)
      _osum(all
          .where((o) {
            final d = _doneAt(o);
            final start = sod(now) - i * 86400000;
            return statusState(o) == 4 && d >= start && d < start + 86400000;
          })
          .toList()),
  ];

  // Tasks before totals: what an admin opens this screen for is what is broken,
  // and "needs a rider" is impossible to act on silently when every rider is
  // offline — hence the second row.
  final alerts = <Widget>[
    if (needR.isNotEmpty)
      ActionRow(
        accent: p.s0fg,
        icon: 'truck',
        title:
            '${needR.length} ${needR.length == 1 ? 'order needs' : 'orders need'} a rider',
        sub: 'Assign a rider so delivery can start.',
        verb: 'Assign',
        onTap: () => s.goScreen('adeliv'),
      ),
    if (needR.isNotEmpty && online == 0)
      ActionRow(
        accent: p.danger,
        icon: 'users',
        title: 'No rider is available',
        sub: 'Assignments wait until a rider goes online.',
        verb: 'Riders',
        onTap: () => s.goScreen('ausers'),
      ),
    for (final k in low)
      ActionRow(
        accent: p.s5fg,
        icon: k == 'water' ? 'drop' : 'box',
        title: '${INV_DEFS[k]!.name}: ${s.inv[k]!.qty} left',
        sub: 'Reorder level is ${s.inv[k]!.low}.',
        verb: 'Restock',
        onTap: () => s.goScreen('ainv'),
      ),
  ];

  final body = Container(
    color: p.bg,
    child: PadScroll(children: [
      _salesCard(context,
          sales: sales,
          yesterday: _osum(yT),
          orders: todayOrders.length,
          week: weekly),
      if (alerts.isNotEmpty) ...[
        const SectionRow('Needs attention'),
        VGap(alerts, gap: 10),
      ],
      StatRow([
        StatTile(
            icon: 'cart',
            value: '${todayOrders.length}',
            label: 'Orders today',
            bg: p.ice,
            fg: p.blue,
            onTap: () {
              s.atab = 'all';
              s.atoday = true; // the list shows today's orders, like the tile
              s.goScreen('aorders');
            }),
        StatTile(
            icon: 'truck',
            value: '$ong',
            label: 'Ongoing',
            bg: p.peachBg,
            fg: p.peachFg,
            onTap: () {
              s.atab = 'delivery';
              s.atoday = false; // ongoing is everything on the road, any day
              s.goScreen('aorders');
            }),
        StatTile(
            icon: 'check',
            value: '${dnT.length}',
            label: 'Delivered',
            bg: p.mintBg,
            fg: p.mintFg,
            onTap: () {
              s.atab = 'done';
              s.atoday = true; // delivered today, matching the tile
              s.goScreen('aorders');
            }),
        StatTile(
            icon: 'drop',
            value: '${dnT.fold<int>(0, (a, o) => a + gallonsOf(o))}',
            label: 'Gallons out',
            bg: p.s3bg,
            fg: p.s3fg,
            onTap: () => s.goScreen('areports')),
      ]),
      SectionRow('Recent Orders', action: 'View All', onTap: () {
        s.atoday = false; // "View All" means all of them, not today's
        s.goScreen('aorders');
      }),
      if (recent3.isNotEmpty)
        ...recent3.map((o) => _acard(context, s, o))
      else
        AquaCard(
          padding: const EdgeInsets.all(22),
          child: SizedBox(
            width: double.infinity,
            child: Text('No orders yet. New orders will show up here.',
                textAlign: TextAlign.center, style: para(context)),
          ),
        ),
    ]),
  );

  return ScreenView(
    content: Column(children: [
      DashHero(
        title: 'Station overview',
        // The operational state an admin needs on arrival — who can deliver.
        sub: '${dayLong(DateTime.now())} · '
            '${s.riders.isEmpty ? 'no riders yet' : '$online of ${s.riders.length} riders available'}',
        art: SizedBox(width: 112, height: 84, child: storeArt),
      ),
      Expanded(child: body),
    ]),
  );
}

/// Money first with yesterday's delta and a 7-day strip, so the headline reads
/// as a trend instead of a scoreboard.
Widget _salesCard(BuildContext context,
    {required double sales,
    required double yesterday,
    required int orders,
    required List<double> week}) {
  final d = sales - yesterday;
  return Container(
    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
    decoration: BoxDecoration(
      gradient: Pal.btnBlue,
      borderRadius: BorderRadius.circular(18),
      boxShadow: const [
        BoxShadow(color: Color(0x331565D8), offset: Offset(0, 6), blurRadius: 16),
      ],
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Sales today',
                style: tx(context, 12.5,
                    w: FontWeight.w800,
                    color: Colors.white.withValues(alpha: .85),
                    ls: .3)),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(peso(sales),
                  style: numStyle(context,
                      size: 28, w: FontWeight.w700, disp: true, color: Colors.white)),
            ),
          ]),
        ),
        const SizedBox(width: 12),
        SizedBox(width: 92, child: Sparkline(week, height: 46)),
      ]),
      const SizedBox(height: 6),
      Text(
        '$orders ${orders == 1 ? 'order' : 'orders'} · '
        '${d >= 0 ? '+' : '-'}${peso(d.abs())} vs yesterday',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: tx(context, 12,
            w: FontWeight.w600, color: Colors.white.withValues(alpha: .9)),
      ),
    ]),
  );
}

/* =====================================================================
   aorders — Orders list with tabs, live search and filter sheet
   ===================================================================== */

final TextEditingController _aqCtl = TextEditingController();

void _syncAq(AppState s) {
  if (_aqCtl.text != s.aq) {
    // Defer to after the frame: mutating the controller during build would
    // make the listening TextField call setState() inside the build phase.
    final v = s.aq;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _aqCtl.text = v;
      _aqCtl.selection = TextSelection.collapsed(offset: v.length);
    });
  }
}

Widget _radioRows(BuildContext context, List<List<String>> arr, String cur, void Function(String) act) =>
    VGap([
      for (final x in arr)
        RadioRow(
          checked: cur == x[0],
          onTap: () => act(x[0]),
          content: Text(x[1], style: tx(context, 15, w: FontWeight.w700)),
        ),
    ], gap: 8);

/// Sheet body listens to AppState so radio selections repaint live.
class _FilterSheetBody extends StatelessWidget {
  final AppState s;
  const _FilterSheetBody(this.s);

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    const lbl = [
      ['new', 'Newest first'],
      ['old', 'Oldest first'],
      ['high', 'Highest total'],
    ];
    const types = [
      ['all', 'All products'],
      ['refill', 'Refill Gallon'],
      ['buy', 'Buy Gallon'],
    ];
    return AnimatedBuilder(
      animation: s,
      builder: (context, _) {
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Sort by', style: tx(context, 13, w: FontWeight.w700, color: p.muted, ls: 0.2)),
          const SizedBox(height: 8),
          _radioRows(context, lbl, s.asort, (v) {
            s.asort = v;
            s.save();
            s.updateUI();
          }),
          const SizedBox(height: 14),
          Text('Product', style: tx(context, 13, w: FontWeight.w700, color: p.muted, ls: 0.2)),
          const SizedBox(height: 8),
          _radioRows(context, types, s.atype, (v) {
            s.atype = v;
            s.save();
            s.updateUI();
          }),
          const SizedBox(height: 16),
          Btn('Done', onPressed: () => Navigator.of(context).pop()),
        ]);
      },
    );
  }
}

void _openFilterSheet(BuildContext context, AppState s) {
  showAquaSheet(context, title: 'Filter and sort', body: _FilterSheetBody(s));
}

ScreenView aordersView(BuildContext context, AppState s) {
  final p = Pal.of(context);
  _syncAq(s);
  const tabs = [
    ['all', 'All'],
    ['pending', 'Pending'],
    ['delivery', 'In Delivery'],
    ['done', 'Completed'],
    ['cancelled', 'Cancelled'],
  ];
  final chipsOn = s.atype != 'all' || s.asort != 'new';

  final q = s.aq.trim().toLowerCase();
  final nowMs = _nowMs();
  final l = s.orders.where((o) {
    if (!_amatch(o, s.atab)) return false;
    // Today scope: the dashboard's today tiles land here, so the list must
    // show exactly what the tile counted. Delivered orders are scoped by the
    // time they finished; every other tile by when they were placed. A
    // cancelled order is never a "today" figure, so it drops out here too.
    if (s.atoday) {
      if (o.cancelled) return false;
      final ref = s.atab == 'done' ? _doneAt(o) : o.createdAt;
      if (ref < sod(nowMs)) return false;
    }
    if (s.atype != 'all' && !o.items.any((i) => i.type == s.atype)) return false;
    if (q.isEmpty) return true;
    final c = s.custOf(o);
    return ('${o.id} ${c.name} ${c.phone} ${o.address.line}').toLowerCase().contains(q);
  }).toList()
    ..sort((a, b) {
      if (s.asort == 'old') return a.createdAt.compareTo(b.createdAt);
      if (s.asort == 'high') return b.total.compareTo(a.total);
      return b.createdAt.compareTo(a.createdAt);
    });

  return ScreenView(content: 
    PadScroll(children: [
      if (s.atoday)
        TapSurface(
          onTap: () {
            s.atoday = false;
            s.save();
            s.updateUI();
          },
          semanticLabel: 'Show all dates',
          semanticButton: false,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
                color: p.ice, borderRadius: BorderRadius.circular(12)),
            child: RowW([
              Ic('clock', size: 16, color: p.blue),
              Expanded(
                  child: Text('Showing today only',
                      style: tx(context, 13, w: FontWeight.w700, color: p.blue))),
              Text('Show all',
                  style: tx(context, 12.5, w: FontWeight.w800, color: p.link)),
              Ic('close', size: 15, color: p.link),
            ], gap: 8),
          ),
        ),
      FilterChips(
        items: [
          for (final x in tabs)
            SegItem(x[0], '${x[1]} (${s.orders.where((o) => _amatch(o, x[0])).length})'),
        ],
        value: s.atab,
        onSelect: (v) {
          s.atab = v;
          s.atoday = false; // a tab is an all-time view; drop the today scope
          s.save();
          s.updateUI();
        },
      ),
      RowW([
        Expanded(
          child: AquaSearch(
            controller: _aqCtl,
            hint: 'Search order ID, customer…',
            onChanged: (v) {
              s.aq = v;
              s.save();
              s.updateUI();
            },
          ),
        ),
        TapSurface(
          onTap: () => _openFilterSheet(context, s),
          semanticLabel: 'Filters',
          borderRadius: BorderRadius.circular(14),
          child: Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
                color: p.card,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: p.line, width: 1.5)),
            alignment: Alignment.center,
            child: Stack(clipBehavior: Clip.none, children: [
              Ic('filter', size: 22, color: p.link),
              if (chipsOn)
                Positioned(
                  top: -2,
                  right: -2,
                  child: Container(
                      width: 9,
                      height: 9,
                      decoration:
                          BoxDecoration(color: p.pip, shape: BoxShape.circle)),
                ),
            ]),
          ),
        ),
      ], gap: 10),
      if (l.isNotEmpty)
        ...l.map((o) => _acard(context, s, o))
      else
        EmptyView('No matching orders', msg: 'Try another tab or clear the search.'),
    ]),
  );
}

/* =====================================================================
   adetail — Order Details
   ===================================================================== */

const List<String> _NXT = [
  'Confirm Order',
  'Start Preparing',
  'Send Out for Delivery',
  'Mark as Delivered'
];

class _Timeline extends StatelessWidget {
  final Order o;
  const _Timeline(this.o);

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (var i = 0; i < STAGE.length; i++)
        IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Column(children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: (i <= o.status && !(o.cancelled && i > o.status))
                      ? p.blue
                      : p.card,
                  border: Border.all(
                      color: (i <= o.status && !(o.cancelled && i > o.status))
                          ? p.blue
                          : p.line,
                      width: 2),
                ),
                child: (i <= o.status && !(o.cancelled && i > o.status))
                    ? Ic('check', size: 15, color: Colors.white)
                    : null,
              ),
              if (i != STAGE.length - 1)
                Expanded(
                  child: Container(
                    width: 2,
                    margin: const EdgeInsets.only(top: 4),
                    color: i < o.status && !(o.cancelled && i > o.status)
                        ? p.blue
                        : p.line,
                  ),
                ),
            ]),
            const SizedBox(width: 12),
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(bottom: i == STAGE.length - 1 ? 0 : 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(STAGE[i],
                        style: tx(context, 15, disp: true, w: FontWeight.w700,
                            color: (i <= o.status && !(o.cancelled && i > o.status))
                                ? p.ink
                                : p.muted)),
                    if (i <= o.status &&
                        !(o.cancelled && i > o.status) &&
                        o.stamps.length > i &&
                        o.stamps[i] != null) ...[
                      const SizedBox(height: 1),
                      Text(tfmt(o.stamps[i]!),
                          style: numStyle(context, size: 13, color: p.muted)),
                    ],
                  ],
                ),
              ),
            ),
          ]),
        ),
    ]);
  }
}

void _openAssignSheet(BuildContext context, AppState s, String orderId) {
  showAquaSheet(context, title: 'Assign a rider', body: _AssignSheetBody(s, orderId));
}

/// Sheet body listens to AppState so the checked rider updates live.
class _AssignSheetBody extends StatelessWidget {
  final AppState s;
  final String orderId;
  const _AssignSheetBody(this.s, this.orderId);

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final o = _orderOf(s, orderId);
    if (o == null) {
      return Text('No active riders. Add one in Users.',
          style: para(context, color: p.muted));
    }
    final act = s.riders.where((r) => r.active != false).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      VGap([
        if (act.isEmpty)
          Text('No active riders. Add one in Users.',
              style: para(context, color: p.muted))
        else
          ...act.map((r) => RadioRow(
                checked: o.riderId == r.id,
                onTap: () {
                  s.adminPickRider(orderId, r.id);
                  Navigator.of(context).pop();
                },
                content: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Flexible(
                        child: Text(r.name,
                            maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: tx(context, 15, w: FontWeight.w700))),
                    const SizedBox(width: 8),
                    OrdBadge(int.parse(AVS[r.available]!), label: AV[r.available]),
                  ]),
                  const SizedBox(height: 2),
                  Text('${r.vehicle} · ${s.loadOf(r)} active',
                      style: para(context, color: p.muted, size: 13)),
                ]),
              )),
      ], gap: 8),
      if (o.riderId != null) ...[
        const SizedBox(height: 12),
        Btn('Remove rider', kind: BtnKind.alt, onPressed: () {
          s.adminPickRider(orderId, '');
          Navigator.of(context).pop();
        }),
      ],
    ]);
  }
}

ScreenView adetailView(BuildContext context, AppState s) {
  final p = Pal.of(context);
  final o = _orderOf(s, s.aid);

  if (o == null) {
    return ScreenView(content: 
      PadScroll(children: [
        EmptyView(
          'Order not found',
          msg: '',
          action: SizedBox(
              width: 240,
              child: Btn('Orders', onPressed: () {
                s.atoday = false;
                s.goScreen('aorders');
              })),
        ),
      ]),
    );
  }

  final sv = statusState(o);
  final c = s.custOf(o);
  final r = _riderOf(s, o);
  final ph = c.phone.replaceAll(RegExp(r'[^\d+]'), '');

  final Widget? dock = sv < 4
      ? Btn('${_NXT[sv]}',
          icon: 'check',
          iconSize: 22,
          kind: sv == 3 ? BtnKind.green : BtnKind.primary,
          onPressed: () {
            final res = s.adminAdvance(o, sv + 1);
            if (res == 'need') {
              s.toast('Assign a rider first');
              _openAssignSheet(context, s, o.id);
            }
          })
      : null;

  final content = PadScroll(children: [
    // summary
    AquaCard(
      background: p.ice,
      child: RowW([
          Gal(o.items.isNotEmpty ? o.items[0].type : 'refill', h: 70),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(o.id, style: tx(context, 17, disp: true, w: FontWeight.w700, ls: 0.4)),
              Text('Placed: ${placed(o.createdAt)}',
                  style: para(context, color: p.muted, size: 13)),
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: OrdBadge(sv),
              ),
            ]),
          ),
        ],
      ),
    ),
    // issue / cancellation card
    if (o.issue != null)
      AquaCard(
        background: p.s0bg,
        borderColor: p.s0fg,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          RowW([
            Ic('alert', size: 22, color: p.ink),
            Text(o.cancelled ? 'Cancelled' : 'Issue reported',
                style: tx(context, 15, w: FontWeight.w700)),
          ]),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('${o.issue!.type}${o.issue!.text.isNotEmpty ? ': ${o.issue!.text}' : ''}',
                style: para(context, size: 13)),
          ),
          Text('${dfmt(o.issue!.ts)} · ${tfmt(o.issue!.ts)}',
              style: para(context, color: p.muted, size: 13)),
        ]),
      ),
    // customer
    AquaCard( child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: const SectionHead('Customer'),
        ),
        KvList(rows: [
          RowW([
            Ic('user', size: 20, color: p.blue),
            Expanded(
                child: Text(c.name,
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: tx(context, 15, w: FontWeight.w700))),
          ]),
          RowW([
            Ic('phone', size: 20, color: p.blue),
            Expanded(
                child: Text(c.phone.isEmpty ? 'No number' : c.phone,
                    style: numStyle(context, size: 15, color: p.ink))),
            if (c.phone.isNotEmpty) ...[
              _iconAction(context, 'phone', () async {
                try {
                  await launchUrl(Uri.parse('tel:$ph'), mode: LaunchMode.externalApplication);
                } catch (_) {}
              }, label: 'Call ${c.phone}'),
              _iconAction(context, 'copy', () async {
                await Clipboard.setData(ClipboardData(text: c.phone));
                s.toast('Copied');
              }, label: 'Copy phone number'),
            ],
          ]),
          RowW([
              Ic('pin', size: 20, color: p.blue),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(o.address.label, style: tx(context, 15, w: FontWeight.w700)),
                  const SizedBox(height: 1),
                  Text(o.address.line, softWrap: true, style: para(context, size: 13.5)),
                ]),
              ),
            ],
          ),
          RowW([
            Ic('clock', size: 20, color: p.blue),
            Expanded(child: Text(timeLabel(o.time), style: para(context, size: 13.5))),
          ]),
          if (o.note.isNotEmpty)
            RowW([
                Ic('pencil', size: 20, color: p.blue),
                Expanded(
                    child: Text(o.note, softWrap: true, style: para(context, size: 13.5))),
              ],
            ),
        ]),
      ]),
    ),
    // delivery map — store, door and rider on one screen; dispatch used to
    // have to open the rider app to answer "where is it now?".
    if (o.address.hasPin && s.station.lat != null && s.station.lng != null)
      _AdminOrderMap(
        station: LatLng(s.station.lat!, s.station.lng!),
        o: o,
        sv: sv,
      ),
    // order items
    AquaCard( child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: const SectionHead('Order Items'),
        ),
        for (final i in o.items)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: RowW([
              Gal(i.type, h: 70),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${s.nameOf(i.type)} × ${i.qty}',
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: tx(context, 16, disp: true, w: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text('${peso(_uprice(s, o, i.type))} / gallon',
                      style: numStyle(context, size: 13, color: p.muted)),
                ]),
              ),
              Text(peso(_uprice(s, o, i.type) * i.qty),
                  style: numStyle(context, size: 15, w: FontWeight.w700, color: p.ink)),
            ]),
          ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration:
              BoxDecoration(color: p.ice, borderRadius: BorderRadius.circular(14)),
          child: Row(children: [
            Flexible(
                child: Text('Total', style: tx(context, 20, disp: true, w: FontWeight.w700))),
            const SizedBox(width: 12),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Text(peso(o.total),
                    style: numStyle(context, size: 20, w: FontWeight.w700, disp: true, color: p.ink)),
              ),
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(o.pay == 'gcash' ? 'GCash on Delivery' : 'Cash on Delivery',
              style: para(context, color: p.muted, size: 13)),
        ),
      ]),
    ),
    // rider
    AquaCard( child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: SectionHead('Rider', icon: 'truck', iconSize: 22),
        ),
        if (r != null)
          RowW([
            Avatar(initialsOf(r.name), sm: true, bg: p.ice, fg: p.link),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(r.name,
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: tx(context, 15, w: FontWeight.w700)),
                Text('${r.phone} · ${r.vehicle}',
                    style: numStyle(context, size: 13, color: p.muted)),
              ]),
            ),
            OrdBadge(int.parse(AVS[r.available]!), label: AV[r.available]),
          ])
        else
          Text('No rider assigned yet.', style: para(context, color: p.muted)),
        if (sv < 3) ...[
          const SizedBox(height: 10),
          Btn(r != null ? 'Change Rider' : 'Assign Rider',
              kind: r != null ? BtnKind.alt : BtnKind.primary,
              onPressed: () => _openAssignSheet(context, s, o.id)),
        ],
      ]),
    ),
    // status timeline
    AquaCard( child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: const SectionHead('Status'),
        ),
        _Timeline(o),
      ]),
    ),
    if (sv < 4)
      Btn('Cancel Order',
          icon: 'close',
          iconSize: 22,
          kind: BtnKind.outd,
          onPressed: () {
            _confirmSheet(
              context,
              title: 'Cancel this order?',
              msg: _confirmText(context, 'Order ', o.id,
                  ' will be cancelled and the customer will be notified. Stock is returned.'),
              label: 'Cancel Order',
              danger: true,
              onConfirm: () {
                s.adminCancel(o.id);
                Navigator.of(context).pop();
              },
            );
          }),
  ]);

  return ScreenView(content: content, dock: dock);
}

/* =====================================================================
   _AdminOrderMap — read-only dispatch map for an order
   ===================================================================== */

/// Station, drop-off and rider on one map. The rider marker advances by
/// simulation from the order's stamps — dispatch needs to see where the order
/// is, not to drive, so no GPS subscription is opened here.
class _AdminOrderMap extends StatefulWidget {
  final LatLng station;
  final Order o;
  final int sv;
  const _AdminOrderMap({required this.station, required this.o, required this.sv});

  @override
  State<_AdminOrderMap> createState() => _AdminOrderMapState();
}

class _AdminOrderMapState extends State<_AdminOrderMap> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    // One repaint a second follows the simulated rider; anything faster keeps
    // the tile layer busy for no visible gain.
    if (widget.sv == 3) {
      _tick = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final o = widget.o;
    final dest = LatLng(o.address.lat!, o.address.lng!);
    final rider = o.riderId == null
        ? null
        : simulatedRiderPos(
            station: widget.station,
            o: o,
            now: DateTime.now().millisecondsSinceEpoch,
          );
    return AquaCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SectionHead('Delivery map', icon: 'map'),
        const SizedBox(height: 12),
        DeliveryTrackMap(
          station: widget.station,
          dest: dest,
          rider: rider,
          height: 200,
        ),
        const SizedBox(height: 8),
        Text(
          rider == null
              ? 'No rider assigned — the map shows the station and the drop-off.'
              : (o.status >= 4
                  ? 'Delivered. The rider marker sits at the drop-off.'
                  : 'Estimated rider position between the station and the drop-off.'),
          style: tx(context, 13, color: p.muted, h: 1.4),
        ),
      ]),
    );
  }
}

/* =====================================================================  
   adeliv — Deliveries board
   ===================================================================== */

Widget _dlcard(BuildContext context, AppState s, Order o) {
  final p = Pal.of(context);
  final c = s.custOf(o);
  final r = _riderOf(s, o);
  final st = o.status;
  Widget? road;
  final st3 = (o.stamps.length > 3) ? o.stamps[3] : null;
  if (st == 3 && st3 != null) road = Flexible(child: _RoadTime(st3));
  return AquaCard( child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      TapSurface(
        onTap: () {
          s.aid = o.id;
          s.goScreen('adetail');
        },
        semanticLabel: 'Order ${o.id}, ${c.name}',
        semanticButton: false,
        borderRadius: BorderRadius.circular(12),
        child: RowW([
            Gal(o.items.isNotEmpty ? o.items[0].type : 'refill', h: 70),
            // The status chip has to give way to the order details: laid out
            // beside an Expanded it used to claim its whole natural width and
            // squeeze this card past the screen at large text sizes.
            Expanded(
              flex: 3,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(o.id, style: tx(context, 15, disp: true, w: FontWeight.w700, ls: 0.4)),
                const SizedBox(height: 1),
                Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: para(context)),
                const SizedBox(height: 1),
                Text(o.address.line,
                    maxLines: 3, overflow: TextOverflow.ellipsis,
                    style: para(context, color: p.muted, size: 13)),
              ]),
            ),
            Flexible(
              flex: 2,
              child: Align(
                alignment: Alignment.centerRight,
                child: OrdBadge(statusState(o)),
              ),
            ),
          ],
        ),
      ),
      Row(children: [
        if (r != null) ...[
          Ic('truck', size: 18, color: p.blue),
          const SizedBox(width: 6),
          Flexible(
              child: Text(r.name,
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: tx(context, 13, w: FontWeight.w700))),
        ] else
          OrdBadge(0, label: 'No rider'),
        const Spacer(),
        if (road != null) ...[road, const SizedBox(width: 10)],
        if (st < 3)
          Btn(r != null ? 'Change' : 'Assign Rider',
              small: true,
              kind: r != null ? BtnKind.alt : BtnKind.primary,
              onPressed: () => _openAssignSheet(context, s, o.id)),
      ]),
    ]),
  );
}

/// "N min on the road" that keeps counting while the board stays open.
class _RoadTime extends StatefulWidget {
  final int since;
  const _RoadTime(this.since);
  @override
  State<_RoadTime> createState() => _RoadTimeState();
}

class _RoadTimeState extends State<_RoadTime> {
  Timer? _tmr;

  @override
  void initState() {
    super.initState();
    _tmr = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tmr?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mins =
        ((DateTime.now().millisecondsSinceEpoch - widget.since) / 60000).round();
    return Text('${mins < 1 ? 1 : mins} min on the road',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: numStyle(context, size: 13, color: Pal.of(context).muted));
  }
}

/// `secHead(t,n)` — section title with a count tag.
Widget _secHeadCount(BuildContext context, String title, int n) {
  return Row(children: [
    Expanded(child: SectionHead(title)),
    const SizedBox(width: 8),
    Tag('$n'),
  ]);
}

ScreenView adelivView(BuildContext context, AppState s) {
  final p = Pal.of(context);
  final now = _nowMs();
  final act = s.orders.where((o) => !o.cancelled && o.status < 4).toList();
  final needs = act.where((o) => o.riderId == null).toList();
  final way = act.where((o) => o.status == 3 && o.riderId != null).toList();
  final que = act.where((o) => o.riderId != null && o.status < 3).toList();
  final iss = s.orders
      .where((o) => o.issue != null && sod(o.issue!.ts) >= sod(now) - 7 * DAY)
      .toList()
    ..sort((a, b) => b.issue!.ts.compareTo(a.issue!.ts));
  final dn = s.orders
      .where((o) => statusState(o) == 4 && _doneAt(o) >= sod(now))
      .length;

  return ScreenView(content: PadScroll(children: [
    _statGrid([
      _rstatTile(context, bg: p.peachBg, fg: p.peachFg, num: '${needs.length}', label: 'Need a rider'),
      _rstatTile(context, bg: p.ice, fg: p.blue, num: '${way.length}', label: 'On the way'),
      _rstatTile(context, bg: p.s3bg, fg: p.s3fg, num: '${que.length}', label: 'Waiting to leave'),
      _rstatTile(context, bg: p.mintBg, fg: p.mintFg, num: '$dn', label: 'Delivered today'),
    ]),
    if (act.isEmpty)
      AquaCard(
        padding: const EdgeInsets.all(22),
        child: SizedBox(
          width: double.infinity,
          child: Column(children: [
            Text('No active deliveries', style: tx(context, 20, disp: true, w: FontWeight.w700)),
            const SizedBox(height: 10),
            Text('New orders will appear here.', style: para(context, color: p.muted)),
          ]),
        ),
      ),
    if (needs.isNotEmpty) ...[
      _secHeadCount(context, 'Needs a rider', needs.length),
      ...needs.map((o) => _dlcard(context, s, o)),
    ],
    if (way.isNotEmpty) ...[
      _secHeadCount(context, 'On the way', way.length),
      ...way.map((o) => _dlcard(context, s, o)),
    ],
    if (que.isNotEmpty) ...[
      _secHeadCount(context, 'Waiting to leave', que.length),
      ...que.map((o) => _dlcard(context, s, o)),
    ],
    if (iss.isNotEmpty) ...[
      _secHeadCount(context, 'Recent issues', iss.length),
      ...iss.map((o) {
        return AquaCard(
          background: p.s0bg,
          borderColor: p.s0fg,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: TapSurface(
            onTap: () {
              s.aid = o.id;
              s.goScreen('adetail');
            },
            semanticLabel: 'Issue on order ${o.id}',
            semanticButton: false,
            borderRadius: BorderRadius.circular(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Flexible(
                    child: Text(o.id,
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: tx(context, 14.5, disp: true, w: FontWeight.w700, ls: 0.4))),
                OrdBadge(statusState(o)),
              ]),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                    '${o.issue!.type}${o.issue!.text.isNotEmpty ? ': ${o.issue!.text}' : ''}',
                    style: para(context, size: 13)),
              ),
              Text('${s.custOf(o).name} · ${dfmt(o.issue!.ts)}, ${tfmt(o.issue!.ts)}',
                  style: para(context, color: p.muted, size: 13)),
            ]),
          ),
        );
      }),
    ],
    SectionHead('Riders', icon: 'users'),
    AquaCard( child: s.riders.where((r) => r.active != false).toList().isEmpty
          ? Text('No active riders.', style: para(context, color: p.muted))
          : KvList(
              rows: [
                for (final r in s.riders.where((r) => r.active != false))
                  RowW([
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(r.name,
                            maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: tx(context, 15, w: FontWeight.w700)),
                        Text('${r.vehicle} · ${s.loadOf(r)} active',
                            style: para(context, color: p.muted, size: 13)),
                      ]),
                    ),
                    OrdBadge(int.parse(AVS[r.available]!), label: AV[r.available]),
                  ]),
              ],
            ),
    ),
  ]));
}

/* =====================================================================
   aprod — Products & Prices
   ===================================================================== */

/// `invSeg(on)` — Products/Inventory segmented control shared by both screens.
Widget _invSeg(BuildContext context, AppState s, String on) {
  return SegBar(
    items: const [SegItem('prod', 'Products'), SegItem('inv', 'Inventory')],
    value: on,
    onSelect: (v) => s.goScreen(v == 'inv' ? 'ainv' : 'aprod'),
  );
}

class _PricesSheetBody extends StatefulWidget {
  final AppState s;
  const _PricesSheetBody(this.s);
  @override
  State<_PricesSheetBody> createState() => _PricesSheetBodyState();
}

class _PricesSheetBodyState extends State<_PricesSheetBody> {
  late final TextEditingController _r =
      TextEditingController(text: _priceStr(widget.s.products['refill']!.price));
  late final TextEditingController _b =
      TextEditingController(text: _priceStr(widget.s.products['buy']!.price));
  String _err = '';

  @override
  void dispose() {
    _r.dispose();
    _b.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      AquaField('Refill Gallon (₱ per gallon)', _r,
          kbType: const TextInputType.numberWithOptions(decimal: true)),
      const SizedBox(height: 14),
      AquaField('Buy Gallon (₱ per gallon)', _b,
          kbType: const TextInputType.numberWithOptions(decimal: true)),
      const SizedBox(height: 8),
      Text('New prices apply to new orders and to carts that are not checked out yet.',
          style: para(context, color: p.muted, size: 13)),
      const SizedBox(height: 8),
      ErrLine(_err),
      Btn('Save Prices', onPressed: () {
        final err = widget.s.updatePrices(_r.text, _b.text);
        if (err != null) {
          setState(() => _err = err);
        } else {
          Navigator.of(context).pop();
        }
      }),
    ]);
  }
}

class _ProdSheetBody extends StatefulWidget {
  final AppState s;
  final String k;
  const _ProdSheetBody(this.s, this.k);
  @override
  State<_ProdSheetBody> createState() => _ProdSheetBodyState();
}

class _ProdSheetBodyState extends State<_ProdSheetBody> {
  late final TextEditingController _price =
      TextEditingController(text: _priceStr(widget.s.products[widget.k]!.price));
  late final TextEditingController _desc =
      TextEditingController(text: widget.s.products[widget.k]!.desc);
  late bool _active = widget.s.products[widget.k]!.active;
  String _err = '';

  @override
  void dispose() {
    _price.dispose();
    _desc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      AquaField('Price per gallon (₱)', _price,
          kbType: const TextInputType.numberWithOptions(decimal: true)),
      const SizedBox(height: 14),
      AquaField('Description', _desc, maxLines: 3, minHeight: 96),
      const SizedBox(height: 12),
      CheckRow(
        value: _active,
        onChanged: (v) => setState(() => _active = v),
        label: 'Available to customers',
      ),
      const SizedBox(height: 8),
      Text('The new price applies to new orders. Existing orders keep the price they were placed at.',
          style: para(context, color: p.muted, size: 13)),
      const SizedBox(height: 8),
      ErrLine(_err),
      Btn('Save Product', onPressed: () {
        final v = nz(_price.text);
        if (!v.isFinite || v <= 0 || v > 9999) {
          setState(() => _err = 'Enter a price between ₱1 and ₱9,999.');
          return;
        }
        final d = _desc.text.trim();
        if (d.isEmpty) {
          setState(() => _err = 'Add a short description for customers.');
          return;
        }
        widget.s.updateProduct(widget.k, price: v, desc: d, active: _active);
        Navigator.of(context).pop();
      }),
    ]);
  }
}

void _openProdSheet(BuildContext context, AppState s, String k) {
  showAquaSheet(context, title: 'Edit ${s.nameOf(k)}', body: _ProdSheetBody(s, k));
}

ScreenView aprodView(BuildContext context, AppState s) {
  final p = Pal.of(context);
  final cs = s.stockState('containers');

  return ScreenView(content: 
    PadScroll(children: [
      _invSeg(context, s, 'prod'),
      for (final k in ['refill', 'buy'])
        AquaCard( child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            RowW([
                Gal(k, h: 84),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(
                          child: Text(s.nameOf(k),
                              style: tx(context, 19, disp: true, w: FontWeight.w700))),
                      _iconAction(context, 'pencil', () => _openProdSheet(context, s, k),
                          label: 'Edit ${s.nameOf(k)}'),
                    ]),
                    Text(s.descOf(k), style: para(context, color: p.muted, size: 13)),
                    const SizedBox(height: 6),
                    Tag('${peso(s.products[k]!.price)} / gallon',
                        fontSize: 15, minHeight: 32, padding: const EdgeInsets.symmetric(horizontal: 12)),
                  ]),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                  child: Text(
                      k == 'refill'
                          ? 'Customer provides the empty gallon'
                          : 'New filled gallon with container',
                      style: para(context, size: 13))),
              const SizedBox(width: 10),
              RowW([
                Text(s.products[k]!.active ? 'Available' : 'Hidden',
                    style: para(context, color: p.muted, size: 13)),
                AquaSwitch(
                    value: s.products[k]!.active,
                    onChanged: (_) => s.toggleProduct(k)),
              ], gap: 8),
            ]),
          ]),
        ),
      SectionHead('Inventory Summary', icon: 'coins'),
      AquaCard( child: RowW([
            Gal('buy', h: 70),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Gallon Containers',
                    style: tx(context, 17, disp: true, w: FontWeight.w700)),
                const SizedBox(height: 1),
                Text('For Buy Gallon', style: para(context, color: p.muted, size: 13)),
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: OrdBadge(int.parse(cs[1]),
                      label: '${s.inv['containers']!.qty} pcs'),
                ),
              ]),
            ),
            Btn('Manage', small: true, kind: BtnKind.alt, onPressed: () => s.goScreen('ainv')),
          ],
        ),
      ),
    ]),
    dock: Btn('Update Prices',
        icon: 'pencil',
        iconSize: 22,
        onPressed: () =>
            showAquaSheet(context, title: 'Update Prices', body: _PricesSheetBody(s))),
  );
}

/* =====================================================================
   ainv — Inventory
   ===================================================================== */

class _RestockSheetBody extends StatefulWidget {
  final AppState s;
  final String k;
  const _RestockSheetBody(this.s, this.k);
  @override
  State<_RestockSheetBody> createState() => _RestockSheetBodyState();
}

class _RestockSheetBodyState extends State<_RestockSheetBody> {
  final TextEditingController _qty = TextEditingController();
  final TextEditingController _note = TextEditingController();
  String _err = '';

  @override
  void dispose() {
    _qty.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final def = INV_DEFS[widget.k]!;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      AquaField('Quantity to add (${def.unit})', _qty, kbType: TextInputType.number),
      const SizedBox(height: 14),
      AquaField('Note (optional)', _note),
      const SizedBox(height: 8),
      ErrLine(_err),
      Btn('Add Stock', onPressed: () {
        final err = widget.s.restock(widget.k, _qty.text, _note.text);
        if (err != null) {
          setState(() => _err = err);
        } else {
          Navigator.of(context).pop();
        }
      }),
    ]);
  }
}

class _AdjustSheetBody extends StatefulWidget {
  final AppState s;
  final String k;
  const _AdjustSheetBody(this.s, this.k);
  @override
  State<_AdjustSheetBody> createState() => _AdjustSheetBodyState();
}

class _AdjustSheetBodyState extends State<_AdjustSheetBody> {
  late final TextEditingController _qty =
      TextEditingController(text: '${widget.s.inv[widget.k]!.qty}');
  late final TextEditingController _low =
      TextEditingController(text: '${widget.s.inv[widget.k]!.low}');
  String _err = '';

  @override
  void dispose() {
    _qty.dispose();
    _low.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final def = INV_DEFS[widget.k]!;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      AquaField('Counted stock (${def.unit})', _qty, kbType: TextInputType.number),
      const SizedBox(height: 14),
      AquaField('Reorder level', _low, kbType: TextInputType.number),
      const SizedBox(height: 8),
      ErrLine(_err),
      Btn('Save', onPressed: () {
        final err = widget.s.adjustStock(widget.k, _qty.text, _low.text);
        if (err != null) {
          setState(() => _err = err);
        } else {
          Navigator.of(context).pop();
        }
      }),
    ]);
  }
}

ScreenView ainvView(BuildContext context, AppState s) {
  final p = Pal.of(context);

  return ScreenView(content: 
    PadScroll(children: [
      _invSeg(context, s, 'inv'),
      for (final k in ['containers', 'water'])
        Builder(builder: (context) {
          final it = s.inv[k]!;
          final st = s.stockState(k);
          final m = INV_DEFS[k]!;
          final max4 = it.low * 4 > 0 ? it.low * 4 : 1;
          final pct =
              ((it.qty / max4) * 100).round().clamp(2, 100).toDouble();
          final meterColor = st[2] == 'warn'
              ? const Color(0xFFE0A100)
              : st[2] == 'bad'
                  ? p.danger
                  : p.blue;
          return AquaCard( child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              RowW([
                  if (k == 'containers')
                    Gal('buy', h: 70)
                  else
                    SizedBox(
                      width: 56,
                      height: 70,
                      child: Center(child: Ic('drop', size: 46, color: p.blue)),
                    ),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(m.name, style: tx(context, 17, disp: true, w: FontWeight.w700)),
                      const SizedBox(height: 1),
                      Text(m.sub, style: para(context, color: p.muted, size: 13)),
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        // Wrap, not Row: the qty + unit pair has to survive a 1.3x
                        // text scale without pushing past the card edge.
                        child: Wrap(crossAxisAlignment: WrapCrossAlignment.end,
                            spacing: 6, children: [
                          Text('${it.qty}',
                              style: numStyle(context, size: 22, w: FontWeight.w700, disp: true, color: p.ink)),
                          Text(m.unit,
                              style: para(context, color: p.muted, size: 14, w: FontWeight.w600)),
                        ]),
                      ),
                    ]),
                  ),
                  OrdBadge(int.parse(st[1]), label: st[0]),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                height: 10,
                width: double.infinity,
                decoration:
                    BoxDecoration(color: p.ice2, borderRadius: BorderRadius.circular(5)),
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: pct / 100,
                  child: Container(
                    decoration: BoxDecoration(
                        color: meterColor, borderRadius: BorderRadius.circular(5)),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('Reorder level: ${it.low} ${m.unit}',
                    style: para(context, color: p.muted, size: 13)),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  Btn('Restock',
                      small: true,
                      icon: 'plus',
                      iconSize: 18,
                      onPressed: () => showAquaSheet(context,
                          title: 'Restock ${m.name}', body: _RestockSheetBody(s, k))),
                  Btn('Adjust',
                      small: true,
                      kind: BtnKind.alt,
                      icon: 'pencil',
                      iconSize: 18,
                      onPressed: () => showAquaSheet(context,
                          title: 'Adjust ${m.name}', body: _AdjustSheetBody(s, k))),
                ],
              ),
            ]),
          );
        }),
      SectionHead('Recent Movements', icon: 'clock'),
      AquaCard( child: s.invLogList.isEmpty
            ? Text('No stock movements yet.', style: para(context, color: p.muted))
            : KvList(
                rows: [
                  for (final l in s.invLogList.take(12))
                    RowW([
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('${LOGK[l.kind] ?? l.kind} · ${INV_DEFS[l.item]?.name ?? l.item}',
                                maxLines: 1, overflow: TextOverflow.ellipsis,
                                style: tx(context, 15, w: FontWeight.w700)),
                            Text(
                                '${l.note.isNotEmpty ? '${l.note} · ' : ''}${dfmt(l.ts)}, ${tfmt(l.ts)}',
                                style: para(context, color: p.muted, size: 13)),
                          ]),
                        ),
                        Text('${l.delta > 0 ? '+' : ''}${l.delta}',
                            style: numStyle(context, size: 15, w: FontWeight.w800,
                                color: l.delta > 0 ? p.ok : p.danger)),
                      ],
                    ),
                ],
              ),
      ),
    ]),
  );
}

/* =====================================================================
   ausers — Users (riders / customers)
   ===================================================================== */

class _RiderFormBody extends StatefulWidget {
  final AppState s;
  final Rider? r;
  const _RiderFormBody(this.s, this.r);
  @override
  State<_RiderFormBody> createState() => _RiderFormBodyState();
}

class _RiderFormBodyState extends State<_RiderFormBody> {
  late final TextEditingController _name = TextEditingController(text: widget.r?.name ?? '');
  late final TextEditingController _phone = TextEditingController(text: widget.r?.phone ?? '');
  late final TextEditingController _email = TextEditingController(text: widget.r?.email ?? '');
  late final TextEditingController _pass = TextEditingController(text: widget.r?.pass ?? '');
  bool _obscure = true;
  String _err = '';

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _email.dispose();
    _pass.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      AquaField('Full name', _name),
      const SizedBox(height: 14),
      AquaField('Mobile number', _phone, kbType: TextInputType.phone),
      const SizedBox(height: 14),
      AquaField('Email (used to log in)', _email, kbType: TextInputType.emailAddress),
      const SizedBox(height: 14),
      AquaField('Password (at least 4 characters)', _pass,
          obscure: _obscure,
          eyeToggle: true,
          onEye: () => setState(() => _obscure = !_obscure)),
      const SizedBox(height: 8),
      ErrLine(_err),
      Btn(widget.r != null ? 'Save Rider' : 'Add Rider', onPressed: () {
        setState(() => _err = '');
        if (_name.text.trim().length < 2) {
          setState(() => _err = 'Enter the rider’s full name.');
          return;
        }
        if (_phone.text.trim().replaceAll(RegExp(r'\D'), '').length < 10) {
          setState(() => _err = 'Enter a mobile number with at least 10 digits.');
          return;
        }
        if (!isEmail(_email.text.trim().toLowerCase())) {
          setState(() => _err = 'Enter a valid email address.');
          return;
        }
        if (_pass.text.length < 4) {
          setState(() => _err = 'Choose a password with at least 4 characters.');
          return;
        }
        final err = widget.s.saveRider(
            id: widget.r?.id,
            name: _name.text,
            phone: _phone.text,
            vehicle: widget.r?.vehicle ?? 'Motorcycle',
            plate: widget.r?.plate ?? '',
            email: _email.text,
            pass: _pass.text);
        if (err != null) {
          setState(() => _err = err);
        } else {
          Navigator.of(context).pop();
        }
      }),
    ]);
  }
}

class _CustAgg {
  String name = '';
  String phone = '';
  int n = 0;
  double spent = 0;
  int last = 0;
}

ScreenView ausersView(BuildContext context, AppState s) {
  final p = Pal.of(context);
  final t = s.autab;

  final List<Widget> body;
  if (t == 'riders') {
    body = [
      // One flat row with a short button label: the two nested rows overflowed
      // by 9px once "Add Rider" grew with the text scale on a 320dp screen.
      Row(children: [
        const Expanded(child: SectionHead('Riders', icon: 'truck')),
        const SizedBox(width: 8),
        Tag('${s.riders.length}'),
        const SizedBox(width: 10),
        Btn('Add',
            small: true,
            icon: 'plus',
            iconSize: 18,
            onPressed: () =>
                showAquaSheet(context, title: 'Add Rider', body: _RiderFormBody(s, null))),
      ]),
      if (s.riders.isNotEmpty)
        ...s.riders.map((r) {
          final d = s.orders.where((o) => o.riderId == r.id && statusState(o) == 4).length;
          return AquaCard( child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              RowW([
                Avatar(initialsOf(r.name), sm: true, bg: p.ice, fg: p.link),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Flexible(
                          child: Text(r.name,
                              maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: tx(context, 15, w: FontWeight.w700))),
                      if (r.active == false) ...[
                        const SizedBox(width: 8),
                        Tag('Deactivated'),
                      ],
                    ]),
                    Text(r.phone, style: numStyle(context, size: 13, color: p.muted)),
                  ]),
                ),
                if (r.active != false)
                  OrdBadge(int.parse(AVS[r.available]!), label: AV[r.available]),
              ]),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Flexible(
                    child: Text(r.plate.isNotEmpty ? '${r.vehicle} · ${r.plate}' : r.vehicle,
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: para(context, size: 13))),
                Text('${s.loadOf(r)} active · $d done',
                    style: numStyle(context, size: 13, color: p.ink)),
              ]),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  Btn('Edit',
                      small: true,
                      kind: BtnKind.alt,
                      icon: 'pencil',
                      iconSize: 18,
                      onPressed: () => showAquaSheet(context,
                          title: 'Edit Rider', body: _RiderFormBody(s, r))),
                  Btn(r.active == false ? 'Activate' : 'Deactivate',
                      small: true,
                      kind: BtnKind.alt,
                      onPressed: () {
                        if (r.active == false) {
                          _confirmSheet(context,
                              title: 'Activate ${r.name}?',
                              msg: Text('They can log in and receive deliveries again.',
                                  style: para(context, color: Pal.of(context).muted)),
                              label: 'Activate',
                              danger: false,
                              keep: 'Not now',
                              onConfirm: () {
                                s.toggleRiderActive(r.id);
                                Navigator.of(context).pop();
                              });
                        } else {
                          _confirmSheet(context,
                              title: 'Deactivate ${r.name}?',
                              msg: Text(
                                  'They will be logged out of new work. Deliveries not yet started are moved to other riders. Deliveries already on the road stay with them.',
                                  style: para(context, color: Pal.of(context).muted)),
                              label: 'Deactivate',
                              danger: true,
                              keep: 'Keep active',
                              onConfirm: () {
                                s.toggleRiderActive(r.id);
                                Navigator.of(context).pop();
                              });
                        }
                      }),
                ],
              ),
            ]),
          );
        })
      else
        AquaCard(
          padding: const EdgeInsets.all(22),
          child: SizedBox(
              width: double.infinity,
              child: Text('No riders yet. Add your first rider.',
                  textAlign: TextAlign.center, style: para(context))),
        ),
    ];
  } else {
    final Map<String, _CustAgg> m = {};
    for (final o in s.orders) {
      final c = s.custOf(o);
      final k = c.phone.isNotEmpty ? c.phone : c.name;
      final e = m.putIfAbsent(
          k,
          () => _CustAgg()
            ..name = c.name
            ..phone = c.phone);
      e.n++;
      if (statusState(o) == 4) e.spent += o.total;
      if (o.createdAt > e.last) e.last = o.createdAt;
    }
    final list = m.values.toList()..sort((a, b) => b.spent.compareTo(a.spent));
    body = [
      Row(children: [
        Expanded(child: SectionHead('Customers', icon: 'users')),
        const SizedBox(width: 8),
        Tag('${list.length}'),
      ]),
      if (list.isNotEmpty)
        ...list.map((c) => AquaCard( child: RowW([
                  Avatar(initialsOf(c.name), sm: true, bg: p.ice, fg: p.link),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(c.name,
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: tx(context, 15, w: FontWeight.w700)),
                      Text(c.phone.isEmpty ? 'No number' : c.phone,
                          style: numStyle(context, size: 13, color: p.muted)),
                      const SizedBox(height: 2),
                      Text('Last order ${dfmt(c.last)}',
                          style: para(context, color: p.muted, size: 13)),
                    ]),
                  ),
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text(peso(c.spent),
                        style: numStyle(context, size: 15, w: FontWeight.w700, color: p.ink)),
                    Text(_plOk(c.n, 'order'),
                        style: para(context, color: p.muted, size: 13)),
                  ]),
                ],
              ),
            ))
      else
        AquaCard(
          padding: const EdgeInsets.all(22),
          child: SizedBox(
              width: double.infinity,
              child: Text('Customers appear after their first order.',
                  textAlign: TextAlign.center, style: para(context))),
        ),
    ];
  }

  return ScreenView(content: PadScroll(children: [
    SegBar(
      items: const [SegItem('riders', 'Riders'), SegItem('customers', 'Customers')],
      value: t,
      onSelect: (v) {
        s.autab = v;
        s.save();
        s.updateUI();
      },
    ),
    ...body,
  ]));
}

/* =====================================================================
   areports — Reports + daily sales chart
   ===================================================================== */

class _DayStat {
  final double v;
  final int n;
  final String short;
  final String long;
  const _DayStat(this.v, this.n, this.short, this.long);
}

/// `fm(v)` — ₱k axis labels with no trailing `.0`.
String _fm(double v) {
  if (v >= 1000) {
    final x = (v / 100).round() / 10;
    final sx = x == x.roundToDouble() ? x.toInt().toString() : x.toString();
    return '₱${sx}k';
  }
  return '₱${v.round()}';
}

class _SalesPainter extends CustomPainter {
  final List<_DayStat> days;
  final double top;
  final int maxI;
  final Pal p;
  _SalesPainter({required this.days, required this.top, required this.maxI, required this.p});

  void _txt(Canvas c, String text, double x, double y,
      {bool bold = false, Color? color, required int align}) {
    final tp = TextPainter(
      text: TextSpan(
          text: text,
          style: TextStyle(
            fontFamily: 'Nunito Sans',
            fontSize: 11,
            fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
            color: color ?? p.muted,
          )),
      textDirection: TextDirection.ltr,
    );
    tp.layout();
    final dx = align == 0 ? x - tp.width / 2 : (align == 1 ? x - tp.width : x);
    tp.paint(c, Offset(dx, y - tp.height / 2));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final width = size.width;
    const L = 46.0, R = 10.0, T = 28.0, B = 30.0, H = 210.0;
    final pw = width - L - R;
    final ph = H - T - B;
    final y0 = T + ph;
    double y(double v) => T + ph - (v / top) * ph;
    final slot = pw / days.length;
    final bw = math.min(28.0, slot - 14);

    // gridlines + axis labels (0 / mid / top)
    final grid = Paint()
      ..strokeWidth = 1
      ..color = p.line;
    for (final t in [0.0, top / 2, top]) {
      canvas.drawLine(Offset(L, y(t)), Offset(width - R, y(t)), grid);
      _txt(canvas, _fm(t), L - 6, y(t) + 4, align: 1);
    }
    // bars
    for (var i = 0; i < days.length; i++) {
      final d = days[i];
      final cx = L + slot * i + slot / 2;
      final x = cx - bw / 2;
      final h = (d.v / top) * ph;
      if (d.v > 0) {
        final yy = y0 - h;
        final r = h < 4 ? h : 4.0;
        final fill = Paint()
          ..color = p.blue.withValues(alpha: i == days.length - 1 ? 1 : 0.62);
        canvas.drawRRect(
          RRect.fromRectAndCorners(
            Rect.fromLTRB(x, yy, x + bw, y0),
            topLeft: Radius.circular(r),
            topRight: Radius.circular(r),
          ),
          fill,
        );
        if (i == maxI || i == days.length - 1) {
          _txt(canvas, _fm(d.v), cx, yy - 8, color: p.muted, align: 0);
        }
      }
      _txt(canvas, d.short, cx, H - 10,
          bold: i == days.length - 1,
          color: i == days.length - 1 ? p.ink : p.muted,
          align: 0);
    }
    // baseline axis on top
    final base = Paint()
      ..strokeWidth = 1
      ..color = p.muted;
    canvas.drawLine(Offset(L, y0), Offset(width - R, y0), base);
  }

  @override
  bool shouldRepaint(covariant _SalesPainter old) =>
      old.top != top || old.maxI != maxI || old.p != p || old.days.length != days.length;
}

class _SalesChart extends StatefulWidget {
  final AppState s;
  final List<_DayStat> days;
  const _SalesChart(this.s, this.days);
  @override
  State<_SalesChart> createState() => _SalesChartState();
}

class _SalesChartState extends State<_SalesChart> {
  String _readout = 'Tap a bar to see that day.';
  bool _table = false;

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final days = widget.days;
    // nice top value — mag = 10^floor(log10(max)), top = first of [1,2,2.5,5,10]*mag >= max
    final mx = days.fold(1.0, (a, d) => d.v > a ? d.v : a);
    final mag =
        math.pow(10, (math.log(mx) / math.ln10).floor()).toDouble();
    double top = 0;
    for (final m in [1.0, 2.0, 2.5, 5.0, 10.0]) {
      final cand = m * mag;
      if (cand >= mx) {
        top = cand;
        break;
      }
    }
    if (top == 0) top = mx;
    var maxI = 0;
    for (var i = 0; i < days.length; i++) {
      if (days[i].v > days[maxI].v) maxI = i;
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SizedBox(height: 8),
      LayoutBuilder(builder: (context, box) {
        final w = box.maxWidth.isFinite ? box.maxWidth : 360.0;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (d) {
            const L = 46.0, R = 10.0, T = 28.0, H = 210.0;
            final pw = w - L - R;
            final ph = H - T - 30.0;
            final slot = pw / days.length;
            if (d.localPosition.dx < L || d.localPosition.dx > w - R) return;
            if (d.localPosition.dy < T || d.localPosition.dy > T + ph) return;
            final i =
                ((d.localPosition.dx - L) / slot).floor().clamp(0, days.length - 1);
            setState(() {
              _readout =
                  '${days[i].long}: ${peso(days[i].v)} from ${_plOk(days[i].n, 'delivery')}';
            });
          },
          child: CustomPaint(
            size: Size(w, 210),
            painter: _SalesPainter(days: days, top: top, maxI: maxI, p: p),
          ),
        );
      }),
      const SizedBox(height: 4),
      SizedBox(height: 20, child: Text(_readout, style: para(context, size: 13))),
      TapSurface(
        onTap: () => setState(() => _table = !_table),
        semanticLabel: _table ? 'Hide table view' : 'View as table',
        borderRadius: BorderRadius.circular(12),
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          alignment: Alignment.centerLeft,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text('View as table', style: tx(context, 13, w: FontWeight.w700, color: p.link)),
            const SizedBox(width: 6),
            Ic('chev', size: 16, color: p.link),
          ]),
        ),
      ),
      if (_table)
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final d in days)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(children: [
                Expanded(child: Text(d.long, style: numStyle(context, size: 13, color: p.ink))),
                Flexible(
                    child: Text('${peso(d.v)} · ${d.n}',
                        textAlign: TextAlign.end,
                        style: numStyle(context, size: 13, color: p.ink))),
              ]),
            ),
        ]),
    ]);
  }
}

Widget _rbar(BuildContext context, String label, String right, double v, double mx) {
  final p = Pal.of(context);
  final pct = ((v / mx) * 100).round().clamp(v > 0 ? 3 : 0, 100).toDouble();
  return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Row(children: [
      Expanded(child: Text(label, style: tx(context, 15, w: FontWeight.w700))),
      Flexible(
          child: Text(right,
              textAlign: TextAlign.end, style: numStyle(context, size: 13, color: p.ink))),
    ]),
    const SizedBox(height: 6),
    Container(
      height: 10,
      width: double.infinity,
      decoration: BoxDecoration(color: p.ice2, borderRadius: BorderRadius.circular(5)),
      child: FractionallySizedBox(
        alignment: Alignment.centerLeft,
        widthFactor: (v > 0 ? pct : 0) / 100,
        child: Container(
            decoration:
                BoxDecoration(color: p.blue, borderRadius: BorderRadius.circular(5))),
      ),
    ),
  ]);
}

Widget _kpi(BuildContext context, String label, String value) {
  final p = Pal.of(context);
  return AquaCard(
    background: p.ice,
    padding: const EdgeInsets.all(12),
    child: SizedBox(
      width: double.infinity,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: para(context, color: p.muted, size: 13)),
        const SizedBox(height: 2),
        Text(value,
            style: numStyle(context, size: 20, w: FontWeight.w700, disp: true, color: p.ink)),
      ]),
    ),
  );
}

ScreenView areportsView(BuildContext context, AppState s) {
  final p = Pal.of(context);
  final now = _nowMs();
  final perList = [
    ['today', PER['today']!],
    ['7d', PER['7d']!],
    ['30d', PER['30d']!],
    ['all', PER['all']!],
  ];
  final from = s.areport == 'today'
      ? sod(now)
      : s.areport == '7d'
          ? now - 7 * DAY
          : s.areport == '30d'
              ? now - 30 * DAY
              : 0;
  final list = s.orders.where((o) => o.createdAt >= from).toList();
  final del = list.where((o) => statusState(o) == 4).toList();
  final canc = list.where((o) => statusState(o) == 5).toList();
  final rev = _osum(del);
  final avg = del.isNotEmpty ? rev / del.length : 0.0;
  final fin = del.length + canc.length;
  final rate = fin > 0 ? '${((del.length / fin) * 100).round()}%' : '—';
  final tm = del.isNotEmpty
      ? del.fold<int>(0, (a, o) => a + (_doneAt(o) - o.createdAt)) / del.length / 60000
      : 0.0;
  final tmT = del.isEmpty ? '—' : (tm < 1 ? '<1 min' : '${tm.round()} min');

  // chart data — delivered orders per day, last 7 days
  final days = <_DayStat>[];
  for (var i = 6; i >= 0; i--) {
    final st = sod(now) - i * DAY;
    final en = st + DAY;
    final l = s.orders
        .where((o) => statusState(o) == 4 && _doneAt(o) >= st && _doneAt(o) < en)
        .toList();
    final dt = DateTime.fromMillisecondsSinceEpoch(st);
    days.add(_DayStat(_osum(l), l.length, dayShort(dt), '${dayLong(dt)}, ${dfmt(st)}'));
  }

  final gRefill = _gsum(del, 'refill');
  final irRefill = _irev(s, del, 'refill');
  final gBuy = _gsum(del, 'buy');
  final irBuy = _irev(s, del, 'buy');
  final pmax = [1.0, irRefill, irBuy].reduce((a, b) => a > b ? a : b);
  final cash = _osum(del.where((o) => o.pay != 'gcash').toList());
  final gc = _osum(del.where((o) => o.pay == 'gcash').toList());
  final cmax = [1.0, cash, gc].reduce((a, b) => a > b ? a : b);

  final summary = 'AQUARUN report (${PER[s.areport]}): sales ${peso(rev)}, ${del.length} delivered, '
      '${canc.length} cancelled, $gRefill refill and $gBuy buy gallons.';

  return ScreenView(content: PadScroll(children: [
    SegBar(
      small: true,
      items: [for (final x in perList) SegItem(x[0], x[1])],
      value: s.areport,
      onSelect: (v) {
        s.areport = v;
        s.save();
        s.updateUI();
      },
    ),
    AquaCard(
      background: p.ice,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Sales · ${PER[s.areport]}', style: para(context, color: p.muted)),
        Text(peso(rev),
            style: numStyle(context, size: 34, w: FontWeight.w700, disp: true, color: p.ink)),
        Text('${_plOk(del.length, 'completed delivery')} of ${pl(list.length, 'order')} placed',
            style: para(context, color: p.muted, size: 13)),
      ]),
    ),
    _statGrid([
      _kpi(context, 'Average order', peso(avg)),
      _kpi(context, 'Completion rate', rate),
      _kpi(context, 'Cancelled', '${canc.length}'),
      _kpi(context, 'Avg. delivery time', tmT),
    ]),
    AquaCard( child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SectionHead('Daily sales'),
        Text('Delivered orders, last 7 days', style: para(context, color: p.muted, size: 13)),
        _SalesChart(s, days),
      ]),
    ),
    AquaCard( child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SectionHead('Gallons delivered'),
        const SizedBox(height: 10),
        _rbar(context, 'Refill Gallon', '$gRefill gallons · ${peso(irRefill)}', irRefill, pmax),
        const SizedBox(height: 10),
        _rbar(context, 'Buy Gallon', '$gBuy gallons · ${peso(irBuy)}', irBuy, pmax),
      ]),
    ),
    AquaCard( child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SectionHead('Payments collected'),
        const SizedBox(height: 10),
        _rbar(context, 'Cash on Delivery', peso(cash), cash, cmax),
        const SizedBox(height: 10),
        _rbar(context, 'GCash on Delivery', peso(gc), gc, cmax),
      ]),
    ),
    AquaCard( child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: const SectionHead('Rider deliveries'),
        ),
        s.riders.isEmpty
            ? Text('No riders yet.', style: para(context, color: p.muted))
            : KvList(
                rows: [
                  for (final r in s.riders)
                    RowW([
                        Expanded(
                          child:
                              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(r.name,
                                maxLines: 1, overflow: TextOverflow.ellipsis,
                                style: tx(context, 15, w: FontWeight.w700)),
                            Builder(builder: (_) {
                              final d = del.where((o) => o.riderId == r.id).length;
                              final is2 =
                                  list.where((o) => o.riderId == r.id && o.issue != null).length;
                              var t2 = _plOk(d, 'delivery');
                              if (is2 > 0) t2 += ' · ${_plOk(is2, 'issue')}';
                              return Text(t2, style: para(context, color: p.muted, size: 13));
                            }),
                          ]),
                        ),
                        Text(peso(_osum(del.where((o) => o.riderId == r.id).toList())),
                            style: numStyle(context, size: 15, w: FontWeight.w700, color: p.ink)),
                      ],
                    ),
                ],
              ),
      ]),
    ),
    Btn('Copy summary',
        kind: BtnKind.alt,
        icon: 'copy',
        iconSize: 20,
        onPressed: () async {
          await Clipboard.setData(ClipboardData(text: summary));
          s.toast('Summary copied');
        }),
  ]));
}

/* =====================================================================
   adminProfile — My Profile (admin)
   ===================================================================== */

class _ProfileSheetBody extends StatefulWidget {
  final AppState s;
  const _ProfileSheetBody(this.s);
  @override
  State<_ProfileSheetBody> createState() => _ProfileSheetBodyState();
}

class _ProfileSheetBodyState extends State<_ProfileSheetBody> {
  late final TextEditingController _name = TextEditingController(text: widget.s.admin?.name ?? '');
  late final TextEditingController _phone = TextEditingController(text: widget.s.admin?.phone ?? '');
  late final TextEditingController _email = TextEditingController(text: widget.s.admin?.email ?? '');
  String _err = '';

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _email.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      AquaField('Full name', _name),
      const SizedBox(height: 14),
      AquaField('Mobile number', _phone, kbType: TextInputType.phone),
      const SizedBox(height: 14),
      AquaField('Email', _email, kbType: TextInputType.emailAddress),
      const SizedBox(height: 8),
      ErrLine(_err),
      Btn('Save Changes', onPressed: () {
        setState(() => _err = '');
        if (_name.text.trim().length < 2) {
          setState(() => _err = 'Enter your full name.');
          return;
        }
        if (!isEmail(_email.text.trim().toLowerCase())) {
          setState(() => _err = 'Enter a valid email address.');
          return;
        }
        final err = widget.s
            .updateAdminProfile(name: _name.text, email: _email.text, phone: _phone.text);
        if (err.isNotEmpty) {
          setState(() => _err = err);
        } else {
          Navigator.of(context).pop();
        }
      }),
    ]);
  }
}

ScreenView adminProfileView(BuildContext context, AppState s) {
  final p = Pal.of(context);
  final ad = s.admin;

  return ScreenView(content: PadScroll(children: [
    AquaCard( child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        RowW([
            Avatar(initialsOf(ad?.name)),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(ad?.name ?? '',
                      maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: tx(context, 20, disp: true, w: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Wrap(children: [Tag('Administrator')]),
                ]),
              ),
            ),
            _iconAction(context, 'pencil',
                () => showAquaSheet(context, title: 'Edit Profile', body: _ProfileSheetBody(s)),
                label: 'Edit profile'),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: KvList(rows: [
            RowW([
              Ic('phone', size: 20, color: p.blue),
              Expanded(
                  child: Text(ad == null || ad.phone.isEmpty ? 'Add mobile number' : ad.phone,
                      style: numStyle(context, size: 15, color: p.ink))),
            ]),
            RowW([
                Ic('mail', size: 20, color: p.blue),
                Expanded(
                    child: Text(ad?.email ?? '', softWrap: true, style: para(context, size: 13.5))),
              ],
            ),
            RowW([
              Ic('store', size: 20, color: p.blue),
              Expanded(
                  child: Text(s.station.name,
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: para(context, size: 13.5))),
            ]),
          ]),
        ),
      ]),
    ),
    _statGrid([
      AquaCard(
        background: p.ice,
        padding: const EdgeInsets.all(14),
        child: SizedBox(
          width: double.infinity,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Orders managed', style: para(context, color: p.muted, size: 13)),
            Text('${s.orders.length}',
                style: numStyle(context, size: 20, w: FontWeight.w700, disp: true, color: p.ink)),
          ]),
        ),
      ),
      AquaCard(
        background: p.ice,
        padding: const EdgeInsets.all(14),
        child: SizedBox(
          width: double.infinity,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Riders', style: para(context, color: p.muted, size: 13)),
            Text('${s.riders.length}',
                style: numStyle(context, size: 20, w: FontWeight.w700, disp: true, color: p.ink)),
          ]),
        ),
      ),
    ]),
    Btn('Log Out',
        kind: BtnKind.alt,
        icon: 'logout',
        iconSize: 20,
        onPressed: () {
          _confirmSheet(
            context,
            title: 'Log out of AQUARUN?',
            msg: Text('Your saved addresses and orders stay on this device. Log back in any time.',
                style: para(context, color: p.muted)),
            label: 'Log Out',
            danger: false,
            onConfirm: () {
              Navigator.of(context).pop();
              s.logout();
            },
          );
        }),
  ]));
}

/* =====================================================================
   adminSettings — Settings (admin)
   ===================================================================== */

/// `swRow(t,s,act,on)` — switch row card.
Widget _swRow(BuildContext context, String title, String sub, bool value, VoidCallback onToggle) {
  return AquaCard( child: Row(children: [
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: tx(context, 15, w: FontWeight.w700)),
          const SizedBox(height: 1),
          Text(sub, style: para(context, color: Pal.of(context).muted, size: 13)),
        ]),
      ),
      const SizedBox(width: 12),
      AquaSwitch(value: value, onChanged: (_) => onToggle()),
    ]),
  );
}

/// `autoCard()`.
class _AutoProgressCard extends StatelessWidget {
  final AppState s;
  const _AutoProgressCard(this.s);

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return AquaCard( child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Auto-progress demo orders', style: tx(context, 15, w: FontWeight.w700)),
            const SizedBox(height: 1),
            Text(
                'When on, new orders are confirmed and prepared on their own. Out for delivery and Delivered always come from the rider.',
                style: para(context, color: p.muted, size: 13)),
          ]),
        ),
        const SizedBox(width: 12),
        AquaSwitch(value: s.settings.autoDeliver, onChanged: (_) => s.toggleAutoDeliver()),
      ]),
    );
  }
}

class _StationForm extends StatefulWidget {
  final AppState s;
  const _StationForm(this.s);
  @override
  State<_StationForm> createState() => _StationFormState();
}

class _StationFormState extends State<_StationForm> {
  late final TextEditingController _name = TextEditingController(text: widget.s.station.name);
  late final TextEditingController _phone = TextEditingController(text: widget.s.station.phone);
  late final TextEditingController _addr = TextEditingController(text: widget.s.station.address);
  late final TextEditingController _open = TextEditingController(text: widget.s.station.open);
  late final TextEditingController _close = TextEditingController(text: widget.s.station.close);
  double? _lat;
  double? _lng;
  bool _pinChanged = false;
  String _err = '';

  @override
  void initState() {
    super.initState();
    _lat = widget.s.station.lat;
    _lng = widget.s.station.lng;
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _addr.dispose();
    _open.dispose();
    _close.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return AquaCard( child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SectionHead('Business Details', icon: 'store'),
        const SizedBox(height: 14),
        AquaField('Station name', _name),
        const SizedBox(height: 14),
        AquaField('Contact number', _phone, kbType: TextInputType.phone),
        const SizedBox(height: 14),
        AquaField('Address', _addr),
        const SizedBox(height: 14),
        Btn(_lat == null || _pinChanged ? 'Set station pin on map' : 'Adjust station pin on map',
            icon: 'pin',
            kind: _lat == null ? BtnKind.primary : BtnKind.alt,
            onPressed: () async {
              final picked = await openPinPickerPage(
                context,
                initial: _lat != null && _lng != null ? LatLng(_lat!, _lng!) : null,
              );
              if (picked != null) {
                // Offer the resolved address if the field is empty.
                final line = [
                  picked.street,
                  picked.brgy,
                  picked.city,
                ].where((s) => s.isNotEmpty).join(', ');
                if (line.isNotEmpty && _addr.text.trim().isEmpty) {
                  _addr.text = line;
                }
                setState(() {
                  _lat = picked.point.latitude;
                  _lng = picked.point.longitude;
                  _pinChanged = true;
                });
              }
            }),
        Text(
          _lat == null
              ? 'No station pin yet — set it so delivery routes start from your actual location.'
              : 'Station pin at (${_lat!.toStringAsFixed(5)}, ${_lng!.toStringAsFixed(5)}).'
                  '${_pinChanged ? ' Press Save Details to apply.' : ''}',
          style: tx(context, 13, color: p.muted, h: 1.4),
        ),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: AquaField('Opens', _open, kbType: TextInputType.datetime, hint: '07:00')),
          const SizedBox(width: 12),
          Expanded(child: AquaField('Closes', _close, kbType: TextInputType.datetime, hint: '19:00')),
        ]),
        const SizedBox(height: 8),
        ErrLine(_err),
        Btn('Save Details', onPressed: () {
          setState(() => _err = '');
          if (_name.text.trim().length < 2) {
            setState(() => _err = 'Enter the station name.');
            return;
          }
          if (_open.text.isEmpty || _close.text.isEmpty) {
            setState(() => _err = 'Set the opening and closing time.');
            return;
          }
          widget.s.updateStation(
              name: _name.text,
              phone: _phone.text,
              address: _addr.text,
              open: _open.text,
              close: _close.text,
              lat: _lat,
              lng: _lng,
              setPin: _pinChanged);
        }),
      ]),
    );
  }
}

ScreenView adminSettingsView(BuildContext context, AppState s) {
  final p = Pal.of(context);

  return ScreenView(content: PadScroll(children: [
    _swRow(context, 'Accepting orders', 'Turn off to stop customers from placing new orders.',
        s.station.accepting, s.toggleAccepting),
    _swRow(
        context,
        'Auto-assign riders',
        'New orders go to the available rider with the fewest deliveries.',
        s.station.autoAssign,
        s.toggleAutoAssign),
    _StationForm(s),
    _AutoProgressCard(s),
    _swRow(context, 'Order alerts', 'Show notifications for new orders, issues and low stock.',
        s.settings.notify, s.toggleNotify),
    AquaCard( child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SectionHead('Appearance'),
        const SizedBox(height: 10),
        SegBar(
          items: const [SegItem('system', 'System'), SegItem('light', 'Light'), SegItem('dark', 'Dark')],
          value: s.settings.theme,
          onSelect: (v) {
            s.settings.theme = v;
            s.save();
            s.updateUI();
          },
        ),
      ]),
    ),
    Btn('Reset demo data',
        kind: BtnKind.outd,
        onPressed: () {
          _confirmSheet(
            context,
            title: 'Reset demo data?',
            msg: Text(
                'This clears every account, order, rider and stock level saved in this browser and starts fresh.',
                style: para(context, color: p.muted)),
            label: 'Reset Everything',
            danger: true,
            keep: 'Cancel',
            onConfirm: () {
              Navigator.of(context).pop();
              s.resetAll();
            },
          );
        }),
    Center(
      child: Text('AQUARUN · Admin app',
          textAlign: TextAlign.center, style: para(context, color: p.muted, size: 13)),
    ),
  ]));
}
