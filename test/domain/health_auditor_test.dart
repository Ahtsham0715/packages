import 'package:flutter_test/flutter_test.dart';
import 'package:sablekey/core/crypto/totp.dart';
import 'package:sablekey/domain/models/item_type.dart';
import 'package:sablekey/domain/models/vault_item.dart';
import 'package:sablekey/domain/services/health_auditor.dart';
import 'package:sablekey/domain/services/password_strength.dart';

void main() {
  final estimator = PasswordStrengthEstimator(
    commonPasswords: const {'password', 'letmein', '123456'},
    dictionaryWords: const {'correct', 'horse', 'battery', 'staple', 'summer'},
  );
  final auditor = HealthAuditor(estimator: estimator);
  final now = DateTime(2026, 6, 1);

  VaultItem login({
    required String id,
    required String name,
    String? password,
    String? uri,
    TotpConfig? totp,
    DateTime? passwordUpdatedAt,
    bool deleted = false,
  }) =>
      VaultItem(
        id: id,
        type: ItemType.login,
        name: name,
        fields: {
          'username': 'user',
          if (password != null) 'password': password,
          if (uri != null) 'uri': uri,
        },
        totp: totp,
        createdAt: DateTime(2026, 5, 1),
        updatedAt: DateTime(2026, 5, 1),
        passwordUpdatedAt: passwordUpdatedAt ?? DateTime(2026, 5, 1),
        deletedAt: deleted ? now : null,
      );

  Set<HealthIssue> issuesFor(List<VaultItem> items, String id) {
    final report = auditor.audit(items, now: now);
    return report.results.firstWhere((r) => r.item.id == id).issues;
  }

  group('weak and common passwords', () {
    test('flags a password from the common list', () {
      final items = [login(id: '1', name: 'A', password: 'password')];
      expect(issuesFor(items, '1'), contains(HealthIssue.compromised));
    });

    test('flags a short password as weak', () {
      final items = [login(id: '1', name: 'A', password: 'abc12')];
      expect(issuesFor(items, '1'), contains(HealthIssue.weak));
    });

    test('does not flag a long random password', () {
      final items = [
        login(id: '1', name: 'A', password: r'7Kq!vZ2mT#pL9wXb$Rn4'),
      ];
      final issues = issuesFor(items, '1');
      expect(issues, isNot(contains(HealthIssue.weak)));
      expect(issues, isNot(contains(HealthIssue.compromised)));
    });

    test('flags a missing password separately from a weak one', () {
      final items = [login(id: '1', name: 'A')];
      final issues = issuesFor(items, '1');
      expect(issues, contains(HealthIssue.emptyPassword));
      expect(issues, isNot(contains(HealthIssue.weak)));
    });
  });

  group('reuse', () {
    test('flags both entries sharing a password', () {
      final items = [
        login(id: '1', name: 'A', password: r'8Jd!mQ4xW#zR7vNc$Kt2'),
        login(id: '2', name: 'B', password: r'8Jd!mQ4xW#zR7vNc$Kt2'),
        login(id: '3', name: 'C', password: r'3Hf@nP6yE#uT1sVb%Lj9'),
      ];

      expect(issuesFor(items, '1'), contains(HealthIssue.reused));
      expect(issuesFor(items, '2'), contains(HealthIssue.reused));
      expect(issuesFor(items, '3'), isNot(contains(HealthIssue.reused)));
    });

    test('reports how many entries share it', () {
      final items = [
        for (var i = 0; i < 3; i++)
          login(id: '$i', name: 'Item $i', password: r'8Jd!mQ4xW#zR7vNc$Kt2'),
      ];
      final report = auditor.audit(items, now: now);
      expect(report.results.first.reuseCount, 3);
    });

    test('ignores deleted entries when counting reuse', () {
      // A password only used by a trashed entry is not "reused".
      final items = [
        login(id: '1', name: 'Live', password: r'8Jd!mQ4xW#zR7vNc$Kt2'),
        login(
          id: '2',
          name: 'Binned',
          password: r'8Jd!mQ4xW#zR7vNc$Kt2',
          deleted: true,
        ),
      ];
      expect(issuesFor(items, '1'), isNot(contains(HealthIssue.reused)));
    });
  });

  group('staleness', () {
    test('flags a password older than a year', () {
      final items = [
        login(
          id: '1',
          name: 'A',
          password: r'9Wx!kR3nY#qF5tHm$Ub7',
          passwordUpdatedAt: DateTime(2024, 1, 1),
        ),
      ];
      expect(issuesFor(items, '1'), contains(HealthIssue.stale));
    });

    test('does not flag a recent one', () {
      final items = [
        login(
          id: '1',
          name: 'A',
          password: r'9Wx!kR3nY#qF5tHm$Ub7',
          passwordUpdatedAt: DateTime(2026, 5, 20),
        ),
      ];
      expect(issuesFor(items, '1'), isNot(contains(HealthIssue.stale)));
    });
  });

  group('other checks', () {
    test('flags an http:// address', () {
      final items = [
        login(
          id: '1',
          name: 'A',
          password: r'9Wx!kR3nY#qF5tHm$Ub7',
          uri: 'http://insecure.example',
        ),
      ];
      expect(issuesFor(items, '1'), contains(HealthIssue.insecureUri));
    });

    test('does not flag https://', () {
      final items = [
        login(
          id: '1',
          name: 'A',
          password: r'9Wx!kR3nY#qF5tHm$Ub7',
          uri: 'https://secure.example',
        ),
      ];
      expect(issuesFor(items, '1'), isNot(contains(HealthIssue.insecureUri)));
    });

    test('notes a login with no second factor', () {
      final items = [
        login(id: '1', name: 'A', password: r'9Wx!kR3nY#qF5tHm$Ub7'),
      ];
      expect(issuesFor(items, '1'), contains(HealthIssue.missingTotp));
    });

    test('does not note one that has a second factor', () {
      final items = [
        login(
          id: '1',
          name: 'A',
          password: r'9Wx!kR3nY#qF5tHm$Ub7',
          totp: const TotpConfig(secret: 'JBSWY3DPEHPK3PXP'),
        ),
      ];
      expect(issuesFor(items, '1'), isNot(contains(HealthIssue.missingTotp)));
    });
  });

  group('expiry', () {
    VaultItem card(String expiry) => VaultItem(
          id: 'c',
          type: ItemType.card,
          name: 'Card',
          fields: {'number': '4111111111111111', 'expiry': expiry},
          createdAt: now,
          updatedAt: now,
        );

    test('flags an expired card', () {
      expect(issuesFor([card('01/25')], 'c'), contains(HealthIssue.expired));
    });

    test('flags one expiring soon', () {
      expect(issuesFor([card('06/26')], 'c'), contains(HealthIssue.expiring));
    });

    test('leaves a distant expiry alone', () {
      final issues = issuesFor([card('12/30')], 'c');
      expect(issues, isNot(contains(HealthIssue.expired)));
      expect(issues, isNot(contains(HealthIssue.expiring)));
    });

    group('date parsing', () {
      test('MM/YY runs to the end of the month', () {
        expect(HealthAuditor.parseExpiry('03/27'), DateTime(2027, 3, 31));
      });

      test('MM/YYYY', () {
        expect(HealthAuditor.parseExpiry('03/2027'), DateTime(2027, 3, 31));
      });

      test('ISO year-month and full date', () {
        expect(HealthAuditor.parseExpiry('2027-03'), DateTime(2027, 3, 31));
        expect(HealthAuditor.parseExpiry('2027-03-15'), DateTime(2027, 3, 15));
      });

      test('DD/MM/YYYY', () {
        expect(HealthAuditor.parseExpiry('15/03/2027'), DateTime(2027, 3, 15));
      });

      test('February in a leap year', () {
        expect(HealthAuditor.parseExpiry('02/28'), DateTime(2028, 2, 29));
        expect(HealthAuditor.parseExpiry('02/27'), DateTime(2027, 2, 28));
      });

      test('December rolls into the next year correctly', () {
        expect(HealthAuditor.parseExpiry('12/26'), DateTime(2026, 12, 31));
      });

      test('returns null for nonsense rather than guessing', () {
        expect(HealthAuditor.parseExpiry('not a date'), isNull);
        expect(HealthAuditor.parseExpiry('13/27'), isNull);
        expect(HealthAuditor.parseExpiry(''), isNull);
      });
    });
  });

  group('scoring', () {
    test('an empty vault scores 100', () {
      final report = auditor.audit(const [], now: now);
      expect(report.score, 100);
      expect(report.auditedCount, 0);
    });

    test('a healthy vault scores highly', () {
      final items = [
        for (var i = 0; i < 5; i++)
          login(
            id: '$i',
            name: 'Item $i',
            password: 'Zq${i}7!vX2mT#pL9wXbRn4',
            uri: 'https://example$i.com',
            totp: const TotpConfig(secret: 'JBSWY3DPEHPK3PXP'),
            passwordUpdatedAt: DateTime(2026, 5, 20),
          ),
      ];
      expect(auditor.audit(items, now: now).score, greaterThanOrEqualTo(90));
    });

    test('a vault of reused common passwords scores badly', () {
      final items = [
        for (var i = 0; i < 5; i++)
          login(id: '$i', name: 'Item $i', password: 'password'),
      ];
      expect(auditor.audit(items, now: now).score, lessThan(30));
    });

    test('the score does not drift as a healthy vault grows', () {
      List<VaultItem> healthy(int count) => [
            for (var i = 0; i < count; i++)
              login(
                id: '$i',
                name: 'Item $i',
                password: 'Zq${i}7!vX2mT#pL9wXbRn4',
                uri: 'https://example$i.com',
                totp: const TotpConfig(secret: 'JBSWY3DPEHPK3PXP'),
                passwordUpdatedAt: DateTime(2026, 5, 20),
              ),
          ];

      // Scaling by vault size is what stops a 300-item vault from being
      // permanently marked unhealthy by three old entries.
      expect(
        auditor.audit(healthy(3), now: now).score,
        auditor.audit(healthy(60), now: now).score,
      );
    });

    test('reports counts and ids per issue', () {
      final items = [
        login(id: '1', name: 'A', password: 'password'),
        login(id: '2', name: 'B', password: r'9Wx!kR3nY#qF5tHm$Ub7'),
      ];
      final report = auditor.audit(items, now: now);

      expect(report.countOf(HealthIssue.compromised), 1);
      expect(report.idsWith(HealthIssue.compromised), {'1'});
      expect(report.problems.first.item.id, '1');
    });
  });
}
