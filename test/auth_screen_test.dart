/* Guards for the sign-in screens: they must fit a small phone with large text,
 * keep the primary action above the fold, and explain the links they offer. */

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aqua/admin.dart' as adm;
import 'package:aqua/customer.dart' as cus;
import 'package:aqua/main.dart';
import 'package:aqua/rider.dart' as rid;
import 'package:aqua/state.dart';
import 'package:aqua/widgets.dart';

typedef ViewBuilder = ScreenView Function(BuildContext, AppState);

/// Pumps one sign-in screen inside the shell's slot at 320x640.
Future<void> pumpAuth(
  WidgetTester tester,
  ViewBuilder view, {
  String tab = 'login',
  double textScale = 1,
}) async {
  tester.view.physicalSize = const Size(320, 640);
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

  final state = AppState()..authTab = tab;
  await tester.pumpWidget(MaterialApp(
    home: Builder(builder: (context) {
      final sv = view(context, state);
      return Scaffold(
        body: ScreenSlot(
          name: 'auth',
          duration: Duration.zero,
          child: sv.content,
        ),
      );
    }),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('every sign-in screen fits 320dp with 1.3x text', (tester) async {
    final views = <String, ViewBuilder>{
      'customer': cus.authView,
      'rider': rid.authRiderView,
      'admin': adm.authAdminView,
    };
    for (final e in views.entries) {
      for (final tab in ['login', 'register']) {
        // Only the customer screen has a register tab; the other two stay on
        // login even when the flag is set.
        await pumpAuth(tester, e.value, tab: tab, textScale: 1.3);
        expect(tester.takeException(), isNull,
            reason: '${e.key} ($tab) overflowed');
      }
    }
  });

  testWidgets('customer sign-in keeps its primary action above the fold',
      (tester) async {
    await pumpAuth(tester, cus.authView);
    final btn = tester.getRect(find.widgetWithText(Btn, 'Log In'));
    // The old 278dp hero pushed this under the keyboard area on 640dp phones.
    expect(btn.bottom, lessThanOrEqualTo(640));
  });

  testWidgets('register tab fits without scrolling to the field list',
      (tester) async {
    await pumpAuth(tester, cus.authView, tab: 'register');
    expect(find.text('Full name'), findsOneWidget);
    expect(find.text('Mobile number'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('submitting an empty form marks the email field',
      (tester) async {
    await pumpAuth(tester, cus.authView);
    await tester.tap(find.widgetWithText(Btn, 'Log In'));
    await tester.pumpAndSettle();
    expect(find.text('Enter your email address.'), findsOneWidget);
  });

  testWidgets('the staff link opens the role switcher', (tester) async {
    await pumpAuth(tester, cus.authView);
    await tester.tap(find.text('Staff sign-in'));
    await tester.pumpAndSettle();
    expect(find.text('Who is signing in?'), findsOneWidget);
    expect(find.text('Station admin'), findsOneWidget);
  });

  testWidgets('the forgot link explains the manual reset', (tester) async {
    await pumpAuth(tester, cus.authView);
    await tester.tap(find.text('Forgot password?'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Only the station can reset'), findsOneWidget);
  });

  testWidgets('the rider screen explains where accounts come from',
      (tester) async {
    await pumpAuth(tester, rid.authRiderView);
    expect(find.textContaining('created by the station admin'), findsOneWidget);
    // One link to the role chooser, so rider to admin needs no detour through
    // the customer form.
    expect(find.text('Switch account type'), findsOneWidget);
    await tester.tap(find.text('Switch account type'));
    await tester.pumpAndSettle();
    expect(find.text('Station admin'), findsOneWidget);
  });

  testWidgets('the admin screen keeps the demo account filled in',
      (tester) async {
    await pumpAuth(tester, adm.authAdminView);
    expect(find.text('admin@aqua.ph'), findsOneWidget);
    expect(find.textContaining('Demo admin account'), findsOneWidget);
  });
}
