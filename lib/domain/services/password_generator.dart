import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../core/crypto/secure_random.dart';

/// Character classes a generated password may draw from.
class GeneratorOptions {
  const GeneratorOptions({
    this.length = 20,
    this.useLowercase = true,
    this.useUppercase = true,
    this.useDigits = true,
    this.useSymbols = true,
    this.avoidAmbiguous = true,
    this.requireEveryClass = true,
    this.symbolSet = defaultSymbols,
  });

  static const String lowercase = 'abcdefghijklmnopqrstuvwxyz';
  static const String uppercase = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
  static const String digits = '0123456789';
  static const String defaultSymbols = r'!@#$%^&*()-_=+[]{};:,.?/';

  /// Glyphs that are hard to tell apart when read off a screen or a printed
  /// recovery sheet. Excluding them costs about 0.3 bits per character and
  /// saves a genuinely common support problem.
  static const String ambiguous = 'Il1O0o|`\'"~,;:.{}[]()/\\';

  static const int minLength = 4;
  static const int maxLength = 128;

  final int length;
  final bool useLowercase;
  final bool useUppercase;
  final bool useDigits;
  final bool useSymbols;
  final bool avoidAmbiguous;

  /// Insist that every enabled class appears at least once.
  ///
  /// Satisfied by rejection sampling rather than by placing one character per
  /// class and shuffling — the latter subtly biases the output distribution.
  final bool requireEveryClass;

  final String symbolSet;

  GeneratorOptions copyWith({
    int? length,
    bool? useLowercase,
    bool? useUppercase,
    bool? useDigits,
    bool? useSymbols,
    bool? avoidAmbiguous,
    bool? requireEveryClass,
    String? symbolSet,
  }) =>
      GeneratorOptions(
        length: length ?? this.length,
        useLowercase: useLowercase ?? this.useLowercase,
        useUppercase: useUppercase ?? this.useUppercase,
        useDigits: useDigits ?? this.useDigits,
        useSymbols: useSymbols ?? this.useSymbols,
        avoidAmbiguous: avoidAmbiguous ?? this.avoidAmbiguous,
        requireEveryClass: requireEveryClass ?? this.requireEveryClass,
        symbolSet: symbolSet ?? this.symbolSet,
      );

  /// The enabled classes, each already filtered for ambiguity.
  List<String> get activeClasses {
    String filter(String source) => avoidAmbiguous
        ? source.split('').where((c) => !ambiguous.contains(c)).join()
        : source;

    return [
      if (useLowercase) filter(lowercase),
      if (useUppercase) filter(uppercase),
      if (useDigits) filter(digits),
      if (useSymbols) filter(symbolSet),
    ].where((s) => s.isNotEmpty).toList(growable: false);
  }

  String get alphabet => activeClasses.join();

  bool get isValid =>
      alphabet.isNotEmpty && length >= minLength && length <= maxLength;

  /// Bits of entropy in a password generated with these settings.
  double get entropyBits =>
      alphabet.isEmpty ? 0 : length * (math.log(alphabet.length) / math.ln2);
}

/// Settings for a word-based passphrase.
class PassphraseOptions {
  const PassphraseOptions({
    this.wordCount = 6,
    this.separator = '-',
    this.capitalise = true,
    this.includeNumber = false,
    this.includeSymbol = false,
  });

  static const int minWords = 3;
  static const int maxWords = 12;

  final int wordCount;
  final String separator;
  final bool capitalise;
  final bool includeNumber;
  final bool includeSymbol;

  PassphraseOptions copyWith({
    int? wordCount,
    String? separator,
    bool? capitalise,
    bool? includeNumber,
    bool? includeSymbol,
  }) =>
      PassphraseOptions(
        wordCount: wordCount ?? this.wordCount,
        separator: separator ?? this.separator,
        capitalise: capitalise ?? this.capitalise,
        includeNumber: includeNumber ?? this.includeNumber,
        includeSymbol: includeSymbol ?? this.includeSymbol,
      );
}

/// The generated value together with an honest entropy figure.
@immutable
class GeneratedSecret {
  const GeneratedSecret({required this.value, required this.entropyBits});
  final String value;
  final double entropyBits;
}

/// Generates passwords, passphrases and PINs.
///
/// Every draw comes from [SecureRandom]. There is a test that fails the build
/// if `dart:math`'s default `Random()` appears anywhere under `lib/` — a seeded
/// PRNG here would produce output that looks fine and is enumerable.
class PasswordGenerator {
  PasswordGenerator({required List<String> wordlist}) : _wordlist = wordlist;

  /// Words used for passphrases, loaded from the bundled asset.
  final List<String> _wordlist;

  int get wordlistSize => _wordlist.length;

  /// Bits contributed by each word, computed from the real list length rather
  /// than assumed.
  double get bitsPerWord =>
      _wordlist.isEmpty ? 0 : math.log(_wordlist.length) / math.ln2;

  GeneratedSecret generatePassword(GeneratorOptions options) {
    if (!options.isValid) {
      throw ArgumentError('Enable at least one character class');
    }
    final alphabet = options.alphabet;
    final classes = options.activeClasses;

    // Rejection sampling: draw a uniform password, and if it misses a required
    // class, throw it away and draw again. This keeps every valid password
    // equally likely, which "insert one of each, then shuffle" does not.
    const maxAttempts = 2000;
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      final buffer = StringBuffer();
      for (var i = 0; i < options.length; i++) {
        buffer.write(alphabet[SecureRandom.intBelow(alphabet.length)]);
      }
      final candidate = buffer.toString();
      if (!options.requireEveryClass || _coversAll(candidate, classes)) {
        return GeneratedSecret(
          value: candidate,
          entropyBits: options.entropyBits,
        );
      }
    }

    // Only reachable when the length is barely above the class count, where
    // rejection can be unlucky. Fall back to a guaranteed-valid construction.
    return GeneratedSecret(
      value: _constructCovering(options, classes),
      entropyBits: options.entropyBits,
    );
  }

  GeneratedSecret generatePassphrase(PassphraseOptions options) {
    if (_wordlist.isEmpty) {
      throw StateError('The passphrase wordlist has not been loaded');
    }
    final count = options.wordCount
        .clamp(PassphraseOptions.minWords, PassphraseOptions.maxWords);

    final words = <String>[];
    for (var i = 0; i < count; i++) {
      var word = SecureRandom.pick(_wordlist);
      if (options.capitalise) {
        word = word[0].toUpperCase() + word.substring(1);
      }
      words.add(word);
    }

    var entropy = count * bitsPerWord;

    if (options.includeNumber) {
      // A digit glued to one randomly chosen word.
      final index = SecureRandom.intBelow(words.length);
      words[index] = '${words[index]}${SecureRandom.intBelow(10)}';
      entropy += math.log(10 * words.length) / math.ln2;
    }
    if (options.includeSymbol) {
      const symbols = r'!@#$%^&*';
      final index = SecureRandom.intBelow(words.length);
      words[index] =
          '${words[index]}${symbols[SecureRandom.intBelow(symbols.length)]}';
      entropy += math.log(symbols.length * words.length) / math.ln2;
    }

    return GeneratedSecret(
      value: words.join(options.separator),
      entropyBits: entropy,
    );
  }

  GeneratedSecret generatePin({int length = 6}) {
    final buffer = StringBuffer();
    for (var i = 0; i < length; i++) {
      buffer.write(SecureRandom.intBelow(10));
    }
    return GeneratedSecret(
      value: buffer.toString(),
      entropyBits: length * (math.log(10) / math.ln2),
    );
  }

  /// A username-shaped value, for sites where a throwaway handle is wanted.
  GeneratedSecret generateUsername() {
    if (_wordlist.length < 2) {
      throw StateError('The wordlist has not been loaded');
    }
    final first = SecureRandom.pick(_wordlist);
    final second = SecureRandom.pick(_wordlist);
    final number = SecureRandom.intBelow(1000);
    return GeneratedSecret(
      value: '$first.$second$number',
      entropyBits: 2 * bitsPerWord + (math.log(1000) / math.ln2),
    );
  }

  static bool _coversAll(String candidate, List<String> classes) {
    for (final characters in classes) {
      var found = false;
      for (var i = 0; i < candidate.length; i++) {
        if (characters.contains(candidate[i])) {
          found = true;
          break;
        }
      }
      if (!found) return false;
    }
    return true;
  }

  static String _constructCovering(
      GeneratorOptions options, List<String> classes) {
    final characters = <String>[];
    for (final source in classes) {
      characters.add(source[SecureRandom.intBelow(source.length)]);
    }
    final alphabet = options.alphabet;
    while (characters.length < options.length) {
      characters.add(alphabet[SecureRandom.intBelow(alphabet.length)]);
    }
    SecureRandom.shuffle(characters);
    return characters.join();
  }

  /// Parses the bundled wordlist asset, skipping comments and blank lines.
  static List<String> parseWordlist(String contents) {
    final words = <String>[];
    for (final line in contents.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
      words.addAll(trimmed.split(RegExp(r'\s+')).where((w) => w.isNotEmpty));
    }
    return words;
  }
}
