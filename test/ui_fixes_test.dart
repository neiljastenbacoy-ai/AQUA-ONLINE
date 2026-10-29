/* Guards for the design-system fixes: contrast of filled controls, the shared
 * interaction primitive, the wide-window frame and dark-mode promo slides. */

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aqua/customer.dart' as cus;
import 'package:aqua/admin.dart' as adm;
import 'package:aqua/main.dart';
import 'package:aqua/models.dart' show Account, Rider;
import 'package:aqua/palette.dart';
import 'package:aqua/rider.dart' as rid;
import 'package:aqua/state.dart';
import 'package:aqua/widgets.dart';

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  test('filled controls keep white labels at AA contrast', () {
    for (final g in [Pal.btnBlue, Pal.btnGreen]) {
      for (final c in g.colors) {
        expect(_contrast(c, Colors.white), greaterThanOrEqualTo(4.5),
            reason: '#${c.toARGB32().toRadixString(16)} vs white');
      }
    }
    expect(_contrast(Pal.light.pip, Colors.white), greaterThanOrEqualTo(4.5));
    expect(_contrast(Pal.light.blue, Colors.white), greaterThanOrEqualTo(4.5));
    expect(_contrast(Pal.dark.blue, Colors.white), greaterThanOrEqualTo(4.5));
  });

  testWidgets('TapSurface taps, focuses and activates from the keyboard',
      (tester) async {
    var taps = 0;
    final node = FocusNode();
    addTearDown(node.dispose);
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: TapSurface(
            focusNode: node,
            onTap: () => taps++,
            semanticLabel: 'Demo action',
            child: const SizedBox(
              width: 120,
              height: 48,
              child: Center(child: Text('hit')),
            ),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('hit'));
    expect(taps, 1);

    node.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(taps, 2);

    // The label owns a semantics container; descendant text is merged into it.
    expect(find.bySemanticsLabel(RegExp('Demo action')), findsWidgets);
    semantics.dispose();
  });

  testWidgets('CheckRow toggles from its label', (tester) async {
    var value = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) => CheckRow(
            value: value,
            onChanged: (v) => setState(() => value = v),
            label: 'Use as my default address',
          ),
        ),
      ),
    ));

    await tester.tap(find.text('Use as my default address'));
    await tester.pump();
    expect(value, isTrue);
  });

  testWidgets('wide windows show the app inside the 440px frame',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    late bool framed;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) {
        framed = framedLayout(context);
        return Scaffold(
          body: phoneFrame(
            context,
            child: const SizedBox.expand(key: Key('frame-inner')),
          ),
        );
      }),
    ));

    expect(framed, isTrue);
    // The frame is 440 wide; a 1px border insets the child by 2.
    final frame = find
        .ancestor(
            of: find.byKey(const Key('frame-inner')),
            matching: find.byType(Container))
        .first;
    expect(tester.getSize(frame).width, kFrameWidth);
    expect(tester.getSize(find.byKey(const Key('frame-inner'))).width,
        kFrameWidth - 2);
  });

  testWidgets('bottom sheets stay inside the frame on wide windows',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showAquaSheet(
              context,
              title: 'Test sheet',
              body: const Text('body'),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final sheet = find
        .ancestor(of: find.text('Test sheet'), matching: find.byType(Container))
        .first;
    expect(tester.getSize(sheet).width, kFrameWidth);
  });

  testWidgets('home promo slides use theme colours in dark mode',
      (tester) async {
    final state = AppState();
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(brightness: Brightness.dark),
      home: Builder(
        builder: (context) =>
            Scaffold(body: cus.homeView(context, state).content),
      ),
    ));
    await tester.pump();

    final gradients = tester
        .widgetList<Container>(find.byType(Container))
        .map((c) => c.decoration)
        .whereType<BoxDecoration>()
        .map((d) => d.gradient)
        .whereType<LinearGradient>()
        .map((g) => g.colors);
    // The promo card paints with ice/ice2 of the *current* palette, so the dark
    // palette colours must show up somewhere in the tree.
    expect(gradients.any((c) => c.contains(Pal.dark.ice)), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('short screens stay pinned under the app bar', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final state = AppState();

    for (final view in [rid.rhistoryView, cus.cartView, cus.notifsView]) {
      late ScreenView sv;
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (context) {
          sv = view(context, state);
          return Scaffold(
            body: Column(children: [
              const SizedBox(height: 60, width: double.infinity),
              Expanded(
                child: ScreenSlot(
                  name: 'scan',
                  duration: Duration.zero,
                  child: sv.content,
                ),
              ),
            ]),
          );
        }),
      ));
      await tester.pump();
      final top = tester.getRect(find.byWidget(sv.content)).top;
      // A centred slot floated these to the middle of the page.
      expect(top, 60, reason: 'content must start right under the app bar');
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('screens do not overflow at 320dp with 1.3x text',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    final views = <String, ScreenView Function(BuildContext, AppState)>{
      'home': cus.homeView,
      'order': cus.orderView,
      'cart': cus.cartView,
      'checkout': cus.checkoutView,
      'confirm': cus.confirmView,
      'track': cus.trackView,
      'orders': cus.ordersView,
      'notifs': cus.notifsView,
      'profile': cus.profileView,
      'settings': cus.settingsView,
      'rdash': rid.rdashView,
      'rlist': rid.rlistView,
      'rdetail': rid.rdetailView,
      'rhistory': rid.rhistoryView,
      'rearn': rid.rearnView,
      'adash': adm.adashView,
      'aorders': adm.aordersView,
      'adeliv': adm.adelivView,
      'aprod': adm.aprodView,
      'ainv': adm.ainvView,
      'ausers': adm.ausersView,
      'areports': adm.areportsView,
    };

    for (final e in views.entries) {
      final state = AppState()
        ..session = true
        ..role = e.key.startsWith('r')
            ? 'rider'
            : (e.key.startsWith('a') ? 'admin' : 'customer')
        ..user = Account(name: 'Maria', email: 'maria@example.com');
      state.rider = Rider(id: 'R1', name: 'Rico', email: 'rico@example.com');
      state.admin = Account(name: 'Admin', email: 'admin@example.com');

      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) {
            final sv = e.value(context, state);
            return Scaffold(
              // Mirrors the shell: content fills the stage, the dock sits under
              // it. Scanning only the content missed dock overflows.
              body: Column(children: [
                Expanded(child: sv.content),
                if (sv.dock != null)
                  Container(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [sv.dock!],
                    ),
                  ),
              ]),
            );
          },
        ),
      ));
      await tester.pump();
      expect(tester.takeException(), isNull, reason: '${e.key} overflowed');
    }
  });
}
