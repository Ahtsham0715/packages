import 'dart:math' as math;

import 'package:flutter/foundation.dart';

/// The verdict on a single password.
@immutable
class PasswordStrength {
  const PasswordStrength({
    required this.entropyBits,
    required this.score,
    required this.warnings,
    required this.suggestions,
    required this.isCommon,
  });

  static const PasswordStrength empty = PasswordStrength(
    entropyBits: 0,
    score: 0,
    warnings: <String>[],
    suggestions: <String>[],
    isCommon: false,
  );

  /// Estimated bits of entropy against an attacker who knows how the password
  /// was built.
  final double entropyBits;

  /// 0 = terrible … 4 = strong. Drives the colour of the meter.
  final int score;

  final List<String> warnings;
  final List<String> suggestions;

  /// Appeared in the bundled list of the most-guessed passwords.
  final bool isCommon;

  String get label => switch (score) {
        0 => 'Very weak',
        1 => 'Weak',
        2 => 'Fair',
        3 => 'Strong',
        _ => 'Excellent',
      };

  /// Rough time for an offline attacker with serious hardware.
  ///
  /// Assumes 10^11 guesses per second — a well-funded attacker against a site
  /// that hashed the password badly. It is deliberately pessimistic: a number
  /// that says "3 weeks" when the truth is "3 hours" is worse than useless.
  String get offlineCrackTime {
    final guesses = math.pow(2, entropyBits) / 2;
    final seconds = guesses / 1e11;
    return _humanizeSeconds(seconds.toDouble());
  }

  static String _humanizeSeconds(double seconds) {
    if (seconds < 1) return 'instantly';
    if (seconds < 60) return '${seconds.round()} seconds';
    final minutes = seconds / 60;
    if (minutes < 60) return '${minutes.round()} minutes';
    final hours = minutes / 60;
    if (hours < 24) return '${hours.round()} hours';
    final days = hours / 24;
    if (days < 365) return '${days.round()} days';
    final years = days / 365;
    if (years < 1000) return '${years.round()} years';
    if (years < 1e6) return '${(years / 1000).round()} thousand years';
    if (years < 1e9) return '${(years / 1e6).round()} million years';
    if (years < 1e12) return '${(years / 1e9).round()} billion years';
    return 'longer than the age of the universe';
  }
}

/// A local password strength estimator in the spirit of zxcvbn.
///
/// Scoring by character-class rules ("must contain a symbol") is the thing that
/// produces `Password1!` and calls it strong. This instead looks for the
/// structures people actually use — dictionary words, keyboard runs, dates,
/// repeats, leet substitutions — and charges only the entropy each piece really
/// carries.
///
/// It runs entirely offline against the bundled lists. It is an estimate, and
/// the UI presents it as one.
class PasswordStrengthEstimator {
  PasswordStrengthEstimator({
    required Set<String> commonPasswords,
    required Set<String> dictionaryWords,
  })  : _commonPasswords = commonPasswords,
        _dictionaryWords = dictionaryWords;

  /// An estimator with no word lists loaded — still catches structure, just not
  /// dictionary words. Used before assets finish loading.
  factory PasswordStrengthEstimator.structureOnly() =>
      PasswordStrengthEstimator(commonPasswords: const {}, dictionaryWords: const {});

  final Set<String> _commonPasswords;
  final Set<String> _dictionaryWords;

  static const Map<String, String> _leetMap = {
    '4': 'a', '@': 'a', '3': 'e', '0': 'o', '1': 'i', '!': 'i',
    '\$': 's', '5': 's', '7': 't', '+': 't', '8': 'b', '9': 'g',
  };

  /// Rows as they sit under the fingers, for detecting `qwerty` and `1qaz2wsx`.
  static const List<String> _keyboardRows = [
    '1234567890',
    'qwertyuiop',
    'asdfghjkl',
    'zxcvbnm',
  ];

  PasswordStrength evaluate(String password) {
    if (password.isEmpty) return PasswordStrength.empty;

    final warnings = <String>[];
    final suggestions = <String>[];
    final lower = password.toLowerCase();
    final deleet = _deleet(lower);

    // A direct hit on the common list ends the analysis: no amount of length
    // rescues a password an attacker tries in the first thousand guesses.
    final isCommon =
        _commonPasswords.contains(lower) || _commonPasswords.contains(deleet);
    if (isCommon) {
      warnings.add('This is one of the most commonly used passwords in the '
          'world. Attackers try it within the first few seconds.');
      suggestions.add('Replace it now — anywhere you have used it.');
      return PasswordStrength(
        entropyBits: math.min(12, password.length * 1.0),
        score: 0,
        warnings: warnings,
        suggestions: suggestions,
        isCommon: true,
      );
    }

    final entropy = _segmentedEntropy(password, warnings);

    if (password.length < 8) {
      warnings.add('Short passwords fall to brute force regardless of how '
          'unusual the characters are.');
      suggestions.add('Aim for at least 14 characters.');
    }
    if (_hasLongRepeat(lower)) {
      warnings.add('Repeated characters add much less strength than they look '
          'like they do.');
    }
    if (RegExp(r'^\d+$').hasMatch(password)) {
      warnings.add('Digits only — the search space is tiny.');
      suggestions.add('Mix in letters, or use a passphrase instead.');
    }
    if (RegExp(r'(19|20)\d{2}').hasMatch(password)) {
      warnings.add('Contains what looks like a year. Attackers try every year '
          'from 1900 to next year.');
    }
    if (entropy < 60 && suggestions.isEmpty) {
      suggestions.add('A generated passphrase of six words or more would be '
          'far stronger and easier to remember.');
    }

    return PasswordStrength(
      entropyBits: entropy,
      score: _scoreFor(entropy),
      warnings: warnings,
      suggestions: suggestions,
      isCommon: false,
    );
  }

  /// Walks the password left to right, taking the longest recognisable pattern
  /// at each position and charging it the entropy that pattern really costs an
  /// attacker. Unrecognised runs are charged at the full character-set rate.
  double _segmentedEntropy(String password, List<String> warnings) {
    final lower = password.toLowerCase();
    var total = 0.0;
    var index = 0;
    var sawDictionary = false;
    var sawKeyboard = false;
    var sawSequence = false;

    while (index < password.length) {
      final match = _longestPatternAt(lower, index);
      if (match != null) {
        total += match.entropy;
        // Mixed case and leet inside a matched word add a little back, since
        // the attacker must also guess the mangling.
        total += _mangleBonus(password.substring(index, index + match.length));
        switch (match.kind) {
          case _PatternKind.dictionary:
            sawDictionary = true;
          case _PatternKind.keyboard:
            sawKeyboard = true;
          case _PatternKind.sequence:
          case _PatternKind.repeat:
            sawSequence = true;
        }
        index += match.length;
      } else {
        total += _charsetBits(password[index]);
        index += 1;
      }
    }

    if (sawDictionary) {
      warnings.add('Built from dictionary words. Attackers start with a word '
          'list, not with random characters.');
    }
    if (sawKeyboard) {
      warnings.add('Contains a run of adjacent keyboard keys.');
    }
    if (sawSequence) {
      warnings.add('Contains a predictable sequence or repetition.');
    }

    return total;
  }

  _PatternMatch? _longestPatternAt(String lower, int start) {
    _PatternMatch? best;

    void consider(_PatternMatch candidate) {
      if (best == null || candidate.length > best!.length) best = candidate;
    }

    // Dictionary words, including a de-leeted reading of the same span.
    final maxWord = math.min(lower.length - start, 16);
    for (var length = maxWord; length >= 3; length--) {
      final span = lower.substring(start, start + length);
      if (_dictionaryWords.contains(span) ||
          _dictionaryWords.contains(_deleet(span))) {
        // A word costs the attacker log2(list size) at most, and far less for
        // common words. 11 bits matches a ~2000-word practical attack list.
        consider(_PatternMatch(length, 11.0, _PatternKind.dictionary));
        break;
      }
    }

    // Runs of adjacent keys, forwards or backwards.
    final keyboard = _keyboardRunLength(lower, start);
    if (keyboard >= 3) {
      consider(_PatternMatch(keyboard, 6.0, _PatternKind.keyboard));
    }

    // Alphabetic or numeric sequences: abcd, 5678, wvut.
    final sequence = _sequenceRunLength(lower, start);
    if (sequence >= 3) {
      consider(_PatternMatch(sequence, 5.0, _PatternKind.sequence));
    }

    // The same character repeated.
    final repeat = _repeatRunLength(lower, start);
    if (repeat >= 3) {
      // Charge for the character plus the (cheap) choice of run length.
      consider(_PatternMatch(
          repeat, _charsetBits(lower[start]) + math.log(repeat) / math.ln2,
          _PatternKind.repeat));
    }

    return best;
  }

  /// Extra bits for capitalisation and leet inside an otherwise known word.
  double _mangleBonus(String segment) {
    var bonus = 0.0;
    final hasUpper = segment.contains(RegExp('[A-Z]'));
    final hasLower = segment.contains(RegExp('[a-z]'));
    if (hasUpper && hasLower) {
      // Capitalised-first-letter is the overwhelmingly common case and is
      // barely worth anything; interior capitals are worth more.
      final leadingCapOnly =
          RegExp(r'^[A-Z][a-z]*$').hasMatch(segment);
      bonus += leadingCapOnly ? 1.0 : math.min(segment.length.toDouble(), 6.0);
    }
    final leetCount =
        segment.split('').where((c) => _leetMap.containsKey(c)).length;
    if (leetCount > 0) bonus += math.min(leetCount * 1.0, 3.0);
    return bonus;
  }

  int _keyboardRunLength(String lower, int start) {
    for (final row in _keyboardRows) {
      for (final direction in const [1, -1]) {
        var length = 0;
        var position = row.indexOf(lower[start]);
        if (position < 0) continue;
        var cursor = start;
        while (cursor < lower.length &&
            position >= 0 &&
            position < row.length &&
            row[position] == lower[cursor]) {
          length++;
          cursor++;
          position += direction;
        }
        if (length >= 3) return length;
      }
    }
    return 0;
  }

  int _sequenceRunLength(String lower, int start) {
    if (start + 2 >= lower.length) return 0;
    final step = lower.codeUnitAt(start + 1) - lower.codeUnitAt(start);
    if (step != 1 && step != -1) return 0;
    var length = 1;
    while (start + length < lower.length &&
        lower.codeUnitAt(start + length) - lower.codeUnitAt(start + length - 1) ==
            step) {
      length++;
    }
    return length >= 3 ? length : 0;
  }

  int _repeatRunLength(String lower, int start) {
    var length = 1;
    while (start + length < lower.length && lower[start + length] == lower[start]) {
      length++;
    }
    return length >= 3 ? length : 0;
  }

  bool _hasLongRepeat(String lower) {
    for (var i = 0; i < lower.length; i++) {
      if (_repeatRunLength(lower, i) >= 3) return true;
    }
    return false;
  }

  /// Bits contributed by one unrecognised character, based on the class it
  /// belongs to.
  static double _charsetBits(String character) {
    final code = character.codeUnitAt(0);
    if (code >= 0x30 && code <= 0x39) return 3.32; // log2(10)
    if (code >= 0x61 && code <= 0x7A) return 4.70; // log2(26)
    if (code >= 0x41 && code <= 0x5A) return 4.70;
    if (code < 0x80) return 5.00; // ~32 printable symbols
    return 7.00; // non-ASCII: rare, and attackers rarely enumerate it
  }

  static String _deleet(String input) {
    final buffer = StringBuffer();
    for (final character in input.split('')) {
      buffer.write(_leetMap[character] ?? character);
    }
    return buffer.toString();
  }

  static int _scoreFor(double entropy) {
    if (entropy < 28) return 0;
    if (entropy < 40) return 1;
    if (entropy < 60) return 2;
    if (entropy < 80) return 3;
    return 4;
  }
}

enum _PatternKind { dictionary, keyboard, sequence, repeat }

@immutable
class _PatternMatch {
  const _PatternMatch(this.length, this.entropy, this.kind);
  final int length;
  final double entropy;
  final _PatternKind kind;
}
