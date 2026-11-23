import 'package:flutter/material.dart';

import 'motion.dart';

import 'glass_surface.dart' show GlassPass;

/// The screen under a push drifts aside as ONE picture.
///
/// While a screen is being covered or uncovered, it is drawn once into a
/// picture and the picture is moved, so a push on a small phone moves one
/// live screen instead of two; the live screen is back the moment the
/// slide ends. iOS slides its screens the same way.
class StillWhileMoving extends StatefulWidget {
  const StillWhileMoving({
    super.key,
    required this.animation,
    required this.secondaryAnimation,
    required this.child,
  });

  final Animation<double> animation;
  final Animation<double> secondaryAnimation;
  final Widget child;

  @override
  State<StillWhileMoving> createState() => _StillWhileMovingState();
}

class _StillWhileMovingState extends State<StillWhileMoving> {
  final _snap = SnapshotController();

  @override
  void initState() {
    super.initState();
    _listen(widget.animation, widget.secondaryAnimation);
    _update();
  }

  @override
  void didUpdateWidget(StillWhileMoving old) {
    super.didUpdateWidget(old);
    if (old.animation != widget.animation ||
        old.secondaryAnimation != widget.secondaryAnimation) {
      _unlisten(old.animation, old.secondaryAnimation);
      _listen(widget.animation, widget.secondaryAnimation);
      _update();
    }
  }

  // Values as well as statuses: the screen underneath learns of a push
  // through a proxy whose parent is swapped in before the slide starts, and
  // that swap does not always report a status change.
  void _listen(Animation<double> a, Animation<double> b) {
    for (final x in [a, b]) {
      x.addListener(_update);
      x.addStatusListener(_onStatus);
    }
  }

  void _unlisten(Animation<double> a, Animation<double> b) {
    for (final x in [a, b]) {
      x.removeListener(_update);
      x.removeStatusListener(_onStatus);
    }
  }

  void _onStatus(AnimationStatus _) => _update();

  // A finger dragging the screen back (the edge swipe) moves the
  // controller by hand; its status is then forward or reverse too.
  //
  // Only the screen UNDERNEATH is a picture. The arriving screen stays live
  // so its content can assemble as it slides in (StaggerIn): a picture of
  // it taken on the first frame would slide in blank. Its flat blocks are
  // cheap to draw.
  void _update() =>
      _snap.allowSnapshotting = widget.secondaryAnimation.isAnimating;

  @override
  void dispose() {
    _unlisten(widget.animation, widget.secondaryAnimation);
    _snap.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SnapshotWidget(
    controller: _snap,
    // Anything that cannot be a picture is simply drawn live.
    mode: SnapshotMode.permissive,
    child: GlassPass(controller: _snap, child: widget.child),
  );
}

/// How a screen arrives and leaves: shared axis X. The arriving screen
/// slides in [pageShift] dp from the right and fades in over the first part
/// of the move; the screen underneath drifts [pageShift] dp left as one
/// still picture ([StillWhileMoving]). Back is the same move reversed.
/// While a finger drives it (Android's predictive back) it follows the
/// finger linearly; otherwise it rides [pageCurve].
///
/// Only the ARRIVING screen fades: both fading at once would show the
/// window's black through the middle of the move.
const int pageMs = 300;
const int pageBackMs = 260;
const double pageShift = 30;
const Curve pageCurve = Curves.easeOutCubic;

Widget sharedAxisX(
  BuildContext context,
  Animation<double> animation,
  Animation<double> secondaryAnimation,
  Widget child, {
  bool linear = false,
}) {
  // Read straight from the animations: a route rebuilds its transitions
  // every frame of them, and a CurvedAnimation made here would add a
  // listener per frame.
  double move(Animation<double> a) => linear
      ? a.value
      : a.status == AnimationStatus.reverse
      ? pageCurve.flipped.transform(a.value)
      : pageCurve.transform(a.value);
  final dx =
      pageShift * (1 - move(animation)) - pageShift * move(secondaryAnimation);
  final f = animation.isCompleted
      ? 1.0
      : linear
      ? animation.value
      : kFade.transform((animation.value / 0.6).clamp(0.0, 1.0));
  // One fixed structure at rest and in motion: swapping wrappers would
  // rebuild the whole screen (and lose its state) when the move ends. At
  // opacity 1 and no offset both cost nothing.
  return Opacity(
    opacity: f.clamp(0.0, 1.0),
    child: Transform.translate(offset: Offset(dx, 0), child: child),
  );
}

/// [sharedAxisX] for any route the theme builds (a MaterialPageRoute from
/// a package): no Material zoom or Cupertino slide is left in the app.
class AppPageTransitionsBuilder extends PageTransitionsBuilder {
  const AppPageTransitionsBuilder();

  @override
  Duration get transitionDuration => const Duration(milliseconds: pageMs);

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => sharedAxisX(
    context,
    animation,
    secondaryAnimation,
    child,
    linear: route.popGestureInProgress,
  );
}

/// The app's screen push, used for every route (test/motion_test): shared
/// axis X ([sharedAxisX]), [pageMs] in and [pageBackMs] back. The screen
/// underneath slides as a still picture; the arriving one stays live so its
/// content can assemble (PageScroll's StaggerIn) as it lands. Android's
/// predictive back drives the same move with the finger. With reduced
/// motion the screen simply appears.
class AppPageRoute<T> extends PageRoute<T> {
  AppPageRoute({required this.builder, super.settings});

  final WidgetBuilder builder;

  @override
  Duration get transitionDuration =>
      _reduce ? Duration.zero : const Duration(milliseconds: pageMs);

  @override
  Duration get reverseTransitionDuration =>
      _reduce ? Duration.zero : const Duration(milliseconds: pageBackMs);

  bool get _reduce {
    final ctx = navigator?.context;
    return ctx != null && MediaQuery.maybeDisableAnimationsOf(ctx) == true;
  }

  @override
  bool get opaque => true;

  @override
  bool get maintainState => true;

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  @override
  bool canTransitionTo(TransitionRoute<dynamic> nextRoute) =>
      nextRoute is AppPageRoute;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) => Semantics(
    scopesRoute: true,
    explicitChildNodes: true,
    child: builder(context),
  );

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => sharedAxisX(
    context,
    animation,
    secondaryAnimation,
    StillWhileMoving(
      animation: animation,
      secondaryAnimation: secondaryAnimation,
      child: child,
    ),
    linear: popGestureInProgress,
  );
}
