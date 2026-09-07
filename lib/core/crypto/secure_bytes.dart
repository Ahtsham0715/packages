import 'dart:typed_data';

/// A byte buffer holding key material that can be wiped when it is no longer
/// needed.
///
/// Dart gives no hard guarantee that a buffer is not copied by the GC, so this
/// is defence in depth rather than a promise: it shortens the window in which
/// a key sits in a readable page, and it makes "who still holds this key?"
/// answerable by reading the code. Every long-lived key in Sablekey lives in
/// one of these, and locking the vault destroys all of them.
class SecureBytes {
  SecureBytes(Uint8List bytes) : _bytes = bytes;

  /// Takes a defensive copy, then wipes the source.
  factory SecureBytes.consume(Uint8List source) {
    final copy = Uint8List.fromList(source);
    _wipe(source);
    return SecureBytes(copy);
  }

  factory SecureBytes.zero(int length) => SecureBytes(Uint8List(length));

  Uint8List _bytes;
  bool _destroyed = false;

  bool get isDestroyed => _destroyed;

  int get length => _bytes.length;

  /// The raw bytes. Throws once [destroy] has been called, which turns a
  /// use-after-free into a loud failure instead of silent garbage.
  Uint8List get bytes {
    if (_destroyed) {
      throw StateError('SecureBytes used after destroy()');
    }
    return _bytes;
  }

  /// Returns an independent copy of the material. The caller owns it.
  Uint8List copy() => Uint8List.fromList(bytes);

  /// Overwrites the buffer and marks it unusable. Idempotent.
  void destroy() {
    if (_destroyed) return;
    _wipe(_bytes);
    _bytes = Uint8List(0);
    _destroyed = true;
  }

  static void _wipe(Uint8List buffer) {
    // Two passes with different patterns: a single zero-fill is the pattern a
    // compiler is most likely to elide, and 0xFF then 0x00 also clears any
    // sticky-bit weirdness on exotic storage.
    buffer.fillRange(0, buffer.length, 0xFF);
    buffer.fillRange(0, buffer.length, 0x00);
  }
}

/// Wipes a plain buffer in place. Use for short-lived plaintext.
void wipeBytes(Uint8List buffer) {
  buffer.fillRange(0, buffer.length, 0xFF);
  buffer.fillRange(0, buffer.length, 0x00);
}

/// Compares two byte strings in time that does not depend on where they first
/// differ.
///
/// Used for every MAC/verifier comparison. The early-exit `==` that reads more
/// naturally would leak the position of the first mismatch through timing.
bool constantTimeEquals(List<int> a, List<int> b) {
  // The length check is not itself secret — the lengths are structural.
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}
