import 'dart:async';

import 'package:flutter/widgets.dart';

/// Today's date for the whole app, kept current while the app is open.
///
/// The Today and Tools tabs read the date as they build, and nothing used to
/// rebuild them when the day turned: an app left open over midnight, or open
/// while the clock or time zone was changed, kept showing yesterday (seen
/// on a device: the icon said Wednesday while the page said Tuesday). Every
/// widget that shows "today" reads it through [TodayScope.now], which also
/// subscribes it to the change.
///
/// It checks the date:
///  - just after the next local midnight (a timer aimed there),
///  - once a minute, which also catches a clock or time-zone change, since
///    a timer runs on elapsed time and would miss a midnight the clock
///    jumped over,
///  - whenever the app comes back to the screen.
/// While the app is in the background it does not tick at all.
class TodayScope extends StatefulWidget {
  const TodayScope({super.key, required this.child, this.clock = DateTime.now});

  final Widget child;

  /// The time source; tests pass a fake one.
  final DateTime Function() clock;

  /// The current time, and a subscription: the calling widget rebuilds when
  /// the date changes. Falls back to the plain clock with no scope above.
  static DateTime now(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<_TodayData>();
    return scope?.clock() ?? DateTime.now();
  }

  @override
  State<TodayScope> createState() => _TodayScopeState();
}

class _TodayScopeState extends State<TodayScope> with WidgetsBindingObserver {
  late DateTime _day = _dateOf(widget.clock());
  Timer? _midnight;
  Timer? _minute;

  static DateTime _dateOf(DateTime t) => DateTime(t.year, t.month, t.day);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stop();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _check();
      _start();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _stop();
    }
  }

  void _start() {
    _stop();
    final now = widget.clock();
    // DateTime(y, m, d + 1) is local midnight of the next calendar day,
    // whatever the day's length (a clock change makes it 23 or 25 hours).
    final next = DateTime(now.year, now.month, now.day + 1);
    _midnight = Timer(next.difference(now) + const Duration(seconds: 1), () {
      _check();
      _start();
    });
    _minute = Timer.periodic(const Duration(minutes: 1), (_) => _check());
  }

  void _stop() {
    _midnight?.cancel();
    _minute?.cancel();
    _midnight = _minute = null;
  }

  void _check() {
    final day = _dateOf(widget.clock());
    if (day != _day && mounted) setState(() => _day = day);
  }

  @override
  Widget build(BuildContext context) =>
      _TodayData(day: _day, clock: widget.clock, child: widget.child);
}

class _TodayData extends InheritedWidget {
  const _TodayData({required this.day, required this.clock, required super.child});

  final DateTime day;
  final DateTime Function() clock;

  @override
  bool updateShouldNotify(_TodayData old) => old.day != day;
}
