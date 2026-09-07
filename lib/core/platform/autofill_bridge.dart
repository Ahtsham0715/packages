import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// What the platform autofill service is asking for.
@immutable
class AutofillRequest {
  const AutofillRequest({
    required this.mode,
    this.webDomain,
    this.packageName,
    this.appLabel,
    this.suggestedUsername,
    this.suggestedPassword,
    this.wantsPassword = true,
    this.wantsCard = false,
  });

  factory AutofillRequest.fromMap(Map<Object?, Object?> map) => AutofillRequest(
        mode: map['mode'] == 'save' ? AutofillMode.save : AutofillMode.fill,
        webDomain: map['webDomain'] as String?,
        packageName: map['packageName'] as String?,
        appLabel: map['appLabel'] as String?,
        suggestedUsername: map['username'] as String?,
        suggestedPassword: map['password'] as String?,
        wantsPassword: (map['wantsPassword'] as bool?) ?? true,
        wantsCard: (map['wantsCard'] as bool?) ?? false,
      );

  final AutofillMode mode;

  /// The site the browser is on, when the request came from a web page.
  final String? webDomain;

  /// The Android package, when the request came from a native app.
  final String? packageName;

  /// A human-readable app name, for the picker header.
  final String? appLabel;

  /// Values the user just typed, present on a save request.
  final String? suggestedUsername;
  final String? suggestedPassword;

  final bool wantsPassword;
  final bool wantsCard;

  /// What the credential should be matched against.
  String get target => webDomain ?? packageName ?? '';

  /// What to show the user as "you are filling into…".
  String get displayTarget => webDomain ?? appLabel ?? packageName ?? 'this app';
}

enum AutofillMode { fill, save }

/// Bridge to the platform autofill implementations.
///
/// # Why this is a separate activity rather than a cached credential list
///
/// The obvious way to implement Android autofill is to keep a decrypted index
/// of logins somewhere the background `AutofillService` can read it. That would
/// mean plaintext credentials on disk whenever autofill is enabled, which
/// undoes the entire point of the app.
///
/// Instead the service answers every request with a single locked dataset whose
/// authentication intent launches Sablekey. The user unlocks, picks an entry,
/// and the chosen values are handed straight back to the requesting app. The
/// vault is only ever decrypted inside the app process, for as long as the
/// picker is on screen.
abstract final class AutofillBridge {
  static const MethodChannel _channel = MethodChannel('sablekey/autofill');

  /// Whether Sablekey is the selected autofill provider.
  static Future<bool> isServiceEnabled() async {
    try {
      return await _channel.invokeMethod<bool>('isEnabled') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Opens the OS screen where autofill providers are chosen.
  static Future<void> openSettings() async {
    try {
      await _channel.invokeMethod<void>('openSettings');
    } on PlatformException catch (error) {
      debugPrint('sablekey: could not open autofill settings: '
          '${error.message}');
    } on MissingPluginException {
      // Not supported here.
    }
  }

  /// Whether this launch is serving an autofill request rather than a normal
  /// app start.
  static Future<AutofillRequest?> pendingRequest() async {
    try {
      final map = await _channel.invokeMethod<Map<Object?, Object?>>('getRequest');
      if (map == null) return null;
      return AutofillRequest.fromMap(map);
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// Hands the chosen credential back to the requesting app and closes the
  /// picker.
  static Future<void> respond({
    String? username,
    String? password,
    String? totpCode,
    Map<String, String> cardFields = const {},
  }) async {
    await _channel.invokeMethod<void>('respond', {
      if (username != null) 'username': username,
      if (password != null) 'password': password,
      if (totpCode != null) 'totp': totpCode,
      if (cardFields.isNotEmpty) 'card': cardFields,
    });
  }

  /// Dismisses the autofill picker without filling anything.
  static Future<void> cancel() async {
    try {
      await _channel.invokeMethod<void>('cancel');
    } on MissingPluginException {
      // Nothing to dismiss.
    }
  }

  /// Tells the native side that a save request was handled, so it can finish
  /// its activity.
  static Future<void> finishSave({required bool saved}) async {
    try {
      await _channel.invokeMethod<void>('finishSave', {'saved': saved});
    } on MissingPluginException {
      // Nothing to finish.
    }
  }
}
