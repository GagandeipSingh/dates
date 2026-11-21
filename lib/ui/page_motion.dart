import 'package:flutter/cupertino.dart';

import 'glass_surface.dart' show GlassPass;

/// A screen that slides in and out as ONE picture.
///
/// Every card here is glass, and glass re-reads and re-blurs the screen
/// behind it on each frame it moves. A push moved two whole screens of it
/// (the new one sliding in, the old one sliding aside), every frame, and
/// the open stuttered. While either slide runs, the screen is drawn once
/// into a picture and the picture is moved; the live screen is back the
/// moment the slide ends. iOS slides its screens the same way.
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
  void _update() => _snap.allowSnapshotting =
      widget.animation.isAnimating || widget.secondaryAnimation.isAnimating;

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

/// The app's screen push: iOS's slide, moving a still picture of each screen.
class GlassPageRoute<T> extends CupertinoPageRoute<T> {
  GlassPageRoute({required super.builder});

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => super.buildTransitions(
    context,
    animation,
    secondaryAnimation,
    StillWhileMoving(
      animation: animation,
      secondaryAnimation: secondaryAnimation,
      child: child,
    ),
  );
}
