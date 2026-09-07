import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sablekey/data/backup.dart';
import 'package:sablekey/domain/models/item_type.dart';
import 'package:sablekey/domain/models/vault_item.dart';

void main() {
  final now = DateTime(2026, 3, 14);

  final items = [
    VaultItem(
      id: 'a',
      type: ItemType.login,
      name: 'GitHub',
      fields: const {
        'username': 'octocat',
        'password': 'correct-horse',
        'uri': 'https://github.com',
      },
      tags: const {'work'},
      notes: 'a note',
      favourite: true,
      createdAt: now,
      updatedAt: now,
    ),
    VaultItem(
      id: 'b',
      type: ItemType.card,
      name: 'Travel card',
      fields: const {'number': '4111111111111111', 'cvv': '123'},
      createdAt: now,
      updatedAt: now,
    ),
  ];

  final folders = [
    Folder(id: 'f1', name: 'Work', updatedAt: now),
  ];

  group('encrypted backup', () {
    test('round-trips items and folders', () async {
      final bytes = await VaultBackup.create(
        items: items,
        folders: folders,
        password: 'a backup password',
      );

      final restored = await VaultBackup.restore(
        fileBytes: bytes,
        password: 'a backup password',
      );

      expect(restored.items.length, 2);
      expect(restored.folders.length, 1);

      final github = restored.items.first;
      expect(github.name, 'GitHub');
      expect(github.fields['password'], 'correct-horse');
      expect(github.tags, {'work'});
      expect(github.favourite, isTrue);
      expect(restored.items[1].type, ItemType.card);
      expect(restored.items[1].fields['cvv'], '123');
    });

    test('the wrong password is rejected', () async {
      final bytes = await VaultBackup.create(
        items: items,
        folders: const [],
        password: 'right password',
      );

      expect(
        () => VaultBackup.restore(
            fileBytes: bytes, password: 'wrong password'),
        throwsA(isA<BackupException>()),
      );
    });

    test('no secret appears in the file', () async {
      final bytes = await VaultBackup.create(
        items: items,
        folders: folders,
        password: 'a backup password',
      );
      final text = utf8.decode(bytes);

      // The envelope is readable JSON by design; the payload must not be.
      expect(text.contains('correct-horse'), isFalse);
      expect(text.contains('octocat'), isFalse);
      expect(text.contains('4111111111111111'), isFalse);
      expect(text.contains('GitHub'), isFalse);
    });

    test('the envelope declares what it is without revealing content',
        () async {
      final bytes = await VaultBackup.create(
        items: items,
        folders: const [],
        password: 'a backup password',
      );

      final summary = VaultBackup.peek(bytes);
      expect(summary, isNotNull);
      expect(summary!['itemCount'], 2);
      expect(summary['version'], VaultBackup.formatVersion);
    });

    test('two backups of the same data differ', () async {
      final first = await VaultBackup.create(
        items: items,
        folders: const [],
        password: 'same password',
      );
      final second = await VaultBackup.create(
        items: items,
        folders: const [],
        password: 'same password',
      );
      // Fresh salt and fresh nonce each time.
      expect(first, isNot(equals(second)));
    });

    test('tampering with the payload is detected', () async {
      final bytes = await VaultBackup.create(
        items: items,
        folders: const [],
        password: 'a backup password',
      );

      final envelope =
          jsonDecode(utf8.decode(bytes)) as Map<String, Object?>;
      final payload = base64Decode(envelope['payload']! as String);
      payload[payload.length ~/ 2] ^= 0xFF;
      envelope['payload'] = base64Encode(payload);

      expect(
        () => VaultBackup.restore(
          fileBytes: Uint8List.fromList(utf8.encode(jsonEncode(envelope))),
          password: 'a backup password',
        ),
        throwsA(isA<BackupException>()),
      );
    });

    test('a downgraded KDF in the envelope is refused', () async {
      final bytes = await VaultBackup.create(
        items: items,
        folders: const [],
        password: 'a backup password',
      );

      final envelope =
          jsonDecode(utf8.decode(bytes)) as Map<String, Object?>;
      envelope['kdf'] = {'m': 8, 't': 1, 'p': 1, 'len': 32};

      expect(
        () => VaultBackup.restore(
          fileBytes: Uint8List.fromList(utf8.encode(jsonEncode(envelope))),
          password: 'a backup password',
        ),
        throwsA(isA<BackupException>()),
      );
    });

    test('a file that is not a backup gives a clear error', () async {
      expect(
        () => VaultBackup.restore(
          fileBytes: Uint8List.fromList(utf8.encode('just some text')),
          password: 'x',
        ),
        throwsA(isA<BackupException>()),
      );
      expect(
        VaultBackup.peek(Uint8List.fromList(utf8.encode('{"a":1}'))),
        isNull,
      );
    });

    test('a backup from a newer format version is refused', () async {
      final bytes = await VaultBackup.create(
        items: const [],
        folders: const [],
        password: 'a backup password',
      );
      final envelope =
          jsonDecode(utf8.decode(bytes)) as Map<String, Object?>;
      envelope['version'] = VaultBackup.formatVersion + 1;

      expect(
        () => VaultBackup.restore(
          fileBytes: Uint8List.fromList(utf8.encode(jsonEncode(envelope))),
          password: 'a backup password',
        ),
        throwsA(isA<BackupException>()),
      );
    });

    test('a too-short backup password is refused up front', () async {
      expect(
        () => VaultBackup.create(
            items: const [], folders: const [], password: 'short'),
        throwsA(isA<BackupException>()),
      );
    });

    test('an empty vault backs up and restores', () async {
      final bytes = await VaultBackup.create(
        items: const [],
        folders: const [],
        password: 'a backup password',
      );
      final restored = await VaultBackup.restore(
        fileBytes: bytes,
        password: 'a backup password',
      );
      expect(restored.items, isEmpty);
    });
  });

  group('file naming', () {
    test('is sortable and carries the extension', () {
      final name = VaultBackup.suggestedFileName(now: DateTime(2026, 3, 4, 9, 7));
      expect(name, 'sablekey-20260304-0907.skbak');
    });
  });

  group('item serialisation', () {
    test('survives a JSON round trip with everything populated', () {
      final full = VaultItem(
        id: 'x',
        type: ItemType.sshKey,
        name: 'Deploy key',
        fields: const {'label': 'deploy', 'privateKey': 'PRIVATE'},
        customFields: const [
          CustomField(label: 'Host', value: 'example.com'),
        ],
        tags: const {'infra', 'prod'},
        folderId: 'f1',
        notes: 'notes here',
        favourite: true,
        extraUris: const ['androidapp://com.example'],
        attachmentIds: const ['att1'],
        createdAt: now,
        updatedAt: now,
        passwordUpdatedAt: now,
        passwordHistory: [
          PasswordHistoryEntry(value: 'old', replacedAt: now),
        ],
        requireUnlockToReveal: true,
      );

      final restored = VaultItem.fromJson(full.toJson());

      expect(restored.id, 'x');
      expect(restored.type, ItemType.sshKey);
      expect(restored.fields['privateKey'], 'PRIVATE');
      expect(restored.customFields.first.label, 'Host');
      expect(restored.tags, {'infra', 'prod'});
      expect(restored.folderId, 'f1');
      expect(restored.extraUris, ['androidapp://com.example']);
      expect(restored.attachmentIds, ['att1']);
      expect(restored.passwordHistory.first.value, 'old');
      expect(restored.requireUnlockToReveal, isTrue);
    });

    test('an unknown item type degrades to a note instead of disappearing',
        () {
      final json = items.first.toJson()..['type'] = 'type-from-the-future';
      expect(VaultItem.fromJson(json).type, ItemType.secureNote);
    });
  });

  group('password history', () {
    test('an edit rolls the old password into history', () {
      final original = items.first;
      final edited = original.applyEdit(
        name: original.name,
        fields: {...original.fields, 'password': 'new-password'},
        customFields: const [],
        tags: original.tags,
        notes: original.notes,
        now: now.add(const Duration(days: 1)),
      );

      expect(edited.fields['password'], 'new-password');
      expect(edited.passwordHistory.first.value, 'correct-horse');
      expect(edited.passwordUpdatedAt, now.add(const Duration(days: 1)));
    });

    test('an edit that leaves the password alone adds no history', () {
      final original = items.first;
      final edited = original.applyEdit(
        name: 'Renamed',
        fields: original.fields,
        customFields: const [],
        tags: original.tags,
        notes: original.notes,
      );
      expect(edited.passwordHistory, isEmpty);
      expect(edited.name, 'Renamed');
    });

    test('history is capped', () {
      var item = items.first;
      for (var i = 0; i < VaultItem.maxHistoryEntries + 6; i++) {
        item = item.applyEdit(
          name: item.name,
          fields: {...item.fields, 'password': 'password-$i'},
          customFields: const [],
          tags: item.tags,
          notes: item.notes,
        );
      }
      expect(item.passwordHistory.length, VaultItem.maxHistoryEntries);
      // Newest first.
      expect(item.passwordHistory.first.value,
          'password-${VaultItem.maxHistoryEntries + 4}');
    });
  });
}
