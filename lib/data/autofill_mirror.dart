import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../domain/models/item_type.dart';
import '../domain/models/vault_item.dart';

/// Keeps the iOS AutoFill extension's login mirror in step with the vault.
///
/// This is a no-op on Android, where the autofill service authenticates through
/// the app and never needs a copy of anything. See `ios/Runner/SablekeyMirror.swift`
/// for the full reasoning and the security trade-off it represents; in short,
/// an iOS credential provider extension cannot open the real vault, so enabling
/// iOS autofill writes a logins-only mirror encrypted under a Keychain key
/// gated by Face ID or Touch ID.
///
/// The mirror is rewritten from scratch on every sync rather than patched.
/// Incremental updates would need the app to read back what it wrote, which
/// would mean holding a key that can decrypt it — and the whole point is that
/// only the biometric check can.
abstract final class AutofillMirror {
  static const MethodChannel _channel = MethodChannel('sablekey/autofill');

  /// Whether this platform uses a mirror at all.
  static bool get isSupported => !kIsWeb && Platform.isIOS;

  /// Pushes the current set of logins to the extension.
  ///
  /// Returns false when the platform does not use a mirror, or when the write
  /// failed — the caller surfaces that as "autofill could not be set up"
  /// rather than leaving the user believing it works.
  static Future<bool> sync(List<VaultItem> items) async {
    if (!isSupported) return false;

    final entries = <Map<String, Object?>>[];
    for (final item in items) {
      if (item.isDeleted) continue;
      if (!item.type.isAutofillable) continue;

      final password = item.password;
      final username = item.username;
      if (password == null || password.isEmpty) continue;

      final uris = item.allUris;
      if (uris.isEmpty) continue;

      entries.add({
        'id': item.id,
        'name': item.name,
        'uris': uris,
        'username': username ?? '',
        'password': password,
        // The secret, not a generated code: a code would be stale within
        // thirty seconds of being written.
        'totpSecret': item.totp?.secret,
      });
    }

    try {
      final result = await _channel.invokeMethod<bool>('syncMirror', {
        'entries': jsonEncode(entries),
      });
      return result ?? false;
    } on PlatformException catch (error) {
      debugPrint('sablekey: autofill mirror sync failed: ${error.message}');
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Deletes the mirror and its key.
  ///
  /// Called when autofill is turned off, when the master password changes, and
  /// when the vault is erased. Leaving a stale mirror behind after any of those
  /// would keep logins reachable by biometrics alone, after the user believed
  /// they had revoked exactly that.
  static Future<void> clear() async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod<bool>('clearMirror');
    } on PlatformException catch (error) {
      debugPrint('sablekey: could not clear autofill mirror: ${error.message}');
    } on MissingPluginException {
      // Nothing to clear.
    }
  }

  /// How many items would be exposed to the extension, for the settings screen
  /// to state plainly before the user turns this on.
  static int countEligible(List<VaultItem> items) => items
      .where((item) =>
          !item.isDeleted &&
          item.type.isAutofillable &&
          (item.password?.isNotEmpty ?? false) &&
          item.allUris.isNotEmpty)
      .length;

  /// Item types that would never appear in the mirror, listed in the UI so the
  /// scope of the trade-off is visible rather than implied.
  static List<ItemType> get excludedTypes =>
      ItemType.values.where((type) => !type.isAutofillable).toList();
}
