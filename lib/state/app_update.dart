import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Updates from Google Play, through Play's own in-app update API.
///
/// When Play has a newer version, Play's own "Update available" sheet comes
/// up over the app (the FLEXIBLE flow): the download runs in the background
/// while the app stays usable. Once it is downloaded, [onReady] asks the user
/// to restart; if they choose later, the update installs the next time the
/// app leaves the screen, so it is never left waiting.
///
/// Android only, and only for a copy installed from Play: anywhere else Play
/// refuses the check, and that is treated as "no update", never an error.
class AppUpdater with WidgetsBindingObserver {
  AppUpdater._();
  static final instance = AppUpdater._();

  /// A "not now" is respected for this long before Play's sheet comes back.
  static const declineQuietFor = Duration(days: 3);
  static const _declinedAtKey = 'update_declined_at';
  static const _declinedCodeKey = 'update_declined_code';

  /// Shows the "restart to finish" prompt; set by the app.
  Future<bool> Function()? onReady;

  bool _started = false;
  bool _busy = false;
  bool _downloaded = false;
  bool _installOnLeave = false;

  static bool get _supported => !kIsWeb && !kDebugMode && Platform.isAndroid;

  void start() {
    if (_started || !_supported) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    // After the first screen is up, so the check never slows the launch.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => Timer(const Duration(seconds: 2), _check),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _check();
    } else if (state == AppLifecycleState.paused && _installOnLeave) {
      // Off screen, Play installs quietly; the next open is the new version.
      _installOnLeave = false;
      InAppUpdate.completeFlexibleUpdate().catchError((_) {});
    }
  }

  Future<void> _check() async {
    if (_busy) return;
    _busy = true;
    try {
      final info = await InAppUpdate.checkForUpdate();
      if (info.installStatus == InstallStatus.downloaded) {
        await _ready();
        return;
      }
      if (_downloaded ||
          info.updateAvailability != UpdateAvailability.updateAvailable ||
          !info.flexibleUpdateAllowed) {
        return;
      }
      final code = info.availableVersionCode ?? 0;
      if (await _recentlyDeclined(code)) return;

      final result = await InAppUpdate.startFlexibleUpdate();
      switch (result) {
        case AppUpdateResult.success:
          await _ready();
        case AppUpdateResult.userDeniedUpdate:
          await _rememberDecline(code);
        case AppUpdateResult.inAppUpdateFailed:
          break;
      }
    } catch (_) {
      // Not installed from Play, no Play Store, offline: no update to offer.
    } finally {
      _busy = false;
    }
  }

  Future<void> _ready() async {
    _downloaded = true;
    if (_installOnLeave) return; // already asked; installs on leaving
    final restart = await (onReady?.call() ?? Future.value(false));
    if (restart) {
      await InAppUpdate.completeFlexibleUpdate().catchError((_) {});
    } else {
      _installOnLeave = true;
    }
  }

  Future<bool> _recentlyDeclined(int code) async {
    final prefs = await SharedPreferences.getInstance();
    final at = prefs.getInt(_declinedAtKey);
    if (at == null || prefs.getInt(_declinedCodeKey) != code) return false;
    final since = DateTime.now().difference(
      DateTime.fromMillisecondsSinceEpoch(at),
    );
    return since < declineQuietFor;
  }

  Future<void> _rememberDecline(int code) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_declinedAtKey, DateTime.now().millisecondsSinceEpoch);
    await prefs.setInt(_declinedCodeKey, code);
  }
}
