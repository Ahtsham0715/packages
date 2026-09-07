import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/services/password_generator.dart';
import '../../../state/services.dart';
import '../../../state/vault_controller.dart';
import '../../theme/sable_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/surfaces.dart';

enum GeneratorMode { password, passphrase, pin, username }

/// The generator, as a full tab.
class GeneratorScreen extends StatelessWidget {
  const GeneratorScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(Space.xl, Space.lg, Space.xl, Space.huge),
        children: [
          Text('Generate', style: theme.textTheme.headlineMedium),
          const SizedBox(height: 2),
          Text(
            'Every value here comes from the operating system\'s secure '
            'random source.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: Space.xl),
          const GeneratorPanel(),
        ],
      ),
    );
  }
}

/// The generator controls plus the current value.
///
/// Shared by the tab and by the sheet the editor opens, so the two can never
/// drift apart in behaviour.
class GeneratorPanel extends ConsumerStatefulWidget {
  const GeneratorPanel({this.onUse, super.key});

  /// When set, a "Use this" button is shown that returns the value.
  final ValueChanged<String>? onUse;

  @override
  ConsumerState<GeneratorPanel> createState() => _GeneratorPanelState();
}

class _GeneratorPanelState extends ConsumerState<GeneratorPanel> {
  GeneratorMode _mode = GeneratorMode.password;
  GeneratorOptions _options = const GeneratorOptions();
  PassphraseOptions _passphrase = const PassphraseOptions();
  int _pinLength = 6;

  GeneratedSecret? _current;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _regenerate());
  }

  void _regenerate() {
    final generator = ref.read(generatorProvider);
    try {
      final result = switch (_mode) {
        GeneratorMode.password => generator.generatePassword(_options),
        GeneratorMode.passphrase => generator.generatePassphrase(_passphrase),
        GeneratorMode.pin => generator.generatePin(length: _pinLength),
        GeneratorMode.username => generator.generateUsername(),
      };
      setState(() {
        _current = result;
        _error = null;
      });
    } on Object catch (error) {
      setState(() => _error = error.toString());
    }
  }

  Future<void> _copy() async {
    final value = _current?.value;
    if (value == null) return;

    final clipboard = ref.read(clipboardProvider);
    final settings = ref.read(vaultControllerProvider).valueOrNull?.settings;
    clipboard.clearAfter =
        Duration(seconds: settings?.clipboardClearSeconds ?? 30);
    await clipboard.copySecret(value);

    if (!mounted) return;
    HapticFeedback.selectionClick();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Copied')));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final generator = ref.watch(generatorProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<GeneratorMode>(
          segments: const [
            ButtonSegment(
              value: GeneratorMode.password,
              label: Text('Password'),
            ),
            ButtonSegment(
              value: GeneratorMode.passphrase,
              label: Text('Phrase'),
            ),
            ButtonSegment(value: GeneratorMode.pin, label: Text('PIN')),
            ButtonSegment(value: GeneratorMode.username, label: Text('User')),
          ],
          selected: {_mode},
          showSelectedIcon: false,
          onSelectionChanged: (selection) {
            setState(() => _mode = selection.first);
            _regenerate();
          },
        ),

        const SizedBox(height: Space.xl),
        _Output(
          secret: _current,
          error: _error,
          onCopy: _copy,
          onRegenerate: _regenerate,
        ),

        const SizedBox(height: Space.xl),
        switch (_mode) {
          GeneratorMode.password => _PasswordControls(
              options: _options,
              onChanged: (options) {
                setState(() => _options = options);
                _regenerate();
              },
            ),
          GeneratorMode.passphrase => _PassphraseControls(
              options: _passphrase,
              bitsPerWord: generator.bitsPerWord,
              wordlistSize: generator.wordlistSize,
              onChanged: (options) {
                setState(() => _passphrase = options);
                _regenerate();
              },
            ),
          GeneratorMode.pin => _PinControls(
              length: _pinLength,
              onChanged: (length) {
                setState(() => _pinLength = length);
                _regenerate();
              },
            ),
          GeneratorMode.username => Text(
              'Two words from the bundled list plus a number — useful where a '
              'site insists on a handle you will never type again.',
              style: theme.textTheme.bodySmall,
            ),
        },

        if (widget.onUse != null && _current != null) ...[
          const SizedBox(height: Space.xl),
          FilledButton(
            onPressed: () => widget.onUse!(_current!.value),
            child: const Text('Use this'),
          ),
        ],
      ],
    );
  }
}

class _Output extends StatelessWidget {
  const _Output({
    required this.secret,
    required this.error,
    required this.onCopy,
    required this.onRegenerate,
  });

  final GeneratedSecret? secret;
  final String? error;
  final VoidCallback onCopy;
  final VoidCallback onRegenerate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (error != null) {
      return NoticeBanner(
        tone: NoticeTone.danger,
        icon: Icons.error_outline_rounded,
        message: error!,
      );
    }

    final value = secret?.value ?? '';
    final bits = secret?.entropyBits ?? 0;

    return SableCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectableText(
            value,
            style: SableTheme.mono(context, size: 18),
          ),
          const SizedBox(height: Space.lg),
          Row(
            children: [
              Icon(
                Icons.bolt_rounded,
                size: 15,
                color: _colourFor(bits),
              ),
              const SizedBox(width: Space.xs),
              Text(
                '${bits.round()} bits of entropy',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: _colourFor(bits),
                ),
              ),
              const Spacer(),
              IconButton(
                onPressed: onRegenerate,
                icon: const Icon(Icons.refresh_rounded),
                tooltip: 'Generate another',
              ),
              IconButton(
                onPressed: onCopy,
                icon: const Icon(Icons.copy_rounded),
                tooltip: 'Copy',
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Thresholds match the strength estimator's bands, so a generated value and
  /// a typed one of the same strength are never described differently.
  static Color _colourFor(double bits) {
    if (bits < 40) return SableColors.strengthScale[1];
    if (bits < 60) return SableColors.strengthScale[2];
    if (bits < 80) return SableColors.strengthScale[3];
    return SableColors.strengthScale[4];
  }
}

class _PasswordControls extends StatelessWidget {
  const _PasswordControls({required this.options, required this.onChanged});

  final GeneratorOptions options;
  final ValueChanged<GeneratorOptions> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Length', style: theme.textTheme.labelLarge),
            const Spacer(),
            Text('${options.length}', style: theme.textTheme.labelLarge),
          ],
        ),
        Slider(
          value: options.length.toDouble(),
          min: 8,
          max: 64,
          divisions: 56,
          onChanged: (value) =>
              onChanged(options.copyWith(length: value.round())),
        ),
        const SizedBox(height: Space.sm),
        _Toggle(
          label: 'Lowercase  a-z',
          value: options.useLowercase,
          onChanged: (value) => onChanged(options.copyWith(useLowercase: value)),
        ),
        _Toggle(
          label: 'Uppercase  A-Z',
          value: options.useUppercase,
          onChanged: (value) => onChanged(options.copyWith(useUppercase: value)),
        ),
        _Toggle(
          label: 'Digits  0-9',
          value: options.useDigits,
          onChanged: (value) => onChanged(options.copyWith(useDigits: value)),
        ),
        _Toggle(
          label: r'Symbols  !@#$',
          value: options.useSymbols,
          onChanged: (value) => onChanged(options.copyWith(useSymbols: value)),
        ),
        const Divider(height: Space.xl),
        _Toggle(
          label: 'Avoid look-alike characters',
          subtitle: 'Excludes I l 1 O 0 and similar',
          value: options.avoidAmbiguous,
          onChanged: (value) =>
              onChanged(options.copyWith(avoidAmbiguous: value)),
        ),
        _Toggle(
          label: 'Require every selected class',
          subtitle: 'For sites that insist on one of each',
          value: options.requireEveryClass,
          onChanged: (value) =>
              onChanged(options.copyWith(requireEveryClass: value)),
        ),
      ],
    );
  }
}

class _PassphraseControls extends StatelessWidget {
  const _PassphraseControls({
    required this.options,
    required this.bitsPerWord,
    required this.wordlistSize,
    required this.onChanged,
  });

  final PassphraseOptions options;
  final double bitsPerWord;
  final int wordlistSize;
  final ValueChanged<PassphraseOptions> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Words', style: theme.textTheme.labelLarge),
            const Spacer(),
            Text('${options.wordCount}', style: theme.textTheme.labelLarge),
          ],
        ),
        Slider(
          value: options.wordCount.toDouble(),
          min: PassphraseOptions.minWords.toDouble(),
          max: PassphraseOptions.maxWords.toDouble(),
          divisions: PassphraseOptions.maxWords - PassphraseOptions.minWords,
          onChanged: (value) =>
              onChanged(options.copyWith(wordCount: value.round())),
        ),
        Text(
          '$wordlistSize words in the list, so each one adds '
          '${bitsPerWord.toStringAsFixed(1)} bits.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: Space.lg),
        Row(
          children: [
            Text('Separator', style: theme.textTheme.labelLarge),
            const Spacer(),
            for (final separator in const ['-', '.', '_', ' ', ''])
              Padding(
                padding: const EdgeInsets.only(left: Space.sm),
                child: ChoiceChip(
                  label: Text(separator.isEmpty ? 'none' : separator),
                  selected: options.separator == separator,
                  onSelected: (_) =>
                      onChanged(options.copyWith(separator: separator)),
                ),
              ),
          ],
        ),
        const SizedBox(height: Space.md),
        _Toggle(
          label: 'Capitalise each word',
          value: options.capitalise,
          onChanged: (value) => onChanged(options.copyWith(capitalise: value)),
        ),
        _Toggle(
          label: 'Add a digit',
          value: options.includeNumber,
          onChanged: (value) =>
              onChanged(options.copyWith(includeNumber: value)),
        ),
        _Toggle(
          label: 'Add a symbol',
          value: options.includeSymbol,
          onChanged: (value) =>
              onChanged(options.copyWith(includeSymbol: value)),
        ),
      ],
    );
  }
}

class _PinControls extends StatelessWidget {
  const _PinControls({required this.length, required this.onChanged});

  final int length;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Digits', style: theme.textTheme.labelLarge),
            const Spacer(),
            Text('$length', style: theme.textTheme.labelLarge),
          ],
        ),
        Slider(
          value: length.toDouble(),
          min: 4,
          max: 12,
          divisions: 8,
          onChanged: (value) => onChanged(value.round()),
        ),
        Text(
          'A PIN is short by definition. Use one only where the thing checking '
          'it limits attempts.',
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _Toggle extends StatelessWidget {
  const _Toggle({
    required this.label,
    required this.value,
    required this.onChanged,
    this.subtitle,
  });

  final String label;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      value: value,
      onChanged: onChanged,
      title: Text(label),
      subtitle: subtitle == null ? null : Text(subtitle!),
      contentPadding: EdgeInsets.zero,
      dense: true,
    );
  }
}
