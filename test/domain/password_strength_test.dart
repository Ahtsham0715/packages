import 'package:flutter_test/flutter_test.dart';
import 'package:sablekey/domain/services/password_strength.dart';

void main() {
  // A deliberately tiny dictionary so the expected figures below are
  // arithmetic anyone can check, rather than a property of the shipped lists.
  final estimator = PasswordStrengthEstimator(
    commonPasswords: const {'password', 'letmein', '123456', 'qwerty'},
    dictionaryWords: const {
      'correct', 'horse', 'battery', 'staple', 'dragon', 'summer', 'monkey',
    },
  );

  group('common passwords', () {
    test('an exact match is flagged and scores zero', () {
      final result = estimator.evaluate('password');
      expect(result.isCommon, isTrue);
      expect(result.score, 0);
      expect(result.warnings, isNotEmpty);
    });

    test('matching is case insensitive', () {
      expect(estimator.evaluate('Password').isCommon, isTrue);
      expect(estimator.evaluate('PASSWORD').isCommon, isTrue);
    });

    test('leet substitutions do not hide a common password', () {
      // The single most common "clever" transformation, and attackers apply it
      // by default.
      expect(estimator.evaluate('P@ssw0rd').isCommon, isTrue);
      expect(estimator.evaluate('l3tm31n').isCommon, isTrue);
    });

    test('an uncommon password is not flagged', () {
      expect(estimator.evaluate(r'x7Kq!vZ2mT#pL9wXb$Rn').isCommon, isFalse);
    });
  });

  group('structure is charged honestly', () {
    test('a run of repeated characters is nearly worthless', () {
      final result = estimator.evaluate('aaaaaaa');
      expect(result.entropyBits, closeTo(7.5, 0.5));
      expect(result.score, 0);
    });

    test('a keyboard run is nearly worthless', () {
      final result = estimator.evaluate('qwertyuiop');
      expect(result.entropyBits, closeTo(6.0, 0.5));
      expect(result.score, 0);
    });

    test('an alphabet sequence is nearly worthless', () {
      final result = estimator.evaluate('abcdefgh');
      expect(result.entropyBits, closeTo(5.0, 0.5));
      expect(result.score, 0);
    });

    test('length alone does not rescue a structured password', () {
      // Ten characters, but only one real choice behind them. A rule-based
      // checker would call this "strong: 10 chars, mixed case + digits".
      final structured = estimator.evaluate('qwertyuiop');
      final random = estimator.evaluate('k4Rm!p2Xz9');
      expect(structured.entropyBits, lessThan(random.entropyBits / 5));
    });

    test('dictionary words are charged per word, not per character', () {
      // Four known words: about 11 bits each, not 25 characters' worth.
      final result = estimator.evaluate('correcthorsebatterystaple');
      expect(result.entropyBits, closeTo(44.0, 1.0));
      expect(result.score, 2);
      expect(
        result.warnings.any((w) => w.toLowerCase().contains('dictionary')),
        isTrue,
      );
    });

    test('separators between words add their own entropy', () {
      final joined = estimator.evaluate('correcthorsebatterystaple');
      final separated = estimator.evaluate('correct-horse-battery-staple');
      expect(separated.entropyBits, greaterThan(joined.entropyBits));
    });

    test('a leading capital is worth almost nothing', () {
      final lower = estimator.evaluate('dragon');
      final capitalised = estimator.evaluate('Dragon');
      // Capitalising the first letter is what almost everyone does, so an
      // attacker tries it first. One bit, not five.
      expect(capitalised.entropyBits - lower.entropyBits, closeTo(1.0, 0.5));
    });

    test('interior capitals are worth more than a leading one', () {
      final leading = estimator.evaluate('Dragon');
      final interior = estimator.evaluate('drAgOn');
      expect(interior.entropyBits, greaterThan(leading.entropyBits));
    });
  });

  group('random passwords', () {
    test('score at the top of the scale', () {
      final result = estimator.evaluate(r'x7Kq!vZ2mT#pL9wXb$Rn');
      expect(result.score, 4);
      expect(result.entropyBits, greaterThan(80));
    });

    test('entropy grows with length', () {
      final short = estimator.evaluate('k4Rm!p2X');
      final long = estimator.evaluate(r'k4Rm!p2Xz9Bv#nQ7wLt$');
      expect(long.entropyBits, greaterThan(short.entropyBits));
    });
  });

  group('warnings', () {
    test('flags a short password', () {
      final result = estimator.evaluate('abc12');
      expect(result.score, 0);
      expect(
        result.warnings.any((w) => w.toLowerCase().contains('short')),
        isTrue,
      );
    });

    test('flags a digits-only password', () {
      final result = estimator.evaluate('928374651');
      expect(
        result.warnings.any((w) => w.toLowerCase().contains('digits only')),
        isTrue,
      );
    });

    test('flags an embedded year', () {
      final result = estimator.evaluate('Summer2024');
      expect(
        result.warnings.any((w) => w.toLowerCase().contains('year')),
        isTrue,
      );
    });

    test('suggests a passphrase for a mediocre password', () {
      final result = estimator.evaluate('k4Rm!p2X');
      expect(result.suggestions, isNotEmpty);
    });

    test('a strong password gets no warnings', () {
      final result = estimator.evaluate(r'x7Kq!vZ2mT#pL9wXb$Rn');
      expect(result.warnings, isEmpty);
    });
  });

  group('edges', () {
    test('an empty password is zero, not an error', () {
      final result = estimator.evaluate('');
      expect(result.entropyBits, 0);
      expect(result.score, 0);
      expect(result.isCommon, isFalse);
    });

    test('a single character is handled', () {
      expect(estimator.evaluate('a').score, 0);
    });

    test('non-ASCII characters are counted generously but not absurdly', () {
      final result = estimator.evaluate('日本語のパスワード');
      expect(result.entropyBits, greaterThan(40));
    });

    test('a structure-only estimator still catches patterns', () {
      final bare = PasswordStrengthEstimator.structureOnly();
      expect(bare.evaluate('qwertyuiop').score, 0);
      expect(bare.evaluate('aaaaaaaa').score, 0);
      // With no list loaded it cannot know this one is common.
      expect(bare.evaluate('password').isCommon, isFalse);
    });
  });

  group('labels and crack times', () {
    test('labels track the score', () {
      expect(estimator.evaluate('password').label, 'Very weak');
      expect(estimator.evaluate(r'x7Kq!vZ2mT#pL9wXb$Rn').label, 'Excellent');
    });

    test('a weak password cracks instantly, a strong one does not', () {
      expect(estimator.evaluate('abcdefgh').offlineCrackTime, 'instantly');
      expect(
        estimator.evaluate(r'x7Kq!vZ2mT#pL9wXb$Rn').offlineCrackTime,
        contains('years'),
      );
    });
  });
}
