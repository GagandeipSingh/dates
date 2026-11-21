import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'state/app_update.dart';
import 'state/settings.dart';
import 'ui/glass_surface.dart' show GlassLens;
import 'ui/home.dart';
import 'ui/page_motion.dart';
import 'ui/scale.dart';
import 'ui/update_prompt.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
      systemNavigationBarContrastEnforced: false,
    ),
  );
  // Phones stay portrait. Tablets, unfolded foldables and desktops
  // (shortest side >= 600 dp) turn freely.
  final view = WidgetsBinding.instance.platformDispatcher.views.firstOrNull;
  final isLargeScreen =
      view != null &&
      view.physicalSize.shortestSide > 0 &&
      (view.physicalSize.shortestSide / view.devicePixelRatio) >= 600;
  if (!isLargeScreen) {
    await SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
  }
  // The liquid glass lens; without it (no Impeller) glass is frost only.
  await GlassLens.load();
  final settings = await Settings.load();
  runApp(SettingsScope(settings: settings, child: const DatesApp()));
  // Play's own "Update available" sheet, when Play has a newer version.
  AppUpdater.instance
    ..onReady = () async {
      final context = DatesApp.navigatorKey.currentContext;
      if (context == null || !context.mounted) return false;
      return showUpdateReady(context);
    }
    ..start();
}

class DatesApp extends StatelessWidget {
  const DatesApp({super.key});

  /// For prompts raised from outside the tree (the update-ready sheet).
  static final navigatorKey = GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    final s = SettingsScope.of(context);
    ThemeData theme(Brightness b) => ThemeData(
      brightness: b,
      fontFamily: 'Inter',
      colorSchemeSeed: s.accent.color,
      useMaterial3: true,
      splashFactory: NoSplash.splashFactory,
      // Screens slide in from the right and can be swiped back, as on
      // iOS, on every platform.
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.linux: CupertinoPageTransitionsBuilder(),
        },
      ),
      cupertinoOverrideTheme: const CupertinoThemeData(
        textTheme: CupertinoTextThemeData(
          textStyle: TextStyle(fontFamily: 'Inter'),
        ),
      ),
    );
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'Dates',
      debugShowCheckedModeBanner: false,
      scrollBehavior: const _StillScroll(),
      theme: theme(Brightness.light),
      darkTheme: theme(Brightness.dark),
      themeMode: switch (s.appearance) {
        Appearance.system => ThemeMode.system,
        Appearance.light => ThemeMode.light,
        Appearance.dark => ThemeMode.dark,
      },
      // 1. The phone's font size is honoured up to 1.25x: the app already
      //    scales to the screen, and its bars have fixed heights.
      // 2. Scale the whole tree to the design width, as the compass app does.
      // 3. screenutil inside it, designed for the same screen, so .sp/.dp
      //    stay ~1 and nothing is scaled twice.
      // 4. One transparent Material above every route gives Text a style.
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        return MediaQuery(
          data: mq.copyWith(
            textScaler: mq.textScaler.clamp(
              minScaleFactor: 1.0,
              maxScaleFactor: 1.25,
            ),
          ),
          child: ScaleToWidth(
            child: ScreenUtilScope(
              child: Material(type: MaterialType.transparency, child: child),
            ),
          ),
        );
      },
      // The home screen is the same kind of route as every tool screen, so
      // it slides aside under a push as one still picture too. (As a
      // MaterialPageRoute it was moved by Flutter's delegated transition,
      // which hides the slide from the screen's own transition.)
      onGenerateRoute: (_) => GlassPageRoute(builder: (_) => const HomeShell()),
    );
  }
}

/// Lists give a very slight bounce at their ends instead of Android's
/// stretch. The stretch redraws the list through an image filter, which
/// switches off the glass blur while it lasts, so every card flashed clear.
class _StillScroll extends MaterialScrollBehavior {
  const _StillScroll();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      const _SubtleBounce(parent: RangeMaintainingScrollPhysics());

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) => child;
}

class _SubtleBounce extends BouncingScrollPhysics {
  const _SubtleBounce({super.parent});

  @override
  _SubtleBounce applyTo(ScrollPhysics? ancestor) =>
      _SubtleBounce(parent: buildParent(ancestor));

  // iOS uses 0.52; 0.035 lets the list move only a few points past its end.
  @override
  double frictionFactor(double overscrollFraction) =>
      0.035 * (1 - overscrollFraction) * (1 - overscrollFraction);

  // Stiff and fully damped: back in place at once, no wobble.
  @override
  SpringDescription get spring =>
      SpringDescription.withDampingRatio(mass: 0.5, stiffness: 700, ratio: 1.0);
}
