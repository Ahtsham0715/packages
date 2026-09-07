import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';

import 'secure_bytes.dart';

/// Argon2id parameters for turning the master password into a master key.
///
/// The parameters are stored *in the vault header* rather than hardcoded, so a
/// vault created on a slow phone in 2026 still opens on a fast one in 2030, and
/// so the cost can be raised later without breaking existing vaults.
@immutable
class KdfParams {
  const KdfParams({
    required this.memoryKib,
    required this.iterations,
    required this.parallelism,
    this.hashLength = 32,
  });

  factory KdfParams.fromJson(Map<String, Object?> json) => KdfParams(
        memoryKib: json['m']! as int,
        iterations: json['t']! as int,
        parallelism: json['p']! as int,
        hashLength: (json['len'] as int?) ?? 32,
      );

  /// Roughly one second on a mid-range 2024 phone. The default for new vaults.
  static const KdfParams balanced =
      KdfParams(memoryKib: 65536, iterations: 3, parallelism: 4);

  /// For people who accept a slower unlock in exchange for a costlier guess.
  static const KdfParams hardened =
      KdfParams(memoryKib: 262144, iterations: 4, parallelism: 4);

  /// Only for tests and for low-memory devices that cannot hold 64 MiB.
  static const KdfParams reduced =
      KdfParams(memoryKib: 16384, iterations: 3, parallelism: 2);

  /// Anything weaker than this is refused when opening a vault, so a tampered
  /// header cannot talk the app into a cheap derivation.
  static const KdfParams floor =
      KdfParams(memoryKib: 8192, iterations: 2, parallelism: 1);

  final int memoryKib;
  final int iterations;
  final int parallelism;
  final int hashLength;

  Map<String, Object?> toJson() => {
        'm': memoryKib,
        't': iterations,
        'p': parallelism,
        'len': hashLength,
      };

  /// Rejects headers that would make brute-forcing the master password cheap.
  ///
  /// Without this check an attacker who can write to the database file could
  /// set m=8/t=1 and then test candidate passwords at enormous speed against
  /// the verifier. The vault refuses to open rather than deriving weakly.
  bool get meetsFloor =>
      memoryKib >= floor.memoryKib &&
      iterations >= floor.iterations &&
      parallelism >= floor.parallelism &&
      hashLength >= 32;

  @override
  bool operator ==(Object other) =>
      other is KdfParams &&
      other.memoryKib == memoryKib &&
      other.iterations == iterations &&
      other.parallelism == parallelism &&
      other.hashLength == hashLength;

  @override
  int get hashCode => Object.hash(memoryKib, iterations, parallelism, hashLength);

  @override
  String toString() =>
      'Argon2id(m=${memoryKib}KiB, t=$iterations, p=$parallelism)';
}

/// Argument bundle for the isolate hop. Must be a plain sendable object.
@immutable
class _DeriveRequest {
  const _DeriveRequest(this.password, this.salt, this.params);
  final Uint8List password;
  final Uint8List salt;
  final Map<String, Object?> params;
}

Future<Uint8List> _deriveInIsolate(_DeriveRequest request) async {
  final params = KdfParams.fromJson(request.params);
  final argon2 = Argon2id(
    memory: params.memoryKib,
    iterations: params.iterations,
    parallelism: params.parallelism,
    hashLength: params.hashLength,
  );
  final key = await argon2.deriveKey(
    secretKey: SecretKey(request.password),
    nonce: request.salt,
  );
  final bytes = await key.extractBytes();
  return Uint8List.fromList(bytes);
}

/// Password-based key derivation.
abstract final class Kdf {
  /// Length of the per-vault Argon2id salt.
  static const int saltLength = 32;

  /// Derives the master key from a password.
  ///
  /// Runs on a background isolate: at the default cost this occupies a core for
  /// about a second, and doing it on the UI isolate would freeze the unlock
  /// animation and make the app look hung.
  static Future<SecureBytes> deriveMasterKey({
    required String password,
    required Uint8List salt,
    required KdfParams params,
  }) async {
    if (!params.meetsFloor) {
      throw ArgumentError('KDF parameters below the accepted floor: $params');
    }
    if (salt.length < 16) {
      throw ArgumentError('salt must be at least 16 bytes');
    }

    // NFKC first: the same passphrase typed on two keyboards can be different
    // byte strings otherwise (composed vs decomposed accents, full-width
    // digits), which would lock the user out of their own vault.
    final normalized = Uint8List.fromList(utf8.encode(_normalize(password)));
    try {
      final raw = await compute(
        _deriveInIsolate,
        _DeriveRequest(normalized, salt, params.toJson()),
        debugLabel: 'sablekey.argon2id',
      );
      return SecureBytes.consume(raw);
    } finally {
      wipeBytes(normalized);
    }
  }

  /// Measures how long [candidate] takes on *this* device.
  ///
  /// Used at vault creation to pick parameters that are as expensive as the
  /// device can afford without making unlock painful.
  static Future<Duration> measure(KdfParams candidate) async {
    final watch = Stopwatch()..start();
    final key = await deriveMasterKey(
      password: 'calibration-probe',
      salt: Uint8List(saltLength),
      params: candidate,
    );
    watch.stop();
    key.destroy();
    return watch.elapsed;
  }

  /// Picks the strongest profile that stays under [budget] on this device.
  ///
  /// Falls back to [KdfParams.reduced] on hardware that cannot even manage the
  /// balanced profile in twice the budget — a vault that takes eight seconds to
  /// open is a vault the owner stops locking.
  static Future<KdfParams> calibrate({
    Duration budget = const Duration(milliseconds: 1200),
  }) async {
    final balancedTime = await measure(KdfParams.balanced);
    if (balancedTime > budget * 2) {
      return KdfParams.reduced;
    }
    if (balancedTime * 4 <= budget) {
      return KdfParams.hardened;
    }
    return KdfParams.balanced;
  }

  /// Unicode-normalising the password to NFKC.
  ///
  /// Dart has no NFKC in the core library, so this handles the cases that
  /// actually bite on mobile keyboards: non-breaking spaces, full-width Latin,
  /// and stray zero-width characters that some keyboards emit.
  static String _normalize(String password) {
    final buffer = StringBuffer();
    for (final rune in password.runes) {
      // Zero-width space / non-joiner / joiner / BOM: invisible, and different
      // keyboards insert them inconsistently.
      if (rune == 0x200B || rune == 0x200C || rune == 0x200D || rune == 0xFEFF) {
        continue;
      }
      // Full-width ASCII block maps down to plain ASCII.
      if (rune >= 0xFF01 && rune <= 0xFF5E) {
        buffer.writeCharCode(rune - 0xFEE0);
        continue;
      }
      // Every flavour of Unicode space becomes U+0020.
      if (rune == 0x00A0 ||
          (rune >= 0x2000 && rune <= 0x200A) ||
          rune == 0x202F ||
          rune == 0x205F ||
          rune == 0x3000) {
        buffer.writeCharCode(0x20);
        continue;
      }
      buffer.writeCharCode(rune);
    }
    return buffer.toString();
  }
}
