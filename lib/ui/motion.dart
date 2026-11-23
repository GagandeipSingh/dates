import 'dart:math' as math;

import 'package:flutter/physics.dart';
import 'package:flutter/widgets.dart';

import 'one_ui.dart';

// The app's motion, in one place.
//
// Character: a well-made instrument. Everything everyday is quick in and
// quick out, physical but with no visible wobble: near-critically damped
// springs that land on their mark (at most ~1% past it, below a pixel on
// anything this app moves). The one place Dates is allowed to feel alive is
// the thing the user came for: the numbers. A result counts to its new
// value, a progress bar fills once, a countdown ticks without disturbing
// the card around it.
//
// Rules every widget here keeps:
// * transform and opacity only: no blur, shader or BackdropFilter, and a
//   RepaintBoundary under anything that moves every frame;
// * a fade or colour change never overshoots (an opacity past 1 is an
//   error, a colour past its target a flicker): plain ease-out;
// * nothing waits for motion: a child is live and tappable from frame one;
// * reduced motion (MediaQuery.disableAnimations) makes all of it instant.
//
// The old motion was a 620ms spring with ~12% bounce on everything; the
// owner found it toy-like and slow. test/motion_test.dart holds each rule
// to its numbers.

// ───────────────────────────────────────────── Springs

/// How far into its spring an animation counts as at rest: the residual
/// error falls below 0.3% of the distance. [SpringCurve] and [springFor]
/// share it, so a curve and a physics spring of the same ratio and length
/// are the same motion.
double _settleFactor(double ratio) => ratio >= 0.999
    ? 8.4 // critically damped: (1 + wT)e^-wT = 0.003
    : math.log(1 / (0.003 * math.sqrt(1 - ratio * ratio)));

/// A spring with damping [ratio] that comes to rest in [ms]: for motion
/// that must keep its speed when retargeted mid-flight ([SpringValue], the
/// press release, the tab pill).
SpringDescription springFor(double ratio, int ms) {
  final w = _settleFactor(ratio) / (ratio * ms / 1000);
  return SpringDescription(mass: 1, stiffness: w * w, damping: 2 * ratio * w);
}

/// A spring as a [Curve] for a fixed-length animation: damping [ratio],
/// at rest by t = 1 (normalised so it ends exactly on 1, with no jump on
/// the last frame). The animation's length is given separately.
class SpringCurve extends Curve {
  const SpringCurve(this.ratio);

  /// 1 lands without passing the mark; 0.82 passes it by about 1%.
  final double ratio;

  @override
  double transformInternal(double t) {
    final w = _settleFactor(ratio) / ratio;
    final sim = SpringSimulation(
      SpringDescription(mass: 1, stiffness: w * w, damping: 2 * ratio * w),
      0,
      1,
      0,
    );
    return sim.x(t) / sim.x(1);
  }
}

/// The everyday spring: page content, a pill sliding across a track, a
/// press letting go, a figure rising in. Near-critical (about 1% past the
/// mark, invisible), at rest in [kSnapMs].
const double kSnapRatio = 0.82;
const int kSnapMs = 360;
const Curve kSnap = SpringCurve(kSnapRatio);
final SpringDescription kSnapSpring = springFor(kSnapRatio, kSnapMs);

/// For big surfaces (a sheet, the bottom bar, a toast): a touch softer and
/// longer, so a large area arrives rather than snaps. No overshoot to see.
const double kSettleRatio = 0.9;
const int kSettleMs = 400;
const Curve kSettle = SpringCurve(kSettleRatio);

/// Leaving: a sheet closing, a toast going. Quicker than arriving and
/// accelerating away, so the screen is given back at once.
const int kExitMs = 200;
const Curve kExit = Curves.easeInCubic;

/// Fades and colour changes: short, ease-out, never past the target.
const int kFadeMs = 180;
const Curve kFade = Curves.easeOutCubic;

/// Press feedback: down to [kPressScale] in [kPressMs], so it answers the
/// finger at once, and back up on [kSnapSpring].
const double kPressScale = 0.97;
const int kPressMs = 90;

/// A figure counting to its new value.
const int kCountMs = 450;
const Curve kCount = Curves.easeOutCubic;

/// A progress bar or ring filling the first time it is shown, and easing
/// to a new value after that.
const int kFillMs = 600;
const int kRefillMs = 250;

/// A screen's first appearance: each block [kStaggerStepMs] behind the one
/// above it, for at most [kStaggerCap] steps.
const int kStaggerStepMs = 30;
const int kStaggerCap = 6;

/// [ms] of motion, or none when the user has asked for reduced motion.
Duration motion(BuildContext context, int ms) =>
    MediaQuery.disableAnimationsOf(context)
    ? Duration.zero
    : Duration(milliseconds: ms);

/// Whether this screen gets the wide (tablet) layout: a tablet, an
/// unfolded foldable, a phone on its side, a desktop window. One test for
/// every screen, in the app's own scaled units.
///
/// 600 is the common tablet breakpoint. It was 720, which an unfolded
/// foldable (about 790 wide, then scaled 1.3x up to about 608) never
/// reached, so it was laid out as a stretched phone.
bool isWideLayout(BuildContext context) =>
    MediaQuery.sizeOf(context).width >= 600;

// ───────────────────────────────────────────── Everyday motion

/// Press feedback for a tappable object (a card, a tile, a pill): sinks to
/// [kPressScale] in [kPressMs] and comes back on the snap spring, with no
/// rebound. The shared kit's one, so every surface presses the same way.
typedef PressScale = OnePressScale;

/// A piece of UI arriving once (the bottom bar at launch): it moves in from
/// [from] (dp) on [kSettle]. Give it a new key to play again. Moved, not
/// faded: a transform on its own layer costs a frame nothing but a matrix.
class SpringIn extends StatelessWidget {
  const SpringIn({super.key, required this.from, required this.child});

  final Offset from;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: kSettleMs),
      curve: kSettle,
      child: RepaintBoundary(child: child),
      builder: (context, v, child) =>
          Transform.translate(offset: from * (1 - v), child: child),
    );
  }
}

/// A number that moves to [value] on a spring and KEEPS ITS SPEED when the
/// target changes mid-flight (a second tap while the first is landing
/// carries on instead of jerking from rest). [kSnapSpring] unless told.
class SpringValue extends StatefulWidget {
  const SpringValue({
    super.key,
    required this.value,
    required this.builder,
    this.child,
    this.spring,
  });

  final double value;
  final SpringDescription? spring;
  final Widget? child;
  final Widget Function(BuildContext context, double value, Widget? child)
  builder;

  @override
  State<SpringValue> createState() => _SpringValueState();
}

class _SpringValueState extends State<SpringValue>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController.unbounded(
    vsync: this,
    value: widget.value,
  );

  @override
  void didUpdateWidget(SpringValue old) {
    super.didUpdateWidget(old);
    if (widget.value == old.value) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _c.value = widget.value;
      return;
    }
    _c.animateWith(
      SpringSimulation(
        widget.spring ?? kSnapSpring,
        _c.value,
        widget.value,
        _c.velocity,
      ),
    );
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    child: widget.child,
    builder: (context, child) => widget.builder(context, _c.value, child),
  );
}

/// Content arriving with its screen: it rises [rise] dp on [kSnap] and
/// fades in over [kFadeMs], the [index]th item [kStaggerStepMs] behind the
/// first, so a page assembles top to bottom instead of landing as a slab.
///
/// Plays ONCE, on the screen's first appearance: a rebuild, a scroll or a
/// tab coming back never replays it, and a block a lazy list builds later
/// simply appears ([StaggerScope]). Items past [kStaggerCap] arrive with
/// the last staggered one, so a long page never waits. Never blocks a tap:
/// the child is live from the first frame. Nothing with reduced motion.
class StaggerIn extends StatefulWidget {
  const StaggerIn({
    super.key,
    required this.index,
    required this.child,
    this.rise = 14,
  });

  final int index;
  final Widget child;
  final double rise;

  @override
  State<StaggerIn> createState() => _StaggerInState();
}

class _StaggerInState extends State<StaggerIn>
    with SingleTickerProviderStateMixin {
  AnimationController? _c;
  late Animation<double> _move;
  late Animation<double> _fade;
  bool _decided = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_decided) return;
    _decided = true;
    if (MediaQuery.disableAnimationsOf(context)) return;
    // Built late (scrolled into a lazy list after the page arrived): no
    // arrival, the page is already here.
    if (!StaggerScope.fresh(context)) return;
    final int delay = kStaggerStepMs * math.min<int>(widget.index, kStaggerCap);
    final total = delay + kSnapMs;
    final start = delay / total;
    final c = _c = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: total),
    )..forward();
    _move = CurvedAnimation(
      parent: c,
      curve: Interval(start, 1, curve: kSnap),
    );
    _fade = CurvedAnimation(
      parent: c,
      curve: Interval(
        start,
        math.min(1, start + kFadeMs / total),
        curve: kFade,
      ),
    );
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    if (c == null) return widget.child;
    return AnimatedBuilder(
      animation: c,
      child: RepaintBoundary(child: widget.child),
      // One fixed structure from first frame to last: returning the bare
      // child at the end would rebuild everything inside (and lose its
      // state) the moment the arrival finished.
      builder: (context, child) => Opacity(
        opacity: c.isCompleted ? 1 : _fade.value.clamp(0.0, 1.0),
        child: Transform.translate(
          offset: Offset(0, c.isCompleted ? 0 : widget.rise * (1 - _move.value)),
          child: child,
        ),
      ),
    );
  }
}

/// The moment a page was first built: a [StaggerIn] inside it animates
/// only if it is built within [window] of that, so content a lazy list
/// builds on scroll simply appears where it belongs.
class StaggerScope extends StatefulWidget {
  const StaggerScope({super.key, required this.child});
  final Widget child;

  static const Duration window = Duration(milliseconds: 500);

  /// Whether something built now is part of its page's arrival.
  static bool fresh(BuildContext context) {
    final s = context.findAncestorStateOfType<_StaggerScopeState>();
    return s == null || s._age.elapsed < window;
  }

  @override
  State<StaggerScope> createState() => _StaggerScopeState();
}

class _StaggerScopeState extends State<StaggerScope> {
  final Stopwatch _age = Stopwatch()..start();

  @override
  Widget build(BuildContext context) => widget.child;
}

/// The bottom tabs' content: each tab is built the first time it is shown
/// and then KEPT (its scroll position and state survive a switch). A switch
/// is a short fade-through: the old tab fades out in [outMs] while the new
/// one fades in and grows from [scaleFrom] on [kSnap], [ms] in all. The two
/// overlap a little, so there is never an empty frame. Instant with reduced
/// motion.
class FadeThroughTabs extends StatefulWidget {
  const FadeThroughTabs({
    super.key,
    required this.index,
    required this.count,
    required this.builder,
  });

  final int index;
  final int count;
  final IndexedWidgetBuilder builder;

  /// The whole switch, the old tab's fade, and when the new one starts.
  static const int ms = 220;
  static const int outMs = 90;
  static const int inStartMs = 60;
  static const double scaleFrom = 0.98;

  @override
  State<FadeThroughTabs> createState() => _FadeThroughTabsState();
}

class _FadeThroughTabsState extends State<FadeThroughTabs>
    with SingleTickerProviderStateMixin {
  late final List<Widget?> _built = List.filled(widget.count, null);
  late int _from = widget.index;
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: FadeThroughTabs.ms),
    value: 1,
  );

  @override
  void didUpdateWidget(FadeThroughTabs old) {
    super.didUpdateWidget(old);
    if (widget.index == old.index) return;
    _from = old.index;
    if (MediaQuery.disableAnimationsOf(context)) {
      _c.value = 1;
    } else {
      _c.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _built[widget.index] ??= KeyedSubtree(
      key: ValueKey('tab-${widget.index}'),
      child: widget.builder(context, widget.index),
    );
    const total = FadeThroughTabs.ms;
    const start = FadeThroughTabs.inStartMs / total;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = _c.value;
        final moving = t < 1 && _from != widget.index;
        final inT = ((t - start) / (1 - start)).clamp(0.0, 1.0);
        final outT = (t * total / FadeThroughTabs.outMs).clamp(0.0, 1.0);
        return Stack(
          fit: StackFit.expand,
          children: [
            for (var i = 0; i < widget.count; i++)
              if (_built[i] != null)
                _layer(
                  i,
                  visible: i == widget.index || (moving && i == _from),
                  opacity: i == widget.index
                      ? (moving ? kFade.transform(inT) : 1)
                      : 1 - kFade.transform(outT),
                  scale: i == widget.index && moving
                      ? FadeThroughTabs.scaleFrom +
                            (1 - FadeThroughTabs.scaleFrom) *
                                kSnap.transform(inT)
                      : 1,
                ),
          ],
        );
      },
    );
  }

  Widget _layer(
    int i, {
    required bool visible,
    required double opacity,
    required double scale,
  }) {
    final live = i == widget.index;
    return Offstage(
      key: ValueKey('layer-$i'),
      offstage: !visible,
      child: TickerMode(
        enabled: visible,
        // Only the selected tab takes touches; one fading out ignores them.
        child: IgnorePointer(
          ignoring: !live,
          child: ExcludeSemantics(
            excluding: !live,
            child: Opacity(
              opacity: opacity.clamp(0.0, 1.0),
              child: Transform.scale(
                scale: scale,
                child: RepaintBoundary(child: _built[i]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ───────────────────────────────────────────── The numbers

/// Content that is REPLACED rather than counted (a date, a weekday, a
/// whole card for a new day): the old one slides up and out, the new one
/// rises in from below, as a calendar leaf turns. Keyed on [value]: the
/// same value never animates. The slide is [kSnap]; the cross-fade a plain
/// ease. Instant with reduced motion.
class RollSwitcher extends StatelessWidget {
  const RollSwitcher({
    super.key,
    required this.value,
    required this.child,
    this.ms = kSnapMs,
    this.distance = 0.3,
  });

  /// What identifies the content; a change rolls.
  final Object value;
  final Widget child;
  final int ms;

  /// How far it travels, as a fraction of its own height.
  final double distance;

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
    duration: motion(context, ms),
    // Passthrough: the content keeps the constraints it would have had
    // without the switcher (a card still stretches to its column).
    layoutBuilder: (current, previous) => Stack(
      fit: StackFit.passthrough,
      alignment: Alignment.topCenter,
      children: [...previous, ?current],
    ),
    transitionBuilder: (child, anim) {
      final incoming = child.key == ValueKey(value);
      return AnimatedBuilder(
        animation: anim,
        child: child,
        builder: (context, child) {
          final v = anim.value;
          // Incoming: up from below on the snap spring. Outgoing (its
          // animation runs 1 -> 0): up and away on a plain ease.
          final dy = incoming
              ? distance * (1 - kSnap.transform(v))
              : -distance * (1 - kFade.transform(v));
          return Opacity(
            opacity: kFade.transform(v.clamp(0.0, 1.0)),
            child: FractionalTranslation(
              translation: Offset(0, dy),
              child: child,
            ),
          );
        },
      );
    },
    child: KeyedSubtree(key: ValueKey(value), child: child),
  );
}

/// A figure that COUNTS to its new value when it changes (a day count, an
/// age, a total), keeping its format: [kCountMs] on [kCount], ease-out and
/// never past the target, since a count that overshoots shows a wrong
/// answer for a frame. A change mid-count carries on from the figure on
/// screen rather than restarting. Anything that is not one leading figure
/// (a date, a weekday, "3 years, 2 months") rolls instead.
///
/// A figure that appears AFTER its screen has arrived (a row switched on,
/// a result revealed) rises in by [rise] dp; one that arrives with its
/// screen rides the screen's own stagger, and one scrolled into view just
/// appears. Instant with reduced motion.
class CountText extends StatefulWidget {
  const CountText(
    this.text, {
    super.key,
    this.style,
    this.textAlign,
    this.maxLines,
  });

  final String text;
  final TextStyle? style;
  final TextAlign? textAlign;
  final int? maxLines;

  static const int ms = kCountMs;

  /// How far a late-arriving figure rises, in dp.
  static const double rise = 6;

  static final _sepChars = RegExp('[,  ]');

  /// The first run of digits (with group separators) in [s], or null.
  static RegExpMatch? figure(String s) =>
      RegExp('-?\\d{1,3}(?:[,  ]\\d{3})+|-?\\d+').firstMatch(s);

  @override
  State<CountText> createState() => _CountTextState();
}

class _CountTextState extends State<CountText> with TickerProviderStateMixin {
  late final AnimationController _c;
  AnimationController? _arrive;
  bool _decided = false;
  int _from = 0;
  int _to = 0;
  String _prefix = '', _suffix = '', _sep = ',';
  bool _grouped = false;
  bool _counting = false;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: CountText.ms),
      value: 1,
    );
    _read(widget.text);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_decided) return;
    _decided = true;
    if (MediaQuery.disableAnimationsOf(context)) return;
    // Part of the screen's arrival: the screen's stagger carries it.
    if (StaggerScope.fresh(context)) return;
    // Built because the list scrolled to it: it was always there.
    final scroll = Scrollable.maybeOf(context)?.position;
    if (scroll != null && scroll.isScrollingNotifier.value) return;
    _arrive = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: kSnapMs),
    )..forward();
  }

  void _read(String s) {
    final m = CountText.figure(s);
    final v = m == null
        ? null
        : int.tryParse(m[0]!.replaceAll(CountText._sepChars, ''));
    // Only a lone leading figure counts ("1,204 days", "38"): a date or
    // "3 years, 2 months" would pass through wrong values on the way, so
    // those roll instead.
    if (m == null ||
        v == null ||
        m.start != 0 ||
        s.substring(m.end).contains(RegExp(r'\d'))) {
      _counting = false;
      return;
    }
    _counting = true;
    _prefix = s.substring(0, m.start);
    _suffix = s.substring(m.end);
    final sep = CountText._sepChars.firstMatch(m[0]!);
    _grouped = sep != null;
    _sep = sep == null ? ',' : sep[0]!;
    _to = v;
  }

  @override
  void didUpdateWidget(CountText old) {
    super.didUpdateWidget(old);
    if (widget.text == old.text) return;
    final was = _counting ? _shown : null;
    final oldShape = (_prefix, _suffix);
    _read(widget.text);
    if (!_counting ||
        was == null ||
        oldShape != (_prefix, _suffix) ||
        MediaQuery.disableAnimationsOf(context)) {
      _c.value = 1;
      return;
    }
    _from = was;
    _c.forward(from: 0);
  }

  int get _shown => _c.isCompleted
      ? _to
      : (_from + (_to - _from) * kCount.transform(_c.value)).round();

  String _format(int v) {
    final d = v.abs().toString();
    if (!_grouped) return v.toString();
    final b = StringBuffer();
    for (var i = 0; i < d.length; i++) {
      if (i > 0 && (d.length - i) % 3 == 0) b.write(_sep);
      b.write(d[i]);
    }
    return '${v < 0 ? '-' : ''}$b';
  }

  @override
  void dispose() {
    _c.dispose();
    _arrive?.dispose();
    super.dispose();
  }

  Text _text(String s) => Text(
    s,
    style: widget.style,
    textAlign: widget.textAlign,
    maxLines: widget.maxLines,
  );

  Widget _figure() {
    if (!_counting) {
      return RollSwitcher(
        value: widget.text,
        ms: 260,
        distance: 0.5,
        child: _text(widget.text),
      );
    }
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) => _c.isCompleted
          ? _text(widget.text)
          : _text('$_prefix${_format(_shown)}$_suffix'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final a = _arrive;
    if (a == null) return _figure();
    return AnimatedBuilder(
      animation: a,
      child: _figure(),
      builder: (context, child) {
        final v = a.value;
        return Opacity(
          opacity: kFade.transform((v * kSnapMs / kFadeMs).clamp(0.0, 1.0)),
          child: Transform.translate(
            offset: Offset(0, CountText.rise * (1 - kSnap.transform(v))),
            child: child,
          ),
        );
      },
    );
  }
}

/// A fraction (a ring, a progress bar) that FILLS from empty when it first
/// appears ([kFillMs], ease-out), then eases to any new value
/// ([kRefillMs]). With an [id] it fills only the first time that id is
/// drawn in this run of the app (a Today ring does not refill on every
/// visit); without one, each new instance fills (a screen just opened).
/// Never past the target, since a bar at 103% states a wrong fact.
/// Instant with reduced motion.
class FillOnce extends StatefulWidget {
  const FillOnce({
    super.key,
    this.id,
    required this.value,
    required this.builder,
  });

  final String? id;
  final double value;
  final Widget Function(BuildContext context, double value) builder;

  static final Set<String> _seen = {};

  /// Forget what has filled (tests).
  static void reset() => _seen.clear();

  @override
  State<FillOnce> createState() => _FillOnceState();
}

class _FillOnceState extends State<FillOnce> {
  late final bool _fill = widget.id == null || FillOnce._seen.add(widget.id!);
  bool _built = false;

  @override
  Widget build(BuildContext context) {
    final first = !_built && _fill;
    _built = true;
    if (MediaQuery.disableAnimationsOf(context)) {
      return widget.builder(context, widget.value);
    }
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: first ? 0 : widget.value, end: widget.value),
      duration: Duration(milliseconds: first ? kFillMs : kRefillMs),
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => widget.builder(context, v),
    );
  }
}
