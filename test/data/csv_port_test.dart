import 'package:flutter_test/flutter_test.dart';
import 'package:sablekey/data/csv_port.dart';
import 'package:sablekey/domain/models/item_type.dart';

void main() {
  group('RFC 4180 parsing', () {
    test('splits plain rows', () {
      expect(
        Csv.parse('a,b,c\n1,2,3'),
        [
          ['a', 'b', 'c'],
          ['1', '2', '3'],
        ],
      );
    });

    test('keeps commas inside quotes', () {
      expect(
        Csv.parse('name,notes\nAcme,"one, two, three"'),
        [
          ['name', 'notes'],
          ['Acme', 'one, two, three'],
        ],
      );
    });

    test('unescapes doubled quotes', () {
      expect(
        Csv.parse('a\n"He said ""hi"""'),
        [
          ['a'],
          ['He said "hi"'],
        ],
      );
    });

    test('keeps newlines inside quotes', () {
      final rows = Csv.parse('name,notes\nAcme,"line one\nline two"');
      expect(rows[1][1], 'line one\nline two');
      expect(rows.length, 2);
    });

    test('handles CRLF', () {
      expect(Csv.parse('a,b\r\n1,2').length, 2);
    });

    test('strips a UTF-8 byte order mark', () {
      // Excel writes one, and without this the first header becomes "﻿name"
      // and never matches a role.
      final rows = Csv.parse('﻿name,password\nAcme,secret');
      expect(rows.first.first, 'name');
    });

    test('ignores a trailing newline', () {
      expect(Csv.parse('a,b\n1,2\n').length, 2);
    });

    test('preserves empty fields', () {
      expect(Csv.parse('a,b,c\n1,,3')[1], ['1', '', '3']);
    });
  });

  group('writing', () {
    test('quotes only what needs it', () {
      expect(Csv.escapeField('plain'), 'plain');
      expect(Csv.escapeField('has,comma'), '"has,comma"');
      expect(Csv.escapeField('has"quote'), '"has""quote"');
      expect(Csv.escapeField('has\nnewline'), '"has\nnewline"');
    });

    test('round-trips through the parser', () {
      final rows = [
        ['name', 'notes'],
        ['Acme', 'one, "two"\nthree'],
      ];
      expect(Csv.parse(Csv.write(rows)), rows);
    });
  });

  group('importing other managers', () {
    test('Bitwarden', () {
      const source =
          'folder,favorite,type,name,notes,fields,reprompt,login_uri,'
          'login_username,login_password,login_totp\n'
          'Work,1,login,GitHub,some notes,,0,https://github.com,octocat,'
          's3cret,JBSWY3DPEHPK3PXP';

      final result = CsvImporter.import(source);
      expect(result.detectedFormat, 'Bitwarden');
      expect(result.items.length, 1);

      final item = result.items.first;
      expect(item.name, 'GitHub');
      expect(item.type, ItemType.login);
      expect(item.fields['username'], 'octocat');
      expect(item.fields['password'], 's3cret');
      expect(item.fields['uri'], 'https://github.com');
      expect(item.notes, 'some notes');
      expect(item.tags, contains('Work'));
      expect(item.favourite, isTrue);
      expect(item.totp?.secret, 'JBSWY3DPEHPK3PXP');
    });

    test('LastPass', () {
      const source = 'url,username,password,totp,extra,name,grouping,fav\n'
          'https://example.com,alice,pw123,,a note,Example,Personal,0';

      final result = CsvImporter.import(source);
      expect(result.detectedFormat, 'LastPass');

      final item = result.items.first;
      expect(item.name, 'Example');
      expect(item.fields['username'], 'alice');
      expect(item.fields['password'], 'pw123');
      expect(item.tags, contains('Personal'));
      expect(item.favourite, isFalse);
    });

    test('Chrome', () {
      const source = 'name,url,username,password,note\n'
          'example.com,https://example.com/login,bob,hunter2,';

      final result = CsvImporter.import(source);
      final item = result.items.first;
      expect(item.fields['username'], 'bob');
      expect(item.fields['password'], 'hunter2');
    });

    test('1Password', () {
      const source = 'Title,Url,Username,Password,OTPAuth,Notes\n'
          'Bank,https://bank.example,carol,pw,'
          'otpauth://totp/Bank?secret=JBSWY3DPEHPK3PXP,';

      final result = CsvImporter.import(source);
      expect(result.detectedFormat, '1Password');
      expect(result.items.first.totp?.secret, 'JBSWY3DPEHPK3PXP');
    });

    test('KeePass, with a nested group becoming tags', () {
      const source = 'Group,Title,Username,Password,URL,Notes\n'
          'Root/Work/Dev,GitLab,dave,pw,https://gitlab.com,';

      final result = CsvImporter.import(source);
      expect(result.items.first.tags, containsAll(['Root', 'Work', 'Dev']));
    });
  });

  group('import edge cases', () {
    test('a row with no credentials becomes a secure note', () {
      const source = 'name,notes,password\nShopping,buy milk,';
      final item = CsvImporter.import(source).items.first;
      expect(item.type, ItemType.secureNote);
      expect(item.fields['body'], 'buy milk');
    });

    test('completely empty rows are skipped, not imported', () {
      const source = 'name,username,password,notes\nA,alice,pw,\n,,,\n';
      final result = CsvImporter.import(source);
      expect(result.items.length, 1);
      expect(result.skippedRows, greaterThanOrEqualTo(1));
    });

    test('one column never fills two roles', () {
      // LastPass has both "name" and "username"; letting "account" claim both
      // produces entries titled with their own username.
      const source = 'name,username,password\nGitHub,octocat,pw';
      final item = CsvImporter.import(source).items.first;
      expect(item.name, 'GitHub');
      expect(item.fields['username'], 'octocat');
    });

    test('takes the first of several URIs in one cell', () {
      const source = 'name,url,username,password\n'
          'Multi,"https://a.example\nhttps://b.example",u,p';
      expect(CsvImporter.import(source).items.first.fields['uri'],
          'https://a.example');
    });

    test('an unreadable TOTP secret warns instead of failing the import', () {
      const source = 'name,username,password,totp\nA,u,p,not-base32!!';
      final result = CsvImporter.import(source);
      expect(result.items.length, 1);
      expect(result.items.first.totp, isNull);
      expect(result.warnings, isNotEmpty);
    });

    test('falls back to the URL when there is no name', () {
      const source = 'url,username,password\nhttps://example.com,u,p';
      expect(CsvImporter.import(source).items.first.name,
          'https://example.com');
    });

    test('rejects a file with no recognisable columns', () {
      expect(
        () => CsvImporter.import('alpha,beta\n1,2'),
        throwsA(isA<CsvException>()),
      );
    });

    test('rejects an empty file', () {
      expect(() => CsvImporter.import(''), throwsA(isA<CsvException>()));
    });
  });

  group('export', () {
    test('writes a header and one row per live item', () {
      const source = 'name,username,password,url\nGitHub,octocat,s3cret,'
          'https://github.com';
      final items = CsvImporter.import(source).items;

      final rows = Csv.parse(CsvExporter.export(items));
      expect(rows.first,
          ['name', 'type', 'username', 'password', 'url', 'totp', 'notes',
           'tags']);
      expect(rows[1][0], 'GitHub');
      expect(rows[1][2], 'octocat');
      expect(rows[1][3], 's3cret');
    });

    test('folds fields with no CSV column into the notes', () {
      // Otherwise a passport number or a card PIN would silently vanish on the
      // way out, which would make the export a data-loss trap.
      const source = 'name,notes,password\nDocs,keep this,';
      final items = CsvImporter.import(source).items;
      final exported = CsvExporter.export(items);
      expect(exported, contains('keep this'));
    });

    test('survives a round trip through the importer', () {
      const source = 'name,username,password,url,notes\n'
          'Acme,alice,"pw,with,commas",https://acme.example,"a\nnote"';
      final original = CsvImporter.import(source).items;
      final reimported = CsvImporter.import(CsvExporter.export(original)).items;

      expect(reimported.first.name, 'Acme');
      expect(reimported.first.fields['password'], 'pw,with,commas');
    });
  });
}
