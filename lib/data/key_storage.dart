import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

/// Why a biometric unlock did not happen.
enum BiometricOutcome {
  success,
  cancelled,
  notEnrolled,
  notAvailable,
  lockedOut,
  failed,
}

/// Stores the vault's data key behind the platform keystore so a fingerprint or
/// face can open the vault without the master password.
///
/// # What this does and does not guarantee
///
/// On Android the key sits in `EncryptedSharedPreferences`, which is wrapped by
/// a hardware-backed Keystore key. On iOS it is a Keychain item marked
/// `first_unlock_this_device`, so it never syncs to iCloud and never leaves the
/// device.
///
/// The biometric prompt is enforced *by this app*, not by the keystore itself:
/// the app authenticates, and only then reads the key. On a device where an
/// attacker has already achieved root or jailbreak, that ordering can be
/// bypassed and the key read directly. Binding the key to
/// `setUserAuthenticationRequired` in the Keystore would close that gap and is
/// the main piece of hardening still outstanding — it is why biometric unlock
/// is opt-in and off by default, and why SECURITY.md states this plainly rather
/// than claiming hardware-enforced biometrics.
class KeyStorage {
  KeyStorage({
    FlutterSecureStorage? storage,
    LocalAuthentication? localAuth,
  })  : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
              iOptions: IOSOptions(
                accessibility: KeychainAccessibility.first_unlock_this_device,
              ),
            ),
        _localAuth = localAuth ?? LocalAuthentication();

  static const String _dataKeyEntry = 'sablekey.datakey.v1';

  final FlutterSecureStorage _storage;
  final LocalAuthentication _localAuth;

  Future<bool> get isEnrolled async =>
      (await _storage.read(key: _dataKeyEntry)) != null;

  /// Whether the device can do biometrics at all.
  Future<bool> get isBiometricAvailable async {
    try {
      if (!await _localAuth.isDeviceSupported()) return false;
      final available = await _localAuth.getAvailableBiometrics();
      return available.isNotEmpty;
    } on Object {
      return false;
    }
  }

  Future<List<BiometricType>> availableBiometrics() async {
    try {
      return await _localAuth.getAvailableBiometrics();
    } on Object {
      return const [];
    }
  }

  /// Stores the data key for later biometric recovery.
  ///
  /// The caller must have just proved knowledge of the master password —
  /// enrolling from an already-unlocked session without re-authenticating would
  /// let someone with a briefly borrowed phone give themselves permanent
  /// access.
  Future<void> enrol(Uint8List dataKey) async {
    await _storage.write(key: _dataKeyEntry, value: base64Encode(dataKey));
  }

  Future<void> removeEnrolment() async {
    await _storage.delete(key: _dataKeyEntry);
  }

  /// Prompts for biometrics and returns the data key on success.
  ///
  /// Returns `null` for every failure path; the reason comes back in
  /// [lastOutcome] so the UI can say something useful instead of "failed".
  Future<Uint8List?> unlock({
    String reason = 'Unlock your Sablekey vault',
  }) async {
    lastOutcome = BiometricOutcome.failed;

    final stored = await _storage.read(key: _dataKeyEntry);
    if (stored == null) {
      lastOutcome = BiometricOutcome.notEnrolled;
      return null;
    }

    bool authenticated;
    try {
      authenticated = await _localAuth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
          // The vault is already protected by a master password; falling back
          // to the device PIN would make the phone's lock screen the only thing
          // standing between an attacker and the vault.
          useErrorDialogs: true,
        ),
      );
    } on Object catch (error) {
      lastOutcome = _classify(error);
      return null;
    }

    if (!authenticated) {
      lastOutcome = BiometricOutcome.cancelled;
      return null;
    }

    lastOutcome = BiometricOutcome.success;
    try {
      return Uint8List.fromList(base64Decode(stored));
    } on FormatException {
      // Corrupt entry: drop it so the user is not stuck failing forever.
      await removeEnrolment();
      lastOutcome = BiometricOutcome.notEnrolled;
      return null;
    }
  }

  /// Result of the most recent [unlock] call.
  BiometricOutcome lastOutcome = BiometricOutcome.failed;

  static BiometricOutcome _classify(Object error) {
    final text = error.toString();
    if (text.contains('NotEnrolled') || text.contains('not enrolled')) {
      return BiometricOutcome.notEnrolled;
    }
    if (text.contains('LockedOut') || text.contains('PermanentlyLockedOut')) {
      return BiometricOutcome.lockedOut;
    }
    if (text.contains('NotAvailable') || text.contains('no_fragment_activity')) {
      return BiometricOutcome.notAvailable;
    }
    debugPrint('sablekey: biometric error: $text');
    return BiometricOutcome.failed;
  }
}

/// Human-readable explanation for a biometric failure.
extension BiometricOutcomeMessage on BiometricOutcome {
  String get message => switch (this) {
        BiometricOutcome.success => 'Unlocked',
        BiometricOutcome.cancelled => 'Biometric unlock cancelled',
        BiometricOutcome.notEnrolled =>
          'No biometrics are enrolled on this device',
        BiometricOutcome.notAvailable =>
          'This device does not support biometric unlock',
        BiometricOutcome.lockedOut =>
          'Too many attempts. Use your master password.',
        BiometricOutcome.failed => 'Biometric unlock failed',
      };
}
