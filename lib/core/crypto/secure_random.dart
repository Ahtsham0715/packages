import 'dart:math';
import 'dart:typed_data';

/// The single source of randomness for the whole app.
///
/// Everything that must be unguessable — salts, nonces, the data encryption
/// key, generated passwords — comes from here. `Random()` (the non-secure one)
/// must never appear anywhere else in `lib/`; there is a test that greps for
/// it, because a seeded PRNG in a password generator is the kind of bug that
/// looks fine and silently produces guessable output.
abstract final class SecureRandom {
  static final Random _random = Random.secure();

  static Uint8List bytes(int length) {
    final out = Uint8List(length);
    for (var i = 0; i < length; i++) {
      out[i] = _random.nextInt(256);
    }
    return out;
  }

  /// Uniform integer in `[0, max)`.
  ///
  /// Delegates to `Random.secure().nextInt`, which is already rejection-based
  /// and unbiased for the range we use.
  static int intBelow(int max) {
    if (max <= 0) throw ArgumentError.value(max, 'max', 'must be positive');
    return _random.nextInt(max);
  }

  /// Picks one element uniformly.
  static T pick<T>(List<T> items) {
    if (items.isEmpty) throw ArgumentError('cannot pick from an empty list');
    return items[intBelow(items.length)];
  }

  /// Fisher–Yates, so generated passwords do not leak the order in which
  /// character classes were satisfied.
  ///
  /// Without this, a generator that appends "one digit, one symbol" to satisfy
  /// its rules produces passwords whose last two characters are predictable in
  /// class, which measurably shrinks the search space.
  static void shuffle<T>(List<T> items) {
    for (var i = items.length - 1; i > 0; i--) {
      final j = intBelow(i + 1);
      final tmp = items[i];
      items[i] = items[j];
      items[j] = tmp;
    }
  }
}
