import 'package:flutter/widgets.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

export 'package:flutter_screenutil/flutter_screenutil.dart' show SizeExtension;

/// Sizing comes from flutter_screenutil, running INSIDE [ScaleToWidth] with
/// the same design size, so `.dp` is ~1 and the tree scale does the work. `.sp` is screenutil's font size; `.dp` is a length scaled
/// the same way (screenutil's `.r`, the smaller of the width/height ratios,
/// so a tall or wide screen never stretches a shape).
extension Dp on num {
  double get dp => r;
}

/// The compass app's whole-tree scaling: the app is laid out for a
/// [designWidth]-dp screen (the Motorola Edge 60 it was tuned on) and the
/// result is scaled to the real one, so every phone shows the same
/// proportions. One scale for everything, the glass library's own controls
/// included, clamped so a small phone does not shrink text past reading and
/// a tablet does not balloon it.
class ScaleToWidth extends StatelessWidget {
  const ScaleToWidth({super.key, required this.child});
  final Widget child;

  static const designWidth = 418.0;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final f = (mq.size.width / designWidth).clamp(0.8, 1.3);
    if ((f - 1).abs() < 0.01) return child;
    final size = mq.size / f;
    return SizedBox.expand(
      child: FittedBox(
        fit: BoxFit.fill,
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: size.width,
          height: size.height,
          child: MediaQuery(
            data: mq.copyWith(
              size: size,
              devicePixelRatio: mq.devicePixelRatio * f,
              padding: mq.padding / f,
              viewPadding: mq.viewPadding / f,
              viewInsets: mq.viewInsets / f,
              systemGestureInsets: mq.systemGestureInsets / f,
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Configures screenutil from the INHERITED (already scaled) MediaQuery.
/// ScreenUtilInit reads the physical View, which is the real screen, so
/// under [ScaleToWidth] it scaled `.sp`/`.dp` a second time: 0.86 x 0.86 on
/// a 360 dp phone. Its `useInheritedMediaQuery` flag is ignored in 5.9.3.
///
/// Two rules, each a bug seen on the phone:
/// * Nothing builds until the size is real. The first frame can arrive
///   with an empty size; screenutil then scales by 0, and widgets built in
///   that frame drew at zero size (titles and cards missing until a tab
///   switch rebuilt them).
/// * When the size changes (rotation, split screen), every descendant is
///   rebuilt, because `.sp`/`.dp` are read at build time and nothing else
///   tells a widget they changed.
class ScreenUtilScope extends StatefulWidget {
  const ScreenUtilScope({super.key, required this.child});
  final Widget child;

  @override
  State<ScreenUtilScope> createState() => _ScreenUtilScopeState();
}

class _ScreenUtilScopeState extends State<ScreenUtilScope> {
  Size? _configured;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    if (mq.size.isEmpty) return const SizedBox.shrink();
    if (_configured != mq.size) {
      final first = _configured == null;
      ScreenUtil.configure(
        data: mq,
        designSize: Size(ScaleToWidth.designWidth, mq.size.height),
        minTextAdapt: true,
        splitScreenMode: true,
      );
      _configured = mq.size;
      if (!first) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          void rebuild(Element e) {
            e.markNeedsBuild();
            e.visitChildren(rebuild);
          }
          (context as Element).visitChildren(rebuild);
        });
      }
    }
    return widget.child;
  }
}
