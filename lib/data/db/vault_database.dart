import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

/// The on-device SQLite store.
///
/// # What the database does and does not protect
///
/// Every secret is encrypted *before* it reaches SQLite, under keys that only
/// exist while the vault is unlocked. The columns beside each ciphertext hold
/// an opaque id and a pair of timestamps — nothing else. So an attacker who
/// copies `vault.db` off the device learns how many entries exist and roughly
/// when they were edited, and nothing about what they are.
///
/// That residual metadata is a deliberate trade: keeping timestamps in the
/// clear is what lets the app list, sort and page the vault without decrypting
/// every row, and it is what makes an interrupted write recoverable.
class VaultDatabase {
  VaultDatabase._(this._db);

  static const String fileName = 'vault.db';
  static const int schemaVersion = 1;

  // meta table keys.
  static const String metaHeader = 'header';
  static const String metaSettings = 'settings';
  static const String metaFailedAttempts = 'failed_attempts';
  static const String metaLockoutUntil = 'lockout_until';
  static const String metaAutofillMirror = 'autofill_mirror';

  final Database _db;

  Database get raw => _db;

  static Future<String> defaultPath() async {
    // Application support rather than documents: it is not exposed to the
    // Files app, and on Android it sits in the app's private data directory.
    final directory = await getApplicationSupportDirectory();
    await directory.create(recursive: true);
    return p.join(directory.path, fileName);
  }

  static Future<VaultDatabase> open({String? path}) async {
    final resolved = path ?? await defaultPath();
    final database = await openDatabase(
      resolved,
      version: schemaVersion,
      onConfigure: (db) async {
        // Cascade deletes so removing an item cannot strand its attachments.
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: _createSchema,
      onUpgrade: _upgradeSchema,
    );
    return VaultDatabase._(database);
  }

  static Future<void> _createSchema(Database db, int version) async {
    final batch = db.batch()
      ..execute('''
        CREATE TABLE meta (
          key   TEXT PRIMARY KEY,
          value BLOB NOT NULL
        )
      ''')
      ..execute('''
        CREATE TABLE items (
          id         TEXT PRIMARY KEY,
          blob       BLOB    NOT NULL,
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL,
          deleted_at INTEGER
        )
      ''')
      ..execute('CREATE INDEX idx_items_updated ON items (updated_at DESC)')
      ..execute('CREATE INDEX idx_items_deleted ON items (deleted_at)')
      ..execute('''
        CREATE TABLE folders (
          id         TEXT PRIMARY KEY,
          blob       BLOB    NOT NULL,
          updated_at INTEGER NOT NULL
        )
      ''')
      ..execute('''
        CREATE TABLE attachments (
          id         TEXT PRIMARY KEY,
          item_id    TEXT    NOT NULL,
          meta       BLOB    NOT NULL,
          payload    BLOB    NOT NULL,
          created_at INTEGER NOT NULL,
          FOREIGN KEY (item_id) REFERENCES items (id) ON DELETE CASCADE
        )
      ''')
      ..execute('CREATE INDEX idx_attachments_item ON attachments (item_id)')
      ..execute('''
        CREATE TABLE events (
          id   INTEGER PRIMARY KEY AUTOINCREMENT,
          at   INTEGER NOT NULL,
          blob BLOB    NOT NULL
        )
      ''')
      ..execute('CREATE INDEX idx_events_at ON events (at DESC)');
    await batch.commit(noResult: true);
  }

  /// Migrations run in order. Each step must be additive or must rewrite rows
  /// through the codec — a schema change that cannot be applied to an existing
  /// encrypted vault would lock the owner out of their own data.
  static Future<void> _upgradeSchema(
      Database db, int oldVersion, int newVersion) async {
    // v1 is the first release; no upgrade paths exist yet. New steps go here as
    //   if (oldVersion < 2) { await db.execute('ALTER TABLE ...'); }
  }

  // ---------------------------------------------------------------------
  // meta
  // ---------------------------------------------------------------------

  Future<List<int>?> readMeta(String key) async {
    final rows = await _db.query(
      'meta',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['value'] as List<int>?;
  }

  Future<void> writeMeta(String key, List<int> value) async {
    await _db.insert(
      'meta',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deleteMeta(String key) async {
    await _db.delete('meta', where: 'key = ?', whereArgs: [key]);
  }

  Future<bool> get hasVault async => (await readMeta(metaHeader)) != null;

  // ---------------------------------------------------------------------
  // Destructive operations
  // ---------------------------------------------------------------------

  /// Erases every row, then vacuums.
  ///
  /// The VACUUM matters: without it, deleted pages stay on disk with their
  /// ciphertext intact, and "wipe the vault" would be a lie at the filesystem
  /// level. The keys are gone either way, but leaving the bytes behind is not
  /// what someone triggering a panic wipe expects.
  Future<void> eraseEverything() async {
    await _db.transaction((txn) async {
      await txn.delete('attachments');
      await txn.delete('items');
      await txn.delete('folders');
      await txn.delete('events');
      await txn.delete('meta');
    });
    await _db.execute('VACUUM');
  }

  Future<int> countItems({bool includeDeleted = false}) async {
    final result = await _db.rawQuery(
      includeDeleted
          ? 'SELECT COUNT(*) AS c FROM items'
          : 'SELECT COUNT(*) AS c FROM items WHERE deleted_at IS NULL',
    );
    return (result.first['c'] as int?) ?? 0;
  }

  /// Approximate on-disk size, shown in settings.
  Future<int> fileSizeBytes() async {
    final file = File(_db.path);
    if (!file.existsSync()) return 0;
    return file.length();
  }

  Future<void> close() => _db.close();
}
