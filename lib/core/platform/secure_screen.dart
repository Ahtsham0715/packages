import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Screen-capture and clipboard hardening that only the platform can do.
///
/// Flutter has no way to set `FLAG_SECURE` or to mark a clipboard item
/// sensitive, so this is a thin channel onto the two native implementations.
/// Both calls are best-effort: on a platform or OS version that cannot honour
/// them the call returns quietly rather than throwing, because a missing
/// screenshot flag must not stop the vault from opening.
abstract final class SecureScreen {
  static const MethodChannel _channel =
      MethodChannel('sablekey/secure_screen');

  static bool _secureEnabled = false;

  static bool get isSecure => _secureEnabled;

  /// Blocks screenshots and screen recording, and hides the window's contents
  /// from the app switcher.
  ///
  /// On Android this sets `FLAG_SECURE`, which the system enforces for
  /// screenshots, recording and the recents thumbnail alike. On iOS there is no
  /// equivalent flag, so the native side covers the window with a blur when the
  /// app resigns active — screenshots there cannot be prevented, only the
  /// switcher preview, and SECURITY.md says so.
  static Future<void> setSecure({required bool enabled}) async {
    if (kIsWeb) return;
    if (_secureEnabled == enabled) return;
    try {
      await _channel.invokeMethod<void>('setSecure', {'enabled': enabled});
      _secureEnabled = enabled;
    } on PlatformException catch (error) {
      debugPrint('sablekey: could not set secure flag: ${error.message}');
    } on MissingPluginException {
      // Running in a test harness or on an unsupported platform.
    }
  }

  /// Copies text and marks it sensitive so the OS does not show a preview or
  /// sync it to another device.
  ///
  /// On Android 13+ this sets `EXTRA_IS_SENSITIVE`, which stops the clipboard
  /// toast from displaying the password in plain sight. On iOS the item is
  /// marked local-only and given an expiry so Universal Clipboard does not push
  /// the password to a nearby Mac.
  static Future<void> copySensitive(
    String value, {
    Duration? expiresAfter,
  }) async {
    if (kIsWeb) {
      await Clipboard.setData(ClipboardData(text: value));
      return;
    }
    try {
      await _channel.invokeMethod<void>('copySensitive', {
        'value': value,
        'expiresInSeconds': expiresAfter?.inSeconds ?? 0,
      });
    } on PlatformException catch (error) {
      debugPrint('sablekey: sensitive copy failed, falling back: '
          '${error.message}');
      await Clipboard.setData(ClipboardData(text: value));
    } on MissingPluginException {
      await Clipboard.setData(ClipboardData(text: value));
    }
  }

  /// Clears the clipboard, but only if it still holds what we put there.
  ///
  /// Checking first matters: between the copy and the timer firing the user may
  /// well have copied something else, and wiping their shopping list because a
  /// password timer expired is a bug they will notice and never diagnose.
  static Future<void> clearIfStillOurs(String expected) async {
    try {
      final current = await Clipboard.getData(Clipboard.kTextPlain);
      if (current?.text != expected) return;
      await Clipboard.setData(const ClipboardData(text: ''));
    } on PlatformException catch (error) {
      debugPrint('sablekey: clipboard clear failed: ${error.message}');
    } on MissingPluginException {
      // Nothing to do.
    }
  }

  /// Whether this platform can actually block screenshots.
  static bool get supportsScreenshotBlocking =>
      !kIsWeb && Platform.isAndroid;
}
