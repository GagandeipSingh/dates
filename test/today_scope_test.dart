import 'dart:io';

import 'package:dates/state/today.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Shows the day of the month TodayScope reports, so a test can read it.
class _Day extends StatelessWidget {
  const _Day();
  @override
  Widget build(BuildContext context) => Text(
    '${TodayScope.now(context).day}',
    textDirection: TextDirection.ltr,
  );
}

void main() {
  late DateTime fake;
  DateTime clock() => fake;

  Future<void> pumpScope(WidgetTester tester) => tester.pumpWidget(
    TodayScope(clock: clock, child: const _Day()),
  );

  testWidgets('turns over at midnight while the app is open', (tester) async {
    fake = DateTime(2026, 11, 24, 23, 59, 30);
    await pumpScope(tester);
    expect(find.text('24'), findsOneWidget);
    // The midnight timer fires 30 s + 1 s later; move the clock with it.
    fake = DateTime(2026, 11, 25, 0, 0, 1);
    await tester.pump(const Duration(seconds: 31));
    expect(find.text('25'), findsOneWidget);
  });

  testWidgets('follows a clock or time-zone change within a minute', (
    tester,
  ) async {
    fake = DateTime(2026, 11, 24, 10);
    await pumpScope(tester);
    expect(find.text('24'), findsOneWidget);
    // The clock jumps a day; no midnight timer is due, the minute check sees it.
    fake = DateTime(2026, 11, 25, 10);
    await tester.pump(const Duration(minutes: 1));
    expect(find.text('25'), findsOneWidget);
  });

  testWidgets('checks again when the app comes back to the screen', (
    tester,
  ) async {
    fake = DateTime(2026, 11, 24, 10);
    await pumpScope(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    fake = DateTime(2026, 11, 26, 9);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(find.text('26'), findsOneWidget);
  });

  testWidgets('does not rebuild while the date is unchanged', (tester) async {
    fake = DateTime(2026, 11, 24, 10);
    var builds = 0;
    await tester.pumpWidget(
      TodayScope(
        clock: clock,
        child: Builder(
          builder: (context) {
            TodayScope.now(context);
            builds++;
            return const SizedBox();
          },
        ),
      ),
    );
    fake = DateTime(2026, 11, 24, 10, 5);
    await tester.pump(const Duration(minutes: 5));
    expect(builds, 1);
  });

  test('the tabs that show today read it through TodayScope', () {
    // A plain DateTime.now() in these builds is how the Today page stayed
    // on yesterday; this keeps it from coming back.
    final home = File('lib/ui/home.dart').readAsStringSync();
    for (final tab in ['class TodayTab', 'class ToolsTab']) {
      final start = home.indexOf(tab);
      expect(start, isNonNegative, reason: tab);
      final build = home.indexOf('Widget build(', start);
      final body = home.substring(build, home.indexOf('\n  }\n', build));
      expect(body, contains('TodayScope.now(context)'), reason: tab);
      expect(body, isNot(contains('DateTime.now()')), reason: tab);
    }
    final main = File('lib/main.dart').readAsStringSync();
    expect(main, contains('TodayScope(child: DatesApp())'));
  });
}
