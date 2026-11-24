// The One UI kit's rules (lib/ui/one_ui.dart), each pinned where a test can
// see it without a GPU:
// * the expandable app bar is used only where the guide allows it (p.19);
// * a lifted finger snaps the bar to one state, never in between (p.24);
// * the dark theme is near-black with tonal blocks (p.9);
// * an accent always keeps contrast on its theme (p.86);
// * high contrast gives every surface a visible edge;
// * the tab pill stretches on springs, the new icon pops, a press sinks
//   and springs back; reduced motion makes each of them instant;
// * nothing in the kit blurs or samples the screen (BackdropFilter).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dates/ui/glass_surface.dart';
import 'package:dates/ui/one_ui.dart';

Widget _app(
  Widget child, {
  Brightness b = Brightness.light,
  MediaQueryData? mq,
}) {
  final app = MaterialApp(
    theme: oneUiTheme(b),
    home: Scaffold(body: child),
  );
  return mq == null ? app : MediaQuery(data: mq, child: app);
}

double _luma(Color c) => c.computeLuminance();

double _contrast(Color a, Color b) {
  final l1 = _luma(a), l2 = _luma(b);
  final hi = l1 > l2 ? l1 : l2, lo = l1 > l2 ? l2 : l1;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  group('expandable app bar (guide p.19)', () {
    test('a portrait phone taller than 580dp expands', () {
      expect(oneUiCanExpand(const Size(412, 915)), isTrue);
      expect(oneUiCanExpand(const Size(360, 640)), isTrue);
    });
    test('580dp or shorter never expands', () {
      expect(oneUiCanExpand(const Size(320, 570)), isFalse);
      expect(oneUiCanExpand(const Size(412, 580)), isFalse);
    });
    test('a phone in landscape never expands, a tall window does', () {
      expect(oneUiCanExpand(const Size(915, 412)), isFalse);
      // An unfolded foldable or tablet on its side, taller than 580.
      expect(oneUiCanExpand(const Size(1280, 800)), isTrue);
      // A short multi-window pane on a tablet.
      expect(oneUiCanExpand(const Size(1280, 560)), isFalse);
    });
  });

  group('snap (guide p.24)', () {
    test('half-way goes to the nearer state', () {
      expect(oneUiSnapTarget(40, 300), 0);
      expect(oneUiSnapTarget(149, 300), 0);
      expect(oneUiSnapTarget(151, 300), 300);
      expect(oneUiSnapTarget(299, 300), 300);
    });
    test('the ends and the list below stay where they are', () {
      expect(oneUiSnapTarget(0, 300), 0);
      expect(oneUiSnapTarget(300, 300), 300);
      expect(oneUiSnapTarget(900, 300), 900);
      expect(oneUiSnapTarget(10, 0), 10);
    });
  });

  group('palette', () {
    test('dark is near-black with tonal blocks, light is grey with white', () {
      final d = OnePalette.forBrightness(Brightness.dark);
      expect(_luma(d.background), lessThan(0.002));
      expect(_luma(d.block), greaterThan(_luma(d.background)));
      final l = OnePalette.forBrightness(Brightness.light);
      expect(_luma(l.block), greaterThan(_luma(l.background)));
    });
    test('text keeps 4.5:1 on blocks in both themes', () {
      for (final b in Brightness.values) {
        final p = OnePalette.forBrightness(b);
        expect(_contrast(p.ink, p.block), greaterThan(4.5));
        expect(_contrast(p.sub, p.block), greaterThan(4.5));
      }
    });
    test('any accent keeps 3:1 against the blocks', () {
      for (final accent in const [
        Color(0xFF387AFF),
        Color(0xFF2C2C2E), // graphite
        Color(0xFFFFE8A0), // a pale yellow
        Color(0xFF14A37F),
      ]) {
        for (final b in Brightness.values) {
          final p = OnePalette.forBrightness(b, accent: accent);
          expect(
            _contrast(p.primary, p.block),
            greaterThan(3),
            reason: '$accent on $b',
          );
        }
      }
    });
    test('small primary-coloured text keeps 4.5:1 against the blocks', () {
      for (final accent in const [
        Color(0xFF387AFF),
        Color(0xFFFFE8A0),
        Color(0xFFF08A1D),
        Color(0xFF14A37F),
      ]) {
        for (final b in Brightness.values) {
          final p = OnePalette.forBrightness(b, accent: accent);
          expect(
            _contrast(p.primaryText, p.block),
            greaterThanOrEqualTo(4.5),
            reason: '$accent on $b',
          );
        }
      }
    });
    test('both themes are Material 3', () {
      expect(oneUiTheme(Brightness.light).useMaterial3, isTrue);
      expect(oneUiTheme(Brightness.dark).useMaterial3, isTrue);
      expect(
        oneUiTheme(Brightness.dark).scaffoldBackgroundColor,
        const Color(0xFF010102),
      );
    });
  });

  testWidgets('high contrast puts a visible edge on a surface', (t) async {
    await t.pumpWidget(
      _app(
        const GlassSurface(radius: 26, child: SizedBox(width: 100, height: 40)),
        mq: const MediaQueryData(highContrast: true),
      ),
    );
    final box = t.widget<DecoratedBox>(
      find
          .descendant(
            of: find.byType(GlassSurface),
            matching: find.byType(DecoratedBox),
          )
          .first,
    );
    expect((box.decoration as BoxDecoration).border, isNotNull);
  });

  testWidgets('surfaces are flat: no backdrop filter, no blur', (t) async {
    await t.pumpWidget(
      _app(
        Column(
          children: [
            const GlassSurface(
              radius: 26,
              thick: true,
              child: SizedBox(height: 40),
            ),
            const GlassSurface(radius: 26, child: SizedBox(height: 40)),
            const FocusBlock(
              children: [
                OneListRow(title: 'A'),
                OneListRow(title: 'B'),
              ],
            ),
            OneBottomNav(
              items: const [(Icons.home, 'Home'), (Icons.settings, 'Settings')],
              selected: 0,
              onSelected: (_) {},
            ),
          ],
        ),
      ),
    );
    expect(find.byType(BackdropFilter), findsNothing);
    expect(find.byType(ImageFiltered), findsNothing);
  });

  testWidgets('a focus block divides its rows with inset lines', (t) async {
    await t.pumpWidget(
      _app(
        const SizedBox(
          width: 300,
          child: FocusBlock(
            children: [
              OneListRow(title: 'A'),
              OneListRow(title: 'B'),
            ],
          ),
        ),
      ),
    );
    final line = t.getRect(
      find.byWidgetPredicate(
        (w) =>
            w is ColoredBox &&
            w.child is SizedBox &&
            (w.child as SizedBox).height == 1,
      ),
    );
    final block = t.getRect(find.byType(FocusBlock));
    expect(line.left - block.left, OneUi.blockPadH);
    expect(block.right - line.right, OneUi.blockPadH);
    // Rows meet the 48dp touch target and One UI's row height.
    expect(
      t.getSize(find.byType(OneListRow).first).height,
      greaterThanOrEqualTo(OneUi.rowMinHeight),
    );
  });

  for (final reduce in [false, true]) {
    testWidgets(
      'tab indicator ${reduce ? 'jumps with reduced motion' : 'stretches on a spring'}',
      (t) async {
        var sel = 0;
        await t.pumpWidget(
          StatefulBuilder(
            builder: (context, set) => _app(
              OneBottomNav(
                items: const [
                  (Icons.home, 'Home'),
                  (Icons.star, 'Star'),
                  (Icons.settings, 'Settings'),
                ],
                selected: sel,
                onSelected: (i) => set(() => sel = i),
              ),
              mq: MediaQueryData(
                size: const Size(400, 800),
                disableAnimations: reduce,
              ),
            ),
          ),
        );
        final paint = find.byKey(const ValueKey('one-nav-pill'));
        (double, double) edges() {
          final cp = t.widget<CustomPaint>(
            find.descendant(of: paint, matching: find.byType(CustomPaint)),
          );
          return (cp.painter! as OneNavIndicatorPainter).edges(
            t.getSize(paint).width,
          );
        }

        final (l0, r0) = edges();
        final w0 = r0 - l0;
        // An icon-only item: its label is closed, so tap it by its name.
        await t.tap(find.bySemanticsLabel('Settings'));
        await t.pump();
        await t.pump(const Duration(milliseconds: 60));
        final (lm, rm) = edges();
        var maxRight = rm;
        for (var i = 0; i < 60; i++) {
          await t.pump(const Duration(milliseconds: 16));
          final (_, r) = edges();
          if (r > maxRight) maxRight = r;
        }
        await t.pumpAndSettle();
        final (l1, r1) = edges();
        expect(l1, greaterThan(l0));
        expect(r1 - l1, closeTo(w0, 0.5), reason: 'settles to one tab wide');
        if (reduce) {
          expect((lm, rm), (l1, r1));
        } else {
          // Mid-flight the leading edge has run ahead: the pill stretches.
          expect(rm - lm, greaterThan(w0 + 1));
          expect(lm, inExclusiveRange(l0, l1));
        }
      },
    );
  }

  group('bottom navigation', () {
    const items = [
      (Icons.today_outlined, 'Today'),
      (Icons.grid_view_outlined, 'Tools'),
      (Icons.settings_outlined, 'Settings'),
    ];
    const filled = [
      Icons.today_rounded,
      Icons.grid_view_rounded,
      Icons.settings_rounded,
    ];

    Future<void> pumpNav(
      WidgetTester t, {
      double width = 400,
      double text = 1,
      Brightness b = Brightness.light,
    }) async {
      t.view.physicalSize = Size(width, 800);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      var sel = 0;
      await t.pumpWidget(
        StatefulBuilder(
          builder: (context, set) => _app(
            Align(
              alignment: Alignment.bottomCenter,
              child: OneBottomNav(
                items: items,
                activeIcons: filled,
                selected: sel,
                onSelected: (i) => set(() => sel = i),
              ),
            ),
            b: b,
            mq: MediaQueryData(
              size: Size(width, 800),
              textScaler: TextScaler.linear(text),
            ),
          ),
        ),
      );
    }

    Rect pill(WidgetTester t) {
      final f = find.descendant(
        of: find.byKey(const ValueKey('one-nav-pill')),
        matching: find.byType(CustomPaint),
      );
      final cp = t.widget<CustomPaint>(f);
      final box = t.getRect(f);
      final (l, r) = (cp.painter! as OneNavIndicatorPainter).edges(box.width);
      return Rect.fromLTRB(box.left + l, box.top, box.left + r, box.bottom);
    }

    testWidgets('the active pill holds its label and follows the selection', (
      t,
    ) async {
      await pumpNav(t);
      // Only the selected item shows its label; the others are icon-only.
      expect(find.text('Today'), findsOneWidget);
      expect(find.byIcon(Icons.today_rounded), findsOneWidget, reason: 'filled');
      expect(find.byIcon(Icons.settings_outlined), findsOneWidget);
      final before = pill(t);
      expect(before.contains(t.getCenter(find.byIcon(Icons.today_rounded))), isTrue);

      await t.tap(find.bySemanticsLabel('Settings'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
      final after = pill(t);
      expect(after.left, greaterThan(before.left));
      expect(
        after.contains(t.getCenter(find.byIcon(Icons.settings_rounded))),
        isTrue,
        reason: 'the pill sits under the new item, icon now filled',
      );
      expect(find.byIcon(Icons.today_outlined), findsOneWidget);
      await t.pumpAndSettle();
    });

    for (final b in Brightness.values) {
      testWidgets('no overflow at 320dp with large text ($b)', (t) async {
        await pumpNav(t, width: 320, text: 1.3, b: b);
        for (final to in ['Tools', 'Settings', 'Today']) {
          await t.tap(find.bySemanticsLabel(to));
          for (var i = 0; i < 20; i++) {
            await t.pump(const Duration(milliseconds: 16));
          }
        }
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        final bar = t.getRect(find.byType(OneBottomNav));
        expect(bar.width, lessThanOrEqualTo(320));
      });
    }

    testWidgets('every item is a 48dp target with a label', (t) async {
      final handle = t.ensureSemantics();
      await pumpNav(t, width: 320);
      for (final (_, label) in items) {
        final node = find.bySemanticsLabel(label);
        expect(node, findsOneWidget, reason: label);
        final size = t.getSize(node);
        expect(size.width, greaterThanOrEqualTo(48), reason: label);
        expect(size.height, greaterThanOrEqualTo(48), reason: label);
      }
      // Icon-only items also name themselves in a tooltip.
      expect(find.byType(Tooltip), findsNWidgets(2));
      handle.dispose();
    });

    testWidgets('it is centred at its max width on a tablet', (t) async {
      await pumpNav(t, width: 1000);
      final bar = t.getRect(
        find.descendant(
          of: find.byType(OneBottomNav),
          matching: find.byType(DecoratedBox),
        ).first,
      );
      expect(bar.width, OneBottomNav.maxWidth);
      expect(bar.center.dx, closeTo(500, 0.5));
    });

    testWidgets('reduced motion moves the pill at once', (t) async {
      var sel = 0;
      await t.pumpWidget(
        StatefulBuilder(
          builder: (context, set) => _app(
            OneBottomNav(
              items: items,
              selected: sel,
              onSelected: (i) => set(() => sel = i),
            ),
            mq: const MediaQueryData(
              size: Size(400, 800),
              disableAnimations: true,
            ),
          ),
        ),
      );
      await t.tap(find.bySemanticsLabel('Tools'));
      await t.pump();
      // The pill is already where it settles: nothing travels.
      final first = pill(t);
      expect(first.contains(t.getCenter(find.byIcon(Icons.grid_view_outlined))),
          isTrue);
      await t.pumpAndSettle();
      expect(pill(t), first);
    });
  });

  testWidgets('the newly selected tab icon does not pop', (t) async {
    // The pill's glide and the colour say which tab is on; a bouncing icon
    // read as toy-like.
    var sel = 0;
    await t.pumpWidget(
      StatefulBuilder(
        builder: (context, set) => _app(
          OneBottomNav(
            items: const [(Icons.home, 'Home'), (Icons.star, 'Star')],
            selected: sel,
            onSelected: (i) => set(() => sel = i),
          ),
        ),
      ),
    );
    await t.tap(find.bySemanticsLabel('Star'));
    for (var i = 0; i < 20; i++) {
      await t.pump(const Duration(milliseconds: 16));
      expect(
        find.ancestor(
          of: find.byIcon(Icons.star),
          matching: find.byType(Transform),
        ),
        findsNothing,
      );
    }
    await t.pumpAndSettle();
  });

  for (final reduce in [false, true]) {
    testWidgets(
      'press scale ${reduce ? 'stays still with reduced motion' : 'sinks and comes back without a rebound'}',
      (t) async {
        await t.pumpWidget(
          _app(
            Center(
              child: BriefAction(label: 'Go', onTap: () {}),
            ),
            mq: MediaQueryData(
              size: const Size(400, 800),
              disableAnimations: reduce,
            ),
          ),
        );
        double scale() => t
            .widget<Transform>(
              find
                  .descendant(
                    of: find.byType(OnePressScale),
                    matching: find.byType(Transform),
                  )
                  .first,
            )
            .transform
            .storage[0];
        final g = await t.startGesture(t.getCenter(find.text('Go')));
        await t.pump();
        await t.pump(const Duration(milliseconds: 150));
        expect(scale(), reduce ? 1 : closeTo(0.97, 0.002));
        await g.up();
        var peak = 0.0;
        for (var i = 0; i < 40; i++) {
          await t.pump(const Duration(milliseconds: 16));
          if (scale() > peak) peak = scale();
        }
        expect(peak, lessThanOrEqualTo(1.001), reason: 'no rebound');
        await t.pumpAndSettle();
        expect(scale(), closeTo(1, 0.001));
      },
    );
  }

  testWidgets('a fling back up stops at the bar; only a pull from rest opens '
      'the big title', (t) async {
    // Samsung's own lists: scrolling back up lands on the collapsed bar,
    // where the content began; the big centred title opens only when the
    // page is already resting there and the user pulls down (2026-11-24).
    t.view.physicalSize = const Size(1080, 2400);
    t.view.devicePixelRatio = 2.625;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      MaterialApp(
        theme: oneUiTheme(Brightness.light),
        home: Scaffold(
          body: OneScrollPage(
            title: 'Settings',
            slivers: [
              SliverList.list(
                children: [
                  for (var i = 0; i < 60; i++) OneListRow(title: 'Row $i'),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    final list = find.byType(CustomScrollView);
    final c = t.widget<CustomScrollView>(list).controller!;
    final (min, max) = OneScrollPage.extents(
      t.element(find.byType(OneScrollPage)),
    );
    final range = max - min;
    expect(c.offset, closeTo(range, 0.5));
    // Down into the content, then a hard fling back up: momentum stops at
    // the bar, never runs on into the big title.
    await t.drag(list, const Offset(0, -900));
    await t.pumpAndSettle();
    expect(c.offset, greaterThan(range + 300));
    await t.fling(list, const Offset(0, 600), 6000);
    await t.pumpAndSettle();
    expect(c.offset, closeTo(range, 0.5));
    // One long drag that starts in the content and carries on down also
    // stops at the bar.
    await t.drag(list, const Offset(0, -400));
    await t.pumpAndSettle();
    await t.drag(list, const Offset(0, 1200));
    await t.pumpAndSettle();
    expect(c.offset, closeTo(range, 0.5));
    // Now at rest on the bar, a pull down opens the big title.
    await t.drag(list, const Offset(0, 400));
    await t.pumpAndSettle();
    expect(c.offset, 0);
    expect(
      t
          .widgetList<Text>(find.text('Settings'))
          .any((w) => w.style?.fontSize == OneUi.titleExpanded),
      isTrue,
    );
    // And from the open title, scrolling up collapses it as before.
    await t.drag(list, const Offset(0, -500));
    await t.pumpAndSettle();
    expect(c.offset, greaterThan(range));
  });

  testWidgets('a page opens collapsed; pulling down shows the big title', (
    t,
  ) async {
    t.view.physicalSize = const Size(1080, 2400);
    t.view.devicePixelRatio = 2.625;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      MaterialApp(
        theme: oneUiTheme(Brightness.light),
        home: Scaffold(
          body: OneScrollPage(
            title: 'Settings',
            slivers: [
              SliverList.list(
                children: [
                  for (var i = 0; i < 40; i++) OneListRow(title: 'Row $i'),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    Text title() => t.widget<Text>(find.text('Settings').first);
    // Owner's call: small title at the top left until the user pulls down.
    expect(find.text('Settings'), findsOneWidget);
    expect(title().style!.fontSize, OneUi.titleCollapsed);
    await t.drag(find.byType(CustomScrollView), const Offset(0, 400));
    await t.pumpAndSettle();
    final big = t
        .widgetList<Text>(find.text('Settings'))
        .any((w) => w.style?.fontSize == OneUi.titleExpanded);
    expect(big, isTrue);
  });

  testWidgets('the large title collapses into the bar and snaps', (t) async {
    t.view.physicalSize = const Size(1080, 2400);
    t.view.devicePixelRatio = 2.625;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      MaterialApp(
        theme: oneUiTheme(Brightness.light),
        home: Scaffold(
          body: OneScrollPage(
            title: 'Settings',
            startCollapsed: false,
            slivers: [
              SliverList.list(
                children: [
                  for (var i = 0; i < 40; i++) OneListRow(title: 'Row $i'),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    Text big() => t.widget<Text>(find.text('Settings').first);
    expect(big().style!.fontSize, OneUi.titleExpanded);
    // A short drag that is let go of early springs back open...
    await t.drag(find.byType(CustomScrollView), const Offset(0, -60));
    await t.pumpAndSettle();
    final c = t
        .widget<CustomScrollView>(find.byType(CustomScrollView))
        .controller!;
    expect(c.offset, 0);
    // ...a longer one collapses it fully, never stopping between.
    await t.drag(find.byType(CustomScrollView), const Offset(0, -220));
    await t.pumpAndSettle();
    final (min, max) = OneScrollPage.extents(
      t.element(find.byType(OneScrollPage)),
    );
    expect(c.offset, closeTo(max - min, 0.5));
    // Only the collapsed bar's title is left, at the bar's size.
    expect(find.text('Settings'), findsOneWidget);
    expect(big().style!.fontSize, OneUi.titleCollapsed);
  });

  testWidgets('a short window shows only the collapsed bar', (t) async {
    t.view.physicalSize = const Size(2400, 1080); // phone on its side
    t.view.devicePixelRatio = 2.625;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      MaterialApp(
        theme: oneUiTheme(Brightness.light),
        home: const Scaffold(
          body: OneScrollPage(title: 'Today', slivers: [SliverToBoxAdapter()]),
        ),
      ),
    );
    final (min, max) = OneScrollPage.extents(
      t.element(find.byType(OneScrollPage)),
    );
    expect(max, min);
    expect(find.text('Today'), findsOneWidget);
  });
}
