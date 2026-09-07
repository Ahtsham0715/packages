import 'package:flutter_test/flutter_test.dart';
import 'package:sablekey/core/crypto/totp.dart';

void main() {
  // The RFC 6238 appendix B vectors. The seeds are the ASCII strings
  // "12345678901234567890" (repeated to length for SHA-256 and SHA-512),
  // base32-encoded.
  const sha1Secret = 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ';
  const sha256Secret =
      'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZA';
  const sha512Secret = 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ'
      'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNA';

  Future<String> codeAt(
    int unixSeconds, {
    String secret = sha1Secret,
    OtpAlgorithm algorithm = OtpAlgorithm.sha1,
  }) async {
    final config = TotpConfig(
      secret: secret,
      algorithm: algorithm,
      digits: 8,
    );
    final result = await Totp.generate(
      config,
      now: DateTime.fromMillisecondsSinceEpoch(unixSeconds * 1000,
          isUtc: true),
    );
    return result.value;
  }

  group('RFC 6238 test vectors', () {
    test('SHA-1', () async {
      expect(await codeAt(59), '94287082');
      expect(await codeAt(1111111109), '07081804');
      expect(await codeAt(1111111111), '14050471');
      expect(await codeAt(1234567890), '89005924');
      expect(await codeAt(2000000000), '69279037');
      // Past the 32-bit epoch rollover, which is where a counter written as an
      // int32 quietly starts producing wrong codes.
      expect(await codeAt(20000000000), '65353130');
    });

    test('SHA-256', () async {
      expect(
        await codeAt(59,
            secret: sha256Secret, algorithm: OtpAlgorithm.sha256),
        '46119246',
      );
    });

    test('SHA-512', () async {
      expect(
        await codeAt(59,
            secret: sha512Secret, algorithm: OtpAlgorithm.sha512),
        '90693936',
      );
    });
  });

  group('base32', () {
    test('decodes and re-encodes without loss', () {
      final decoded = Totp.decodeBase32(sha1Secret);
      expect(String.fromCharCodes(decoded), '12345678901234567890');
      expect(Totp.encodeBase32(decoded), sha1Secret);
    });

    test('tolerates padding, spaces and lowercase', () {
      final canonical = Totp.decodeBase32('JBSWY3DPEHPK3PXP');
      expect(Totp.decodeBase32('jbsw y3dp ehpk 3pxp'), canonical);
      expect(Totp.decodeBase32('JBSWY3DPEHPK3PXP===='), canonical);
    });

    test('rejects characters outside the alphabet', () {
      expect(() => Totp.decodeBase32('JBSW1809'), throwsA(isA<OtpParseException>()));
    });
  });

  group('otpauth:// parsing', () {
    test('reads a full URI', () {
      final config = TotpConfig.parseUri(
        'otpauth://totp/GitHub:alice%40example.com'
        '?secret=JBSWY3DPEHPK3PXP&issuer=GitHub&algorithm=SHA256'
        '&digits=8&period=60',
      );

      expect(config.secret, 'JBSWY3DPEHPK3PXP');
      expect(config.issuer, 'GitHub');
      expect(config.account, 'alice@example.com');
      expect(config.algorithm, OtpAlgorithm.sha256);
      expect(config.digits, 8);
      expect(config.period, 60);
    });

    test('applies the spec defaults when parameters are absent', () {
      final config =
          TotpConfig.parseUri('otpauth://totp/Example?secret=JBSWY3DPEHPK3PXP');
      expect(config.algorithm, OtpAlgorithm.sha1);
      expect(config.digits, 6);
      expect(config.period, 30);
    });

    test('takes the issuer from the label when the parameter is missing', () {
      final config = TotpConfig.parseUri(
          'otpauth://totp/ACME%20Co:john?secret=JBSWY3DPEHPK3PXP');
      expect(config.issuer, 'ACME Co');
      expect(config.account, 'john');
    });

    test('round-trips through toUri', () {
      const original = TotpConfig(
        secret: 'JBSWY3DPEHPK3PXP',
        algorithm: OtpAlgorithm.sha256,
        digits: 8,
        period: 60,
        issuer: 'GitHub',
        account: 'alice@example.com',
      );
      final reparsed = TotpConfig.parseUri(original.toUri());

      expect(reparsed.secret, original.secret);
      expect(reparsed.algorithm, original.algorithm);
      expect(reparsed.digits, original.digits);
      expect(reparsed.period, original.period);
      expect(reparsed.issuer, original.issuer);
      expect(reparsed.account, original.account);
    });

    test('rejects counter-based (HOTP) codes rather than silently misreading',
        () {
      expect(
        () => TotpConfig.parseUri(
            'otpauth://hotp/Example?secret=JBSWY3DPEHPK3PXP&counter=1'),
        throwsA(isA<OtpParseException>()),
      );
    });

    test('rejects a URI with no secret', () {
      expect(
        () => TotpConfig.parseUri('otpauth://totp/Example?issuer=Example'),
        throwsA(isA<OtpParseException>()),
      );
    });
  });

  group('flexible input', () {
    test('accepts a bare secret as typed off a web page', () {
      final config = Totp.parseFlexible('jbsw y3dp ehpk 3pxp');
      expect(config.secret, 'JBSWY3DPEHPK3PXP');
      expect(config.digits, 6);
    });

    test('accepts a full URI', () {
      final config =
          Totp.parseFlexible('otpauth://totp/Example?secret=JBSWY3DPEHPK3PXP');
      expect(config.secret, 'JBSWY3DPEHPK3PXP');
    });
  });

  group('code metadata', () {
    test('reports the time left in the current window', () async {
      const config = TotpConfig(secret: sha1Secret);
      final code = await Totp.generate(
        config,
        now: DateTime.fromMillisecondsSinceEpoch(1000 * 1000, isUtc: true),
      );
      // 1000 seconds is 10 seconds into a 30-second window.
      expect(code.secondsRemaining, 20);
      expect(code.fractionRemaining, closeTo(20 / 30, 0.001));
      expect(code.isExpiring, isFalse);
    });

    test('flags a code that is about to roll over', () async {
      const config = TotpConfig(secret: sha1Secret);
      final code = await Totp.generate(
        config,
        now: DateTime.fromMillisecondsSinceEpoch(1027 * 1000, isUtc: true),
      );
      expect(code.secondsRemaining, 3);
      expect(code.isExpiring, isTrue);
    });

    test('groups six digits for readability', () async {
      const config = TotpConfig(secret: sha1Secret);
      final code = await Totp.generate(config);
      expect(code.value.length, 6);
      expect(code.formatted, matches(RegExp(r'^\d{3} \d{3}$')));
    });
  });
}
