// Every tab and every tool screen, light and dark, on a phone, an unfolded
// foldable, a tablet and a desktop window, with the largest text the app
// allows: no overflow anywhere. A RenderFlex overflow is reported as an
// exception, which fails the test.
import 'package:dates/main.dart';
import 'package:dates/state/settings.dart';
import 'package:dates/ui/home.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _screens = [
  ('320dp phone', Size(840, 1700), 2.625),
  ('unfolded fold', Size(1500, 2250), 2.5), // 600 x 900 dp
  ('tablet landscape', Size(2560, 1600), 2.0),
  ('desktop window', Size(1280, 800), 1.0),
];

const _tools = ['Between Dates', 'Age', 'Add or Subtract', 'Working Days', 'Weekday', 'Leap Year'];

void main() {
  for (final (where, size, ratio) in _screens) {
    for (final dark in [false, true]) {
      testWidgets('${dark ? 'dark' : 'light'} fits on $where with large text', (t) async {
        t.view.physicalSize = size;
        t.view.devicePixelRatio = ratio;
        t.platformDispatcher.textScaleFactorTestValue = 1.4;
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
        expect(find.byType(TodayTab), findsOneWidget);

        await t.tap(find.bySemanticsLabel('Settings').last);
        await t.pumpAndSettle();
        expect(find.byType(SettingsTab), findsOneWidget);

        await t.tap(find.bySemanticsLabel('Tools').last);
        await t.pumpAndSettle();
        expect(find.byType(ToolsTab), findsOneWidget);

        for (final tool in _tools) {
          final row = find.text(tool).first;
          // Into the middle of the screen, clear of the bars.
          await t.runAsync(() => Scrollable.ensureVisible(t.element(row), alignment: 0.5));
          await t.pumpAndSettle();
          await t.tap(row);
          await t.pumpAndSettle();
          await t.tap(find.bySemanticsLabel('Back'));
          await t.pumpAndSettle();
        }

        // The glass date and time pickers open and close.
        await t.tap(find.text('Between Dates').first);
        await t.pumpAndSettle();
        for (final what in ['Change date', 'Change time']) {
          final field = find.bySemanticsLabel(RegExp(what));
          if (field.evaluate().isEmpty) continue;
          await t.tap(field.first);
          await t.pumpAndSettle();
          expect(find.text('Done'), findsOneWidget);
          await t.tap(find.text('Done'));
          await t.pumpAndSettle();
        }
      });
    }
  }
}
