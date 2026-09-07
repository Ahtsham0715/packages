import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'secure_bytes.dart';
import 'secure_random.dart';

/// Raised when a ciphertext fails to authenticate.
///
/// Deliberately carries no detail about *why*: distinguishing "wrong key" from
/// "bad MAC" from "truncated" gives an attacker with write access to the file a
/// decryption oracle.
class DecryptionFailure implements Exception {
  const DecryptionFailure([this.context = '']);
  final String context;
  @override
  String toString() => 'DecryptionFailure${context.isEmpty ? '' : ': $context'}';
}

/// The on-disk authenticated-encryption envelope used for every secret byte
/// Sablekey stores.
///
/// Layout:
/// ```
///   0     'S'
///   1     'K'
///   2     format version (1)
///   3     algorithm id   (1 = XChaCha20-Poly1305)
///   4..27 nonce (24 bytes, random per message)
///   28..  ciphertext || Poly1305 tag (16 bytes)
/// ```
///
/// The 4-byte header is fed in as additional authenticated data, so the version
/// and algorithm bytes are covered by the tag. Without that, an attacker could
/// flip the algorithm id and try to steer a future build onto a weaker cipher.
///
/// XChaCha20 rather than ChaCha20 because its 24-byte nonce can be generated
/// randomly with no practical collision risk. A 12-byte nonce would force us to
/// keep a per-key counter, and a counter that resets — after a restore from
/// backup, say — silently destroys confidentiality.
abstract final class SealedBox {
  static const int _magic0 = 0x53; // 'S'
  static const int _magic1 = 0x4B; // 'K'
  static const int formatVersion = 0x01;
  static const int algXChaCha20Poly1305 = 0x01;

  static const int headerLength = 4;
  static const int nonceLength = 24;
  static const int macLength = 16;
  static const int overhead = headerLength + nonceLength + macLength;

  static final Xchacha20 _cipher = Xchacha20.poly1305Aead();

  /// Encrypts [plaintext] under [key].
  ///
  /// [aad] binds the ciphertext to its context — an item id, a table name — so
  /// a valid blob cannot be lifted out of one row and dropped into another.
  static Future<Uint8List> seal({
    required SecureBytes key,
    required Uint8List plaintext,
    List<int> aad = const [],
  }) async {
    final nonce = SecureRandom.bytes(nonceLength);
    final header = _header();

    final box = await _cipher.encrypt(
      plaintext,
      secretKey: SecretKey(key.bytes),
      nonce: nonce,
      aad: [...header, ...aad],
    );

    final out = Uint8List(overhead + box.cipherText.length);
    out.setRange(0, headerLength, header);
    out.setRange(headerLength, headerLength + nonceLength, nonce);
    out.setRange(headerLength + nonceLength,
        headerLength + nonceLength + box.cipherText.length, box.cipherText);
    out.setRange(out.length - macLength, out.length, box.mac.bytes);
    return out;
  }

  /// Decrypts an envelope produced by [seal].
  ///
  /// Throws [DecryptionFailure] on any problem: wrong key, tampered bytes,
  /// unknown version, truncation.
  static Future<Uint8List> open({
    required SecureBytes key,
    required Uint8List envelope,
    List<int> aad = const [],
  }) async {
    if (envelope.length < overhead) {
      throw const DecryptionFailure('short envelope');
    }
    if (envelope[0] != _magic0 || envelope[1] != _magic1) {
      throw const DecryptionFailure('bad magic');
    }
    if (envelope[2] != formatVersion) {
      throw const DecryptionFailure('unsupported format version');
    }
    if (envelope[3] != algXChaCha20Poly1305) {
      throw const DecryptionFailure('unsupported algorithm');
    }

    final header = envelope.sublist(0, headerLength);
    final nonce = envelope.sublist(headerLength, headerLength + nonceLength);
    final cipherText = envelope.sublist(
        headerLength + nonceLength, envelope.length - macLength);
    final mac = envelope.sublist(envelope.length - macLength);

    try {
      final clear = await _cipher.decrypt(
        SecretBox(cipherText, nonce: nonce, mac: Mac(mac)),
        secretKey: SecretKey(key.bytes),
        aad: [...header, ...aad],
      );
      return Uint8List.fromList(clear);
    } on SecretBoxAuthenticationError {
      throw const DecryptionFailure();
    } on ArgumentError {
      throw const DecryptionFailure();
    }
  }

  static Uint8List _header() => Uint8List.fromList(
      const [_magic0, _magic1, formatVersion, algXChaCha20Poly1305]);
}

/// Key separation.
///
/// One password produces one master key, but that key is never used to encrypt
/// anything directly. Every purpose gets its own subkey derived with a distinct
/// `info` label, so a flaw that exposes one — the autofill mirror key, say —
/// tells an attacker nothing about the others.
abstract final class KeyDerivation {
  static final Hkdf _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);

  /// Wraps the vault's data encryption key.
  static const String infoKek = 'sablekey/v1/kek';

  /// Proves the password is right without touching the data key.
  static const String infoVerifier = 'sablekey/v1/verifier';

  /// Keys the blind index used for duplicate detection.
  static const String infoBlindIndex = 'sablekey/v1/blind-index';

  /// Encrypts the optional platform autofill mirror.
  static const String infoAutofill = 'sablekey/v1/autofill';

  /// Encrypts attachment payloads.
  static const String infoAttachment = 'sablekey/v1/attachment';

  static Future<SecureBytes> subkey({
    required SecureBytes master,
    required String info,
    required Uint8List salt,
  }) async {
    final derived = await _hkdf.deriveKey(
      secretKey: SecretKey(master.bytes),
      nonce: salt,
      info: info.codeUnits,
    );
    final bytes = await derived.extractBytes();
    return SecureBytes.consume(Uint8List.fromList(bytes));
  }
}
