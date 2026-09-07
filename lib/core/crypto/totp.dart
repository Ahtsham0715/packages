import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';

/// Hash algorithms an authenticator may specify.
enum OtpAlgorithm {
  sha1('SHA1'),
  sha256('SHA256'),
  sha512('SHA512');

  const OtpAlgorithm(this.label);
  final String label;

  static OtpAlgorithm parse(String? value) {
    switch (value?.toUpperCase().replaceAll('-', '')) {
      case 'SHA256':
        return OtpAlgorithm.sha256;
      case 'SHA512':
        return OtpAlgorithm.sha512;
      case 'SHA1':
      case null:
      case '':
        return OtpAlgorithm.sha1;
      default:
        throw const OtpParseException('Unsupported OTP hash algorithm');
    }
  }

  MacAlgorithm get _mac => switch (this) {
        OtpAlgorithm.sha1 => Hmac.sha1(),
        OtpAlgorithm.sha256 => Hmac.sha256(),
        OtpAlgorithm.sha512 => Hmac.sha512(),
      };
}

class OtpParseException implements Exception {
  const OtpParseException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// A one-time-password configuration, as carried by an `otpauth://` URI.
///
/// Sablekey generates these on-device; the shared secret is stored inside the
/// item's encrypted blob like any other field, so a vault with TOTP secrets is
/// no less protected than one without. Storing the second factor next to the
/// first is a real trade-off — it is documented in SECURITY.md — but it is what
/// every mainstream manager does, and the alternative most people choose is a
/// screenshot of the QR code in their camera roll.
@immutable
class TotpConfig {
  const TotpConfig({
    required this.secret,
    this.algorithm = OtpAlgorithm.sha1,
    this.digits = 6,
    this.period = 30,
    this.issuer,
    this.account,
  });

  /// Parses an `otpauth://totp/...` URI, as produced by every QR code.
  factory TotpConfig.parseUri(String uri) {
    final Uri parsed;
    try {
      parsed = Uri.parse(uri.trim());
    } on FormatException {
      throw const OtpParseException('Not a valid otpauth:// URI');
    }
    if (parsed.scheme.toLowerCase() != 'otpauth') {
      throw const OtpParseException('Not an otpauth:// URI');
    }
    if (parsed.host.toLowerCase() != 'totp') {
      throw const OtpParseException('Only time-based (TOTP) codes are supported');
    }

    final params = parsed.queryParameters;
    final secret = params['secret'];
    if (secret == null || secret.isEmpty) {
      throw const OtpParseException('The QR code carries no secret');
    }

    // Label is "Issuer:account" or just "account"; the issuer query parameter
    // wins when both are present, which is what the spec recommends.
    var label = parsed.path;
    if (label.startsWith('/')) label = label.substring(1);
    label = Uri.decodeComponent(label);
    String? issuer = params['issuer'];
    String? account = label;
    if (label.contains(':')) {
      final split = label.split(':');
      issuer ??= split.first.trim();
      account = split.sublist(1).join(':').trim();
    }

    final digits = int.tryParse(params['digits'] ?? '6') ?? 6;
    final period = int.tryParse(params['period'] ?? '30') ?? 30;
    if (digits < 6 || digits > 10) {
      throw const OtpParseException('Unsupported digit count');
    }
    if (period < 1 || period > 300) {
      throw const OtpParseException('Unsupported refresh period');
    }

    return TotpConfig(
      secret: normalizeSecret(secret),
      algorithm: OtpAlgorithm.parse(params['algorithm']),
      digits: digits,
      period: period,
      issuer: (issuer == null || issuer.isEmpty) ? null : issuer,
      account: (account == null || account.isEmpty) ? null : account,
    );
  }

  factory TotpConfig.fromJson(Map<String, Object?> json) => TotpConfig(
        secret: json['secret']! as String,
        algorithm: OtpAlgorithm.parse(json['alg'] as String?),
        digits: (json['digits'] as int?) ?? 6,
        period: (json['period'] as int?) ?? 30,
        issuer: json['issuer'] as String?,
        account: json['account'] as String?,
      );

  /// Base32, no padding, uppercase.
  final String secret;
  final OtpAlgorithm algorithm;
  final int digits;
  final int period;
  final String? issuer;
  final String? account;

  Map<String, Object?> toJson() => {
        'secret': secret,
        'alg': algorithm.label,
        'digits': digits,
        'period': period,
        if (issuer != null) 'issuer': issuer,
        if (account != null) 'account': account,
      };

  /// Rebuilds the URI, for showing a QR code when moving to another device.
  String toUri() {
    final label = issuer != null && account != null
        ? '${Uri.encodeComponent(issuer!)}:${Uri.encodeComponent(account!)}'
        : Uri.encodeComponent(account ?? issuer ?? 'Sablekey');
    final query = <String, String>{
      'secret': secret,
      'algorithm': algorithm.label,
      'digits': '$digits',
      'period': '$period',
      if (issuer != null) 'issuer': issuer!,
    };
    final encoded =
        query.entries.map((e) => '${e.key}=${Uri.encodeComponent(e.value)}').join('&');
    return 'otpauth://totp/$label?$encoded';
  }

  /// Users paste secrets copied from web pages, complete with spaces and
  /// lowercase letters. Normalise rather than reject.
  static String normalizeSecret(String raw) {
    final cleaned =
        raw.replaceAll(RegExp(r'[\s\-_]'), '').replaceAll('=', '').toUpperCase();
    if (cleaned.isEmpty) {
      throw const OtpParseException('The secret is empty');
    }
    if (!RegExp(r'^[A-Z2-7]+$').hasMatch(cleaned)) {
      throw const OtpParseException(
          'The secret is not valid base32 (only A-Z and 2-7 are allowed)');
    }
    return cleaned;
  }
}

/// A generated code plus the life left in it.
@immutable
class TotpCode {
  const TotpCode({
    required this.value,
    required this.secondsRemaining,
    required this.period,
  });

  final String value;
  final int secondsRemaining;
  final int period;

  /// 1.0 immediately after a refresh, falling to 0.0 as it expires.
  double get fractionRemaining => secondsRemaining / period;

  /// Codes about to roll over often fail on slow servers; the UI nudges the
  /// user to wait for the next one.
  bool get isExpiring => secondsRemaining <= 5;

  /// Grouped as `123 456`, which is markedly easier to type off a screen.
  String get formatted {
    if (value.length == 6) return '${value.substring(0, 3)} ${value.substring(3)}';
    if (value.length == 8) return '${value.substring(0, 4)} ${value.substring(4)}';
    return value;
  }
}

/// RFC 6238 time-based one-time passwords, on top of RFC 4226 HOTP.
abstract final class Totp {
  static Future<TotpCode> generate(TotpConfig config, {DateTime? now}) async {
    final at = now ?? DateTime.now();
    final unixSeconds = at.millisecondsSinceEpoch ~/ 1000;
    final counter = unixSeconds ~/ config.period;
    final value = await _hotp(
      secret: decodeBase32(config.secret),
      counter: counter,
      digits: config.digits,
      algorithm: config.algorithm,
    );
    return TotpCode(
      value: value,
      secondsRemaining: config.period - (unixSeconds % config.period),
      period: config.period,
    );
  }

  static Future<String> _hotp({
    required Uint8List secret,
    required int counter,
    required int digits,
    required OtpAlgorithm algorithm,
  }) async {
    // Counter as a big-endian 64-bit value.
    final message = Uint8List(8);
    var remaining = counter;
    for (var i = 7; i >= 0; i--) {
      message[i] = remaining & 0xFF;
      remaining >>= 8;
    }

    final mac = await algorithm._mac
        .calculateMac(message, secretKey: SecretKey(secret));
    final digest = mac.bytes;

    // Dynamic truncation (RFC 4226 §5.4).
    final offset = digest[digest.length - 1] & 0x0F;
    final binary = ((digest[offset] & 0x7F) << 24) |
        ((digest[offset + 1] & 0xFF) << 16) |
        ((digest[offset + 2] & 0xFF) << 8) |
        (digest[offset + 3] & 0xFF);

    final modulus = _pow10(digits);
    return (binary % modulus).toString().padLeft(digits, '0');
  }

  static int _pow10(int exponent) {
    var result = 1;
    for (var i = 0; i < exponent; i++) {
      result *= 10;
    }
    return result;
  }

  /// RFC 4648 base32 decode, padding optional.
  static Uint8List decodeBase32(String input) {
    const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
    final cleaned = input.replaceAll('=', '').replaceAll(' ', '').toUpperCase();

    final out = <int>[];
    var buffer = 0;
    var bitsInBuffer = 0;
    for (final char in cleaned.codeUnits) {
      final index = alphabet.indexOf(String.fromCharCode(char));
      if (index < 0) {
        throw const OtpParseException('The secret is not valid base32');
      }
      buffer = (buffer << 5) | index;
      bitsInBuffer += 5;
      if (bitsInBuffer >= 8) {
        bitsInBuffer -= 8;
        out.add((buffer >> bitsInBuffer) & 0xFF);
      }
    }
    if (out.isEmpty) {
      throw const OtpParseException('The secret is too short');
    }
    return Uint8List.fromList(out);
  }

  /// Base32 encode, used when exporting a secret back to a URI.
  static String encodeBase32(Uint8List input) {
    const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
    final out = StringBuffer();
    var buffer = 0;
    var bitsInBuffer = 0;
    for (final byte in input) {
      buffer = (buffer << 8) | byte;
      bitsInBuffer += 8;
      while (bitsInBuffer >= 5) {
        bitsInBuffer -= 5;
        out.write(alphabet[(buffer >> bitsInBuffer) & 0x1F]);
      }
    }
    if (bitsInBuffer > 0) {
      out.write(alphabet[(buffer << (5 - bitsInBuffer)) & 0x1F]);
    }
    return out.toString();
  }

  /// Accepts either a full `otpauth://` URI or a bare base32 secret, which is
  /// what users actually have in their clipboard.
  static TotpConfig parseFlexible(String input) {
    final trimmed = input.trim();
    if (trimmed.toLowerCase().startsWith('otpauth://')) {
      return TotpConfig.parseUri(trimmed);
    }
    return TotpConfig(secret: TotpConfig.normalizeSecret(trimmed));
  }
}

/// Keyed hashes over field values, used to answer "is this password reused?"
/// without keeping any plaintext around to compare.
///
/// The key comes from the vault's data key, so the index is meaningless to
/// anyone who only has the database file — unlike a plain SHA-256 of the
/// password, which would be trivially checkable against a rainbow table.
abstract final class BlindIndex {
  static Future<Uint8List> compute({
    required Uint8List key,
    required String value,
  }) async {
    final mac = await Hmac.sha256()
        .calculateMac(utf8.encode(value), secretKey: SecretKey(key));
    // 16 bytes is ample for equality bucketing and halves the storage.
    return Uint8List.fromList(mac.bytes.sublist(0, 16));
  }
}
