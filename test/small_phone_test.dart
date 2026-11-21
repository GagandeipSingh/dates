// The field reports from a small, older phone (360 x 640 dp, a 24 dp status
// bar and 3-button navigation), each pinned so it cannot come back:
// * nothing overflows, in light or dark, at the largest text the app allows;
// * the top bar sits BELOW the status bar, never pressed up under it;
// * the "Copied" toast appears at the top, clear of Android's own clipboard
//   pill at the bottom of the screen;
// * a segment highlight never leaves its track, even mid-spring.
import 'package:dates/main.dart';
import 'package:dates/state/settings.dart';
import 'package:dates/ui/glass_surface.dart';
import 'package:dates/ui/kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _phones = [
  // name, physical size, ratio, status bar dp, nav bar dp
  ('360x640 phone, 3-button nav', Size(720, 1280), 2.0, 24.0, 48.0),
  ('320x570 phone, 3-button nav', Size(640, 1140), 2.0, 24.0, 48.0),
  ('412x915 phone, gesture nav', Size(1080, 2400), 2.625, 32.0, 16.0),
];

const _tools = ['Between Dates', 'Age', 'Add or Subtract', 'Working Days', 'Weekday', 'Leap Year'];

Future<void> _start(WidgetTester t, Size size, double ratio, double statusDp, double navDp,
    {required bool dark, double text = 1.0}) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = ratio;
  t.view.padding = FakeViewPadding(top: statusDp * ratio, bottom: navDp * ratio);
  t.view.viewPadding = FakeViewPadding(top: statusDp * ratio, bottom: navDp * ratio);
  t.platformDispatcher.textScaleFactorTestValue = text;
  addTearDown(t.view.reset);
  addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
  SharedPreferences.setMockInitialValues({});
  late Settings settings;
  await t.runAsync(() async {
    settings = await Settings.load();
    settings.appearance = dark ? Appearance.dark : Appearance.light;
  });
  await t.pumpWidget(SettingsScope(settings: settings, child: const DatesApp()));
  await t.pumpAndSettle();
}

/// Where the status bar ends, in the same (global, logical) coordinates the
/// finder reports.
double _statusBottom(WidgetTester t, double statusDp, double ratio) =>
    statusDp * ratio / t.view.devicePixelRatio;

void main() {
  for (final (where, size, ratio, statusDp, navDp) in _phones) {
    for (final dark in [false, true]) {
      final mode = dark ? 'dark' : 'light';

      testWidgets('$mode: every screen fits on $where at large text', (t) async {
        await _start(t, size, ratio, statusDp, navDp, dark: dark, text: 1.25);
        for (final tab in ['Settings', 'Tools']) {
          await t.tap(find.bySemanticsLabel(tab).last);
          await t.pumpAndSettle();
        }
        for (final tool in _tools) {
          final row = find.text(tool).first;
          await t.runAsync(() => Scrollable.ensureVisible(t.element(row), alignment: 0.5));
          await t.pumpAndSettle();
          await t.tap(row);
          await t.pumpAndSettle();
          await t.tap(find.bySemanticsLabel('Back'));
          await t.pumpAndSettle();
        }
      });

      testWidgets('$mode: titles sit below the status bar on $where', (t) async {
        await _start(t, size, ratio, statusDp, navDp, dark: dark);
        final statusBottom = _statusBottom(t, statusDp, ratio);
        for (final tab in ['Today', 'Tools', 'Settings']) {
          await t.tap(find.bySemanticsLabel(tab).last);
          await t.pumpAndSettle();
          // The bar's glass runs up under the status bar on purpose; its
          // TITLE must sit clear of it, with room to breathe.
          final title = t.getRect(find.descendant(
              of: find.byType(GlassAppBar).first, matching: find.text(tab)).first);
          expect(title.top - statusBottom, greaterThanOrEqualTo(6),
              reason: '$tab title has breathing room under the status bar');
        }
        // A pushed tool screen has the same header spacing.
        await t.tap(find.bySemanticsLabel('Tools').last);
        await t.pumpAndSettle();
        await t.tap(find.text('Add or Subtract').first);
        await t.pumpAndSettle();
        final back = t.getRect(find.bySemanticsLabel('Back').first);
        expect(back.top - statusBottom, greaterThanOrEqualTo(4),
            reason: 'back button is clear of the status bar');
      });

      testWidgets('$mode: the nav buttons get their own strip on $where', (t) async {
        await _start(t, size, ratio, statusDp, navDp, dark: dark);
        for (final tab in ['Today', 'Tools', 'Settings']) {
          await t.tap(find.bySemanticsLabel(tab).last);
          await t.pumpAndSettle();
          final strip = find.descendant(
              of: find.byType(NavButtonBacking), matching: find.byType(GlassSurface));
          if (navDp >= NavButtonBacking.threeButtonMinDp) {
            // 3-button: the buttons sit on the app's liquid glass, never on
            // raw content.
            expect(strip, findsOneWidget, reason: '$tab has a glass strip');
            final screen = t.view.physicalSize / t.view.devicePixelRatio;
            final r = t.getRect(strip);
            expect(r.bottom, closeTo(screen.height, 0.5), reason: '$tab strip at the bottom');
            expect(r.height, closeTo(navDp, 0.5), reason: '$tab strip covers the buttons');
            expect(r.width, closeTo(screen.width, 0.5));
          } else {
            // Gesture nav: content runs to the edge under the handle.
            expect(strip, findsNothing, reason: '$tab has no glass under a gesture bar');
          }
        }
      });

      testWidgets('$mode: "Copied" shows at the top on $where', (t) async {
        final copied = <String>[];
        t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform,
            (call) async {
          if (call.method == 'Clipboard.setData') copied.add('${call.arguments}');
          return null;
        });
        addTearDown(() => t.binding.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null));
        await _start(t, size, ratio, statusDp, navDp, dark: dark);
        await t.tap(find.bySemanticsLabel('Tools').last);
        await t.pumpAndSettle();
        await t.tap(find.text('Between Dates').first);
        await t.pumpAndSettle();
        await t.tap(find.bySemanticsLabel('Copy').last);
        for (var i = 0; i < 12; i++) {
          await t.pump(const Duration(milliseconds: 100));
        }
        expect(copied, isNotEmpty);
        final toast = t.getRect(find.text('Copied'));
        final screen = t.view.physicalSize / t.view.devicePixelRatio;
        expect(toast.top, greaterThanOrEqualTo(_statusBottom(t, statusDp, ratio)),
            reason: 'clear of the status bar');
        expect(toast.center.dy, lessThan(screen.height / 3),
            reason: "in the top third, away from Android's own clipboard pill");
        // ...and below the page's own header, never on its title or back button.
        final pill = t.getRect(find.ancestor(
                of: find.text('Copied'), matching: find.byType(GlassSurface))
            .first);
        for (final header in [
          find.bySemanticsLabel('Back').first,
          find.descendant(of: find.byType(GlassAppBar).first, matching: find.text('Between Dates')).first,
        ]) {
          expect(pill.overlaps(t.getRect(header)), isFalse,
              reason: 'the toast must not cover the page header');
        }
        await t.pump(const Duration(seconds: 7));
        await t.pumpAndSettle();
        expect(find.text('Copied'), findsNothing);
      });
    }
  }

  testWidgets('a segment highlight never leaves its track mid-spring', (t) async {
    await _start(t, const Size(720, 1280), 2.0, 24, 48, dark: true);
    await t.tap(find.bySemanticsLabel('Settings').last);
    await t.pumpAndSettle();
    final track = t.getRect(find.byType(Segments<Appearance>));
    Rect pill() => t.getRect(find.descendant(
        of: find.byType(Segments<Appearance>), matching: find.byType(SelectionPill)));
    for (final to in ['Dark', 'System', 'Light', 'Dark', 'System']) {
      await t.tap(find.descendant(of: find.byType(Segments<Appearance>), matching: find.text(to)));
      for (var i = 0; i < 40; i++) {
        await t.pump(const Duration(milliseconds: 16));
        final r = pill();
        expect(r.left, greaterThanOrEqualTo(track.left - 0.5), reason: 'toward $to, frame $i');
        expect(r.right, lessThanOrEqualTo(track.right + 0.5), reason: 'toward $to, frame $i');
      }
      await t.pumpAndSettle();
    }
  });

  testWidgets('the tab bar highlight never leaves the bar mid-spring', (t) async {
    await _start(t, const Size(720, 1280), 2.0, 24, 48, dark: false);
    final pills = find.byType(SelectionPill);
    Rect bar() => t.getRect(find.ancestor(of: pills.first, matching: find.byType(Stack)).first);
    for (final to in ['Settings', 'Today', 'Settings', 'Today']) {
      await t.tap(find.bySemanticsLabel(to).last);
      for (var i = 0; i < 40; i++) {
        await t.pump(const Duration(milliseconds: 16));
        final r = t.getRect(pills.first);
        final b = bar();
        expect(r.left, greaterThanOrEqualTo(b.left - 0.5), reason: 'toward $to, frame $i');
        expect(r.right, lessThanOrEqualTo(b.right + 0.5), reason: 'toward $to, frame $i');
      }
      await t.pumpAndSettle();
    }
  });
}
