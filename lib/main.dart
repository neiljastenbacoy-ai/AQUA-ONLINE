import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'art.dart';
import 'constants.dart';
import 'firebase_boot.dart';
import 'icons.dart';
import 'notify.dart';
import 'palette.dart';
import 'state.dart';
import 'widgets.dart';

import 'customer.dart' as cus;
import 'rider.dart' as rid;
import 'admin.dart' as adm;

late final AppState appState;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  appState = AppState();
  // Register both Google fonts up front so the raw fontFamily references in
  // tx() ('Poppins' headings, 'Nunito Sans' body) resolve to the real fonts.
  GoogleFonts.poppins();
  GoogleFonts.nunitoSans();
  // Real system notifications (Android status bar / heads-up).
  PhoneNotify.init();
  // Don't block first frame on Firebase — it finishes in the background and
  // the tracking layer activates when ready.
  unawaited(bootFirebase());
  runApp(const AquaApp());
}

class AquaApp extends StatefulWidget {
  const AquaApp({super.key});
  @override
  State<AquaApp> createState() => _AquaAppState();
}

class _AquaAppState extends State<AquaApp> {
  late final Timer _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => appState.tick());
  }

  @override
  void dispose() {
    _tick.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: appState,
      builder: (context, _) {
        final theme = appState.settings.theme;
        return MaterialApp(
          title: 'AQUA Water Ordering',
          debugShowCheckedModeBanner: false,
          themeMode: theme == 'light'
              ? ThemeMode.light
              : (theme == 'dark' ? ThemeMode.dark : ThemeMode.system),
          theme: _theme(Brightness.light),
          darkTheme: _theme(Brightness.dark),
          home: RootShell(),
        );
      },
    );
  }

  ThemeData _theme(Brightness b) {
    final dark = b == Brightness.dark;
    return ThemeData(
      useMaterial3: true,
      brightness: b,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF0A3A8A),
        brightness: b,
      ),
      scaffoldBackgroundColor: dark ? Pal.dark.stage : Pal.light.stage,
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      splashColor: Colors.transparent,
      textTheme:
          GoogleFonts.nunitoSansTextTheme(
            ThemeData(brightness: b, useMaterial3: true).textTheme,
          ).apply(
            bodyColor: dark ? Pal.dark.ink : Pal.light.ink,
            displayColor: dark ? Pal.dark.ink : Pal.light.ink,
          ),
    );
  }
}

/* ================= root shell ================= */

class RootShell extends StatefulWidget {
  const RootShell({super.key});
  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  bool sideOpen = false;
  String toastText = '';
  bool toastVisible = false;
  Timer? _toastTimer;

  @override
  void initState() {
    super.initState();
    appState.onToast = _showToast;
    // Keep the splash visible briefly, but route only after saved state loads.
    Future.wait<void>([
      appState.init(),
      Future<void>.delayed(const Duration(milliseconds: 1100)),
    ]).then((_) {
      if (!mounted) return;
      if (appState.screen == 'splash') {
        if (appState.session) {
          appState.goScreen(appState.homeOf(), fresh: true);
        } else {
          appState.goScreen('auth', fresh: true);
        }
      }
    });
  }

  void _showToast(String msg) {
    if (!mounted) return;
    setState(() {
      toastText = msg;
      toastVisible = true;
    });
    _toastTimer?.cancel();
    _toastTimer = Timer(const Duration(milliseconds: 2400), () {
      if (mounted) setState(() => toastVisible = false);
    });
  }

  void _openSide() {
    setState(() => sideOpen = true);
  }

  void _closeSide() {
    if (sideOpen) setState(() => sideOpen = false);
  }

  ScreenView _screenView(BuildContext context, String name) {
    if (name == 'splash') return cus.splashView(context, appState);
    if (name == 'auth') {
      if (appState.authRole == 'admin')
        return adm.authAdminView(context, appState);
      if (appState.authRole == 'rider')
        return rid.authRiderView(context, appState);
      return cus.authView(context, appState);
    }
    switch (name) {
      // customer
      case 'home':
        return cus.homeView(context, appState);
      case 'order':
        return cus.orderView(context, appState);
      case 'cart':
        return cus.cartView(context, appState);
      case 'checkout':
        return cus.checkoutView(context, appState);
      case 'confirm':
        return cus.confirmView(context, appState);
      case 'track':
        return cus.trackView(context, appState);
      case 'orders':
        return cus.ordersView(context, appState);
      case 'notifs':
        return cus.notifsView(context, appState);
      case 'profile':
        return appState.role == 'admin'
            ? adm.adminProfileView(context, appState)
            : appState.role == 'rider'
            ? rid.riderProfileView(context, appState)
            : cus.profileView(context, appState);
      case 'settings':
        return appState.role == 'admin'
            ? adm.adminSettingsView(context, appState)
            : appState.role == 'rider'
            ? rid.riderSettingsView(context, appState)
            : cus.settingsView(context, appState);
      // rider
      case 'rdash':
        return rid.rdashView(context, appState);
      case 'rlist':
        return rid.rlistView(context, appState);
      case 'rdetail':
        return rid.rdetailView(context, appState);
      case 'rroute':
        return rid.rrouteView(context, appState);
      case 'rhistory':
        return rid.rhistoryView(context, appState);
      case 'rearn':
        return rid.rearnView(context, appState);
      // admin
      case 'adash':
        return adm.adashView(context, appState);
      case 'aorders':
        return adm.aordersView(context, appState);
      case 'adetail':
        return adm.adetailView(context, appState);
      case 'adeliv':
        return adm.adelivView(context, appState);
      case 'aprod':
        return adm.aprodView(context, appState);
      case 'ainv':
        return adm.ainvView(context, appState);
      case 'ausers':
        return adm.ausersView(context, appState);
      case 'areports':
        return adm.areportsView(context, appState);
    }
    return ScreenView(
      content: PadScroll(
        children: [
          EmptyView(
            'Page unavailable',
            msg: 'This page could not be opened. Return to your home screen to continue.',
            action: Btn(
              'Go to Home',
              onPressed: () =>
                  appState.goScreen(appState.homeOf(), fresh: true),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final name = appState.screen;
    final sv = _screenView(context, name);
    final stage = MediaQuery.of(context).size;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    Widget app = Column(
      children: [
        if (!sv.bare) _appBar(context, name),
        Expanded(
          child: AnimatedSwitcher(
            duration: reduceMotion ? Duration.zero : screenTransitionDuration,
            reverseDuration: reduceMotion
                ? Duration.zero
                : screenTransitionDuration,
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, animation) {
              final position =
                  Tween<Offset>(
                    begin: const Offset(0.025, 0),
                    end: Offset.zero,
                  ).animate(
                    CurvedAnimation(
                      parent: animation,
                      curve: Curves.easeOutCubic,
                      reverseCurve: Curves.easeInCubic,
                    ),
                  );
              return FadeTransition(
                opacity: animation,
                child: SlideTransition(position: position, child: child),
              );
            },
            child: KeyedSubtree(
              key: ValueKey('screen-$name-${sv.content.runtimeType}'),
              child: sv.content,
            ),
          ),
        ),
        if (sv.dock != null) ...[
          Container(
            decoration: BoxDecoration(
              color: p.card,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.07),
                  offset: const Offset(0, -8),
                  blurRadius: 20,
                ),
              ],
            ),
            padding: EdgeInsets.fromLTRB(
              16,
              12,
              16,
              12 + MediaQuery.of(context).padding.bottom * 0.0,
            ),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [sv.dock!],
              ),
            ),
          ),
        ],
      ],
    );

    // On wide screens: centered phone frame like the web preview. Height is
    // capped so tall windows don't stretch the app into a skinny column of
    // blank space.
    if (stage.width >= 520) {
      app = Center(
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 14),
          width: 440,
          constraints: const BoxConstraints(maxHeight: 900),
          decoration: BoxDecoration(
            color: p.bg,
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: p.line),
            boxShadow: const [
              BoxShadow(
                color: Color(0x47102A64),
                offset: Offset(0, 20),
                blurRadius: 60,
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: app,
        ),
      );
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (sideOpen) return _closeSide();
        if (appState.stack.length > 1 || appState.screen != appState.homeOf()) {
          appState.back();
        }
      },
      child: Scaffold(
        backgroundColor: p.stage,
        body: Stack(
          children: [
            Positioned.fill(
              child: SafeArea(top: false, bottom: false, child: app),
            ),
            if (sideOpen) ..._sideOverlay(),
            // toast
            Positioned(
              left: 0,
              right: 0,
              bottom: 90,
              child: IgnorePointer(
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 150),
                  opacity: toastVisible ? 1 : 0,
                  child: Center(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 30),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 11,
                      ),
                      constraints: const BoxConstraints(maxWidth: 400),
                      decoration: BoxDecoration(
                        color: p.ink,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x40000000),
                            offset: Offset(0, 8),
                            blurRadius: 20,
                          ),
                        ],
                      ),
                      child: Text(
                        toastText,
                        textAlign: TextAlign.center,
                        style: tx(context, 14, w: FontWeight.w700, color: p.bg),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /* ---------------- app bar ---------------- */

  Widget _appBar(BuildContext context, String name) {
    final p = Pal.of(context);
    final c = cartCountSafe();
    final n = unreadSafe();
    final isRoot = ROOT.contains(name);
    final mid = (name == 'home' || name == 'rdash' || name == 'adash')
        ? AquaLogo(color: Colors.white)
        : Text(
            TITLES[name] ?? '',
            style: tx(
              context,
              19,
              disp: true,
              w: FontWeight.w600,
              color: Colors.white,
              ls: 0.2,
            ),
          );
    final right = <Widget>[];
    if (name != 'confirm') {
      if (appState.role == 'customer' && name != 'cart') {
        right.add(
          _iconBtn(
            context,
            'cart',
            24,
            c > 0 ? c.toString() : null,
            'Cart',
            () {
              appState.goScreen('cart');
            },
          ),
        );
      }
      right.add(
        _iconBtn(
          context,
          'bell',
          24,
          n > 0 ? n.toString() : null,
          'Notifications',
          () {
            appState.goScreen('notifs');
          },
        ),
      );
    }
    return Container(
      color: p.navy,
      child: SafeArea(
        bottom: false,
        child: Container(
          constraints: const BoxConstraints(minHeight: 60),
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 44,
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.only(left: 8),
                child: _iconBtn2(
                  context,
                  isRoot ? 'menu' : 'back',
                  26,
                  isRoot ? _openSide : appState.back,
                ),
              ),
              Expanded(child: Center(child: mid)),
              // right icons
              Row(
                children: [for (final r in right) r, const SizedBox(width: 8)],
              ),
            ],
          ),
        ),
      ),
    );
  }

  int cartCountSafe() {
    try {
      return appState.cartCount();
    } catch (_) {
      return 0;
    }
  }

  int unreadSafe() {
    try {
      return appState.unread();
    } catch (_) {
      return 0;
    }
  }

  Widget _iconBtn(
    BuildContext context,
    String icon,
    double size,
    String? pip,
    String label,
    VoidCallback onTap,
  ) {
    final p = Pal.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        alignment: Alignment.center,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Ic(icon, size: size, color: Colors.white),
            if (pip != null)
              Positioned(
                top: -5,
                right: -4,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  height: 18,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: p.pip,
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(color: p.navy, width: 2),
                  ),
                  child: Text(
                    pip,
                    style: tx(
                      context,
                      11,
                      w: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _iconBtn2(
    BuildContext context,
    String icon,
    double size,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        alignment: Alignment.center,
        child: Ic(icon, size: size, color: Colors.white),
      ),
    );
  }

  /* ---------------- sidebar ---------------- */

  List<Widget> _sideOverlay() {
    if (!sideOpen) return const [];
    final p = Pal.of(context);
    final wide = MediaQuery.of(context).size.width >= 520;
    Widget layer = Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            onTap: _closeSide,
            child: Container(color: p.scrim),
          ),
        ),
        Positioned.fill(
          child: Align(
            alignment: Alignment.centerLeft,
            child: SafeArea(
              child: SidePanel(
                s: appState,
                onClose: _closeSide,
                onSelect: (v) {
                  if (v == 'logout-ask') {
                    _closeSide();
                    confirmLogoutSheet(context);
                    return;
                  }
                  if (v == 'order')
                    appState.draft.type = appState.draft.type.isEmpty
                        ? 'refill'
                        : appState.draft.type;
                  _closeSide();
                  appState.goScreen(v, side: true);
                  appState.save();
                },
              ),
            ),
          ),
        ),
      ],
    );
    // On wide screens keep the drawer inside the phone frame instead of
    // sliding from the far edge of the window.
    if (wide) {
      layer = Center(
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 14),
          width: 440,
          constraints: const BoxConstraints(maxHeight: 900),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(30),
          ),
          child: layer,
        ),
      );
    }
    return [Positioned.fill(child: layer)];
  }
}

/* shared confirm sheet used by sidebar logout + more */
Future<void> confirmLogoutSheet(BuildContext context) async {
  final s = appState;
  await showAquaSheet(
    context,
    title: 'Log out of AQUA?',
    body: VGap(
      [
        Text(
          'Your saved addresses and orders stay on this device. Log back in any time.',
          style: para(context, color: Pal.of(context).muted),
        ),
        const SizedBox(height: 2),
        Btn(
          'Log Out',
          kind: BtnKind.primary,
          onPressed: () {
            Navigator.of(context).pop();
            s.logout();
          },
        ),
        Btn(
          'Keep it',
          kind: BtnKind.alt,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
      gap: 10,
      crossStart: false,
    ),
  );
}
