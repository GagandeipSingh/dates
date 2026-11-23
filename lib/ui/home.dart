import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../logic/date_math.dart';
import '../state/settings.dart';
import '../state/today.dart';
import 'glass_surface.dart';
import 'date_dock.dart';
import 'kit.dart';
import 'page_motion.dart';
import 'scale.dart';
import 'tools.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int tab = 0;

  /// Fired when a tab's dock item is tapped while it is open.
  final _top = [for (var i = 0; i < 3; i++) ValueNotifier<int>(0)];

  @override
  void dispose() {
    for (final t in _top) {
      t.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    // Back from Tools or Settings goes to Today; back from Today leaves.
    return PopScope(
      canPop: tab == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => tab = 0);
      },
      child: _scaffold(p),
    );
  }

  Widget _scaffold(Pal p) {
    // Each tab is its own screen with its own One UI app bar, titled with
    // the tab's name (guide p.31: no separate app title over main tabs).
    // The tabs sit in the floating bottom navigation, in thumb reach.
    return GlassScaffold(
      background: const GradientBackground(),
      statusBarStyle: p.dark
          ? GlassStatusBarStyle.light
          : GlassStatusBarStyle.dark,
      bottomBarHeight: DateDock.height,
      // At launch the dock rises into place from below the screen on the
      // settle spring, once (its key never changes).
      bottomBar: SpringIn(
        key: const ValueKey('tabs'),
        from: Offset(0, 110.dp),
        // The date dock: Today | Tools | Settings, the open tab a pill on
        // the left, Today's icon a live calendar. Tab indexes are Today 0,
        // Tools 1, Settings 2; Today is the default.
        child: DateDockHost(
          selected: tab,
          onSelected: (i) => setState(() => tab = i),
          onReselect: (i) => _top[i].value++,
          items: const [
            DockItem(tab: 0, label: 'Today', kind: DockIconKind.today),
            DockItem(
              tab: 1,
              label: 'Tools',
              icon: PhosphorIconsFill.stack,
              activeIcon: PhosphorIconsFill.stack,
              kind: DockIconKind.wiggle,
            ),
            DockItem(
              tab: 2,
              label: 'Settings',
              icon: PhosphorIconsFill.gearSix,
              activeIcon: PhosphorIconsFill.gearSix,
              kind: DockIconKind.turn,
            ),
          ],
        ),
      ),
      // Each tab is built on first visit and then kept, so its scroll
      // position survives a switch; a switch is a short fade-through (the
      // dock's blob stretches across at the same time). Tapping the open
      // tab again scrolls it back to its top.
      body: FadeThroughTabs(
        index: tab,
        count: 3,
        builder: (context, i) => ScrollToTop(
          signal: _top[i],
          child: const [TodayTab(), ToolsTab(), SettingsTab()][i],
        ),
      ),
    );
  }
}

// ───────────────────────────────────────────── Layout

// contentMaxWidth and pageColumns live in kit.dart, beside ToolScreen.

// ───────────────────────────────────────────── Today

class TodayTab extends StatelessWidget {
  const TodayTab({super.key});

  @override
  Widget build(BuildContext context) {
    // Rebuilt when the day turns while the app is open (TodayScope).
    final now = TodayScope.now(context);
    final isWide = pageColumns(context, minColumn: 380) > 1;
    // The calendar's week rows are tall where the window is (an unfolded
    // fold) and shorter on a landscape tablet or a desktop window, so the
    // page ends above the dock there instead of running under it.
    final height = MediaQuery.sizeOf(context).height;
    final wideRow = 52 - ((790 - height) / 6).clamp(0.0, 20.0);
    // Six jumps from today beside a tall calendar, four beside a short one.
    final tall = height >= 760;
    // On a wide screen the rings move beside the calendar, so the two
    // columns come out about the same height without stretching a card.
    final left = [
      _DateHeader(now: now),
      SizedBox(height: 18.dp),
      if (!isWide) ...[_Rings(now: now), SizedBox(height: 12.dp)],
      _MonthCard(now: now, row: isWide ? wideRow : 36),
    ];
    final right = [
      const SectionTitle('Coming up'),
      _ComingUp(now: now),
      if (isWide) ...[SizedBox(height: 12.dp), _Rings(now: now)],
      // A wide window has room beside the calendar: the quick jumps from
      // today fill it with answers rather than leave it empty.
      if (isWide) ...[
        const SectionTitle('From today'),
        Expanded(
          child: _QuickDates(
            today: DateTime(now.year, now.month, now.day),
            more: tall,
          ),
        ),
      ],
    ];

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: contentMaxWidth(context)),
        child: PageScroll(
          title: 'Today',
          padding: pagePadding(context, tabBar: true),
          children: isWide
              ? [
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: left,
                          ),
                        ),
                        Gap(24.dp),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: right,
                          ),
                        ),
                      ],
                    ),
                  ),
                ]
              : [...left, ...right],
        ),
      ),
    );
  }
}

/// Today's brief (One UI's Now Brief card): the day of the week, the date
/// large, where it sits in the year, how far the weekend is, and the two
/// tools most often reached for from today as quick actions.
class _DateHeader extends StatelessWidget {
  const _DateHeader({required this.now});
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final s = SettingsScope.of(context);
    final today = DateTime(now.year, now.month, now.day);
    final toWeekend = (DateTime.saturday - today.weekday) % 7;
    final weekend = today.weekday >= DateTime.saturday
        ? 'It is the weekend'
        : toWeekend == 1
        ? 'The weekend starts tomorrow'
        : 'The weekend is $toWeekend days away';
    void open(Widget page) =>
        Navigator.of(context).push(AppPageRoute(builder: (_) => page));
    // When the day turns with the app open, the card rolls over to the new
    // day like a calendar leaf (TodayScope rebuilds it).
    return RollSwitcher(
      value: today,
      child: BriefCard(
        now: now,
        eyebrow: DateFormat('EEEE').format(now),
        headline: DateFormat('d MMMM y').format(now),
        lines: [
          'Week ${weekOfYear(now, mondayFirst: s.mondayFirst)}'
              '  ·  Day ${dayOfYear(now)} of ${daysInYear(now.year)}',
          weekend,
        ],
        actions: [
          BriefAction(
            label: 'Add or subtract',
            icon: PhosphorIconsFill.calculator,
            onTap: () => open(const AddScreen()),
          ),
          BriefAction(
            label: 'Between dates',
            icon: PhosphorIconsFill.hourglassMedium,
            onTap: () => open(const BetweenScreen()),
          ),
        ],
      ),
    );
  }
}

/// How far through the year and the month, as two rings side by side.
class _Rings extends StatelessWidget {
  const _Rings({required this.now});
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final dim = daysInMonth(now.year, now.month);
    final yearLeft = daysInYear(now.year) - dayOfYear(now);
    Widget half(String title, double v, String left) => Row(
      children: [
        // Fills from empty the first time Today is shown in a run.
        RepaintBoundary(
          child: FillOnce(
            id: 'today-ring:$title',
            value: v,
            builder: (context, x) => _Ring(value: x, size: 58.dp),
          ),
        ),
        SizedBox(width: 12.dp),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: p.ink,
                  fontSize: 15.sp,
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(height: 2.dp),
              Text(
                left,
                style: TextStyle(color: p.sub, fontSize: 12.5.sp),
              ),
            ],
          ),
        ),
      ],
    );
    return Pane(
      padding: EdgeInsets.fromLTRB(14.dp, 14.dp, 14.dp, 14.dp),
      child: IntrinsicHeight(
        child: Row(
          children: [
            Expanded(
              child: half(
                '${now.year}',
                yearProgress(now),
                '${n(yearLeft)} days left',
              ),
            ),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 12.dp),
              child: Container(width: 0.6, color: p.faint),
            ),
            Expanded(
              child: half(
                DateFormat('MMMM').format(now),
                now.day / dim,
                '${plural(dim - now.day, 'day')} left',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A progress ring with its percentage inside.
class _Ring extends StatelessWidget {
  const _Ring({required this.value, required this.size});
  final double value, size;

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _RingPainter(
          value: value,
          track: p.faint,
          fill: p.accent,
          width: size * 0.11,
        ),
        child: Center(
          child: Text(
            '${(value * 100).round()}%',
            style: TextStyle(
              color: p.ink,
              fontSize: 13.sp,
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.value,
    required this.track,
    required this.fill,
    required this.width,
  });
  final double value, width;
  final Color track, fill;

  @override
  void paint(Canvas canvas, Size size) {
    final r = (size.shortestSide - width) / 2;
    final c = size.center(Offset.zero);
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width;
    canvas.drawCircle(c, r, base..color = track);
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r),
      -1.5707963267948966,
      6.283185307179586 * value.clamp(0.0, 1.0),
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round
        ..color = fill,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.value != value || old.fill != fill || old.track != track;
}

/// This month as a calendar: today in an accent circle, the days gone
/// quieter, weekends a shade softer.
class _MonthCard extends StatelessWidget {
  const _MonthCard({required this.now, this.row = 36});
  final DateTime now;

  /// Height of a week row. Taller beside the right column on a wide screen,
  /// so the two columns end together without stretching a card.
  final double row;

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final mondayFirst = SettingsScope.of(context).mondayFirst;
    final dim = daysInMonth(now.year, now.month);
    final first = DateTime(now.year, now.month, 1);
    final lead = mondayFirst ? first.weekday - 1 : first.weekday % 7;
    final cells = lead + dim;
    final rows = (cells / 7).ceil();
    // Weekday letters in the week's own order.
    final names = [
      for (var i = 0; i < 7; i++)
        DateFormat('E')
            .format(DateTime(2024, 1, mondayFirst ? 1 + i : 7 + i))
            .substring(0, 1),
    ];
    bool weekendCol(int c) => mondayFirst ? c >= 5 : (c == 0 || c == 6);

    return Pane(
      padding: EdgeInsets.fromLTRB(14.dp, 14.dp, 14.dp, 10.dp),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 4.dp),
            child: Row(
              children: [
                Text(
                  DateFormat('MMMM').format(now),
                  style: TextStyle(
                    color: p.ink,
                    fontSize: 15.sp,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Text(
                  '${now.year}',
                  style: TextStyle(color: p.sub, fontSize: 12.5.sp),
                ),
              ],
            ),
          ),
          SizedBox(height: 10.dp),
          Row(
            children: [
              for (var c = 0; c < 7; c++)
                Expanded(
                  child: Center(
                    child: Text(
                      names[c],
                      style: TextStyle(
                        color: p.sub,
                        fontSize: 11.sp,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          SizedBox(height: 4.dp),
          for (var r = 0; r < rows; r++)
            Row(
              children: [
                for (var c = 0; c < 7; c++)
                  Expanded(
                    child: Builder(
                      builder: (context) {
                        final day = r * 7 + c - lead + 1;
                        if (day < 1 || day > dim) {
                          return SizedBox(height: row.dp);
                        }
                        final isToday = day == now.day;
                        final past = day < now.day;
                        return SizedBox(
                          height: row.dp,
                          child: Center(
                            child: Container(
                              width: 32.dp,
                              height: 32.dp,
                              alignment: Alignment.center,
                              decoration: isToday
                                  ? BoxDecoration(
                                      color: p.accentRaw,
                                      shape: BoxShape.circle,
                                    )
                                  : null,
                              child: Text(
                                '$day',
                                style: TextStyle(
                                  color: isToday
                                      ? Colors.white
                                      : past
                                      ? p.sub.withValues(alpha: 0.45)
                                      : weekendCol(c)
                                      ? p.sub
                                      : p.ink,
                                  fontSize: 14.sp,
                                  fontWeight: isToday
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

/// What is next on the calendar, counted from today: four small cards,
/// each a countdown with what it is and when.
class _ComingUp extends StatelessWidget {
  const _ComingUp({required this.now});
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final today = DateTime(now.year, now.month, now.day);
    int until(DateTime d) => DateTime.utc(
      d.year,
      d.month,
      d.day,
    ).difference(DateTime.utc(today.year, today.month, today.day)).inDays;
    final weekend = today.weekday >= DateTime.saturday;
    final sat = today.add(
      Duration(days: (DateTime.saturday - today.weekday) % 7),
    );
    final nextMonth = DateTime(today.year, today.month + 1, 1);
    final newYear = DateTime(today.year + 1, 1, 1);
    final leap = nextLeapDay(today);
    final fmt = DateFormat('EEE, d MMM');
    // (icon, colour, days away, what, when)
    final items = <(IconData, Color, int, String, String)>[
      (
        PhosphorIconsFill.sun,
        const Color(0xFFF08A1D),
        weekend ? 0 : until(sat),
        'Weekend',
        weekend ? 'Today' : fmt.format(sat),
      ),
      (
        PhosphorIconsFill.calendarBlank,
        const Color(0xFF1E7BF2),
        until(nextMonth),
        DateFormat('MMMM').format(nextMonth),
        fmt.format(nextMonth),
      ),
      (
        PhosphorIconsFill.sparkle,
        const Color(0xFFE5407F),
        until(newYear),
        'New Year',
        DateFormat('d MMM y').format(newYear),
      ),
      (
        PhosphorIconsFill.star,
        const Color(0xFF6A4CF5),
        until(leap),
        'Leap day',
        DateFormat('d MMM y').format(leap),
      ),
    ];
    Widget card((IconData, Color, int, String, String) it) => GlassSurface(
      radius: 22.dp,
      padding: EdgeInsets.fromLTRB(14.dp, 15.dp, 12.dp, 15.dp),
      child: Row(
        children: [
          Container(
            width: 36.dp,
            height: 36.dp,
            decoration: BoxDecoration(
              color: it.$2.withValues(alpha: p.dark ? 0.2 : 0.13),
              borderRadius: BorderRadius.circular(11.dp),
            ),
            alignment: Alignment.center,
            child: Icon(it.$1, size: 19.dp, color: it.$2),
          ),
          SizedBox(width: 12.dp),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  // Ticks down in place when the day turns: only the
                  // figure counts, the card around it stays still.
                  child: CountText(
                    it.$3 == 0
                        ? 'Today'
                        : '${n(it.$3)} ${it.$3 == 1 ? 'day' : 'days'}',
                    style: TextStyle(
                      color: p.ink,
                      fontSize: 18.5.sp,
                      fontWeight: FontWeight.w700,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                Text(
                  it.$4,
                  style: TextStyle(color: p.sub, fontSize: 13.5.sp),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    Widget row(int i) => IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: card(items[i])),
          SizedBox(width: 12.dp),
          Expanded(child: card(items[i + 1])),
        ],
      ),
    );
    return Column(
      children: [
        row(0),
        SizedBox(height: 12.dp),
        row(2),
      ],
    );
  }
}

// ───────────────────────────────────────────── Tools

class _Tool {
  const _Tool(
    this.title,
    this.subtitle,
    this.icon,
    this.color,
    this.page, {
    this.glyph,
  });
  final String title, subtitle;
  final IconData icon;

  /// Text drawn in the tile instead of [icon] (Leap Year shows "29").
  final String? glyph;
  final Color color;
  final Widget Function() page;
}

final _tools = <_Tool>[
  _Tool(
    'Between Dates',
    'Time between any two dates',
    PhosphorIconsFill.hourglassMedium,
    const Color(0xFF1E7BF2),
    () => const BetweenScreen(),
  ),
  _Tool(
    'Age',
    'Exact age, next birthday and totals',
    PhosphorIconsFill.cake,
    const Color(0xFFE5407F),
    () => const AgeScreen(),
  ),
  _Tool(
    'Add or Subtract',
    'Move a date forward or back',
    PhosphorIconsFill.calculator,
    const Color(0xFFF08A1D),
    () => const AddScreen(),
  ),
  _Tool(
    'Working Days',
    'Business days between two dates',
    PhosphorIconsFill.briefcase,
    const Color(0xFF14A37F),
    () => const WorkingDaysScreen(),
  ),
  _Tool(
    'Weekday',
    'The day of the week for any date',
    PhosphorIconsFill.calendarBlank,
    const Color(0xFF6A4CF5),
    () => const WeekdayScreen(),
  ),
  _Tool(
    'Leap Year',
    'Check any year for 29 February',
    PhosphorIconsFill.calendarPlus,
    const Color(0xFFF2564B),
    () => const LeapYearScreen(),
    glyph: '29',
  ),
];

class ToolsTab extends StatelessWidget {
  const ToolsTab({super.key});

  /// Three pairs: tools that count a span, tools that find a date, and
  /// tools that check a fact. Each tile shows a live answer for today and
  /// a small picture of it, so the screen says what a tool does by doing it.
  static const _groups = <(String, List<int>)>[
    ('Count', [0, 3]),
    ('Find', [2, 4]),
    ('Check', [1, 5]),
  ];

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final settings = SettingsScope.of(context);
    final now = TodayScope.now(context);
    final today = DateTime(now.year, now.month, now.day);
    final newYear = DateTime(now.year + 1, 1, 1);
    final toNewYear = newYear.difference(today).inDays;
    final monthEnd = DateTime(
      now.year,
      now.month,
      daysInMonth(now.year, now.month),
    );
    final workdays = settings.workdays;
    final workLeft = workingDays(today, monthEnd, workdays).working;
    final plus30 = today.add(const Duration(days: 30));
    final leap = nextLeapDay(today).year;
    final short = DateFormat('d MMM');

    Widget chip(String text, Color c, {bool on = true}) => Container(
      padding: EdgeInsets.symmetric(horizontal: 7.dp, vertical: 3.dp),
      decoration: BoxDecoration(
        color: on ? c.withValues(alpha: p.dark ? 0.22 : 0.14) : p.faint,
        borderRadius: BorderRadius.circular(8.dp),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: on ? c : p.sub,
          fontSize: 11.5.sp,
          fontWeight: FontWeight.w500,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );

    // Between Dates: today joined to New Year.
    Widget span(Color c) => FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          chip('Today', c),
          SizedBox(
            width: 58.dp,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 4.dp),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 2,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(1),
                        gradient: LinearGradient(
                          colors: [c.withValues(alpha: 0.15), c],
                        ),
                      ),
                    ),
                  ),
                  Icon(PhosphorIconsBold.caretRight, size: 11.dp, color: c),
                ],
              ),
            ),
          ),
          chip(short.format(newYear), c),
        ],
      ),
    );

    // Working Days: every day left this month, work days filled.
    Widget days(Color c) => Wrap(
      spacing: 4.dp,
      runSpacing: 4.dp,
      children: [
        for (
          var d = today;
          !d.isAfter(monthEnd);
          d = DateTime(d.year, d.month, d.day + 1)
        )
          Container(
            width: 8.dp,
            height: 8.dp,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: workdays.contains(d.weekday) ? c : p.faint,
            ),
          ),
      ],
    );

    // Add or Subtract: today moved 30 days on.
    Widget shift(Color c) => FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          chip(short.format(today), c, on: false),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 5.dp),
            child: Text(
              '+30',
              style: TextStyle(
                color: p.sub,
                fontSize: 12.5.sp,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          chip(short.format(plus30), c),
        ],
      ),
    );

    // Weekday: the week's letters, today lit.
    Widget week(Color c) {
      final first = settings.mondayFirst ? 1 : 7;
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          for (var i = 0; i < 7; i++)
            Builder(
              builder: (_) {
                final wd = (first - 1 + i) % 7 + 1;
                final on = wd == now.weekday;
                return Container(
                  width: 19.dp,
                  height: 19.dp,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: on ? c : Colors.transparent,
                  ),
                  child: Text(
                    DateFormat(
                      'E',
                    ).format(DateTime(2024, 1, wd)).substring(0, 1),
                    style: TextStyle(
                      color: on ? Colors.white : p.sub,
                      fontSize: 12.sp,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                );
              },
            ),
        ],
      );
    }

    // Age: the three parts it answers in.
    Widget parts(Color c) => Wrap(
      spacing: 5.dp,
      runSpacing: 5.dp,
      children: [chip('Years', c), chip('Months', c), chip('Days', c)],
    );

    // Leap Year: this year to the next leap year.
    Widget years(Color c) => Wrap(
      spacing: 5.dp,
      runSpacing: 5.dp,
      children: [
        for (var y = now.year; y <= leap && y < now.year + 4; y++)
          chip('$y', c, on: y == leap),
      ],
    );

    // (value, what it means, picture) for each tool, in _tools order.
    final live = <(String, String, Widget Function(Color))>[
      (n(toNewYear), 'days to New Year', span),
      ('To the day', 'your exact age', parts),
      (short.format(plus30), '30 days from today', shift),
      (
        '$workLeft',
        'work days left in ${DateFormat('MMMM').format(now)}',
        days,
      ),
      (DateFormat('EEEE').format(now), 'today', week),
      ('$leap', 'next leap year', years),
    ];
    // A phone or an unfolded foldable: one column. A tablet: two. A
    // desktop window: three, so the six tools sit in one band.
    final big = isWideLayout(context);
    // A landscape tablet or desktop window is short: the tiles tighten a
    // little so the From today band ends above the dock.
    final snug = big && MediaQuery.sizeOf(context).height < 760;
    Widget tile(int i) => _ToolTile(
      snug: snug,
      tool: _tools[i],
      value: live[i].$1,
      note: live[i].$2,
      picture: live[i].$3(_tools[i].color),
      big: big,
    );
    // A phone: each group's two tools side by side. A fold, tablet or
    // desktop: the three groups side by side, each group's tools stacked,
    // so every tile keeps a tile's shape and the screen is filled.
    Widget group((String, List<int>) g) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(g.$1),
        Expanded(
          child: big
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < g.$2.length; i++) ...[
                      if (i > 0) SizedBox(height: 10.dp),
                      Expanded(child: tile(g.$2[i])),
                    ],
                  ],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < g.$2.length; i++) ...[
                      if (i > 0) SizedBox(width: 10.dp),
                      Expanded(child: tile(g.$2[i])),
                    ],
                  ],
                ),
        ),
      ],
    );
    final quick = IntrinsicHeight(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionTitle('From today'),
          Expanded(
            child: _QuickDates(today: today, perRow: big ? 4 : 2),
          ),
        ],
      ),
    );
    // Side by side, every section in a row is the same height.
    Widget band(List<Widget> items) => IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var j = 0; j < items.length; j++) ...[
            if (j > 0) Gap(16.dp),
            Expanded(child: items[j]),
          ],
        ],
      ),
    );
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: contentMaxWidth(context)),
        child: PageScroll(
          title: 'Tools',
          padding: pagePadding(context, tabBar: true),
          children: big
              ? [
                  band([for (final g in _groups) group(g)]),
                  SizedBox(height: 8.dp),
                  quick,
                ]
              : [
                  for (final g in _groups) band([group(g)]),
                  quick,
                ],
        ),
      ),
    );
  }
}

/// Common jumps from today, answered at a glance: a week, a fortnight,
/// 30, 90 and 100 days, a year. Tapping opens Add or Subtract.
class _QuickDates extends StatelessWidget {
  const _QuickDates({required this.today, this.perRow = 2, this.more = false});
  final DateTime today;

  /// Six jumps instead of four, for a tall card beside the calendar.
  final bool more;

  /// Cells per row: four in a wide band, else two rows of two.
  final int perRow;

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final fmt = DateFormat('EEE, d MMM');
    final jumps = <(String, DateTime)>[
      ('1 week', today.add(const Duration(days: 7))),
      if (more) ('2 weeks', today.add(const Duration(days: 14))),
      ('30 days', today.add(const Duration(days: 30))),
      if (more) ('90 days', today.add(const Duration(days: 90))),
      ('100 days', today.add(const Duration(days: 100))),
      ('1 year', DateTime(today.year + 1, today.month, today.day)),
    ];
    Widget cell((String, DateTime) j) => Padding(
      padding: EdgeInsets.symmetric(vertical: 8.dp, horizontal: 4.dp),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            j.$1,
            style: TextStyle(color: p.sub, fontSize: 12.5.sp),
          ),
          SizedBox(height: 2.dp),
          Text(
            fmt.format(j.$2),
            style: TextStyle(
              color: p.ink,
              fontSize: 14.5.sp,
              fontWeight: FontWeight.w500,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
    Widget line() => Container(height: 0.6, color: p.faint);
    return GlassPress(
      label: 'Add or Subtract',
      onTap: () => Navigator.of(
        context,
      ).push(AppPageRoute(builder: (_) => const AddScreen())),
      builder: (down) => GlassSurface(
        radius: 16.dp,
        lit: down,
        padding: EdgeInsets.fromLTRB(12.dp, 6.dp, 12.dp, 6.dp),
        child: Column(
          children: [
            for (var r = 0; r < jumps.length ~/ perRow; r++) ...[
              if (r > 0) line(),
              Expanded(
                child: Row(
                  children: [
                    for (var k = 0; k < perRow; k++)
                      Expanded(child: cell(jumps[r * perRow + k])),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A tool as a small glass tile: badge and name, today's answer from that
/// tool, and a small picture of it pinned to the bottom.
class _ToolTile extends StatelessWidget {
  const _ToolTile({
    required this.tool,
    required this.value,
    required this.note,
    required this.picture,
    this.big = false,
    this.snug = false,
  });
  final _Tool tool;
  final String value, note;
  final Widget picture;

  /// Larger type for a tablet, fold or desktop window.
  final bool big;

  /// Tighter spacing, for a short wide window.
  final bool snug;

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final t = tool;
    return GlassPress(
      label: '${t.title}. $value $note',
      onTap: () =>
          Navigator.of(context).push(AppPageRoute(builder: (_) => t.page())),
      builder: (down) => GlassSurface(
        radius: 18.dp,
        lit: down,
        padding: big
            ? EdgeInsets.all(snug ? 13.dp : 16.dp)
            : EdgeInsets.fromLTRB(14.dp, 14.dp, 14.dp, 15.dp),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _Badge(
                  color: t.color,
                  icon: t.icon,
                  glyph: t.glyph,
                  size: big ? 32.dp : 28.dp,
                ),
                SizedBox(width: 10.dp),
                Expanded(
                  child: Text(
                    t.title,
                    style: TextStyle(
                      color: p.ink,
                      fontSize: big ? 15.sp : 14.sp,
                      fontWeight: FontWeight.w500,
                      height: 1.15,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: snug ? 10.dp : 14.dp),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: TextStyle(
                  color: p.ink,
                  fontSize: big ? 26.sp : 20.sp,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.2,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            Text(
              note,
              style: TextStyle(color: p.sub, fontSize: big ? 13.sp : 12.5.sp),
            ),
            SizedBox(height: snug ? 10.dp : 14.dp),
            const Spacer(),
            picture,
          ],
        ),
      ),
    );
  }
}

/// A coloured square with a white icon (or a glyph, as Leap Year's "29").
class _Badge extends StatelessWidget {
  const _Badge({
    required this.color,
    required this.icon,
    required this.size,
    this.glyph,
  });
  final Color color;
  final IconData icon;
  final String? glyph;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(size * 0.26),
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color.lerp(color, Colors.white, 0.18)!, color],
      ),
    ),
    alignment: Alignment.center,
    child: glyph == null
        ? Icon(icon, color: Colors.white, size: size * 0.5)
        : Text(
            glyph!,
            style: TextStyle(
              color: Colors.white,
              fontSize: size * 0.4,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
              height: 1,
            ),
          ),
  );
}

class _ToolRow extends StatefulWidget {
  const _ToolRow({required this.tool});
  final _Tool tool;
  @override
  State<_ToolRow> createState() => _ToolRowState();
}

class _ToolRowState extends State<_ToolRow> {
  bool down = false;
  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final t = widget.tool;
    return Semantics(
      button: true,
      label: '${t.title}. ${t.subtitle}',
      excludeSemantics: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => setState(() => down = true),
          onTapCancel: () => setState(() => down = false),
          onTapUp: (_) => setState(() => down = false),
          onTap: () => Navigator.of(
            context,
          ).push(AppPageRoute(builder: (_) => t.page())),
          child: PressScale(
            child: AnimatedContainer(
              duration: motion(context, kFadeMs),
              curve: kFade,
              margin: EdgeInsets.symmetric(horizontal: 6.dp),
              padding: EdgeInsets.symmetric(horizontal: 10.dp, vertical: 16.dp),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18.dp),
                color: down ? p.faint : Colors.transparent,
              ),
              child: Row(
                children: [
                  Container(
                    width: 40.dp,
                    height: 40.dp,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12.dp),
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Color.lerp(t.color, Colors.white, 0.18)!,
                          t.color,
                        ],
                      ),
                    ),
                    alignment: Alignment.center,
                    child: t.glyph == null
                        ? Icon(t.icon, color: Colors.white, size: 21.dp)
                        : Text(
                            t.glyph!,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: t.glyph!.length == 1 ? 26.sp : 17.sp,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.5,
                              height: 1,
                            ),
                          ),
                  ),
                  SizedBox(width: 14.dp),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          t.title,
                          style: TextStyle(
                            color: p.ink,
                            fontSize: 16.sp,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        SizedBox(height: 2.dp),
                        Text(
                          t.subtitle,
                          style: TextStyle(color: p.sub, fontSize: 12.5.sp),
                        ),
                      ],
                    ),
                  ),
                  Icon(PhosphorIconsBold.caretRight, size: 16.dp, color: p.sub),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ───────────────────────────────────────────── Settings

class SettingsTab extends StatelessWidget {
  const SettingsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final s = SettingsScope.of(context);
    final p = Pal.of(context);
    final sample = DateTime(DateTime.now().year, 7, 17);
    final isWide = pageColumns(context, minColumn: 380) > 1;

    // Every colour on one row, spread edge to edge: a Wrap left the last
    // one alone on a second row on a fold. The dot shrinks only if the row
    // could not otherwise hold all of them.
    // A short wide window (landscape tablet, desktop) tightens a little so
    // the page ends above the dock.
    final short = MediaQuery.sizeOf(context).height < 760;
    final maxSwatch = isWide ? 52.dp : 40.dp;
    // Flexible + AspectRatio rather than a LayoutBuilder: this row sits in
    // an IntrinsicHeight on wide screens, which a LayoutBuilder cannot.
    final swatches = Builder(
      builder: (context) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (var i = 0; i < accents.length; i++) ...[
              if (i > 0) SizedBox(width: 6.dp),
              Flexible(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxSwatch),
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: Semantics(
                      button: true,
                      selected: i == s.accentIndex,
                      label: accents[i].name,
                      excludeSemantics: true,
                      child: GestureDetector(
                        onTap: () => s.accentIndex = i,
                        child: MouseRegion(
                          cursor: SystemMouseCursors.click,
                          // Pressed like any tile; the ring eases in.
                          child: PressScale(
                            child: AnimatedContainer(
                              duration: motion(context, kFadeMs),
                              curve: kFade,
                              padding: EdgeInsets.all(3.dp),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: i == s.accentIndex
                                      ? accents[i].color
                                      : Colors.transparent,
                                  width: 2.2.dp,
                                ),
                              ),
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      accents[i].light[1],
                                      accents[i].color,
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );

    final switches = <Widget>[
      SwitchRow(
        label: '24-hour time',
        hint: s.time(DateTime(2026, 1, 1, 17, 30)),
        value: s.use24h,
        onChanged: (v) => s.use24h = v,
      ),
      SwitchRow(
        label: 'Week starts on Monday',
        hint: s.mondayFirst
            ? 'ISO week numbers'
            : 'Sunday first, US week numbers',
        value: s.mondayFirst,
        onChanged: (v) => s.mondayFirst = v,
      ),
      SwitchRow(
        label: 'Share button',
        hint: 'Show Share under results',
        value: s.showShare,
        onChanged: (v) => s.showShare = v,
      ),
      // Android only: the launcher icon follows today's date. Off keeps
      // one fixed entry that app pairs and routines can name.
      if (dateIconSupported)
        SwitchRow(
          key: const ValueKey('settings/daily-icon'),
          label: 'Daily date icon',
          hint: 'Off: fixed icon, keeps app pairs',
          value: s.dailyIcon,
          onChanged: (v) => s.dailyIcon = v,
        ),
    ];
    // A phone lists the switches; a wide page sets them two to a row, so
    // the card is half as tall and the page fits above the dock.
    final prefs = isWide
        ? Column(
            children: [
              for (var i = 0; i < switches.length; i += 2) ...[
                if (i > 0) const Hairline(),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: switches[i]),
                    Gap(32.dp),
                    Expanded(
                      child: i + 1 < switches.length
                          ? switches[i + 1]
                          : const SizedBox.shrink(),
                    ),
                  ],
                ),
              ],
            ],
          )
        : Column(
            children: [
              for (var i = 0; i < switches.length; i++) ...[
                if (i > 0) const Hairline(),
                switches[i],
              ],
            ],
          );

    final lookColumn = [
      const SectionTitle('Appearance'),
      Segments<Appearance>(
        values: Appearance.values,
        labels: const ['System', 'Light', 'Dark'],
        selected: s.appearance,
        onChanged: (v) => s.appearance = v,
      ),
      Gap(12.dp),
      Pane(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Caption('Colour'),
                const Spacer(),
                Text(
                  s.accent.name,
                  style: TextStyle(
                    color: p.accent,
                    fontSize: 13.sp,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            SizedBox(height: isWide ? 20.dp : 14.dp),
            // Never stretched to the Date format card beside it: that left
            // a band of nothing between the label and the swatches.
            swatches,
          ],
        ),
      ),
    ];

    final preferencesColumn = [
      const SectionTitle('Date format'),
      Pane(
        padding: EdgeInsets.fromLTRB(18.dp, 6.dp, 18.dp, 6.dp),
        child: Column(
          children: [
            for (final f in dateFormats)
              Semantics(
                button: true,
                selected: f == s.dateFormat,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => s.dateFormat = f,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: SizedBox(
                      // A touch shorter beside the Colour card on a wide page, so the
                      // two cards come out the same height without padding.
                      height: isWide ? (short ? 40.dp : 42.dp) : 48.dp,
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              DateFormat(f).format(sample),
                              style: TextStyle(color: p.ink, fontSize: 15.5.sp),
                            ),
                          ),
                          if (f == s.dateFormat)
                            Icon(
                              PhosphorIconsBold.check,
                              color: p.accent,
                              size: 20.dp,
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
      const SectionTitle('Preferences'),
      Pane(child: prefs),
    ];

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: contentMaxWidth(context)),
        child: PageScroll(
          title: 'Settings',
          padding: pagePadding(context, tabBar: true),
          children: [
            if (isWide) ...[
              // Two equal columns, tops aligned, each card at its own
              // height; Preferences runs full width beneath.
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: lookColumn,
                    ),
                  ),
                  Gap(20.dp),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: preferencesColumn.sublist(0, 2),
                    ),
                  ),
                ],
              ),
              ...preferencesColumn.sublist(2),
            ] else ...[
              ...lookColumn,
              ...preferencesColumn,
            ],
            Gap(isWide ? 8.dp : 24.dp),
            Center(
              child: Text(
                'Dates · ${dayOfYear(TodayScope.now(context))} days into ${TodayScope.now(context).year}',
                style: TextStyle(color: p.sub, fontSize: 12.sp),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
