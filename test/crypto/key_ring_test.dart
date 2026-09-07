import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sablekey/core/crypto/kdf.dart';
import 'package:sablekey/core/crypto/key_ring.dart';
import 'package:sablekey/core/crypto/sealed_box.dart';
import 'package:sablekey/core/crypto/vault_header.dart';

void main() {
  // The real profiles take a second each by design, which would make this file
  // take minutes. The reduced profile exercises identical code paths.
  const params = KdfParams.reduced;

  Uint8List bytes(String value) => Uint8List.fromList(utf8.encode(value));

  group('vault creation', () {
    test('produces a usable key ring and a well-formed header', () async {
      final created = await KeyRing.createVault(
        password: 'correct horse battery staple',
        params: params,
      );

      expect(created.header.formatVersion, VaultHeader.currentFormatVersion);
      expect(created.header.salt.length, Kdf.saltLength);
      expect(created.header.kdfParams, params);
      expect(created.keyRing.itemKey.length, 32);
      expect(created.keyRing.isDestroyed, isFalse);
    });

    test('two vaults with the same password get different keys', () async {
      const password = 'the same password';
      final first = await KeyRing.createVault(password: password, params: params);
      final second =
          await KeyRing.createVault(password: password, params: params);

      // Different salts and different random data keys. Without this, two
      // people choosing the same password would share ciphertext structure.
      expect(first.header.salt, isNot(equals(second.header.salt)));
      expect(
        first.keyRing.itemKey.bytes,
        isNot(equals(second.keyRing.itemKey.bytes)),
      );
    });
  });

  group('unlock', () {
    test('the right password reproduces the same item key', () async {
      const password = 'open sesame please';
      final created =
          await KeyRing.createVault(password: password, params: params);
      final expected = created.keyRing.itemKey.copy();

      final reopened = await KeyRing.unlockWithPassword(
        password: password,
        header: created.header,
      );

      expect(reopened.itemKey.bytes, equals(expected));
    });

    test('the wrong password is rejected', () async {
      final created =
          await KeyRing.createVault(password: 'right', params: params);

      expect(
        () => KeyRing.unlockWithPassword(
            password: 'wrong', header: created.header),
        throwsA(isA<WrongPasswordException>()),
      );
    });

    test('data written before a lock is readable after unlocking', () async {
      const password = 'a durable passphrase';
      final created =
          await KeyRing.createVault(password: password, params: params);

      final sealed = await SealedBox.seal(
        key: created.keyRing.itemKey,
        plaintext: bytes('my bank password'),
        aad: utf8.encode('item-1'),
      );
      created.keyRing.destroy();

      final reopened = await KeyRing.unlockWithPassword(
        password: password,
        header: created.header,
      );
      final opened = await SealedBox.open(
        key: reopened.itemKey,
        envelope: sealed,
        aad: utf8.encode('item-1'),
      );

      expect(utf8.decode(opened), 'my bank password');
    });
  });

  group('biometric path', () {
    test('a stored data key reconstructs the full key ring', () async {
      final created =
          await KeyRing.createVault(password: 'passphrase', params: params);

      // What the platform keystore would hold.
      final storedKey = created.keyRing.exportDataKeyForWrapping();

      final viaBiometrics = await KeyRing.unlockWithDataKey(
        dataKey: storedKey,
        header: created.header,
      );

      // Every subkey must match, or biometric unlock would open the vault but
      // fail to read attachments or the blind index.
      expect(viaBiometrics.itemKey.bytes,
          equals(created.keyRing.itemKey.bytes));
      expect(viaBiometrics.attachmentKey.bytes,
          equals(created.keyRing.attachmentKey.bytes));
      expect(viaBiometrics.blindIndexKey.bytes,
          equals(created.keyRing.blindIndexKey.bytes));
      expect(viaBiometrics.autofillKey.bytes,
          equals(created.keyRing.autofillKey.bytes));
    });
  });

  group('password verification', () {
    test('accepts the right password without exposing the data key', () async {
      final created =
          await KeyRing.createVault(password: 'let me in', params: params);

      expect(
        await KeyRing.verifyPassword(
            password: 'let me in', header: created.header),
        isTrue,
      );
      expect(
        await KeyRing.verifyPassword(
            password: 'let me out', header: created.header),
        isFalse,
      );
    });
  });

  group('changing the master password', () {
    test('keeps existing ciphertext readable', () async {
      final created =
          await KeyRing.createVault(password: 'old password', params: params);

      final sealed = await SealedBox.seal(
        key: created.keyRing.itemKey,
        plaintext: bytes('unchanged data'),
      );

      final updated = await created.keyRing.rewrapForNewPassword(
        header: created.header,
        newPassword: 'new password',
        params: params,
      );

      final reopened = await KeyRing.unlockWithPassword(
        password: 'new password',
        header: updated,
      );

      // The whole point: the data key did not change, so the existing
      // ciphertext still opens.
      final opened =
          await SealedBox.open(key: reopened.itemKey, envelope: sealed);
      expect(utf8.decode(opened), 'unchanged data');
    });

    test('invalidates the old password', () async {
      final created =
          await KeyRing.createVault(password: 'old password', params: params);
      final updated = await created.keyRing.rewrapForNewPassword(
        header: created.header,
        newPassword: 'new password',
        params: params,
      );

      expect(
        () => KeyRing.unlockWithPassword(
            password: 'old password', header: updated),
        throwsA(isA<WrongPasswordException>()),
      );
    });

    test('uses a fresh salt', () async {
      final created =
          await KeyRing.createVault(password: 'old', params: params);
      final updated = await created.keyRing.rewrapForNewPassword(
        header: created.header,
        newPassword: 'new',
        params: params,
      );
      expect(updated.salt, isNot(equals(created.header.salt)));
    });
  });

  group('header tampering', () {
    test('a downgraded KDF cost is refused', () async {
      final created =
          await KeyRing.createVault(password: 'password', params: params);

      // An attacker with write access to the database would love to set
      // m=8/t=1 and then brute-force the password cheaply.
      final weakened = created.header.copyWith(
        kdfParams: const KdfParams(memoryKib: 8, iterations: 1, parallelism: 1),
      );

      expect(
        () => KeyRing.unlockWithPassword(
            password: 'password', header: weakened),
        throwsA(isA<VaultFormatException>()),
      );
    });

    test('the floor accepts the shipped profiles', () {
      expect(KdfParams.balanced.meetsFloor, isTrue);
      expect(KdfParams.hardened.meetsFloor, isTrue);
      expect(KdfParams.reduced.meetsFloor, isTrue);
      expect(
        const KdfParams(memoryKib: 1024, iterations: 1, parallelism: 1)
            .meetsFloor,
        isFalse,
      );
    });

    test('a header from a newer format version is refused', () {
      expect(
        () => VaultHeader.fromJson({
          'v': VaultHeader.currentFormatVersion + 1,
          'salt': base64Encode(Uint8List(32)),
          'kdf': params.toJson(),
          'dek': base64Encode(Uint8List(64)),
          'verifier': base64Encode(Uint8List(64)),
          'created': 0,
          'rekeyed': 0,
        }),
        throwsA(isA<VaultFormatException>()),
      );
    });

    test('survives a JSON round trip', () async {
      final created =
          await KeyRing.createVault(password: 'password', params: params);
      final decoded = VaultHeader.decode(created.header.encode());

      expect(decoded.salt, equals(created.header.salt));
      expect(decoded.kdfParams, equals(created.header.kdfParams));
      expect(decoded.wrappedDek, equals(created.header.wrappedDek));

      final reopened = await KeyRing.unlockWithPassword(
          password: 'password', header: decoded);
      expect(reopened.itemKey.bytes,
          equals(created.keyRing.itemKey.bytes));
    });
  });

  group('password normalisation', () {
    test('unicode spacing variants open the same vault', () async {
      // A phone keyboard that emits U+00A0 instead of a plain space must not
      // lock someone out of their own vault.
      final created = await KeyRing.createVault(
        password: 'my secret phrase',
        params: params,
      );

      final reopened = await KeyRing.unlockWithPassword(
        // Same phrase, but with U+00A0 NO-BREAK SPACE and U+2009 THIN
        // SPACE where the vault was created with plain U+0020.
        password: 'my secret phrase',
        header: created.header,
      );
      expect(reopened.itemKey.bytes,
          equals(created.keyRing.itemKey.bytes));
    });

    test('zero-width characters are ignored', () async {
      final created =
          await KeyRing.createVault(password: 'passphrase', params: params);
      final reopened = await KeyRing.unlockWithPassword(
        // U+200B ZERO WIDTH SPACE, which some keyboards insert invisibly.
        password: 'pass​phrase',
        header: created.header,
      );
      expect(reopened.itemKey.bytes,
          equals(created.keyRing.itemKey.bytes));
    });

    test('genuinely different passwords still differ', () async {
      final created =
          await KeyRing.createVault(password: 'passphrase', params: params);
      expect(
        () => KeyRing.unlockWithPassword(
            password: 'Passphrase', header: created.header),
        throwsA(isA<WrongPasswordException>()),
      );
    });
  });

  group('locking', () {
    test('destroy wipes every key', () async {
      final created =
          await KeyRing.createVault(password: 'password', params: params);
      created.keyRing.destroy();

      expect(created.keyRing.isDestroyed, isTrue);
      expect(() => created.keyRing.itemKey, throwsStateError);
      expect(() => created.keyRing.attachmentKey, throwsStateError);
      expect(() => created.keyRing.exportDataKeyForWrapping(), throwsStateError);
    });

    test('destroy is idempotent', () async {
      final created =
          await KeyRing.createVault(password: 'password', params: params);
      created.keyRing.destroy();
      expect(created.keyRing.destroy, returnsNormally);
    });
  });
}
