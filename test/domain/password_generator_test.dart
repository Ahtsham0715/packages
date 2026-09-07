import 'package:flutter_test/flutter_test.dart';
import 'package:sablekey/domain/services/password_generator.dart';

void main() {
  // A small deterministic list keeps the assertions readable. The real list is
  // exercised by wordlist_asset_test.dart.
  final generator = PasswordGenerator(
    wordlist: const ['alpha', 'bravo', 'charlie', 'delta'],
  );

  group('password generation', () {
    test('respects the requested length', () {
      for (final length in [8, 20, 64, 128]) {
        final result = generator.generatePassword(
          GeneratorOptions(length: length),
        );
        expect(result.value.length, length);
      }
    });

    test('draws only from the enabled classes', () {
      final result = generator.generatePassword(const GeneratorOptions(
        length: 40,
        useLowercase: true,
        useUppercase: false,
        useDigits: false,
        useSymbols: false,
        avoidAmbiguous: false,
      ));
      expect(result.value, matches(RegExp(r'^[a-z]+$')));
    });

    test('includes every enabled class when asked', () {
      // Run repeatedly: a bug here shows up as an occasional miss, not a
      // consistent one.
      for (var attempt = 0; attempt < 200; attempt++) {
        final result = generator.generatePassword(const GeneratorOptions(
          length: 12,
          requireEveryClass: true,
        ));
        expect(result.value, matches(RegExp('[a-z]')), reason: 'no lowercase');
        expect(result.value, matches(RegExp('[A-Z]')), reason: 'no uppercase');
        expect(result.value, matches(RegExp('[0-9]')), reason: 'no digit');
        expect(
          result.value,
          matches(RegExp(r'[!@#\$%^&*()\-_=+\[\]{};:,.?/]')),
          reason: 'no symbol',
        );
      }
    });

    test('excludes look-alike characters when asked', () {
      for (var attempt = 0; attempt < 100; attempt++) {
        final result = generator.generatePassword(
          const GeneratorOptions(length: 64, avoidAmbiguous: true),
        );
        for (final character in GeneratorOptions.ambiguous.split('')) {
          expect(result.value.contains(character), isFalse,
              reason: 'contained ambiguous "$character"');
        }
      }
    });

    test('produces a different password each call', () {
      final seen = <String>{};
      for (var attempt = 0; attempt < 100; attempt++) {
        seen.add(generator.generatePassword(const GeneratorOptions()).value);
      }
      // 20 characters from a ~70-character alphabet: a repeat here means the
      // randomness is broken, not that we got unlucky.
      expect(seen.length, 100);
    });

    test('uses the whole alphabet over many draws', () {
      const options = GeneratorOptions(
        length: 64,
        useUppercase: false,
        useDigits: false,
        useSymbols: false,
        avoidAmbiguous: false,
        requireEveryClass: false,
      );

      final seen = <String>{};
      for (var attempt = 0; attempt < 200; attempt++) {
        seen.addAll(generator.generatePassword(options).value.split(''));
      }
      // Every letter a-z should appear across 12 800 characters. A generator
      // stuck on a subrange would fail here.
      expect(seen.length, 26);
    });

    test('reports entropy as length times log2(alphabet)', () {
      final result = generator.generatePassword(const GeneratorOptions(
        length: 10,
        useLowercase: true,
        useUppercase: false,
        useDigits: false,
        useSymbols: false,
        avoidAmbiguous: false,
      ));
      // log2(26) * 10 = 47.0
      expect(result.entropyBits, closeTo(47.0, 0.1));
    });

    test('refuses to generate with no classes enabled', () {
      expect(
        () => generator.generatePassword(const GeneratorOptions(
          useLowercase: false,
          useUppercase: false,
          useDigits: false,
          useSymbols: false,
        )),
        throwsArgumentError,
      );
    });

    test('still satisfies every class at the awkward short lengths', () {
      // Length 4 with four required classes is the case where rejection
      // sampling is most likely to give up and fall back.
      for (var attempt = 0; attempt < 100; attempt++) {
        final result = generator.generatePassword(
          const GeneratorOptions(length: 4, avoidAmbiguous: false),
        );
        expect(result.value.length, 4);
        expect(result.value, matches(RegExp('[a-z]')));
        expect(result.value, matches(RegExp('[A-Z]')));
        expect(result.value, matches(RegExp('[0-9]')));
      }
    });
  });

  group('passphrase generation', () {
    test('produces the requested number of words', () {
      final result = generator.generatePassphrase(
        const PassphraseOptions(wordCount: 5, separator: '-'),
      );
      expect(result.value.split('-').length, 5);
    });

    test('uses only words from the list', () {
      final result = generator.generatePassphrase(
        const PassphraseOptions(wordCount: 8, capitalise: false),
      );
      for (final word in result.value.split('-')) {
        expect(['alpha', 'bravo', 'charlie', 'delta'], contains(word));
      }
    });

    test('capitalises when asked', () {
      final result = generator.generatePassphrase(
        const PassphraseOptions(wordCount: 4),
      );
      for (final word in result.value.split('-')) {
        expect(word[0], word[0].toUpperCase());
      }
    });

    test('computes entropy from the real list length', () {
      // log2(4) = 2 bits per word, six words = 12 bits.
      expect(generator.bitsPerWord, closeTo(2.0, 0.001));
      final result = generator.generatePassphrase(
        const PassphraseOptions(wordCount: 6),
      );
      expect(result.entropyBits, closeTo(12.0, 0.001));
    });

    test('adding a digit increases the reported entropy', () {
      final plain = generator.generatePassphrase(
        const PassphraseOptions(wordCount: 6),
      );
      final withDigit = generator.generatePassphrase(
        const PassphraseOptions(wordCount: 6, includeNumber: true),
      );
      expect(withDigit.entropyBits, greaterThan(plain.entropyBits));
    });

    test('honours the separator, including an empty one', () {
      final dotted = generator.generatePassphrase(
        const PassphraseOptions(wordCount: 3, separator: '.'),
      );
      expect(dotted.value.split('.').length, 3);

      final joined = generator.generatePassphrase(
        const PassphraseOptions(wordCount: 3, separator: ''),
      );
      expect(joined.value.contains('-'), isFalse);
    });

    test('clamps an out-of-range word count', () {
      final result = generator.generatePassphrase(
        const PassphraseOptions(wordCount: 99),
      );
      expect(result.value.split('-').length, PassphraseOptions.maxWords);
    });

    test('fails clearly when no wordlist was loaded', () {
      final empty = PasswordGenerator(wordlist: const []);
      expect(
        () => empty.generatePassphrase(const PassphraseOptions()),
        throwsStateError,
      );
    });
  });

  group('PIN generation', () {
    test('produces digits only, at the requested length', () {
      final result = generator.generatePin(length: 8);
      expect(result.value, matches(RegExp(r'^\d{8}$')));
      expect(result.entropyBits, closeTo(26.6, 0.1));
    });

    test('varies between calls', () {
      final seen = <String>{};
      for (var attempt = 0; attempt < 200; attempt++) {
        seen.add(generator.generatePin(length: 8).value);
      }
      expect(seen.length, greaterThan(150));
    });
  });

  group('wordlist parsing', () {
    test('skips comments and blank lines', () {
      const source = '''
# a comment
alpha bravo

charlie
  delta   echo
''';
      expect(
        PasswordGenerator.parseWordlist(source),
        ['alpha', 'bravo', 'charlie', 'delta', 'echo'],
      );
    });

    test('returns nothing for an all-comment file', () {
      expect(PasswordGenerator.parseWordlist('# only\n# comments\n'), isEmpty);
    });
  });
}
