import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import 'kdf.dart';

/// The public, unencrypted description of a vault.
///
/// Everything here is safe to read without the password: the salt, the cost
/// parameters, and two ciphertexts that are useless without the master key. It
/// is what lets the app show an unlock screen — and choose the right Argon2
/// parameters — before anyone has typed anything.
@immutable
class VaultHeader {
  const VaultHeader({
    required this.formatVersion,
    required this.salt,
    required this.kdfParams,
    required this.wrappedDek,
    required this.verifier,
    required this.createdAt,
    required this.lastRekeyedAt,
  });

  factory VaultHeader.fromJson(Map<String, Object?> json) {
    final version = json['v']! as int;
    if (version > currentFormatVersion) {
      // A newer build wrote this vault. Refusing is the only safe move: a
      // partial read followed by a write would corrupt data we cannot parse.
      throw VaultFormatException(
        'This vault was created by a newer version of Sablekey '
        '(format $version, this build understands $currentFormatVersion).',
      );
    }
    return VaultHeader(
      formatVersion: version,
      salt: base64Decode(json['salt']! as String),
      kdfParams: KdfParams.fromJson(json['kdf']! as Map<String, Object?>),
      wrappedDek: base64Decode(json['dek']! as String),
      verifier: base64Decode(json['verifier']! as String),
      createdAt: DateTime.fromMillisecondsSinceEpoch(json['created']! as int),
      lastRekeyedAt:
          DateTime.fromMillisecondsSinceEpoch(json['rekeyed']! as int),
    );
  }

  factory VaultHeader.decode(String source) =>
      VaultHeader.fromJson(jsonDecode(source) as Map<String, Object?>);

  static const int currentFormatVersion = 1;

  final int formatVersion;
  final Uint8List salt;
  final KdfParams kdfParams;

  /// The data encryption key, sealed under the key-encryption key.
  final Uint8List wrappedDek;

  /// A sealed constant used to check a password without unwrapping the DEK.
  final Uint8List verifier;

  final DateTime createdAt;
  final DateTime lastRekeyedAt;

  Map<String, Object?> toJson() => {
        'v': formatVersion,
        'salt': base64Encode(salt),
        'kdf': kdfParams.toJson(),
        'dek': base64Encode(wrappedDek),
        'verifier': base64Encode(verifier),
        'created': createdAt.millisecondsSinceEpoch,
        'rekeyed': lastRekeyedAt.millisecondsSinceEpoch,
      };

  String encode() => jsonEncode(toJson());

  VaultHeader copyWith({
    Uint8List? wrappedDek,
    Uint8List? verifier,
    Uint8List? salt,
    KdfParams? kdfParams,
    DateTime? lastRekeyedAt,
  }) =>
      VaultHeader(
        formatVersion: formatVersion,
        salt: salt ?? this.salt,
        kdfParams: kdfParams ?? this.kdfParams,
        wrappedDek: wrappedDek ?? this.wrappedDek,
        verifier: verifier ?? this.verifier,
        createdAt: createdAt,
        lastRekeyedAt: lastRekeyedAt ?? this.lastRekeyedAt,
      );
}

class VaultFormatException implements Exception {
  const VaultFormatException(this.message);
  final String message;
  @override
  String toString() => message;
}
