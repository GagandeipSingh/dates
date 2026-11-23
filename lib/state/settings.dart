import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Accent colours the user can pick. Each has a light and a dark gradient
/// behind the glass, so the refraction always has colour to bend.
class Accent {
  const Accent(this.name, this.color, this.light, this.dark);
  final String name;
  final Color color;
  final List<Color> light;
  final List<Color> dark;
}

const accents = <Accent>[
  Accent(
    'Coral',
    Color(0xFFF2564B),
    [
      Color(0xFFFFE3D6),
      Color(0xFFFFC7C2),
      Color(0xFFF6D3F0),
      Color(0xFFDCE4FF),
    ],
    [
      Color(0xFF2A0F17),
      Color(0xFF4A1625),
      Color(0xFF2B1640),
      Color(0xFF0F1530),
    ],
  ),
  Accent(
    'Ocean',
    Color(0xFF1E7BF2),
    [
      Color(0xFFD7ECFF),
      Color(0xFFC6DBFF),
      Color(0xFFD9D2FF),
      Color(0xFFCFF4EE),
    ],
    [
      Color(0xFF07152E),
      Color(0xFF0B2654),
      Color(0xFF1B1748),
      Color(0xFF052A2E),
    ],
  ),
  Accent(
    'Iris',
    Color(0xFF6A4CF5),
    [
      Color(0xFFE6E0FF),
      Color(0xFFD4CCFF),
      Color(0xFFF3D6F7),
      Color(0xFFD6E6FF),
    ],
    [
      Color(0xFF130E30),
      Color(0xFF241A57),
      Color(0xFF341544),
      Color(0xFF0E1A3A),
    ],
  ),
  Accent(
    'Mint',
    Color(0xFF14A37F),
    [
      Color(0xFFD5F5EA),
      Color(0xFFC9EEDF),
      Color(0xFFD8ECFF),
      Color(0xFFF1F6D2),
    ],
    [
      Color(0xFF06221B),
      Color(0xFF0A3A2D),
      Color(0xFF0B2338),
      Color(0xFF1E2A10),
    ],
  ),
  Accent(
    'Sunset',
    Color(0xFFF08A1D),
    [
      Color(0xFFFFEBD0),
      Color(0xFFFFD6B8),
      Color(0xFFFFCFD9),
      Color(0xFFF4E2FF),
    ],
    [
      Color(0xFF2A1606),
      Color(0xFF45220C),
      Color(0xFF3F1222),
      Color(0xFF231536),
    ],
  ),
  Accent(
    'Rose',
    Color(0xFFE5407F),
    [
      Color(0xFFFFDDEA),
      Color(0xFFFFCCE0),
      Color(0xFFEAD6FF),
      Color(0xFFFFE6D6),
    ],
    [
      Color(0xFF2B0A18),
      Color(0xFF4A1030),
      Color(0xFF2A1446),
      Color(0xFF331707),
    ],
  ),
  Accent(
    'Graphite',
    Color(0xFF4A5568),
    [
      Color(0xFFEDEFF3),
      Color(0xFFDDE2EA),
      Color(0xFFE6E3EE),
      Color(0xFFDCE6EC),
    ],
    [
      Color(0xFF0E1014),
      Color(0xFF1A1E26),
      Color(0xFF1C1A24),
      Color(0xFF111A1E),
    ],
  ),
];

/// Date formats on offer, as intl patterns. The label is what the user sees.
const dateFormats = <String>[
  'd MMM yyyy',
  'dd/MM/yyyy',
  'MM/dd/yyyy',
  'yyyy-MM-dd',
  'EEE, d MMM yyyy',
];

enum Appearance { system, light, dark }

/// Whether this platform has the daily date icon at all (Android only).
bool get dateIconSupported =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

/// The native "Daily date icon" switch. Native (DateIcon.kt) owns the value;
/// Dart only reads it at start and asks native to change it.
const dateIconChannel = MethodChannel('com.blessing.dates/date_icon');

class Settings extends ChangeNotifier {
  Settings._(this._prefs, this._dailyIcon);

  static Future<Settings> load() async {
    final prefs = await SharedPreferences.getInstance();
    var daily = true;
    if (dateIconSupported) {
      try {
        daily =
            await dateIconChannel.invokeMethod<bool>('getDailyIcon') ?? true;
      } on Exception {
        // No native side (a test, a host without the channel): the default.
      }
    }
    return Settings._(prefs, daily);
  }

  final SharedPreferences _prefs;

  /// "Daily date icon": the launcher icon shows today's date. Off keeps one
  /// fixed icon. Seeded from native at start; native is the source of truth.
  bool get dailyIcon => _dailyIcon;
  bool _dailyIcon;
  set dailyIcon(bool v) {
    if (v == _dailyIcon) return;
    _dailyIcon = v;
    notifyListeners();
    _sendDailyIcon(v);
  }

  Future<void> _sendDailyIcon(bool v) async {
    try {
      final stored = await dateIconChannel.invokeMethod<bool>(
        'setDailyIcon',
        {'on': v},
      );
      // Native's answer wins should it refuse this change, unless the user
      // has flipped the switch again since (a later call is on its way).
      if (stored != null && stored != v && _dailyIcon == v) {
        _dailyIcon = stored;
        notifyListeners();
      }
    } on Exception {
      // No native side: the switch still reads what the user chose.
    }
  }

  Appearance get appearance =>
      Appearance.values[(_prefs.getInt('appearance') ?? 0).clamp(0, 2)];
  set appearance(Appearance v) =>
      _set(() => _prefs.setInt('appearance', v.index));

  Accent get accent =>
      accents[(_prefs.getInt('accent') ?? 4).clamp(0, accents.length - 1)];
  int get accentIndex => accents.indexOf(accent);
  set accentIndex(int i) => _set(() => _prefs.setInt('accent', i));

  String get dateFormat {
    final f = _prefs.getString('date_format');
    return dateFormats.contains(f) ? f! : dateFormats.first;
  }

  set dateFormat(String v) => _set(() => _prefs.setString('date_format', v));

  bool get use24h => _prefs.getBool('use_24h') ?? false;
  set use24h(bool v) => _set(() => _prefs.setBool('use_24h', v));

  /// Monday first (ISO weeks) is the default; Sunday first uses US weeks.
  bool get mondayFirst => _prefs.getBool('monday_first') ?? true;
  set mondayFirst(bool v) => _set(() => _prefs.setBool('monday_first', v));

  bool get showShare => _prefs.getBool('show_share') ?? true;
  set showShare(bool v) => _set(() => _prefs.setBool('show_share', v));

  /// Working week for the working-days tool (1 = Monday .. 7 = Sunday).
  Set<int> get workdays {
    final l = _prefs.getStringList('workdays');
    if (l == null) return {1, 2, 3, 4, 5};
    return l.map(int.parse).where((d) => d >= 1 && d <= 7).toSet();
  }

  set workdays(Set<int> v) => _set(
    () => _prefs.setStringList(
      'workdays',
      (v.toList()..sort()).map((e) => '$e').toList(),
    ),
  );

  String date(DateTime d) => DateFormat(dateFormat).format(d);
  String time(DateTime d) => DateFormat(use24h ? 'HH:mm' : 'h:mm a').format(d);

  void _set(Future<bool> Function() write) {
    write();
    notifyListeners();
  }
}

/// Makes [Settings] reachable from any widget and rebuilds them on change.
class SettingsScope extends InheritedNotifier<Settings> {
  const SettingsScope({
    super.key,
    required Settings settings,
    required super.child,
  }) : super(notifier: settings);

  static Settings of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SettingsScope>()!.notifier!;
}
