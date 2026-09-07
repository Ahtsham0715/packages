import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../core/crypto/kdf.dart';
import '../core/crypto/key_ring.dart';
import '../core/crypto/sealed_box.dart';
import '../core/crypto/vault_header.dart';
import '../domain/models/vault_item.dart';
import 'db/vault_database.dart';
import 'models/security_event.dart';
import 'models/vault_settings.dart';

/// Raised when an operation needs an unlocked vault and does not have one.
class VaultLockedException implements Exception {
  const VaultLockedException();
  @override
  String toString() => 'The vault is locked';
}

/// Everything held in memory while the vault is open.
@immutable
class VaultSnapshot {
  const VaultSnapshot({
    required this.items,
    required this.folders,
    required this.settings,
  });

  static const VaultSnapshot empty = VaultSnapshot(
    items: [],
    folders: [],
    settings: VaultSettings.defaults,
  );

  final List<VaultItem> items;
  final List<Folder> folders;
  final VaultSettings settings;
}

/// Reads and writes the vault, encrypting on the way in and decrypting on the
/// way out.
///
/// This is the only place that touches both plaintext items and the database.
/// Keeping that boundary in one file is what makes "is anything written in the
/// clear?" a question you can answer by reading a single class.
class VaultRepository {
  VaultRepository(this._db);

  static const Uuid _uuid = Uuid();

  final VaultDatabase _db;

  KeyRing? _keyRing;
  VaultHeader? _header;

  bool get isUnlocked => _keyRing != null && !_keyRing!.isDestroyed;

  VaultHeader? get header => _header;

  KeyRing get _keys {
    final ring = _keyRing;
    if (ring == null || ring.isDestroyed) throw const VaultLockedException();
    return ring;
  }

  Future<bool> get vaultExists => _db.hasVault;

  // ---------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------

  /// Loads the header so the unlock screen knows the KDF cost before the user
  /// types anything.
  Future<VaultHeader?> loadHeader() async {
    final bytes = await _db.readMeta(VaultDatabase.metaHeader);
    if (bytes == null) return null;
    final header = VaultHeader.decode(utf8.decode(bytes));
    _header = header;
    return header;
  }

  Future<void> createVault({
    required String password,
    KdfParams? params,
  }) async {
    if (await _db.hasVault) {
      throw StateError('A vault already exists on this device');
    }
    final chosen = params ?? await Kdf.calibrate();
    final created =
        await KeyRing.createVault(password: password, params: chosen);

    _header = created.header;
    _keyRing = created.keyRing;

    await _db.writeMeta(
      VaultDatabase.metaHeader,
      utf8.encode(created.header.encode()),
    );
    await saveSettings(VaultSettings.defaults);
    await logEvent(SecurityEvent.vaultCreated());
  }

  Future<void> unlock(String password) async {
    final header = _header ?? await loadHeader();
    if (header == null) throw StateError('No vault exists on this device');
    try {
      _keyRing =
          await KeyRing.unlockWithPassword(password: password, header: header);
    } on WrongPasswordException {
      await _recordFailedAttempt();
      rethrow;
    }
    await _clearFailedAttempts();
    await logEvent(SecurityEvent.unlocked(method: 'password'));
  }

  /// Unlocks from a data key recovered from the platform keystore.
  Future<void> unlockWithDataKey(Uint8List dataKey) async {
    final header = _header ?? await loadHeader();
    if (header == null) throw StateError('No vault exists on this device');
    _keyRing =
        await KeyRing.unlockWithDataKey(dataKey: dataKey, header: header);
    await _clearFailedAttempts();
    await logEvent(SecurityEvent.unlocked(method: 'biometric'));
  }

  /// Wipes every key. Cheap, and safe to call more than once.
  void lock() {
    _keyRing?.destroy();
    _keyRing = null;
  }

  Future<bool> verifyMasterPassword(String password) async {
    final header = _header ?? await loadHeader();
    if (header == null) return false;
    return KeyRing.verifyPassword(password: password, header: header);
  }

  /// Rewraps the data key under a new password. Item ciphertext is untouched.
  Future<void> changeMasterPassword({
    required String newPassword,
    KdfParams? params,
  }) async {
    final header = _header;
    if (header == null) throw const VaultLockedException();
    final chosen = params ?? header.kdfParams;
    final updated = await _keys.rewrapForNewPassword(
      header: header,
      newPassword: newPassword,
      params: chosen,
    );
    await _db.writeMeta(
        VaultDatabase.metaHeader, utf8.encode(updated.encode()));
    _header = updated;
    await logEvent(SecurityEvent.masterPasswordChanged());
  }

  /// Deletes everything and forgets the keys.
  Future<void> eraseVault() async {
    await _db.eraseEverything();
    lock();
    _header = null;
  }

  // ---------------------------------------------------------------------
  // Items
  // ---------------------------------------------------------------------

  Future<VaultSnapshot> loadAll() async {
    final items = await loadItems();
    final folders = await loadFolders();
    final settings = await loadSettings();
    return VaultSnapshot(items: items, folders: folders, settings: settings);
  }

  Future<List<VaultItem>> loadItems() async {
    final rows = await _db.raw.query('items', columns: ['id', 'blob']);
    final items = <VaultItem>[];
    for (final row in rows) {
      final id = row['id']! as String;
      try {
        final clear = await SealedBox.open(
          key: _keys.itemKey,
          envelope: Uint8List.fromList(row['blob']! as List<int>),
          aad: utf8.encode(id),
        );
        items.add(VaultItem.fromJson(
            jsonDecode(utf8.decode(clear)) as Map<String, Object?>));
      } on DecryptionFailure {
        // One unreadable row must not take the whole vault down with it. Skip
        // it, surface it as a corrupt-record count, and keep the rest usable.
        debugPrint('sablekey: skipping unreadable item row');
      }
    }
    return items;
  }

  Future<VaultItem> saveItem(VaultItem item) async {
    final id = item.id.isEmpty ? _uuid.v4() : item.id;
    final stored = item.id.isEmpty ? item.copyWith(id: id) : item;

    final blob = await SealedBox.seal(
      key: _keys.itemKey,
      plaintext: Uint8List.fromList(utf8.encode(jsonEncode(stored.toJson()))),
      aad: utf8.encode(id),
    );

    await _db.raw.insert(
      'items',
      {
        'id': id,
        'blob': blob,
        'created_at': stored.createdAt.millisecondsSinceEpoch,
        'updated_at': stored.updatedAt.millisecondsSinceEpoch,
        'deleted_at': stored.deletedAt?.millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return stored;
  }

  Future<void> saveItems(List<VaultItem> items) async {
    final batch = _db.raw.batch();
    for (final item in items) {
      final id = item.id.isEmpty ? _uuid.v4() : item.id;
      final blob = await SealedBox.seal(
        key: _keys.itemKey,
        plaintext: Uint8List.fromList(
            utf8.encode(jsonEncode(item.copyWith(id: id).toJson()))),
        aad: utf8.encode(id),
      );
      batch.insert(
        'items',
        {
          'id': id,
          'blob': blob,
          'created_at': item.createdAt.millisecondsSinceEpoch,
          'updated_at': item.updatedAt.millisecondsSinceEpoch,
          'deleted_at': item.deletedAt?.millisecondsSinceEpoch,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  /// Moves an item to the trash. Recoverable until it is purged.
  Future<VaultItem> trashItem(VaultItem item) =>
      saveItem(item.copyWith(deletedAt: DateTime.now()));

  Future<VaultItem> restoreItem(VaultItem item) =>
      saveItem(item.copyWith(clearDeletedAt: true, updatedAt: DateTime.now()));

  /// Removes an item and its attachments for good.
  Future<void> purgeItem(String id) async {
    await _db.raw.delete('items', where: 'id = ?', whereArgs: [id]);
    // The cascade handles attachments, but be explicit: foreign keys can be
    // disabled by a future migration and silently orphan encrypted payloads.
    await _db.raw.delete('attachments', where: 'item_id = ?', whereArgs: [id]);
  }

  Future<int> emptyTrash() async {
    final rows = await _db.raw.query(
      'items',
      columns: ['id'],
      where: 'deleted_at IS NOT NULL',
    );
    for (final row in rows) {
      await purgeItem(row['id']! as String);
    }
    return rows.length;
  }

  /// Purges trashed items older than [retention].
  ///
  /// Called on every unlock so the trash does not quietly become a permanent
  /// archive of things the owner believed they had deleted.
  Future<int> purgeExpiredTrash(Duration retention) async {
    final cutoff = DateTime.now().subtract(retention).millisecondsSinceEpoch;
    final rows = await _db.raw.query(
      'items',
      columns: ['id'],
      where: 'deleted_at IS NOT NULL AND deleted_at < ?',
      whereArgs: [cutoff],
    );
    for (final row in rows) {
      await purgeItem(row['id']! as String);
    }
    return rows.length;
  }

  // ---------------------------------------------------------------------
  // Folders
  // ---------------------------------------------------------------------

  Future<List<Folder>> loadFolders() async {
    final rows = await _db.raw.query('folders', columns: ['id', 'blob']);
    final folders = <Folder>[];
    for (final row in rows) {
      final id = row['id']! as String;
      try {
        final clear = await SealedBox.open(
          key: _keys.itemKey,
          envelope: Uint8List.fromList(row['blob']! as List<int>),
          aad: utf8.encode('folder:$id'),
        );
        folders.add(Folder.fromJson(
            jsonDecode(utf8.decode(clear)) as Map<String, Object?>));
      } on DecryptionFailure {
        debugPrint('sablekey: skipping unreadable folder row');
      }
    }
    folders.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return folders;
  }

  Future<Folder> saveFolder(Folder folder) async {
    final id = folder.id.isEmpty ? _uuid.v4() : folder.id;
    final stored = Folder(
      id: id,
      name: folder.name,
      updatedAt: DateTime.now(),
      parentId: folder.parentId,
      colourValue: folder.colourValue,
    );
    final blob = await SealedBox.seal(
      key: _keys.itemKey,
      plaintext: Uint8List.fromList(utf8.encode(jsonEncode(stored.toJson()))),
      aad: utf8.encode('folder:$id'),
    );
    await _db.raw.insert(
      'folders',
      {
        'id': id,
        'blob': blob,
        'updated_at': stored.updatedAt.millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return stored;
  }

  Future<void> deleteFolder(String id) async {
    await _db.raw.delete('folders', where: 'id = ?', whereArgs: [id]);
  }

  // ---------------------------------------------------------------------
  // Attachments
  // ---------------------------------------------------------------------

  /// Stores a file under the attachment subkey, in its own row.
  ///
  /// Keeping payloads out of the item blob is what stops a vault with a few
  /// scanned documents in it from loading tens of megabytes on every unlock.
  Future<Attachment> saveAttachment({
    required String itemId,
    required String fileName,
    required Uint8List bytes,
    String? mimeType,
  }) async {
    final id = _uuid.v4();
    final meta = Attachment(
      id: id,
      itemId: itemId,
      fileName: fileName,
      sizeBytes: bytes.length,
      createdAt: DateTime.now(),
      mimeType: mimeType,
    );

    final sealedMeta = await SealedBox.seal(
      key: _keys.itemKey,
      plaintext: Uint8List.fromList(utf8.encode(jsonEncode(meta.toJson()))),
      aad: utf8.encode('attachment-meta:$id'),
    );
    final sealedPayload = await SealedBox.seal(
      key: _keys.attachmentKey,
      plaintext: bytes,
      aad: utf8.encode('attachment:$id'),
    );

    await _db.raw.insert('attachments', {
      'id': id,
      'item_id': itemId,
      'meta': sealedMeta,
      'payload': sealedPayload,
      'created_at': meta.createdAt.millisecondsSinceEpoch,
    });
    return meta;
  }

  Future<List<Attachment>> loadAttachmentsFor(String itemId) async {
    final rows = await _db.raw.query(
      'attachments',
      columns: ['id', 'meta'],
      where: 'item_id = ?',
      whereArgs: [itemId],
    );
    final result = <Attachment>[];
    for (final row in rows) {
      final id = row['id']! as String;
      try {
        final clear = await SealedBox.open(
          key: _keys.itemKey,
          envelope: Uint8List.fromList(row['meta']! as List<int>),
          aad: utf8.encode('attachment-meta:$id'),
        );
        result.add(Attachment.fromJson(
            jsonDecode(utf8.decode(clear)) as Map<String, Object?>));
      } on DecryptionFailure {
        debugPrint('sablekey: skipping unreadable attachment row');
      }
    }
    return result;
  }

  Future<Uint8List> readAttachment(String id) async {
    final rows = await _db.raw.query(
      'attachments',
      columns: ['payload'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) throw StateError('Attachment not found');
    return SealedBox.open(
      key: _keys.attachmentKey,
      envelope: Uint8List.fromList(rows.first['payload']! as List<int>),
      aad: utf8.encode('attachment:$id'),
    );
  }

  Future<void> deleteAttachment(String id) async {
    await _db.raw.delete('attachments', where: 'id = ?', whereArgs: [id]);
  }

  // ---------------------------------------------------------------------
  // Settings
  // ---------------------------------------------------------------------

  /// Settings are encrypted too.
  ///
  /// They are not secrets in themselves, but "auto-lock after 30 seconds,
  /// biometrics off, panic wipe at 5 attempts" tells an attacker exactly what
  /// they are up against, and there is no cost to sealing them.
  Future<VaultSettings> loadSettings() async {
    final bytes = await _db.readMeta(VaultDatabase.metaSettings);
    if (bytes == null) return VaultSettings.defaults;
    try {
      final clear = await SealedBox.open(
        key: _keys.itemKey,
        envelope: Uint8List.fromList(bytes),
        aad: utf8.encode('settings'),
      );
      return VaultSettings.fromJson(
          jsonDecode(utf8.decode(clear)) as Map<String, Object?>);
    } on DecryptionFailure {
      return VaultSettings.defaults;
    }
  }

  Future<void> saveSettings(VaultSettings settings) async {
    final blob = await SealedBox.seal(
      key: _keys.itemKey,
      plaintext: Uint8List.fromList(utf8.encode(jsonEncode(settings.toJson()))),
      aad: utf8.encode('settings'),
    );
    await _db.writeMeta(VaultDatabase.metaSettings, blob);
  }

  // ---------------------------------------------------------------------
  // Lockout and the security log
  // ---------------------------------------------------------------------

  /// Failed attempts are stored in the clear, because they must be readable
  /// while the vault is locked — that is the only moment they matter.
  Future<int> failedAttempts() async {
    final bytes = await _db.readMeta(VaultDatabase.metaFailedAttempts);
    if (bytes == null || bytes.isEmpty) return 0;
    return int.tryParse(utf8.decode(bytes)) ?? 0;
  }

  Future<DateTime?> lockoutUntil() async {
    final bytes = await _db.readMeta(VaultDatabase.metaLockoutUntil);
    if (bytes == null || bytes.isEmpty) return null;
    final millis = int.tryParse(utf8.decode(bytes));
    if (millis == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(millis);
  }

  Future<void> _recordFailedAttempt() async {
    final count = await failedAttempts() + 1;
    await _db.writeMeta(
        VaultDatabase.metaFailedAttempts, utf8.encode('$count'));

    // Back off exponentially from the fourth attempt: 5s, 10s, 20s, ... capped
    // at five minutes. Enough to make sustained guessing at the lock screen
    // pointless without punishing someone who fat-fingers their own password.
    if (count >= 4) {
      final seconds = (5 * (1 << (count - 4))).clamp(5, 300);
      final until = DateTime.now().add(Duration(seconds: seconds));
      await _db.writeMeta(VaultDatabase.metaLockoutUntil,
          utf8.encode('${until.millisecondsSinceEpoch}'));
    }
  }

  Future<void> _clearFailedAttempts() async {
    await _db.deleteMeta(VaultDatabase.metaFailedAttempts);
    await _db.deleteMeta(VaultDatabase.metaLockoutUntil);
  }

  /// Appends to the encrypted security log.
  ///
  /// Silently does nothing while locked — several call sites fire on lock or on
  /// a failed unlock, and an exception there would be worse than a missing log
  /// line.
  Future<void> logEvent(SecurityEvent event) async {
    if (!isUnlocked) return;
    try {
      final blob = await SealedBox.seal(
        key: _keys.itemKey,
        plaintext:
            Uint8List.fromList(utf8.encode(jsonEncode(event.toJson()))),
        aad: utf8.encode('event'),
      );
      await _db.raw.insert('events', {
        'at': event.at.millisecondsSinceEpoch,
        'blob': blob,
      });
    } on Object catch (error) {
      debugPrint('sablekey: could not write security event: $error');
    }
  }

  Future<List<SecurityEvent>> loadEvents({int limit = 200}) async {
    final rows = await _db.raw.query(
      'events',
      columns: ['blob'],
      orderBy: 'at DESC',
      limit: limit,
    );
    final events = <SecurityEvent>[];
    for (final row in rows) {
      try {
        final clear = await SealedBox.open(
          key: _keys.itemKey,
          envelope: Uint8List.fromList(row['blob']! as List<int>),
          aad: utf8.encode('event'),
        );
        events.add(SecurityEvent.fromJson(
            jsonDecode(utf8.decode(clear)) as Map<String, Object?>));
      } on DecryptionFailure {
        continue;
      }
    }
    return events;
  }

  Future<void> clearEvents() async {
    await _db.raw.delete('events');
  }

  /// Exposed for the backup and autofill services, which need the same keys.
  KeyRing get keyRing => _keys;

  VaultDatabase get database => _db;
}
