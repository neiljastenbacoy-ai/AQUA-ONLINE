/* Customer screens — 1:1 port of the AQUA Water Ordering HTML app. */

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';

import 'art.dart';
import 'constants.dart';
import 'firebase_boot.dart';
import 'icons.dart';
import 'models.dart';
import 'palette.dart';
import 'state.dart';
import 'tracking_map.dart';
import 'widgets.dart';

/* ================= local helpers ================= */

T? _first<T>(Iterable<T> items, bool Function(T) test) {
  for (final x in items) {
    if (test(x)) return x;
  }
  return null;
}

int? _stamp(Order o, int i) => i < o.stamps.length ? o.stamps[i] : null;

double _unitPrice(Order o, AppState s, String t) =>
    o.unitPrice(t, s.priceOf('refill'), s.priceOf('buy'));

/// Scroll body used right under a gradient hero: negative overlap via translate.
Widget _overlapScroll(Widget child, {required double overlap, double bottom = 28}) =>
    authOverlapScroll(child, overlap: overlap, bottom: bottom);

/* ================= splash ================= */

ScreenView splashView(BuildContext context, AppState s) {
  return ScreenView(bare: true, content: const _SplashBody());
}

class _SplashBody extends StatefulWidget {
  const _SplashBody();
  @override
  State<_SplashBody> createState() => _SplashBodyState();
}

class _SplashBodyState extends State<_SplashBody> with TickerProviderStateMixin {
  late final AnimationController _float =
      AnimationController(vsync: this, duration: const Duration(seconds: 3))
        ..repeat();
  late final AnimationController _load =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1000))
        ..forward();

  @override
  void dispose() {
    _float.dispose();
    _load.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return Container(
      color: p.navy,
      child: Stack(children: [
        Center(
          child: AnimatedBuilder(
            animation: _float,
            builder: (context, _) {
              return Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                const AquaLogo(lg: true, color: Colors.white),
                const SizedBox(height: 14),
                Transform.translate(
                  offset: Offset(
                    0,
                    MediaQuery.disableAnimationsOf(context)
                        ? 0
                        : -8 * math.sin(math.pi * _float.value),
                  ),
                  child: const Gal('refill', h: 150),
                ),
                const SizedBox(height: 14),
                Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: Container(
                    width: 140,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .25),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: AnimatedBuilder(
                      animation: _load,
                      builder: (context, _) => Align(
                        alignment: Alignment.centerLeft,
                        child: FractionallySizedBox(
                          widthFactor: _load.value.clamp(0.0, 1.0),
                          child: Container(
                            height: 5,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ]);
            },
          ),
        ),
        Positioned(left: 0, right: 0, bottom: 0, child: Wave(height: 90, w2: p.bg)),
      ]),
    );
  }
}

/* ================= auth (customer role) ================= */

ScreenView authView(BuildContext context, AppState s) {
  final isReg = s.authTab == 'register';
  final Widget form = isReg
      ? _RegisterForm(s, key: const ValueKey('register'))
      : _LoginForm(s, key: const ValueKey('login'));
  return ScreenView(
    bare: true,
    content: Column(children: [
      AuthHero(
        title: isReg ? 'Create your account' : 'Welcome back',
        sub: isReg
            ? 'Refills and new gallons, a few taps away.'
            : 'Sign in to order and track your water.',
        art: const Gal('buy', h: 118),
      ),
      authOverlapScroll(
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          AquaCard(
            child: VGap([
              SegBar(
                items: const [
                  SegItem('login', 'Log In'),
                  SegItem('register', 'Register'),
                ],
                value: s.authTab,
                onSelect: (v) {
                  s.authTab = v;
                  s.updateUI();
                },
              ),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                // Top-aligned: the register form is much taller, and a centred
                // stack would make the card jump while the two cross-fade.
                layoutBuilder: (current, previous) => Stack(
                  alignment: Alignment.topCenter,
                  children: [...previous, ?current],
                ),
                child: form,
              ),
            ]),
          ),
          const SizedBox(height: 8),
          Center(
            child: TxtLink('Staff sign-in',
                icon: 'truck', onTap: () => showAuthRoleSheet(context, s)),
          ),
        ]),
      ),
    ]),
  );
}

/// Password resets are manual in this station setup, so the link explains the
/// only route instead of pretending to send a reset email.
void _forgotSheet(BuildContext context, String email) {
  final who = email.trim();
  showAquaSheet<void>(
    context,
    title: 'Forgot password?',
    body: VGap([
      Text(
          'Only the station can reset a password, so knowing an email address is not enough to open an account.',
          style: para(context, color: Pal.of(context).muted)),
      Text(
          who.isEmpty
              ? 'Message the AQUARUN station at 0917 800 1200 and tell them the email you signed up with.'
              : 'Message the AQUARUN station at 0917 800 1200 and ask them to reset the password for $who.',
          style: para(context)),
      Btn('Back to sign in',
          kind: BtnKind.alt, onPressed: () => Navigator.of(context).pop()),
    ]),
  );
}

class _LoginForm extends StatefulWidget {
  final AppState s;
  const _LoginForm(this.s, {super.key});
  @override
  State<_LoginForm> createState() => _LoginFormState();
}

class _LoginFormState extends State<_LoginForm> {
  final _email = TextEditingController();
  final _pw = TextEditingController();
  final _emailFocus = FocusNode();
  final _pwFocus = FocusNode();
  bool _show = false;
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
    final err = await widget.s.loginCustomer(email, _pw.text);
    if (!mounted) return;
    setState(() => _busy = false);
    if (err == null) return;
    // loginCustomer answers with one sentence; show it on the field it names.
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

  @override
  Widget build(BuildContext context) {
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
        obscure: !_show,
        eyeToggle: true,
        onEye: () => setState(() => _show = !_show),
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
        child: TxtLink('Forgot password?',
            onTap: () => _forgotSheet(context, _email.text)),
      ),
      ErrLine(_err),
      Btn('Log In', busy: _busy, onPressed: _submit),
    ]);
  }
}

class _RegisterForm extends StatefulWidget {
  final AppState s;
  const _RegisterForm(this.s, {super.key});
  @override
  State<_RegisterForm> createState() => _RegisterFormState();
}

class _RegisterFormState extends State<_RegisterForm> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _pw = TextEditingController();
  final _nameFocus = FocusNode();
  final _phoneFocus = FocusNode();
  final _emailFocus = FocusNode();
  final _pwFocus = FocusNode();
  bool _show = false;
  bool _busy = false;
  String _nameErr = '';
  String _phoneErr = '';
  String _emailErr = '';
  String _pwErr = '';
  String _err = '';

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _email.dispose();
    _pw.dispose();
    _nameFocus.dispose();
    _phoneFocus.dispose();
    _emailFocus.dispose();
    _pwFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _email.text.trim();
    if (_busy) return;
    setState(() {
      _err = '';
      _nameErr = '';
      _phoneErr = '';
      _emailErr = '';
      _pwErr = '';
    });
    // Same checks the state layer runs, done here first so each one lands on
    // its own field instead of in a single line under the form.
    if (_name.text.trim().length < 2) {
      setState(() => _nameErr = 'Enter your full name.');
      _nameFocus.requestFocus();
      return;
    }
    if (_phone.text.replaceAll(RegExp(r'\D'), '').length < 10) {
      setState(() => _phoneErr = 'Use at least 10 digits, like 0917 555 0142.');
      _phoneFocus.requestFocus();
      return;
    }
    if (!isEmail(email)) {
      setState(() => _emailErr = 'That address is missing an @ or a domain.');
      _emailFocus.requestFocus();
      return;
    }
    if (_pw.text.length < 4) {
      setState(() => _pwErr = 'Use at least 4 characters.');
      _pwFocus.requestFocus();
      return;
    }
    setState(() => _busy = true);
    final err = await widget.s
        .registerCustomer(_name.text, _phone.text, email, _pw.text);
    if (!mounted) return;
    setState(() => _busy = false);
    if (err == null) return;
    // Account-level answers (email taken, offline) stay on the form line.
    setState(() => _err = err);
  }

  @override
  Widget build(BuildContext context) {
    return VGap([
      AquaField(
        'Full name',
        _name,
        error: _nameErr.isEmpty ? null : _nameErr,
        hint: 'Maria Santos',
        kbAction: TextInputAction.next,
        autofillHints: const [AutofillHints.name],
        focusNode: _nameFocus,
        onSubmitted: (_) => _phoneFocus.requestFocus(),
        onChanged: (_) {
          if (_nameErr.isNotEmpty) setState(() => _nameErr = '');
        },
      ),
      AquaField(
        'Mobile number',
        _phone,
        error: _phoneErr.isEmpty ? null : _phoneErr,
        kbType: TextInputType.phone,
        hint: '0917 555 0142',
        kbAction: TextInputAction.next,
        autofillHints: const [AutofillHints.telephoneNumber],
        focusNode: _phoneFocus,
        onSubmitted: (_) => _emailFocus.requestFocus(),
        onChanged: (_) {
          if (_phoneErr.isNotEmpty) setState(() => _phoneErr = '');
        },
      ),
      AquaField(
        'Email',
        _email,
        error: _emailErr.isEmpty ? null : _emailErr,
        kbType: TextInputType.emailAddress,
        hint: 'you@example.com',
        kbAction: TextInputAction.next,
        autofillHints: const [AutofillHints.email],
        focusNode: _emailFocus,
        onSubmitted: (_) => _pwFocus.requestFocus(),
        onChanged: (_) {
          if (_emailErr.isNotEmpty) setState(() => _emailErr = '');
        },
      ),
      AquaField(
        'Password (at least 4 characters)',
        _pw,
        error: _pwErr.isEmpty ? null : _pwErr,
        obscure: !_show,
        eyeToggle: true,
        onEye: () => setState(() => _show = !_show),
        kbAction: TextInputAction.done,
        autofillHints: const [AutofillHints.newPassword],
        focusNode: _pwFocus,
        onSubmitted: (_) => _submit(),
        onChanged: (_) {
          if (_pwErr.isNotEmpty) setState(() => _pwErr = '');
        },
      ),
      ErrLine(_err),
      Btn('Create Account', busy: _busy, onPressed: _submit),
    ]);
  }
}

/* ================= home ================= */

ScreenView homeView(BuildContext context, AppState s) {
  final my = s.myOrders();
  final actList = my.where(isActive).toList()
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  final Order? act = actList.isEmpty ? null : actList.first;
  final past = my.where((o) => !isActive(o) && !o.cancelled).toList()
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  final Order? last = past.isEmpty ? null : past.first;

  final kids = <Widget>[];
  void add(Widget w) {
    if (kids.isNotEmpty) kids.add(const SizedBox(height: 14));
    kids.add(w);
  }

  // The page follows the questions a customer actually has: where is my water,
  // what does it cost, can I just repeat it, where else can I go. Products used
  // to sit under the promo carousel at ~650dp on a 640dp phone, prices unseen.
  if (act != null) add(_activeBanner(context, s, act));

  add(const SectionHead('Our Products'));
  add(Row(children: [
    Expanded(child: TapSurface(
      onTap: () => _openProduct(s, 'refill'),
      semanticLabel: s.nameOf('refill'),
      borderRadius: BorderRadius.circular(18),
      child: _prodCard(context, s, 'refill'),
    )),
    const SizedBox(width: 12),
    Expanded(child: TapSurface(
      onTap: () => _openProduct(s, 'buy'),
      semanticLabel: s.nameOf('buy'),
      borderRadius: BorderRadius.circular(18),
      child: _prodCard(context, s, 'buy'),
    )),
  ]));

  if (last != null) add(_orderAgain(context, s, last));

  add(Row(children: [
    Expanded(child: _miniTile(context, 'My Orders', 'clip', () => s.goScreen('orders'))),
    const SizedBox(width: 10),
    Expanded(child: _miniTile(context, 'Track Delivery', 'pin', () {
      s.trackId = null;
      s.goScreen('track');
    })),
  ]));

  add(_Slides(s));

  return ScreenView(
    content: Column(children: [
      DashHero(
        title: 'Good Day, ${s.firstName()}!',
        sub: act != null
            ? '${act.id} · ${BADGE[statusState(act)]}'
            : 'Refill or buy — we deliver to your door.',
        art: const Gal('refill', h: 96),
      ),
      _overlapScroll(
        Container(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: kids),
        ),
        overlap: 12,
      ),
    ]),
  );
}

void _openProduct(AppState s, String k) {
  s.draft.type = k;
  s.draft.qty = 1;
  s.goScreen('order');
}

/// Repeat the last finished order in one tap — `reorder` already fills the cart.
Widget _orderAgain(BuildContext context, AppState s, Order o) {
  final p = Pal.of(context);
  return TapSurface(
    onTap: () => s.reorder(o.id),
    semanticLabel: 'Order again: ${itemsText(o)}',
    borderRadius: BorderRadius.circular(16),
    child: Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: BoxDecoration(
        color: p.ice,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: p.line),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Ic('copy', size: 20, color: p.blue),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Order again',
                style: tx(context, 13.5, w: FontWeight.w800, color: p.link)),
            Text('${itemsText(o)} · ${peso(o.total)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: tx(context, 12.5, color: p.muted, h: 1.3)),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Ic('chev', size: 16, color: p.link),
        ),
      ]),
    ),
  );
}

/// Secondary destination: the product cards own the primary actions.
Widget _miniTile(BuildContext context, String label, String icon, VoidCallback onTap) {
  final p = Pal.of(context);
  return TapSurface(
    onTap: onTap,
    semanticLabel: label,
    borderRadius: BorderRadius.circular(16),
    child: Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: p.line),
        boxShadow: p.shadow,
      ),
      // Two of these share 288dp on a 320dp phone; the label wraps to its two
      // words and truncates only at very large text.
      child: Row(children: [
        Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(color: p.ice, shape: BoxShape.circle),
          alignment: Alignment.center,
          child: Ic(icon, size: 15, color: p.blue),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: tx(context, 13, disp: true, w: FontWeight.w700, h: 1.15)),
        ),
      ]),
    ),
  );
}

Widget _activeBanner(BuildContext context, AppState s, Order o) {
  final p = Pal.of(context);
    return TapSurface(
      onTap: () {
        s.trackId = o.id;
        s.goScreen('track');
      },
      semanticLabel: 'Order ${o.id}, ${BADGE[statusState(o)]}, track delivery',
      borderRadius: BorderRadius.circular(16),
      // Flutter only allows a borderRadius on a uniform-color border, so the
      // rounded corners come from a clip (same look as the CSS original).
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          boxShadow: p.shadow,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: p.card,
            border: Border(
              left: BorderSide(color: p.blue, width: 5),
              top: BorderSide(color: p.line),
              right: BorderSide(color: p.line),
              bottom: BorderSide(color: p.line),
            ),
          ),
          // No status chip on this card: at 1.3x text it took 175dp of a
          // 255dp card and crushed the progress bar to 9dp. The five-segment
          // bar carries the stage; the hero subtitle keeps the readable label.
          child: RowW([
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(o.id, style: tx(context, 15, disp: true, w: FontWeight.w700, ls: .4)),
              const SizedBox(height: 2),
              Text(itemsText(o),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tx(context, 13, color: p.muted)),
              const SizedBox(height: 8),
              _statusBar(context, statusState(o)),
            ])),
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Ic('chev', size: 18, color: p.muted),
            ),
          ], gap: 10, cross: CrossAxisAlignment.start),
          ),
        ),
      ),
    );
}

/// Five-segment progress under the live order: one filled bar per reached
/// [STAGE], so "how far along" is readable at a glance instead of only as a
/// badge label.
Widget _statusBar(BuildContext context, int st) {
  final p = Pal.of(context);
  const n = 5;
  return Row(children: [
    for (var i = 0; i < n; i++) ...[
      Expanded(
        child: Container(
          height: 4,
          decoration: BoxDecoration(
            color: i <= st ? p.blue : p.ice2,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
      if (i != n - 1) const SizedBox(width: 4),
    ],
  ]);
}

Widget _slide(BuildContext context, AppState s, List<String> sl) {
  final p = Pal.of(context);
  final h = sl[0].replaceAll('{R}', peso(s.priceOf('refill'))).replaceAll('{B}', peso(s.priceOf('buy')));
  return Stack(children: [
    Container(
      // Themed: the light gradient turned into unreadable pale text in dark mode.
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: const Alignment(-0.3, -0.6),
          end: const Alignment(0.8, 0.8),
          colors: [p.ice, p.ice2],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Row(children: [
        Expanded(
          child: Column(mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(h,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: tx(context, 17, disp: true, w: FontWeight.w700, h: 1.2)),
            const SizedBox(height: 5),
            Text(sl[1],
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: tx(context, 13, color: p.muted, h: 1.35)),
          ]),
        ),
        Gal(sl[2] == 'buy' ? 'buy' : 'refill', h: 92),
      ]),
    ),
    // Affordance: the slide is a shortcut to that product, not a poster.
    Positioned(
      right: 10,
      top: 10,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(color: p.card, shape: BoxShape.circle),
        alignment: Alignment.center,
        child: Ic('chev', size: 15, color: p.link),
      ),
    ),
  ]);
}

class _Slides extends StatefulWidget {
  final AppState s;
  const _Slides(this.s);
  @override
  State<_Slides> createState() => _SlidesState();
}

class _SlidesState extends State<_Slides> with TickerProviderStateMixin {
  late final PageController _ctrl =
      PageController(initialPage: widget.s.slide.clamp(0, SLIDES_DATA.length - 1));
  Timer? _tmr;
  DateTime _userAt = DateTime.fromMillisecondsSinceEpoch(0);
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _page = widget.s.slide;
    _tmr = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted) return;
      if (MediaQuery.of(context).disableAnimations) return;
      if (DateTime.now().difference(_userAt).inMilliseconds < 4500) return;
      _goTo((_page + 1) % SLIDES_DATA.length);
    });
  }

  void _goTo(int i) {
    _ctrl.animateToPage(i, duration: const Duration(milliseconds: 450), curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _tmr?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    final p = Pal.of(context);
    final promo = Container(
      height: 156,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: p.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (n is ScrollStartNotification && n.dragDetails != null ||
              n is ScrollUpdateNotification && n.dragDetails != null) {
            _userAt = DateTime.now();
          }
          return false;
        },
        child: PageView(
          controller: _ctrl,
          onPageChanged: (i) {
            _page = i;
            s.slide = i;
            if (mounted) setState(() {});
          },
          // Each promo is a shortcut to the product it advertises; as a plain
          // poster it was the biggest dead area on the screen.
          children: [
            for (final sl in SLIDES_DATA)
              TapSurface(
                onTap: () => _openProduct(s, sl[2] == 'buy' ? 'buy' : 'refill'),
                semanticLabel: sl[0],
                child: _slide(context, s, sl),
              ),
          ],
        ),
      ),
    );
    // 22dp indicator row instead of 36dp: the carousel now sits under the
    // products, so it must not eat another slice of the screen.
    final dots = Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      for (var i = 0; i < SLIDES_DATA.length; i++)
        TapSurface(
          onTap: () => _goTo(i),
          semanticLabel: 'Slide ${i + 1} of ${SLIDES_DATA.length}',
          semanticSelected: i == _page,
          borderRadius: BorderRadius.circular(999),
          child: Container(
            width: 24,
            height: 22,
            alignment: Alignment.center,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: i == _page ? 16 : 6,
              height: 6,
              decoration: BoxDecoration(
                color: i == _page ? p.blue : p.ice2,
                borderRadius: BorderRadius.circular(i == _page ? 5 : 4),
                border: i == _page ? null : Border.all(color: p.blueHi),
              ),
            ),
          ),
        ),
    ]);
    return VGap([promo, dots], gap: 4);
  }
}

/* ================= order ================= */

Widget _prodCard(BuildContext context, AppState s, String k) {
  final p = Pal.of(context);
  return AquaCard(
    padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
    child: Column(children: [
      Gal(k, h: 84),
      const SizedBox(height: 6),
      Text(s.nameOf(k), textAlign: TextAlign.center,
          style: tx(context, 16, disp: true, w: FontWeight.w700)),
      Text(k == 'refill' ? 'Refill your empty gallon.' : 'New filled gallon with container.',
          textAlign: TextAlign.center, style: tx(context, 13, color: p.muted, h: 1.3)),
      const SizedBox(height: 4),
      SizedBox(width: double.infinity, child: Row(children: [
        Expanded(child: Text('${peso(s.priceOf(k))} / gallon',
            style: tx(context, 14, w: FontWeight.w800, fontFeatures: numFeatures))),
        Container(width: 30, height: 30,
          decoration: BoxDecoration(color: p.ice, shape: BoxShape.circle),
          alignment: Alignment.center,
          child: Ic('chev', size: 16, color: p.link)),
      ])),
    ]),
  );
}

ScreenView orderView(BuildContext context, AppState s) {
  final d = s.draft;
  final t = d.type;
  final price = s.priceOf(t);
  final q = d.qty;
  final block = s.orderBlock(t, q);
  return ScreenView(
    content: PadScroll(children: [
      SegBar(items: [
        SegItem('refill', s.nameOf('refill'), icon: 'drop'),
        SegItem('buy', s.nameOf('buy'), icon: 'box'),
      ], value: t, onSelect: s.doType),
      _prodHeroCard(context, s),
      _explainCard(context, t),
      SectionHead('Delivery Details', icon: 'truck'),
      VGap(_deliveryRows(context, s), gap: 8),
    ]),
    dock: Column(mainAxisSize: MainAxisSize.min, children: [
      DockTotal(main: 'Total', small: '(${pl(q, 'Gallon')})', amount: peso(price * q)),
      const SizedBox(height: 10),
      block.isEmpty
          ? Btn('Add to Cart', icon: 'cart', onPressed: s.addToCart)
          : Btn(block, onPressed: null),
    ]),
  );
}

Widget _prodHeroCard(BuildContext context, AppState s) {
  final p = Pal.of(context);
  final t = s.draft.type;
  final price = s.priceOf(t);
  return AquaCard(
    background: p.ice,
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      RowW([
        Gal(t, h: 150),
        Expanded(child: VGap([
          Text(s.nameOf(t), style: tx(context, 22, disp: true, w: FontWeight.w700)),
          Text(s.descOf(t), style: para(context, color: p.muted)),
          Text.rich(TextSpan(children: [
            TextSpan(text: peso(price),
                style: tx(context, 23, disp: true, w: FontWeight.w700, fontFeatures: numFeatures)),
            const TextSpan(text: ' '),
            TextSpan(text: '/ gallon',
                style: tx(context, 14, w: FontWeight.w600, color: p.muted)),
          ])),
        ], gap: 8)),
      ], gap: 16),
      const SizedBox(height: 14),
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Expanded(
            child: Text('Quantity', style: tx(context, 15, w: FontWeight.w700))),
        StepperCtl(qty: s.draft.qty, onChange: s.draftQty),
      ]),
      const SizedBox(height: 10),
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Expanded(child: Text('${peso(price)} × ${s.draft.qty}',
            style: tx(context, 15, w: FontWeight.w700, color: p.muted, fontFeatures: numFeatures))),
        Text(peso(price * s.draft.qty),
            style: tx(context, 15, w: FontWeight.w700, color: p.muted, fontFeatures: numFeatures)),
      ]),
    ]),
  );
}

Widget _explainCard(BuildContext context, String t) {
  final p = Pal.of(context);
  final rows = t == 'refill'
      ? [['You provide', ' your own empty gallon.'],
         ['We provide', ' purified water to refill it. Price is per refill.']]
      : [['You get', ' a new filled gallon with its container.'],
         ['No empty gallon needed.', ' Price is per new gallon.']];
  return AquaCard( child: VGap([
    for (final r in rows)
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Ic('check', size: 18, color: p.ok),
        const SizedBox(width: 10),
        Expanded(child: Text.rich(TextSpan(children: [
          TextSpan(text: r[0], style: tx(context, 14, w: FontWeight.w700)),
          TextSpan(text: r[1], style: tx(context, 14)),
        ]))),
      ]),
  ], gap: 6));
}

/// The three `.rowbtn` delivery-detail rows shared by Order and Checkout.
List<Widget> _deliveryRows(BuildContext context, AppState s) {
  final a = s.curAddr();
  final d = s.draft;
  return [
    RowBtn(icon: 'pin', title: 'Delivery Address',
      value: a == null ? 'Add a delivery address' : '${a.label} · ${a.line}',
      warn: a == null,
      onTap: () => _addressPickerSheet(context, s)),
    RowBtn(icon: 'cal', title: 'Preferred Delivery Time',
      value: timeLabel(d.time),
      onTap: () => _timeSheet(context, s)),
    RowBtn(icon: 'pencil', title: 'Note (Optional)',
      value: d.note.isEmpty ? 'Gate code, landmark, instructions' : d.note,
      onTap: () => _noteSheet(context, s)),
  ];
}

/* ================= sheets (order / checkout) ================= */

void _addressPickerSheet(BuildContext context, AppState s) {
  final p = Pal.of(context);
  showAquaSheet(context, title: 'Delivery Address', body: VGap([
    if (s.addresses.isEmpty)
      Text('You have no saved addresses yet.', style: para(context, color: p.muted))
    else
      ...s.addresses.map((a) => RadioRow(
        checked: s.curAddr()?.id == a.id,
        onTap: () {
          s.pickAddress(a.id);
          Navigator.of(context).pop();
        },
        content: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Flexible(child: Text(a.label, style: tx(context, 15, w: FontWeight.w700))),
            if (a.def) ...[const SizedBox(width: 8), const Tag('Default')],
          ]),
          Text(a.line, style: tx(context, 13, color: p.muted)),
        ]),
      )),
    const SizedBox(height: 14),
    Btn('Add new address', icon: 'plus', iconSize: 20, kind: BtnKind.alt, onPressed: () {
      Navigator.of(context).pop();
      _addressFormSheet(context, s, null, true);
    }),
  ], gap: 8));
}

void _addressFormSheet(BuildContext context, AppState s, Address? a, bool pick) {
  showAquaSheet(
    context,
    title: a == null ? 'New Address' : 'Edit Address',
    body: _AddressForm(s: s, addr: a, pick: pick),
  );
}

class _AddressForm extends StatefulWidget {
  final AppState s;
  final Address? addr;
  final bool pick;
  const _AddressForm({required this.s, required this.addr, required this.pick});
  @override
  State<_AddressForm> createState() => _AddressFormState();
}

class _AddressFormState extends State<_AddressForm> {
  late final _street = TextEditingController(text: widget.addr?.street ?? '');
  late final _brgy = TextEditingController(text: widget.addr?.brgy ?? '');
  late final _city = TextEditingController(text: widget.addr?.city ?? '');
  late final _landmark = TextEditingController(text: widget.addr?.landmark ?? '');
  double? _lat;
  double? _lng;
  String _label = 'Home';
  bool _def = false;
  String _err = '';

  static String _labelOf(Address? a) {
    for (final o in const ['Home', 'Work', 'Other']) {
      if (a != null && a.label == o) return o;
    }
    return 'Home';
  }

  @override
  void initState() {
    super.initState();
    _label = _labelOf(widget.addr);
    _def = widget.addr?.def ?? widget.s.addresses.isEmpty;
    _lat = widget.addr?.lat;
    _lng = widget.addr?.lng;
  }

  @override
  void dispose() {
    _street.dispose();
    _brgy.dispose();
    _city.dispose();
    _landmark.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final s = widget.s;
    return VGap([
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Label', style: tx(context, 13, w: FontWeight.w700, color: p.muted, ls: .2)),
        const SizedBox(height: 6),
        Chips(options: const ['Home', 'Work', 'Other'], value: _label,
            onSelect: (v) => setState(() => _label = v)),
      ]),
      AquaField('House no. / street / building', _street),
      AquaField('Barangay', _brgy),
      AquaField('City / municipality', _city),
      AquaField('Landmark or delivery note (optional)', _landmark),
      Btn(_lat == null ? 'Set pin on map' : 'Adjust pin on map',
          icon: 'pin',
          kind: _lat == null ? BtnKind.primary : BtnKind.alt,
          onPressed: () async {
            // The pin is only the spot on the map; it never writes into the
            // fields. A reverse-geocoded street is a guess — around here it
            // resolved to the highway instead of the purok — and overwriting
            // what the customer meant to type sent riders to the wrong gate.
            final picked = await openPinPickerPage(
              context,
              initial: _lat != null && _lng != null ? LatLng(_lat!, _lng!) : null,
              resolveAddress: false,
            );
            if (picked == null) return;
            setState(() {
              _lat = picked.point.latitude;
              _lng = picked.point.longitude;
            });
          }),
      Text(
        _lat == null
            ? 'No map pin yet — add one so you can watch your rider approach on the live map.'
            : 'Pin set (${_lat!.toStringAsFixed(5)}, ${_lng!.toStringAsFixed(5)}). '
                'Type your address in the fields above — the pin does not fill them in.',
        style: tx(context, 13, color: _lat == null ? p.muted : p.ok, h: 1.4),
      ),
      CheckRow(
        value: _def,
        onChanged: (v) => setState(() => _def = v),
        label: 'Use as my default address',
      ),
      ErrLine(_err),
      Btn('Save Address', onPressed: () {
        final street = _street.text.trim(), brgy = _brgy.text.trim();
        final city = _city.text.trim();
        if (street.isEmpty || brgy.isEmpty || city.isEmpty) {
          setState(() => _err =
              'Enter the street, barangay and city or municipality so the rider can find you.');
          return;
        }
        s.saveAddress(
          id: widget.addr?.id,
          label: _label,
          street: street,
          brgy: brgy,
          city: city,
          landmark: _landmark.text.trim(),
          def: _def,
          pick: widget.pick,
          lat: _lat,
          lng: _lng,
        );
        Navigator.of(context).pop();
      }),
    ]);
  }
}

void _timeSheet(BuildContext context, AppState s) {
  final p = Pal.of(context);
  final cur = s.draft.time;
  final list = <String>['asap', ...slots()];
  showAquaSheet(
    context,
    title: 'Preferred Delivery Time',
    body: VGap([
      for (final v in list)
        RadioRow(
          checked: cur == v,
          onTap: () {
            s.setDraftTime(v);
            Navigator.of(context).pop();
          },
          content: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(v == 'asap' ? 'As soon as possible' : v, style: tx(context, 15, w: FontWeight.w700)),
            if (v == 'asap')
              Text('Usually 30–45 minutes', style: tx(context, 13, color: p.muted)),
          ]),
        ),
    ], gap: 8),
  );
}

void _noteSheet(BuildContext context, AppState s) {
  showAquaSheet(context, title: 'Note for the rider', body: _NoteForm(s: s));
}

class _NoteForm extends StatefulWidget {
  final AppState s;
  const _NoteForm({required this.s});
  @override
  State<_NoteForm> createState() => _NoteFormState();
}

class _NoteFormState extends State<_NoteForm> {
  late final _note = TextEditingController(text: widget.s.draft.note);

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    return VGap([
      AquaField('Note (optional)', _note, maxLines: 3, minHeight: 96,
          hint: 'Gate code, landmark, or where to leave the gallon'),
      Btn('Save Note', onPressed: () {
        s.setDraftNote(_note.text.trim());
        Navigator.of(context).pop();
      }),
    ]);
  }
}

/* ================= cart ================= */

ScreenView cartView(BuildContext context, AppState s) {
  if (s.cart.isEmpty) {
    return ScreenView(
      content: PadScroll(children: [
        EmptyView(
          'Your cart is empty',
          msg: 'Add refills or new gallons to get started.',
          galType: 'refill',
          action: Btn('Order Water', onPressed: () {
            s.draft.type = 'refill';
            s.draft.qty = 1;
            s.goScreen('order');
          }),
        ),
      ]),
    );
  }
  final tot = s.sumItems(s.cart);
  final kids = <Widget>[];
  for (var i = 0; i < s.cart.length; i++) {
    if (kids.isNotEmpty) kids.add(const SizedBox(height: 14));
    kids.add(_cartLine(context, s, i));
  }
  kids.add(const SizedBox(height: 14));
  kids.add(_summaryCard(context, s));
  kids.add(const SizedBox(height: 14));
  kids.add(Btn('Add more water', icon: 'plus', iconSize: 20, kind: BtnKind.alt, onPressed: () {
    if (s.draft.type == 'refill' || s.draft.type == 'buy') {
      s.draft.qty = 1;
      s.goScreen('order');
    } else {
      s.draft.type = 'refill';
      s.draft.qty = 1;
      s.goScreen('order');
    }
  }));
  return ScreenView(
    content: PadScroll(children: kids),
    dock: Btn('Checkout · ${peso(tot)}', icon: 'truck', onPressed: () => s.goScreen('checkout')),
  );
}

Widget _cartLine(BuildContext context, AppState s, int i) {
  final p = Pal.of(context);
  final it = s.cart[i];
  final price = s.priceOf(it.type);
  return AquaCard(child: RowW([
    Gal(it.type, h: 70),
    const SizedBox(width: 12),
    Expanded(child: VGap([
      Row(children: [
        Expanded(child: Text(s.nameOf(it.type), style: tx(context, 16, disp: true, w: FontWeight.w700))),
        IconAction('trash', onTap: () => s.cartDelete(i), color: p.danger, label: 'Remove ${s.nameOf(it.type)}'),
      ]),
      Text('${peso(price)} / gallon · ${it.type == 'refill' ? 'bring your empty gallon' : 'filled gallon with container'}',
          style: numStyle(context, size: 13, color: p.muted)),
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        StepperCtl(small: true, qty: it.qty, onChange: (d) => s.cartQty(i, d)),
        const SizedBox(width: 8),
        // The stepper is a fixed width; a three-digit total at 1.3x text pushed
        // the line past the card, so the money shrinks instead of clipping.
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: Text(peso(price * it.qty),
                style: tx(context, 15, disp: true, w: FontWeight.w700, fontFeatures: numFeatures)),
          ),
        ),
      ]),
    ], gap: 4)),
  ], gap: 12));
}

/// Order summary card shared by Cart and Checkout.
Widget _summaryCard(BuildContext context, AppState s) {
  final p = Pal.of(context);
  final tot = s.sumItems(s.cart);
  return AquaCard( child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    SectionHead('Order Summary', icon: 'cart', iconSize: 22),
    const SizedBox(height: 8),
    for (final it in s.cart)
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(children: [
          Expanded(child: Text('${s.nameOf(it.type)} × ${it.qty}', style: numStyle(context))),
          Text(peso(s.priceOf(it.type) * it.qty), style: numStyle(context)),
        ]),
      ),
    Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(children: [
        Expanded(child: Text('Delivery', style: tx(context, 15, color: p.muted))),
        Text('Free', style: tx(context, 15, color: p.muted)),
      ]),
    ),
    Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(color: p.ice, borderRadius: BorderRadius.circular(14)),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Flexible(
            child: Text('Total', style: tx(context, 20, disp: true, w: FontWeight.w700))),
        // Money labels scale down rather than clip on a 320dp screen at 1.3x.
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: Text(peso(tot),
                style: tx(context, 20, disp: true, w: FontWeight.w700, fontFeatures: numFeatures)),
          ),
        ),
      ]),
    ),
  ]));
}

/* ================= checkout ================= */

/// Checkout errors are short-lived; the notifier lives at module level and is
/// cleared every time the screen mounts (HTML re-renders clear it too).
final ValueNotifier<String> _coErr = ValueNotifier<String>('');

ScreenView checkoutView(BuildContext context, AppState s) {
  return ScreenView(
    content: _CheckoutBody(s),
    dock: _CheckoutDock(s),
  );
}

class _CheckoutBody extends StatefulWidget {
  final AppState s;
  const _CheckoutBody(this.s);
  @override
  State<_CheckoutBody> createState() => _CheckoutBodyState();
}

class _CheckoutBodyState extends State<_CheckoutBody> {
  @override
  void initState() {
    super.initState();
    _coErr.value = '';
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: _coErr,
      builder: (context, err, _) {
        return PadScroll(children: [
          SectionHead('Delivery Details', icon: 'truck'),
          VGap(_deliveryRows(context, widget.s), gap: 8),
          SectionHead('Payment', icon: 'cash'),
          VGap(_payRows(context, widget.s), gap: 8),
          _summaryCard(context, widget.s),
          ErrLine(err),
        ]);
      },
    );
  }
}

List<Widget> _payRows(BuildContext context, AppState s) {
  const opts = [
    ['cod', 'Cash on Delivery', 'Pay the rider in cash'],
    ['gcash', 'GCash on Delivery', 'Pay the rider by scanning their GCash QR'],
  ];
  return [
    for (final p0 in opts)
      RadioRow(
        checked: s.draft.pay == p0[0],
        onTap: () => s.setPay(p0[0]),
        content: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(p0[1], style: tx(context, 15, w: FontWeight.w700)),
          Text(p0[2], style: tx(context, 13, color: Pal.of(context).muted)),
        ]),
      ),
  ];
}

class _CheckoutDock extends StatelessWidget {
  final AppState s;
  const _CheckoutDock(this.s);
  @override
  Widget build(BuildContext context) {
    final tot = s.sumItems(s.cart);
    final cc = s.cartCount();
    return Column(mainAxisSize: MainAxisSize.min, children: [
      DockTotal(main: 'Total', small: '(${pl(cc, 'Gallon')})', amount: peso(tot)),
      const SizedBox(height: 10),
      Btn('Place Order', icon: 'truck', onPressed: () async {
        final e = await s.placeOrder();
        if (e != null) {
          _coErr.value = e;
          s.toast(e);
        }
      }),
    ]);
  }
}

/* ================= generic confirm sheet ================= */

void _confirmSheet(
  BuildContext context, {
  required String title,
  required String msg,
  required String label,
  bool danger = false,
  String keep = 'Keep it',
  required VoidCallback onConfirm,
}) {
  showAquaSheet(context, title: title, body: VGap([
    Text(msg, style: para(context, color: Pal.of(context).muted)),
    const SizedBox(height: 2),
    Btn(label, kind: danger ? BtnKind.danger : BtnKind.primary, onPressed: () {
      Navigator.of(context).pop();
      onConfirm();
    }),
    Btn(keep, kind: BtnKind.alt, onPressed: () => Navigator.of(context).pop()),
  ], gap: 10, crossStart: false));
}

/* ================= confirm (order placed) ================= */

ScreenView confirmView(BuildContext context, AppState s) {
  final Order? o = _first(s.orders, (x) => x.id == s.lastOrderId);
  if (o == null) {
    return ScreenView(
      content: PadScroll(children: [
        EmptyView(
          'Order not found',
          msg: 'The order confirmation is no longer available.',
          action: Btn(
            'Back to Home',
            kind: BtnKind.alt,
            onPressed: () => s.goScreen('home', fresh: true),
          ),
        ),
      ]),
    );
  }
  return ScreenView(
    content: PadScroll(children: [
      _doneBlock(context, s),
      _confirmInfoCard(context, s, o),
      _confirmItemsCard(context, s, o),
      _confirmAddrCard(context, s, o),
    ]),
    dock: Column(mainAxisSize: MainAxisSize.min, children: [
      Btn('Track Delivery', icon: 'pin', onPressed: () {
        s.trackId = o.id;
        s.goScreen('track');
      }),
      const SizedBox(height: 10),
      Btn('Back to Home', kind: BtnKind.alt, onPressed: () => s.goScreen('home')),
    ]),
  );
}

Widget _doneBlock(BuildContext context, AppState s) {
  final p = Pal.of(context);
  return VGap(crossStart: false, gap: 8, [
    Column(children: [
      const _TickPop(),
      const SizedBox(height: 10),
      Text('Order Placed!', style: tx(context, 24, disp: true, w: FontWeight.w700)),
    ]),
    Text('Thank you, ${s.firstName()}. The station has received your order.',
        textAlign: TextAlign.center,
        style: para(context, color: p.muted)),
  ]);
}

class _TickPop extends StatefulWidget {
  const _TickPop();
  @override
  State<_TickPop> createState() => _TickPopState();
}

class _TickPopState extends State<_TickPop> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 500))
        ..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    if (MediaQuery.disableAnimationsOf(context)) return _tick(p);
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = Curves.easeOut.transform(_c.value);
        return Opacity(
          opacity: t.clamp(0.0, 1.0),
          child: Transform.scale(
            scale: .6 + .4 * t,
            child: _tick(p),
          ),
        );
      },
    );
  }

  Widget _tick(Pal p) {
    return Container(
      width: 84, height: 84,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: Pal.btnBlue,
        boxShadow: [BoxShadow(color: p.blueHi.withValues(alpha: .18), spreadRadius: 10)],
      ),
      child: Ic('check', size: 44, color: Colors.white),
    );
  }
}

Widget _confirmInfoCard(BuildContext context, AppState s, Order o) {
  return AquaCard(
    background: Pal.of(context).ice,
    child: VGap([
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Flexible(
            child: Text('Order number', style: tx(context, 15, color: Pal.of(context).muted))),
        const SizedBox(width: 12),
        Flexible(child: Text(o.id, textAlign: TextAlign.right,
            style: tx(context, 15, disp: true, w: FontWeight.w700, ls: .4))),
      ]),
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text('Status', style: tx(context, 15, color: Pal.of(context).muted)),
        OrdBadge(statusState(o)),
      ]),
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        // The label is fixed text and the estimate can be a long range; let the
        // label shrink instead of pushing the row past the card at 1.3x.
        Flexible(
            child: Text('Estimated arrival',
                style: tx(context, 15, color: Pal.of(context).muted))),
        const SizedBox(width: 12),
        Flexible(child: Text(etaText(o), textAlign: TextAlign.right,
            style: numStyle(context, w: FontWeight.w700))),
      ]),
    ], gap: 10),
  );
}

Widget _confirmItemsCard(BuildContext context, AppState s, Order o) {
  final p = Pal.of(context);
  return AquaCard( child: Column(children: [
    for (final it in o.items) ...[
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(children: [
          Gal(it.type, h: 44),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${s.nameOf(it.type)} × ${it.qty}',
                style: tx(context, 15, disp: true, w: FontWeight.w700)),
            Text('${peso(_unitPrice(o, s, it.type))} each',
                style: numStyle(context, size: 13, color: p.muted)),
          ])),
          Text(peso(_unitPrice(o, s, it.type) * it.qty), style: numStyle(context, w: FontWeight.w700)),
        ]),
      ),
    ],
    Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(color: p.ice, borderRadius: BorderRadius.circular(14)),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Flexible(
            child: Text('Total', style: tx(context, 20, disp: true, w: FontWeight.w700))),
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: Text(peso(o.total),
                style: tx(context, 20, disp: true, w: FontWeight.w700, fontFeatures: numFeatures)),
          ),
        ),
      ]),
    ),
  ]));
}

Widget _confirmAddrCard(BuildContext context, AppState s, Order o) {
  final p = Pal.of(context);
  return AquaCard( child: VGap([
    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Ic('pin', size: 20, color: p.ink),
      const SizedBox(width: 10),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(o.address.label, style: tx(context, 15, w: FontWeight.w700)),
        Text(o.address.line, style: tx(context, 13, color: p.muted)),
      ])),
    ]),
    Row(children: [
      Ic('cash', size: 20, color: p.ink),
      const SizedBox(width: 10),
      Expanded(child: Text(o.pay == 'gcash' ? 'GCash on Delivery' : 'Cash on Delivery',
          style: tx(context, 15))),
    ]),
  ], gap: 10));
}

/* ================= track ================= */

ScreenView trackView(BuildContext context, AppState s) {
  final mineList = s.myOrders()..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  Order? o;
  if (s.trackId != null) {
    final f = _first(s.orders, (x) => x.id == s.trackId);
    // An order the customer picked themselves — from My Orders, a finished
    // order's Details button or a cancellation notice — is the one to show,
    // cancelled or not. Falling through to another order made "Details" open
    // somebody else's delivery.
    if (f != null && s.mine(f)) o = f;
  }
  o ??= _first(mineList, isActive);
  o ??= mineList.isEmpty ? null : mineList.first;
  if (o == null) {
    return ScreenView(
      content: PadScroll(children: [
        EmptyView(
          'No orders to track',
          msg: 'Place an order and follow it here, step by step.',
          galType: 'refill',
          action: Btn('Order Water', onPressed: () {
            s.draft.type = 'refill';
            s.draft.qty = 1;
            s.goScreen('order');
          }),
        ),
      ]),
    );
  }
  final st = o.status;
  final cn = o.cancelled;
  final oid = o.id;

  final kids = <Widget>[];
  void add(Widget w) {
    if (kids.isNotEmpty) kids.add(const SizedBox(height: 14));
    kids.add(w);
  }

  add(_trackHeadCard(context, o, st, cn));

  if (!cn && st == 3 && o.arrivedAt != null) {
    final p = Pal.of(context);
    final r = s.riderOf(o);
    add(AquaCard(
      background: p.s4bg,
      borderColor: p.s4fg,
      child: Row(children: [
        Ic('bell', size: 24, color: p.s4fg),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Your rider has arrived', style: tx(context, 15, w: FontWeight.w700)),
          Text('${r != null ? 'Rider ${r.name.split(' ').first}' : 'Your rider'} is outside since '
              '${tfmt(o.arrivedAt!)}. Please meet them at the door.',
              style: tx(context, 13)),
        ])),
      ]),
    ));
  }

  // The map appears as soon as somebody owns the delivery — a rider assigned
  // while the water is still being prepared is already visible and already
  // moving, so the customer never has to wait for status 3 to see them. It is
  // gone again at the door: once the gallons are handed over there is nothing
  // left to watch, and a last position frozen on the map reads like the rider
  // is still out there.
  if (!cn && st < 4 && o.address.hasPin && (st >= 2 || o.riderId != null)) {
    add(_LiveTrackCard(s: s, o: o));
  }

  if (!cn && st >= 3) {
    final r = s.riderOf(o);
    final phone = r?.phone ?? '';
    add(AquaCard( child: Row(children: [
      Container(width: 48, height: 48,
        decoration: BoxDecoration(shape: BoxShape.circle, color: Pal.of(context).ice),
        alignment: Alignment.center,
        child: Ic('truck', size: 22, color: Pal.of(context).link)),
      const SizedBox(width: 10),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Rider ${r?.name ?? 'Your rider'}', style: tx(context, 15, w: FontWeight.w700)),
        Text(phone, style: numStyle(context, size: 13, color: Pal.of(context).muted)),
      ])),
      Btn('Copy', icon: 'copy', iconSize: 18, kind: BtnKind.alt, small: true, onPressed: () {
        Clipboard.setData(ClipboardData(text: phone));
        s.toast('Copied');
      }),
    ])));
  }

  if (o.issue != null) {
    final p = Pal.of(context);
    add(AquaCard(
      background: p.s0bg,
      borderColor: p.s0fg,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(o.cancelled ? 'Delivery cancelled' : 'Delivery issue reported',
            style: tx(context, 15, w: FontWeight.w700)),
        Text('${o.issue!.type}${o.cancelled ? '.' : '. Your rider will contact you.'}',
            style: tx(context, 13)),
      ]),
    ));
  }

  add(_trackStatusCard(context, s, o, st, cn));
  add(_trackDetailsCard(context, s, o, st, cn));

  if (!cn && st <= 1) {
    add(Btn('Cancel Order', kind: BtnKind.alt, onPressed: () {
      _confirmSheet(context,
        title: 'Cancel this order?',
        msg: 'Order $oid will be cancelled. You can place a new order any time.',
        label: 'Cancel Order',
        danger: true,
        onConfirm: () => s.cancelOrder(oid));
    }));
  }

  add(Btn('View all orders', kind: BtnKind.ghost, onPressed: () => s.goScreen('orders')));

  return ScreenView(content: PadScroll(children: kids));
}

/// Live delivery map for the track screen. The rider marker comes from the
/// rider's real GPS and nothing else: there used to be a simulated position
/// derived from the order's status stamps, which drew a marker gliding down
/// the road whether or not anyone had left the station.
class _LiveTrackCard extends StatefulWidget {
  final AppState s;
  final Order o;
  const _LiveTrackCard({required this.s, required this.o});
  @override
  State<_LiveTrackCard> createState() => _LiveTrackCardState();
}

class _LiveTrackCardState extends State<_LiveTrackCard> {
  StreamSubscription<RiderFix?>? _sub;
  RiderFix? _fix;
  String? _watchingRid;
  Timer? _ageTick;
  bool _retried = false;

  @override
  void initState() {
    super.initState();
    _watchOrderRider();
    // This timer only refreshes the "12 s ago" line. The marker itself moves
    // when a fix arrives on the stream, never on a clock.
    _ageTick = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted && _fix != null) setState(() {});
    });
  }

  void _watchOrderRider() {
    final rid = widget.o.riderId;
    _sub?.cancel();
    _sub = null;
    // Stored normalised: build() compares against `riderId ?? ''`, and a null
    // here made every rebuild look like a new rider and resubscribe.
    _watchingRid = rid ?? '';
    final stream = watchRider(rid ?? '');
    _sub = stream?.listen((f) {
      if (mounted) setState(() => _fix = f);
    });
  }

  @override
  void dispose() {
    _ageTick?.cancel();
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final s = widget.s;
    final o = widget.o;
    // The rider may get assigned while this screen is open (same Order object
    // is mutated in place), so re-check the subscription every rebuild.
    final wantRid = o.riderId ?? '';
    if (wantRid != _watchingRid) {
      _fix = null;
      _retried = false;
      _watchOrderRider();
    } else if (_sub == null && !_retried && firebaseReady && wantRid.isNotEmpty) {
      // Firebase came online after this card mounted, so the first subscribe
      // returned null. Try once more now that the socket is up.
      _retried = true;
      _watchOrderRider();
    }
    final station = LatLng(s.station.lat!, s.station.lng!);
    final dest = LatLng(o.address.lat!, o.address.lng!);
    final fix = _fix;
    // A default-constructed fix (no lat/lng in the doc yet) is not a position;
    // LatLng(0, 0) would put the rider in the Atlantic.
    final point = (fix == null || (fix.lat == 0 && fix.lng == 0)) ? null : fix.point;
    final fresh = point != null && fix!.isFresh;
    final ageS = point == null
        ? 0
        : ((DateTime.now().millisecondsSinceEpoch - fix!.ts) / 1000).round();

    // No alarm states on this card. A gap between fixes is normal — tunnels,
    // dead zones, a rider who pocketed the phone — so the map keeps the last
    // position and the caption quietly says when it last changed, instead of
    // flashing "signal lost" at the customer.
    final String note = fresh
        ? 'Your rider\'s position, updated ${ageS < 5 ? 'just now' : '${_ago(ageS)} ago'}.'
        : point != null
            ? 'Your rider\'s last position, ${_ago(ageS)} ago. The map moves on as they ride.'
            : wantRid.isEmpty
                ? 'The station is matching a rider to this order.'
                : firebaseReady
                    ? 'Your rider\'s position appears here as soon as their phone reports it.'
                    : 'Live tracking needs an internet connection.';

    return AquaCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        RowW([
          Expanded(child: SectionHead('Live Tracking', icon: 'map')),
          // Only a live fix earns a badge. Everything else is explained in the
          // caption below, in words rather than a warning colour.
          if (fresh)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: p.mintBg,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text('LIVE GPS',
                  style: tx(context, 11, w: FontWeight.w700, ls: .6, color: p.mintFg)),
            ),
        ]),
        const SizedBox(height: 12),
        DeliveryTrackMap(
          station: station,
          dest: dest,
          rider: point,
        ),
        const SizedBox(height: 10),
        Text(note, style: tx(context, 13, color: p.muted, h: 1.4)),
      ]),
    );
  }
}

String _ago(int s) => s < 60 ? '${s}s' : '${s ~/ 60}m';

Widget _trackHeadCard(BuildContext context, Order o, int st, bool cn) {
  final p = Pal.of(context);
  return AquaCard(
    background: p.ice,
    child: VGap([
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Order number', style: tx(context, 13, color: p.muted)),
          Text(o.id, style: tx(context, 18, disp: true, w: FontWeight.w700, ls: .4)),
        ])),
        OrdBadge(statusState(o)),
      ]),
      if (cn)
        Align(alignment: Alignment.centerLeft,
            child: Text('This order was cancelled.', style: para(context, color: p.muted))),
      if (!cn) ...[
        _routeStrip(context, st),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(color: p.ice2, borderRadius: BorderRadius.circular(14)),
          child: Row(children: [
            Ic('clock', size: 20, color: p.blue),
            const SizedBox(width: 10),
            Expanded(child: st >= 4
                ? Text('Delivered at ${_deliveredAt(o)}',
                    style: tx(context, 15, w: FontWeight.w700))
                : Text('Estimated arrival · ${etaText(o)}',
                    style: tx(context, 15, w: FontWeight.w700))),
          ]),
        ),
      ],
    ], gap: 10),
  );
}

String _deliveredAt(Order o) {
  final ts = _stamp(o, 4);
  return ts == null ? '' : tfmt(ts);
}

/// The dashed station→home progress strip.
Widget _routeStrip(BuildContext context, int st) {
  final p = Pal.of(context);
  final frac = st >= 4 ? 1.0 : (st == 3 ? .55 : 0.0);
  return LayoutBuilder(builder: (context, cons) {
    final w = cons.maxWidth;
    return SizedBox(
      height: 74,
      child: Stack(children: [
        Positioned(
          left: 28, right: 28, top: 34,
          child: SizedBox(height: 3, child: CustomPaint(painter: _DashLine(painterColor: p.ice2))),
        ),
        if (frac > 0)
          Positioned(
            left: 28, top: 34,
            width: (w - 56) * frac,
            child: Container(height: 3, color: p.blue),
          ),
        Positioned(
          left: 0, top: 10,
          child: _routeBox(context, 'drop', false),
        ),
        Positioned(
          right: 0, top: 10,
          child: _routeBox(context, 'home', st >= 4),
        ),
        // Only draw the truck while it is between the two stops. At frac 0 it
        // would sit on the station box and at frac 1 on the home box, hiding
        // the icon that actually communicates the state.
        if (frac > 0 && frac < 1)
          Positioned(
            left: 28 + (w - 56) * frac,
            top: 21,
            child: Transform.translate(
              offset: const Offset(-17, 0),
              child: Container(width: 34, height: 30,
                decoration: BoxDecoration(color: p.blue, borderRadius: BorderRadius.circular(10)),
                alignment: Alignment.center,
                child: Ic('truck', size: 20, color: Colors.white)),
            ),
          ),
      ]),
    );
  });
}

Widget _routeBox(BuildContext context, String icon, bool on) {
  final p = Pal.of(context);
  return Container(width: 52, height: 52,
    decoration: BoxDecoration(
      color: on ? p.ok : p.ice,
      border: Border.all(color: on ? p.ok : p.line),
      borderRadius: BorderRadius.circular(16),
    ),
    alignment: Alignment.center,
    child: Ic(icon, size: 24, color: on ? Colors.white : p.link),
  );
}

class _DashLine extends CustomPainter {
  final Color painterColor;
  _DashLine({required this.painterColor});
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = painterColor
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;
    const dash = 7.0, gap = 5.0;
    final y = size.height / 2;
    double x = 0;
    while (x < size.width) {
      final end = x + dash >= size.width ? size.width : x + dash;
      canvas.drawLine(Offset(x, y), Offset(end, y), paint);
      x += dash + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _DashLine old) => old.painterColor != painterColor;
}

Widget _trackStatusCard(BuildContext context, AppState s, Order o, int st, bool cn) {
  final p = Pal.of(context);
  final refillDone = o.items.any((x) => x.type == 'refill');
  const descs = [
    'We received your order.',
    'The station accepted it.',
    '', // index 2 is computed below (refill vs buy wording)
    'Your rider is on the way.',
    'Delivered to your address.',
  ];
  return AquaCard( child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    SectionHead('Delivery Status'),
    const SizedBox(height: 14),
    for (var i = 0; i < STAGE.length; i++)
      _tlItem(
        context,
        s,
        o,
        i,
        stageName: STAGE[i],
        desc: i == 2 ? (refillDone ? 'Your gallons are being refilled.' : 'Your gallons are being prepared.') : descs[i],
        cn: cn,
        st: st,
        last: i == STAGE.length - 1,
      ),
    if (!cn && st < 4) ...[
      const SizedBox(height: 14),
      Text(
        s.settings.autoDeliver
            ? 'Confirmation and preparation are simulated in this demo; your rider marks the delivery stages.'
            : 'Delivery updates come from the station and your rider.',
        style: tx(context, 13, color: p.muted),
      ),
    ],
  ]));
}

bool _tlDone(int i, int st, bool cn) =>
    cn ? i <= math.min(st, 1) : (i < st || st == 4);

Widget _tlItem(BuildContext context, AppState s, Order o, int i,
    {required String stageName, required String desc, required bool cn, required int st, required bool last}) {
  final p = Pal.of(context);
  final done = _tlDone(i, st, cn);
  final cur = !cn && i == st;
  final ts = _stamp(o, i);
  return Padding(
    padding: last ? EdgeInsets.zero : const EdgeInsets.only(bottom: 18),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Column(children: [
        cur ? const _PulseDot() : Container(width: 28, height: 28,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: done ? p.blue : p.card,
            border: Border.all(color: done ? p.blue : p.line, width: 2),
          ),
          alignment: Alignment.center,
          child: done ? Ic('check', size: 15, color: Colors.white) : null,
        ),
        if (!last)
          Container(width: 2, height: 34, color: done ? p.blue : p.line),
      ]),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(stageName, style: tx(context, 15, disp: true, w: FontWeight.w700,
            color: cur ? p.ink : (done ? p.ink : p.muted))),
        Text(desc, style: tx(context, 13, color: p.muted)),
      ])),
      if (ts != null && i <= st)
        Text(tfmt(ts), style: numStyle(context, size: 13, color: p.muted)),
    ]),
  );
}

class _PulseDot extends StatefulWidget {
  const _PulseDot();
  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))
        ..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = _c.value;
        return Container(width: 28, height: 28,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: p.card,
            border: Border.all(color: p.blue, width: 2),
            boxShadow: [BoxShadow(
              color: p.blueHi.withValues(alpha: .25 - .17 * t),
              spreadRadius: 5 + 4 * t,
            )],
          ),
        );
      },
    );
  }
}

Widget _trackDetailsCard(BuildContext context, AppState s, Order o, int st, bool cn) {
  final p = Pal.of(context);
  return AquaCard( child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    SectionHead('Order Details'),
    const SizedBox(height: 10),
    for (final it in o.items)
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(children: [
          Expanded(child: Text('${s.nameOf(it.type)} × ${it.qty}',
              style: numStyle(context, w: FontWeight.w700))),
          Text(peso(_unitPrice(o, s, it.type) * it.qty),
              style: numStyle(context, w: FontWeight.w700)),
        ]),
      ),
    const SizedBox(height: 5),
    Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(color: p.ice, borderRadius: BorderRadius.circular(14)),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Flexible(
            child: Text('Total', style: tx(context, 20, disp: true, w: FontWeight.w700))),
        const SizedBox(width: 12),
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: Text(peso(o.total),
                style: tx(context, 20, disp: true, w: FontWeight.w700, fontFeatures: numFeatures)),
          ),
        ),
      ]),
    ),
    const SizedBox(height: 10),
    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Ic('pin', size: 20, color: p.ink),
      const SizedBox(width: 10),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(o.address.label, style: tx(context, 15, w: FontWeight.w700)),
        Text(o.address.line, style: tx(context, 13, color: p.muted)),
      ])),
    ]),
    Row(children: [
      Ic('clock', size: 20, color: p.ink),
      const SizedBox(width: 10),
      Expanded(child: Text(timeLabel(o.time), style: tx(context, 15))),
    ]),
    if (o.note.isNotEmpty)
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Ic('pencil', size: 20, color: p.ink),
        const SizedBox(width: 10),
        Expanded(child: Text(o.note, style: tx(context, 15))),
      ]),
    Row(children: [
      Ic('cash', size: 20, color: p.ink),
      const SizedBox(width: 10),
      Expanded(child: Text(o.pay == 'gcash' ? 'GCash on Delivery' : 'Cash on Delivery',
          style: tx(context, 15))),
    ]),
  ]));
}

/* ================= orders ================= */

ScreenView ordersView(BuildContext context, AppState s) {
  final f = s.filter;
  final list = s.myOrders()..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  final filtered = list.where((o) {
    final st = statusState(o);
    return f == 'all' ||
        (f == 'active' && st < 4) ||
        (f == 'delivered' && st == 4) ||
        (f == 'cancelled' && st == 5);
  }).toList();
  return ScreenView(
    content: PadScroll(children: [
      FilterChips(
        items: const [
          SegItem('all', 'All'),
          SegItem('active', 'Active'),
          SegItem('delivered', 'Delivered'),
          SegItem('cancelled', 'Cancelled'),
        ],
        value: f,
        onSelect: (v) {
          s.filter = v;
          s.save();
          s.updateUI();
        },
      ),
      if (filtered.isEmpty)
        const EmptyView('No orders here', msg: 'Orders you place will show up in this list.')
      else
        ...filtered.map((o) => _orderCard(context, s, o)),
    ]),
  );
}

Widget _orderCard(BuildContext context, AppState s, Order o) {
  final p = Pal.of(context);
  final st = statusState(o);
  return AquaCard( child: VGap([
    TapSurface(
      onTap: () {
        s.trackId = o.id;
        s.goScreen('track');
      },
      semanticLabel: 'Order ${o.id}, ${BADGE[st]}',
      semanticButton: false,
      borderRadius: BorderRadius.circular(12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(o.id, style: tx(context, 15, disp: true, w: FontWeight.w700, ls: .4)),
          Text('${dfmt(o.createdAt)} · ${tfmt(o.createdAt)}',
              style: tx(context, 13, color: p.muted)),
        ])),
        OrdBadge(st),
      ]),
    ),
    Row(children: [
      for (final it in o.items) ...[
        Gal(it.type, h: 44),
        const SizedBox(width: 8),
      ],
      Expanded(child: Text(itemsText(o))),
      Text(peso(o.total), style: numStyle(context, w: FontWeight.w700)),
    ]),
    Wrap(spacing: 8, runSpacing: 8, children: [
      // One primary action per order: an active order only needs "Track" (both
      // buttons used to open the same screen), a finished one offers reorder +
      // the full detail sheet.
      if (st < 4)
        Btn('Track', icon: 'pin', iconSize: 18, small: true, onPressed: () {
          s.trackId = o.id;
          s.goScreen('track');
        })
      else ...[
        Btn('Order Again', icon: 'drop', iconSize: 18, small: true,
            onPressed: () => s.reorder(o.id)),
        Btn('Details', kind: BtnKind.alt, small: true, onPressed: () {
          s.trackId = o.id;
          s.goScreen('track');
        }),
      ],
    ]),
  ], gap: 10));
}

/* ================= notifications (all roles) ================= */

ScreenView notifsView(BuildContext context, AppState s) {
  final list = s.notifList();
  final unread = list.where((n) => !n.read).length;
  return ScreenView(
    content: PadScroll(children: [
      if (list.isEmpty)
        const EmptyView('No notifications', msg: 'Order updates will appear here.')
      else ...[
        Row(children: [
          Expanded(child: Text(pl(unread, 'unread update'),
              style: tx(context, 15, color: Pal.of(context).muted))),
          Btn('Mark all read', icon: 'check', iconSize: 18, kind: BtnKind.alt, small: true,
              onPressed: s.markAllRead),
        ]),
        ...list.map((n) => _notifRow(context, s, n)),
      ],
    ]),
  );
}

Widget _notifRow(BuildContext context, AppState s, Notif n) {
  final p = Pal.of(context);
  return TapSurface(
    onTap: () => s.openNotif(n.id, () {}),
    semanticLabel: '${n.title}, ${n.body}',
    semanticButton: false,
    borderRadius: BorderRadius.circular(16),
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        color: n.read ? p.card : p.ice,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: n.read ? p.line : p.ice2),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(width: 40, height: 40,
          decoration: BoxDecoration(color: p.ice2, borderRadius: BorderRadius.circular(12)),
          alignment: Alignment.center,
          child: Ic(n.type == 'order' ? 'truck' : 'bell', size: 22, color: p.link)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(n.title, style: tx(context, 14.5, disp: true, w: FontWeight.w700)),
          Text(n.body, style: tx(context, 13)),
          Text(ago(n.ts), style: tx(context, 13, color: p.muted)),
        ])),
        if (!n.read) ...[
          const SizedBox(width: 8),
          Container(width: 9, height: 9,
              decoration: BoxDecoration(color: p.pip, shape: BoxShape.circle)),
        ],
      ]),
    ),
  );
}

/* ================= profile ================= */

ScreenView profileView(BuildContext context, AppState s) {
  final p = Pal.of(context);
  final u = s.user;
  final addrKids = <Widget>[];
  for (final a in s.addresses) {
    if (addrKids.isNotEmpty) addrKids.add(const SizedBox(height: 14));
    addrKids.add(_addressCard(context, s, a));
  }
  return ScreenView(
    content: PadScroll(children: [
      AquaCard( child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Avatar(initialsOf(u?.name)),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(u?.name ?? '', style: tx(context, 20, disp: true, w: FontWeight.w700)),
            const SizedBox(height: 4),
            Align(alignment: Alignment.centerLeft, child: const Tag('Customer')),
          ])),
          IconAction('pencil', onTap: () => _profileEditSheet(context, s), color: p.link, label: 'Edit profile'),
        ]),
        const SizedBox(height: 12),
        KvList(rows: [
          Row(children: [
            Ic('phone', size: 20, color: p.blue),
            const SizedBox(width: 12),
            Expanded(child: Text(u?.phone.isEmpty ?? true ? 'Add mobile number' : u!.phone,
                style: numStyle(context))),
          ]),
          Row(children: [
            Ic('mail', size: 20, color: p.blue),
            const SizedBox(width: 12),
            Expanded(child: Text(u?.email ?? '', softWrap: true, style: tx(context, 15))),
          ]),
        ]),
      ])),
      Row(children: [
        Expanded(child: SectionHead('Saved Addresses', icon: 'pin')),
        Btn('Add', icon: 'plus', iconSize: 18, small: true,
            onPressed: () => _addressFormSheet(context, s, null, false)),
      ]),
      if (s.addresses.isEmpty)
        AquaCard(
          padding: const EdgeInsets.all(22),
          child: Text('No saved addresses yet. Add one to speed up checkout.',
              textAlign: TextAlign.center, style: para(context, color: p.muted)),
        )
      else
        ...addrKids,
      Btn('Log Out', icon: 'logout', iconSize: 20, kind: BtnKind.alt, onPressed: () {
        _confirmSheet(context,
          title: 'Log out of AQUARUN?',
          msg: 'Your saved addresses and orders stay on this device. Log back in any time.',
          label: 'Log Out',
          onConfirm: () => s.logout());
      }),
    ]),
  );
}

Widget _addressCard(BuildContext context, AppState s, Address a) {
  final p = Pal.of(context);
  return AquaCard( child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Container(width: 40, height: 40,
      decoration: BoxDecoration(color: p.ice, borderRadius: BorderRadius.circular(12)),
      alignment: Alignment.center,
      child: Ic(a.label == 'Work' ? 'box' : (a.label == 'Home' ? 'home' : 'pin'),
          size: 22, color: p.blue)),
    const SizedBox(width: 12),
    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Flexible(child: Text(a.label, style: tx(context, 15, w: FontWeight.w700))),
        if (a.def) ...[const SizedBox(width: 8), const Tag('Default')],
      ]),
      Text(a.line, style: tx(context, 13, color: p.muted)),
      if (a.landmark.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(a.landmark, style: tx(context, 13, color: p.muted)),
        ),
      if (!a.def)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Btn('Set as default', kind: BtnKind.ghost, small: true,
              onPressed: () => s.setAddressDefault(a.id)),
        ),
    ])),
    IconAction('pencil', onTap: () => _addressFormSheet(context, s, a, false), color: p.link, label: 'Edit ${a.label} address'),
    IconAction('trash', onTap: () {
      _confirmSheet(context,
        title: 'Delete address?',
        msg: 'Remove ${a.label} (${a.line}) from your saved addresses?',
        label: 'Delete Address',
        danger: true,
        onConfirm: () => s.deleteAddress(a.id));
    }, color: p.danger, label: 'Delete ${a.label} address'),
  ]));
}

void _profileEditSheet(BuildContext context, AppState s) {
  showAquaSheet(context, title: 'Edit Profile', body: _ProfileForm(s: s));
}

class _ProfileForm extends StatefulWidget {
  final AppState s;
  const _ProfileForm({required this.s});
  @override
  State<_ProfileForm> createState() => _ProfileFormState();
}

class _ProfileFormState extends State<_ProfileForm> {
  late final _name = TextEditingController(text: widget.s.user?.name ?? '');
  late final _phone = TextEditingController(text: widget.s.user?.phone ?? '');
  late final _email = TextEditingController(text: widget.s.user?.email ?? '');
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
    final s = widget.s;
    return VGap([
      AquaField('Full name', _name),
      AquaField('Mobile number', _phone, kbType: TextInputType.phone),
      // The email is the account key (orders, saved addresses and the cloud
      // inbox all hang off it), so it is shown but not editable here.
      AquaField('Email · your sign-in', _email, kbType: TextInputType.emailAddress, readOnly: true),
      ErrLine(_err),
      Btn('Save Changes', onPressed: () {
        final err = s.updateCustomerProfile(
            name: _name.text, email: _email.text, phone: _phone.text);
        if (err == '') {
          Navigator.of(context).pop();
        } else {
          setState(() => _err = err);
        }
      }),
    ]);
  }
}

/* ================= settings ================= */

ScreenView settingsView(BuildContext context, AppState s) {
  final p = Pal.of(context);
  return ScreenView(
    content: PadScroll(children: [
      AquaCard( child: VGap([
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
            s.save();
            s.updateUI();
          },
        ),
      ])),
      AquaCard( child: RowW([
        Expanded(child: VGap([
          Text('Order updates', style: tx(context, 15, w: FontWeight.w700)),
          Text('Get notified when your order status changes.',
              style: tx(context, 13, color: p.muted)),
        ], gap: 2)),
        AquaSwitch(value: s.settings.notify, onChanged: (_) => s.toggleNotify()),
      ], gap: 10)),
      _stationCard(context, s),
      AquaCard( child: RowW([
        Expanded(child: VGap([
          Text('Auto-progress demo orders', style: tx(context, 15, w: FontWeight.w700)),
          Text('When on, new orders move through every stage on their own. Turn it off to run them from the Admin and Rider apps.',
              style: tx(context, 13, color: p.muted)),
        ], gap: 2)),
        AquaSwitch(value: s.settings.autoDeliver, onChanged: (_) => s.toggleAutoDeliver()),
      ], gap: 10)),
      AquaCard( child: VGap([
        SectionHead('Prices'),
        Row(children: [
          Expanded(child: Text('Refill Gallon', style: numStyle(context))),
          Flexible(
              child: Text('${peso(s.priceOf('refill'))} / gallon',
                  textAlign: TextAlign.end, style: numStyle(context, w: FontWeight.w700))),
        ]),
        Row(children: [
          Expanded(child: Text('Buy Gallon', style: numStyle(context))),
          Flexible(
              child: Text('${peso(s.priceOf('buy'))} / gallon',
                  textAlign: TextAlign.end, style: numStyle(context, w: FontWeight.w700))),
        ]),
        Row(children: [
          Expanded(child: Text('Delivery', style: tx(context, 15))),
          Flexible(
              child: Text('Free',
                  textAlign: TextAlign.end, style: numStyle(context, w: FontWeight.w700))),
        ]),
      ], gap: 6)),
      Align(
        alignment: Alignment.center,
        child: Text('AQUARUN · Customer app',
            textAlign: TextAlign.center, style: tx(context, 13, color: p.muted)),
      ),
    ]),
  );
}

/// Business info card, shared design with the rider/admin settings screens.
Widget _stationCard(BuildContext context, AppState s) {
  final p = Pal.of(context);
  final st = s.station;
  return AquaCard( child: VGap([
    Row(children: [
      Ic('store', size: 24, color: p.blue),
      const SizedBox(width: 8),
      Expanded(child: Text(st.name, style: tx(context, 18, disp: true, w: FontWeight.w700))),
    ]),
    Row(children: [
      Ic('clock', size: 18, color: p.ink),
      const SizedBox(width: 10),
      Expanded(child: Text('Open ${hh(st.open)} – ${hh(st.close)}', style: tx(context, 15))),
    ]),
    Row(children: [
      Ic('phone', size: 18, color: p.ink),
      const SizedBox(width: 10),
      Expanded(child: Text(st.phone, style: numStyle(context))),
    ]),
    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Ic('pin', size: 18, color: p.ink),
      const SizedBox(width: 10),
      Expanded(child: Text(st.address, style: tx(context, 15))),
    ]),
    if (!st.accepting) Align(alignment: Alignment.centerLeft, child: OrdBadge(5, label: 'Not taking orders')),
  ], gap: 8));
}
