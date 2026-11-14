import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../logic/date_math.dart';
import '../state/settings.dart';
import 'glass_surface.dart';
import 'glass_tabs.dart';
import 'kit.dart';
import 'scale.dart';
import 'tools.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int tab = 0;
  static const titles = ['Today', 'Tools', 'Settings'];

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
    return GlassScaffold(
      background: const GradientBackground(),
      statusBarStyle: p.dark
          ? GlassStatusBarStyle.light
          : GlassStatusBarStyle.dark,
      appBar: GlassAppBar(
        title: Text(
          titles[tab],
          style: TextStyle(
            color: p.ink,
            fontSize: 17.sp,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      // The compass app's sheet glass as a floating capsule, with a pill
      // that slides under the selected tab.
      bottomBarHeight: 64.dp,
      bottomBar: SpringIn(
        key: const ValueKey('tabs'),
        from: Offset(0, 110.dp),
        child: GlassTabs(
          selected: tab,
          onSelected: (i) => setState(() => tab = i),
          items: const [
            (CupertinoIcons.calendar_today, 'Today'),
            (CupertinoIcons.square_grid_2x2_fill, 'Tools'),
            (CupertinoIcons.gear_alt_fill, 'Settings'),
          ],
        ),
      ),
      // Only the visible tab is built (a glass surface in an offstage tab is
      // still drawn), and it switches instantly, as an iOS tab bar does: the
      // bar's own indicator is the animation.
      // The new tab rises into place on a soft spring: moved, never faded,
      // so its glass never flashes white.
      body: SpringIn(
        key: ValueKey(tab),
        from: Offset(0, 28.dp),
        soft: true,
        child: const [TodayTab(), ToolsTab(), SettingsTab()][tab],
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
    final p = Pal.of(context);
    final now = DateTime.now();
    final isWide = pageColumns(context, minColumn: 380) > 1;

    final heroCard = Pane(
      tint: p.accent.withValues(alpha: 0.035),
      padding: EdgeInsets.fromLTRB(22.dp, 20.dp, 22.dp, 22.dp),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Caption(DateFormat('EEEE').format(now), color: p.accent),
          SizedBox(height: 4.dp),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${now.day}',
                style: TextStyle(
                  color: p.ink,
                  fontSize: 76.sp,
                  height: 1,
                  fontWeight: FontWeight.w300,
                  letterSpacing: -3,
                ),
              ),
              SizedBox(width: 12.dp),
              // A long month name at a large font shrinks a little rather than
              // running off the card.
              Flexible(
                child: Padding(
                  padding: EdgeInsets.only(bottom: 8.dp),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.bottomLeft,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          DateFormat('MMMM').format(now),
                          style: TextStyle(
                            color: p.ink,
                            fontSize: 22.sp,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          '${now.year}',
                          style: TextStyle(color: p.sub, fontSize: 16.sp),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: contentMaxWidth(context)),
        child: PageScroll(
          padding: pagePadding(context, tabBar: true),
          children: isWide
              ? [
                  // Two columns of about equal height, their first cards
                  // level under matching headings, and the stat tiles in a
                  // full-width band of three beneath both.
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const SectionTitle('Date'),
                              heroCard,
                              Gap(12.dp),
                              YearGlance(date: now, stats: false),
                            ],
                          ),
                        ),
                        Gap(20.dp),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              SectionTitle('Quick tools'),
                              // Fills down to the foot of the left column, its
                              // rows spread evenly, so both columns end level.
                              Expanded(child: _ToolList(limit: 3, fill: true)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SectionTitle('This year'),
                  YearGlance(date: now, progress: false, statsPerRow: 3),
                ]
              : [
                  heroCard,
                  Gap(12.dp),
                  YearGlance(date: now),
                  const SectionTitle('Quick tools'),
                  const _ToolList(limit: 3),
                ],
        ),
      ),
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
    'Years, months, days and time between two dates',
    CupertinoIcons.hourglass,
    const Color(0xFF1E7BF2),
    () => const BetweenScreen(),
  ),
  _Tool(
    'Age',
    'Exact age, next birthday and totals',
    Icons.cake_rounded,
    const Color(0xFFE5407F),
    () => const AgeScreen(),
  ),
  _Tool(
    'Add or Subtract',
    'Move a date forward or back',
    Icons.calculate_rounded,
    const Color(0xFFF08A1D),
    () => const AddScreen(),
  ),
  _Tool(
    'Working Days',
    'Business days between two dates',
    CupertinoIcons.briefcase_fill,
    const Color(0xFF14A37F),
    () => const WorkingDaysScreen(),
  ),
  _Tool(
    'Weekday',
    'The day of the week for any date',
    CupertinoIcons.calendar,
    const Color(0xFF6A4CF5),
    () => const WeekdayScreen(),
  ),
  _Tool(
    'Leap Year',
    'Check any year for 29 February',
    CupertinoIcons.calendar_badge_plus,
    const Color(0xFFF2564B),
    () => const LeapYearScreen(),
    glyph: '29',
  ),
];

class ToolsTab extends StatelessWidget {
  const ToolsTab({super.key});
  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: contentMaxWidth(context)),
        child: PageScroll(
          padding: pagePadding(context, tabBar: true),
          children: const [_ToolList()],
        ),
      ),
    );
  }
}

class _ToolList extends StatelessWidget {
  const _ToolList({this.limit, this.fill = false});
  final int? limit;

  /// Grow to the height it is given, spreading the rows evenly.
  final bool fill;

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final list = limit == null ? _tools : _tools.take(limit!).toList();
    final columns = limit == null ? pageColumns(context, minColumn: 380) : 1;

    // A desktop or landscape tablet: big tiles, three to a row, so the page
    // is filled with the tools rather than six thin rows in empty space.
    final tiles = limit == null
        ? pageColumns(context, minColumn: 290, max: 3)
        : 1;
    // An unfolded foldable fits two: the same big tiles, two to a row, so
    // the near-square page is filled rather than three thin rows mid-screen.
    if (tiles >= 2) {
      final rows = <Widget>[];
      for (var i = 0; i < list.length; i += tiles) {
        rows.add(
          Padding(
            padding: EdgeInsets.only(bottom: 16.dp),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var j = 0; j < tiles; j++) ...[
                    if (j > 0) SizedBox(width: 16.dp),
                    Expanded(
                      child: i + j < list.length
                          ? _ToolTile(tool: list[i + j])
                          : const SizedBox(),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      }
      return Column(children: rows);
    }

    // Side by side, each tool its own card. Rows size to their tallest card,
    // never to a fixed height, so a larger font wraps instead of clipping.
    if (columns > 1) {
      final rows = <Widget>[];
      for (var i = 0; i < list.length; i += columns) {
        rows.add(
          Padding(
            padding: EdgeInsets.only(bottom: 12.dp),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var j = 0; j < columns; j++) ...[
                    if (j > 0) SizedBox(width: 12.dp),
                    Expanded(
                      child: i + j < list.length
                          ? Pane(
                              padding: EdgeInsets.symmetric(vertical: 4.dp),
                              child: _ToolRow(tool: list[i + j]),
                            )
                          : const SizedBox(),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      }
      return Column(children: rows);
    }

    return Pane(
      padding: EdgeInsets.symmetric(vertical: 6.dp),
      child: Column(
        mainAxisSize: fill ? MainAxisSize.max : MainAxisSize.min,
        mainAxisAlignment: fill
            ? MainAxisAlignment.spaceEvenly
            : MainAxisAlignment.start,
        children: [
          for (var i = 0; i < list.length; i++) ...[
            if (i > 0)
              Padding(
                padding: EdgeInsets.only(left: 70.dp),
                child: Container(height: 0.6, color: p.faint),
              ),
            _ToolRow(tool: list[i]),
          ],
        ],
      ),
    );
  }
}

/// A tool as a tall glass tile: its icon large at the top, the name and
/// what it does under it. Swells under the finger like every glass control.
class _ToolTile extends StatelessWidget {
  const _ToolTile({required this.tool});
  final _Tool tool;

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final t = tool;
    // A short window (a tablet in landscape, a desktop window not
    // maximised) gets a tighter tile, so the two rows keep air above the tab
    // bar instead of pressing into it. A full desktop keeps the big tile.
    final tight = MediaQuery.sizeOf(context).height < 650;
    double k(double v) => tight ? v * 0.8 : v;
    return GlassPress(
      label: '${t.title}. ${t.subtitle}',
      onTap: () => Navigator.of(
        context,
      ).push(CupertinoPageRoute(builder: (_) => t.page())),
      builder: (down) => GlassSurface(
        radius: 28.dp,
        lit: down,
        padding: EdgeInsets.fromLTRB(k(22).dp, k(22).dp, k(18).dp, k(22).dp),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: k(56).dp,
                  height: k(56).dp,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(k(17).dp),
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Color.lerp(t.color, Colors.white, 0.18)!,
                        t.color,
                      ],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: t.color.withValues(alpha: 0.35),
                        blurRadius: 14.dp,
                        offset: Offset(0, 5.dp),
                      ),
                    ],
                  ),
                  alignment: Alignment.center,
                  child: t.glyph == null
                      ? Icon(t.icon, color: Colors.white, size: k(28).dp)
                      : Text(
                          t.glyph!,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: k(24).sp,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                            height: 1,
                          ),
                        ),
                ),
                const Spacer(),
                Icon(CupertinoIcons.chevron_right, size: 17.dp, color: p.sub),
              ],
            ),
            SizedBox(height: k(22).dp),
            Text(
              t.title,
              style: TextStyle(
                color: p.ink,
                fontSize: (tight ? 17.0 : 19.0).sp,
                fontWeight: FontWeight.w700,
              ),
            ),
            SizedBox(height: 5.dp),
            // Two lines kept for every description, so all the tiles come
            // out the same size whether theirs wraps or not.
            Text(
              '${t.subtitle}\n',
              maxLines: 2,
              overflow: TextOverflow.clip,
              style: TextStyle(
                color: p.sub,
                fontSize: (tight ? 12.5 : 13.5).sp,
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
    );
  }
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
          ).push(CupertinoPageRoute(builder: (_) => t.page())),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
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
                Icon(CupertinoIcons.chevron_right, size: 16.dp, color: p.sub),
              ],
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
    final maxSwatch = isWide ? 46.dp : 40.dp;
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
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 220),
                            curve: Curves.easeOutCubic,
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
            ],
          ],
        );
      },
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
            SizedBox(height: 14.dp),
            // On a wide page the card is stretched to the Date format card
            // beside it: the swatches sit in the middle of that space.
            if (isWide)
              Expanded(
                child: Align(alignment: Alignment.centerLeft, child: swatches),
              )
            else
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
                      height: isWide ? 42.dp : 48.dp,
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
                              CupertinoIcons.checkmark_alt,
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
      Pane(
        child: Column(
          children: [
            SwitchRow(
              label: '24-hour time',
              hint: s.time(DateTime(2026, 1, 1, 17, 30)),
              value: s.use24h,
              onChanged: (v) => s.use24h = v,
            ),
            const Hairline(),
            SwitchRow(
              label: 'Week starts on Monday',
              hint: s.mondayFirst
                  ? 'ISO week numbers'
                  : 'Sunday first, US week numbers',
              value: s.mondayFirst,
              onChanged: (v) => s.mondayFirst = v,
            ),
            const Hairline(),
            SwitchRow(
              label: 'Share button',
              hint: 'Show Share under results',
              value: s.showShare,
              onChanged: (v) => s.showShare = v,
            ),
          ],
        ),
      ),
    ];

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: contentMaxWidth(context)),
        child: PageScroll(
          padding: pagePadding(context, tabBar: true),
          children: [
            if (isWide) ...[
              // Two columns of equal height, their last cards stretched so
              // both end level; Preferences runs full width beneath.
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          ...lookColumn.sublist(0, lookColumn.length - 1),
                          Expanded(child: lookColumn.last),
                        ],
                      ),
                    ),
                    Gap(20.dp),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          preferencesColumn[0],
                          Expanded(child: preferencesColumn[1]),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              ...preferencesColumn.sublist(2),
            ] else ...[
              ...lookColumn,
              ...preferencesColumn,
            ],
            Gap(24.dp),
            Center(
              child: Text(
                'Dates · ${dayOfYear(DateTime.now())} days into ${DateTime.now().year}',
                style: TextStyle(color: p.sub, fontSize: 12.sp),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
