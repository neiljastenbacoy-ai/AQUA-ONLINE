import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
    return TapSurface(
      onTap: () {
        s.detailId = o.id;
        s.goScreen('rdetail');
      },
      semanticLabel: 'Delivery ${o.id}, ${c.name}, ${RLBL[st]}',
      semanticButton: false,
      borderRadius: BorderRadius.circular(18),
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
                const SizedBox(height: 8),
                // The chip lives under the address, inside the column: beside
                // it, "In Progress" is ~194dp at 1.3x text and squeezed this
                // column to 0 on a 320dp phone.
                OrdBadge(st, label: RLBL[st]),
              ]),
            ),
            const SizedBox(width: 10),
            Ic('chev', size: 20, color: p.muted),
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
  return TapSurface(
    onTap: () {
      s.detailId = o.id;
      s.goScreen('rdetail');
    },
    semanticLabel: 'Delivery ${o.id}, ${c.name}, ${RLBL[st]}',
    semanticButton: false,
    borderRadius: BorderRadius.circular(18),
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
  return ScreenView(
    bare: true,
    content: Column(children: [
      AuthHero(
        title: 'Rider sign-in',
        sub: 'Manage your assigned deliveries.',
        art: scooterArt,
      ),
      authOverlapScroll(
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          AquaCard(child: _RiderLoginForm(s: s)),
          const SizedBox(height: 8),
          // One link, every role: rider ↔ admin used to need a detour through
          // the customer form to get back to this choice.
          Center(
            child: TxtLink('Switch account type', icon: 'users',
                onTap: () => showAuthRoleSheet(context, s)),
          ),
        ]),
      ),
    ]),
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
  final FocusNode _emailFocus = FocusNode();
  final FocusNode _pwFocus = FocusNode();
  bool _obscure = true;
  bool _busy = false;
  String _emailErr = '';
  String _pwErr = '';
  String _err = '';

  @override
  void dispose() {
    _email.dispose();
    _pw.dispose();
    _emailFocus.dispose();
    _pwFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _email.text.trim();
    if (_busy) return;
    setState(() {
      _err = '';
      _emailErr = '';
      _pwErr = '';
    });
    if (email.isEmpty) {
      setState(() => _emailErr = 'Enter your email address.');
      _emailFocus.requestFocus();
      return;
    }
    if (!isEmail(email)) {
      setState(() => _emailErr = 'That address is missing an @ or a domain.');
      _emailFocus.requestFocus();
      return;
    }
    if (_pw.text.isEmpty) {
      setState(() => _pwErr = 'Enter your password.');
      _pwFocus.requestFocus();
      return;
    }
    setState(() => _busy = true);
    final err = await widget.s.loginRider(email, _pw.text);
    if (!mounted) return;
    setState(() => _busy = false);
    if (err == null) return;
    final low = err.toLowerCase();
    setState(() {
      if (low.contains('password')) {
        _pwErr = err;
      } else if (low.contains('email') || low.contains('account')) {
        _emailErr = err;
      } else {
        _err = err;
      }
    });
    (low.contains('password') ? _pwFocus : _emailFocus).requestFocus();
  }

  /// Riders are created and reset by the station, so there is no self-serve
  /// reset to fake here.
  void _forgot() {
    showAquaSheet<void>(
      context,
      title: 'Forgot password?',
      body: VGap([
        Text(
            'Ask the station admin to set a new password for you: Users → Riders → your name → Edit.',
            style: para(context)),
        Btn('Back to sign in',
            kind: BtnKind.alt,
            onPressed: () => Navigator.of(context).pop()),
      ]),
    );
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
        onSubmitted: (_) => _pwFocus.requestFocus(),
        onChanged: (_) {
          if (_emailErr.isNotEmpty) setState(() => _emailErr = '');
        },
      ),
      AquaField(
        'Password',
        _pw,
        error: _pwErr.isEmpty ? null : _pwErr,
        obscure: _obscure,
        eyeToggle: true,
        onEye: () => setState(() => _obscure = !_obscure),
        kbAction: TextInputAction.done,
        autofillHints: const [AutofillHints.password],
        focusNode: _pwFocus,
        onSubmitted: (_) => _submit(),
        onChanged: (_) {
          if (_pwErr.isNotEmpty) setState(() => _pwErr = '');
        },
      ),
      Align(
        alignment: Alignment.centerRight,
        child: TxtLink('Forgot password?', onTap: _forgot),
      ),
      ErrLine(_err),
      Btn('Log In', busy: _busy, onPressed: _submit),
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: p.ice,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
            'Rider accounts are created by the station admin in the Admin app.',
            style: tx(context, 13, color: p.muted, h: 1.4)),
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
  final pend = all.where((o) => s.rstate(o) == 0).toList()
    ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  final prog = all.where((o) => s.rstate(o) == 1).toList()
    ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  final done = all.where((o) => s.rstate(o) == 4).toList();

  final nowMs = DateTime.now().millisecondsSinceEpoch;
  // Counters are all *today*: the old grid mixed current assignments with
  // all-time completions, so "Completed 12" contradicted the list under it.
  final doneToday = done.where((o) => sameDay(s.doneAt(o), nowMs)).toList();
  final earned = doneToday.fold<double>(0, (a, o) => a + s.feeOf(o));

  // What to do next: finish the delivery already on the road, else the oldest
  // waiting assignment. Everything else on this screen is context for it.
  final Order? next = prog.isNotEmpty ? prog.first : (pend.isEmpty ? null : pend.first);

  final today = [...pend, ...prog, ...doneToday]..sort((a, b) {
      final x = (s.rstate(b) == 1 ? 1 : 0) - (s.rstate(a) == 1 ? 1 : 0);
      if (x != 0) return x;
      final y = (s.rstate(a) == 4 ? 1 : 0) - (s.rstate(b) == 4 ? 1 : 0);
      if (y != 0) return y;
      return a.createdAt - b.createdAt;
    });
  final todayShown = today.take(4).toList();

  Widget body() {
    return PadScroll(children: [
      _nextCard(context, s, next),
      StatRow([
        StatTile(
            icon: 'box',
            value: '${pend.length}',
            label: 'Assigned',
            bg: p.ice,
            fg: p.blue,
            onTap: () {
              s.rtab = 'assigned';
              s.goScreen('rlist');
            }),
        StatTile(
            icon: 'truck',
            value: '${prog.length}',
            label: 'On the way',
            bg: p.peachBg,
            fg: p.peachFg,
            onTap: () {
              s.rtab = 'progress';
              s.goScreen('rlist');
            }),
        StatTile(
            icon: 'check',
            value: '${doneToday.length}',
            label: 'Delivered',
            bg: p.mintBg,
            fg: p.mintFg,
            onTap: () {
              s.rtab = 'done';
              s.goScreen('rlist');
            }),
        StatTile(
            icon: 'coins',
            value: peso(earned),
            label: 'Earned today',
            bg: p.s3bg,
            fg: p.s3fg,
            onTap: () => s.goScreen('rearn')),
      ]),
      SectionRow('Today’s Deliveries',
          action: 'View all', onTap: () => s.goScreen('rlist')),
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
      DashHero(
        title: 'Good Day, ${s.firstName()}!',
        sub: 'Driver / Rider',
        // Availability is the rider's most-used control and used to live two
        // screens away in Profile; it belongs in the header.
        trailing: SegBar(
          small: true,
          items: const [
            SegItem('available', 'Available'),
            SegItem('break', 'Break'),
            SegItem('offline', 'Offline'),
          ],
          value: avail,
          onSelect: s.riderAvailableTo,
        ),
      ),
      Expanded(child: ColoredBox(color: p.bg, child: body())),
    ]),
    // The dock carries the map only. Starting and completing happen on the
    // delivery screen, where the rider sees the address and the customer's
    // number before acting — the dashboard is for seeing the day, not for
    // pressing Start on whichever order happened to sort first.
    dock: Btn('View Map Route', icon: 'map', onPressed: () {
      // routeId cleared: the map shows every assigned stop, not one of them.
      s.routeId = null;
      s.goScreen('rroute');
    }),
  );
}

/// The delivery that matters right now — in progress first, else the oldest
/// assignment — with everything the rider needs before tapping it.
Widget _nextCard(BuildContext context, AppState s, Order? o) {
  final p = Pal.of(context);
  if (o == null) {
    return AquaCard(
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 16),
      child: RowW([
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Ic('check', size: 22, color: p.ok),
        ),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('No deliveries assigned',
                style: tx(context, 15, disp: true, w: FontWeight.w700)),
            Text('New orders land here as soon as the station assigns them.',
                style: para(context, color: p.muted, size: 13)),
          ]),
        ),
      ], gap: 10, cross: CrossAxisAlignment.start),
    );
  }
  final c = s.custOf(o);
  final st = s.rstate(o);
  return TapSurface(
    onTap: () {
      s.detailId = o.id;
      s.goScreen('rdetail');
    },
    semanticLabel: 'Next delivery ${o.id}, ${c.name}, ${RLBL[st]}',
    borderRadius: BorderRadius.circular(18),
    child: Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: p.line),
        boxShadow: p.shadow,
      ),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('NEXT DELIVERY',
                style: tx(context, 11, w: FontWeight.w800, color: p.link, ls: .8)),
            const SizedBox(height: 6),
            Text(c.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: tx(context, 16.5, disp: true, w: FontWeight.w800)),
            const SizedBox(height: 2),
            Text('${itemsText(o)} · fee ${peso(s.feeOf(o))}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: tx(context, 13, w: FontWeight.w700, color: p.muted)),
            const SizedBox(height: 4),
            RowW([
              Ic('pin', size: 14, color: p.blue),
              Expanded(
                child: Text(o.address.line,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tx(context, 12.5, color: p.muted)),
              ),
            ], gap: 5, cross: CrossAxisAlignment.start),
            const SizedBox(height: 8),
            // Inside the column the chip truncates instead of overflowing.
            OrdBadge(st, label: RLBL[st]),
          ]),
        ),
        IconAction('map', iconSize: 22, label: 'Open map route', onTap: () {
          s.routeId = o.id;
          s.goScreen('rroute');
        }),
      ]),
    ),
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
  // The next stage, pinned in the dock so the common path is one tap without
  // scrolling — the same pattern as the admin's order screen, and the same
  // four names for the four stages.
  final Widget? dock = (!o.cancelled && o.status < 4)
      ? Btn(_nextAction[o.status],
          icon: 'check',
          kind: o.status == 3 ? BtnKind.green : BtnKind.primary,
          onPressed: () => _advance(context, s, o, o.status + 1))
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
              // The real stage, not the list's grouping: a rider looking at one
              // delivery wants to know whether it is prepared or on the road,
              // not that it is "in progress".
              OrdBadge(o.cancelled ? 5 : o.status,
                  label: o.cancelled ? 'Cancelled' : BADGE[o.status]),
            ]),
          ),
        ], gap: 10, cross: CrossAxisAlignment.start),
      ),
      if (st == 4) _etaRow(context, icon: 'check', text: 'Delivered at ${tfmt(doneT)}'),
      if (st == 5) _etaRow(context, icon: 'close', text: 'This delivery was cancelled.'),
      if (!o.cancelled && o.status == 3) _arrivalCard(context, s, o, ph),
      if (st < 4) _statusTrail(context, s, o),
      if (o.issue != null)
        card(
          background: p.s0bg,
          borderColor: p.s0fg,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            RowW([
              Ic('alert', size: 22, color: p.ink),
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
          const SectionHead('Customer Information'),
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
                IconAction('phone', label: 'Call ${c.phone}', onTap: () {
                  launchUrl(Uri.parse('tel:$ph'));
                }),
                IconAction('copy', label: 'Copy phone number', onTap: () {
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
              IconAction('copy', label: 'Copy delivery address', onTap: () {
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
          const SectionHead('Order Items'),
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
            Flexible(child: Text('Total gallons', style: tx(context, 15, color: p.muted))),
            Text('${gallonsOf(o)}', style: numStyle(context, w: FontWeight.w700)),
          ]),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: p.ice, borderRadius: BorderRadius.circular(14)),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              // Two 20dp labels side by side overflowed here once the amount
              // grew; the money shrinks rather than clipping the card.
              Flexible(
                  child: Text(st == 4 ? 'Collected' : 'To collect',
                      style: tx(context, 20, disp: true, w: FontWeight.w700))),
              const SizedBox(width: 12),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text(peso(o.total),
                      style: numStyle(context, size: 20, w: FontWeight.w700, disp: true)),
                ),
              ),
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

/* ---------- arrival ---------- */

/// At the door. Sits right under the header while the order is on the road,
/// so the rider never scrolls for it: one tap rings the customer's phone. GPS
/// presses it on its own at the customer's pin; the button covers a missing or
/// misplaced pin and a phone with location off. Once sent it turns into a
/// receipt, one "Notify Again" for a customer who has not come out, and then
/// the call button.
Widget _arrivalCard(BuildContext context, AppState s, Order o, String ph) {
  final p = Pal.of(context);
  final first = s.custOf(o).name.split(' ').first;
  if (o.arrivedAt == null) {
    return card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        RowW([
          Ic('bell', size: 22, color: p.blue),
          Expanded(
            child: Text('At $first\'s place? Let them know you\'re outside.',
                style: tx(context, 14, h: 1.35)),
          ),
        ], gap: 10),
        const SizedBox(height: 10),
        Btn('Notify Customer: I\'ve Arrived',
            icon: 'bell', onPressed: () => s.riderArrived(o.id)),
      ]),
    );
  }
  final again = !s.nudged.contains(o.id);
  return card(
    background: p.s4bg,
    borderColor: p.s4fg,
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      RowW([
        Ic('check', size: 22, color: p.s4fg),
        Expanded(
          child: Text(
              again
                  ? 'Customer notified you arrived at ${tfmt(o.arrivedAt!)}'
                  : 'Customer notified twice. Call them if they still haven\'t come out.',
              style: tx(context, 14, w: FontWeight.w700, h: 1.35)),
        ),
      ], gap: 10),
      if (again) ...[
        const SizedBox(height: 10),
        Btn('Notify Again', icon: 'bell', kind: BtnKind.alt,
            onPressed: () => s.riderNudge(o.id)),
      ] else if (ph.isNotEmpty) ...[
        const SizedBox(height: 10),
        Btn('Call Customer', icon: 'phone', kind: BtnKind.alt,
            onPressed: () => launchUrl(Uri.parse('tel:$ph'))),
      ],
    ]),
  );
}

/* ---------- delivery status control ---------- */

/// The four order stages in the admin's words. Index = target status − 1, so
/// a rider reads the same "Send Out for Delivery" that dispatch pressed.
const List<String> _nextAction = [
  'Confirm Order',
  'Start Preparing',
  'Send Out for Delivery',
  'Mark as Delivered',
];

/// Runs one stage from the status card or the dock. Delivered is the only
/// stage that asks first, because it also closes the cash.
void _advance(BuildContext context, AppState s, Order o, int n) {
  if (n == 4) {
    _deliverAskSheet(context, s, o);
  } else if (n == 3) {
    s.riderStart(o.id);
  } else {
    s.riderSetStatus(o.id, n);
  }
}

/// The four customer-visible stages, with the times the order actually
/// carries. Stages 1–2 belong to the station, but the rider sees them so the
/// status they are about to change is never a surprise. The action itself
/// lives in the dock, so this card stays a read-only record.
Widget _statusTrail(BuildContext context, AppState s, Order o) {
  final p = Pal.of(context);
  final cur = o.cancelled ? 5 : o.status;
  const stages = [(1, 'Confirmed'), (2, 'Preparing'), (3, 'Out for delivery'), (4, 'Delivered')];
  int? stampOf(int i) => o.stamps.length > i ? o.stamps[i] : null;
  return card(
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SectionHead('Delivery Status', icon: 'check'),
      const SizedBox(height: 10),
      for (final (i, label) in stages)
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Column(children: [
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: cur >= i ? p.mintFg : p.ice,
                border: Border.all(color: cur >= i ? p.mintFg : p.ice2),
              ),
              child: cur >= i ? const Ic('check', size: 14, color: Colors.white) : null,
            ),
            if (i != 4)
              Container(
                  width: 2,
                  height: 20,
                  color: cur >= i ? p.mintFg.withValues(alpha: .35) : p.ice2),
          ]),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: RowW([
                Expanded(
                  child: Text(label,
                      style: tx(context, 15,
                          w: cur == i ? FontWeight.w700 : FontWeight.w600,
                          color: cur >= i ? p.ink : p.muted)),
                ),
                Text(
                  stampOf(i) == null
                      ? (cur >= i ? 'Done' : '')
                      : tfmt(stampOf(i)!),
                  style: tx(context, 13, color: p.muted),
                ),
              ]),
            ),
          ),
        ]),
    ]),
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
        // The delivery screen has no next stage once it reads Delivered, so
        // staying here left the rider on a finished page with an empty dock.
        s.back();
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
      CheckRow(
        value: _cancel,
        onChanged: (v) => setState(() => _cancel = v),
        label: 'Cancel this delivery',
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
        // A cancelled delivery drops out of every list and has no action left,
        // so hand the rider back to their deliveries instead of a dead detail.
        if (_cancel) s.back();
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
        // Says up front that the map is the whole assignment, not one stop.
        '${stops.length} ${stops.length == 1 ? 'stop' : 'stops'} on your route. '
        '${pins.length < stops.length ? 'Pins appear for customers who set a map pin; the rest are listed below with their address.' : 'Use Directions for turn-by-turn navigation in Google Maps.'}',
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
          // On the road and not yet announced: the stop card carries the same
          // one-tap arrival as the delivery screen, so the rider can send it
          // straight from the map.
          if (!o.cancelled && o.status == 3 && o.arrivedAt == null)
            Btn('I\'ve Arrived',
                small: true,
                icon: 'bell',
                iconSize: 18,
                kind: BtnKind.green,
                onPressed: () => s.riderArrived(o.id)),
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
            IconAction('pencil',
                onTap: () => _editProfileSheet(context, s), label: 'Edit profile'),
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
          title: 'Log out of AQUARUN?',
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
                  'When on, new orders are confirmed and prepared on their own. You always mark the delivery itself.',
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
            Flexible(child: Text('Per delivery', style: tx(context, 15))),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Text(peso(RIDER_FEE_BASE), style: numStyle(context, w: FontWeight.w700)),
              ),
            ),
          ]),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Flexible(child: Text('Per gallon', style: tx(context, 15))),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Text(peso(RIDER_FEE_PER_GALLON), style: numStyle(context, w: FontWeight.w700)),
              ),
            ),
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
        'AQUARUN · Rider app',
        textAlign: TextAlign.center,
        style: tx(context, 13, color: p.muted),
      ),
    ]),
  );
}
