import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import 'state/settings.dart';
import 'ui/home.dart';
import 'ui/scale.dart';

/// Clear iOS 26-style glass for the chrome (bars, tab bar, switches): a light
/// tint so the gradient shows through, real refraction, a touch of colour
/// fringing at the edge. The iOS 27 preset is ~53% white with heavy frost,
/// which read as a white bar rather than glass.
const _glass = GlassThemeData(
  light: GlassThemeVariant(
    settings: GlassThemeSettings(
      thickness: 26,
      blur: 2.5,
      glassColor: Color.fromRGBO(255, 255, 255, 0.10),
      lightAngle: 2.356,
      lightIntensity: 0.95,
      ambientStrength: 0.12,
      refractiveIndex: 1.28,
      saturation: 1.45,
      chromaticAberration: 0.025,
    ),
    quality: GlassQuality.premium,
  ),
  dark: GlassThemeVariant(
    settings: GlassThemeSettings(
      thickness: 24,
      blur: 2.5,
      glassColor: Color.fromRGBO(255, 255, 255, 0.07),
      lightAngle: 2.356,
      lightIntensity: 0.8,
      refractiveIndex: 1.28,
      saturation: 1.4,
      chromaticAberration: 0.02,
    ),
    quality: GlassQuality.premium,
  ),
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Portrait only. The manifest and Info.plist say the same, so the first
  // frame never draws sideways before this runs.
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  await LiquidGlassWidgets.initialize(enablePerformanceMonitor: false);
  final settings = await Settings.load();
  runApp(LiquidGlassWidgets.wrap(
    brightnessResolver: Theme.maybeBrightnessOf,
    // No adaptive quality: it drops glass to a flat frosted fallback while a
    // list scrolls, which is the "turns white, comes back later" effect.
    theme: _glass,
    child: SettingsScope(settings: settings, child: const DatesApp()),
  ));
}

class DatesApp extends StatelessWidget {
  const DatesApp({super.key});

  @override
  Widget build(BuildContext context) {
    final s = SettingsScope.of(context);
    ThemeData theme(Brightness b) => ThemeData(
          brightness: b,
          fontFamily: 'Inter',
          colorSchemeSeed: s.accent.color,
          useMaterial3: true,
          splashFactory: NoSplash.splashFactory,
          // The glass widgets draw Cupertino text; give it Inter too.
          cupertinoOverrideTheme: const CupertinoThemeData(
            textTheme: CupertinoTextThemeData(textStyle: TextStyle(fontFamily: 'Inter')),
          ),
        );
    return MaterialApp(
      title: 'Dates',
      debugShowCheckedModeBanner: false,
      theme: theme(Brightness.light),
      darkTheme: theme(Brightness.dark),
      themeMode: switch (s.appearance) {
        Appearance.system => ThemeMode.system,
        Appearance.light => ThemeMode.light,
        Appearance.dark => ThemeMode.dark,
      },
      // 1. Scale the whole tree to the design width, as the compass app does.
      // 2. screenutil inside it, designed for the same screen, so .sp/.dp
      //    stay ~1 and nothing is scaled twice.
      // 3. The glass scaffold is a Cupertino page, so Text gets no Material
      //    default style; one transparent Material above every route fixes it.
      builder: (context, child) => ScaleToWidth(
        child: ScreenUtilScope(
          child: Material(type: MaterialType.transparency, child: child),
        ),
      ),
      home: const HomeShell(),
    );
  }
}
