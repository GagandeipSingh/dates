// Play Store art, step 1 of 2: renders the REAL app screens offscreen.
//
// Skipped in a normal `flutter test`. To regenerate the store images:
//
//   flutter test test/store_art_test.dart --dart-define=STORE_ART=true
//   python tool/store_art.py
//
// This test pumps the app (Inter, Phosphor and Material icon fonts loaded,
// so text and icons draw as themselves rather than test boxes), with
// "today" fixed to Wednesday 28 October 2026 (the Play icon's WED 28), gesture navigation, and writes one PNG per
// screen and device shape to build/store_art/raw/. The script then frames
// each in a device and adds the caption and background.
//
// Odd shots are light and even ones dark, as the store set always was.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:dates/main.dart';
import 'package:dates/state/settings.dart';
import 'package:dates/state/today.dart';
import 'package:dates/ui/glass_surface.dart';
import 'package:dates/ui/kit.dart';
import 'package:dates/ui/tools.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _run = bool.fromEnvironment('STORE_ART');

/// "Today" in every shot.
final _today = DateTime(2026, 10, 28, 9, 41);

/// Device shapes: name, logical size, pixel ratio of the capture.
/// Desktop has no status bar and no system navigation; every other shape is
/// a phone or tablet in gesture navigation (24dp at the foot).
const _devices = [
  ('phone', Size(412, 940), 3.0),
  ('tablet', Size(1280, 800), 1.5),
  ('square', Size(840, 860), 2.5),
  ('desktop', Size(1280, 800), 1.5),
];

/// Each shot's hero card, lifted out of the frame by the script as the old
/// set did: found from a line of text inside it.
const _heroes = {
  '01_today': '64 days left',
  '02_tools': 'days to New Year',
  '03_between': 'Months',
  '04_age': 'Years',
  '05_work': 'F',
  '06_settings': 'Colour',
};

/// The six shots: file stem, tab to open (0 Today, 1 Tools, 2 Settings),
/// tool row to push (if any).
const _shots = [
  ('01_today', 0, null),
  ('02_tools', 1, null),
  ('03_between', 1, 'Between Dates'),
  ('04_age', 1, 'Age'),
  ('05_work', 1, 'Working Days'),
  ('06_settings', 2, null),
];

Future<void> _loadFont(String family, List<String> files) async {
  final loader = FontLoader(family);
  for (final f in files) {
    final bytes = File(f).readAsBytesSync();
    loader.addFont(Future.value(ByteData.sublistView(bytes)));
  }
  await loader.load();
}

String _packageRoot(String name) {
  final config = jsonDecode(
    File('.dart_tool/package_config.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final pkg = (config['packages'] as List)
      .cast<Map<String, dynamic>>()
      .firstWhere((p) => p['name'] == name);
  final uri = Uri.parse(pkg['rootUri'] as String);
  return uri.isAbsolute
      ? uri.toFilePath()
      : File('.dart_tool/${uri.path}').absolute.path;
}

Future<void> _loadFonts() async {
  await _loadFont('Inter', [
    for (final w in [
      'ExtraLight', 'Light', 'Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold',
    ])
      'assets/fonts/Inter-$w.ttf',
  ]);
  final phosphor = '${_packageRoot('phosphor_flutter')}/lib/fonts';
  for (final (family, file) in [
    ('PhosphorFill', 'Phosphor-Fill.ttf'),
    ('PhosphorBold', 'Phosphor-Bold.ttf'),
    ('PhosphorRegular', 'Phosphor.ttf'),
    ('PhosphorLight', 'Phosphor-Light.ttf'),
    ('PhosphorThin', 'Phosphor-Thin.ttf'),
    ('PhosphorDuotone', 'Phosphor-Duotone.ttf'),
  ]) {
    await _loadFont('packages/phosphor_flutter/$family', ['$phosphor/$file']);
  }
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root != null) {
    final icons = File(
      '$root/bin/cache/artifacts/material_fonts/materialicons-regular.otf',
    );
    if (icons.existsSync()) await _loadFont('MaterialIcons', [icons.path]);
  }
}

void main() {
  setUpAll(() async {
    if (_run) await _loadFonts();
  });

  for (final (device, size, ratio) in _devices) {
    for (final (stem, tab, tool) in _shots) {
      final dark = int.parse(stem.substring(0, 2)).isEven;
      testWidgets('store art: $device $stem', skip: !_run, (t) async {
        // Gesture navigation, never 3-button (owner's rule for the store
        // art): a status bar and a 24dp inset at the foot, where the
        // script draws only the thin gesture handle.
        t.view.physicalSize = size * ratio;
        t.view.devicePixelRatio = ratio;
        final inset = device == 'desktop' ? 0.0 : 24 * ratio;
        t.view.padding = FakeViewPadding(top: inset, bottom: inset);
        t.view.viewPadding = FakeViewPadding(top: inset, bottom: inset);
        addTearDown(t.view.reset);
        SharedPreferences.setMockInitialValues({});
        late Settings settings;
        await t.runAsync(() async {
          settings = await Settings.load();
          settings.appearance = dark ? Appearance.dark : Appearance.light;
        });
        final key = GlobalKey();
        await t.pumpWidget(
          RepaintBoundary(
            key: key,
            child: SettingsScope(
              settings: settings,
              child: TodayScope(clock: () => _today, child: const DatesApp()),
            ),
          ),
        );
        await t.pumpAndSettle();

        if (tab != 0) {
          await t.tap(find.bySemanticsLabel(
            RegExp('^${tab == 1 ? 'Tools' : 'Settings'}\$'),
          ).last);
          await t.pumpAndSettle();
        }
        // A tab taller than the screen rests with cards under the floating
        // pills; a store shot shows it scrolled to its end, where every
        // card clears them.
        if (tool == null) {
          final scroll = find.byType(Scrollable);
          if (scroll.evaluate().isNotEmpty) {
            await t.drag(scroll.first, const Offset(0, -3000));
            await t.pumpAndSettle();
          }
        }
        if (tool != null) {
          final row = find.text(tool).first;
          await t.runAsync(
            () => Scrollable.ensureVisible(t.element(row), alignment: 0.5),
          );
          await t.pumpAndSettle();
          await t.tap(row);
          await t.pumpAndSettle();
          // The screens' own "today" reads the wall clock; set the dates
          // the store shots always showed.
          final today = DateTime(2026, 10, 28);
          switch (tool) {
            case 'Between Dates':
              final s = t.state(find.byType(BetweenScreen)) as dynamic;
              s.start = DateTime(2026, 1, 1);
              s.end = today;
              s.setState(() {});
            case 'Age':
              final s = t.state(find.byType(AgeScreen)) as dynamic;
              s.birth = DateTime(2000, 1, 1);
              s.on = today;
              s.setState(() {});
            case 'Working Days':
              final s = t.state(find.byType(WorkingDaysScreen)) as dynamic;
              s.start = DateTime(2026, 10, 1);
              s.end = today;
              s.includeEnd = true;
              s.setState(() {});
          }
          await t.pumpAndSettle();
        }
        expect(t.takeException(), isNull);

        // The hero card's rect, in logical pixels of the capture.
        Rect? hero;
        final text = find.text(_heroes[stem]!);
        if (text.evaluate().isNotEmpty) {
          for (final e in find
              .ancestor(
                of: text.first,
                matching: find.byWidgetPredicate(
                  (w) => w is Pane || w is GlassSurface,
                ),
              )
              .evaluate()) {
            final r = t.getRect(find.byWidget(e.widget).first);
            if (r.width >= size.width * 0.3) {
              hero = r;
              break;
            }
          }
        }

        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        await t.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: ratio);
          final png = await image.toByteData(format: ui.ImageByteFormat.png);
          image.dispose();
          final out = File('build/store_art/raw/${device}_$stem.png');
          out.parent.createSync(recursive: true);
          out.writeAsBytesSync(png!.buffer.asUint8List());
          File('build/store_art/raw/${device}_$stem.json').writeAsStringSync(
            jsonEncode({
              'width': size.width,
              'height': size.height,
              if (hero != null)
                'hero': [hero.left, hero.top, hero.right, hero.bottom],
            }),
          );
        });
      });
    }
  }
}
