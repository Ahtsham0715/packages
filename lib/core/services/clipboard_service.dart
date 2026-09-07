import 'dart:async';

import '../platform/secure_screen.dart';

/// Copies secrets to the clipboard and takes them back out again.
///
/// The clipboard is the weakest part of any password manager: on Android every
/// app used to be able to read it, on both platforms it survives the app being
/// locked, and desktop sync will happily carry a password to another machine.
/// So every copy here is marked sensitive at the OS level and scheduled for
/// deletion, and the pending wipe is re-armed rather than stacked when the user
/// copies twice.
class ClipboardService {
  ClipboardService({this.clearAfter = const Duration(seconds: 30)});

  /// How long a copied secret may live. [Duration.zero] disables clearing.
  Duration clearAfter;

  Timer? _pendingClear;
  String? _lastCopied;

  /// Seconds left before the clipboard is wiped, or null when nothing is
  /// pending. Drives the countdown chip in the UI.
  DateTime? _clearsAt;
  DateTime? get clearsAt => _clearsAt;

  bool get hasPendingClear => _pendingClear?.isActive ?? false;

  /// Copies a secret and schedules the wipe.
  Future<void> copySecret(String value) async {
    await SecureScreen.copySensitive(
      value,
      expiresAfter: clearAfter > Duration.zero ? clearAfter : null,
    );
    _lastCopied = value;
    _schedule(value);
  }

  /// Copies something that is not secret — a username, a URL — without the
  /// wipe timer, since silently emptying the clipboard there is just confusing.
  Future<void> copyPlain(String value) async {
    await SecureScreen.copySensitive(value);
    _cancel();
  }

  void _schedule(String value) {
    _cancel();
    if (clearAfter <= Duration.zero) return;
    _clearsAt = DateTime.now().add(clearAfter);
    _pendingClear = Timer(clearAfter, () async {
      await SecureScreen.clearIfStillOurs(value);
      _clearsAt = null;
      _lastCopied = null;
    });
  }

  void _cancel() {
    _pendingClear?.cancel();
    _pendingClear = null;
    _clearsAt = null;
  }

  /// Wipes immediately. Called when the vault locks — a password sitting in the
  /// clipboard after lock would make the lock meaningless.
  Future<void> clearNow() async {
    final value = _lastCopied;
    _cancel();
    if (value != null) {
      await SecureScreen.clearIfStillOurs(value);
      _lastCopied = null;
    }
  }

  void dispose() => _cancel();
}
