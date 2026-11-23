// The field reports from a small, older phone (360 x 640 dp, a 24 dp status
// bar and 3-button navigation), each pinned so it cannot come back:
// * nothing overflows, in light or dark, at the largest text the app allows;
// * the top bar sits BELOW the status bar, never pressed up under it;
// * the "Copied" toast appears at the top, clear of Android's own clipboard
//   pill at the bottom of the screen;
// * a segment highlight never leaves its track, even mid-glide;
// * the date dock's split pills float above the system navigation, each a
//   48dp named target, the open one a wide pill showing its whole label,
//   following the selection on a spring (at once with reduced motion).
import 'package:dates/main.dart';
import 'package:dates/state/settings.dart';
import 'package:dates/ui/date_dock.dart';
import 'package:dates/ui/glass_surface.dart';
import 'package:dates/ui/kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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

/// A dock item by its label (Today announces the full date after it).
Finder _dock(String label) =>
    find.bySemanticsLabel(RegExp('^${RegExp.escape(label)}(,|\$)')).last;

void main() {
  for (final (where, size, ratio, statusDp, navDp) in _phones) {
    for (final dark in [false, true]) {
      final mode = dark ? 'dark' : 'light';

      testWidgets('$mode: every screen fits on $where at large text', (t) async {
        await _start(t, size, ratio, statusDp, navDp, dark: dark, text: 1.25);
        for (final tab in ['Settings', 'Tools']) {
          await t.tap(_dock(tab));
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
          await t.tap(_dock(tab));
          await t.pumpAndSettle();
          // The app bar runs up under the status bar on purpose; its
          // TITLE (expanded or collapsed) must sit clear of it.
          final titles = find.descendant(
              of: find.byType(OneScrollPage), matching: find.text(tab));
          expect(titles, findsWidgets);
          for (final e in titles.evaluate()) {
            final title = t.getRect(find.byWidget(e.widget));
            expect(title.top - statusBottom, greaterThanOrEqualTo(6),
                reason: '$tab title has breathing room under the status bar');
          }
        }
        // A pushed tool screen has the same header spacing.
        await t.tap(_dock('Tools'));
        await t.pumpAndSettle();
        await t.tap(find.text('Add or Subtract').first);
        await t.pumpAndSettle();
        final back = t.getRect(find.bySemanticsLabel('Back').first);
        // Its 48dp target sits centred in One UI's 56dp bar, so a few dp of
        // the target's own padding is the gap (before the app's scaling).
        expect(back.top - statusBottom, greaterThanOrEqualTo(3),
            reason: 'back button is clear of the status bar');
      });

      testWidgets('$mode: the dock pills float above the nav buttons on $where', (t) async {
        await _start(t, size, ratio, statusDp, navDp, dark: dark);
        final handle = t.ensureSemantics();
        final screen = t.view.physicalSize / t.view.devicePixelRatio;
        for (final (tab, label) in _dockTabs) {
          await t.tap(_dock(label));
          await t.pumpAndSettle();
          expect(t.takeException(), isNull, reason: 'nothing overflows on $label');
          final open = _shape(t, tab);
          for (final (other, otherLabel) in _dockTabs) {
            final r = _shape(t, other);
            // Above the system navigation, never under its buttons.
            expect(r.bottom, lessThanOrEqualTo(screen.height - navDp + 0.5),
                reason: '$otherLabel sits above the nav inset');
            expect(r.left, greaterThanOrEqualTo(0));
            expect(r.right, lessThanOrEqualTo(screen.width));
            // A 48dp target, named for screen readers.
            final node = _dock(otherLabel);
            expect(t.getSize(node).width, greaterThanOrEqualTo(48), reason: otherLabel);
            expect(t.getSize(node).height, greaterThanOrEqualTo(48), reason: otherLabel);
            if (other != tab) {
              // A closed item is a round button, narrower than the open pill.
              expect(r.width, closeTo(r.height, 0.5), reason: '$otherLabel is round');
              expect(open.width, greaterThan(r.width + 20));
            }
          }
          _expectOpenLabel(t, tab, label);
          // Nothing is painted behind the floating pills.
          expect(find.byType(NavButtonBacking), findsNothing);
        }
        handle.dispose();
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
        await t.tap(_dock('Tools'));
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
          find.descendant(of: find.byType(OneScrollPage).last, matching: find.text('Between Dates')).first,
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

  for (final reduce in [false, true]) {
    testWidgets(
        'the open pill follows the selection${reduce ? ' at once with reduced motion' : ' on a spring'}',
        (t) async {
      if (reduce) {
        t.platformDispatcher.accessibilityFeaturesTestValue =
            const FakeAccessibilityFeatures(disableAnimations: true);
        addTearDown(t.platformDispatcher.clearAccessibilityFeaturesTestValue);
      }
      await _start(t, const Size(720, 1280), 2.0, 24, 48, dark: false);
      final round = _shape(t, 1).width;
      final wide = _shape(t, 0).width;
      expect(wide, greaterThan(round + 20), reason: 'Today opens as the pill');
      for (final (tab, label) in [(2, 'Settings'), (1, 'Tools'), (0, 'Today'), (2, 'Settings')]) {
        final from = _dockTabs.firstWhere((e) => _shape(t, e.$1).width > round + 1).$1;
        await t.tap(_dock(label));
        await t.pump();
        await t.pump(const Duration(milliseconds: 60));
        final mid = _shape(t, tab).width;
        if (reduce) {
          // Instant: already at its open width, the old one already round.
          expect(mid, greaterThan(round + 20), reason: '$label is open at once');
          expect(_shape(t, from).width, closeTo(round, 0.5));
          expect(_labelOpacity(t, label), 1.0);
        }
        await t.pumpAndSettle();
        if (!reduce) {
          // Mid-flight it was widening on its spring: past round, not there yet.
          expect(mid, inExclusiveRange(round + 0.5, _shape(t, tab).width - 0.5),
              reason: '$label was widening');
        }
        _expectOpenLabel(t, tab, label);
        expect(_shape(t, from).width, closeTo(round, 0.5),
            reason: 'the old pill is round again');
      }
    });
  }
}

/// The dock tabs, in their visual order: (tab index, label).
const _dockTabs = [(0, 'Today'), (1, 'Tools'), (2, 'Settings')];

/// A dock shape's rect, by tab index.
Rect _shape(WidgetTester t, int tab) =>
    t.getRect(find.byKey(ValueKey('dock-$tab')));

/// The open item's label in the dock, or null when it is not painted.
Finder _dockLabel(String label) => find.descendant(
    of: find.byType(DateDock), matching: find.text(label));

double _labelOpacity(WidgetTester t, String label) => t
    .widget<Opacity>(find.ancestor(of: _dockLabel(label), matching: find.byType(Opacity)).first)
    .opacity;

/// Only the open item shows its label, whole, inside its pill, unscaled.
void _expectOpenLabel(WidgetTester t, int tab, String label) {
  for (final (_, other) in _dockTabs) {
    expect(_dockLabel(other), other == label ? findsOneWidget : findsNothing,
        reason: other == label ? '$label shows its label' : '$other is icon-only');
  }
  final text = _dockLabel(label);
  final para = t.renderObject<RenderParagraph>(text);
  expect(para.didExceedMaxLines, isFalse, reason: '$label is not cut');
  final r = t.getRect(text);
  final pill = _shape(t, tab);
  expect(r.left, greaterThanOrEqualTo(pill.left));
  expect(r.right, lessThanOrEqualTo(pill.right), reason: '$label fits its pill');
  // Laid out at its natural width (the FittedBox did not have to shrink it).
  final natural = para.getMaxIntrinsicWidth(double.infinity);
  expect(r.width, closeTo(natural * _globalScale(t), 1.0),
      reason: '$label is drawn at full size');
  expect(_labelOpacity(t, label), 1.0);
}

/// How much the app's ScaleToWidth shrinks or grows its tree on this screen.
double _globalScale(WidgetTester t) {
  final box = t.renderObject<RenderBox>(find.byType(DateDock));
  return t.getRect(find.byType(DateDock)).width / box.size.width;
}
