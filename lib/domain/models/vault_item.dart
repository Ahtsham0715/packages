import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';

import '../../core/crypto/totp.dart';
import 'field_spec.dart';
import 'item_type.dart';

/// A user-defined extra field on an item.
@immutable
class CustomField {
  const CustomField({
    required this.label,
    required this.value,
    this.kind = FieldKind.text,
  });

  factory CustomField.fromJson(Map<String, Object?> json) => CustomField(
        label: json['label']! as String,
        value: json['value']! as String,
        kind: FieldKind.values.firstWhere(
          (k) => k.name == json['kind'],
          orElse: () => FieldKind.text,
        ),
      );

  final String label;
  final String value;
  final FieldKind kind;

  Map<String, Object?> toJson() =>
      {'label': label, 'value': value, 'kind': kind.name};

  CustomField copyWith({String? label, String? value, FieldKind? kind}) =>
      CustomField(
        label: label ?? this.label,
        value: value ?? this.value,
        kind: kind ?? this.kind,
      );
}

/// One superseded password, kept so a botched rotation can be undone.
@immutable
class PasswordHistoryEntry {
  const PasswordHistoryEntry({required this.value, required this.replacedAt});

  factory PasswordHistoryEntry.fromJson(Map<String, Object?> json) =>
      PasswordHistoryEntry(
        value: json['value']! as String,
        replacedAt:
            DateTime.fromMillisecondsSinceEpoch(json['at']! as int),
      );

  final String value;
  final DateTime replacedAt;

  Map<String, Object?> toJson() =>
      {'value': value, 'at': replacedAt.millisecondsSinceEpoch};
}

/// One record in the vault.
///
/// Everything on this object is secret. It exists in memory only while the
/// vault is unlocked, and it is written to disk as a single authenticated
/// ciphertext — the database columns beside that ciphertext hold nothing but an
/// opaque id and timestamps.
@immutable
class VaultItem {
  const VaultItem({
    required this.id,
    required this.type,
    required this.name,
    required this.fields,
    required this.createdAt,
    required this.updatedAt,
    this.customFields = const [],
    this.tags = const {},
    this.folderId,
    this.notes = '',
    this.favourite = false,
    this.totp,
    this.attachmentIds = const [],
    this.extraUris = const [],
    this.deletedAt,
    this.lastUsedAt,
    this.useCount = 0,
    this.passwordUpdatedAt,
    this.passwordHistory = const [],
    this.requireUnlockToReveal = false,
  });

  factory VaultItem.blank(ItemType type) {
    final now = DateTime.now();
    return VaultItem(
      id: '',
      type: type,
      name: '',
      fields: const {},
      createdAt: now,
      updatedAt: now,
    );
  }

  factory VaultItem.fromJson(Map<String, Object?> json) => VaultItem(
        id: json['id']! as String,
        type: ItemType.fromId(json['type']! as String),
        name: json['name']! as String,
        fields: (json['fields'] as Map<Object?, Object?>? ?? const {})
            .map((key, value) => MapEntry(key! as String, value! as String)),
        customFields: ((json['custom'] as List<Object?>?) ?? const [])
            .map((e) => CustomField.fromJson(e! as Map<String, Object?>))
            .toList(growable: false),
        tags: ((json['tags'] as List<Object?>?) ?? const [])
            .map((e) => e! as String)
            .toSet(),
        folderId: json['folder'] as String?,
        notes: (json['notes'] as String?) ?? '',
        favourite: (json['fav'] as bool?) ?? false,
        totp: json['totp'] == null
            ? null
            : TotpConfig.fromJson(json['totp']! as Map<String, Object?>),
        attachmentIds: ((json['attachments'] as List<Object?>?) ?? const [])
            .map((e) => e! as String)
            .toList(growable: false),
        extraUris: ((json['uris'] as List<Object?>?) ?? const [])
            .map((e) => e! as String)
            .toList(growable: false),
        createdAt: DateTime.fromMillisecondsSinceEpoch(json['created']! as int),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(json['updated']! as int),
        deletedAt: json['deleted'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(json['deleted']! as int),
        lastUsedAt: json['used'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(json['used']! as int),
        useCount: (json['uses'] as int?) ?? 0,
        passwordUpdatedAt: json['pwAt'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(json['pwAt']! as int),
        passwordHistory: ((json['pwHistory'] as List<Object?>?) ?? const [])
            .map((e) => PasswordHistoryEntry.fromJson(e! as Map<String, Object?>))
            .toList(growable: false),
        requireUnlockToReveal: (json['reprompt'] as bool?) ?? false,
      );

  /// How many superseded passwords to keep. Unbounded history would grow the
  /// item blob without limit for anyone who rotates on a schedule.
  static const int maxHistoryEntries = 12;

  final String id;
  final ItemType type;
  final String name;

  /// Values keyed by [FieldSpec.key] for this item's type.
  final Map<String, String> fields;

  final List<CustomField> customFields;
  final Set<String> tags;
  final String? folderId;
  final String notes;
  final bool favourite;
  final TotpConfig? totp;
  final List<String> attachmentIds;

  /// Additional domains or package names this item should autofill on, beyond
  /// the primary URI. Covers the "same login, three domains" case.
  final List<String> extraUris;

  final DateTime createdAt;
  final DateTime updatedAt;

  /// Set when the item is in the trash. Non-null means hidden from the vault.
  final DateTime? deletedAt;

  final DateTime? lastUsedAt;
  final int useCount;

  final DateTime? passwordUpdatedAt;
  final List<PasswordHistoryEntry> passwordHistory;

  /// Ask for the master password again before revealing this item's secrets,
  /// even in an unlocked session.
  final bool requireUnlockToReveal;

  bool get isDeleted => deletedAt != null;

  String? get password =>
      type.passwordKey == null ? null : fields[type.passwordKey!];

  String? get primaryValue => fields[type.primaryKey];

  String? get uri => type.uriKey == null ? null : fields[type.uriKey!];

  /// Every URI this item should match for autofill.
  List<String> get allUris => [
        if (uri != null && uri!.trim().isNotEmpty) uri!.trim(),
        ...extraUris.where((u) => u.trim().isNotEmpty),
      ];

  String? get username {
    for (final spec in type.fields) {
      if (spec.kind == FieldKind.username || spec.kind == FieldKind.email) {
        final value = fields[spec.key];
        if (value != null && value.isNotEmpty) return value;
      }
    }
    return null;
  }

  /// Field values the audit should examine.
  Iterable<String> get auditedSecrets sync* {
    for (final spec in type.fields) {
      if (!spec.kind.isAudited) continue;
      final value = fields[spec.key];
      if (value != null && value.isNotEmpty) yield value;
    }
    for (final custom in customFields) {
      if (custom.kind.isAudited && custom.value.isNotEmpty) yield custom.value;
    }
  }

  /// Text that search indexes. Deliberately excludes secrets: matching a query
  /// against a password would let someone who can watch the result list
  /// confirm a guess without ever revealing it.
  String get searchableText {
    final buffer = StringBuffer()
      ..write(name)
      ..write(' ')
      ..write(type.label)
      ..write(' ')
      ..write(notes)
      ..write(' ')
      ..writeAll(tags, ' ');
    for (final spec in type.fields) {
      if (spec.isSecret) continue;
      final value = fields[spec.key];
      if (value != null) buffer
        ..write(' ')
        ..write(value);
    }
    for (final custom in customFields) {
      if (custom.kind.isSecret) continue;
      buffer
        ..write(' ')
        ..write(custom.label)
        ..write(' ')
        ..write(custom.value);
    }
    return buffer.toString();
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'type': type.id,
        'name': name,
        'fields': fields,
        if (customFields.isNotEmpty)
          'custom': customFields.map((f) => f.toJson()).toList(),
        if (tags.isNotEmpty) 'tags': tags.toList(),
        if (folderId != null) 'folder': folderId,
        if (notes.isNotEmpty) 'notes': notes,
        if (favourite) 'fav': true,
        if (totp != null) 'totp': totp!.toJson(),
        if (attachmentIds.isNotEmpty) 'attachments': attachmentIds,
        if (extraUris.isNotEmpty) 'uris': extraUris,
        'created': createdAt.millisecondsSinceEpoch,
        'updated': updatedAt.millisecondsSinceEpoch,
        if (deletedAt != null) 'deleted': deletedAt!.millisecondsSinceEpoch,
        if (lastUsedAt != null) 'used': lastUsedAt!.millisecondsSinceEpoch,
        if (useCount > 0) 'uses': useCount,
        if (passwordUpdatedAt != null)
          'pwAt': passwordUpdatedAt!.millisecondsSinceEpoch,
        if (passwordHistory.isNotEmpty)
          'pwHistory': passwordHistory.map((e) => e.toJson()).toList(),
        if (requireUnlockToReveal) 'reprompt': true,
      };

  VaultItem copyWith({
    String? id,
    ItemType? type,
    String? name,
    Map<String, String>? fields,
    List<CustomField>? customFields,
    Set<String>? tags,
    String? folderId,
    bool clearFolder = false,
    String? notes,
    bool? favourite,
    TotpConfig? totp,
    bool clearTotp = false,
    List<String>? attachmentIds,
    List<String>? extraUris,
    DateTime? updatedAt,
    DateTime? deletedAt,
    bool clearDeletedAt = false,
    DateTime? lastUsedAt,
    int? useCount,
    DateTime? passwordUpdatedAt,
    List<PasswordHistoryEntry>? passwordHistory,
    bool? requireUnlockToReveal,
  }) =>
      VaultItem(
        id: id ?? this.id,
        type: type ?? this.type,
        name: name ?? this.name,
        fields: fields ?? this.fields,
        customFields: customFields ?? this.customFields,
        tags: tags ?? this.tags,
        folderId: clearFolder ? null : (folderId ?? this.folderId),
        notes: notes ?? this.notes,
        favourite: favourite ?? this.favourite,
        totp: clearTotp ? null : (totp ?? this.totp),
        attachmentIds: attachmentIds ?? this.attachmentIds,
        extraUris: extraUris ?? this.extraUris,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        deletedAt: clearDeletedAt ? null : (deletedAt ?? this.deletedAt),
        lastUsedAt: lastUsedAt ?? this.lastUsedAt,
        useCount: useCount ?? this.useCount,
        passwordUpdatedAt: passwordUpdatedAt ?? this.passwordUpdatedAt,
        passwordHistory: passwordHistory ?? this.passwordHistory,
        requireUnlockToReveal:
            requireUnlockToReveal ?? this.requireUnlockToReveal,
      );

  /// Applies an edit, rolling the old password into history if it changed.
  ///
  /// Centralised here so no call site can forget: a rotation that silently
  /// discards the previous value strands the user when the new one is rejected
  /// by a site that never actually saved it.
  VaultItem applyEdit({
    required String name,
    required Map<String, String> fields,
    required List<CustomField> customFields,
    required Set<String> tags,
    required String notes,
    String? folderId,
    bool clearFolder = false,
    TotpConfig? totp,
    bool clearTotp = false,
    List<String>? extraUris,
    bool? requireUnlockToReveal,
    DateTime? now,
  }) {
    final at = now ?? DateTime.now();
    final passwordKey = type.passwordKey;
    final oldPassword = passwordKey == null ? null : this.fields[passwordKey];
    final newPassword = passwordKey == null ? null : fields[passwordKey];

    var history = passwordHistory;
    var passwordAt = passwordUpdatedAt;
    final changed = passwordKey != null &&
        oldPassword != null &&
        oldPassword.isNotEmpty &&
        newPassword != oldPassword;
    if (changed) {
      history = [
        PasswordHistoryEntry(value: oldPassword, replacedAt: at),
        ...passwordHistory,
      ].take(maxHistoryEntries).toList(growable: false);
      passwordAt = at;
    } else if (passwordAt == null && (newPassword?.isNotEmpty ?? false)) {
      passwordAt = at;
    }

    return copyWith(
      name: name,
      fields: fields,
      customFields: customFields,
      tags: tags,
      notes: notes,
      folderId: folderId,
      clearFolder: clearFolder,
      totp: totp,
      clearTotp: clearTotp,
      extraUris: extraUris,
      requireUnlockToReveal: requireUnlockToReveal,
      updatedAt: at,
      passwordHistory: history,
      passwordUpdatedAt: passwordAt,
    );
  }

  /// Records that the item was copied or autofilled, which feeds the
  /// most-used ordering on the home screen.
  VaultItem markUsed({DateTime? now}) => copyWith(
        lastUsedAt: now ?? DateTime.now(),
        useCount: useCount + 1,
      );

  @override
  bool operator ==(Object other) =>
      other is VaultItem &&
      other.id == id &&
      other.updatedAt == updatedAt &&
      other.name == name &&
      const MapEquality<String, String>().equals(other.fields, fields);

  @override
  int get hashCode => Object.hash(id, updatedAt, name);
}

/// A user-created grouping. Folders nest one level via [parentId].
@immutable
class Folder {
  const Folder({
    required this.id,
    required this.name,
    required this.updatedAt,
    this.parentId,
    this.colourValue,
  });

  factory Folder.fromJson(Map<String, Object?> json) => Folder(
        id: json['id']! as String,
        name: json['name']! as String,
        updatedAt: DateTime.fromMillisecondsSinceEpoch(json['updated']! as int),
        parentId: json['parent'] as String?,
        colourValue: json['colour'] as int?,
      );

  final String id;
  final String name;
  final DateTime updatedAt;
  final String? parentId;
  final int? colourValue;

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'updated': updatedAt.millisecondsSinceEpoch,
        if (parentId != null) 'parent': parentId,
        if (colourValue != null) 'colour': colourValue,
      };

  Folder copyWith({String? name, String? parentId, int? colourValue}) => Folder(
        id: id,
        name: name ?? this.name,
        updatedAt: DateTime.now(),
        parentId: parentId ?? this.parentId,
        colourValue: colourValue ?? this.colourValue,
      );
}

/// Metadata for an encrypted file attached to an item.
///
/// The payload lives in its own row, encrypted under the attachment subkey, so
/// opening a 40-item list never pulls megabytes of file data into memory.
@immutable
class Attachment {
  const Attachment({
    required this.id,
    required this.itemId,
    required this.fileName,
    required this.sizeBytes,
    required this.createdAt,
    this.mimeType,
  });

  factory Attachment.fromJson(Map<String, Object?> json) => Attachment(
        id: json['id']! as String,
        itemId: json['item']! as String,
        fileName: json['name']! as String,
        sizeBytes: json['size']! as int,
        createdAt: DateTime.fromMillisecondsSinceEpoch(json['created']! as int),
        mimeType: json['mime'] as String?,
      );

  final String id;
  final String itemId;
  final String fileName;
  final int sizeBytes;
  final DateTime createdAt;
  final String? mimeType;

  Map<String, Object?> toJson() => {
        'id': id,
        'item': itemId,
        'name': fileName,
        'size': sizeBytes,
        'created': createdAt.millisecondsSinceEpoch,
        if (mimeType != null) 'mime': mimeType,
      };

  String get humanSize {
    if (sizeBytes < 1024) return '$sizeBytes B';
    if (sizeBytes < 1024 * 1024) {
      return '${(sizeBytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
