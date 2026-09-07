import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:sablekey/domain/services/password_generator.dart';
import 'package:sablekey/domain/services/password_strength.dart';

/// Checks on the repository itself.
///
/// These are the invariants that a code review would catch on a good day and
/// miss on a bad one, so they are asserted mechanically instead.
void main() {
  List<File> dartSources(String directory) => Directory(directory)
      .listSync(recursive: true)
      .whereType<File>()
      .where((file) => file.path.endsWith('.dart'))
      .toList();

  group('randomness', () {
    test('no insecure Random() anywhere under lib/', () {
      // A seeded or default PRNG in a password generator produces output that
      // looks fine and is enumerable. Everything must go through SecureRandom,
      // which wraps Random.secure().
      final offenders = <String>[];

      for (final file in dartSources('lib')) {
        // The one legitimate definition site.
        if (file.path.endsWith('core/crypto/secure_random.dart')) continue;

        final source = file.readAsStringSync();
        for (final line in source.split('\n')) {
          final trimmed = line.trim();
          if (trimmed.startsWith('//') || trimmed.startsWith('///')) continue;
          // `Random()` or `Random(seed)`, but not `Random.secure()`.
          if (RegExp(r'\bRandom\s*\((?!\s*\))|(?<!\.)\bRandom\(\)')
              .hasMatch(line)) {
            offenders.add('${file.path}: $trimmed');
          }
        }
      }

      expect(offenders, isEmpty,
          reason: 'use SecureRandom instead:\n${offenders.join('\n')}');
    });
  });

  group('offline guarantee', () {
    test('the release manifest removes the INTERNET permission', () {
      final manifest =
          File('android/app/src/main/AndroidManifest.xml').readAsStringSync();

      // Merely omitting the permission is not enough: a plugin deep in the
      // dependency tree can contribute it to the merged manifest.
      expect(
        manifest,
        contains('android.permission.INTERNET'),
        reason: 'the removal directive itself must be present',
      );
      expect(manifest, contains('tools:node="remove"'));
      expect(manifest, contains('android:allowBackup="false"'));
    });

    test('no Dart source imports an HTTP client', () {
      final offenders = <String>[];
      // dart:io itself is fine — it is how Platform checks and local file
      // access work. The network types reached through it are not.
      const forbidden = [
        'package:http/',
        'package:dio/',
        'HttpClient',
        'WebSocket',
        'RawDatagramSocket',
        'Socket.connect',
      ];

      for (final file in dartSources('lib')) {
        final source = file.readAsStringSync();
        for (final needle in forbidden) {
          if (source.contains(needle)) offenders.add('${file.path}: $needle');
        }
      }

      expect(offenders, isEmpty,
          reason: 'Sablekey must make no network calls:\n'
              '${offenders.join('\n')}');
    });

    test('the iOS Info.plist allows no ATS exceptions', () {
      final plist = File('ios/Runner/Info.plist').readAsStringSync();
      expect(plist, contains('NSAllowsArbitraryLoads'));
      final index = plist.indexOf('NSAllowsArbitraryLoads');
      expect(plist.substring(index, index + 60), contains('<false/>'));
    });
  });

  group('bundled wordlists', () {
    late List<String> words;
    late List<String> common;

    setUpAll(() {
      words = PasswordGenerator.parseWordlist(
        File('assets/wordlist/passphrase_words.txt').readAsStringSync(),
      );
      common = PasswordGenerator.parseWordlist(
        File('assets/wordlist/common_passwords.txt').readAsStringSync(),
      );
    });

    test('the passphrase list is large enough to be worth using', () {
      // Under ~2000 words a six-word passphrase drops below 66 bits.
      expect(words.length, greaterThan(2000));
    });

    test('every word is unique', () {
      // A duplicate silently overstates the entropy the UI reports.
      expect(words.toSet().length, words.length);
    });

    test('words are lowercase letters only, and a sane length', () {
      final malformed =
          words.where((w) => !RegExp(r'^[a-z]{3,9}$').hasMatch(w)).toList();
      expect(malformed, isEmpty);
    });

    test('a six-word passphrase clears 60 bits', () {
      final bitsPerWord = math.log(words.length) / math.ln2;
      expect(bitsPerWord * 6, greaterThan(60));
    });

    test('the common-password list is populated and lowercase', () {
      expect(common.length, greaterThan(300));
      expect(common.every((p) => p == p.toLowerCase()), isTrue);
      expect(common, contains('password'));
      expect(common, contains('123456'));
    });

    test('a generated passphrase is never rated weak by our own estimator', () {
      // The lists overlap by design — "dragon" is both an ordinary word and a
      // top-guessed password — and that is harmless, because a six-word
      // passphrase containing it is still strong. What would be a real defect
      // is the generator producing something the app then flags, so assert
      // that directly rather than policing the overlap.
      final generator = PasswordGenerator(wordlist: words);
      final estimator = PasswordStrengthEstimator(
        commonPasswords: common.toSet(),
        dictionaryWords: words.toSet(),
      );

      for (var attempt = 0; attempt < 100; attempt++) {
        final phrase =
            generator.generatePassphrase(const PassphraseOptions(wordCount: 6));
        final strength = estimator.evaluate(phrase.value);

        expect(strength.isCommon, isFalse, reason: phrase.value);
        expect(strength.score, greaterThanOrEqualTo(3), reason: phrase.value);
      }
    });

    test('a generated password is never rated weak either', () {
      final generator = PasswordGenerator(wordlist: words);
      final estimator = PasswordStrengthEstimator(
        commonPasswords: common.toSet(),
        dictionaryWords: words.toSet(),
      );

      for (var attempt = 0; attempt < 100; attempt++) {
        final password =
            generator.generatePassword(const GeneratorOptions(length: 20));
        final strength = estimator.evaluate(password.value);
        expect(strength.score, 4, reason: password.value);
      }
    });
  });

  group('assets are declared', () {
    test('every bundled asset directory is listed in pubspec.yaml', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      expect(pubspec, contains('assets/brand/'));
      expect(pubspec, contains('assets/wordlist/'));
    });

    test('the brand images referenced by the UI exist', () {
      expect(File('assets/brand/sablekey_mark_512.png').existsSync(), isTrue);
      expect(File('assets/brand/sablekey_icon_1024.png').existsSync(), isTrue);
    });
  });
}
