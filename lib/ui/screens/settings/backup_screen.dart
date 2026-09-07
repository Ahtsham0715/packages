import 'dart:convert';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/backup.dart';
import '../../../data/csv_port.dart';
import '../../../data/models/security_event.dart';
import '../../../state/services.dart';
import '../../../state/vault_controller.dart';
import '../../theme/tokens.dart';
import '../../widgets/surfaces.dart';

/// Encrypted export, restore, and import from other managers.
class BackupScreen extends ConsumerStatefulWidget {
  const BackupScreen({super.key});

  @override
  ConsumerState<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends ConsumerState<BackupScreen> {
  bool _busy = false;

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  // ---------------------------------------------------------------------

  Future<void> _exportEncrypted() async {
    final vault = ref.read(vaultControllerProvider).requireValue;

    final password = await _promptForPassword(
      title: 'Password for this backup',
      body: 'The backup is encrypted with its own password, independent of '
          'your master password. Without it the file cannot be opened by '
          'anyone, including you.',
      confirm: true,
    );
    if (password == null) return;

    setState(() => _busy = true);
    try {
      final bytes = await VaultBackup.create(
        items: vault.items.where((item) => !item.isDeleted).toList(),
        folders: vault.folders,
        password: password,
      );

      final location = await getSaveLocation(
        suggestedName: VaultBackup.suggestedFileName(),
        acceptedTypeGroups: const [
          XTypeGroup(label: 'Sablekey backup', extensions: ['skbak']),
        ],
      );
      if (location == null) return;

      await XFile.fromData(bytes, name: VaultBackup.suggestedFileName())
          .saveTo(location.path);

      await ref
          .read(repositoryProvider)
          .logEvent(SecurityEvent.exported(format: 'encrypted'));
      _toast('Backup saved');
    } on BackupException catch (error) {
      _toast(error.message);
    } on Object catch (error) {
      _toast('Could not write the backup: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'Sablekey backup', extensions: ['skbak', 'json']),
      ],
    );
    if (file == null) return;

    final bytes = await file.readAsBytes();
    final summary = VaultBackup.peek(bytes);
    if (summary == null) {
      _toast('That file is not a Sablekey backup.');
      return;
    }

    if (!mounted) return;
    final password = await _promptForPassword(
      title: 'Backup password',
      body: 'Created ${summary['createdAt']} · '
          '${summary['itemCount']} entries.',
    );
    if (password == null) return;

    setState(() => _busy = true);
    try {
      final contents =
          await VaultBackup.restore(fileBytes: bytes, password: password);

      if (!mounted) return;
      final merge = await _confirmImport(contents.items.length);
      if (!merge) return;

      // Restored entries get new ids so a restore never overwrites something
      // added since the backup was taken. Duplicates are visible and
      // deletable; silently clobbered edits are not.
      await ref.read(vaultControllerProvider.notifier).importItems(
            contents.items
                .map((item) => item.copyWith(id: ''))
                .toList(growable: false),
          );
      _toast('Restored ${contents.items.length} entries');
    } on BackupException catch (error) {
      _toast(error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _importCsv() async {
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'CSV export', extensions: ['csv', 'txt']),
      ],
    );
    if (file == null) return;

    setState(() => _busy = true);
    try {
      final contents = utf8.decode(await file.readAsBytes(),
          allowMalformed: true);
      final result = CsvImporter.import(contents);

      if (!mounted) return;
      final proceed = await _confirmImport(
        result.items.length,
        detail: 'Detected format: ${result.detectedFormat}'
            '${result.skippedRows > 0 ? '\n${result.skippedRows} empty rows '
                'skipped.' : ''}'
            '${result.warnings.isNotEmpty ? '\n${result.warnings.length} rows '
                'had problems.' : ''}',
      );
      if (!proceed) return;

      await ref.read(vaultControllerProvider.notifier).importItems(result.items);
      _toast('Imported ${result.items.length} entries');

      if (!mounted) return;
      await _remindToDeleteExport();
    } on CsvException catch (error) {
      _toast(error.message);
    } on Object catch (error) {
      _toast('Could not read that file: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _exportCsv() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Export unencrypted?'),
        content: const Text(
          'A CSV holds every password in plain text. Anything that can read '
          'the file — a backup service, a file manager, whatever it is '
          'shared with — reads your passwords.\n\n'
          'Use this only to move into another password manager, and delete '
          'the file the moment you are done.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(backgroundColor: SableColors.danger),
            child: const Text('I understand'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final password = await _promptForPassword(
      title: 'Confirm your master password',
      body: 'Required before writing your passwords out in the clear.',
      isMasterPassword: true,
    );
    if (password == null) return;

    if (!await ref.read(repositoryProvider).verifyMasterPassword(password)) {
      _toast('That password is not correct');
      return;
    }

    final vault = ref.read(vaultControllerProvider).requireValue;
    final csv = CsvExporter.export(vault.items);

    final location = await getSaveLocation(suggestedName: 'sablekey-export.csv');
    if (location == null) return;

    await XFile.fromData(
      Uint8List.fromList(utf8.encode(csv)),
      name: 'sablekey-export.csv',
      mimeType: 'text/csv',
    ).saveTo(location.path);

    await ref
        .read(repositoryProvider)
        .logEvent(SecurityEvent.exported(format: 'csv-plaintext'));
    _toast('Exported. Delete that file once you are done with it.');
  }

  // ---------------------------------------------------------------------

  Future<String?> _promptForPassword({
    required String title,
    required String body,
    bool confirm = false,
    bool isMasterPassword = false,
  }) async {
    final first = TextEditingController();
    final second = TextEditingController();

    final result = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          final matches = !confirm || first.text == second.text;
          final longEnough = isMasterPassword || first.text.length >= 8;

          return AlertDialog(
            title: Text(title),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(body, style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: Space.lg),
                TextField(
                  controller: first,
                  obscureText: true,
                  autofocus: true,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(labelText: 'Password'),
                ),
                if (confirm) ...[
                  const SizedBox(height: Space.md),
                  TextField(
                    controller: second,
                    obscureText: true,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      labelText: 'Confirm',
                      errorText: matches ? null : 'These do not match',
                    ),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: matches && longEnough && first.text.isNotEmpty
                    ? () => Navigator.of(context).pop(first.text)
                    : null,
                child: const Text('Continue'),
              ),
            ],
          );
        },
      ),
    );

    first.dispose();
    second.dispose();
    return result;
  }

  Future<bool> _confirmImport(int count, {String? detail}) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Import $count ${count == 1 ? 'entry' : 'entries'}?'),
        content: Text(
          '${detail == null ? '' : '$detail\n\n'}'
          'These are added to your vault. Nothing already there is replaced.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Import'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _remindToDeleteExport() async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete the file you imported'),
        content: const Text(
          'That CSV still contains every password in plain text. Delete it '
          'from your device — and from wherever you downloaded it — now.',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Understood'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final vault = ref.watch(vaultControllerProvider).valueOrNull;
    if (vault == null || !vault.isUnlocked) return const SizedBox.shrink();

    return Scaffold(
      appBar: AppBar(title: const Text('Backup and import')),
      body: AbsorbPointer(
        absorbing: _busy,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
              Space.lg, 0, Space.lg, Space.huge),
          children: [
            const NoticeBanner(
              icon: Icons.cloud_off_rounded,
              message: 'Sablekey never uploads anything. A backup exists only '
                  'if you make one, and only where you put it.',
            ),

            const SectionHeader('Encrypted backup'),
            SableCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'A single file, sealed with its own password using Argon2id '
                    'at a deliberately high cost. Safe to keep in cloud storage '
                    '— what is inside is unreadable without that password.',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: Space.lg),
                  FilledButton.icon(
                    onPressed: _busy ? null : _exportEncrypted,
                    icon: const Icon(Icons.lock_rounded),
                    label: Text(
                      'Export ${vault.liveItems.length} entries',
                    ),
                  ),
                  const SizedBox(height: Space.md),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _restore,
                    icon: const Icon(Icons.restore_rounded),
                    label: const Text('Restore from a backup'),
                  ),
                ],
              ),
            ),

            const SectionHeader('Move in from another manager'),
            SableCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Reads CSV exports from Bitwarden, 1Password, LastPass, '
                    'KeePass, Dashlane, NordPass, Chrome and Edge.',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: Space.lg),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _importCsv,
                    icon: const Icon(Icons.file_upload_outlined),
                    label: const Text('Import a CSV'),
                  ),
                ],
              ),
            ),

            const SectionHeader('Move out'),
            SableCard(
              accent: SableColors.danger,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'You can always take your data elsewhere. A CSV export is '
                    'unencrypted by nature — every password in plain text.',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: Space.lg),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _exportCsv,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: SableColors.danger,
                      side: const BorderSide(color: SableColors.danger),
                    ),
                    icon: const Icon(Icons.warning_amber_rounded),
                    label: const Text('Export unencrypted CSV'),
                  ),
                ],
              ),
            ),

            if (_busy) ...[
              const SizedBox(height: Space.xl),
              const Center(child: CircularProgressIndicator()),
            ],
          ],
        ),
      ),
    );
  }
}
