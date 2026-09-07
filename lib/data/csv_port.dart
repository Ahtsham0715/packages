import 'package:flutter/foundation.dart';

import '../core/crypto/totp.dart';
import '../domain/models/field_spec.dart';
import '../domain/models/item_type.dart';
import '../domain/models/vault_item.dart';

class CsvException implements Exception {
  const CsvException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// An RFC 4180 CSV reader.
///
/// Written here rather than pulled in as a dependency: the format is small, and
/// the export files this parses come from other password managers, so it is
/// worth being able to read exactly what the parser does with a quoted field
/// containing a comma, a newline, or a doubled quote.
abstract final class Csv {
  static List<List<String>> parse(String input) {
    final rows = <List<String>>[];
    var row = <String>[];
    final field = StringBuffer();
    var inQuotes = false;
    var i = 0;

    // A byte-order mark at the start of a Windows-generated export would
    // otherwise become part of the first header name and break every mapping.
    if (input.isNotEmpty && input.codeUnitAt(0) == 0xFEFF) i = 1;

    void endField() {
      row.add(field.toString());
      field.clear();
    }

    void endRow() {
      endField();
      // Skip blank trailing lines rather than emitting an empty item.
      if (row.length > 1 || row.first.trim().isNotEmpty) rows.add(row);
      row = <String>[];
    }

    while (i < input.length) {
      final char = input[i];

      if (inQuotes) {
        if (char == '"') {
          if (i + 1 < input.length && input[i + 1] == '"') {
            field.write('"');
            i += 2;
            continue;
          }
          inQuotes = false;
          i++;
          continue;
        }
        field.write(char);
        i++;
        continue;
      }

      switch (char) {
        case '"':
          inQuotes = true;
          i++;
        case ',':
          endField();
          i++;
        case '\r':
          // Handle CRLF and a bare CR alike.
          if (i + 1 < input.length && input[i + 1] == '\n') i++;
          endRow();
          i++;
        case '\n':
          endRow();
          i++;
        default:
          field.write(char);
          i++;
      }
    }

    if (field.isNotEmpty || row.isNotEmpty) endRow();
    return rows;
  }

  static String escapeField(String value) {
    if (value.contains(RegExp(r'[",\r\n]'))) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }

  static String write(List<List<String>> rows) {
    return rows.map((row) => row.map(escapeField).join(',')).join('\r\n');
  }
}

/// The result of reading someone else's export.
@immutable
class CsvImportResult {
  const CsvImportResult({
    required this.items,
    required this.detectedFormat,
    required this.skippedRows,
    required this.warnings,
  });

  final List<VaultItem> items;

  /// A best guess at which manager produced the file, for the confirmation
  /// screen.
  final String detectedFormat;

  final int skippedRows;
  final List<String> warnings;
}

/// Imports CSV exports from other password managers.
///
/// Rather than hardcoding one layout per product, this maps *column names* onto
/// roles. Every mainstream manager names its columns from the same small
/// vocabulary, so header sniffing handles Bitwarden, 1Password, LastPass,
/// Chrome, KeePass, Dashlane, NordPass and Keeper with one code path — and
/// degrades sensibly on an export this code has never seen.
abstract final class CsvImporter {
  /// Header names that map onto each role, in priority order.
  static const Map<_Role, List<String>> _headerAliases = {
    _Role.name: [
      'name', 'title', 'account', 'account name', 'entry', 'item name',
      'display name', 'login_name',
    ],
    _Role.username: [
      'username', 'login_username', 'user name', 'user', 'login', 'email',
      'e-mail', 'login_uri_username', 'account', 'userid',
    ],
    _Role.password: [
      'password', 'login_password', 'pass', 'passwd', 'secret',
    ],
    _Role.url: [
      'url', 'urls', 'login_uri', 'uri', 'website', 'site', 'web site',
      'login url', 'link',
    ],
    _Role.notes: [
      'notes', 'note', 'extra', 'comments', 'comment', 'description',
    ],
    _Role.totp: [
      'totp', 'login_totp', 'otpauth', 'otp', 'otpsecret', 'otp secret',
      'two factor', '2fa',
    ],
    _Role.folder: [
      'folder', 'grouping', 'group', 'category', 'collection', 'path',
    ],
    _Role.favourite: ['favorite', 'favourite', 'fav', 'starred'],
    _Role.type: ['type'],
  };

  static CsvImportResult import(String contents) {
    final rows = Csv.parse(contents);
    if (rows.isEmpty) {
      throw const CsvException('That file is empty.');
    }

    final headers = rows.first.map((h) => h.trim().toLowerCase()).toList();
    final mapping = _mapColumns(headers);

    if (mapping[_Role.password] == null && mapping[_Role.notes] == null) {
      throw const CsvException(
        'No password or notes column was found. Make sure you exported a CSV '
        'from your previous password manager, and that the first row contains '
        'column names.',
      );
    }

    final items = <VaultItem>[];
    final warnings = <String>[];
    var skipped = 0;
    final now = DateTime.now();

    for (var r = 1; r < rows.length; r++) {
      final row = rows[r];
      String? cell(_Role role) {
        final index = mapping[role];
        if (index == null || index >= row.length) return null;
        final value = row[index].trim();
        return value.isEmpty ? null : value;
      }

      final name = cell(_Role.name) ??
          cell(_Role.url) ??
          cell(_Role.username) ??
          'Untitled';
      final password = cell(_Role.password);
      final username = cell(_Role.username);
      final url = cell(_Role.url);
      final notes = cell(_Role.notes) ?? '';

      // A row with nothing usable is noise from a trailing newline or a
      // section separator, not data.
      if (password == null && username == null && url == null && notes.isEmpty) {
        skipped++;
        continue;
      }

      final isNote = password == null && username == null && url == null;
      final type = isNote ? ItemType.secureNote : ItemType.login;

      TotpConfig? totp;
      final totpRaw = cell(_Role.totp);
      if (totpRaw != null) {
        try {
          totp = Totp.parseFlexible(totpRaw);
        } on OtpParseException {
          warnings.add('Row ${r + 1}: the two-factor secret could not be read '
              'and was skipped.');
        }
      }

      final fields = <String, String>{};
      if (isNote) {
        fields['body'] = notes;
      } else {
        if (username != null) fields['username'] = username;
        if (password != null) fields['password'] = password;
        if (url != null) fields['uri'] = _firstUri(url);
      }

      final tags = <String>{};
      final folder = cell(_Role.folder);
      if (folder != null) {
        // Nested paths become tags: a one-level folder model plus tags covers
        // the same ground without inventing a hierarchy the user did not ask
        // this app to keep.
        tags.addAll(folder
            .split(RegExp(r'[/\\>]'))
            .map((part) => part.trim())
            .where((part) => part.isNotEmpty));
      }

      final favouriteRaw = cell(_Role.favourite)?.toLowerCase();
      final favourite =
          favouriteRaw == '1' || favouriteRaw == 'true' || favouriteRaw == 'yes';

      items.add(VaultItem(
        id: '',
        type: type,
        name: name,
        fields: fields,
        notes: isNote ? '' : notes,
        tags: tags,
        favourite: favourite,
        totp: totp,
        createdAt: now,
        updatedAt: now,
        passwordUpdatedAt: password == null ? null : now,
      ));
    }

    return CsvImportResult(
      items: items,
      detectedFormat: _detectFormat(headers),
      skippedRows: skipped,
      warnings: warnings,
    );
  }

  static Map<_Role, int> _mapColumns(List<String> headers) {
    final mapping = <_Role, int>{};
    final taken = <int>{};

    for (final entry in _headerAliases.entries) {
      for (final alias in entry.value) {
        final index = headers.indexOf(alias);
        // Do not let one column satisfy two roles: LastPass has both a "name"
        // and a "username", and letting "account" claim both produces items
        // whose title is their password's owner.
        if (index >= 0 && !taken.contains(index)) {
          mapping[entry.key] = index;
          taken.add(index);
          break;
        }
      }
    }
    return mapping;
  }

  /// Some managers export several URIs in one cell, newline or comma
  /// separated. Take the first and keep the item simple.
  static String _firstUri(String raw) {
    final parts = raw.split(RegExp(r'[\n,;]'));
    return parts.first.trim();
  }

  static String _detectFormat(List<String> headers) {
    final joined = headers.join(',');
    if (joined.contains('login_uri') && joined.contains('reprompt')) {
      return 'Bitwarden';
    }
    if (joined.contains('grouping') && joined.contains('extra')) {
      return 'LastPass';
    }
    if (joined.contains('otpauth')) return '1Password';
    if (joined.contains('otpsecret')) return 'Dashlane';
    if (headers.length == 5 &&
        joined.contains('name') &&
        joined.contains('url') &&
        joined.contains('note')) {
      return 'Chrome or Edge';
    }
    if (joined.contains('group') && joined.contains('title')) return 'KeePass';
    return 'Generic CSV';
  }
}

/// Writes a plaintext CSV.
///
/// This exists only so nobody is locked into Sablekey — the ability to leave is
/// part of trusting a password manager. The output is unencrypted by
/// definition, so the UI puts that in front of the user in as many words,
/// requires the master password first, and steers them to an encrypted `.skbak`
/// backup for anything that is not a one-time migration.
abstract final class CsvExporter {
  static String export(List<VaultItem> items) {
    final rows = <List<String>>[
      ['name', 'type', 'username', 'password', 'url', 'totp', 'notes', 'tags'],
    ];

    for (final item in items.where((i) => !i.isDeleted)) {
      rows.add([
        item.name,
        item.type.id,
        item.username ?? '',
        item.password ?? '',
        item.allUris.join(' '),
        item.totp?.toUri() ?? '',
        _notesFor(item),
        item.tags.join(' '),
      ]);
    }
    return Csv.write(rows);
  }

  /// Folds any field the CSV shape has no column for into the notes, so an
  /// export never silently loses a passport number or a card PIN.
  static String _notesFor(VaultItem item) {
    final buffer = StringBuffer(item.notes);
    final skipped = <String>[];

    for (final spec in item.type.fields) {
      if (spec.key == item.type.passwordKey || spec.key == item.type.uriKey) {
        continue;
      }
      if (spec.kind == FieldKind.username) continue;
      final value = item.fields[spec.key];
      if (value == null || value.isEmpty) continue;
      skipped.add('${spec.label}: $value');
    }
    for (final custom in item.customFields) {
      if (custom.value.isEmpty) continue;
      skipped.add('${custom.label}: ${custom.value}');
    }

    if (skipped.isEmpty) return buffer.toString();
    if (buffer.isNotEmpty) buffer.write('\n\n');
    buffer.writeAll(skipped, '\n');
    return buffer.toString();
  }
}

enum _Role { name, username, password, url, notes, totp, folder, favourite, type }
