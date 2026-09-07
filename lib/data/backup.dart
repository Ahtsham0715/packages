import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../core/crypto/kdf.dart';
import '../core/crypto/sealed_box.dart';
import '../core/crypto/secure_bytes.dart';
import '../core/crypto/secure_random.dart';
import '../domain/models/vault_item.dart';

class BackupException implements Exception {
  const BackupException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// What came out of a backup file.
@immutable
class BackupContents {
  const BackupContents({
    required this.items,
    required this.folders,
    required this.createdAt,
  });

  final List<VaultItem> items;
  final List<Folder> folders;
  final DateTime createdAt;
}

/// Encrypted vault backups.
///
/// A backup is a self-contained file: its own salt, its own Argon2 parameters,
/// its own password. It is *not* wrapped under the vault's data key, because a
/// backup that can only be opened by the device that wrote it is not a backup —
/// it is a second copy of a file you already have, useless in exactly the case
/// you made it for.
///
/// The file is plain JSON on the outside so that a future version, or a
/// determined owner with a script, can always identify what they are holding.
/// Everything that matters is inside the sealed payload.
abstract final class VaultBackup {
  static const String magic = 'sablekey.backup';
  static const int formatVersion = 1;
  static const String fileExtension = 'skbak';

  /// Backups get a deliberately expensive KDF: unlike an unlock, this happens
  /// once, and the file may sit on cloud storage for years.
  static const KdfParams backupKdf = KdfParams.hardened;

  static Future<Uint8List> create({
    required List<VaultItem> items,
    required List<Folder> folders,
    required String password,
  }) async {
    if (password.length < 8) {
      throw const BackupException(
          'Choose a backup password of at least 8 characters.');
    }

    final salt = SecureRandom.bytes(Kdf.saltLength);
    final key = await Kdf.deriveMasterKey(
      password: password,
      salt: salt,
      params: backupKdf,
    );

    try {
      final payload = jsonEncode({
        'items': items.map((i) => i.toJson()).toList(),
        'folders': folders.map((f) => f.toJson()).toList(),
      });

      final sealed = await SealedBox.seal(
        key: key,
        plaintext: Uint8List.fromList(utf8.encode(payload)),
        aad: utf8.encode(magic),
      );

      final envelope = {
        'format': magic,
        'version': formatVersion,
        'createdAt': DateTime.now().toIso8601String(),
        'itemCount': items.length,
        'kdf': backupKdf.toJson(),
        'salt': base64Encode(salt),
        'payload': base64Encode(sealed),
      };
      return Uint8List.fromList(
          utf8.encode(const JsonEncoder.withIndent('  ').convert(envelope)));
    } finally {
      key.destroy();
    }
  }

  static Future<BackupContents> restore({
    required Uint8List fileBytes,
    required String password,
  }) async {
    final Map<String, Object?> envelope;
    try {
      envelope = jsonDecode(utf8.decode(fileBytes)) as Map<String, Object?>;
    } on Object {
      throw const BackupException(
          'This file is not a Sablekey backup, or it has been damaged.');
    }

    if (envelope['format'] != magic) {
      throw const BackupException('This file is not a Sablekey backup.');
    }
    final version = envelope['version'];
    if (version is! int || version > formatVersion) {
      throw const BackupException(
          'This backup was written by a newer version of Sablekey.');
    }

    final salt = base64Decode(envelope['salt']! as String);
    final params = KdfParams.fromJson(envelope['kdf']! as Map<String, Object?>);
    if (!params.meetsFloor) {
      throw const BackupException(
          'This backup declares key-derivation settings that are too weak to '
          'trust. It may have been altered.');
    }

    final key = await Kdf.deriveMasterKey(
      password: password,
      salt: salt,
      params: params,
    );

    try {
      final Uint8List clear;
      try {
        clear = await SealedBox.open(
          key: key,
          envelope: base64Decode(envelope['payload']! as String),
          aad: utf8.encode(magic),
        );
      } on DecryptionFailure {
        throw const BackupException(
            'Wrong password, or the backup has been altered.');
      }

      final payload = jsonDecode(utf8.decode(clear)) as Map<String, Object?>;
      final items = ((payload['items'] as List<Object?>?) ?? const [])
          .map((e) => VaultItem.fromJson(e! as Map<String, Object?>))
          .toList(growable: false);
      final folders = ((payload['folders'] as List<Object?>?) ?? const [])
          .map((e) => Folder.fromJson(e! as Map<String, Object?>))
          .toList(growable: false);

      return BackupContents(
        items: items,
        folders: folders,
        createdAt: DateTime.tryParse(envelope['createdAt'] as String? ?? '') ??
            DateTime.now(),
      );
    } finally {
      key.destroy();
    }
  }

  /// Reads the unencrypted header of a backup so the restore screen can show
  /// what it is about to open before asking for a password.
  static Map<String, Object?>? peek(Uint8List fileBytes) {
    try {
      final envelope = jsonDecode(utf8.decode(fileBytes)) as Map<String, Object?>;
      if (envelope['format'] != magic) return null;
      return {
        'version': envelope['version'],
        'createdAt': envelope['createdAt'],
        'itemCount': envelope['itemCount'],
      };
    } on Object {
      return null;
    }
  }

  static String suggestedFileName({DateTime? now}) {
    final at = now ?? DateTime.now();
    String two(int value) => value.toString().padLeft(2, '0');
    return 'sablekey-${at.year}${two(at.month)}${two(at.day)}'
        '-${two(at.hour)}${two(at.minute)}.$fileExtension';
  }
}

/// Wipes a decrypted backup buffer once it has been imported.
void disposeBackupBuffer(Uint8List buffer) => wipeBytes(buffer);
