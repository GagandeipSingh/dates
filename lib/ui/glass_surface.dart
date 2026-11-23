import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'one_ui.dart';

/// The app's surfaces, in One UI's flat material.
///
/// The name is kept from the liquid glass this replaced so no screen had to
/// change its calls; nothing here is glass any more. One UI is fast on small
/// processors because its surfaces are solid colour, so a surface never
/// samples or blurs the screen behind it:
/// * a card or row ([thick] false) is a focus block: the block colour on the
///   grey (light) or near-black (dark) field, no shadow;
/// * a floating control or bar ([thick] true: a toolbar, a toast, a sheet)
///   is the same solid colour lifted by one small static shadow in light
///   mode and a 1px tonal edge in dark mode, where a shadow would not show;
/// * a filled control ([gradient], or a strong [tint]) is a solid fill;
/// * [lit] is a pressed or selected state: One UI's grey press veil.
/// Surfaces may nest freely: each is just a filled shape.
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    required this.radius,
    this.padding = EdgeInsets.zero,
    this.tint,
    this.gradient,
    this.thick = false,
    this.lit = false,
    this.blur,
    this.edgeless = false,
  });

  final Widget child;
  final double radius;
  final EdgeInsetsGeometry padding;
  final Color? tint;

  /// A fill in place of [tint]: e.g., the accent buttons. One UI's contained
  /// buttons are flat, so its colours are averaged into one solid fill.
  final Gradient? gradient;
  final bool thick;
  final bool lit;

  /// Unused: kept so existing calls compile. Nothing blurs.
  final double? blur;

  /// A surface that runs off the screen (the strip behind the nav buttons):
  /// no rounded edge and no shadow.
  final bool edgeless;

  /// The solid colour a [tint] or [gradient] resolves to, over [base].
  static Color fillOf({required Color base, Color? tint, Gradient? gradient}) {
    if (gradient != null && gradient.colors.isNotEmpty) {
      final c = Color.lerp(gradient.colors.first, gradient.colors.last, 0.5)!;
      return c.withValues(alpha: 1);
    }
    if (tint != null) {
      // A translucent tint was a wash over glass: laid over the block
      // colour instead, it keeps its look without letting anything through.
      return Color.alphaBlend(tint, base);
    }
    return base;
  }

  @override
  Widget build(BuildContext context) {
    final p = OnePalette.of(context);
    final hc = MediaQuery.highContrastOf(context);
    final base = thick ? (p.dark ? p.popup : p.block) : p.block;
    var fill = fillOf(base: base, tint: tint, gradient: gradient);
    if (lit) fill = Color.alphaBlend(p.pressed, fill);
    final shape = BorderRadius.circular(edgeless ? 0 : radius);
    final floating = thick && !edgeless;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: fill,
        borderRadius: shape,
        border: hc
            ? Border.all(color: p.ink.withValues(alpha: 0.7), width: 1.5)
            : (floating && p.dark && gradient == null
                  ? Border.all(color: p.divider, width: 1)
                  : null),
        // SESL elevation 2-4 for a floating control: one small shadow that
        // never animates. Dark mode has none (it cannot be seen on black).
        boxShadow: floating && !p.dark && !hc
            ? const [
                BoxShadow(
                  color: Color(0x1A000000),
                  blurRadius: 6,
                  offset: Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: ClipRRect(
        borderRadius: shape,
        clipBehavior: radius > 0 && !edgeless ? Clip.antiAlias : Clip.none,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

/// Marks a screen that slides as one still picture while [controller]
/// allows it (see page_motion.dart). Kept as the seam between the page
/// transition and the snapshot; it paints its child unchanged.
class GlassPass extends SingleChildRenderObjectWidget {
  const GlassPass({super.key, required this.controller, super.child});

  final SnapshotController controller;

  @override
  RenderGlassPass createRenderObject(BuildContext context) =>
      RenderGlassPass(controller, MediaQuery.devicePixelRatioOf(context));

  @override
  void updateRenderObject(BuildContext context, RenderGlassPass renderObject) {
    renderObject
      ..controller = controller
      ..pixelRatio = MediaQuery.devicePixelRatioOf(context);
  }
}

class RenderGlassPass extends RenderProxyBox {
  RenderGlassPass(this.controller, this.pixelRatio);

  SnapshotController controller;
  double pixelRatio;

  bool get active => controller.allowSnapshotting;
}
