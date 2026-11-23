// The app's motion (lib/ui/motion.dart, page_motion.dart and their call
// sites), each rule where a test can see it:
// * the everyday springs are tight: kSnap passes its mark by at most ~1%,
//   kSettle not visibly at all, and both end exactly on 1;
// * every sheet, dialog and route goes through the app's own helpers, so
//   nothing is left on a default transition (a grep over lib/), and every
//   pushed screen is an AppPageRoute moving on shared axis X;
// * a staggered arrival plays once, 30ms a step for at most 6 steps, and
//   not at all with reduced motion;
// * a figure counts to its new value, never past it, and lands on it;
// * the tabs fade through quickly and keep their state;
// * a press sinks in 90ms and comes back without a rebound.
import 'dart:io';
import 'dart:math' as math;

import 'package:dates/ui/kit.dart';
import 'package:dates/ui/page_motion.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child, {bool reduce = false}) => MediaQuery(
  data: MediaQueryData(size: const Size(400, 800), disableAnimations: reduce),
  child: MaterialApp(home: Scaffold(body: child)),
);

double _sx(WidgetTester t, Finder f) =>
    t.widget<Transform>(f).transform.storage[0];
double _ty(WidgetTester t, Finder f) =>
    t.widget<Transform>(f).transform.storage[13];
double _op(WidgetTester t, String text) => t
    .widget<Opacity>(
      find.ancestor(of: find.text(text), matching: find.byType(Opacity)).first,
    )
    .opacity;

void main() {
  group('springs', () {
    double peak(Curve c) {
      var m = 0.0;
      for (var i = 0; i <= 400; i++) {
        final v = c.transform(i / 400);
        if (v > m) m = v;
      }
      return m;
    }

    test('kSnap is tight: at most ~1% past the mark, ends on it', () {
      expect(peak(kSnap), inInclusiveRange(1.0, 1.02));
      expect(kSnap.transform(1), 1);
      expect(kSnapMs, inInclusiveRange(320, 400));
      // Quick off the mark: most of the way there in the first third.
      expect(kSnap.transform(1 / 3), greaterThan(0.8));
    });

    test('kSettle (big surfaces) never visibly overshoots', () {
      expect(peak(kSettle), lessThanOrEqualTo(1.005));
      expect(kSettle.transform(1), 1);
      expect(kSettleMs, 400);
    });

    test('the physics twin of kSnap rests in kSnapMs', () {
      final sim = SpringSimulation(kSnapSpring, 0, 1, 0);
      var m = 0.0;
      for (var ms = 0; ms <= kSnapMs; ms += 4) {
        m = math.max(m, sim.x(ms / 1000));
      }
      expect(m, lessThanOrEqualTo(1.02));
      expect(sim.x(kSnapMs / 1000), closeTo(1, 0.005));
    });

    test('fades are short and never overshoot', () {
      expect(kFadeMs, inInclusiveRange(150, 200));
      for (var i = 0; i <= 100; i++) {
        expect(kFade.transform(i / 100), lessThanOrEqualTo(1));
      }
    });

    testWidgets('reduced motion gives zero duration', (t) async {
      late Duration d;
      await t.pumpWidget(
        _host(
          Builder(
            builder: (c) {
              d = motion(c, kSnapMs);
              return const SizedBox();
            },
          ),
          reduce: true,
        ),
      );
      expect(d, Duration.zero);
    });
  });

  group('coverage', () {
    // Raw presenters and routes are allowed only inside the helpers that
    // give them the app's motion.
    final allowed = {
      'showModalBottomSheet': ['lib/ui/glass_chrome.dart'],
      'showDialog': <String>[],
      'showGeneralDialog': <String>[],
      'showCupertinoModalPopup': <String>[],
      'showMenu': <String>[],
      'MaterialPageRoute': <String>[],
      'PageRouteBuilder': <String>[],
      'CupertinoPageRoute': <String>[],
      'CupertinoPageTransitionsBuilder': <String>[],
      'ZoomPageTransitionsBuilder': <String>[],
      'FadeUpwardsPageTransitionsBuilder': <String>[],
      'OpenUpwardsPageTransitionsBuilder': <String>[],
    };

    test('no raw sheet, dialog or route outside the motion helpers', () {
      final files = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'));
      final bad = <String>[];
      for (final f in files) {
        final path = f.path.replaceAll('\\', '/');
        final code = f
            .readAsLinesSync()
            .where((l) => !l.trimLeft().startsWith('//'))
            .join('\n');
        for (final e in allowed.entries) {
          if (RegExp('\\b${e.key}\\s*[<(]').hasMatch(code) &&
              !e.value.contains(path)) {
            bad.add('$path uses ${e.key}');
          }
        }
      }
      expect(bad, isEmpty);
    });

    test('every pushed route is the app route', () {
      final files = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'));
      var pushes = 0;
      for (final f in files) {
        final code = f.readAsStringSync();
        for (final m in RegExp(
          r'\.push(?:Replacement)?\(\s*([A-Za-z]+)',
          multiLine: true,
        ).allMatches(code)) {
          pushes++;
          expect(m[1], 'AppPageRoute', reason: f.path);
        }
        for (final m in RegExp(r'onGenerateRoute:[^\n]*').allMatches(code)) {
          expect(m[0], contains('AppPageRoute'), reason: f.path);
        }
      }
      expect(pushes, greaterThan(0));
    });
  });

  group('routes', () {
    test('the bouncy springs are gone from lib/', () {
      final bad = <String>[];
      for (final f in Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))) {
        final code = f.readAsStringSync();
        for (final name in [
          'kSpring',
          'kSpringSoft',
          'PopOnSelect',
          'PressGlow',
        ]) {
          if (RegExp(r'\b' '$name' r'\b').hasMatch(code)) {
            bad.add('${f.path}: $name');
          }
        }
      }
      expect(bad, isEmpty);
    });

    testWidgets('a push is shared axis X and back mirrors it', (t) async {
      final nav = GlobalKey<NavigatorState>();
      await t.pumpWidget(
        MaterialApp(
          navigatorKey: nav,
          theme: ThemeData(
            pageTransitionsTheme: const PageTransitionsTheme(
              builders: {
                TargetPlatform.android: AppPageTransitionsBuilder(),
              },
            ),
          ),
          // As in the app: home is an AppPageRoute too.
          onGenerateRoute: (_) =>
              AppPageRoute(builder: (_) => const Scaffold(body: Text('home'))),
        ),
      );
      nav.currentState!.push(
        AppPageRoute(builder: (_) => const Scaffold(body: Text('next'))),
      );
      await t.pump();
      await t.pump(const Duration(milliseconds: 60));
      double dx(String s) => t
          .widget<Transform>(
            find.ancestor(of: find.text(s), matching: find.byType(Transform)).first,
          )
          .transform
          .storage[12];
      double op(String s) => t
          .widget<Opacity>(
            find.ancestor(of: find.text(s), matching: find.byType(Opacity)).first,
          )
          .opacity;
      // In from the right, a few dp, fading in; the old screen drifts left.
      expect(dx('next'), inExclusiveRange(0, pageShift));
      expect(op('next'), inExclusiveRange(0, 1));
      expect(dx('home'), inExclusiveRange(-pageShift, 0));
      await t.pump(const Duration(milliseconds: pageMs));
      expect(dx('next'), 0);
      expect(op('next'), 1);
      expect(ModalRoute.of(t.element(find.text('next'))), isA<AppPageRoute>());

      nav.currentState!.pop();
      await t.pump();
      await t.pump(const Duration(milliseconds: 60));
      expect(dx('next'), inExclusiveRange(0, pageShift), reason: 'back out right');
      expect(dx('home'), inExclusiveRange(-pageShift, 0));
      await t.pumpAndSettle();
      expect(find.text('next'), findsNothing);
      expect(dx('home'), 0);
    });

    testWidgets('with reduced motion a push simply appears', (t) async {
      final nav = GlobalKey<NavigatorState>();
      await t.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: MaterialApp(
            navigatorKey: nav,
            home: const Scaffold(body: Text('home')),
          ),
        ),
      );
      nav.currentState!.push(
        AppPageRoute(builder: (_) => const Scaffold(body: Text('next'))),
      );
      await t.pump();
      await t.pump();
      expect(t.hasRunningAnimations, isFalse);
      expect(find.text('next'), findsOneWidget);
    });
  });

  group('StaggerIn', () {
    for (final reduce in [false, true]) {
      testWidgets(
        'arrives once${reduce ? ', instantly with reduced motion' : ''}',
        (t) async {
          await t.pumpWidget(
            _host(
              const Column(
                children: [
                  StaggerIn(index: 0, child: Text('a')),
                  StaggerIn(index: 3, child: Text('b')),
                ],
              ),
              reduce: reduce,
            ),
          );
          final b = find.ancestor(
            of: find.text('b'),
            matching: find.byType(Transform),
          );
          if (reduce) {
            expect(b, findsNothing);
            return;
          }
          await t.pump(const Duration(milliseconds: 60));
          // The later item has not started: still low and invisible.
          expect(_ty(t, b.first), greaterThan(10));
          await t.pumpAndSettle();
          expect(_ty(t, b.first), 0, reason: 'settled in place');
          expect(_op(t, 'b'), 1);
          // A rebuild never replays it.
          await t.pumpWidget(
            _host(
              const Column(
                children: [
                  StaggerIn(index: 0, child: Text('a')),
                  StaggerIn(index: 3, child: Text('b!')),
                ],
              ),
            ),
          );
          await t.pump(const Duration(milliseconds: 16));
          final b2 = find.ancestor(
            of: find.text('b!'),
            matching: find.byType(Transform),
          );
          expect(_ty(t, b2.first), 0, reason: 'a rebuild never replays it');
          expect(_op(t, 'b!'), 1);
          expect(t.hasRunningAnimations, isFalse);
        },
      );
    }

    testWidgets('steps 30ms an item and stops at the 6th', (t) async {
      await t.pumpWidget(
        _host(
          Column(
            children: [
              for (final i in [0, 1, 6, 12])
                StaggerIn(index: i, child: Text('i$i')),
            ],
          ),
        ),
      );
      double ty(String s) => _ty(
        t,
        find.ancestor(of: find.text(s), matching: find.byType(Transform)).first,
      );
      await t.pump(const Duration(milliseconds: 20));
      expect(ty('i0'), lessThan(14), reason: 'the first starts at once');
      expect(ty('i1'), 14, reason: 'the second waits 30ms');
      await t.pump(const Duration(milliseconds: 150));
      // Index 6 and 12 both start at 6 x 30 = 180ms: the cap.
      expect(ty('i6'), 14);
      expect(ty('i12'), 14);
      await t.pump(const Duration(milliseconds: 60));
      expect(ty('i6'), lessThan(14));
      expect(ty('i12'), ty('i6'));
      // All in place 180 + kSnapMs after the start.
      await t.pump(const Duration(milliseconds: kSnapMs));
      expect(ty('i12'), 0);
      expect(t.hasRunningAnimations, isFalse);
    });

    testWidgets('the content is tappable from the first frame', (t) async {
      var taps = 0;
      await t.pumpWidget(
        _host(
          StaggerIn(
            index: 5,
            child: TextButton(onPressed: () => taps++, child: const Text('go')),
          ),
        ),
      );
      await t.tap(find.text('go'), warnIfMissed: false);
      expect(taps, 1);
    });
  });

  group('CountText', () {
    testWidgets('counts up to the new value, never past it', (t) async {
      Widget at(String s) => _host(Center(child: CountText(s)));
      await t.pumpWidget(at('1,000 days'));
      expect(find.text('1,000 days'), findsOneWidget);
      await t.pumpWidget(at('2,000 days'));
      await t.pump(const Duration(milliseconds: 100));
      final mid = t.widget<Text>(find.byType(Text)).data!;
      final v = int.parse(mid.split(' ').first.replaceAll(',', ''));
      expect(v, inExclusiveRange(1000, 2000));
      expect(mid, endsWith(' days'));
      var max = v;
      for (var i = 0; i < 30; i++) {
        await t.pump(const Duration(milliseconds: 16));
        final s = t.widget<Text>(find.byType(Text)).data!;
        final x = int.parse(s.split(' ').first.replaceAll(',', ''));
        if (x > max) max = x;
      }
      expect(max, lessThanOrEqualTo(2000));
      await t.pumpAndSettle();
      expect(find.text('2,000 days'), findsOneWidget);
    });

    testWidgets('lands exactly on the target in kCountMs', (t) async {
      Widget at(String s) => _host(Center(child: CountText(s)));
      await t.pumpWidget(at('38'));
      await t.pumpWidget(at('412'));
      await t.pump();
      await t.pump(const Duration(milliseconds: kCountMs ~/ 3));
      final early = int.parse(t.widget<Text>(find.byType(Text)).data!);
      // Ease-out: well past halfway a third of the way in.
      expect(early, greaterThan(38 + (412 - 38) ~/ 2));
      await t.pump(const Duration(milliseconds: kCountMs));
      expect(find.text('412'), findsOneWidget);
      expect(t.hasRunningAnimations, isFalse);
    });

    testWidgets('a new value mid-count carries on from the shown one', (
      t,
    ) async {
      Widget at(String s) => _host(Center(child: CountText(s)));
      await t.pumpWidget(at('0'));
      await t.pumpWidget(at('1000'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 100));
      final shown = int.parse(t.widget<Text>(find.byType(Text)).data!);
      await t.pumpWidget(at('500'));
      await t.pump();
      final next = int.parse(t.widget<Text>(find.byType(Text)).data!);
      expect((next - shown).abs(), lessThan(60), reason: 'no jump');
      await t.pumpAndSettle();
      expect(find.text('500'), findsOneWidget);
    });

    testWidgets('a figure that appears after its screen rises in once', (
      t,
    ) async {
      var show = false;
      late StateSetter set;
      await t.pumpWidget(
        _host(
          StaggerScope(
            child: StatefulBuilder(
              builder: (c, s) {
                set = s;
                return Column(
                  children: [
                    const CountText('7 days'),
                    if (show) const CountText('12 hours'),
                  ],
                );
              },
            ),
          ),
        ),
      );
      // Part of the screen's arrival: no rise of its own.
      expect(
        find.ancestor(of: find.text('7 days'), matching: find.byType(Opacity)),
        findsNothing,
      );
      // Past the arrival window, on either clock the scope might read.
      await t.pump(StaggerScope.window);
      await t.runAsync(
        () => Future<void>.delayed(
          StaggerScope.window + const Duration(milliseconds: 50),
        ),
      );
      set(() => show = true);
      await t.pump();
      await t.pump(const Duration(milliseconds: 40));
      final rising = find.ancestor(
        of: find.text('12 hours'),
        matching: find.byType(Transform),
      );
      expect(_ty(t, rising.first), inExclusiveRange(0, CountText.rise));
      await t.pumpAndSettle();
      expect(_ty(t, rising.first), 0);
      expect(find.text('12 hours'), findsOneWidget);
    });

    testWidgets('jumps with reduced motion', (t) async {
      Widget at(String s) => _host(Center(child: CountText(s)), reduce: true);
      await t.pumpWidget(at('5'));
      await t.pumpWidget(at('90'));
      await t.pump();
      expect(find.text('90'), findsOneWidget);
    });

    testWidgets('a date rolls instead of counting', (t) async {
      Widget at(String s) => _host(Center(child: CountText(s)));
      await t.pumpWidget(at('3 March 2025'));
      await t.pumpWidget(at('17 March 2025'));
      await t.pump(const Duration(milliseconds: 60));
      // Both leaves are on screen mid-roll; nothing in between is shown.
      expect(find.text('3 March 2025'), findsOneWidget);
      expect(find.text('17 March 2025'), findsOneWidget);
      await t.pumpAndSettle();
      expect(find.text('3 March 2025'), findsNothing);
    });
  });

  group('FadeThroughTabs', () {
    testWidgets('fades through and keeps each tab alive', (t) async {
      var tab = 0;
      late StateSetter set;
      await t.pumpWidget(
        _host(
          StatefulBuilder(
            builder: (c, s) {
              set = s;
              return FadeThroughTabs(
                index: tab,
                count: 2,
                builder: (c, i) => ListView(
                  key: PageStorageKey('list$i'),
                  children: [
                    for (var k = 0; k < 60; k++)
                      SizedBox(height: 50, child: Text('t$i-$k')),
                  ],
                ),
              );
            },
          ),
        ),
      );
      await t.drag(find.byType(ListView), const Offset(0, -500));
      await t.pumpAndSettle();
      expect(find.text('t0-0'), findsNothing);

      set(() => tab = 1);
      await t.pump();
      await t.pump(const Duration(milliseconds: 120));
      // Mid-switch: the new tab is partly faded in and slightly small.
      final op = t.widget<Opacity>(
        find
            .ancestor(of: find.text('t1-0'), matching: find.byType(Opacity))
            .first,
      );
      expect(op.opacity, inExclusiveRange(0.0, 1.0));
      await t.pumpAndSettle();
      expect(find.text('t1-0'), findsOneWidget);

      set(() => tab = 0);
      await t.pump();
      await t.pump(const Duration(milliseconds: FadeThroughTabs.ms));
      expect(
        t
            .widget<Opacity>(
              find
                  .ancestor(of: find.text('t0-12'), matching: find.byType(Opacity))
                  .first,
            )
            .opacity,
        1,
        reason: 'done in 220ms',
      );
      expect(find.text('t0-0'), findsNothing, reason: 'scroll position kept');
    });
  });

  group('press', () {
    for (final reduce in [false, true]) {
      testWidgets(
        'GlassPress ${reduce ? 'stays still with reduced motion' : 'sinks in 90ms and comes back without a rebound'}',
        (t) async {
          await t.pumpWidget(
            _host(
              Center(
                child: GlassPress(
                  onTap: () {},
                  label: 'x',
                  child: const SizedBox(width: 100, height: 60),
                ),
              ),
              reduce: reduce,
            ),
          );
          final tr = find.descendant(
            of: find.byType(GlassPress),
            matching: find.byType(Transform),
          );
          final g = await t.startGesture(t.getCenter(find.byType(GlassPress)));
          await t.pump();
          await t.pump(const Duration(milliseconds: kPressMs));
          expect(_sx(t, tr.first), reduce ? 1 : closeTo(kPressScale, 0.003));
          await g.up();
          var peak = 0.0;
          for (var i = 0; i < 30; i++) {
            await t.pump(const Duration(milliseconds: 16));
            peak = math.max(peak, _sx(t, tr.first));
          }
          expect(peak, lessThanOrEqualTo(1.001), reason: 'no rebound');
          expect(_sx(t, tr.first), closeTo(1, 0.001), reason: 'back in ~400ms');
          await t.pumpAndSettle();
        },
      );
    }

    testWidgets('a press that turns into a scroll lets go', (t) async {
      await t.pumpWidget(
        _host(
          const Center(
            child: PressScale(child: SizedBox(width: 100, height: 60)),
          ),
        ),
      );
      final tr = find.descendant(
        of: find.byType(PressScale),
        matching: find.byType(Transform),
      );
      final g = await t.startGesture(t.getCenter(find.byType(PressScale)));
      await t.pump();
      await t.pump(const Duration(milliseconds: 120));
      expect(_sx(t, tr.first), lessThan(0.98));
      await g.moveBy(const Offset(0, 40));
      await t.pumpAndSettle();
      expect(_sx(t, tr.first), closeTo(1, 0.001));
      await g.up();
    });
  });

  group('FillOnce', () {
    setUp(FillOnce.reset);

    testWidgets('fills from empty the first time, not the second', (t) async {
      final seen = <double>[];
      Widget at(Key k) => _host(
        FillOnce(
          key: k,
          id: 'ring',
          value: 0.5,
          builder: (c, v) {
            seen.add(v);
            return const SizedBox();
          },
        ),
      );
      await t.pumpWidget(at(const ValueKey(1)));
      expect(seen.first, 0);
      await t.pump(const Duration(milliseconds: kFillMs ~/ 2));
      expect(seen.last, inExclusiveRange(0.25, 0.5), reason: 'ease-out');
      await t.pump(const Duration(milliseconds: kFillMs ~/ 2));
      expect(seen.last, 0.5, reason: 'full in kFillMs');
      await t.pumpAndSettle();
      expect(seen.last, 0.5);
      expect(seen.every((v) => v <= 0.5), isTrue, reason: 'never past it');
      seen.clear();
      await t.pumpWidget(at(const ValueKey(2)));
      expect(seen.first, 0.5, reason: 'already filled this run');
    });
  });
}
