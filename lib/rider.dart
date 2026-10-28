import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import 'art.dart';
import 'constants.dart';
import 'firebase_boot.dart';
import 'icons.dart';
import 'models.dart';
import 'palette.dart';
import 'state.dart';
import 'tracking_map.dart';
import 'widgets.dart';

/* ================= rider app (1:1 port of the HTML rider screens) ================= */

T? firstBy<T>(Iterable<T> l, bool Function(T) t) {
  for (final x in l) {
    if (t(x)) return x;
  }
  return null;
}

/* ---------- shared rider bits ---------- */

/// Adapter matching the shared contract: named content/dock/bare.
ScreenView view(Widget content, {Widget? dock, bool bare = false}) =>
    ScreenView(content: content, dock: dock, bare: bare);

/// Adapter: thin named-argument wrapper around AquaCard.
Widget card({required Widget child, Color? background, Color? borderColor, EdgeInsets? padding}) =>
    AquaCard(background: background, borderColor: borderColor, padding: padding, child: child);

TextStyle oidStyle(BuildContext c, {double size = 15}) =>
    tx(c, size, disp: true, w: FontWeight.w700, ls: 0.4);

/// `.dcard` — delivery card button (rider variant with address line + isub).
class RCard extends StatelessWidget {
  final AppState s;
  final Order o;
  final bool compact;
  const RCard({super.key, required this.s, required this.o, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final c = s.custOf(o);
    final st = s.rstate(o);
    return GestureDetector(
      onTap: () {
        s.detailId = o.id;
        s.goScreen('rdetail');
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: p.card,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: p.line),
          boxShadow: p.shadow,
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (o.items.isNotEmpty) ...[
              Gal(o.items[0].type, h: compact ? 44 : 70),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(o.id, style: oidStyle(context)),
                Text(c.name, style: para(context)),
                const SizedBox(height: 4),
                RowW([
                  Ic('pin', size: 15, color: p.blue),
                  Expanded(
                    child: Text(o.address.line,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: tx(context, 13, color: p.muted)),
                  ),
                ], gap: 6, cross: CrossAxisAlignment.start),
              ]),
            ),
            const SizedBox(width: 10),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              OrdBadge(st, label: RLBL[st]),
              const SizedBox(height: 10),
              Ic('chev', size: 20, color: p.muted),
            ]),
          ]),
          if (!compact)
            Container(
              margin: const EdgeInsets.only(top: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: p.ice, borderRadius: BorderRadius.circular(12)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                for (final i in o.items) ...[
                  Row(children: [
                    Gal(i.type, h: 44),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text('${s.nameOf(i.type)} × ${i.qty}',
                          style: tx(context, 14, w: FontWeight.w700)),
                    ),
                  ]),
                  if (i != o.items.last) const SizedBox(height: 6),
                ],
              ]),
            ),
        ]),
      ),
    );
  }
}

/// `.dcard` variant used by history (hcard).
Widget historyCard(BuildContext context, AppState s, Order o) {
  final p = Pal.of(context);
  final c = s.custOf(o);
  final st = s.rstate(o);
  final done = s.doneAt(o);
  return GestureDetector(
    onTap: () {
      s.detailId = o.id;
      s.goScreen('rdetail');
    },
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: p.line),
        boxShadow: p.shadow,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(o.id, style: oidStyle(context)),
              Text(c.name, style: para(context)),
              Text('${dfmt(done)} · ${tfmt(done)}', style: tx(context, 13, color: p.muted)),
            ]),
          ),
          OrdBadge(st, label: RLBL[st]),
        ]),
        const SizedBox(height: 8),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Expanded(
            child: Text(itemsText(o),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: tx(context, 13, color: p.muted)),
          ),
          if (st == 4)
            Text('+${peso(s.feeOf(o))}',
                style: numStyle(context, size: 15, w: FontWeight.w800, color: p.ok)),
        ]),
      ]),
    ),
  );
}

/* ================= 1. auth (rider) ================= */

ScreenView authRiderView(BuildContext context, AppState s) {
  final p = Pal.of(context);
  final hero = Container(
    decoration: const BoxDecoration(gradient: Pal.auth),
    padding: EdgeInsets.fromLTRB(
        16, 26 + MediaQuery.of(context).padding.top, 16, 70),
    child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const AquaLogo(lg: true, color: Colors.white),
          const SizedBox(height: 12),
          Text('Deliver fresh water, one stop at a time.',
              style: tx(context, 25, disp: true, w: FontWeight.w700,
                  color: Colors.white, h: 1.15)),
          const SizedBox(height: 6),
          Text('Manage your assigned deliveries.',
              maxLines: 3,
              style: para(context, color: Colors.white.withValues(alpha: .92))),
        ]),
      ),
      const SizedBox(width: 12),
      SizedBox(
        width: 150,
        child: Align(
          alignment: Alignment.bottomCenter,
          child: SvgPicture.string(scooterSvg(), fit: BoxFit.contain),
        ),
      ),
    ]),
  );

  Widget authCard() {
    return Transform.translate(
      offset: const Offset(0, -30),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: p.card,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: p.line),
          boxShadow: p.shadow,
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SegBar(
            items: const [
              SegItem('customer', 'Customer', icon: 'user'),
              SegItem('rider', 'Rider', icon: 'truck'),
              SegItem('admin', 'Admin', icon: 'store'),
            ],
            value: s.authRole,
            onSelect: (v) {
              s.authRole = v;
              s.authTab = 'login';
              s.goScreen('auth', fresh: true);
            },
          ),
          const SizedBox(height: 14),
          _RiderLoginForm(s: s),
        ]),
      ),
    );
  }

  return view(
    Column(children: [
      Stack(children: [
        hero,
        Positioned(left: 0, right: 0, bottom: 0, child: Wave(w2: p.bg)),
      ]),
      Expanded(
        child: ColoredBox(
          color: p.bg,
          child: SingleChildScrollView(
            // No clip so the card can overlap the hero wave above (same as
            // the customer auth screen's overlap scroll).
            clipBehavior: Clip.none,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
            child: authCard(),
          ),
        ),
      ),
    ]),
    bare: true,
  );
}

class _RiderLoginForm extends StatefulWidget {
  final AppState s;
  const _RiderLoginForm({required this.s});
  @override
  State<_RiderLoginForm> createState() => _RiderLoginFormState();
}

class _RiderLoginFormState extends State<_RiderLoginForm> {
  final TextEditingController _email = TextEditingController();
  final TextEditingController _pw = TextEditingController();
  bool _obscure = true;
  bool _busy = false;
  String _err = '';

  @override
  void dispose() {
    _email.dispose();
    _pw.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    return VGap([
      AquaField('Email', _email, kbType: TextInputType.emailAddress),
      AquaField('Password', _pw,
          obscure: _obscure,
          eyeToggle: true,
          onEye: () => setState(() => _obscure = !_obscure)),
      ErrLine(_err),
      Btn(_busy ? 'Logging in…' : 'Log In', onPressed: _busy ? null : () async {
        setState(() { _busy = true; _err = ''; });
        final err = await s.loginRider(_email.text, _pw.text);
        if (mounted && err != null) setState(() { _err = err; _busy = false; });
      }),
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Pal.of(context).ice,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
            'Rider accounts are created by the station admin in the Admin app.',
            style: tx(context, 13, color: Pal.of(context).muted, h: 1.4)),
      ),
    ], gap: 12);
  }
}

/* ================= 2. rider dashboard ================= */

ScreenView rdashView(BuildContext context, AppState s) {
  final p = Pal.of(context);
  if (s.rider == null) {
    return view(PadScroll(children: [
      EmptyView('Not signed in', msg: 'Log in to see your deliveries.'),
    ]));
  }
  final R = s.rider!;
  final avail = R.available;
  final all = s.rorders();
  final pend = all.where((o) => s.rstate(o) == 0).toList();
  final prog = all.where((o) => s.rstate(o) == 1).toList();
  final done = all.where((o) => s.rstate(o) == 4).toList();
  final canc = all.where((o) => s.rstate(o) == 5).toList();

  final nowMs = DateTime.now().millisecondsSinceEpoch;
  final today = all
      .where((o) {
        final st = s.rstate(o);
        return st < 2 || (st == 4 && sameDay(s.doneAt(o), nowMs));
      })
      .toList()
    ..sort((a, b) {
      final x = (s.rstate(b) == 1 ? 1 : 0) - (s.rstate(a) == 1 ? 1 : 0);
      if (x != 0) return x;
      final y = (s.rstate(a) == 4 ? 1 : 0) - (s.rstate(b) == 4 ? 1 : 0);
      if (y != 0) return y;
      return a.createdAt - b.createdAt;
    });
  final todayShown = today.take(4).toList();

  Color dotColor(String v) => v == 'available'
      ? const Color(0xFF7CF0B8)
      : (v == 'break' ? const Color(0xFFFFD36B) : const Color(0xFFC3CCDD));

  Widget tile(String v, int n, String label, String icon, Color bg, Color fg) {
    return GestureDetector(
      onTap: () {
        if (v == 'cancelled') {
          s.rfilter = 'cancelled';
          s.goScreen('rhistory');
        } else {
          s.rtab = v;
          s.goScreen('rlist');
        }
      },
      child: Container(
        constraints: const BoxConstraints(minHeight: 88),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(18),
          boxShadow: p.shadow,
        ),
        child: Row(children: [
          Ic(icon, size: 34, color: fg),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('$n', style: numStyle(context, size: 28, w: FontWeight.w700, disp: true)),
              Text(label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: tx(context, 13.5, w: FontWeight.w700, h: 1.2)),
            ]),
          ),
        ]),
      ),
    );
  }

  final hero = Container(
    decoration: const BoxDecoration(gradient: Pal.hero),
    padding: const EdgeInsets.fromLTRB(16, 6, 16, 58),
    child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Good Day, ${s.firstName()}!',
              style: tx(context, 27, disp: true, w: FontWeight.w700,
                  color: Colors.white, h: 1.15)),
          const SizedBox(height: 6),
          Text('Driver / Rider',
              style: para(context, color: Colors.white.withValues(alpha: .92))),
          const SizedBox(height: 10),
          GestureDetector(
            onTap: () => s.goScreen('profile'),
            child: Container(
              height: 36,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .18),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Container(
                    width: 9,
                    height: 9,
                    decoration:
                        BoxDecoration(color: dotColor(avail), shape: BoxShape.circle)),
                const SizedBox(width: 8),
                Text(AV[avail] ?? '',
                    style: tx(context, 13, w: FontWeight.w800, color: Colors.white)),
              ]),
            ),
          ),
        ]),
      ),
      const SizedBox(width: 12),
      SizedBox(
        width: 150,
        child: Align(
          alignment: Alignment.bottomCenter,
          child: SvgPicture.string(scooterSvg(), fit: BoxFit.contain),
        ),
      ),
    ]),
  );

  Widget body() {
    return PadScroll(children: [
      if (avail != 'available')
        card(
          background: p.ice,
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                '${avail == 'break' ? 'You are on a break.' : 'You are offline.'} New deliveries will not be assigned to you.',
                style: tx(context, 13, color: p.muted, h: 1.4),
              ),
              Btn('Change availability',
                  small: true, kind: BtnKind.ghost, onPressed: () => s.goScreen('profile')),
            ],
          ),
        ),
      Column(children: [
        Row(children: [
          Expanded(
              child: tile('assigned', pend.length, 'Assigned\nDeliveries', 'box', p.ice, p.blue)),
          const SizedBox(width: 12),
          Expanded(
              child: tile('progress', prog.length, 'In Progress', 'truck', p.peachBg, p.peachFg)),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: tile('done', done.length, 'Completed', 'check', p.mintBg, p.mintFg)),
          const SizedBox(width: 12),
          Expanded(
              child: tile('cancelled', canc.length, 'Cancelled', 'close', p.s5bg, p.s5fg)),
        ]),
      ]),
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Expanded(
            child: Text('Today’s Deliveries',
                style: tx(context, 18, disp: true, w: FontWeight.w700))),
        Btn('View All', small: true, kind: BtnKind.ghost, onPressed: () => s.goScreen('rlist')),
      ]),
      if (todayShown.isNotEmpty)
        Column(children: [
          for (final o in todayShown) ...[
            RCard(s: s, o: o, compact: true),
            if (o != todayShown.last) const SizedBox(height: 14),
          ],
        ])
      else
        card(
          padding: const EdgeInsets.all(22),
          child: Text('No deliveries assigned right now. New orders will show up here.',
              style: para(context, color: p.muted)),
        ),
    ]);
  }

  return view(
    Column(children: [
      Stack(children: [
        hero,
        Positioned(left: 0, right: 0, bottom: 0, child: Wave(w2: p.bg)),
      ]),
      Expanded(child: ColoredBox(color: p.bg, child: body())),
    ]),
    dock: Btn('View Map Route', icon: 'map', onPressed: () {
      s.routeId = null;
      s.goScreen('rroute');
    }),
  );
}

/* ================= 3. rider delivery list ================= */

ScreenView rlistView(BuildContext context, AppState s) {
  final all = s.rorders();
  final g = <String, List<Order>>{
    'assigned': all.where((o) => s.rstate(o) == 0).toList(),
    'progress': all.where((o) => s.rstate(o) == 1).toList(),
    'done': all.where((o) => s.rstate(o) == 4).toList()
      ..sort((a, b) => s.doneAt(b).compareTo(s.doneAt(a))),
  };
  final t = s.rtab;
  final list = g[t] ?? <Order>[];
  final msg = switch (t) {
    'progress' => 'Start a delivery to see it here.',
    'done' => 'Finished deliveries will appear here.',
    _ => 'New assignments will appear here.',
  };
  return view(
    PadScroll(children: [
      SegBar(
        small: true,
        items: [
          SegItem('assigned', 'Assigned (${g['assigned']!.length})'),
          SegItem('progress', 'In Progress (${g['progress']!.length})'),
          SegItem('done', 'Completed (${g['done']!.length})'),
        ],
        value: t,
        onSelect: (v) {
          s.rtab = v;
          s.goScreen('rlist');
        },
      ),
      if (list.isNotEmpty)
        Column(children: [
          for (final o in list) ...[
            RCard(s: s, o: o),
            if (o != list.last) const SizedBox(height: 14),
          ],
        ])
      else
        EmptyView('Nothing here yet', msg: msg),
    ]),
  );
}

/* ================= 4. delivery detail ================= */

Widget _iconBtn(BuildContext context, String icon, VoidCallback onTap) {
  return GestureDetector(
    onTap: onTap,
    child: Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        child: Ic(icon, size: 20, color: Pal.of(context).link)),
  );
}

Widget _etaRow(BuildContext context, {required String icon, required String text}) {
  final p = Pal.of(context);
  return Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(color: p.ice, borderRadius: BorderRadius.circular(14)),
    child: RowW([
      Ic(icon, size: 20, color: p.blue),
      Expanded(child: Text(text, style: tx(context, 15, w: FontWeight.w700))),
    ], gap: 10),
  );
}

ScreenView rdetailView(BuildContext context, AppState s) {
  final p = Pal.of(context);
  final o = firstBy(s.orders, (Order x) => x.id == s.detailId);
  if (o == null) {
    return view(
      PadScroll(children: [
        EmptyView(
          'Delivery not found',
          msg: '',
          action: SizedBox(
            width: 240,
            child: Btn('My Deliveries', onPressed: () => s.goScreen('rlist')),
          ),
        ),
      ]),
    );
  }
  final c = s.custOf(o);
  final st = s.rstate(o);
  final ph = c.phone.replaceAll(RegExp(r'[^\d+]'), '');
  final doneT = s.doneAt(o);

  final inlineActions = <Widget>[
    if (st < 4)
      Btn('View on Map', icon: 'map', kind: BtnKind.alt, onPressed: () {
        s.routeId = o.id;
        s.goScreen('rroute');
      }),
    if (st < 2)
      Btn('Report Issue',
          icon: 'close', kind: BtnKind.outd, onPressed: () => _issueSheet(context, s, o)),
  ];
  // Primary delivery action pinned in the dock so it stays in a fixed
  // position and is reachable without scrolling (same pattern as adetail).
  final Widget? dock = (st == 0 || st == 1)
      ? (st == 0
          ? Btn('Start Delivery',
              icon: 'check', kind: BtnKind.green, onPressed: () => s.riderStart(o.id))
          : Btn('Mark as Delivered',
              icon: 'check', kind: BtnKind.green, onPressed: () => _deliverAskSheet(context, s, o)))
      : null;

  return view(
    PadScroll(children: [
      card(
        background: p.ice,
        child: RowW([
          if (o.items.isNotEmpty) Gal(o.items[0].type, h: 70),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(o.id, style: oidStyle(context, size: 17)),
              const SizedBox(height: 2),
              Text('Placed: ${placed(o.createdAt)}', style: tx(context, 13, color: p.muted)),
              const SizedBox(height: 8),
              OrdBadge(st, label: RLBL[st]),
            ]),
          ),
        ], gap: 10, cross: CrossAxisAlignment.start),
      ),
      if (st == 4) _etaRow(context, icon: 'check', text: 'Delivered at ${tfmt(doneT)}'),
      if (st == 5) _etaRow(context, icon: 'close', text: 'This delivery was cancelled.'),
      if (o.issue != null)
        card(
          background: p.s0bg,
          borderColor: p.s0fg,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            RowW([
              Ic('alert', size: 22),
              Expanded(
                  child: Text('Issue reported', style: tx(context, 15, w: FontWeight.w700))),
            ], gap: 10),
            const SizedBox(height: 6),
            Text(
              '${o.issue!.type}${o.issue!.text.isNotEmpty ? ': ${o.issue!.text}' : ''}',
              style: tx(context, 13, h: 1.4),
            ),
            const SizedBox(height: 4),
            Text('${dfmt(o.issue!.ts)} · ${tfmt(o.issue!.ts)}',
                style: tx(context, 13, color: p.muted)),
          ]),
        ),
      card(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Customer Information', style: tx(context, 18, disp: true, w: FontWeight.w700)),
          const SizedBox(height: 6),
          KvList(rows: [
            RowW([
              Ic('user', size: 20, color: p.blue),
              Expanded(child: Text(c.name, style: tx(context, 15, w: FontWeight.w700))),
            ], gap: 12),
            RowW([
              Ic('phone', size: 20, color: p.blue),
              Expanded(
                  child: Text(c.phone.isEmpty ? 'No number' : c.phone,
                      style: numStyle(context))),
              if (c.phone.isNotEmpty) ...[
                _iconBtn(context, 'phone', () {
                  launchUrl(Uri.parse('tel:$ph'));
                }),
                _iconBtn(context, 'copy', () {
                  Clipboard.setData(ClipboardData(text: c.phone));
                  s.toast('Copied');
                }),
              ],
            ], gap: 12),
            RowW([
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Ic('pin', size: 20, color: p.blue),
              ),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(o.address.label, style: tx(context, 15, w: FontWeight.w700)),
                  Text(o.address.line, style: para(context)),
                ]),
              ),
              _iconBtn(context, 'copy', () {
                Clipboard.setData(ClipboardData(text: o.address.line));
                s.toast('Copied');
              }),
            ], gap: 12, cross: CrossAxisAlignment.start),
            RowW([
              Ic('clock', size: 20, color: p.blue),
              Expanded(child: Text(timeLabel(o.time))),
            ], gap: 12),
            if (o.note.isNotEmpty)
              RowW([
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Ic('pencil', size: 20, color: p.blue),
                ),
                Expanded(child: Text(o.note)),
              ], gap: 12, cross: CrossAxisAlignment.start),
          ]),
        ]),
      ),
      card(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Order Items', style: tx(context, 18, disp: true, w: FontWeight.w700)),
          const SizedBox(height: 10),
          for (final i in o.items) ...[
            RowW([
              Gal(i.type, h: 70),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${s.nameOf(i.type)} × ${i.qty}',
                      style: tx(context, 16, disp: true, w: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Tag(
                    i.type == 'buy'
                        ? 'New filled gallon with container'
                        : 'Customer provides empty gallon',
                    buy: i.type == 'buy',
                  ),
                ]),
              ),
            ], gap: 12, cross: CrossAxisAlignment.start),
            if (i != o.items.last) const SizedBox(height: 10),
          ],
          const SizedBox(height: 4),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('Total gallons', style: tx(context, 15, color: p.muted)),
            Text('${gallonsOf(o)}', style: numStyle(context, w: FontWeight.w700)),
          ]),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: p.ice, borderRadius: BorderRadius.circular(14)),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text(st == 4 ? 'Collected' : 'To collect',
                  style: tx(context, 20, disp: true, w: FontWeight.w700)),
              Text(peso(o.total),
                  style: numStyle(context, size: 20, w: FontWeight.w700, disp: true)),
            ]),
          ),
          const SizedBox(height: 8),
          Text(o.pay == 'gcash' ? 'GCash on Delivery' : 'Cash on Delivery',
              style: tx(context, 13, color: p.muted)),
        ]),
      ),
      if (inlineActions.isNotEmpty) VGap(inlineActions, gap: 10),
    ]),
    dock: dock,
  );
}

void _deliverAskSheet(BuildContext context, AppState s, Order o) {
  final p = Pal.of(context);
  final name = s.custOf(o).name;
  showAquaSheet(
    context,
    title: 'Mark as delivered?',
    body: VGap([
      Text.rich(
        TextSpan(style: para(context, color: p.muted), children: [
          const TextSpan(text: 'Confirm you handed the gallons to '),
          TextSpan(text: name, style: tx(context, 15, w: FontWeight.w700, color: p.muted)),
          const TextSpan(text: ' and collected '),
          TextSpan(
              text: peso(o.total),
              style: tx(context, 15, w: FontWeight.w700, color: p.muted,
                  fontFeatures: numFeatures)),
          TextSpan(text: ' (${o.pay == 'gcash' ? 'GCash' : 'cash'}).'),
        ]),
      ),
      const SizedBox(height: 2),
      Btn('Yes, Delivered', onPressed: () {
        Navigator.of(context).pop();
        s.riderDeliver(o.id);
      }),
      Btn('Not yet', kind: BtnKind.alt, onPressed: () => Navigator.of(context).pop()),
    ], gap: 10, crossStart: false),
  );
}

/* ---------- issue report sheet ---------- */

class _IssueSheet extends StatefulWidget {
  final AppState s;
  final Order o;
  const _IssueSheet({required this.s, required this.o});
  @override
  State<_IssueSheet> createState() => _IssueSheetState();
}

class _IssueSheetState extends State<_IssueSheet> {
  final TextEditingController _text = TextEditingController();
  bool _cancel = false;
  String _type = ISSUES.first;
  String _err = '';

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final s = widget.s;
    final o = widget.o;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('What happened?',
          style: tx(context, 13, w: FontWeight.w700, color: p.muted, ls: 0.2)),
      const SizedBox(height: 6),
      Chips(
        options: ISSUES,
        value: _type,
        wide: true,
        onSelect: (v) => setState(() => _type = v),
      ),
      const SizedBox(height: 12),
      AquaField('Details', _text,
          maxLines: 3, minHeight: 96, hint: 'Add anything the station should know'),
      const SizedBox(height: 12),
      GestureDetector(
        onTap: () => setState(() => _cancel = !_cancel),
        child: Row(children: [
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: _cancel ? p.blue : p.card,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: _cancel ? p.blue : p.line, width: 2),
            ),
            alignment: Alignment.center,
            child: _cancel ? Ic('check', size: 15, color: Colors.white) : null,
          ),
          const SizedBox(width: 10),
          Expanded(
              child: Text('Cancel this delivery', style: tx(context, 15, w: FontWeight.w600))),
        ]),
      ),
      const SizedBox(height: 12),
      ErrLine(_err),
      Btn('Submit Report', kind: BtnKind.danger, onPressed: () {
        final text = _text.text.trim();
        if (_type == 'Other' && text.isEmpty) {
          setState(() => _err = 'Describe the issue so the station can follow up.');
          return;
        }
        s.riderReport(orderId: o.id, type: _type, text: text, cancel: _cancel);
        Navigator.of(context).pop();
        s.toast(_cancel ? 'Delivery cancelled' : 'Issue reported');
      }),
    ]);
  }
}

void _issueSheet(BuildContext context, AppState s, Order o) {
  showAquaSheet(
    context,
    title: 'Report an issue',
    body: _IssueSheet(s: s, o: o),
  );
}

/* ================= 5. map route ================= */

/// Rider's own GPS dot + real OSM map of the delivery stops. Falls back to a
/// station-only view when permission is denied or GPS is unavailable.
class _RouteMapCard extends StatefulWidget {
  final AppState s;
  final List<RouteStop> stops;
  const _RouteMapCard(this.s, {required this.stops});
  @override
  State<_RouteMapCard> createState() => _RouteMapCardState();
}

class _RouteMapCardState extends State<_RouteMapCard> {
  StreamSubscription<Position>? _gps;
  LatLng? _me;
  bool _gpsOff = false;

  @override
  void initState() {
    super.initState();
    _startGps();
    // Safety net for demo flows that enter the rider session without going
    // through loginRider — start() no-ops unless Firebase is active.
    if (!RiderLocationBroadcaster.instance.running && widget.s.riderId.isNotEmpty) {
      RiderLocationBroadcaster.instance.start(riderId: widget.s.riderId);
    }
  }

  Future<void> _startGps() async {
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        setState(() => _gpsOff = true);
        return;
      }
      final fix = await Geolocator.getCurrentPosition();
      if (mounted) setState(() => _me = LatLng(fix.latitude, fix.longitude));
      _gps = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
          distanceFilter: 15,
        ),
      ).listen((p) {
        if (mounted) setState(() => _me = LatLng(p.latitude, p.longitude));
      });
    } catch (_) {
      if (mounted) setState(() => _gpsOff = true);
    }
  }

  @override
  void dispose() {
    _gps?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    return Column(children: [
      RouteStopMap(
        station: LatLng(s.station.lat!, s.station.lng!),
        stops: widget.stops,
        me: _me,
      ),
      if (_gpsOff)
        Padding(
          padding: const EdgeInsets.only(top: 8, left: 4, right: 4),
          child: Text(
            'Your GPS is off — the map shows the station and stop pins only.',
            style: tx(context, 12.5, color: Pal.of(context).muted, h: 1.35),
          ),
        ),
    ]);
  }
}

ScreenView rrouteView(BuildContext context, AppState s) {
  final p = Pal.of(context);
  var stops = s.rorders().where((o) => s.rstate(o) < 2).toList()
    ..sort((a, b) {
      final x = (s.rstate(b) == 1 ? 1 : 0) - (s.rstate(a) == 1 ? 1 : 0);
      if (x != 0) return x;
      return a.createdAt - b.createdAt;
    });
  Order? fo = s.routeId == null ? null : firstBy(s.orders, (Order x) => x.id == s.routeId);
  if (fo != null && s.rstate(fo) < 2) {
    stops = [fo, ...stops.where((o) => o.id != fo!.id)];
  } else {
    fo = null;
  }

  if (stops.isEmpty) {
    return view(
      PadScroll(children: [
        EmptyView('No stops to show', msg: 'Assigned deliveries will appear on your route.'),
      ]),
    );
  }

  // Numbered pins for orders that carry a map pin (same numbering as the
  // stop cards below). Orders without a pin keep their text address only.
  final pins = <RouteStop>[
    for (var i = 0; i < stops.length; i++)
      if (stops[i].address.hasPin)
        RouteStop(
          LatLng(stops[i].address.lat!, stops[i].address.lng!),
          i + 1,
          focused: fo != null && stops[i].id == fo.id,
        ),
  ];

  final map = Container(
    decoration: BoxDecoration(
      color: p.ice,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: p.line),
    ),
    clipBehavior: Clip.antiAlias,
    child: _RouteMapCard(s, stops: pins),
  );

  return view(
    PadScroll(children: [
      map,
      Text(
        pins.length < stops.length
            ? 'Pins appear for customers who set a map pin; the rest are listed below with their address.'
            : 'Live route of your stops from the station. Use Directions for turn-by-turn navigation in Google Maps.',
        style: tx(context, 13, color: p.muted, h: 1.4),
      ),
      for (var i = 0; i < stops.length; i++) _routeStopCard(context, s, stops[i], i + 1),
    ]),
  );
}

Widget _routeStopCard(BuildContext context, AppState s, Order o, int n) {
  final p = Pal.of(context);
  final c = s.custOf(o);
  final st = s.rstate(o);
  return card(
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      RowW([
        Container(
          width: 30,
          height: 30,
          decoration: const BoxDecoration(
              gradient: Pal.btnBlue, shape: BoxShape.circle),
          alignment: Alignment.center,
          child: Text('$n',
              style: tx(context, 14, disp: true, w: FontWeight.w700, color: Colors.white)),
        ),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text.rich(
              TextSpan(style: para(context), children: [
                TextSpan(text: c.name, style: tx(context, 15, w: FontWeight.w700)),
                const TextSpan(text: '  '),
                TextSpan(text: o.id,
                    style: tx(context, 13, color: p.muted, fontFeatures: numFeatures)),
              ]),
              softWrap: true,
            ),
            Text(o.address.line, style: tx(context, 13.5, h: 1.35)),
          ]),
        ),
        OrdBadge(st, label: RLBL[st]),
      ], gap: 10, cross: CrossAxisAlignment.start),
      const SizedBox(height: 10),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          Btn('Directions',
              small: true,
              icon: 'send',
              iconSize: 18,
              onPressed: () =>
                  launchUrl(Uri.parse(dirUrl(o)), mode: LaunchMode.externalApplication)),
          Btn('Open in Maps',
              small: true,
              icon: 'map',
              iconSize: 18,
              kind: BtnKind.alt,
              onPressed: () =>
                  launchUrl(Uri.parse(mapsUrl(o)), mode: LaunchMode.externalApplication)),
          Btn('Details', small: true, kind: BtnKind.alt, onPressed: () {
            s.detailId = o.id;
            s.goScreen('rdetail');
          }),
        ],
      ),
    ]),
  );
}

/* ================= 6. delivery history ================= */

ScreenView rhistoryView(BuildContext context, AppState s) {
  final f = s.rfilter;
  final list = s.rorders().where((o) {
    final st = s.rstate(o);
    if (st != 4 && st != 5) return false;
    return f == 'all' || (f == 'completed' && st == 4) || (f == 'cancelled' && st == 5);
  }).toList()
    ..sort((a, b) => s.doneAt(b).compareTo(s.doneAt(a)));
  return view(
    PadScroll(children: [
      FilterChips(
        items: const [
          SegItem('all', 'All'),
          SegItem('completed', 'Completed'),
          SegItem('cancelled', 'Cancelled'),
        ],
        value: f,
        onSelect: (v) {
          s.rfilter = v;
          s.goScreen('rhistory');
        },
      ),
      if (list.isNotEmpty)
        Column(children: [
          for (final o in list) ...[
            historyCard(context, s, o),
            if (o != list.last) const SizedBox(height: 14),
          ],
        ])
      else
        EmptyView('No deliveries here',
            msg: 'Completed and cancelled deliveries are listed here.'),
    ]),
  );
}

/* ================= 7. earnings ================= */

ScreenView rearnView(BuildContext context, AppState s) {
  final p = Pal.of(context);
  final done = s.rorders().where((o) => s.rstate(o) == 4).toList()
    ..sort((a, b) => s.doneAt(b).compareTo(s.doneAt(a)));
  final nowMs = DateTime.now().millisecondsSinceEpoch;
  double sumOf(List<Order> l) => l.fold<double>(0, (a, o) => a + s.feeOf(o));
  final today = done.where((o) => sameDay(s.doneAt(o), nowMs)).toList();
  final week = done.where((o) => nowMs - s.doneAt(o) <= 7 * DAY).toList();
  String dn(int n) => n == 1 ? '1 delivery' : '$n deliveries';

  Widget miniCard(String label, double amount, int n) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: p.card,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: p.line),
          boxShadow: p.shadow,
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: tx(context, 13, color: p.muted)),
          const SizedBox(height: 2),
          Text(peso(amount),
              style: numStyle(context, size: 22, w: FontWeight.w700, disp: true)),
          Text(dn(n), style: tx(context, 13, color: p.muted)),
        ]),
      ),
    );
  }

  return view(
    PadScroll(children: [
      card(
        background: p.ice,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Total earned', style: tx(context, 15, color: p.muted)),
          Text(peso(sumOf(done)),
              style: numStyle(context, size: 34, w: FontWeight.w700, disp: true)),
          Text('${dn(done.length)} completed', style: tx(context, 13, color: p.muted)),
        ]),
      ),
      Row(children: [
        miniCard('Today', sumOf(today), today.length),
        const SizedBox(width: 12),
        miniCard('Last 7 days', sumOf(week), week.length),
      ]),
      Text(
        'Demo rates: ${peso(RIDER_FEE_BASE)} per delivery plus ${peso(RIDER_FEE_PER_GALLON)} per gallon.',
        style: tx(context, 13, color: p.muted, h: 1.4),
      ),
      SectionHead('Earnings by delivery', icon: 'coins'),
      if (done.isNotEmpty)
        Column(children: [
          for (final o in done) ...[
            card(
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(o.id, style: oidStyle(context, size: 14.5)),
                    Text('${s.custOf(o).name} · ${dfmt(s.doneAt(o))}, ${tfmt(s.doneAt(o))}',
                        style: tx(context, 13, color: p.muted)),
                    const SizedBox(height: 2),
                    Text(
                        '${peso(RIDER_FEE_BASE)} + ${gallonsOf(o)} × ${peso(RIDER_FEE_PER_GALLON)}',
                        style: numStyle(context, size: 13, color: p.muted)),
                  ]),
                ),
                const SizedBox(width: 10),
                Text('+${peso(s.feeOf(o))}',
                    style: numStyle(context, size: 16, w: FontWeight.w800, color: p.ok)),
              ]),
            ),
            if (o != done.last) const SizedBox(height: 14),
          ],
        ])
      else
        card(
          padding: const EdgeInsets.all(22),
          child: Text('Complete a delivery to start earning.',
              style: para(context, color: p.muted)),
        ),
    ]),
  );
}

/* ================= 8. rider profile ================= */

ScreenView riderProfileView(BuildContext context, AppState s) {
  final p = Pal.of(context);
  final R = s.rider;
  if (R == null) {
    return view(PadScroll(children: [
      EmptyView('Not signed in', msg: 'Log in to see your profile.'),
    ]));
  }
  final n = s.rorders().where((o) => s.rstate(o) == 4).length;
  return view(
    PadScroll(children: [
      card(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Avatar(s.initials()),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(R.name, style: tx(context, 20, disp: true, w: FontWeight.w700)),
                Tag('Driver / Rider'),
              ]),
            ),
            GestureDetector(
              onTap: () => _editProfileSheet(context, s),
              child: Container(width: 40, height: 40, alignment: Alignment.center,
                  child: Ic('pencil', size: 20, color: p.link)),
            ),
          ]),
          const SizedBox(height: 12),
          KvList(rows: [
            RowW([
              Ic('phone', size: 20, color: p.blue),
              Expanded(
                  child: Text(R.phone.isEmpty ? 'Add mobile number' : R.phone,
                      style: numStyle(context))),
            ], gap: 12),
            RowW([
              Ic('mail', size: 20, color: p.blue),
              Expanded(child: Text(R.email)),
            ], gap: 12),
            RowW([
              Ic('truck', size: 20, color: p.blue),
              Expanded(child: Text('${R.vehicle.isEmpty ? 'Vehicle' : R.vehicle}'
                  '${R.plate.isNotEmpty ? ' · ${R.plate}' : ''}')),
            ], gap: 12),
            RowW([
              Ic('check', size: 20, color: p.blue),
              Expanded(child: Text('$n ${n == 1 ? 'delivery' : 'deliveries'} completed')),
            ], gap: 12),
          ]),
        ]),
      ),
      card(
        child: VGap([
          SectionHead('Availability'),
          SegBar(
            small: true,
            items: const [
              SegItem('available', 'Available'),
              SegItem('break', 'On Break'),
              SegItem('offline', 'Offline'),
            ],
            value: R.available,
            onSelect: (v) => s.riderAvailableTo(v),
          ),
          Text(AVTXT[R.available] ?? '', style: para(context, color: p.muted)),
        ]),
      ),
      Btn('Log Out', icon: 'logout', kind: BtnKind.alt, onPressed: () {
        showAquaSheet(
          context,
          title: 'Log out of AQUA?',
          body: VGap([
            Text('Your saved addresses and orders stay on this device. Log back in any time.',
                style: para(context, color: p.muted)),
            const SizedBox(height: 2),
            Btn('Log Out', onPressed: () {
              Navigator.of(context).pop();
              s.logout();
            }),
            Btn('Keep it', kind: BtnKind.alt, onPressed: () => Navigator.of(context).pop()),
          ], gap: 10, crossStart: false),
        );
      }),
    ]),
  );
}

void _editProfileSheet(BuildContext context, AppState s) {
  final R = s.rider!;
  showAquaSheet(
    context,
    title: 'Edit Profile',
    body: _EditRiderProfileBody(s: s, initial: R),
  );
}

class _EditRiderProfileBody extends StatefulWidget {
  final AppState s;
  final Rider initial;
  const _EditRiderProfileBody({required this.s, required this.initial});
  @override
  State<_EditRiderProfileBody> createState() => _EditRiderProfileBodyState();
}

class _EditRiderProfileBodyState extends State<_EditRiderProfileBody> {
  late final TextEditingController _name =
      TextEditingController(text: widget.initial.name);
  late final TextEditingController _phone =
      TextEditingController(text: widget.initial.phone);
  late final TextEditingController _plate =
      TextEditingController(text: widget.initial.plate);
  late final TextEditingController _email =
      TextEditingController(text: widget.initial.email);
  late String _vehicle = widget.initial.vehicle;
  String _err = '';

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _plate.dispose();
    _email.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final s = widget.s;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      VGap([
        AquaField('Full name', _name),
        AquaField('Mobile number', _phone, kbType: TextInputType.phone),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Vehicle',
              style: tx(context, 13, w: FontWeight.w700, color: p.muted, ls: 0.2)),
          const SizedBox(height: 6),
          Chips(
            options: VEHICLES,
            value: _vehicle,
            onSelect: (v) => setState(() => _vehicle = v),
          ),
        ]),
        AquaField('Plate number (optional)', _plate),
        AquaField('Email', _email, kbType: TextInputType.emailAddress),
        ErrLine(_err),
        Btn('Save Changes', onPressed: () {
          final name = _name.text.trim();
          final email = _email.text.trim().toLowerCase();
          if (name.length < 2) {
            setState(() => _err = 'Enter your full name.');
            return;
          }
          if (!isEmail(email)) {
            setState(() => _err = 'Enter a valid email address.');
            return;
          }
          s.updateRiderProfile(
              name: name,
              phone: _phone.text,
              email: email,
              vehicle: _vehicle,
              plate: _plate.text.trim().toUpperCase());
          Navigator.of(context).pop();
        }),
      ], gap: 12),
    ]);
  }
}

/* ================= 9. rider settings ================= */

ScreenView riderSettingsView(BuildContext context, AppState s) {
  final p = Pal.of(context);
  final st = s.station;
  return view(
    PadScroll(children: [
      card(
        child: VGap([
          SectionHead('Appearance'),
          SegBar(
            items: const [
              SegItem('system', 'System'),
              SegItem('light', 'Light'),
              SegItem('dark', 'Dark'),
            ],
            value: s.settings.theme,
            onSelect: (v) {
              s.settings.theme = v;
              s.goScreen('settings');
            },
          ),
        ]),
      ),
      card(
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Order updates', style: tx(context, 15, w: FontWeight.w700)),
              Text('Get notified when your order status changes.',
                  style: tx(context, 13, color: p.muted, h: 1.35)),
            ]),
          ),
          AquaSwitch(value: s.settings.notify, onChanged: (_) => s.toggleNotify()),
        ]),
      ),
      card(
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Auto-progress demo orders', style: tx(context, 15, w: FontWeight.w700)),
              Text(
                  'When on, new orders move through every stage on their own. Turn it off to run them from the Admin and Rider apps.',
                  style: tx(context, 13, color: p.muted, h: 1.35)),
            ]),
          ),
          const SizedBox(width: 10),
          AquaSwitch(value: s.settings.autoDeliver, onChanged: (_) => s.toggleAutoDeliver()),
        ]),
      ),
      card(
        child: VGap([
          SectionHead('Earnings rates'),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('Per delivery', style: tx(context, 15)),
            Text(peso(RIDER_FEE_BASE), style: numStyle(context, w: FontWeight.w700)),
          ]),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('Per gallon', style: tx(context, 15)),
            Text(peso(RIDER_FEE_PER_GALLON), style: numStyle(context, w: FontWeight.w700)),
          ]),
          Text('Demo rates used on the Earnings page.',
              style: tx(context, 13, color: p.muted, h: 1.4)),
        ], gap: 6),
      ),
      card(
        child: VGap([
          SectionHead(st.name, icon: 'store'),
          RowW([
            Ic('clock', size: 18, color: p.blue),
            Expanded(child: Text('Open ${hh(st.open)} – ${hh(st.close)}')),
          ], gap: 10),
          RowW([
            Ic('phone', size: 18, color: p.blue),
            Expanded(child: Text(st.phone, style: numStyle(context))),
          ], gap: 10),
          RowW([
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Ic('pin', size: 18, color: p.blue),
            ),
            Expanded(child: Text(st.address)),
          ], gap: 10, cross: CrossAxisAlignment.start),
          if (!st.accepting) OrdBadge(5, label: 'Not taking orders'),
        ], gap: 8),
      ),
      Text(
        'AQUA Water Ordering & Delivery System · Rider app',
        textAlign: TextAlign.center,
        style: tx(context, 13, color: p.muted),
      ),
    ]),
  );
}
