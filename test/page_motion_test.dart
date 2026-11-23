// The screen under a push slides aside as one still picture
// (StillWhileMoving) and is live again the moment the slide ends; the
// arriving screen stays live so its content can assemble.
import 'package:dates/main.dart';
import 'package:dates/state/settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  bool anyStill(WidgetTester t) => t
      .widgetList<SnapshotWidget>(find.byType(SnapshotWidget))
      .any((w) => w.controller.allowSnapshotting);

  testWidgets('a push and a pop move pictures, then go live', (t) async {
    t.view.physicalSize = const Size(1080, 2400);
    t.view.devicePixelRatio = 2.625;
    addTearDown(t.view.reset);
    SharedPreferences.setMockInitialValues({});
    late Settings settings;
    await t.runAsync(() async => settings = await Settings.load());
    await t.pumpWidget(
      SettingsScope(settings: settings, child: const DatesApp()),
    );
    await t.pumpAndSettle();
    expect(anyStill(t), isFalse, reason: 'nothing still at rest');

    await t.tap(find.bySemanticsLabel('Tools').last);
    await t.pumpAndSettle();
    // The tile may sit below the large app bar's fold.
    await t.runAsync(
      () => Scrollable.ensureVisible(t.element(find.text('Age').first)),
    );
    await t.pumpAndSettle();
    await t.tap(find.text('Age').first);
    await t.pump();
    await t.pump(const Duration(milliseconds: 120));
    final still = t
        .widgetList<SnapshotWidget>(find.byType(SnapshotWidget))
        .where((w) => w.controller.allowSnapshotting)
        .length;
    // Only the screen underneath is a picture: the arriving one stays live
    // so its content can assemble as it slides in.
    expect(still, 1, reason: 'the screen under the push');

    await t.pumpAndSettle();
    expect(anyStill(t), isFalse, reason: 'live again once it has arrived');
    expect(find.bySemanticsLabel('Back'), findsWidgets);

    await t.tap(find.bySemanticsLabel('Back').first);
    await t.pump();
    await t.pump(const Duration(milliseconds: 120));
    expect(anyStill(t), isTrue, reason: 'the screen uncovered is a picture');
    await t.pumpAndSettle();
    expect(anyStill(t), isFalse);
  });
}
