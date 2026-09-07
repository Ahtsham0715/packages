import 'dart:convert';
import 'dart:typed_data';

import 'kdf.dart';
import 'sealed_box.dart';
import 'secure_bytes.dart';
import 'secure_random.dart';
import 'vault_header.dart';

/// Raised when the master password does not open the vault.
class WrongPasswordException implements Exception {
  const WrongPasswordException();
  @override
  String toString() => 'Incorrect master password';
}

/// The set of live keys for an unlocked vault.
///
/// # Key hierarchy
///
/// ```
///   master password
///        │  Argon2id(salt, m/t/p from the vault header)
///        ▼
///   master key ──HKDF─┬─► key-encryption key ──► unwraps the data key
///                     └─► verifier key       ──► "is this password right?"
///
///   data key (random, 32 bytes, never derived from the password)
///        │  HKDF
///        ├─► item key        ──► every vault record
///        ├─► attachment key  ──► file payloads
///        ├─► blind-index key ──► duplicate/reuse detection
///        └─► autofill key    ──► the optional platform mirror
/// ```
///
/// The data key being *random* rather than password-derived is what makes
/// changing the master password cheap: only the wrapper is redone, and the
/// millions of bytes of item ciphertext are untouched. It is also what lets
/// biometric unlock work — the platform keystore holds a second wrapper around
/// the same data key, so a fingerprint recovers a fully functional key ring
/// without the password ever being present.
class KeyRing {
  KeyRing._({
    required SecureBytes dataKey,
    required SecureBytes itemKey,
    required SecureBytes attachmentKey,
    required SecureBytes blindIndexKey,
    required SecureBytes autofillKey,
  })  : _dataKey = dataKey,
        _itemKey = itemKey,
        _attachmentKey = attachmentKey,
        _blindIndexKey = blindIndexKey,
        _autofillKey = autofillKey;

  static const String _verifierPlaintext = 'sablekey/verifier/v1';
  static const List<int> _aadDek = [0x64, 0x65, 0x6B]; // 'dek'

  final SecureBytes _dataKey;
  final SecureBytes _itemKey;
  final SecureBytes _attachmentKey;
  final SecureBytes _blindIndexKey;
  final SecureBytes _autofillKey;

  bool _destroyed = false;

  bool get isDestroyed => _destroyed;

  SecureBytes get itemKey => _requireLive(_itemKey);
  SecureBytes get attachmentKey => _requireLive(_attachmentKey);
  SecureBytes get blindIndexKey => _requireLive(_blindIndexKey);
  SecureBytes get autofillKey => _requireLive(_autofillKey);

  SecureBytes _requireLive(SecureBytes key) {
    if (_destroyed) throw StateError('KeyRing used after lock');
    return key;
  }

  /// The raw data key, for re-wrapping only (password change, biometric
  /// enrolment). Callers must not hold on to the copy.
  Uint8List exportDataKeyForWrapping() => _requireLive(_dataKey).copy();

  // ---------------------------------------------------------------------
  // Creation and unlocking
  // ---------------------------------------------------------------------

  /// Creates a brand-new vault: fresh salt, fresh random data key, and a
  /// header that can be written to disk.
  static Future<({VaultHeader header, KeyRing keyRing})> createVault({
    required String password,
    required KdfParams params,
  }) async {
    final salt = SecureRandom.bytes(Kdf.saltLength);
    final dataKeyBytes = SecureRandom.bytes(32);
    final dataKey = SecureBytes.consume(dataKeyBytes);

    final masterKey = await Kdf.deriveMasterKey(
      password: password,
      salt: salt,
      params: params,
    );

    try {
      final kek = await KeyDerivation.subkey(
        master: masterKey,
        info: KeyDerivation.infoKek,
        salt: salt,
      );
      final verifierKey = await KeyDerivation.subkey(
        master: masterKey,
        info: KeyDerivation.infoVerifier,
        salt: salt,
      );

      try {
        final wrappedDek = await SealedBox.seal(
          key: kek,
          plaintext: dataKey.copy(),
          aad: _aadDek,
        );
        final verifier = await SealedBox.seal(
          key: verifierKey,
          plaintext: Uint8List.fromList(utf8.encode(_verifierPlaintext)),
        );

        final now = DateTime.now();
        final header = VaultHeader(
          formatVersion: VaultHeader.currentFormatVersion,
          salt: salt,
          kdfParams: params,
          wrappedDek: wrappedDek,
          verifier: verifier,
          createdAt: now,
          lastRekeyedAt: now,
        );
        return (header: header, keyRing: await _fromDataKey(dataKey, salt));
      } finally {
        kek.destroy();
        verifierKey.destroy();
      }
    } finally {
      masterKey.destroy();
    }
  }

  /// Opens a vault with the master password.
  static Future<KeyRing> unlockWithPassword({
    required String password,
    required VaultHeader header,
  }) async {
    if (!header.kdfParams.meetsFloor) {
      throw const VaultFormatException(
        'This vault declares key-derivation parameters that are too weak to be '
        'trusted. It may have been tampered with.',
      );
    }

    final masterKey = await Kdf.deriveMasterKey(
      password: password,
      salt: header.salt,
      params: header.kdfParams,
    );

    try {
      final kek = await KeyDerivation.subkey(
        master: masterKey,
        info: KeyDerivation.infoKek,
        salt: header.salt,
      );
      try {
        final Uint8List dataKeyBytes;
        try {
          dataKeyBytes = await SealedBox.open(
            key: kek,
            envelope: header.wrappedDek,
            aad: _aadDek,
          );
        } on DecryptionFailure {
          // The only reachable cause here is a wrong password; a corrupted
          // header would have failed the format checks above.
          throw const WrongPasswordException();
        }
        return await _fromDataKey(SecureBytes.consume(dataKeyBytes), header.salt);
      } finally {
        kek.destroy();
      }
    } finally {
      masterKey.destroy();
    }
  }

  /// Opens a vault from a data key recovered from the platform keystore.
  static Future<KeyRing> unlockWithDataKey({
    required Uint8List dataKey,
    required VaultHeader header,
  }) =>
      _fromDataKey(SecureBytes.consume(dataKey), header.salt);

  /// Checks a password without producing a usable key ring.
  ///
  /// Used before destructive settings changes, where we want proof of identity
  /// but have no reason to hold the data key.
  static Future<bool> verifyPassword({
    required String password,
    required VaultHeader header,
  }) async {
    final masterKey = await Kdf.deriveMasterKey(
      password: password,
      salt: header.salt,
      params: header.kdfParams,
    );
    try {
      final verifierKey = await KeyDerivation.subkey(
        master: masterKey,
        info: KeyDerivation.infoVerifier,
        salt: header.salt,
      );
      try {
        final clear = await SealedBox.open(
          key: verifierKey,
          envelope: header.verifier,
        );
        return constantTimeEquals(clear, utf8.encode(_verifierPlaintext));
      } on DecryptionFailure {
        return false;
      } finally {
        verifierKey.destroy();
      }
    } finally {
      masterKey.destroy();
    }
  }

  // ---------------------------------------------------------------------
  // Re-keying
  // ---------------------------------------------------------------------

  /// Rewraps the existing data key under a new password.
  ///
  /// Item ciphertext is left completely alone — the data key does not change,
  /// so changing the master password on a 5000-item vault is as fast as on an
  /// empty one. A fresh salt is generated so the new wrapper shares no
  /// derivation input with the old one.
  Future<VaultHeader> rewrapForNewPassword({
    required VaultHeader header,
    required String newPassword,
    required KdfParams params,
  }) async {
    final salt = SecureRandom.bytes(Kdf.saltLength);
    final masterKey = await Kdf.deriveMasterKey(
      password: newPassword,
      salt: salt,
      params: params,
    );
    try {
      final kek = await KeyDerivation.subkey(
        master: masterKey,
        info: KeyDerivation.infoKek,
        salt: salt,
      );
      final verifierKey = await KeyDerivation.subkey(
        master: masterKey,
        info: KeyDerivation.infoVerifier,
        salt: salt,
      );
      try {
        final raw = exportDataKeyForWrapping();
        try {
          final wrappedDek =
              await SealedBox.seal(key: kek, plaintext: raw, aad: _aadDek);
          final verifier = await SealedBox.seal(
            key: verifierKey,
            plaintext: Uint8List.fromList(utf8.encode(_verifierPlaintext)),
          );
          return header.copyWith(
            salt: salt,
            kdfParams: params,
            wrappedDek: wrappedDek,
            verifier: verifier,
            lastRekeyedAt: DateTime.now(),
          );
        } finally {
          wipeBytes(raw);
        }
      } finally {
        kek.destroy();
        verifierKey.destroy();
      }
    } finally {
      masterKey.destroy();
    }
  }

  // ---------------------------------------------------------------------

  static Future<KeyRing> _fromDataKey(SecureBytes dataKey, Uint8List salt) async {
    return KeyRing._(
      dataKey: dataKey,
      itemKey: await KeyDerivation.subkey(
          master: dataKey, info: 'sablekey/v1/item', salt: salt),
      attachmentKey: await KeyDerivation.subkey(
          master: dataKey, info: KeyDerivation.infoAttachment, salt: salt),
      blindIndexKey: await KeyDerivation.subkey(
          master: dataKey, info: KeyDerivation.infoBlindIndex, salt: salt),
      autofillKey: await KeyDerivation.subkey(
          master: dataKey, info: KeyDerivation.infoAutofill, salt: salt),
    );
  }

  /// Wipes every key. Called on lock, on backgrounding, and on panic wipe.
  void destroy() {
    if (_destroyed) return;
    _destroyed = true;
    _dataKey.destroy();
    _itemKey.destroy();
    _attachmentKey.destroy();
    _blindIndexKey.destroy();
    _autofillKey.destroy();
  }
}
