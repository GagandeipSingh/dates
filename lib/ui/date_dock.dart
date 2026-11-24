import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../state/today.dart';
import 'motion.dart';
import 'one_ui.dart';

/// One place in the [DateDock]: which tab it opens, and how it looks.
@immutable
class DockItem {
  const DockItem({
    required this.tab,
    required this.label,
    this.icon,
    this.activeIcon,
    this.kind = DockIconKind.plain,
  });

  /// The tab index this item selects (the dock's ORDER is visual only).
  final int tab;
  final String label;

  /// Outline icon, and the filled one it morphs to when selected. Null on
  /// the calendar tile ([DockIconKind.today]).
  final IconData? icon;
  final IconData? activeIcon;
  final DockIconKind kind;
}

/// What an item does when it is chosen, beyond turning on.
enum DockIconKind {
  /// Nothing more.
  plain,

  /// A tiny wiggle (a tool picked up).
  wiggle,

  /// A 60 degree turn (a gear).
  turn,

  /// The live calendar tile: today's day number and weekday, flipped like a
  /// tear-off page when tapped again.
  today,
}

/// The "date dock": Dates' bottom navigation, as split pills.
///
/// A centred row of SEPARATE shapes floating [bottomGap] dp above the
/// system navigation, [gap] dp apart, no shared container: the open tab is
/// a wide pill (an accent circle holding its icon, then its label), every
/// other tab a round [height] dp button with its outline icon alone. White
/// with a faint border and one soft shadow in light, #2C2C30 (a step above
/// the cards) with a hairline and a deeper shadow in dark; nothing blurs.
///
/// A switch is one move: the old pill shrinks back to a circle while the
/// new one widens, on a near-critical spring (~280ms, no wobble); the
/// label fades and slides in behind the widening, and the accent circle
/// fades across. The icon never moves: a round button's centre is exactly
/// where the pill's circle sits. Choosing an item plays its touch once
/// (the gear turns 60 degrees, the tools icon wiggles, outlines fill);
/// tapping the open item again calls [onReselect] (the shell scrolls that
/// tab to its top) and flips Today like a calendar page. Haptic on every
/// change.
///
/// Nothing sits behind the row: no bar, band or scrim. The shapes float
/// over the page with one soft shadow each, and the page scrolls on under
/// them to the screen's edge.
///
/// Today's icon is a calendar glyph holding today's day number, live (it
/// reads [TodayScope], so it turns over at midnight with the app open).
/// Reduced motion: everything instant. Every shape is a 48dp+ target that
/// announces its label (Today: the full date) and selected state, with a
/// tooltip. The open label is never cut: on a narrow phone at large text
/// the round buttons and gaps tighten first, then the label scales down a
/// little; the row never overflows.
class DateDock extends StatefulWidget {
  const DateDock({
    super.key,
    required this.items,
    required this.selected,
    required this.onSelected,
    this.onReselect,
  });

  /// In visual order, left to right.
  final List<DockItem> items;

  /// The selected TAB index (matched against [DockItem.tab]).
  final int selected;
  final ValueChanged<int> onSelected;
  final ValueChanged<int>? onReselect;

  /// Every shape's height, and a round button's width; [compact] and
  /// [compactGap] when the row would not fit a narrow phone at large text.
  static const double height = 64;
  static const double gap = 10;
  static const double compact = 52;
  static const double compactGap = 4;
  static const double sideInset = 16;
  static const double bottomGap = 12;

  /// Around the open pill's label.
  static const double labelGap = 10;
  static const double labelEnd = 20;

  /// The space the dock takes at the foot of the screen, for content to
  /// pad itself above it: the row, its gap and the system inset.
  static double footprint(BuildContext context) =>
      height + bottomGap + MediaQuery.paddingOf(context).bottom;

  @override
  State<DateDock> createState() => _DateDockState();
}

class _DateDockState extends State<DateDock> {
  // The widening and shrinking: ratio 0.92, at rest in ~240ms (280 read
  // as slow on a low-end phone, 2026-11-24).
  static final SpringDescription _widen = springFor(0.92, 240);

  static const _labelStyle = TextStyle(
    fontSize: 16,
    height: 1.2,
    fontWeight: FontWeight.w600,
  );

  void _tap(DockItem it) {
    if (it.tab == widget.selected) {
      widget.onReselect?.call(it.tab);
      return;
    }
    HapticFeedback.selectionClick();
    widget.onSelected(it.tab);
  }

  /// [label]'s width at the user's text size, in the app's font.
  double _labelWidth(BuildContext context, String label) {
    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: _labelStyle.copyWith(
          fontFamily: DefaultTextStyle.of(context).style.fontFamily,
        ),
      ),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final w = tp.width;
    tp.dispose();
    return w;
  }

  @override
  Widget build(BuildContext context) {
    final p = OnePalette.of(context);
    final bottom = MediaQuery.paddingOf(context).bottom + DateDock.bottomGap;
    final n = widget.items.length;
    final open = widget.items.firstWhere(
      (i) => i.tab == widget.selected,
      orElse: () => widget.items.first,
    );
    // No band: the shapes float over the page with nothing behind them.
    // Only the system inset gets a floor (solid page colour), so cards
    // never scroll under the back/home/recents keys (owner's call,
    // 2026-11-23: "only under system navigation bar, not under ours").
    final total = DateDock.height + bottom;
    final inset = MediaQuery.paddingOf(context).bottom;
    final solidFrom = total <= 0
        ? 1.0
        : ((total - inset) / total).clamp(0.0, 1.0);
    final bg = p.background;
    return SizedBox(
      height: total,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [bg.withValues(alpha: 0), bg.withValues(alpha: 0), bg, bg],
            stops: [0, solidFrom, solidFrom, 1],
          ),
        ),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            DateDock.sideInset,
            0,
            DateDock.sideInset,
            bottom,
          ),
          child: LayoutBuilder(
            builder: (context, c) {
              final full = c.maxWidth;
              // The open label never ellipsizes. If the row does not fit at
              // full size, the round buttons and gaps tighten first; only
              // then does the label itself scale down (to about 12sp).
              final label = _labelWidth(context, open.label);
              double pillFor(double size) =>
                  size + DateDock.labelGap + label + DateDock.labelEnd;
              var size = DateDock.height;
              var gap = DateDock.gap;
              if (pillFor(size) + (n - 1) * (size + gap) > full) {
                size = DateDock.compact;
                gap = DateDock.compactGap;
              }
              final room = full - (n - 1) * (size + gap);
              final pill = math.max(size, math.min(room, pillFor(size)));
              final labelSpace = math.max(
                0.0,
                pill - size - DateDock.labelGap - DateDock.labelEnd + 4,
              );
              return Align(
                alignment: Alignment.bottomCenter,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < n; i++) ...[
                      if (i > 0) SizedBox(width: gap),
                      // Each shape repaints alone while it widens or
                      // shrinks; the still one and the page keep their
                      // pictures.
                      RepaintBoundary(
                        child: _shape(
                          context,
                          p,
                          widget.items[i],
                          size,
                          pill,
                          labelSpace,
                        ),
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _shape(
    BuildContext context,
    OnePalette p,
    DockItem it,
    double size,
    double wide,
    double labelSpace,
  ) {
    final on = it.tab == widget.selected;
    final now = TodayScope.now(context);
    final label = it.kind == DockIconKind.today
        ? '${it.label}, ${DateFormat('EEEE d MMMM y').format(now)}'
        : it.label;
    final accent = p.primary;
    // The open tab is tonal, not solid: a soft tint of the accent behind
    // an accent-coloured icon (a solid accent disc with a dark icon read as
    // harsh, owner's call 2026-11-23).
    final onAccent = accent;
    final tint = accent.withValues(alpha: p.dark ? 0.22 : 0.16);
    // 46dp at full size; the circle keeps its 9dp rim when compact.
    final circle = size - 18;
    const inset = 9.0;
    return Semantics(
      button: true,
      selected: on,
      label: label,
      excludeSemantics: true,
      onTap: () => _tap(it),
      child: Tooltip(
        message: it.label,
        excludeFromSemantics: true,
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (_) => _tap(it),
          child: OnePressScale(
            pressed: 0.94,
            child: SpringValue(
              key: ValueKey('dock-${it.tab}'),
              value: on ? 1 : 0,
              spring: _widen,
              builder: (context, raw, _) {
                final v = raw.clamp(0.0, 1.0);
                final ink = Color.lerp(p.sub, onAccent, v)!;
                // The label follows the widening: in over its later part,
                // sliding the last few dp.
                final lv = ((v - 0.25) / 0.75).clamp(0.0, 1.0);
                return Container(
                  width: size + (wide - size) * v,
                  height: size,
                  decoration: BoxDecoration(
                    // A step lighter than the cards in dark, so the shapes
                    // never blend into what they float over.
                    color: p.dark ? const Color(0xFF2C2C30) : Colors.white,
                    borderRadius: BorderRadius.circular(size / 2),
                    border: Border.all(
                      color: p.dark
                          ? const Color(0x1AFFFFFF)
                          : const Color(0x0F000000),
                    ),
                    // One soft shadow, so a shape floating over a card
                    // stands clear of it.
                    boxShadow: [
                      p.dark
                          ? const BoxShadow(
                              color: Color(0x80000000),
                              blurRadius: 24,
                              offset: Offset(0, 8),
                            )
                          : const BoxShadow(
                              color: Color(0x1A000000),
                              blurRadius: 20,
                              offset: Offset(0, 6),
                            ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(size / 2),
                    child: Stack(
                      clipBehavior: Clip.hardEdge,
                      children: [
                        // The accent circle: fades in under the icon.
                        Positioned(
                          left: inset,
                          top: inset,
                          width: circle,
                          height: circle,
                          child: Opacity(
                            opacity: v,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: tint,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                        ),
                        // The icon, always on the circle's centre (which
                        // is also a round button's centre).
                        Positioned(
                          left: inset,
                          top: inset,
                          width: circle,
                          height: circle,
                          child: Center(
                            child: it.kind == DockIconKind.today
                                ? _TodayGlyph(
                                    day: now.day,
                                    on: on,
                                    ink: ink,
                                    cut: tint,
                                  )
                                : _DockIcon(item: it, on: on, ink: ink),
                          ),
                        ),
                        // The label, laid out at its FINAL width and
                        // revealed by the widening: it never reflows or
                        // ellipsizes, and scales down only if the row
                        // cannot give it its natural width.
                        if (lv > 0)
                          Positioned(
                            left: size + DateDock.labelGap - 4,
                            top: 0,
                            bottom: 0,
                            width: labelSpace,
                            child: Opacity(
                              opacity: lv,
                              child: Transform.translate(
                                offset: Offset(-8 * (1 - lv), 0),
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    it.label,
                                    maxLines: 1,
                                    softWrap: false,
                                    style: _labelStyle.copyWith(
                                      color: accent,
                                      fontFamily: DefaultTextStyle.of(
                                        context,
                                      ).style.fontFamily,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// An item's icon: outline, morphing to filled when chosen, with its
/// one-shot touch ([DockIconKind]) played as it turns on.
class _DockIcon extends StatefulWidget {
  const _DockIcon({required this.item, required this.on, required this.ink});
  final DockItem item;
  final bool on;
  final Color ink;

  @override
  State<_DockIcon> createState() => _DockIconState();
}

class _DockIconState extends State<_DockIcon>
    with SingleTickerProviderStateMixin {
  // 0..1 per touch; the gear's turn accumulates so it never snaps back.
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
    value: 1,
  );
  int _turns = 0;

  @override
  void didUpdateWidget(_DockIcon old) {
    super.didUpdateWidget(old);
    if (widget.on && !old.on) {
      if (widget.item.kind == DockIconKind.turn) _turns++;
      if (MediaQuery.disableAnimationsOf(context)) {
        _c.value = 1;
      } else {
        _c.forward(from: 0);
      }
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  double _angle(double t) => switch (widget.item.kind) {
    // 60 degrees per selection, eased out, never back.
    DockIconKind.turn =>
      _turns == 0
          ? 0
          : (_turns - 1 + Curves.easeOutCubic.transform(t)) * math.pi / 3,
    // A quick, damped shake of about 8 degrees.
    DockIconKind.wiggle => 0.14 * math.sin(t * 3 * math.pi) * (1 - t),
    _ => 0,
  };

  @override
  Widget build(BuildContext context) {
    final it = widget.item;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) =>
          Transform.rotate(angle: _angle(_c.value), child: child),
      // Outline to filled: a short cross-fade with a slight grow.
      child: AnimatedSwitcher(
        duration: motion(context, kFadeMs),
        switchInCurve: kFade,
        switchOutCurve: kFade,
        transitionBuilder: (child, a) => FadeTransition(
          opacity: a,
          child: ScaleTransition(
            scale: Tween(begin: 0.85, end: 1.0).animate(a),
            child: child,
          ),
        ),
        child: Icon(
          widget.on ? (it.activeIcon ?? it.icon) : it.icon,
          key: ValueKey(widget.on),
          size: 26,
          color: widget.ink,
        ),
      ),
    );
  }
}

/// Today's icon: a calendar glyph with today's day number inside, outline
/// when idle, filled when chosen (the number then cut out in the circle's
/// colour). Tapped while chosen it flips over (rotateX, 280ms) like a torn
/// calendar page.
class _TodayGlyph extends StatefulWidget {
  const _TodayGlyph({
    required this.day,
    required this.on,
    required this.ink,
    required this.cut,
  });
  final int day;
  final bool on;
  final Color ink;

  /// The circle's colour, for the number on the filled glyph.
  final Color cut;

  @override
  State<_TodayGlyph> createState() => _TodayGlyphState();
}

class _TodayGlyphState extends State<_TodayGlyph>
    with SingleTickerProviderStateMixin {
  late final AnimationController _flip = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 280),
    value: 1,
  );

  ValueNotifier<int>? _retap;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The dock tells the glyph about a re-tap through this scope.
    final r = _DockRetap.maybeOf(context);
    if (r != null && r != _retap) {
      _retap?.removeListener(_onRetap);
      _retap = r..addListener(_onRetap);
    }
  }

  void _onRetap() {
    if (!widget.on || MediaQuery.disableAnimationsOf(context)) return;
    _flip.forward(from: 0);
  }

  @override
  void dispose() {
    _retap?.removeListener(_onRetap);
    _flip.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // A sun for Today: bold outline idle, solid when chosen.
    final glyph = Icon(
      PhosphorIconsFill.sunHorizon,
      size: 26,
      color: widget.ink,
    );
    return AnimatedBuilder(
      animation: _flip,
      child: glyph,
      builder: (context, child) {
        final t = Curves.easeInOutCubic.transform(_flip.value);
        return Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.003)
            ..rotateX(2 * math.pi * t),
          child: child,
        );
      },
    );
  }
}

/// Carries "the active item was tapped again" to the tile below.
class _DockRetap extends InheritedNotifier<ValueNotifier<int>> {
  const _DockRetap({required super.notifier, required super.child});

  static ValueNotifier<int>? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_DockRetap>()?.notifier;
}

/// Scrolls a kept tab back to its top when [signal] fires (its tab was
/// tapped again in the dock). Finds the tab's main scroll view itself, so
/// no tab has to hand over a controller. "Top" is where the page opens: a
/// page that starts with its title collapsed returns there, not above it.
class ScrollToTop extends StatefulWidget {
  const ScrollToTop({super.key, required this.signal, required this.child});
  final Listenable signal;
  final Widget child;

  @override
  State<ScrollToTop> createState() => _ScrollToTopState();
}

class _ScrollToTopState extends State<ScrollToTop> {
  @override
  void initState() {
    super.initState();
    widget.signal.addListener(_go);
  }

  @override
  void didUpdateWidget(ScrollToTop old) {
    super.didUpdateWidget(old);
    if (old.signal != widget.signal) {
      old.signal.removeListener(_go);
      widget.signal.addListener(_go);
    }
  }

  @override
  void dispose() {
    widget.signal.removeListener(_go);
    super.dispose();
  }

  void _go() {
    ScrollableState? found;
    void visit(Element e) {
      if (found != null) return;
      if (e is StatefulElement && e.state is ScrollableState) {
        final s = e.state as ScrollableState;
        if (s.position.axis == Axis.vertical) {
          found = s;
          return;
        }
      }
      e.visitChildren(visit);
    }

    (context as Element).visitChildren(visit);
    final s = found;
    if (s == null || !s.position.hasPixels) return;
    final top = math.max(
      s.position.minScrollExtent,
      math.min(
        s.widget.controller?.initialScrollOffset ?? 0,
        s.position.pixels,
      ),
    );
    if (s.position.pixels <= top) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      s.position.jumpTo(top);
    } else {
      s.position.animateTo(
        top,
        duration: const Duration(milliseconds: kSettleMs),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// [DateDock] with the re-tap wired to the Today tile's flip.
class DateDockHost extends StatefulWidget {
  const DateDockHost({
    super.key,
    required this.items,
    required this.selected,
    required this.onSelected,
    this.onReselect,
  });

  final List<DockItem> items;
  final int selected;
  final ValueChanged<int> onSelected;
  final ValueChanged<int>? onReselect;

  @override
  State<DateDockHost> createState() => _DateDockHostState();
}

class _DateDockHostState extends State<DateDockHost> {
  final _retap = ValueNotifier<int>(0);

  @override
  void dispose() {
    _retap.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _DockRetap(
    notifier: _retap,
    child: DateDock(
      items: widget.items,
      selected: widget.selected,
      onSelected: widget.onSelected,
      onReselect: (tab) {
        _retap.value++;
        widget.onReselect?.call(tab);
      },
    ),
  );
}
