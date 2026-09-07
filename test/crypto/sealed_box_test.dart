import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sablekey/core/crypto/sealed_box.dart';
import 'package:sablekey/core/crypto/secure_bytes.dart';
import 'package:sablekey/core/crypto/secure_random.dart';

void main() {
  SecureBytes freshKey() => SecureBytes(SecureRandom.bytes(32));

  Uint8List plaintext(String value) =>
      Uint8List.fromList(utf8.encode(value));

  group('seal and open', () {
    test('round-trips', () async {
      final key = freshKey();
      final sealed =
          await SealedBox.seal(key: key, plaintext: plaintext('hunter2'));
      final opened = await SealedBox.open(key: key, envelope: sealed);

      expect(utf8.decode(opened), 'hunter2');
    });

    test('produces a different ciphertext each time', () async {
      final key = freshKey();
      final message = plaintext('the same message');

      final first = await SealedBox.seal(key: key, plaintext: message);
      final second = await SealedBox.seal(key: key, plaintext: message);

      // A repeated nonce under the same key destroys confidentiality outright,
      // so this is the single most important property in the file.
      expect(first, isNot(equals(second)));
    });

    test('handles an empty plaintext', () async {
      final key = freshKey();
      final sealed = await SealedBox.seal(key: key, plaintext: Uint8List(0));
      expect(await SealedBox.open(key: key, envelope: sealed), isEmpty);
    });

    test('handles a large payload', () async {
      final key = freshKey();
      final big = SecureRandom.bytes(512 * 1024);
      final sealed = await SealedBox.seal(key: key, plaintext: big);
      expect(await SealedBox.open(key: key, envelope: sealed), equals(big));
    });
  });

  group('rejects tampering', () {
    test('a wrong key', () async {
      final sealed =
          await SealedBox.seal(key: freshKey(), plaintext: plaintext('secret'));
      expect(
        () => SealedBox.open(key: freshKey(), envelope: sealed),
        throwsA(isA<DecryptionFailure>()),
      );
    });

    test('a flipped bit anywhere in the envelope', () async {
      final key = freshKey();
      final sealed = await SealedBox.seal(
        key: key,
        plaintext: plaintext('a message long enough to have body'),
      );

      for (var index = 0; index < sealed.length; index++) {
        final mutated = Uint8List.fromList(sealed)..[index] ^= 0x01;
        await expectLater(
          SealedBox.open(key: key, envelope: mutated),
          throwsA(isA<DecryptionFailure>()),
          reason: 'byte $index was not covered by authentication',
        );
      }
    });

    test('truncation', () async {
      final key = freshKey();
      final sealed =
          await SealedBox.seal(key: key, plaintext: plaintext('secret'));
      expect(
        () => SealedBox.open(
            key: key, envelope: sealed.sublist(0, sealed.length - 1)),
        throwsA(isA<DecryptionFailure>()),
      );
    });

    test('an envelope shorter than the header', () async {
      expect(
        () => SealedBox.open(key: freshKey(), envelope: Uint8List(4)),
        throwsA(isA<DecryptionFailure>()),
      );
    });
  });

  group('additional authenticated data', () {
    test('binds a ciphertext to its context', () async {
      final key = freshKey();
      final sealed = await SealedBox.seal(
        key: key,
        plaintext: plaintext('card number'),
        aad: utf8.encode('item-a'),
      );

      // Lifting a valid blob from one row into another must fail, or an
      // attacker with write access could swap two entries' contents.
      expect(
        () => SealedBox.open(
            key: key, envelope: sealed, aad: utf8.encode('item-b')),
        throwsA(isA<DecryptionFailure>()),
      );

      final opened = await SealedBox.open(
          key: key, envelope: sealed, aad: utf8.encode('item-a'));
      expect(utf8.decode(opened), 'card number');
    });

    test('a missing aad is not the same as an empty one', () async {
      final key = freshKey();
      final sealed = await SealedBox.seal(
        key: key,
        plaintext: plaintext('x'),
        aad: utf8.encode('ctx'),
      );
      expect(
        () => SealedBox.open(key: key, envelope: sealed),
        throwsA(isA<DecryptionFailure>()),
      );
    });
  });

  group('envelope format', () {
    test('carries the expected header', () async {
      final sealed = await SealedBox.seal(
        key: freshKey(),
        plaintext: plaintext('x'),
      );
      expect(sealed[0], 0x53); // 'S'
      expect(sealed[1], 0x4B); // 'K'
      expect(sealed[2], SealedBox.formatVersion);
      expect(sealed[3], SealedBox.algXChaCha20Poly1305);
    });

    test('overhead is exactly header + nonce + tag', () async {
      final sealed = await SealedBox.seal(
        key: freshKey(),
        plaintext: plaintext('0123456789'),
      );
      expect(sealed.length, 10 + SealedBox.overhead);
    });

    test('refuses an unknown format version', () async {
      final key = freshKey();
      final sealed =
          await SealedBox.seal(key: key, plaintext: plaintext('x'));
      final future = Uint8List.fromList(sealed)..[2] = 0x99;

      expect(
        () => SealedBox.open(key: key, envelope: future),
        throwsA(isA<DecryptionFailure>()),
      );
    });
  });

  group('key separation', () {
    test('different info labels produce different subkeys', () async {
      final master = freshKey();
      final salt = SecureRandom.bytes(32);

      final kek = await KeyDerivation.subkey(
          master: master, info: KeyDerivation.infoKek, salt: salt);
      final verifier = await KeyDerivation.subkey(
          master: master, info: KeyDerivation.infoVerifier, salt: salt);

      expect(kek.bytes, isNot(equals(verifier.bytes)));
      expect(kek.length, 32);
    });

    test('is deterministic for the same inputs', () async {
      final master = SecureBytes(Uint8List.fromList(List.filled(32, 7)));
      final salt = Uint8List.fromList(List.filled(32, 9));

      final first = await KeyDerivation.subkey(
          master: master, info: KeyDerivation.infoKek, salt: salt);
      final second = await KeyDerivation.subkey(
          master: master, info: KeyDerivation.infoKek, salt: salt);

      expect(first.bytes, equals(second.bytes));
    });

    test('a different salt produces a different subkey', () async {
      final master = SecureBytes(Uint8List.fromList(List.filled(32, 7)));

      final first = await KeyDerivation.subkey(
        master: master,
        info: KeyDerivation.infoKek,
        salt: Uint8List.fromList(List.filled(32, 1)),
      );
      final second = await KeyDerivation.subkey(
        master: master,
        info: KeyDerivation.infoKek,
        salt: Uint8List.fromList(List.filled(32, 2)),
      );

      expect(first.bytes, isNot(equals(second.bytes)));
    });
  });

  group('SecureBytes', () {
    test('destroy wipes the buffer and blocks further use', () {
      final key = SecureBytes(Uint8List.fromList([1, 2, 3, 4]));
      key.destroy();

      expect(key.isDestroyed, isTrue);
      expect(() => key.bytes, throwsStateError);
    });

    test('destroy is idempotent', () {
      final key = SecureBytes(Uint8List.fromList([1, 2, 3]))..destroy();
      expect(key.destroy, returnsNormally);
    });

    test('consume wipes the source buffer', () {
      final source = Uint8List.fromList([9, 9, 9, 9]);
      final held = SecureBytes.consume(source);

      expect(source, everyElement(0));
      expect(held.bytes, equals([9, 9, 9, 9]));
    });
  });

  group('constantTimeEquals', () {
    test('matches identical inputs', () {
      expect(constantTimeEquals([1, 2, 3], [1, 2, 3]), isTrue);
    });

    test('rejects a difference at any position', () {
      expect(constantTimeEquals([1, 2, 3], [9, 2, 3]), isFalse);
      expect(constantTimeEquals([1, 2, 3], [1, 2, 9]), isFalse);
    });

    test('rejects a length mismatch', () {
      expect(constantTimeEquals([1, 2], [1, 2, 3]), isFalse);
    });

    test('accepts two empty inputs', () {
      expect(constantTimeEquals(const [], const []), isTrue);
    });
  });
}
