import 'dart:async';

import 'package:flutter/widgets.dart';

/// Locks the vault after inactivity, and when the app leaves the foreground.
///
/// Two separate triggers, because they guard different things. The idle timer
/// covers a phone left unlocked on a desk. The lifecycle trigger covers the
/// screenshot the OS takes for the app switcher and the case where the user
/// hands the phone over with the vault still open — that one fires the moment
/// the app is no longer frontmost, not after a delay.
class AutoLockService with WidgetsBindingObserver {
  AutoLockService({required this.onLock});

  /// Invoked when the vault should be locked. Must be safe to call repeatedly.
  final VoidCallback onLock;

  Timer? _idleTimer;
  Duration? _idleTimeout;
  bool _lockOnBackground = true;
  bool _armed = false;

  /// When the app was backgrounded, so a short interruption — a notification
  /// shade pull, a permission dialog — does not necessarily lock.
  DateTime? _backgroundedAt;

  void start() {
    WidgetsBinding.instance.addObserver(this);
  }

  void stop() {
    WidgetsBinding.instance.removeObserver(this);
    _idleTimer?.cancel();
    _idleTimer = null;
    _armed = false;
  }

  /// Applies the user's current settings. Safe to call whenever they change.
  void configure({
    required int autoLockSeconds,
    required bool lockWhenBackgrounded,
  }) {
    _lockOnBackground = lockWhenBackgrounded;
    _idleTimeout =
        autoLockSeconds < 0 ? null : Duration(seconds: autoLockSeconds);
    if (_armed) touch();
  }

  /// Begins watching. Called on unlock.
  void arm() {
    _armed = true;
    touch();
  }

  /// Stops watching. Called on lock, so a stale timer cannot fire into a
  /// locked vault.
  void disarm() {
    _armed = false;
    _idleTimer?.cancel();
    _idleTimer = null;
    _backgroundedAt = null;
  }

  /// Resets the idle countdown. Wired to every user interaction.
  void touch() {
    if (!_armed) return;
    _idleTimer?.cancel();
    final timeout = _idleTimeout;
    if (timeout == null) return;

    // A zero timeout means "lock immediately on leaving", not "lock right now
    // while the user is looking at it".
    if (timeout == Duration.zero) return;

    _idleTimer = Timer(timeout, () {
      if (_armed) onLock();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_armed) return;

    switch (state) {
      case AppLifecycleState.resumed:
        final since = _backgroundedAt;
        _backgroundedAt = null;
        if (since != null && !_lockOnBackground) {
          // Count time spent in the background against the idle budget, so
          // backgrounding the app is not a way to pause the auto-lock clock.
          final away = DateTime.now().difference(since);
          final timeout = _idleTimeout;
          if (timeout != null && away >= timeout) {
            onLock();
            return;
          }
        }
        touch();

      case AppLifecycleState.inactive:
        // Fires for the app switcher and for transient overlays alike, so it is
        // not enough on its own to lock — but it is the right moment to stop
        // the idle timer.
        _idleTimer?.cancel();

      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        _backgroundedAt = DateTime.now();
        if (_lockOnBackground) onLock();
    }
  }
}

/// Wraps a subtree so that any pointer or key activity resets the idle timer.
class ActivityDetector extends StatelessWidget {
  const ActivityDetector({
    required this.onActivity,
    required this.child,
    super.key,
  });

  final VoidCallback onActivity;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Listener(
      // Listener rather than GestureDetector: this must observe events without
      // competing for them, or it would swallow taps meant for the UI beneath.
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => onActivity(),
      onPointerSignal: (_) => onActivity(),
      child: child,
    );
  }
}
