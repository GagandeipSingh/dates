// The "Daily date icon" switch in Settings: Android only, seeded from
// native (which owns the value), and every flip sent to native.
import 'package:dates/main.dart';
import 'package:dates/state/settings.dart';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _label = 'Daily date icon';
const _hint = 'Off: fixed icon, keeps app pairs';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late bool nativeValue;
  late List<MethodCall> calls;

  // The app's real face, so the one-line check measures real glyphs (the
  // test font draws every glyph a full em wide).
  setUpAll(() async {
    final loader = FontLoader('Inter')
      ..addFont(
        File('assets/fonts/Inter-Regular.ttf')
            .readAsBytes()
            .then((b) => ByteData.sublistView(b)),
      );
    await loader.load();
  });

  setUp(() {
    nativeValue = false; // Native says OFF: Dart must show that, not its default.
    calls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(dateIconChannel, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'getDailyIcon':
          return nativeValue;
        case 'setDailyIcon':
          nativeValue = (call.arguments as Map)['on'] as bool;
          return nativeValue;
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(dateIconChannel, null);
  });

  Future<Settings> openSettings(WidgetTester t) async {
    t.view.physicalSize = const Size(840, 1700); // a 320dp phone
    t.view.devicePixelRatio = 2.625;
    addTearDown(t.view.reset);
    SharedPreferences.setMockInitialValues({});
    late Settings settings;
    await t.runAsync(() async => settings = await Settings.load());
    await t.pumpWidget(SettingsScope(settings: settings, child: const DatesApp()));
    await t.pumpAndSettle();
    await t.tap(find.bySemanticsLabel('Settings').last);
    await t.pumpAndSettle();
    return settings;
  }

  testWidgets('Android: seeded from native, and a flip goes to native', (t) async {
    final settings = await openSettings(t);
    expect(calls.map((c) => c.method), ['getDailyIcon']);
    expect(settings.dailyIcon, isFalse);

    final row = find.byKey(const ValueKey('settings/daily-icon'));
    await t.runAsync(() => Scrollable.ensureVisible(t.element(row), alignment: 0.5));
    await t.pumpAndSettle();
    expect(find.text(_label), findsOneWidget);
    expect(find.text(_hint), findsOneWidget);
    final sw = find.descendant(of: row, matching: find.byType(Switch));
    expect(t.widget<Switch>(sw).value, isFalse);

    // The subtitle is one line on a 320dp phone at the default text size.
    final hintHeight = t.getSize(find.text(_hint)).height;
    final labelLine = t.getSize(find.text(_label)).height;
    expect(hintHeight, lessThan(labelLine * 1.3));

    await t.tap(sw);
    await t.pumpAndSettle();
    expect(calls.last.method, 'setDailyIcon');
    expect(calls.last.arguments, {'on': true});
    expect(nativeValue, isTrue);
    expect(settings.dailyIcon, isTrue);
    expect(t.widget<Switch>(sw).value, isTrue);

    await t.tap(sw);
    await t.pumpAndSettle();
    expect(calls.last.arguments, {'on': false});
    expect(nativeValue, isFalse);
    expect(t.widget<Switch>(sw).value, isFalse);
  });

  testWidgets('not on iOS', (t) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      await openSettings(t);
      expect(find.text(_label), findsNothing);
      expect(calls, isEmpty);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  test('ON when no native side answers', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(dateIconChannel, null);
    SharedPreferences.setMockInitialValues({});
    final s = await Settings.load();
    expect(s.dailyIcon, isTrue);
  });
}
