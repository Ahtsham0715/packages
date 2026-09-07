import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/crypto/totp.dart';
import '../../../domain/models/field_spec.dart';
import '../../../domain/models/vault_item.dart';
import '../../../domain/services/password_strength.dart';
import '../../../state/services.dart';
import '../../../state/vault_controller.dart';
import '../../theme/sable_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/strength_meter.dart';
import '../../widgets/surfaces.dart';
import '../generator/generator_sheet.dart';
import '../scanner/qr_scan_screen.dart';

/// Create or edit an entry.
///
/// The form is built from the item type's field table, so a new type needs no
/// changes here at all.
class ItemEditorScreen extends ConsumerStatefulWidget {
  const ItemEditorScreen({required this.item, super.key});

  final VaultItem item;

  @override
  ConsumerState<ItemEditorScreen> createState() => _ItemEditorScreenState();
}

class _ItemEditorScreenState extends ConsumerState<ItemEditorScreen> {
  late final TextEditingController _name;
  late final TextEditingController _notes;
  late final Map<String, TextEditingController> _fields;

  late List<CustomField> _customFields;
  late Set<String> _tags;
  late List<String> _extraUris;
  TotpConfig? _totp;
  late bool _requireUnlock;

  PasswordStrength _passwordStrength = PasswordStrength.empty;
  bool _dirty = false;

  bool get _isNew => widget.item.id.isEmpty;

  @override
  void initState() {
    super.initState();
    final item = widget.item;

    _name = TextEditingController(text: item.name)..addListener(_markDirty);
    _notes = TextEditingController(text: item.notes)..addListener(_markDirty);
    _fields = {
      for (final spec in item.type.fields)
        spec.key: TextEditingController(text: item.fields[spec.key] ?? '')
          ..addListener(_markDirty),
    };

    _customFields = [...item.customFields];
    _tags = {...item.tags};
    _extraUris = [...item.extraUris];
    _totp = item.totp;
    _requireUnlock = item.requireUnlockToReveal;

    final passwordKey = item.type.passwordKey;
    if (passwordKey != null) {
      _fields[passwordKey]!.addListener(_evaluatePassword);
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _evaluatePassword());
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _notes.dispose();
    for (final controller in _fields.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _markDirty() {
    if (!_dirty) setState(() => _dirty = true);
  }

  void _evaluatePassword() {
    final key = widget.item.type.passwordKey;
    if (key == null) return;
    final estimator = ref.read(estimatorProvider);
    setState(() => _passwordStrength = estimator.evaluate(_fields[key]!.text));
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Give this entry a name')),
      );
      return;
    }

    final values = <String, String>{};
    for (final entry in _fields.entries) {
      final value = entry.value.text;
      if (value.isNotEmpty) values[entry.key] = value;
    }

    final settings = ref.read(vaultControllerProvider).requireValue.settings;
    if (settings.warnOnWeakOnSave &&
        _passwordStrength.entropyBits > 0 &&
        _passwordStrength.score <= 1) {
      final proceed = await _confirmWeak();
      if (!proceed) return;
    }

    final now = DateTime.now();
    final item = _isNew
        ? VaultItem(
            id: '',
            type: widget.item.type,
            name: name,
            fields: values,
            customFields: _customFields,
            tags: _tags,
            notes: _notes.text,
            totp: _totp,
            extraUris: _extraUris,
            requireUnlockToReveal: _requireUnlock,
            createdAt: now,
            updatedAt: now,
            passwordUpdatedAt:
                widget.item.type.passwordKey == null ? null : now,
          )
        : widget.item.applyEdit(
            name: name,
            fields: values,
            customFields: _customFields,
            tags: _tags,
            notes: _notes.text,
            totp: _totp,
            clearTotp: _totp == null,
            extraUris: _extraUris,
            requireUnlockToReveal: _requireUnlock,
            now: now,
          );

    await ref.read(vaultControllerProvider.notifier).saveItem(item);
    if (mounted) Navigator.of(context).pop();
  }

  Future<bool> _confirmWeak() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Save a weak password?'),
        content: Text(
          '${_passwordStrength.label} — an offline attacker would need about '
          '${_passwordStrength.offlineCrackTime}.\n\n'
          'The generator can produce something far stronger in one tap.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Go back'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Save anyway'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _generateInto(String key) async {
    final generated = await showGeneratorSheet(context);
    if (generated == null) return;
    _fields[key]!.text = generated;
    _evaluatePassword();
  }

  Future<void> _addTotp() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.qr_code_scanner_rounded),
              title: const Text('Scan a QR code'),
              subtitle: const Text('The camera never leaves this screen'),
              onTap: () => Navigator.of(context).pop('scan'),
            ),
            ListTile(
              leading: const Icon(Icons.content_paste_rounded),
              title: const Text('Paste a setup key'),
              subtitle: const Text('A base32 secret or an otpauth:// link'),
              onTap: () => Navigator.of(context).pop('paste'),
            ),
            const SizedBox(height: Space.md),
          ],
        ),
      ),
    );

    if (!mounted || choice == null) return;

    String? raw;
    if (choice == 'scan') {
      raw = await Navigator.of(context).push<String>(
        MaterialPageRoute(builder: (_) => const QrScanScreen()),
      );
    } else {
      raw = await _promptForText(
        title: 'Two-factor setup key',
        hint: 'JBSWY3DPEHPK3PXP or otpauth://…',
      );
    }

    if (raw == null || raw.trim().isEmpty || !mounted) return;

    try {
      setState(() {
        _totp = Totp.parseFlexible(raw!);
        _dirty = true;
      });
    } on OtpParseException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  Future<String?> _promptForText({
    required String title,
    String? hint,
    String initial = '',
  }) async {
    final controller = TextEditingController(text: initial);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          autocorrect: false,
          decoration: InputDecoration(hintText: hint),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Done'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final type = widget.item.type;
    final passwordKey = type.passwordKey;

    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final discard = await _confirmDiscard();
        if (discard && mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_isNew ? 'New ${type.label.toLowerCase()}' : 'Edit'),
          actions: [
            TextButton(onPressed: _save, child: const Text('Save')),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.huge),
          children: [
            TextField(
              controller: _name,
              autofocus: _isNew,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            const SizedBox(height: Space.lg),

            for (final spec in type.fields) ...[
              _FieldEditor(
                spec: spec,
                controller: _fields[spec.key]!,
                onGenerate: spec.key == passwordKey
                    ? () => _generateInto(spec.key)
                    : null,
              ),
              if (spec.key == passwordKey &&
                  _fields[spec.key]!.text.isNotEmpty) ...[
                const SizedBox(height: Space.md),
                StrengthMeter(strength: _passwordStrength, compact: true),
              ],
              const SizedBox(height: Space.lg),
            ],

            if (type.supportsTotp) ...[
              const SectionHeader('Two-factor'),
              if (_totp == null)
                OutlinedButton.icon(
                  onPressed: _addTotp,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Add a two-factor code'),
                )
              else
                SableCard(
                  child: Row(
                    children: [
                      const Icon(Icons.timer_outlined, size: 18),
                      const SizedBox(width: Space.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _totp!.issuer ?? 'Two-factor code',
                              style: theme.textTheme.bodyLarge,
                            ),
                            Text(
                              '${_totp!.algorithm.label}, ${_totp!.digits} '
                              'digits, every ${_totp!.period}s',
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => setState(() {
                          _totp = null;
                          _dirty = true;
                        }),
                        icon: const Icon(Icons.delete_outline_rounded),
                        tooltip: 'Remove',
                      ),
                    ],
                  ),
                ),
            ],

            const SectionHeader('Notes'),
            TextField(
              controller: _notes,
              minLines: 3,
              maxLines: 12,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'Anything else worth keeping with this entry',
              ),
            ),

            _TagEditor(
              tags: _tags,
              onChanged: (tags) => setState(() {
                _tags = tags;
                _dirty = true;
              }),
            ),

            _CustomFieldEditor(
              fields: _customFields,
              onChanged: (fields) => setState(() {
                _customFields = fields;
                _dirty = true;
              }),
            ),

            if (type.uriKey != null)
              _ExtraUriEditor(
                uris: _extraUris,
                onChanged: (uris) => setState(() {
                  _extraUris = uris;
                  _dirty = true;
                }),
              ),

            const SectionHeader('Protection'),
            SwitchListTile(
              value: _requireUnlock,
              onChanged: (value) => setState(() {
                _requireUnlock = value;
                _dirty = true;
              }),
              title: const Text('Ask for my master password again'),
              subtitle: const Text(
                'Require re-authentication before revealing this entry, even '
                'in an already-unlocked session.',
              ),
              contentPadding: EdgeInsets.zero,
            ),
          ],
        ),
      ),
    );
  }

  Future<bool> _confirmDiscard() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard changes?'),
        content: const Text('This entry has unsaved edits.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep editing'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    return result ?? false;
  }
}

class _FieldEditor extends StatefulWidget {
  const _FieldEditor({
    required this.spec,
    required this.controller,
    this.onGenerate,
  });

  final FieldSpec spec;
  final TextEditingController controller;
  final VoidCallback? onGenerate;

  @override
  State<_FieldEditor> createState() => _FieldEditorState();
}

class _FieldEditorState extends State<_FieldEditor> {
  late bool _obscure = widget.spec.isSecret;

  @override
  Widget build(BuildContext context) {
    final spec = widget.spec;
    final multiline = spec.kind == FieldKind.multiline;

    return TextField(
      controller: widget.controller,
      obscureText: _obscure,
      keyboardType: spec.kind.keyboardType,
      autocorrect: !spec.isSecret && spec.kind != FieldKind.url,
      enableSuggestions: !spec.isSecret,
      minLines: multiline ? 3 : 1,
      maxLines: multiline ? 10 : 1,
      style: spec.isSecret && !_obscure ? SableTheme.mono(context) : null,
      inputFormatters: [
        if (spec.kind == FieldKind.cardNumber)
          FilteringTextInputFormatter.allow(RegExp(r'[0-9 ]')),
        if (spec.kind == FieldKind.pin || spec.kind == FieldKind.number)
          FilteringTextInputFormatter.digitsOnly,
      ],
      decoration: InputDecoration(
        labelText: spec.label,
        hintText: spec.hint,
        suffixIcon: spec.isSecret || widget.onGenerate != null
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.onGenerate != null)
                    IconButton(
                      onPressed: widget.onGenerate,
                      icon: const Icon(Icons.casino_rounded, size: 20),
                      tooltip: 'Generate',
                    ),
                  if (spec.isSecret)
                    IconButton(
                      onPressed: () => setState(() => _obscure = !_obscure),
                      icon: Icon(
                        _obscure
                            ? Icons.visibility_rounded
                            : Icons.visibility_off_rounded,
                        size: 20,
                      ),
                      tooltip: _obscure ? 'Show' : 'Hide',
                    ),
                ],
              )
            : null,
      ),
    );
  }
}

class _TagEditor extends StatelessWidget {
  const _TagEditor({required this.tags, required this.onChanged});

  final Set<String> tags;
  final ValueChanged<Set<String>> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('Tags'),
        Wrap(
          spacing: Space.sm,
          runSpacing: Space.sm,
          children: [
            for (final tag in tags)
              Chip(
                label: Text(tag),
                onDeleted: () => onChanged({...tags}..remove(tag)),
              ),
            ActionChip(
              avatar: const Icon(Icons.add_rounded, size: 15),
              label: const Text('Add'),
              onPressed: () async {
                final tag = await _prompt(context, 'New tag');
                if (tag != null && tag.trim().isNotEmpty) {
                  onChanged({...tags, tag.trim()});
                }
              },
            ),
          ],
        ),
      ],
    );
  }
}

class _ExtraUriEditor extends StatelessWidget {
  const _ExtraUriEditor({required this.uris, required this.onChanged});

  final List<String> uris;
  final ValueChanged<List<String>> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('Also fills on'),
        Text(
          'Extra domains or Android packages this entry should be offered for.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: Space.md),
        Wrap(
          spacing: Space.sm,
          runSpacing: Space.sm,
          children: [
            for (final uri in uris)
              Chip(
                label: Text(uri),
                onDeleted: () => onChanged([...uris]..remove(uri)),
              ),
            ActionChip(
              avatar: const Icon(Icons.add_rounded, size: 15),
              label: const Text('Add'),
              onPressed: () async {
                final uri = await _prompt(
                  context,
                  'Domain or package',
                  hint: 'example.com or androidapp://com.example',
                );
                if (uri != null && uri.trim().isNotEmpty) {
                  onChanged([...uris, uri.trim()]);
                }
              },
            ),
          ],
        ),
      ],
    );
  }
}

class _CustomFieldEditor extends StatelessWidget {
  const _CustomFieldEditor({required this.fields, required this.onChanged});

  final List<CustomField> fields;
  final ValueChanged<List<CustomField>> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('Custom fields'),
        for (var i = 0; i < fields.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.md),
            child: Row(
              children: [
                Expanded(
                  child: TextFormField(
                    initialValue: fields[i].label,
                    decoration: const InputDecoration(labelText: 'Label'),
                    onChanged: (value) {
                      final updated = [...fields];
                      updated[i] = updated[i].copyWith(label: value);
                      onChanged(updated);
                    },
                  ),
                ),
                const SizedBox(width: Space.md),
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    initialValue: fields[i].value,
                    obscureText: fields[i].kind.isSecret,
                    decoration: const InputDecoration(labelText: 'Value'),
                    onChanged: (value) {
                      final updated = [...fields];
                      updated[i] = updated[i].copyWith(value: value);
                      onChanged(updated);
                    },
                  ),
                ),
                IconButton(
                  onPressed: () => onChanged([...fields]..removeAt(i)),
                  icon: const Icon(Icons.close_rounded, size: 19),
                  tooltip: 'Remove',
                ),
              ],
            ),
          ),
        Row(
          children: [
            ActionChip(
              avatar: const Icon(Icons.add_rounded, size: 15),
              label: const Text('Text field'),
              onPressed: () => onChanged([
                ...fields,
                const CustomField(label: '', value: ''),
              ]),
            ),
            const SizedBox(width: Space.sm),
            ActionChip(
              avatar: const Icon(Icons.lock_outline_rounded, size: 15),
              label: const Text('Hidden field'),
              onPressed: () => onChanged([
                ...fields,
                const CustomField(
                    label: '', value: '', kind: FieldKind.secret),
              ]),
            ),
          ],
        ),
      ],
    );
  }
}

Future<String?> _prompt(BuildContext context, String title, {String? hint}) {
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        autocorrect: false,
        decoration: InputDecoration(hintText: hint),
        onSubmitted: (value) => Navigator.of(context).pop(value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(controller.text),
          child: const Text('Add'),
        ),
      ],
    ),
  ).whenComplete(controller.dispose);
}
