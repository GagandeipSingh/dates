// A visual audit of every Dates screen at every device size, light and
// dark. Skipped in a normal `flutter test`; run it with
//
//   flutter test test/ui_audit_test.dart --dart-define=UI_AUDIT=true
//
// and look at build/ui_audit/: one PNG per screen (top and scrolled to the
// end), per sheet, per size and theme, plus report.txt listing every line
// of text that was cut (ellipsized or clipped). Overflow fails the test.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:dates/main.dart';
import 'package:dates/state/settings.dart';
import 'package:dates/state/today.dart';
import 'package:dates/ui/update_prompt.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _run = bool.fromEnvironment('UI_AUDIT');

// name, logical size, status bar dp, bottom (gesture) inset dp
const _sizes = [
  ('phone', Size(412, 915), 32.0, 24.0),
  ('small_phone', Size(360, 640), 24.0, 24.0),
  ('folded', Size(374, 840), 32.0, 24.0),
  ('tablet7', Size(600, 960), 24.0, 24.0),
  ('unfolded', Size(840, 860), 24.0, 24.0),
  ('tablet10', Size(1280, 800), 24.0, 24.0),
  ('desktop', Size(1280, 720), 0.0, 0.0),
];

const _tools = [
  'Between Dates',
  'Age',
  'Add or Subtract',
  'Working Days',
  'Weekday',
  'Leap Year',
];

Future<void> _loadFont(String family, List<String> files) async {
  final loader = FontLoader(family);
  for (final f in files) {
    loader.addFont(Future.value(ByteData.sublistView(File(f).readAsBytesSync())));
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

final _report = StringBuffer();

void main() {
  setUpAll(() async {
    if (_run) await _loadFonts();
  });
  tearDownAll(() {
    if (!_run) return;
    final f = File('build/ui_audit/report.txt')..createSync(recursive: true);
    f.writeAsStringSync(_report.toString());
  });

  for (final (name, size, status, bottom) in _sizes) {
    for (final dark in [false, true]) {
      final theme = dark ? 'dark' : 'light';
      testWidgets('audit $name $theme', skip: !_run, (t) async {
        const ratio = 2.0;
        t.view.physicalSize = size * ratio;
        t.view.devicePixelRatio = ratio;
        t.view.padding = FakeViewPadding(top: status * ratio, bottom: bottom * ratio);
        t.view.viewPadding = FakeViewPadding(top: status * ratio, bottom: bottom * ratio);
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
              child: TodayScope(
                clock: () => DateTime(2026, 11, 18, 9, 41),
                child: const DatesApp(),
              ),
            ),
          ),
        );
        await t.pumpAndSettle();
        var n = 0;
        final dir = 'build/ui_audit/${name}_$theme';

        Future<void> shoot(String what) async {
          await t.pumpAndSettle();
          expect(t.takeException(), isNull, reason: '$name $theme $what');
          // Every line of text that did not fit.
          for (final e in find.byType(RichText).evaluate()) {
            final rp = e.renderObject;
            if (rp is! RenderParagraph || !rp.hasSize) continue;
            final text = rp.text.toPlainText();
            final single = rp.maxLines == 1 || !rp.softWrap;
            final cut = rp.didExceedMaxLines ||
                (single &&
                    rp.getMaxIntrinsicWidth(double.infinity) >
                        rp.size.width + 0.5);
            if (cut && text.trim().isNotEmpty) {
              _report.writeln('$name $theme $what: "$text" '
                  '(${rp.size.width.toStringAsFixed(1)} wide, needs '
                  '${rp.getMaxIntrinsicWidth(double.infinity).toStringAsFixed(1)})');
            }
          }
          final boundary =
              key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final label = '${(++n).toString().padLeft(2, '0')}_$what';
          await t.runAsync(() async {
            final image = await boundary.toImage(pixelRatio: size.width > 700 ? 1 : 1.5);
            final png = await image.toByteData(format: ui.ImageByteFormat.png);
            image.dispose();
            final out = File('$dir/$label.png')..createSync(recursive: true);
            out.writeAsBytesSync(png!.buffer.asUint8List());
          });
        }

        Future<void> toEnd() async {
          for (final e in find.byType(Scrollable).evaluate()) {
            final s = (e as StatefulElement).state as ScrollableState;
            if (s.position.axis == Axis.vertical &&
                s.position.maxScrollExtent > 0) {
              s.position.jumpTo(s.position.maxScrollExtent);
            }
          }
          await t.pumpAndSettle();
        }

        Future<void> tab(String label) async {
          await t.tap(find.bySemanticsLabel(RegExp('^$label(,|\$)')).last);
          await t.pumpAndSettle();
        }

        // How far each tab runs past the window at rest (under the dock).
        void overrun(String tab) {
          for (final e in find.byType(Scrollable).evaluate()) {
            final s = (e as StatefulElement).state as ScrollableState;
            if (s.position.axis == Axis.vertical &&
                s.position.maxScrollExtent > 0.5) {
              _report.writeln('$name $theme $tab: runs '
                  '${s.position.maxScrollExtent.toStringAsFixed(0)}dp past the window '
                  '(view ${s.position.viewportDimension.toStringAsFixed(0)})');
            }
          }
        }

        overrun('today');
        await shoot('today');
        await toEnd();
        await shoot('today_end');
        await tab('Settings');
        overrun('settings');
        await shoot('settings');
        await toEnd();
        await shoot('settings_end');
        await tab('Tools');
        overrun('tools');
        await shoot('tools');
        await toEnd();
        await shoot('tools_end');

        for (final tool in _tools) {
          final row = find.text(tool).first;
          await t.runAsync(
            () => Scrollable.ensureVisible(t.element(row), alignment: 0.5),
          );
          await t.pumpAndSettle();
          await t.tap(row);
          await t.pumpAndSettle();
          final slug = tool.toLowerCase().replaceAll(' ', '_');
          await shoot(slug);
          await toEnd();
          await shoot('${slug}_end');
          if (tool == 'Between Dates') {
            // The date sheet, then the time sheet (with time switched on).
            final date = find.bySemanticsLabel(RegExp('Change date')).first;
            await t.runAsync(
              () => Scrollable.ensureVisible(t.element(date), alignment: 0.3),
            );
            await t.pumpAndSettle();
            await t.tap(date);
            await shoot('sheet_date');
            await t.tap(find.text('Done'));
            await t.pumpAndSettle();
            final time = find.text('Include time');
            if (time.evaluate().isNotEmpty) {
              await t.runAsync(
                () => Scrollable.ensureVisible(t.element(time.first), alignment: 0.3),
              );
              await t.pumpAndSettle();
              await t.tap(time.first);
              await t.pumpAndSettle();
              await shoot('between_with_time');
              final f = find.bySemanticsLabel(RegExp('Change time'));
              if (f.evaluate().isNotEmpty) {
                await t.runAsync(
                  () => Scrollable.ensureVisible(t.element(f.first), alignment: 0.3),
                );
                await t.pumpAndSettle();
                await t.tap(f.first);
                await shoot('sheet_time');
                await t.tap(find.text('Done'));
                await t.pumpAndSettle();
              }
            }
          }
          await t.tap(find.bySemanticsLabel('Back').first);
          await t.pumpAndSettle();
        }

        // The update-ready sheet.
        final ctx = DatesApp.navigatorKey.currentContext!;
        showUpdateReady(ctx);
        await shoot('sheet_update');
      });
    }
  }
}
