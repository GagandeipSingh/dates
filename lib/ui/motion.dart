import 'dart:math' as math;

import 'package:flutter/physics.dart';
import 'package:flutter/widgets.dart';

import 'glass_surface.dart';

/// The app's motion, after iOS: things that MOVE (slide, grow, rotate,
/// settle into a new shape) do it on a real spring that runs past its mark
/// once and settles back, so the UI feels physical rather than tweened.
///
/// Only motion gets the spring. A fade or a colour change must never
/// overshoot (an opacity past 1 is an error, a colour past its target is a
/// flicker), so those keep a plain ease.
///
/// A cubic with a bump in it was tried first and overshot by ~2%: on a
/// 20dp change that is half a pixel, and nobody could see it.
class SpringCurve extends Curve {
  const SpringCurve({required this.dampingRatio, this.stiffness = 180});

  /// 1 settles without passing the mark; lower bounces more.
  final double dampingRatio;
  final double stiffness;

  /// How long the spring takes to come to rest, in seconds: an animation
  /// using this curve should last about this long.
  double get settle => 4.6 / (dampingRatio * math.sqrt(stiffness));

  @override
  double transformInternal(double t) {
    final sim = SpringSimulation(
      SpringDescription(
        mass: 1,
        stiffness: stiffness,
        damping: 2 * dampingRatio * math.sqrt(stiffness),
      ),
      0,
      1,
      0,
    );
    return sim.x(t * settle);
  }
}

/// The everyday spring: one visible bounce (about 12% past the mark).
const Curve kSpring = SpringCurve(dampingRatio: 0.55);

/// A gentler spring for big surfaces (sheets, toasts), where a large
/// overshoot reads as a wobble (about 4%).
const Curve kSpringSoft = SpringCurve(dampingRatio: 0.7);

/// How long [kSpring] / [kSpringSoft] take to settle.
const int kSpringMs = 620;
const int kSpringSoftMs = 520;

/// [ms] of motion, or none when the user has asked for reduced motion.
Duration motion(BuildContext context, int ms) =>
    MediaQuery.disableAnimationsOf(context)
    ? Duration.zero
    : Duration(milliseconds: ms);

/// A piece of UI arriving (a bar, a field, a row of chips): it springs in
/// from [from] (dp) the first time it is built. Give it a new key to play
/// again. Moved, never faded: glass inside a fade flashes white, and a
/// transform the child repaints under keeps its glass in step.
class SpringIn extends StatelessWidget {
  const SpringIn({
    super.key,
    required this.from,
    required this.child,
    this.soft = false,
    this.scaleFrom = 1,
  });

  final Offset from;

  /// The size it starts at (1: full size), growing on the same spring.
  final double scaleFrom;
  final Widget child;

  /// The gentler spring, for a large surface.
  final bool soft;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: soft ? kSpringSoftMs : kSpringMs),
      curve: soft ? kSpringSoft : kSpring,
      child: child,
      // GlassFollow repaints the glass inside on every step, so its edge
      // moves with the card instead of a frame behind (a white rim flash).
      builder: (context, v, child) => GlassFollow(
        tick: v,
        child: Transform.translate(
          offset: from * (1 - v),
          child: scaleFrom == 1
              ? child
              : Transform.scale(
                  scale: scaleFrom + (1 - scaleFrom) * v,
                  child: child,
                ),
        ),
      ),
    );
  }
}

/// A number that moves to [value] on a real spring and KEEPS ITS SPEED when
/// the target changes mid-flight, as iOS springs do. A tween restarts from
/// rest every time, so a quick second tap jerked; this carries on smoothly.
class SpringValue extends StatefulWidget {
  const SpringValue({
    super.key,
    required this.value,
    required this.builder,
    this.child,
    this.dampingRatio = 0.55,
    this.stiffness = 180,
  });

  final double value;
  final double dampingRatio;
  final double stiffness;
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
    final k = widget.stiffness;
    _c.animateWith(
      SpringSimulation(
        SpringDescription(
          mass: 1,
          stiffness: k,
          damping: 2 * widget.dampingRatio * math.sqrt(k),
        ),
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

/// Where a finger is on the glass being pressed, and how strongly: the
/// nearest [GlassSurface] below lights up around that point, as iOS glass
/// glows under a touch.
class PressGlow extends InheritedWidget {
  const PressGlow({
    super.key,
    required this.point,
    required this.strength,
    required super.child,
  });

  final Offset? point;
  final double strength;

  static PressGlow? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PressGlow>();

  @override
  bool updateShouldNotify(PressGlow old) =>
      old.point != point || old.strength != strength;
}

/// Whether this screen gets the wide (tablet) layout: a tablet, an
/// unfolded foldable, a phone on its side, a desktop window. One test for
/// every screen, in the app's own scaled units.
///
/// 600 is the common tablet breakpoint. It was 720, which an unfolded
/// foldable (about 790 wide, then scaled 1.3x up to about 608) never
/// reached, so it was laid out as a stretched phone.
bool isWideLayout(BuildContext context) =>
    MediaQuery.sizeOf(context).width >= 600;
